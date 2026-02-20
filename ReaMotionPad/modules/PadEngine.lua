local PadEngine = {}

local PI2 = math.pi * 2.0

local function clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

local function lerp(a, b, t)
  return a + ((b - a) * t)
end

function PadEngine.EvaluatePadY(pad, t)
  if not pad or not pad.enabled then return 0.5 end
  
  if pad.points and #pad.points >= 2 then
    local tt = clamp(t, 0.0, 1.0)
    local idx = 1
    for i = 1, #pad.points - 1 do
      if tt <= pad.points[i+1].x then
        idx = i
        break
      end
    end
    if idx >= #pad.points then idx = #pad.points - 1 end
    
    local p1 = pad.points[idx]
    local p2 = pad.points[idx + 1]
    local dx = p2.x - p1.x
    if dx < 0.0001 then return p1.y end
    
    local local_t = (tt - p1.x) / dx
    local dy = p2.y - p1.y
    return clamp(p1.y + dy * local_t, 0.0, 1.0)
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

function PadEngine.EvaluateLFO(lfo, t)
  if not lfo or not lfo.enabled then return 0.5 end
  local phase = ((t * (lfo.rate or 1.0)) + (lfo.offset or 0.0)) % 1.0
  local shape = lfo.shape or 0
  local raw = 0.0
  if shape == 0 then
    raw = math.sin(phase * PI2)
  elseif shape == 1 then
    raw = (phase < 0.5) and 1.0 or -1.0
  elseif shape == 2 then
    raw = (phase * 2.0) - 1.0
  else
    raw = 1.0 - (math.abs((phase * 2.0) - 1.0) * 2.0)
  end
  local depth = clamp(lfo.depth or 1.0, 0.0, 1.0)
  local val = 0.5 + (raw * 0.5 * depth)
  return clamp(val, 0.0, 1.0)
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
  if source_id == 3 then return PadEngine.EvaluatePadY(state.pads.link_c, t) end
  if source_id == 4 then return PadEngine.EvaluatePadY(state.external.pad, t) end
  if source_id == 5 then return PadEngine.EvaluateLFO(state.lfo.lfo1, t) end
  if source_id == 6 then return PadEngine.EvaluateLFO(state.lfo.lfo2, t) end
  if source_id == 7 then return PadEngine.EvaluateEnv(state.env.env1, t) end
  return 0.5
end

return PadEngine
