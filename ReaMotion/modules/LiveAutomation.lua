---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local LiveAutomation = {}

local r = reaper

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Live automation state
local live_state = {
  enabled = false,
  last_update_frame = -1,
  tick = 0,
  targets = {},
  link_a_targets = {},
  link_b_targets = {},
  modulator_targets = {},
  master_target = nil,
  track = nil,
  last_sel_env = nil,
  initialized = false
}

-- Check if FX still exists on track
local function validateFXExists(track, fx_index)
  if not track then return false end
  -- Indices < 0 (like -1) represent standard track envelopes (Volume, Pan, etc.)
  if fx_index < 0 then return true end
  local fx_count = r.TrackFX_GetCount(track)
  return fx_index < fx_count
end

-- Rebuild live automation targets
function LiveAutomation.RebuildTargets(state, track, interaction, buildFunctions)
  if not track or not state then return end

  live_state.track = track

  -- External targets (only if Ext checkbox enabled)
  if interaction.write_auto.external and buildFunctions.collectWriteTargets then
    live_state.targets = buildFunctions.collectWriteTargets(track, false)
  else
    live_state.targets = {}
  end

  -- Link A targets
  if interaction.write_auto.pad_a and buildFunctions.buildLinkTargets and state.pads and state.pads.link_a then
    live_state.link_a_targets = buildFunctions.buildLinkTargets(state.pads.link_a, track, true)
  else
    live_state.link_a_targets = {}
  end

  -- Link B targets
  if interaction.write_auto.pad_b and buildFunctions.buildLinkTargets and state.pads and state.pads.link_b then
    live_state.link_b_targets = buildFunctions.buildLinkTargets(state.pads.link_b, track, true)
  else
    live_state.link_b_targets = {}
  end

  -- Independent modulator targets
  if buildFunctions.buildIndependentModulatorTargets then
    live_state.modulator_targets = buildFunctions.buildIndependentModulatorTargets(track, false)
  else
    live_state.modulator_targets = {}
  end

  -- Master Vol target (combined Master LFO + MSEG)
  if interaction.write_auto.master_vol and buildFunctions.collectMasterMSEGTarget then
    live_state.master_target = buildFunctions.collectMasterMSEGTarget(track, false)
  else
    live_state.master_target = nil
  end

  live_state.last_update_frame = -1
  live_state.tick = 0
end

-- Update live automation
function LiveAutomation.Update(track_in, state, interaction, buildFunctions, getPadPointList, getMasterOutputPointList,
                               buildIndependentOutputPointList, buildIndependentMSEGPointList, markDirty)
  if not live_state.enabled then
    return
  end

  local track = track_in or live_state.track
  if not track or not r.ValidatePtr(track, 'MediaTrack*') then
    return -- Just skip if no track
  end

  -- Detect if selected envelope changed to follow it in real-time
  local sel_env = r.GetSelectedEnvelope(0)
  local sel_env_changed = (sel_env ~= live_state.last_sel_env)

  -- Rebuild targets when track changed, selection changed, or dirty flag is set
  local needs_rebuild = (not live_state.initialized or
    track ~= live_state.track or
    sel_env_changed or
    (state and state.dirty))

  if needs_rebuild then
    live_state.initialized = true
    live_state.last_sel_env = sel_env
    if needs_rebuild or not live_state.targets then
      -- First time or track changed - full rebuild
      live_state.track = track
      -- Collect External targets only if Ext checkbox is enabled
      if interaction.write_auto.external then
        live_state.targets = buildFunctions.collectWriteTargets(track, false)
      else
        live_state.targets = {}
      end
      -- Link A/B targets (always collected if checkboxes enabled)
      if interaction.write_auto.pad_a then
        live_state.link_a_targets = buildFunctions.buildLinkTargets(state.pads.link_a, track, true)
      else
        live_state.link_a_targets = {}
      end
      if interaction.write_auto.pad_b then
        live_state.link_b_targets = buildFunctions.buildLinkTargets(state.pads.link_b, track, true)
      else
        live_state.link_b_targets = {}
      end
      -- Independent modulator targets
      live_state.modulator_targets = buildFunctions.buildIndependentModulatorTargets(track, false)
      -- Master Vol target (only if checkbox enabled)
      if interaction.write_auto.master_vol then
        live_state.master_target = buildFunctions.collectMasterMSEGTarget(track, false)
      else
        live_state.master_target = nil
      end
      live_state.last_update_frame = -1
      live_state.tick = 0
    end
    if state then state.dirty = false end -- Clear dirty after rebuild
  end

  live_state.tick = (live_state.tick or 0) + 1
  if (live_state.tick % 2) ~= 0 then return end -- Update every other frame

  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if end_t <= start_t then
    -- FALLBACK: Use 4 beats (1 measure) based on tempo if no selection
    local bpm = r.Master_GetTempo()
    local beat_len = 60.0 / math.max(1, bpm)
    start_t = r.GetCursorPosition()
    end_t = start_t + (beat_len * 4.0)
  end

  local len = math.max(0.001, end_t - start_t)
  local play_state = r.GetPlayState()
  local now = (play_state & 1) == 1 and r.GetPlayPosition() or r.GetCursorPosition()
  local t_live = clamp((now - start_t) / len, 0.0, 1.0)

  -- Update External pad automation
  if interaction.write_auto.external and #live_state.targets > 0 then
    local points_for_live = getPadPointList(state.external.pad, start_t, end_t)
    for idx, target in ipairs(live_state.targets) do
      if target.env and target.fx_index and target.param_index then
        -- Validate FX still exists
        if not validateFXExists(track, target.fx_index) then
          live_state.targets = {}
          if markDirty then state.dirty = true end
          return
        end

        -- Clear and rewrite envelope points
        local ok_del = pcall(r.DeleteEnvelopePointRange, target.env, start_t - 0.001, end_t + 0.001)
        if not ok_del then
          live_state.targets = {}
          return
        end

        for _, point in ipairs(points_for_live) do
          local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
          local time = point.time or (start_t + (len * t_norm))
          local val = target.value_at(t_norm)
          local shape = tonumber(point.env_shape) or 0
          local tension = tonumber(point.env_tension) or 0.0
          r.InsertEnvelopePoint(target.env, time, val, shape, tension, true, true)
        end

        r.Envelope_SortPoints(target.env)

        -- Update JSFX parameter in real time
        local val_live = target.value_at(t_live)
        local _, fx_name = r.TrackFX_GetFXName(track, target.fx_index)
        if fx_name and fx_name:sub(1, 3) == 'JS:' then
          r.TrackFX_SetParam(track, target.fx_index, target.param_index, val_live)
        else
          r.TrackFX_SetParamNormalized(track, target.fx_index, target.param_index, clamp(val_live, 0.0, 1.0))
        end
      end
    end
  end

  -- Update Link A automation
  if #live_state.link_a_targets > 0 then
    local link_a_points = getPadPointList(state.pads.link_a, start_t, end_t)
    for _, target in ipairs(live_state.link_a_targets) do
      local env = target.env
      local val_live = target.value_at(t_live)

      -- 1. Real-time parameter update (Audible movement)
      if target.target_type == 'track_vol' then
        r.SetMediaTrackInfo_Value(track, 'D_VOL', val_live)
      elseif target.target_type == 'track_pan' then
        r.SetMediaTrackInfo_Value(track, 'D_PAN', val_live)
      elseif target.fx_index ~= nil and target.param_index ~= nil then
        if validateFXExists(track, target.fx_index) then
          r.TrackFX_SetParamNormalized(track, target.fx_index, target.param_index, clamp(val_live, 0.0, 1.0))
        end
      end

      -- 2. Visual Envelope update
      if env and r.ValidatePtr(env, 'TrackEnvelope*') then
        r.DeleteEnvelopePointRange(env, start_t - 0.001, end_t + 0.001)
        for _, point in ipairs(link_a_points) do
          local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
          local time = point.time or (start_t + (len * t_norm))
          local val = target.value_at(t_norm)
          local shape = tonumber(point.env_shape) or 0
          local tension = tonumber(point.env_tension) or 0.0
          r.InsertEnvelopePoint(env, time, val, shape, tension, true, true)
        end
        r.Envelope_SortPoints(env)
      end
    end
  end

  -- Update Link B automation
  if #live_state.link_b_targets > 0 then
    local link_b_points = getPadPointList(state.pads.link_b, start_t, end_t)
    for _, target in ipairs(live_state.link_b_targets) do
      local env = target.env
      local val_live = target.value_at(t_live)

      -- 1. Real-time parameter update (Audible movement)
      if target.target_type == 'track_vol' then
        r.SetMediaTrackInfo_Value(track, 'D_VOL', val_live)
      elseif target.target_type == 'track_pan' then
        r.SetMediaTrackInfo_Value(track, 'D_PAN', val_live)
      elseif target.fx_index ~= nil and target.param_index ~= nil then
        if validateFXExists(track, target.fx_index) then
          r.TrackFX_SetParamNormalized(track, target.fx_index, target.param_index, clamp(val_live, 0.0, 1.0))
        end
      end

      -- 2. Visual Envelope update
      if env and r.ValidatePtr(env, 'TrackEnvelope*') then
        r.DeleteEnvelopePointRange(env, start_t - 0.001, end_t + 0.001)
        for _, point in ipairs(link_b_points) do
          local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
          local time = point.time or (start_t + (len * t_norm))
          local val = target.value_at(t_norm)
          local shape = tonumber(point.env_shape) or 0
          local tension = tonumber(point.env_tension) or 0.0
          r.InsertEnvelopePoint(env, time, val, shape, tension, true, true)
        end
        r.Envelope_SortPoints(env)
      end
    end
  end

  -- Update Independent Modulator automation
  if #live_state.modulator_targets > 0 then
    local indep_points_lfo = buildIndependentOutputPointList(start_t, end_t)
    local indep_points_mseg = buildIndependentMSEGPointList(start_t, end_t)

    for _, target in ipairs(live_state.modulator_targets) do
      if target.is_midi_take_cc and target.take then
        local take = target.take
        local lane = target.cc_lane
        local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, start_t)
        local end_ppq = r.MIDI_GetPPQPosFromProjTime(take, end_t)

        -- Delete existing in range
        r.MIDI_DisableSort(take)
        local _, _, ccevtcnt, _ = r.MIDI_CountEvts(take)
        for i = ccevtcnt - 1, 0, -1 do
          local ok, sel, mut, ppq, chanmsg, chan, msg2, msg3 = r.MIDI_GetCC(take, i)
          if ok and ppq >= start_ppq and ppq <= end_ppq then
            local event_lane = (chanmsg == 0xB0 and msg2) or (chanmsg == 0xE0 and 0x201) or (chanmsg == 0xD0 and 0x203) or
                -1
            if event_lane == lane then r.MIDI_DeleteCC(take, i) end
          end
        end

        -- Insert new points
        local indep_points = (target.point_type == 'mseg') and indep_points_mseg or indep_points_lfo
        for i, point in ipairs(indep_points) do
          local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
          local time = point.time or (start_t + (len * t_norm))
          local ppq = r.MIDI_GetPPQPosFromProjTime(take, time)
          local v = target.value_at(t_norm)

          if lane == 0x201 then -- Pitch
            local lsb, msb = v % 128, math.floor(v / 128)
            r.MIDI_InsertCC(take, false, false, ppq, 0xE0, 0, lsb, msb)
          elseif lane == 0x203 then -- Ch Pressure
            r.MIDI_InsertCC(take, false, false, ppq, 0xD0, 0, v, 0)
          else                      -- Standard CC
            r.MIDI_InsertCC(take, false, false, ppq, 0xB0, 0, lane, v)
          end

          -- Apply shape if it's not the last point
          if i < #indep_points then
            local p_shape = point.shape or 0
            local p_tension = point.tension or 0.0

            local p_cc_shape = 0
            if p_shape == 0 then
              p_cc_shape = 1 -- Linear
            elseif p_shape == 1 then
              p_cc_shape = 4 -- Ease In -> Fast end
            elseif p_shape == 2 then
              p_cc_shape = 3 -- Ease Out -> Fast start
            elseif p_shape == 3 then
              p_cc_shape = 2 -- S-Curve -> Slow start/end
            elseif p_shape == 4 then
              p_cc_shape = 5 -- Bezier
            elseif p_shape == 5 then
              p_cc_shape = 0 -- Square
            else
              p_cc_shape = 1
            end

            local _, _, ccevtcnt = r.MIDI_CountEvts(take)
            if ccevtcnt > 0 then
              r.MIDI_SetCCShape(take, ccevtcnt - 1, p_cc_shape, p_tension, true)
            end
          end
        end
        r.MIDI_Sort(take)
      elseif target.env and target.fx_index and target.param_index then
        if not validateFXExists(track, target.fx_index) then
          live_state.modulator_targets = {}
          if markDirty then state.dirty = true end
          break
        end

        local ok_del = pcall(r.DeleteEnvelopePointRange, target.env, start_t - 0.001, end_t + 0.001)
        if not ok_del then
          live_state.modulator_targets = {}
          break
        end

        local indep_points = (target.point_type == 'mseg') and indep_points_mseg or indep_points_lfo

        -- Write points
        for _, point in ipairs(indep_points) do
          local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
          local time = point.time or (start_t + (len * t_norm))
          local val = target.value_at(t_norm)
          local shape = tonumber(point.env_shape) or 0
          local tension = tonumber(point.env_tension) or 0.0
          r.InsertEnvelopePoint(target.env, time, val, shape, tension, true, true)
        end
        r.Envelope_SortPoints(target.env)

        local val_live = target.value_at(t_live)
        local val_live_norm = (target.value_at_norm and target.value_at_norm(t_live)) or val_live

        if target.fx_index and target.fx_index >= 0 then
          -- FX parameter movement (standard 0..1 normalized)
          r.TrackFX_SetParamNormalized(track, target.fx_index, target.param_index, clamp(val_live_norm, 0.0, 1.0))
        else
          -- Track envelope movement (Volume, Pan, etc. physical values)
          if target.param_index == 0 then     -- Volume
            r.SetMediaTrackInfo_Value(track, 'D_VOL', val_live)
          elseif target.param_index == 1 then -- Pan
            r.SetMediaTrackInfo_Value(track, 'D_PAN', val_live)
          elseif target.param_index == 2 then -- Width
            r.SetMediaTrackInfo_Value(track, 'D_WIDTH', val_live)
          elseif target.param_index == 3 then -- Mute
            r.SetMediaTrackInfo_Value(track, 'B_MUTE', (val_live > 0.5 and 1 or 0))
          end
        end
      end
    end
  end

  -- Update Master MSEG automation
  if live_state.master_target and live_state.master_target.env then
    local master_points = getMasterOutputPointList(start_t, end_t)
    local ok_del = pcall(r.DeleteEnvelopePointRange, live_state.master_target.env, start_t - 0.001, end_t + 0.001)
    if not ok_del then
      live_state.master_target = nil
      return
    end

    for _, point in ipairs(master_points) do
      local t_norm = clamp(point.t or 0.0, 0.0, 1.0)
      local time = point.time or (start_t + (len * t_norm))
      local val = live_state.master_target.value_at(t_norm)
      local shape = tonumber(point.env_shape) or 0
      local tension = tonumber(point.env_tension) or 0.0
      r.InsertEnvelopePoint(live_state.master_target.env, time, val, shape, tension, true, true)
    end

    r.Envelope_SortPoints(live_state.master_target.env)

    -- Update Master parameter in real time
    local m = live_state.master_target
    if m.fx_index and m.param_index then
      local val_live = m.value_at(t_live)
      local _, min_val, max_val = r.TrackFX_GetParamEx(track, m.fx_index, m.param_index)
      local denom = math.max(0.000001, (max_val - min_val))
      local norm = clamp((val_live - min_val) / denom, 0.0, 1.0)
      r.TrackFX_SetParam(track, m.fx_index, m.param_index, norm)
    end
  end

  r.UpdateArrange()
end

-- Enable/disable live automation
function LiveAutomation.SetEnabled(enabled, track)
  live_state.enabled = enabled
  if enabled and track then
    live_state.track = track -- Set track when enabling
  end
  if not enabled then
    live_state.targets = {}
    live_state.link_a_targets = {}
    live_state.link_b_targets = {}
    live_state.modulator_targets = {}
    live_state.master_target = nil
  end
end

-- Get current enabled state
function LiveAutomation.IsEnabled()
  return live_state.enabled
end

-- Clear all targets
function LiveAutomation.ClearTargets()
  live_state.targets = {}
  live_state.link_a_targets = {}
  live_state.link_b_targets = {}
  live_state.modulator_targets = {}
  live_state.master_target = nil
end

return LiveAutomation
