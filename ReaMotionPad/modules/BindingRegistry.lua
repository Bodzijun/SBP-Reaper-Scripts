local BindingRegistry = {}
local r = reaper

local function clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

function BindingRegistry.NewBinding()
  return {
    enabled = true,
    label = "",
    fx_guid = "",
    fx_name = "",
    param_index = 0,
    param_name = "",
    side = 0,
    invert = false,
    min = 0.0,
    max = 1.0,
    curve = 1.0
  }
end

function BindingRegistry.GetTrackByName(name)
  local count = r.CountTracks(0)
  for i = 0, count - 1 do
    local track = r.GetTrack(0, i)
    local _, tr_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if tr_name == name then
      return track
    end
  end
  return nil
end

function BindingRegistry.ListFX(track)
  local items = {}
  if not track then return items end
  local cnt = r.TrackFX_GetCount(track)
  for i = 0, cnt - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i)
    local guid = r.TrackFX_GetFXGUID(track, i)
    items[#items + 1] = {index = i, name = fx_name, guid = guid}
  end
  return items
end

function BindingRegistry.ListParams(track, fx_index)
  local items = {}
  if not track or fx_index < 0 then return items end
  local cnt = r.TrackFX_GetNumParams(track, fx_index)
  for i = 0, cnt - 1 do
    local _, p_name = r.TrackFX_GetParamName(track, fx_index, i)
    items[#items + 1] = {index = i, name = p_name}
  end
  return items
end

function BindingRegistry.ResolveFXIndex(track, binding)
  if not track or not binding then return -1 end
  local cnt = r.TrackFX_GetCount(track)

  if binding.fx_guid and binding.fx_guid ~= "" then
    for i = 0, cnt - 1 do
      local guid = r.TrackFX_GetFXGUID(track, i)
      if guid == binding.fx_guid then
        return i
      end
    end
  end

  if binding.fx_name and binding.fx_name ~= "" then
    for i = 0, cnt - 1 do
      local _, fx_name = r.TrackFX_GetFXName(track, i)
      if fx_name == binding.fx_name then
        return i
      end
    end
  end

  return -1
end

function BindingRegistry.ResolveEnvelope(track, binding)
  local fx_index = BindingRegistry.ResolveFXIndex(track, binding)
  if fx_index < 0 then
    return nil, -1
  end
  local p_idx = math.max(0, math.floor(binding.param_index or 0))
  local env = r.GetFXEnvelope(track, fx_index, p_idx, true)
  return env, fx_index
end

function BindingRegistry.RemapValue(binding, norm)
  local n = clamp(norm, 0.0, 1.0)
  if binding.invert then
    n = 1.0 - n
  end
  local curve = clamp(binding.curve or 1.0, 0.1, 8.0)
  local warped = n ^ curve
  local min_v = binding.min or 0.0
  local max_v = binding.max or 1.0
  local out = min_v + (max_v - min_v) * warped
  return clamp(out, math.min(min_v, max_v), math.max(min_v, max_v))
end

return BindingRegistry
