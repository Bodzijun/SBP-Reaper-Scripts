---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local AutomationWriter = {}
local r = reaper

local function clearRange(env, start_t, end_t)
  if not env then return end
  local point_count = r.CountEnvelopePoints(env)
  for i = point_count - 1, 0, -1 do
    local ok, time, val, shape, tension = r.GetEnvelopePoint(env, i)
    if ok and time ~= nil and time >= start_t and time <= end_t then
      r.DeleteEnvelopePointEx(env, -1, i)
    end
  end
end

function AutomationWriter.MapEnvelopeShape(shape)
  -- Map our internal shape IDs to REAPER envelope shape IDs
  -- Our UI:     0=Linear, 1=Ease In, 2=Ease Out, 3=S-Curve, 4=Bezier, 5=Square
  -- REAPER API: 0=Linear, 1=Square, 2=Slow start/end (S-Curve), 3=Fast start (Ease Out), 4=Fast end (Ease In), 5=Bezier
  if shape == 1 then
    return 4 -- Ease In -> Fast end
  elseif shape == 2 then
    return 3 -- Ease Out -> Fast start
  elseif shape == 3 then
    return 2 -- S-Curve -> Slow start/end
  elseif shape == 4 then
    return 5 -- Bezier -> Bezier
  elseif shape == 5 then
    return 1 -- Square -> Square
  end
  return 0   -- Linear -> Linear
end

local function clearMIDIRange(take, lane, start_t, end_t)
  if not take then return end
  local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, start_t)
  local end_ppq = r.MIDI_GetPPQPosFromProjTime(take, end_t)

  -- CC lane types: 0-127=CC, 0x201=pitch, 0x203=ch pressure
  local is_pitch = (lane == 0x201)
  local is_press = (lane == 0x203)

  local _, _, ccevtcnt, _ = r.MIDI_CountEvts(take)
  for i = ccevtcnt - 1, 0, -1 do
    local ok, sel, mut, ppq, chanmsg, chan, msg2, msg3 = r.MIDI_GetCC(take, i)
    if ok and ppq >= start_ppq and ppq <= end_ppq then
      local event_lane = -1
      if chanmsg == 0xB0 then
        event_lane = msg2  -- standard CC
      elseif chanmsg == 0xE0 then
        event_lane = 0x201 -- pitch
      elseif chanmsg == 0xD0 then
        event_lane = 0x203 -- channel pressure
      end

      if event_lane == lane then
        r.MIDI_DeleteCC(take, i)
      end
    end
  end
end

function AutomationWriter.WriteOverwrite(track, targets, points, shape, tension, trim_mode)
  if #targets == 0 or #points < 2 then return 0 end

  -- Default trim_mode to true if not specified
  if trim_mode == nil then trim_mode = true end

  local written = 0
  local start_t = points[1].time or points[1].t
  local end_t = points[#points].time or points[#points].t

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for _, target in ipairs(targets) do
    if target.is_midi_take_cc and target.take then
      local take = target.take
      local lane = target.cc_lane
      if trim_mode then
        clearMIDIRange(take, lane, start_t, end_t)
      end

      r.MIDI_DisableSort(take)

      for i, p in ipairs(points) do
        local v = target.value_at(p.t or 0)
        local p_time = p.time or p.t
        local ppq = r.MIDI_GetPPQPosFromProjTime(take, p_time)

        if lane == 0x201 then -- Pitch
          local lsb = v % 128
          local msb = math.floor(v / 128)
          r.MIDI_InsertCC(take, false, false, ppq, 0xE0, 0, lsb, msb)
        elseif lane == 0x203 then -- Ch Pressure
          r.MIDI_InsertCC(take, false, false, ppq, 0xD0, 0, v, 0)
        else                      -- Standard CC
          r.MIDI_InsertCC(take, false, false, ppq, 0xB0, 0, lane, v)
        end

        -- Apply shape if it's not the last point
        if i < #points then
          local p_shape = p.shape ~= nil and p.shape or (shape or 0)
          local p_tension = p.tension ~= nil and p.tension or (tension or 0.0)

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

        written = written + 1
      end
      r.MIDI_Sort(take)
    elseif target.env then
      local env = target.env
      -- Clear existing points in range only if trim_mode is enabled
      if trim_mode then
        clearRange(env, start_t, end_t)
      end
      for _, p in ipairs(points) do
        local v = target.value_at(p.t or 0)
        local p_time = p.time or p.t
        local p_shape = p.env_shape ~= nil and p.env_shape or
            (p.shape ~= nil and AutomationWriter.MapEnvelopeShape(p.shape) or (shape or 0))
        local p_tension = p.env_tension ~= nil and p.env_tension or (p.tension ~= nil and p.tension or (tension or 0.0))
        r.InsertEnvelopePoint(env, p_time, v, p_shape, p_tension, true, true)
        written = written + 1
      end
      r.Envelope_SortPoints(env)
    end
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("SBP ReaMotion Pad: Write Automation", -1)
  r.UpdateArrange()
  return written
end

return AutomationWriter
