-- @description SBP Loudness Curve WebView
-- @version 0.1.5
-- @author Bodzijun
-- @changelog
--   0.1.5 Report loading: error now shows the path and OS reason; default report path is only prefilled if the file exists.
-- @provides
--   [nomain] audition.lua
--   [nomain] cache.lua
--   [nomain] export.lua
--   [nomain] file_input.lua
--   [nomain] measurement.lua
--   [nomain] platform.lua
--   [nomain] preview.lua
--   [nomain] profile.lua
--   [nomain] report.lua
--   [nomain] timeline.lua
--   [nomain] measure_audio.py
--   [nomain] preview_server.py
--   [nomain] web/*.{html,js,css}
-- Run as a separate REAPER action. Requires zaibuyidao ReaWebAPI Lua bridge.
local r = reaper
local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")
local file_input = dofile(directory .. "file_input.lua")
local platform = dofile(directory .. "platform.lua")
local report_reader = dofile(directory .. "report.lua")
local timeline = dofile(directory .. "timeline.lua")
local waveform = timeline.waveform(r)
local exporter = dofile(directory .. "export.lua")
local preview = dofile(directory .. "preview.lua").new(r, directory)
local audition = dofile(directory .. "audition.lua")
local measurement
local profile_reader = dofile(directory .. "profile.lua")

for _, name in ipairs({"ReaWeb_Open", "ReaWeb_Close", "ReaWeb_IsOpen", "ReaWeb_IsReady",
                        "ReaWeb_Send", "ReaWeb_Receive"}) do
  if not r.APIExists(name) then
    r.MB("Install ReaWebAPI with the Lua message bridge, then restart REAPER.",
      "SBP Loudness Curve", 0)
    return
  end
end

local key = debug.getinfo(1, "S").source
local window = r.ReaWeb_Open(directory .. "web/index.html", key)
if window == 0 then
  r.MB(r.APIExists("ReaWeb_GetLastError") and r.ReaWeb_GetLastError() or "Cannot open WebView",
    "SBP Loudness Curve", 0)
  return
end
local section = "SBP.LoudnessCurve.WebView"
if tonumber(r.GetExtState(section, key)) == window then return end
r.SetExtState(section, key, tostring(window), false)
r.atexit(function()
  waveform.clear()
  if measurement then measurement.close() end
  preview.close()
  r.ReaWeb_Close(window)
  if r.GetExtState(section, key) == tostring(window) then r.DeleteExtState(section, key, false) end
end)

local array_mt = {}
local function array() return setmetatable({}, array_mt) end
local function quote(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    if char == '"' then return '\\"' end
    if char == "\\" then return "\\\\" end
    return string.format("\\u%04x", char:byte())
  end) .. '"'
end
local function encode(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "string" then return quote(value) end
  if kind == "number" then
    assert(value == value and math.abs(value) ~= math.huge, "Nonfinite number")
    return string.format("%.17g", value):gsub(",", ".")
  end
  if kind == "boolean" then return tostring(value) end
  assert(kind == "table", "Plain data only")
  local parts = {}
  if getmetatable(value) == array_mt then
    for _, part in ipairs(value) do parts[#parts + 1] = encode(part) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for name in pairs(value) do keys[#keys + 1] = name end
  table.sort(keys)
  for _, name in ipairs(keys) do parts[#parts + 1] = quote(name) .. ":" .. encode(value[name]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function send(value) return r.ReaWeb_Send(window, encode(value)) end

local opened_project = r.GetTrackGUID(r.GetMasterTrack(0))
local report, report_revision, session = nil, 0, nil
local scenes, scene_revision = nil, 0
local audition_points, audition_revision = nil, 0
local sources, active_source, stem_serial = {}, 'master', 0
local stem_job_path
local audio_job=false
local function active_profile()
  local profile = profile_reader.load(r)
  local source = sources[active_source]
  assert(active_source == 'master' or source and source.target, 'Choose a destination track for this stem')
  profile.destination_guid = source and source.target or nil
  return profile
end
local function preview_profile()
  local profile=profile_reader.load(r)
  local source=sources[active_source]
  profile.destination_guid=source and source.target or (active_source~='master' and '' or nil)
  return profile
end
local function source_correction(correction)
  correction.source_name, correction.source_i = report.name:gsub('|', '_'), report.integrated
  local source = sources[active_source]
  correction.source_key = source and source.identity or nil
  return correction
end
local function source_audio(audio)
  local source=sources[active_source]
  assert(active_source=='master' or platform.same_path(audio,source.audio,r),
    'Stem audio differs from the measured source. Measure the new WAV first.')
  return audio
end
measurement = dofile(directory .. "measurement.lua").new(r, directory, encode)
local function execute(command, value)
  if command=="file-browse" then return file_input.browse(r,value) end
  if command=="file-clipboard" then return file_input.clipboard(r,value) end
  if command=='measure-cancel' then return measurement.cancel() end
  if command == "ready" then
    local profile = profile_reader.load(r)
    local temp = platform.temp() or ""
    local stats = temp ~= "" and (temp .. "/render_stats.html") or ""
    local probe = stats ~= "" and io.open(stats, "rb")
    if probe then probe:close() else temp = "" end
    local suggested = temp ~= "" and ("file://" .. (platform.windows(r) and "/" or "") .. temp:gsub("\\", "/") .. "/render_stats.html") or ""
    local cache_path,project_cache=dofile(directory..'cache.lua').directory(r)
    return {printmaster = profile.bus_printmaster, suggested_report = suggested, location_track = profile.location,cache_path=cache_path,project_cache=project_cache}
  end
  if command == "load" then
    local loaded, err = report_reader.load(value)
    assert(loaded, err)
    waveform.clear()
    preview.clear()
    report = loaded
    sources.master = {report = loaded};active_source = 'master'
    audition_points=nil
    report_revision = report_revision + 1
    scenes = nil; scene_revision = scene_revision + 1
    local histogram = array(); for _, bin in ipairs(report.histogram) do histogram[#histogram+1] = bin end
    return {name = report.name, length = report.length, integrated = report.integrated, metadata = report.metadata, histogram = histogram,
      count = #report.points, revision = report_revision}
  end
  if command == 'track-list' or command == 'source-select' or command == 'source-target' then
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, 'The active project changed. Reopen this tool.')
    if command == 'track-list' then
      local tracks = array()
      for index = 0, r.CountTracks(0)-1 do
        local track=r.GetTrack(0,index);local _,name=r.GetTrackName(track)
        tracks[#tracks+1]={guid=r.GetTrackGUID(track),name=name,index=index+1}
      end
      return {tracks=tracks}
    elseif command == 'source-target' then
      assert(not measurement.busy(), 'Wait for the current audio scan or cancel it first')
      assert(sources[active_source], 'Load or measure the source first')
      if value ~= '' then
        local found=false
        for index=0,r.CountTracks(0)-1 do if r.GetTrackGUID(r.GetTrack(0,index))==value then found=true;break end end
        assert(found,'The destination track no longer exists')
      end
      assert(active_source=='master' or value~='', 'Choose an explicit destination track for a stem')
      sources[active_source].target=value~='' and value or nil
      audition_points=nil;return {selected=true}
    end
    assert(not measurement.busy(), 'Wait for the current audio scan or cancel it first')
    local source=assert(sources[value], 'Stem measurement is unavailable. Measure the WAV again.')
    waveform.clear();preview.clear();audition_points=nil
    active_source=value;report=source.report;report_revision=report_revision+1
    scenes=nil;scene_revision=scene_revision+1
    return {revision=report_revision,target=source.target or ''}
  end
  if command == 'audio-load' then
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, 'The active project changed. Reopen this tool.')
    local started=measurement.begin({mode='audio',audio=value,length=21600})
    stem_job_path=value;audio_job=true;return started
  end
  if command == 'stem-measure' then
    assert(report, 'Load a render report first')
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, 'The active project changed. Reopen this tool.')
    local revision, audio = value:match('^(%d+)~(.+)$')
    assert(tonumber(revision) == report_revision, 'The render report changed')
    local started=measurement.begin({mode = 'stem', audio = audio, length = 21600})
    stem_job_path=audio;audio_job=false;return started
  end
  if command == 'scene-list-source' or command == 'scene-measure-source' then
    assert(r.GetTrackGUID(r.GetMasterTrack(0))==opened_project,'The active project changed. Reopen this tool.')
    local id,rest=value:match('^([^~]+)~(.+)$');local source=assert(sources[id],'Measure or load this source first')
    if command=='scene-list-source' then
      local window_start,window_end=rest:match('~window:([%d%.]+):([%d%.]+)$')
      if window_start then rest=rest:gsub('~window:[%d%.]+:[%d%.]+$','') end
      local offset,kind,naming,track_name=rest:match('^([%d%.]+)~(%a+)~(%a+)~(.*)$')
      assert(offset,'Invalid scene source request')
      local loaded=timeline.scenes(r,tonumber(offset),source.report.length,kind,track_name,naming,tonumber(window_start),tonumber(window_end))
      assert(#loaded<=2000,'More than 2000 scenes. Select a smaller scene time window.')
      scenes=array();for _,scene in ipairs(loaded) do scenes[#scenes+1]=scene end
      scene_revision=scene_revision+1;return {scenes=scenes,revision=scene_revision}
    end
    local revision,payload,audio=rest:match('^(%d+)~([^~]+)~(.+)$')
    assert(tonumber(revision)==scene_revision and scenes and #scenes>0,'Refresh scenes before measurement')
    local correction,err=exporter.parse(payload);assert(correction,err)
    assert(math.abs(correction.length-source.report.length)<.02,'Correction duration differs from this source')
    correction.source_name,correction.source_i,correction.source_key=source.report.name:gsub('|','_'),source.report.integrated,source.identity
    local points=array();local unity=true;for _,p in ipairs(correction.points) do if p.gain~=0 then unity=false end end
    if unity then points[1]={time=0,linear=1};points[2]={time=correction.length,linear=1}
    else
      local profile=profile_reader.load(r);profile.destination_guid=source.target or (id~='master' and '' or nil)
      for _,p in ipairs(exporter.project_file(r,profile,correction)) do points[#points+1]=p end
    end
    assert(not source.audio or platform.same_path(audio,source.audio,r),'Audio differs from this source')
    return measurement.begin({mode='scenes',audio=audio,expected_identity=source.file_identity,length=source.report.length,source_i=source.report.integrated,points=points,scenes=scenes})
  end
  if command == 'scene-list' or command == 'scene-measure' then
    assert(report, 'Load a render report first')
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, 'The active project changed. Reopen this tool.')
    if command == 'scene-list' then
      local window_start,window_end=value:match('~window:([%d%.]+):([%d%.]+)$')
      if window_start then value=value:gsub('~window:[%d%.]+:[%d%.]+$','') end
      local offset, source, naming, track_name = value:match('^([%d%.]+)~(%a+)~(%a+)~(.*)$')
      assert(offset, 'Invalid scene source request')
      local loaded = timeline.scenes(r, tonumber(offset), report.length, source, track_name, naming,tonumber(window_start),tonumber(window_end))
      assert(#loaded <= 2000, 'More than 2000 scenes. Select a smaller scene time window.')
      local list = array(); for _, scene in ipairs(loaded) do list[#list + 1] = scene end
      scenes = list; scene_revision = scene_revision + 1
      return {scenes = list, revision = scene_revision}
    end
    local revision, scene_id, payload, audio = value:match('^(%d+)~(%d+)~([^~]+)~(.+)$')
    assert(tonumber(revision) == report_revision and tonumber(scene_id) == scene_revision and scenes, 'Scenes or report changed. Refresh scenes first.')
    assert(#scenes > 0, 'No scenes in this render range')
    local correction, err = exporter.parse(payload); assert(correction, err)
    assert(math.abs(correction.length - report.length) < .02, 'Correction duration differs from the report')
    source_correction(correction)
    local points = array(); for _, point in ipairs(exporter.project_file(r, preview_profile(), correction)) do points[#points + 1] = point end
    return measurement.begin({mode = 'scenes', audio = source_audio(audio), expected_identity=sources[active_source].file_identity, length = report.length, source_i = report.integrated, points = points, scenes = scenes})
  end
  if command:match('^preview%-') or command:match('^transport%-') then
    assert(report, 'Load a render report first')
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, 'The active project changed. Reopen this tool.')
    if command == 'preview-gain-start' then
      local revision,payload=value:match('^(%d+)~(.+)$')
      assert(tonumber(revision)==report_revision,'The render report changed')
      local correction,err=exporter.parse(payload);assert(correction,err)
      assert(math.abs(correction.length-report.length)<.02,'Correction duration differs from the report')
      source_correction(correction)
      audition_points=audition.compact(exporter.project_file(r,preview_profile(),correction))
      audition_revision=audition_revision+1
      return {revision=audition_revision,count=#audition_points,length=report.length}
    elseif command == 'preview-gain-chunk' then
      local revision,offset=value:match('^(%d+)~(%d+)$');offset=tonumber(offset)
      assert(audition_points and tonumber(revision)==audition_revision and offset and offset<#audition_points,'Preview curve changed; reload it')
      local points=array();for i=offset+1,math.min(offset+256,#audition_points) do points[#points+1]=audition_points[i] end
      return {points=points}
    elseif command == 'preview-load' then return preview.file_begin(value)
    elseif command == 'preview-stream' then return preview.stream_begin(value)
    elseif command == 'preview-stream-poll' then return preview.stream_poll()
    elseif command == 'preview-stream-clear' then preview.stream_clear(); return {cleared=true}
    elseif command == 'preview-chunk' then return preview.file_chunk()
    elseif command == 'preview-clear' then preview.clear(); return {cleared = true}
    else return preview.transport(command:match('^transport%-(.+)$'), value) end
  end
  if command == "measure-start" or command == "measure-poll" then
    assert(report or command=='measure-poll' and audio_job, "Load the original render report first")
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, "The active project changed. Reopen this tool.")
    if command == "measure-poll" then
      local result=measurement.poll()
      if not result.running and result.stem_json then
        assert(stem_job_path and result.stem_path == stem_job_path, 'Stem measurement source changed')
        stem_serial=stem_serial+1;local id=audio_job and 'master' or 'stem-'..stem_serial
        sources[id]={report={name=stem_job_path:match('[^/\\]+$'),length=assert(result.stem_length),integrated=result.stem_i},
          audio=stem_job_path,file_identity=result.stem_identity,identity=(result.stem_identity..':'..stem_job_path):gsub('|','_')}
        if audio_job then
          waveform.clear();preview.clear();audition_points=nil;report=sources.master.report;active_source='master';report_revision=report_revision+1
          scenes=nil;scene_revision=scene_revision+1;result.revision=report_revision
        end
        result.source_id=id;stem_job_path=nil;audio_job=false
      elseif not result.running then stem_job_path=nil;audio_job=false end
      return result
    end
    local revision, payload, audio = value:match("^(%d+)~([^~]+)~(.+)$")
    assert(tonumber(revision) == report_revision, "The render report changed. Recalculate first.")
    local correction, err = exporter.parse(payload)
    assert(correction, err)
    assert(math.abs(correction.length - report.length) < .02, "Correction duration differs from the report")
    source_correction(correction)
    local points = array()
    for _, point in ipairs(exporter.project_file(r, preview_profile(), correction)) do points[#points + 1] = point end
    return measurement.begin({audio = source_audio(audio), expected_identity=sources[active_source].file_identity, length = report.length, points = points})
  end
  if command == "editor-scenes" then
    assert(report,'Load a source first')
    assert(r.GetTrackGUID(r.GetMasterTrack(0))==opened_project,'The active project changed. Reopen this tool.')
    local offset,source,naming,track_name=value:match('^([%d%.]+)~(%a+)~(%a+)~(.*)$')
    assert(offset,'Invalid editor scene request')
    local list=timeline.scenes(r,tonumber(offset),report.length,source,track_name,naming,nil,nil,10000)
    local data=array();for _,scene in ipairs(list) do data[#data+1]=scene end
    return {scenes=data}
  end
  if command == "regions" or command:match("^waveform%-") then
    assert(report, "Load a render report first")
    assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project, "The active project changed. Reopen this tool.")
    if command == "regions" then
      local list = timeline.regions(r, assert(tonumber(value), "Invalid render start"), report.length)
      local data = array(); for _, item in ipairs(list) do data[#data + 1] = item end
      return {regions = data}
    elseif command == "waveform-load" then return waveform.begin(value)
    elseif command == "waveform-poll" then return waveform.poll()
    elseif command == "waveform-chunk" then
      local chunk = waveform.chunk(tonumber(value))
      local data = array(); for _, item in ipairs(chunk.points) do data[#data + 1] = item end
      chunk.points = data; return chunk
    elseif command=='waveform-detail' then
      local start,finish,count=value:match('^([%d%.]+)~([%d%.]+)~(%d+)$')
      return waveform.detail(tonumber(start),tonumber(finish),tonumber(count))
    elseif command=='waveform-detail-chunk' then
      local revision,offset=value:match('^(%d+)~(%d+)$')
      local chunk=waveform.detail_chunk(tonumber(revision),tonumber(offset))
      local data=array();for _,point in ipairs(chunk.points) do data[#data+1]=point end;chunk.points=data;return chunk
    elseif command == "waveform-clear" then waveform.clear(); return {cleared = true}
    end
  end
  assert(command == "export", "Unknown WebView command")
  assert(report, "Load a render report before exporting")
  assert(r.GetTrackGUID(r.GetMasterTrack(0)) == opened_project,
    "The active project changed. Reopen the WebView for this project.")
  local revision, payload = value:match("^(%d+)~(.+)$")
  local replace = payload and payload:match('^replace~') ~= nil
  if replace then payload = payload:sub(9) end
  assert(tonumber(revision) == report_revision, "The render report changed. Recalculate first.")
  local correction, err = exporter.parse(payload)
  assert(correction, err)
  assert(math.abs(correction.length - report.length) < 0.02, "Correction duration differs from the loaded render")
  source_correction(correction)
  local result, apply_error = exporter.apply(r, 0, active_profile(), correction, replace)
  assert(result, apply_error)
  return result
end

local function handle(message)
  local client, id, command, value = message:match("^([%w%-]+)\t(%d+)\t([%w%-]+)\t(.*)$")
  if not client then return end
  if command == "ready" then session = client elseif client ~= session then return end
  local ok, result = pcall(execute, command, value)
  send({type = "response", session = client, id = tonumber(id), ok = ok,
    data = ok and result or nil, error = not ok and tostring(result) or nil})
  if ok and command == "load" then
    for offset = 1, #report.points, 100 do
      local chunk = array()
      for index = offset, math.min(offset + 99, #report.points) do
        local point = report.points[index]
        chunk[#chunk + 1] = {time = point.time, momentary = point.momentary,
          short_term = point.short_term, peak = point.peak}
      end
      send({type = "points", session = client, revision = report_revision,
        offset = offset - 1, total = #report.points, points = chunk})
    end
  end
end

local function loop()
  if not r.ReaWeb_IsOpen(window) then return end
  local ok, err = pcall(function()
    preview.keepalive()
    for _ = 1, 24 do
      local message = r.ReaWeb_Receive(window)
      if message == "" then break end
      handle(message)
    end
  end)
  if not ok then r.MB(tostring(err), "SBP Loudness Curve", 0); return end
  r.defer(loop)
end
loop()
