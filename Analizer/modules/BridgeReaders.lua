local M = {}

function M.CreateBridgeReaders(deps)
  local r = deps.r
  local state = deps.state
  local Clamp = deps.Clamp
  local ReadTrackFxPhysicalParam = deps.ReadTrackFxPhysicalParam
  local LufsToEnergy = deps.LufsToEnergy
  local GetSourceDialogueSettings = deps.GetSourceDialogueSettings

  local COCKOS_LM_JSFX_NAME = deps.COCKOS_LM_JSFX_NAME
  local COCKOS_LM_FILE_NAME = deps.COCKOS_LM_FILE_NAME
  local COCKOS_CFG_LUFS_M = deps.COCKOS_CFG_LUFS_M
  local COCKOS_CFG_LUFS_S = deps.COCKOS_CFG_LUFS_S
  local COCKOS_CFG_LUFS_I = deps.COCKOS_CFG_LUFS_I
  local COCKOS_CFG_REINIT = deps.COCKOS_CFG_REINIT
  local COCKOS_OUT_PEAK = deps.COCKOS_OUT_PEAK
  local COCKOS_OUT_LUFS_M = deps.COCKOS_OUT_LUFS_M
  local COCKOS_OUT_LUFS_S = deps.COCKOS_OUT_LUFS_S
  local COCKOS_OUT_LUFS_I = deps.COCKOS_OUT_LUFS_I

  local SPEECH_GATE_JSFX_NAME = deps.SPEECH_GATE_JSFX_NAME
  local SPEECH_GATE_FILE_NAME = deps.SPEECH_GATE_FILE_NAME
  local SPEECH_OUT_LUFS_M = deps.SPEECH_OUT_LUFS_M
  local SPEECH_OUT_LUFS_S = deps.SPEECH_OUT_LUFS_S
  local SPEECH_OUT_LUFS_I = deps.SPEECH_OUT_LUFS_I
  local SPEECH_OUT_PEAK = deps.SPEECH_OUT_PEAK
  local SPEECH_OUT_VOICE_SCORE = deps.SPEECH_OUT_VOICE_SCORE

  local function TryGetFxName(track, fx_idx)
    local ok, retval, name = pcall(r.TrackFX_GetFXName, track, fx_idx, "")
    if not ok then return "" end
    if type(retval) == "string" then return retval end
    if type(name) == "string" then return name end
    return ""
  end

  local function FindFxByNameContains(track, needle)
    local n = r.TrackFX_GetCount(track) or 0
    local key = (needle or ""):lower()
    for i = 0, n - 1 do
      local fx_name = TryGetFxName(track, i):lower()
      if fx_name ~= "" and fx_name:find(key, 1, true) then
        return i
      end
    end
    return -1
  end

  local function EnsureCockosMeterConfigured(track, fx_idx)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_M, 2)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_S, 1)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_I, 1)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_REINIT, 0)
  end

  local function EnsureCockosMeterFx(track, allow_insert)
    if not track then return -1, "Track is nil" end

    local cockos_idx = FindFxByNameContains(track, "loudness meter peak/rms/lufs")
    if cockos_idx < 0 and allow_insert ~= false then
      cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_JSFX_NAME, false, 0)
    end
    if cockos_idx < 0 and allow_insert ~= false then
      cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_FILE_NAME, false, 0)
    end
    if cockos_idx < 0 and allow_insert ~= false then
      cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_JSFX_NAME, false, 1)
    end
    if cockos_idx < 0 and allow_insert ~= false then
      cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_FILE_NAME, false, 1)
    end
    if cockos_idx >= 0 then
      local n_params = r.TrackFX_GetNumParams(track, cockos_idx) or 0
      if n_params > COCKOS_OUT_LUFS_I then
        EnsureCockosMeterConfigured(track, cockos_idx)
        return cockos_idx, nil
      end
    end

    return -1, "Cockos Loudness Meter not found/loaded"
  end

  local function EnsureSpeechGateBridgeFx(track, allow_insert)
    if not track then return -1, "Track is nil" end

    local fx_idx = FindFxByNameContains(track, "sbp speech gate bridge")
    if fx_idx < 0 and allow_insert ~= false then
      fx_idx = r.TrackFX_AddByName(track, SPEECH_GATE_JSFX_NAME, false, 0)
    end
    if fx_idx < 0 and allow_insert ~= false then
      fx_idx = r.TrackFX_AddByName(track, SPEECH_GATE_FILE_NAME, false, 0)
    end
    if fx_idx < 0 and allow_insert ~= false then
      fx_idx = r.TrackFX_AddByName(track, SPEECH_GATE_JSFX_NAME, false, 1)
    end
    if fx_idx < 0 and allow_insert ~= false then
      fx_idx = r.TrackFX_AddByName(track, SPEECH_GATE_FILE_NAME, false, 1)
    end
    if fx_idx >= 0 then
      local n_params = r.TrackFX_GetNumParams(track, fx_idx) or 0
      if n_params > SPEECH_OUT_VOICE_SCORE then
        return fx_idx, nil
      end
    end

    return -1, "SBP Speech Gate Bridge not found/loaded"
  end

  local function ReadSpeechGateBridgePoint(track, allow_insert)
    local fx_idx, err = EnsureSpeechGateBridgeFx(track, allow_insert)
    if fx_idx < 0 then return nil, err end

    local m_db = ReadTrackFxPhysicalParam(track, fx_idx, SPEECH_OUT_LUFS_M, -120.0, 12.0)
    local st_db = ReadTrackFxPhysicalParam(track, fx_idx, SPEECH_OUT_LUFS_S, -120.0, 12.0)
    local i_db = ReadTrackFxPhysicalParam(track, fx_idx, SPEECH_OUT_LUFS_I, -120.0, 12.0)
    local peak_db = ReadTrackFxPhysicalParam(track, fx_idx, SPEECH_OUT_PEAK, -150.0, 20.0)
    local speech_score = ReadTrackFxPhysicalParam(track, fx_idx, SPEECH_OUT_VOICE_SCORE, 0.0, 1.0)
    if m_db <= -119.0 and st_db <= -119.0 then
      m_db = -120.0
      st_db = -120.0
      if i_db <= -119.0 then i_db = -120.0 end
      if peak_db <= -149.0 then peak_db = -150.0 end
    end
    state.backend_note = "JSFX source: SBP Speech Gate Bridge"

    return {
      m = m_db,
      st = st_db,
      i = i_db,
      s = st_db,
      peak = peak_db,
      speech_score = Clamp(tonumber(speech_score) or 0.0, 0.0, 1.0),
      gated = (m_db < -70.0),
      lin_energy = LufsToEnergy(m_db),
      m_energy = LufsToEnergy(m_db),
      i_src = i_db
    }, nil
  end

  local function ReadCockosBridgePoint(track, allow_insert, note_text)
    local fx_idx, err = EnsureCockosMeterFx(track, allow_insert)
    if fx_idx < 0 then return nil, err end

    local m_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_M, -100.0, 0.0)
    local st_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_S, -100.0, 0.0)
    local i_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_I, -100.0, 0.0)
    local peak_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_PEAK, -150.0, 20.0)
    if m_db <= -99.0 and st_db <= -99.0 then
      m_db = -120.0
      st_db = -120.0
      if i_db <= -99.0 then i_db = -120.0 end
      if peak_db <= -149.0 then peak_db = -150.0 end
    end
    state.backend_note = note_text or "JSFX source: Cockos Loudness Meter"

    return {
      m = m_db,
      st = st_db,
      i = i_db,
      s = st_db,
      peak = peak_db,
      gated = (m_db < -70.0),
      lin_energy = LufsToEnergy(m_db),
      m_energy = LufsToEnergy(m_db),
      i_src = i_db
    }, nil
  end

  local function ReadBridgePoint(track, allow_insert, source_label)
    local cfg = GetSourceDialogueSettings(source_label or "A")
    if cfg and cfg.method_key == "speech_gate" then
      local sp, sp_err = ReadSpeechGateBridgePoint(track, allow_insert)
      -- Keep graph scale stable in speech mode by using Cockos meter values as primary curves.
      -- Speech bridge is still queried first to detect availability and keep dedicated path visible.
      local ck, ck_err = ReadCockosBridgePoint(track, true, "JSFX source: Cockos Loudness Meter (speech mode)")
      if ck then
        if sp then
          ck.speech_bridge_ok = true
          ck.speech_score = sp.speech_score
        end
        return ck, nil
      end
      if sp then return sp, nil end
      return nil, string.format("%s | %s", tostring(sp_err or "Speech JSFX unavailable"), tostring(ck_err or "Cockos unavailable"))
    end

    return ReadCockosBridgePoint(track, allow_insert, "JSFX source: Cockos Loudness Meter")
  end

  return {
    ReadBridgePoint = ReadBridgePoint,
    EnsureCockosMeterFx = EnsureCockosMeterFx
  }
end

return M
