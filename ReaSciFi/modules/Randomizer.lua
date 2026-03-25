---@diagnostic disable: undefined-field
-- Randomizes synth parameters respecting rand_masks flags.
-- Each mask group covers logically related parameters.
-- Family randomization (rand_masks.family) is opt-in and off by default
-- so users don't accidentally jump to an unrelated sound type.

local Randomizer = {}

local function rf(lo, hi)
  return lo + math.random() * (hi - lo)
end

local function ri(lo, hi)
  return math.floor(lo + math.random() * (hi - lo + 0.9999))
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Total family count including new ones (0..12).
local FAMILY_COUNT = 13

local STYLE_RANGES = {
  [0] = { -- Mild
    intensity = { 0.45, 0.85 }, color = { 0.25, 0.85 }, pitch = { -7.0, 7.0 }, drive = { 0.00, 0.30 },
    character = { 0.25, 0.70 },
    e2_grain_mix = { 0.30, 0.70 }, e2_spectral_mix = { 0.30, 0.70 }, e2_reverse_mix = { 0.28, 0.68 }, e2_safety = { 0.55, 0.90 }, e2_cpu_quality = { 0.50, 1.00 },
    gain_digital = { 0.60, 1.00 },
    complexity = { 0.20, 0.75 }, pulse_rate = { 1.0, 7.5 }, pad_timbre = { 0.20, 0.80 }, gain_packet = { 0.45, 1.00 },
    dirt = { 0.00, 0.50 }, gain_noise = { 0.25, 0.90 },
    motion = { 0.05, 0.65 }, lfo_rate = { 0.20, 5.00 }, lfo_depth = { 0.00, 0.45 },
    lfo2_rate = { 0.20, 5.00 }, lfo2_depth = { 0.00, 0.45 }, mseg_depth = { 0.00, 0.45 }, pad_motion = { 0.20, 0.80 },
    chaos_mix = { 0.00, 0.45 }, gain_chaos = { 0.20, 0.85 },
    tail = { 0.10, 0.80 }, spread = { 0.10, 0.80 }, gain_resonator = { 0.45, 1.00 }
  },
  [1] = { -- Creative
    intensity = { 0.30, 1.00 }, color = { 0.00, 1.00 }, pitch = { -12.0, 12.0 }, drive = { 0.00, 0.55 },
    character = { 0.10, 0.90 },
    e2_grain_mix = { 0.10, 0.95 }, e2_spectral_mix = { 0.10, 0.95 }, e2_reverse_mix = { 0.10, 0.95 }, e2_safety = { 0.35, 1.00 }, e2_cpu_quality = { 0.00, 1.00 },
    gain_digital = { 0.45, 1.00 },
    complexity = { 0.10, 0.90 }, pulse_rate = { 0.5, 10.0 }, pad_timbre = { 0.00, 1.00 }, gain_packet = { 0.35, 1.00 },
    dirt = { 0.00, 0.80 }, gain_noise = { 0.20, 1.00 },
    motion = { 0.00, 0.85 }, lfo_rate = { 0.10, 8.00 }, lfo_depth = { 0.00, 0.70 },
    lfo2_rate = { 0.10, 8.00 }, lfo2_depth = { 0.00, 0.70 }, mseg_depth = { 0.00, 0.70 }, pad_motion = { 0.00, 1.00 },
    chaos_mix = { 0.00, 0.75 }, gain_chaos = { 0.15, 1.00 },
    tail = { 0.00, 1.00 }, spread = { 0.00, 1.00 }, gain_resonator = { 0.35, 1.00 }
  },
  [2] = { -- Extreme
    intensity = { 0.10, 1.00 }, color = { 0.00, 1.00 }, pitch = { -24.0, 24.0 }, drive = { 0.00, 1.00 },
    character = { 0.00, 1.00 },
    e2_grain_mix = { 0.00, 1.00 }, e2_spectral_mix = { 0.00, 1.00 }, e2_reverse_mix = { 0.00, 1.00 }, e2_safety = { 0.00, 1.00 }, e2_cpu_quality = { 0.00, 1.00 },
    gain_digital = { 0.20, 1.00 },
    complexity = { 0.00, 1.00 }, pulse_rate = { 0.5, 12.0 }, pad_timbre = { 0.00, 1.00 }, gain_packet = { 0.10, 1.00 },
    dirt = { 0.00, 1.00 }, gain_noise = { 0.00, 1.00 },
    motion = { 0.00, 1.00 }, lfo_rate = { 0.05, 12.00 }, lfo_depth = { 0.00, 1.00 },
    lfo2_rate = { 0.05, 12.00 }, lfo2_depth = { 0.00, 1.00 }, mseg_depth = { 0.00, 1.00 }, pad_motion = { 0.00, 1.00 },
    chaos_mix = { 0.00, 1.00 }, gain_chaos = { 0.00, 1.00 },
    tail = { 0.00, 1.00 }, spread = { 0.00, 1.00 }, gain_resonator = { 0.10, 1.00 }
  }
}

function Randomizer.Randomize(state, style)
  local s = state.synth
  local m = state.rand_masks
  local preserved_output_mode = s.output_mode
  local style_idx = clamp(math.floor(tonumber(style) or tonumber(state.rand_style) or 1), 0, 2)
  local rng = STYLE_RANGES[style_idx] or STYLE_RANGES[1]

  if m.osc then
    s.intensity = rf(rng.intensity[1], rng.intensity[2])
    s.color     = rf(rng.color[1], rng.color[2])
    s.pitch     = rf(rng.pitch[1], rng.pitch[2])
    s.drive     = rf(rng.drive[1], rng.drive[2])
    s.character = rf(rng.character[1], rng.character[2])
    s.e2_grain_mix = rf(rng.e2_grain_mix[1], rng.e2_grain_mix[2])
    s.e2_spectral_mix = rf(rng.e2_spectral_mix[1], rng.e2_spectral_mix[2])
    s.e2_reverse_mix = rf(rng.e2_reverse_mix[1], rng.e2_reverse_mix[2])
    s.e2_safety = rf(rng.e2_safety[1], rng.e2_safety[2])
    s.e2_cpu_quality = rf(rng.e2_cpu_quality[1], rng.e2_cpu_quality[2]) >= 0.5 and 1 or 0
    s.layer_gain_digital = rf(rng.gain_digital[1], rng.gain_digital[2])
  end

  if m.packet then
    s.complexity    = rf(rng.complexity[1], rng.complexity[2])
    s.pulse_rate    = rf(rng.pulse_rate[1], rng.pulse_rate[2])
    s.pad_timbre_x  = rf(rng.pad_timbre[1], rng.pad_timbre[2])
    s.pad_timbre_y  = rf(rng.pad_timbre[1], rng.pad_timbre[2])
    s.layer_gain_packet = rf(rng.gain_packet[1], rng.gain_packet[2])
  end

  if m.noise then
    s.dirt    = rf(rng.dirt[1], rng.dirt[2])
    s.layer_gain_noise = rf(rng.gain_noise[1], rng.gain_noise[2])
  end

  if m.modulation then
    s.motion        = rf(rng.motion[1], rng.motion[2])
    s.lfo_rate      = rf(rng.lfo_rate[1], rng.lfo_rate[2])
    s.lfo_depth     = rf(rng.lfo_depth[1], rng.lfo_depth[2])
    s.lfo1_wave     = ri(0, 3)
    s.lfo2_rate     = rf(rng.lfo2_rate[1], rng.lfo2_rate[2])
    s.lfo2_depth    = rf(rng.lfo2_depth[1], rng.lfo2_depth[2])
    s.lfo2_wave     = ri(0, 3)
    s.mseg_depth    = rf(rng.mseg_depth[1], rng.mseg_depth[2])
    s.pad_motion_x  = rf(rng.pad_motion[1], rng.pad_motion[2])
    s.pad_motion_y  = rf(rng.pad_motion[1], rng.pad_motion[2])
  end

  if m.chaos then
    s.chaos_mix = rf(rng.chaos_mix[1], rng.chaos_mix[2])
    s.layer_gain_chaos = rf(rng.gain_chaos[1], rng.gain_chaos[2])
    s.chaos_mode = ri(0, 2)
  end

  if m.tail then
    s.tail   = rf(rng.tail[1], rng.tail[2])
    s.spread = rf(rng.spread[1], rng.spread[2])
    s.layer_gain_resonator = rf(rng.gain_resonator[1], rng.gain_resonator[2])
  end

  if m.family then
    s.family = ri(0, FAMILY_COUNT - 1)
  end

  -- Output mode is a transport/routing decision, not a sound-design random target.
  s.output_mode = preserved_output_mode
end

return Randomizer
