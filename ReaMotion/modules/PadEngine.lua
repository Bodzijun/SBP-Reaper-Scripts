---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local PadEngine = {}

local PI2 = math.pi * 2.0

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

local function lerp(a, b, t)
  return a + ((b - a) * t)
end

local function shapeTime(t, shape, tension)
  local tt = clamp(t, 0.0, 1.0)
  if shape == 1 then
    return tt * tt
  elseif shape == 2 then
    local inv = 1.0 - tt
    return 1.0 - (inv * inv)
  elseif shape == 3 then
    local k = 1.0 + (clamp(tension or 0.0, 0.0, 1.0) * 3.0)
    if tt <= 0.0 then return 0.0 end
    if tt >= 1.0 then return 1.0 end
    local a = tt ^ k
    local b = (1.0 - tt) ^ k
    return a / (a + b)
  elseif shape == 4 then
    local ten = clamp(tension or 0.0, -1.0, 1.0)
    local cp1 = (ten < 0) and -ten or 0.0
    local cp2 = (ten > 0) and (1.0 - ten) or 1.0
    local inv_t = 1.0 - tt
    return (3 * inv_t * inv_t * tt * cp1) + (3 * inv_t * tt * tt * cp2) + (tt * tt * tt)
  end
  return tt
end

function PadEngine.EvaluatePadY(pad, t)
  if not pad or not pad.enabled then return 0.5 end

  if pad.points and #pad.points >= 2 then
    local tt = clamp(t, 0.0, 1.0)
    local idx = 1
    for i = 1, #pad.points - 1 do
      if tt <= (pad.points[i + 1].x or 1.0) then
        idx = i
        break
      end
      idx = i
    end
    if idx >= #pad.points then idx = #pad.points - 1 end

    local p1 = pad.points[idx]
    local p2 = pad.points[idx + 1]
    local x1 = clamp(p1.x or 0.0, 0.0, 1.0)
    local x2 = clamp(p2.x or 1.0, 0.0, 1.0)
    local dx = math.max(0.0001, x2 - x1)
    local local_t = clamp((tt - x1) / dx, 0.0, 1.0)

    local shape = pad.segment_shapes and pad.segment_shapes[idx] or pad.curve_mode or 0
    local tension = pad.segment_tensions and pad.segment_tensions[idx] or pad.curve_tension or 0.0
    local st = shapeTime(local_t, shape, tension)

    local dy = p2.y - p1.y
    return clamp(p1.y + dy * st, 0.0, 1.0)
  end

  local sx = clamp(pad.sx or 0.0, 0.0, 1.0)
  local sy = clamp(pad.sy or 0.0, 0.0, 1.0)
  local px = clamp(pad.px or 0.5, 0.0, 1.0)
  local py = clamp(pad.py or 0.5, 0.0, 1.0)
  local ex = clamp(pad.ex or 1.0, 0.0, 1.0)
  local ey = clamp(pad.ey or 1.0, 0.0, 1.0)

  t = clamp(t, 0.0, 1.0)

  if t <= px then
    if px < 0.0001 then return sy end
    local local_t = t / px
    return lerp(sy, py, local_t)
  else
    if (1.0 - px) < 0.0001 then return py end
    local local_t = (t - px) / (1.0 - px)
    return lerp(py, ey, local_t)
  end
end

function PadEngine.EvaluatePadAxis(pad, t, axis)
  if not pad or not pad.enabled then return 0.5 end

  if axis == 0 then
    local mid_t = 0.5
    if pad.points and #pad.points >= 2 then
      mid_t = clamp(t, 0.0, 1.0)
    end
    return mid_t
  else
    return PadEngine.EvaluatePadY(pad, t)
  end
end

function PadEngine.EvaluatePadSide(pad, t, side)
  if not pad or not pad.enabled then return 0.5 end

  t = clamp(t, 0.0, 1.0)
  local y_val = PadEngine.EvaluatePadY(pad, t)

  if side == 0 then
    if pad.points and #pad.points >= 1 then
      return pad.points[1].x
    end
    local sx = clamp(pad.sx or 0.0, 0.0, 1.0)
    return sx
  elseif side == 1 then
    if pad.points and #pad.points >= 1 then
      return pad.points[#pad.points].x
    end
    local ex = clamp(pad.ex or 1.0, 0.0, 1.0)
    return ex
  elseif side == 2 then
    return y_val
  else
    return 1.0 - y_val
  end
end

function PadEngine.EvaluateMorph(state, t)
  return PadEngine.EvaluatePadY(state.pads.morph, t)
end

local function evaluateLfoShapeAt(shape, phase, random_steps)
  local p = phase % 1.0
  if shape == 1 then
    if p < 0.5 then
      return p * 2.0
    end
    return 2.0 - (p * 2.0)
  elseif shape == 2 then
    return p
  elseif shape == 3 then
    return 1.0 - p
  elseif shape == 4 then
    return p < 0.5 and 1.0 or 0.0
  elseif shape == 5 then
    local steps = math.max(2, math.min(32, math.floor(tonumber(random_steps) or 8)))
    local idx = math.floor(p * steps)
    local hash = math.sin((idx + 1) * 12.9898) * 43758.5453
    local rand = hash - math.floor(hash)
    return clamp(rand, 0.0, 1.0)
  end
  return 0.5 + (0.5 * math.sin(p * math.pi * 2.0))
end

function PadEngine.EvaluateLFO(lfo, t)
  if not lfo or not lfo.enabled then return clamp(lfo and lfo.offset or 0.5, 0.0, 1.0) end

  local t_norm = clamp(t, 0.0, 1.0)
  local rate_sweep = clamp(lfo.rate_sweep or 0.0, -1.0, 1.0)
  local base_rate = math.max(0.05, lfo.rate or 1.0)

  -- Calculate phase by integrating the varying rate from 0 to t_norm
  -- Effective rate function: rate(x) = base_rate * (1.0 + rate_sweep * (x - 0.5) * 2.0)
  -- Phase is the integral of effective rate with respect to time x:
  -- Integral(rate(x) dx) = base_rate * [x + rate_sweep * (x^2 - x)] + C
  -- Since we integrate from 0 to t_norm, C = 0.
  local phase_integrated = base_rate * (t_norm + rate_sweep * (t_norm * t_norm - t_norm))
  local phase = (phase_integrated + (lfo.phase_offset or 0.0)) % 1.0

  local wave = evaluateLfoShapeAt(lfo.shape or 0, phase, lfo.random_steps or 8)
  if lfo.invert then
    wave = 1.0 - wave
  end

  local depth = clamp(lfo.depth or 1.0, 0.0, 1.0)
  local depth_ramp = clamp(lfo.depth_ramp or 0.0, -1.0, 1.0)

  -- Calculate dynamic depth based on ramp
  -- negative ramp: starts at 100% depth and goes to 0%
  -- positive ramp: starts at 0% depth and goes to 100%
  local effective_depth = depth
  if depth_ramp ~= 0.0 then
    if depth_ramp > 0 then
      -- Fade in (0 to 1 scaling)
      local fade = math.min(1.0, t_norm / depth_ramp)
      effective_depth = depth * fade
    else
      -- Fade out (1 to 0 scaling)
      local ramp_abs = math.abs(depth_ramp)
      local fade = 1.0 - math.min(1.0, t_norm / ramp_abs)
      effective_depth = depth * fade
    end
  end

  -- LFO depth scales around its neutral value (0.5)
  -- LFO offset moves the entire waveform
  local val = (lfo.offset or 0.5) + ((wave - 0.5) * effective_depth)
  return clamp(val, 0.0, 1.0)
end

function PadEngine.EvaluateExternalPadXY(pad, t, positions)
  -- Для External pad повертає (x, y) координати для прогресу t [0..1] вздовж траєкторії
  if not pad or not pad.enabled then return 0.5, 0.5 end

  -- Points mode: pad.points це масив точок з (x, y) координатами
  if pad.points and #pad.points >= 2 then
    local tt = clamp(t, 0.0, 1.0)
    local idx = 1

    -- Якщо передані позиції сегментації - використовуємо їх як таймінг
    if type(positions) == 'table' and #positions == #pad.points then
      for i = 1, #positions - 1 do
        if tt <= (positions[i + 1] or 1.0) then
          idx = i
          break
        end
        idx = i
      end
      if idx >= #positions then idx = #positions - 1 end

      local p1 = pad.points[idx]
      local p2 = pad.points[idx + 1]
      local t1 = clamp(positions[idx] or 0.0, 0.0, 1.0)
      local t2 = clamp(positions[idx + 1] or 1.0, 0.0, 1.0)
      local dx = math.max(0.0001, t2 - t1)
      local local_t = clamp((tt - t1) / dx, 0.0, 1.0)

      -- Застосувати shape з сегментації
      local x1 = clamp(p1.x or 0.5, 0.0, 1.0)
      local x2 = clamp(p2.x or 0.5, 0.0, 1.0)
      local y1 = clamp(p1.y or 0.5, 0.0, 1.0)
      local y2 = clamp(p2.y or 0.5, 0.0, 1.0)

      local x_out = lerp(x1, x2, local_t)
      local y_out = lerp(y1, y2, local_t)

      return clamp(x_out, 0.0, 1.0), clamp(y_out, 0.0, 1.0)
    end

    -- Fallback: використовувати x як таймінг (стара логіка)
    for i = 1, #pad.points - 1 do
      if tt <= (pad.points[i + 1].x or 1.0) then
        idx = i
        break
      end
      idx = i
    end
    if idx >= #pad.points then idx = #pad.points - 1 end

    local p1 = pad.points[idx]
    local p2 = pad.points[idx + 1]
    local x1 = clamp(p1.x or 0.0, 0.0, 1.0)
    local x2 = clamp(p2.x or 1.0, 0.0, 1.0)
    local y1 = clamp(p1.y or 0.5, 0.0, 1.0)
    local y2 = clamp(p2.y or 0.5, 0.0, 1.0)

    local dx = math.max(0.0001, x2 - x1)
    local local_t = clamp((tt - x1) / dx, 0.0, 1.0)

    local x_out = lerp(x1, x2, local_t)
    local y_out = lerp(y1, y2, local_t)

    return clamp(x_out, 0.0, 1.0), clamp(y_out, 0.0, 1.0)
  end

  -- Fallback: Vector mode (для сумісності зі старими slate)
  local sx = clamp(pad.sx or 0.0, 0.0, 1.0)
  local sy = clamp(pad.sy or 0.0, 0.0, 1.0)
  local px = clamp(pad.px or 0.5, 0.0, 1.0)
  local py = clamp(pad.py or 0.5, 0.0, 1.0)
  local ex = clamp(pad.ex or 1.0, 0.0, 1.0)
  local ey = clamp(pad.ey or 1.0, 0.0, 1.0)

  t = clamp(t, 0.0, 1.0)

  local x, y
  if t <= px then
    if px < 0.0001 then
      x, y = sx, sy
    else
      local local_t = t / px
      x = lerp(sx, px, local_t)
      y = lerp(sy, py, local_t)
    end
  else
    if (1.0 - px) < 0.0001 then
      x, y = px, py
    else
      local local_t = (t - px) / (1.0 - px)
      x = lerp(px, ex, local_t)
      y = lerp(py, ey, local_t)
    end
  end

  return clamp(x, 0.0, 1.0), clamp(y, 0.0, 1.0)
end

function PadEngine.EvaluateEnv(env_cfg, t)
  if not env_cfg or not env_cfg.enabled then return 0.5 end
  local a = clamp(env_cfg.attack or 0.1, 0.01, 0.95)
  local d = clamp(env_cfg.decay or 0.2, 0.01, 0.95)
  local s = clamp(env_cfg.sustain or 0.7, 0.0, 1.0)
  local r = clamp(env_cfg.release or 0.2, 0.01, 0.95)

  local attack_end = a
  local decay_end = clamp(a + d, 0.01, 0.99)
  local release_start = clamp(1.0 - r, decay_end, 0.99)

  if t <= attack_end then
    return t / attack_end
  end
  if t <= decay_end then
    local lt = (t - attack_end) / math.max(0.001, decay_end - attack_end)
    return 1.0 + (s - 1.0) * lt
  end
  if t <= release_start then
    return s
  end
  local rt = (t - release_start) / math.max(0.001, 1.0 - release_start)
  return s * (1.0 - rt)
end

function PadEngine.EvaluateSource(state, source_id, t)
  if source_id == 1 then return PadEngine.EvaluatePadY(state.pads.link_a, t) end
  if source_id == 2 then return PadEngine.EvaluatePadY(state.pads.link_b, t) end
  if source_id == 3 then return PadEngine.EvaluatePadY(state.external.pad, t) end
  if source_id == 4 then return PadEngine.EvaluateLFO(state.lfo.lfo1, t) end
  if source_id == 5 then return PadEngine.EvaluateLFO(state.lfo.lfo2, t) end
  if source_id == 6 then return PadEngine.EvaluateEnv(state.env.env1, t) end
  return 0.5
end

return PadEngine
