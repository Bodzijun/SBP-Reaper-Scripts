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

function AutomationWriter.WriteOverwrite(track, targets, points, shape, tension, trim_mode)
  if not track then return 0 end
  if #targets == 0 or #points < 2 then return 0 end

  -- Default trim_mode to true if not specified
  if trim_mode == nil then trim_mode = true end

  local written = 0
  local start_t = points[1].time or points[1].t
  local end_t = points[#points].time or points[#points].t

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for _, target in ipairs(targets) do
    local env = target.env
    if env then
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
