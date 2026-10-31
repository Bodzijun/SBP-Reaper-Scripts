local platform = dofile(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') .. 'platform.lua')
-- Read-only file transfer and explicit project transport commands for the WebView.
local M = {}
local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
      .. alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
      .. (b and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or '=')
      .. (c and alphabet:sub(n % 64 + 1, n % 64 + 1) or '=')
  end
  return table.concat(out)
end
function M.new(r, directory)
  local cache=directory and dofile(directory..'cache.lua')
  local file, owned_playback, owned_project, stream
  local api = {}
  function api.clear()
    if file then file:close(); file = nil end
  end
  function api.close()
    api.clear()
    api.stream_clear()
    if owned_playback and owned_project == r.GetTrackGUID(r.GetMasterTrack(0)) and r.GetPlayStateEx(0) & 4 == 0 then r.OnStopButtonEx(0) end
    owned_playback = false
  end
  function api.stream_clear()
    if stream then
      local stop = io.open(stream.stop, 'wb'); if stop then stop:close() end
      stream = nil
    end
  end
  function api.keepalive()
    if stream and r.time_precise() - stream.touched >= 10 then
      local lease = io.open(stream.lease, 'wb'); if lease then lease:close() end
      stream.touched = r.time_precise()
    end
  end
  function api.stream_poll()
    assert(stream, 'Start audio streaming first')
    local ready = io.open(stream.ready, 'rb')
    if not ready then
      if r.time_precise()-stream.started>=15 then api.stream_clear();error('Audio streaming startup timed out. Check Python.') end
      return {starting=true}
    end
    local text = ready:read('*a');ready:close()
    local result = {starting=false}
    for key,value in text:gmatch('([%w_]+)=([^\r\n]+)') do result[key]=tonumber(value) or value end
    if result.status~='ok' then api.stream_clear();error(result.error or 'Audio streaming startup failed') end
    return result
  end
  function api.stream_begin(path)
    local normalized, err = platform.path(path); assert(normalized, err); path = normalized
    if stream and stream.audio==path then return api.stream_poll() end
    assert(directory, 'Audio streaming directory is unavailable')
    local opened, err=io.open(path,'rb');assert(opened,err)
    local size=opened:seek('end');opened:close();assert(size and size>0,'Audio file is empty')
    api.stream_clear()
    local python=platform.python(r)
    local temp=cache and cache.directory(r) or assert(platform.temp(),'Temporary directory unavailable')
    local job=temp..'/SBP_LoudnessPreview_'..tostring(r.time_precise()):gsub('[^%d]','')..'_'..math.random(1,2147483647)..'.request'
    local request=assert(io.open(job,'wb'));request:write('audio='..path..'\n');request:close()
    local function argument(value) return platform.argument(value,r) end
    local ok,launch_error=pcall(r.ExecProcess,argument(python)..' '..argument(directory..'preview_server.py')..' '..argument(job),-2)
    if not ok then os.remove(job);error(launch_error) end
    stream={audio=path,ready=job:gsub('%.request$','.ready'),stop=job:gsub('%.request$','.stop'),lease=job:gsub('%.request$','.lease'),started=r.time_precise(),touched=r.time_precise()}
    return {starting=true}
  end
  function api.file_begin(path)
    api.clear()
    local normalized, err = platform.path(path); assert(normalized, err); path = normalized
    local ext = path:match('%.([^%.\\/]+)$')
    ext = ext and ext:lower()
    local mime = ({wav='audio/wav',wave='audio/wav',mp3='audio/mpeg',flac='audio/flac',ogg='audio/ogg',m4a='audio/mp4',aac='audio/aac',webm='audio/webm'})[ext]
    assert(mime, 'File preview supports WAV, MP3, FLAC, OGG, M4A, AAC and WebM. Use REAPER timeline for other formats.')
    local opened, err = io.open(path, 'rb')
    assert(opened, err)
    local size = opened:seek('end')
    if not size or size == 0 or size > 128 * 1024 * 1024 then
      opened:close(); error('File preview supports audio up to 128 MB. Use REAPER timeline for larger files.')
    end
    opened:seek('set', 0); file = opened
    return {size = size, mime = mime}
  end
  function api.file_chunk()
    assert(file, 'Start file preview loading first')
    local data = file:read(196608)
    local done = not data or #data < 196608
    if done then api.clear() end
    return {data = base64(data or ''), done = done}
  end
  function api.transport(command, value)
    local playstate = r.GetPlayStateEx(0)
    if command ~= 'state' then
      assert(playstate & 4 == 0, 'Transport controls are disabled while REAPER is recording')
      if command == 'play' or command == 'seek' then
        local time = tonumber(value)
        assert(time and time >= 0 and time < math.huge, 'Invalid playback position')
        if playstate & 2 ~= 0 then r.OnStopButtonEx(0) end
        r.SetEditCurPos2(0, time, false, command == 'seek')
        if command == 'play' then r.OnPlayButtonEx(0); owned_playback = true; owned_project = r.GetTrackGUID(r.GetMasterTrack(0)) end
      elseif command == 'pause' then
        if playstate & 1 ~= 0 then r.OnPauseButtonEx(0) end
      elseif command == 'stop' then r.OnStopButtonEx(0); owned_playback = false
      else error('Unknown transport command') end
    end
    playstate = r.GetPlayStateEx(0)
    if playstate == 0 then owned_playback = false end
    return {playing = playstate & 1 ~= 0, paused = playstate & 2 ~= 0, recording = playstate & 4 ~= 0,
      position = playstate ~= 0 and r.GetPlayPositionEx(0) or r.GetCursorPositionEx(0)}
  end
  return api
end
return M
