---@diagnostic disable: undefined-field, need-check-nil

local EngineSync = {}
local r = reaper

local FX_NAME = 'sbp_ReaSciFiEngine'

local IDX = {
  mode = 0,
  family = 1,
  intensity = 2,
  complexity = 3,
  dirt = 4,
  motion = 5,
  tail = 6,
  pitch = 7,
  color = 8,
  spread = 9,
  master_gain = 10,
  pad_timbre_x = 11,
  pad_timbre_y = 12,
  pad_motion_x = 13,
  pad_motion_y = 14,
  lfo_depth = 15,
  lfo_rate = 16,
  mseg_depth = 17,
  drive = 18,
  chaos_mix = 19,
  preview_gate = 20,
  pulse_rate = 21,
  output_mode = 22,
  layer_gain_digital = 23,
  layer_gain_packet = 24,
  layer_gain_noise = 25,
  layer_gain_resonator = 26,
  layer_gain_chaos = 27,
  lfo1_wave = 28,
  lfo2_depth = 29,
  lfo2_rate = 30,
  lfo2_wave = 31,
  chaos_mode = 32,
  character = 33,
  e2_grain_mix = 34,
  e2_spectral_mix = 35,
  e2_reverse_mix = 36,
  e2_safety = 37,
  e2_cpu_quality = 38,
  follow_note_len = 39,
  reset_voice = 40
}

local function getTrackName(track)
  local _, name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
  return name or ''
end

function EngineSync.GetTargetTrack(setup)
  if r.CountTracks(0) == 0 then
    return nil, 'Project has no tracks.'
  end

  if setup.follow_selected_track then
    local selected_track = r.GetSelectedTrack(0, 0)
    if selected_track then
      setup.target_track_name = getTrackName(selected_track)
      return selected_track
    end
  end

  if setup.target_track_name ~= '' then
    local track_count = r.CountTracks(0)
    for index = 0, track_count - 1 do
      local track = r.GetTrack(0, index)
      if getTrackName(track) == setup.target_track_name then
        return track
      end
    end
  end

  local fallback_track = r.GetSelectedTrack(0, 0)
  if fallback_track then
    setup.target_track_name = getTrackName(fallback_track)
    return fallback_track
  end

  return nil, 'Select a target track for ReaSciFi.'
end

-- Cache: track_pointer -> fx_index.
-- Avoids calling TrackFX_AddByName on every slider change (which caused constant
-- FX duplication). Cache is invalidated when the track pointer changes.
local fx_cache = { track = nil, fx_index = -1 }

local function normalizeName(name)
  return (tostring(name or '')):lower()
end

local function findExistingEngine(track)
  local count = r.TrackFX_GetCount(track)
  local needle = normalizeName(FX_NAME)
  for i = 0, count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i)
    local n = normalizeName(fx_name)
    if n:find(needle, 1, true) then
      return i
    end
  end
  return -1
end

local function ensureEngine(track)
  -- Return cached index if the track hasn't changed and the FX still exists.
  if fx_cache.track == track and fx_cache.fx_index >= 0 then
    local count = r.TrackFX_GetCount(track)
    if fx_cache.fx_index < count then
      local _, fx_name = r.TrackFX_GetFXName(track, fx_cache.fx_index)
      if normalizeName(fx_name):find(normalizeName(FX_NAME), 1, true) then
        return fx_cache.fx_index
      end
    end
    -- Cached slot changed or FX was removed externally — invalidate.
    fx_cache.fx_index = -1
  end

  -- Always prefer an existing instance to avoid duplicate engine insertion.
  local existing = findExistingEngine(track)
  if existing >= 0 then
    fx_cache.track = track
    fx_cache.fx_index = existing
    return existing
  end

  -- instantiate=0 : query only, returns -1 when not present (NO insertion).
  -- instantiate=1 : insert if not found, return index (idempotent).
  -- NEVER use negative values here: negative instantiate always forces a NEW copy.
  local fx_index = r.TrackFX_AddByName(track, 'JS:' .. FX_NAME, false, 0)
  if fx_index < 0 then
    fx_index = r.TrackFX_AddByName(track, 'JS:' .. FX_NAME, false, 1)
  end

  -- Fallback safety: if AddByName returned unexpected index, still lock to first existing.
  local verify = findExistingEngine(track)
  if verify >= 0 then
    fx_index = verify
  end

  fx_cache.track = track
  fx_cache.fx_index = fx_index
  return fx_index
end

local function setParam(track, fx_index, param_index, value)
  r.TrackFX_SetParam(track, fx_index, param_index, value)
end

function EngineSync.PushState(state)
  local track, err = EngineSync.GetTargetTrack(state.setup)
  if not track then
    return false, err
  end

  local fx_index = ensureEngine(track)
  if fx_index < 0 then
    return false, 'Failed to find or insert sbp_ReaSciFiEngine.'
  end

  local synth = state.synth

  if synth.output_mode == 1 then
    r.SetMediaTrackInfo_Value(track, 'I_NCHAN', 6)
  elseif r.GetMediaTrackInfo_Value(track, 'I_NCHAN') < 2 then
    r.SetMediaTrackInfo_Value(track, 'I_NCHAN', 2)
  end

  setParam(track, fx_index, IDX.mode, synth.mode)
  setParam(track, fx_index, IDX.family, synth.family)
  setParam(track, fx_index, IDX.intensity, synth.intensity)
  setParam(track, fx_index, IDX.complexity, synth.complexity)
  setParam(track, fx_index, IDX.dirt, synth.dirt)
  setParam(track, fx_index, IDX.motion, synth.motion)
  setParam(track, fx_index, IDX.tail, synth.tail)
  setParam(track, fx_index, IDX.pitch, synth.pitch)
  setParam(track, fx_index, IDX.color, synth.color)
  setParam(track, fx_index, IDX.spread, synth.spread)
  setParam(track, fx_index, IDX.master_gain, synth.master_gain)
  setParam(track, fx_index, IDX.pad_timbre_x, synth.pad_timbre_x)
  setParam(track, fx_index, IDX.pad_timbre_y, synth.pad_timbre_y)
  setParam(track, fx_index, IDX.pad_motion_x, synth.pad_motion_x)
  setParam(track, fx_index, IDX.pad_motion_y, synth.pad_motion_y)
  setParam(track, fx_index, IDX.lfo_depth, synth.lfo_depth)
  setParam(track, fx_index, IDX.lfo_rate, synth.lfo_rate)
  setParam(track, fx_index, IDX.mseg_depth, synth.mseg_depth)
  setParam(track, fx_index, IDX.drive, synth.drive)
  setParam(track, fx_index, IDX.chaos_mix, synth.chaos_mix)
  setParam(track, fx_index, IDX.preview_gate, synth.preview_gate)
  setParam(track, fx_index, IDX.pulse_rate, synth.pulse_rate)
  setParam(track, fx_index, IDX.output_mode, synth.output_mode)
  setParam(track, fx_index, IDX.layer_gain_digital, synth.layer_gain_digital)
  setParam(track, fx_index, IDX.layer_gain_packet, synth.layer_gain_packet)
  setParam(track, fx_index, IDX.layer_gain_noise, synth.layer_gain_noise)
  setParam(track, fx_index, IDX.layer_gain_resonator, synth.layer_gain_resonator)
  setParam(track, fx_index, IDX.layer_gain_chaos, synth.layer_gain_chaos)
  setParam(track, fx_index, IDX.lfo1_wave, synth.lfo1_wave)
  setParam(track, fx_index, IDX.lfo2_depth, synth.lfo2_depth)
  setParam(track, fx_index, IDX.lfo2_rate, synth.lfo2_rate)
  setParam(track, fx_index, IDX.lfo2_wave, synth.lfo2_wave)
  setParam(track, fx_index, IDX.chaos_mode, synth.chaos_mode)
  setParam(track, fx_index, IDX.character, synth.character)
  setParam(track, fx_index, IDX.e2_grain_mix, synth.e2_grain_mix)
  setParam(track, fx_index, IDX.e2_spectral_mix, synth.e2_spectral_mix)
  setParam(track, fx_index, IDX.e2_reverse_mix, synth.e2_reverse_mix)
  setParam(track, fx_index, IDX.e2_safety, synth.e2_safety)
  setParam(track, fx_index, IDX.e2_cpu_quality, synth.e2_cpu_quality)
  setParam(track, fx_index, IDX.follow_note_len, synth.follow_note_len or 0)

  return true, 'Synced ReaSciFi to track: ' .. getTrackName(track)
end

function EngineSync.ResetPlaybackState(state)
  local track, err = EngineSync.GetTargetTrack(state.setup)
  if not track then
    return false, err
  end

  local fx_index = ensureEngine(track)
  if fx_index < 0 then
    return false, 'Failed to find or insert sbp_ReaSciFiEngine.'
  end

  EngineSync._reset_toggle = EngineSync._reset_toggle == 1 and 0 or 1
  setParam(track, fx_index, IDX.reset_voice, EngineSync._reset_toggle)
  return true, 'ReaSciFi playback state reset on track: ' .. getTrackName(track)
end

return EngineSync