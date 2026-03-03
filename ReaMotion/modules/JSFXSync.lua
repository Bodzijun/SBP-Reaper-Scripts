---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local JSFXSync = {}

local r = reaper

local EXT_MIXER_CANDIDATES = {
  'JS: sbp_ReaMotionPad_Mixer',
  'JS: Utility/sbp_ReaMotionPad_Mixer',
  'JS: IX/Mixer_8xS-1xS',
  'JS: Utility/8x Stereo to 1x Stereo Mixer',
  'JS: Utility/4x Stereo to 1x Stereo Mixer'
}

-- Find or create mixer FX on track
function JSFXSync.FindOrCreateMixer(track, create_if_missing)
  if not track then return -1, false end

  local cnt = r.TrackFX_GetCount(track)

  -- Search for existing mixer
  for i = 0, cnt - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i)
    for _, candidate in ipairs(EXT_MIXER_CANDIDATES) do
      if fx_name == candidate then
        return i, true
      end
    end
  end

  -- Create if missing
  if create_if_missing then
    for _, candidate in ipairs(EXT_MIXER_CANDIDATES) do
      local idx = r.TrackFX_AddByName(track, candidate, false, 0)
      if idx >= 0 then
        return idx, true
      end
    end
  end

  return -1, false
end

-- Configure mixer input channels for motion pad sources
function JSFXSync.ConfigureMixerInputs(track, mixer_idx, sources, mixer_channels)
  if not track or mixer_idx < 0 then return end
  if not sources or not mixer_channels then return end

  -- Configure each channel's min/max for dB range
  for i = 1, 4 do
    local src = sources[i]
    local ch_cfg = mixer_channels[i]
    if src and ch_cfg then
      -- Set channel parameters via FX parameters if needed
      -- This is a placeholder for actual JSFX parameter configuration
    end
  end
end

-- Sync JSFX mixer with state configuration
function JSFXSync.SyncMixer(track, state, markDirty)
  if not track or not state then return false end

  local sources = state.external and state.external.sources or {}
  local mixer_channels = state.mixer and state.mixer.channels or {}

  local mixer_idx, is_custom = JSFXSync.FindOrCreateMixer(track, true)
  if mixer_idx >= 0 and is_custom then
    JSFXSync.ConfigureMixerInputs(track, mixer_idx, sources, mixer_channels)
    return true
  end

  return false
end

-- Convert dB to normalized value (for JSFX parameters)
function JSFXSync.DbToNormalized(db, min_db, max_db)
  min_db = min_db or -60
  max_db = max_db or 6
  if db <= min_db then return 0.0 end
  if db >= max_db then return 1.0 end
  local range = max_db - min_db
  return (db - min_db) / range
end

-- Convert normalized value to dB
function JSFXSync.NormalizedToDb(norm, min_db, max_db)
  min_db = min_db or -60
  max_db = max_db or 6
  norm = math.max(0.0, math.min(1.0, norm))
  local range = max_db - min_db
  return min_db + (range * norm)
end

return JSFXSync
