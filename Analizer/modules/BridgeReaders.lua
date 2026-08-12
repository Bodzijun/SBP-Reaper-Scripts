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
  local cockos_output_param_cache = setmetatable({}, { __mode = "k" })

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

  local function IsSpeechGateV3Name(name)
    local fx_name = tostring(name or ""):lower()
    return fx_name:find("sbp speech gate bridge", 1, true) ~= nil
      and fx_name:find("v3", 1, true) ~= nil
  end

  local function FindSpeechGateV3Fx(track)
    local n = r.TrackFX_GetCount(track) or 0
    for i = 0, n - 1 do
      if IsSpeechGateV3Name(TryGetFxName(track, i)) then return i end
    end
    return -1
  end

  local function AddSpeechGateV3Candidate(track, fx_name)
    if not fx_name or fx_name == "" then return -1 end
    local idx = r.TrackFX_AddByName(track, fx_name, false, 1)
    if idx and idx >= 0 and IsSpeechGateV3Name(TryGetFxName(track, idx)) then
      return idx
    end
    -- If REAPER resolved an older same-named bridge, leave it untouched and
    -- report failure instead of silently using the wrong algorithm version.
    return -1
  end

  local function EnsureCockosMeterConfigured(track, fx_idx)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_M, 2)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_S, 1)
    r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_I, 1)
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

    local fx_idx = FindSpeechGateV3Fx(track)
    if fx_idx < 0 and allow_insert ~= false then
      -- Prefer the public v3 description name. The filename alias is only a
      -- fallback for REAPER installations that index JSFX by file name.
      fx_idx = AddSpeechGateV3Candidate(track, SPEECH_GATE_JSFX_NAME)
      if fx_idx < 0 then
        fx_idx = AddSpeechGateV3Candidate(track, SPEECH_GATE_FILE_NAME)
      end
    end
    if fx_idx >= 0 then
      local n_params = r.TrackFX_GetNumParams(track, fx_idx) or 0
      if n_params > SPEECH_OUT_VOICE_SCORE then
        return fx_idx, nil
      end
    end

    return -1, "SBP Speech Gate Bridge v3 not found/loaded (expected: " .. tostring(SPEECH_GATE_JSFX_NAME) .. ")"
  end

  local function GetParamNameSafe(track, fx_idx, pidx)
    local ok, a, b = pcall(r.TrackFX_GetParamName, track, fx_idx, pidx, "")
    if not ok then return "" end
    if type(a) == "string" and a ~= "" then return a:lower() end
    if type(b) == "string" and b ~= "" then return b:lower() end
    return ""
  end

  local function ResolveCockosOutputParam(track, fx_idx, fallback, patterns)
    local by_fx = cockos_output_param_cache[track]
    if not by_fx then
      by_fx = {}
      cockos_output_param_cache[track] = by_fx
    end
    if by_fx[fx_idx] and by_fx[fx_idx][fallback] ~= nil then
      return by_fx[fx_idx][fallback]
    end

    local pcount = r.TrackFX_GetNumParams(track, fx_idx) or 0
    local resolved = fallback
    -- Current Cockos loudness_meter exposes automation outputs as sliders
    -- 30..36 (zero-based 29..35). Older builds used the legacy 15/18..20
    -- positions, so names remain preferred and this is only a fallback.
    if pcount > 35 then
      if fallback == COCKOS_OUT_PEAK then resolved = 29 end
      if fallback == COCKOS_OUT_LUFS_M then resolved = 32 end
      if fallback == COCKOS_OUT_LUFS_S then resolved = 33 end
      if fallback == COCKOS_OUT_LUFS_I then resolved = 34 end
    end
    for p = 0, pcount - 1 do
      local name = GetParamNameSafe(track, fx_idx, p)
      local matched = false
      for i = 1, #(patterns or {}) do
        if name:find(patterns[i], 1, true) then
          resolved = p
          matched = true
          break
        end
      end
      if matched then break end
    end
    by_fx[fx_idx] = by_fx[fx_idx] or {}
    by_fx[fx_idx][fallback] = resolved
    return resolved
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

    local out_m = ResolveCockosOutputParam(track, fx_idx, COCKOS_OUT_LUFS_M, { "lufs-m (output)", "lufs-m" })
    local out_s = ResolveCockosOutputParam(track, fx_idx, COCKOS_OUT_LUFS_S, { "lufs-s (output)", "lufs-s" })
    local out_i = ResolveCockosOutputParam(track, fx_idx, COCKOS_OUT_LUFS_I, { "lufs-i (output)", "lufs-i" })
    local out_peak = ResolveCockosOutputParam(track, fx_idx, COCKOS_OUT_PEAK, { "peak/true peak", "peak (output)" })
    local m_db = ReadTrackFxPhysicalParam(track, fx_idx, out_m, -100.0, 0.0)
    local st_db = ReadTrackFxPhysicalParam(track, fx_idx, out_s, -100.0, 0.0)
    local i_db = ReadTrackFxPhysicalParam(track, fx_idx, out_i, -100.0, 0.0)
    local peak_db = ReadTrackFxPhysicalParam(track, fx_idx, out_peak, -150.0, 20.0)
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
    EnsureCockosMeterFx = EnsureCockosMeterFx,
    EnsureSpeechGateBridgeFx = EnsureSpeechGateBridgeFx
  }
end

return M
