-- @description SBP MotorSynth 2 - Lua backend

local r = reaper
if not r.APIExists('ReaWeb_Receive') then
  r.ShowMessageBox('Install ReaWebAPI v0.3.9.69 to run this action.', 'MotorSynth 2', 0)
  return
end

local script_dir = debug.getinfo(1, 'S').source:sub(2):match('^(.*[\\/])')
local M = dofile(script_dir .. 'MotorSynth_Lib.lua')
local registry = r.GetResourcePath() .. '/ReaWebAPI/MotorSynth2-Lua'
local channel = 'sbp-ms2-lua'

local jsfx = { M.es_effects[1], M.link_effect, M.bench .. '/sbp_Grip_Motion_Link.jsfx' }
local allowed_names = {
  ['VST3i: Grip (BOOM Interactive)'] = true,
  ['VST3: Grip (BOOM Interactive)'] = true,
  ['Grip (BOOM Interactive)'] = true,
}
for _, name in ipairs(jsfx) do allowed_names['JS: ' .. name] = true end
for _, name in ipairs(M.clap_names) do allowed_names[name] = true end

local grip_params = { [0] = true, [3] = true, [4] = true, [7] = true, [10] = true }
local link_properties = {
  ['mod.active'] = true,
  ['mod.baseline'] = true,
  ['plink.active'] = true,
  ['plink.effect'] = true,
  ['plink.param'] = true,
  ['plink.scale'] = true,
  ['plink.offset'] = true,
}
local languages = { en = true, uk = true, zh = true }

local function link_key(key)
  local param, property = key:match('^param%.(%d+)%.(.+)$')
  return grip_params[tonumber(param)] and link_properties[property]
end

local function supported_fx(track, index)
  local ident = M.ident(track, index)
  if ident == M.clap_id or ident:lower():find('grip.vst3', 1, true) then return true end
  for _, name in ipairs(jsfx) do
    if ident == name or ident:sub(-#name - 1) == '/' .. name then return true end
  end
  return false
end

local function track_handle(track)
  if not track then return '' end
  local index = r.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER') - 1
  return ('%d:%s'):format(index, r.GetTrackGUID(track))
end

local function resolve_track(project, handle)
  local index, guid = handle:match('^(%d+):(%b{})$')
  if not guid then return end
  local track = r.GetTrack(project, tonumber(index))
  if track and r.GetTrackGUID(track) == guid then return track end
  for i = 0, r.CountTracks(project) - 1 do
    track = r.GetTrack(project, i)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
end

local function wire_bool(value)
  return value and '1' or '0'
end

local function wire_numbers(...)
  local values = { ... }
  for i, value in ipairs(values) do
    values[i] = ('%.17g'):format(value):gsub(',', '.')
  end
  return table.concat(values, ' ')
end

local function wire_text(ok, value)
  return wire_bool(ok) .. ' ' .. (ok and value or '')
end

local project_ops = {
  ['count-tracks'] = function(project) return r.CountTracks(project) end,
  ['count-selected'] = function(project) return r.CountSelectedTracks(project) end,
  ['track'] = function(project, index) return track_handle(r.GetTrack(project, index)) end,
  ['selected'] = function(project, index) return track_handle(r.GetSelectedTrack(project, index)) end,
}

local fx_reads = {
  ['fx-guid'] = function(track, q) return r.TrackFX_GetFXGUID(track, q.fx) or '' end,
  ['get-config'] = function(track, q)
    if q.text ~= 'fx_ident' and not link_key(q.text) then return nil, 'Invalid FX property.' end
    return wire_text(r.TrackFX_GetNamedConfigParm(track, q.fx, q.text))
  end,
  ['param-name'] = function(track, q) return wire_text(r.TrackFX_GetParamName(track, q.fx, q.a, '')) end,
  ['param-display'] = function(track, q) return wire_text(r.TrackFX_GetFormattedParamValue(track, q.fx, q.a, '')) end,
  ['param-format'] = function(track, q)
    if q.b < 0 or q.b > 1 then return nil, 'Invalid normalized value.' end
    return wire_text(r.TrackFX_FormatParamValueNormalized(track, q.fx, q.a, q.b, ''))
  end,
  ['param-range'] = function(track, q) return wire_numbers(r.TrackFX_GetParamEx(track, q.fx, q.a)) end,
  ['param-raw'] = function(track, q) return wire_numbers(r.TrackFX_GetParam(track, q.fx, q.a)) end,
  ['param-normalized'] = function(track, q) return wire_numbers(r.TrackFX_GetParamNormalized(track, q.fx, q.a)) end,
  ['get-pin'] = function(track, q) return wire_numbers(r.TrackFX_GetPinMappings(track, q.fx, q.a, q.b)) end,
}

local fx_writes = {
  ['set-param'] = function(track, q)
    if q.b < 0 or q.b > 1 then return nil, 'Invalid normalized value.' end
    return wire_bool(r.TrackFX_SetParamNormalized(track, q.fx, q.a, q.b))
  end,
  ['set-param-raw'] = function(track, q)
    if q.b < 0 or q.b > 63 then return nil, 'Invalid Link ID.' end
    return wire_bool(r.TrackFX_SetParam(track, q.fx, q.a, q.b))
  end,
  ['set-pin'] = function(track, q)
    if (q.a ~= 0 and q.a ~= 1) or q.b < 0 or q.b >= 64 then return nil, 'Invalid FX pin.' end
    return wire_bool(r.TrackFX_SetPinMappings(track, q.fx, q.a, q.b, q.c, q.d))
  end,
  ['set-config'] = function(track, q)
    local key, value = q.text:match('^(%S+) (%-?%d+)$')
    if not key or not link_key(key) then return nil, 'Invalid FX link property.' end
    return wire_bool(r.TrackFX_SetNamedConfigParm(track, q.fx, key, value))
  end,
  ['move-fx'] = function(track, q)
    if q.a < 0 or q.a >= r.TrackFX_GetCount(track) then return nil, 'Invalid FX destination.' end
    r.TrackFX_CopyToTrack(track, q.fx, track, q.a, true)
    return ''
  end,
}

local project
local epoch = math.floor(r.time_precise() * 1000)
local function dispatch(q)
  if q.verb == 'get-language' then return r.GetExtState('SBP_MotorSynth2', 'language') end
  if q.verb == 'set-language' then
    if not languages[q.text] then return nil, 'Invalid MotorSynth language.' end
    r.SetExtState('SBP_MotorSynth2', 'language', q.text, true)
    return ''
  end

  local current = r.EnumProjects(-1)
  if current ~= project then project, epoch = current, epoch + 1 end
  if not project then return nil, 'No active REAPER project.' end
  if q.verb == 'project' then return epoch end
  if q.epoch ~= epoch then
    if q.verb == 'check-track' then return '0' end
    return nil, 'The active REAPER project changed.'
  end

  local project_op = project_ops[q.verb]
  if project_op then return project_op(project, q.a) end

  local track = resolve_track(project, q.track)
  if q.verb == 'check-track' then return wire_bool(track ~= nil) end
  if not track then return nil, 'The vehicle track is unavailable or changed.' end
  if q.verb == 'count-fx' then return r.TrackFX_GetCount(track) end
  if q.verb == 'get-channels' then return r.GetMediaTrackInfo_Value(track, 'I_NCHAN') end
  if q.verb == 'set-channels' then
    if q.a ~= M.es_channels then return nil, 'Invalid track channel count.' end
    return wire_bool(r.SetMediaTrackInfo_Value(track, 'I_NCHAN', q.a))
  end
  if q.verb == 'add-fx' then
    if not allowed_names[q.text] then return nil, 'Invalid MotorSynth FX name.' end
    return r.TrackFX_AddByName(track, q.text, false, -1)
  end

  local read, write = fx_reads[q.verb], fx_writes[q.verb]
  if not (read or write) then return nil, 'Invalid MotorSynth request.' end
  if q.fx < 0 or q.fx >= r.TrackFX_GetCount(track) then return nil, 'The target FX index is unavailable.' end
  if read then return read(track, q) end
  if not supported_fx(track, q.fx) then return nil, 'The target FX is unavailable or changed.' end
  return write(track, q)
end

local function parse(message)
  if #message > 1024 or message:find('[\r\n%z]') then return end
  local client, id, deadline, verb, context, track, fx, a, b, c, d, text = message:match(
    '^sbp%-ms2%-lua ([0-9a-f]+) (%d+) (%d+) (%S+) (%d+) (%S+) (%-?%d+) (%S+) (%S+) (%S+) (%S+) (.+)$'
  )
  if not client or #client ~= 32 then return end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and b and c and d) then return end
  return {
    client = client, id = id, deadline = tonumber(deadline), verb = verb,
    epoch = tonumber(context), track = track, fx = tonumber(fx),
    a = a, b = b, c = c, d = d, text = text,
  }
end

local function process_messages(id)
  for _ = 1, 32 do
    local message = r.ReaWeb_Receive(id)
    if message == '' then return end
    local request = parse(message)
    if request then
      local ok, result, problem
      if os.time() > request.deadline then
        problem = 'MotorSynth request expired.'
      else
        ok, result, problem = pcall(dispatch, request)
        if not ok then problem, result = result, nil end
      end
      local status = result ~= nil and 'ok' or 'error'
      r.ReaWeb_Send(id, ('%s %s %s %s\n%s'):format(
        channel, request.client, request.id, status, tostring(result or problem)
      ))
    end
  end
end

local function collect_windows()
  local windows, index = {}, 0
  r.EnumerateFiles(registry, -1)
  while #windows < 128 do
    local filename = r.EnumerateFiles(registry, index)
    if not filename then break end
    index = index + 1
    local id, app_id = filename:match('^ms2%-(%d+)%.([a-z0-9%-]+)$')
    id = tonumber(id)
    if id and r.ReaWeb_IsReady(id) then
      local diagnostics = r.ReaWeb_GetDiagnostics(id)
      if diagnostics:match('"appId"%s*:%s*"([a-z0-9%-]+)"') == app_id
        and diagnostics:find('"jsfx"%s*:%s*{') then
        windows[#windows + 1] = id
      end
    end
  end
  return windows
end

local windows, next_scan = {}, 0
local function poll()
  local now = r.time_precise()
  if now >= next_scan then
    windows, next_scan = collect_windows(), now + 0.25
  end
  for _, id in ipairs(windows) do
    if r.ReaWeb_IsReady(id) then process_messages(id) end
  end
  r.defer(poll)
end

r.set_action_options(1)
local _, _, section, command = r.get_action_context()
local function toolbar(state)
  r.SetToggleCommandState(section, command, state)
  r.RefreshToolbar2(section, command)
end
toolbar(1)
r.atexit(function() toolbar(0) end)
poll()

