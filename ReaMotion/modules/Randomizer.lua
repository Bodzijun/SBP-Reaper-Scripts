---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local Randomizer = {}

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

local function randomizePad(p)
  p.sx = math.random()
  p.sy = math.random()
  p.px = math.random()
  p.py = math.random()
  p.ex = math.random()
  p.ey = math.random()
end

-- Randomize all enabled components based on state.random settings
function Randomizer.Randomize(state, markDirty)
  math.randomseed(state.setup.random_seed or os.time())

  local s = state

  -- Pad A
  if s.random.pad_a and s.pads and s.pads.link_a then
    randomizePad(s.pads.link_a)
  end

  -- Pad B
  if s.random.pad_b and s.pads and s.pads.link_b then
    randomizePad(s.pads.link_b)
  end

  -- External Pad
  if s.random.external and type(s.external) == 'table' then
    if type(s.external.pad) == 'table' then
      randomizePad(s.external.pad)
    end
    -- Randomize external sources gain and enabled state
    if type(s.external.sources) == 'table' then
      for i, src in ipairs(s.external.sources) do
        if type(src) == 'table' then
          src.gain = math.random() * 0.5 + 0.5 -- 0.5 to 1.0
          src.enabled = (math.random() > 0.2)  -- 80% chance enabled
        end
      end
    end
  end

  -- Master LFO
  if s.random.lfo then
    if type(s.master_lfo) ~= 'table' then
      s.master_lfo = {
        enabled = false,
        rate = 2.0,
        depth = 0.6,
        offset = 0.5,
        shape = 0,
        mode = 0
      }
    end

    s.master_lfo.enabled = (math.random() > 0.35)
    s.master_lfo.rate = 0.1 + (math.random() * 11.9)
    s.master_lfo.depth = math.random()
    s.master_lfo.offset = math.random()
    s.master_lfo.shape = math.random(0, 4)
    s.master_lfo.mode = math.random(0, 2)
    s.master_lfo.rate_sweep = (math.random() * 2.0 - 1.0) -- -1.0 to 1.0
    s.master_lfo.depth_ramp = (math.random() * 2.0 - 1.0) -- -1.0 to 1.0
    s.master_lfo.invert = (math.random() > 0.7)

    if type(s.lfo) ~= 'table' then s.lfo = {} end
    if type(s.lfo.lfo1) ~= 'table' then
      s.lfo.lfo1 = { rate = 1.0, depth = 1.0, offset = 0.5, shape = 0, enabled = true }
    end
    if type(s.lfo.lfo2) ~= 'table' then
      s.lfo.lfo2 = { rate = 0.5, depth = 0.7, offset = 0.5, shape = 2, enabled = false }
    end

    s.lfo.lfo1.rate = math.random() * 8.0
    s.lfo.lfo1.depth = math.random()
    s.lfo.lfo1.offset = math.random()
    s.lfo.lfo1.shape = math.random(0, 4)
    s.lfo.lfo1.enabled = (math.random() > 0.3)
    s.lfo.lfo2.rate = math.random() * 8.0
    s.lfo.lfo2.depth = math.random()
    s.lfo.lfo2.offset = math.random()
    s.lfo.lfo2.shape = math.random(0, 4)
    s.lfo.lfo2.enabled = (math.random() > 0.5)
  end

  -- Master MSEG
  if s.random.mseg then
    if type(s.master_mseg) ~= 'table' then
      s.master_mseg = {
        mode = 0,
        points = 4,
        division = 2,
        bars = 4,
        manual_positions = { 0.0, 0.333, 0.667, 1.0 },
        curve_mode = 0,
        segment_shapes = {},
        values = {},
        apply_all_shapes = false
      }
    end
    local pts = math.random(2, 6)
    s.master_mseg.points = pts
    local vals = {}
    for i = 1, pts do
      vals[i] = math.random() * 0.8 + 0.1
    end
    s.master_mseg.values = vals
    s.master_mseg.curve_mode = math.random(0, 3)
    -- Redistribute manual positions
    local positions = {}
    for i = 1, pts do
      positions[i] = (i - 1) / (pts - 1)
    end
    s.master_mseg.manual_positions = positions
    -- Randomize segment shapes
    local shapes = {}
    for i = 1, pts - 1 do
      shapes[i] = math.random(0, 3)
    end
    s.master_mseg.segment_shapes = shapes
  end

  -- Independent LFO
  if s.random.ind_lfo then
    if type(s.independent_modulator) ~= 'table' then
      s.independent_modulator = {}
    end
    if type(s.independent_modulator.lfo) ~= 'table' then
      s.independent_modulator.lfo = {
        enabled = false,
        rate = 2.0,
        depth = 0.6,
        offset = 0.5,
        shape = 0,
        mode = 0,
        sync_to_bpm = false,
        random_steps = 8,
        sync_div_idx = 2,
        waveform_name = "Sine",
        phase = 0.0,
        random_seed = 1000,
        rate_sweep = 0.0
      }
    end

    local ind_lfo = s.independent_modulator.lfo
    ind_lfo.enabled = (math.random() > 0.35)
    ind_lfo.rate = 0.1 + (math.random() * 11.9)
    ind_lfo.depth = math.random()
    ind_lfo.offset = math.random()
    ind_lfo.shape = math.random(0, 4)
    ind_lfo.mode = math.random(0, 3)
    ind_lfo.waveform_name = "Sine"
    ind_lfo.phase = 0.0
    ind_lfo.random_seed = math.random(1000, 9999)
    ind_lfo.rate_sweep = (math.random() * 2.0 - 1.0)
    ind_lfo.depth_ramp = (math.random() * 2.0 - 1.0)
    ind_lfo.invert = (math.random() > 0.7)
  end

  -- Independent MSEG
  if s.random.ind_mseg then
    if type(s.independent_modulator) ~= 'table' then
      s.independent_modulator = {}
    end
    if type(s.independent_modulator.mseg) ~= 'table' then
      s.independent_modulator.mseg = {
        mode = 0,
        points = 2,
        division = 2,
        bars = 4,
        manual_positions = { 0.0, 1.0 },
        curve_mode = 0,
        segment_shapes = {},
        values = {},
        selected_segment = 1,
        apply_all_shapes = false
      }
    end

    local ind_mseg = s.independent_modulator.mseg
    local pts = math.random(2, 6)
    ind_mseg.points = pts
    local vals = {}
    for i = 1, pts do
      vals[i] = math.random() * 0.8 + 0.1
    end
    ind_mseg.values = vals
    ind_mseg.curve_mode = math.random(0, 3)

    -- Redistribute manual positions
    local positions = {}
    for i = 1, pts do
      positions[i] = (i - 1) / (pts - 1)
    end
    ind_mseg.manual_positions = positions

    -- Randomize segment shapes
    local shapes = {}
    for i = 1, pts - 1 do
      shapes[i] = math.random(0, 3)
    end
    ind_mseg.segment_shapes = shapes
    -- Randomize curve tension
    ind_mseg.curve_tension = (math.random() * 2.0 - 1.0) -- -1.0 to 1.0
  end

  -- Update random seed for next time
  s.setup.random_seed = (s.setup.random_seed or 1001) + 7

  if markDirty then
    markDirty()
  end

  return 'Randomized'
end

return Randomizer
