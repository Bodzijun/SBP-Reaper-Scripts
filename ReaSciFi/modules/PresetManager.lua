---@diagnostic disable: undefined-field

local State = dofile((debug.getinfo(1, 'S').source:match('@(.*[\\/])') or '') .. 'State.lua')

local PresetManager = {}

local PRESETS = {
  {
    name = 'Data Chirp',
    synth = {
      layer_gain_digital = 1.00, layer_gain_packet = 0.90, layer_gain_noise = 0.30, layer_gain_resonator = 0.55, layer_gain_chaos = 0.20,
      mode = 0, family = 0, intensity = 0.62, complexity = 0.36, dirt = 0.08, motion = 0.28,
      tail = 0.18, pitch = 7.0, color = 0.66, spread = 0.15, output_mode = 0, pulse_rate = 5.8,
      preview_gate = 1.0, pad_timbre_x = 0.18, pad_timbre_y = 0.82, pad_motion_x = 0.55, pad_motion_y = 0.25,
      lfo1_wave = 0, lfo_depth = 0.18, lfo_rate = 2.20, lfo2_wave = 1, lfo2_depth = 0.20, lfo2_rate = 0.80,
      mseg_depth = 0.20, drive = 0.05, chaos_mix = 0.10, chaos_mode = 0, master_gain = -12.0
    }
  },
  {
    name = 'Holo Click',
    synth = {
      layer_gain_digital = 0.95, layer_gain_packet = 0.75, layer_gain_noise = 0.20, layer_gain_resonator = 0.85, layer_gain_chaos = 0.25,
      mode = 0, family = 1, intensity = 0.56, complexity = 0.48, dirt = 0.12, motion = 0.32,
      tail = 0.22, pitch = 2.0, color = 0.72, spread = 0.22, output_mode = 0, pulse_rate = 4.5,
      preview_gate = 1.0, pad_timbre_x = 0.42, pad_timbre_y = 0.64, pad_motion_x = 0.44, pad_motion_y = 0.34,
      lfo1_wave = 0, lfo_depth = 0.15, lfo_rate = 1.80, lfo2_wave = 2, lfo2_depth = 0.18, lfo2_rate = 2.60,
      mseg_depth = 0.30, drive = 0.07, chaos_mix = 0.16, chaos_mode = 0, master_gain = -12.0
    }
  },
  {
    name = 'Alert Ping',
    synth = {
      layer_gain_digital = 1.00, layer_gain_packet = 0.55, layer_gain_noise = 0.12, layer_gain_resonator = 0.60, layer_gain_chaos = 0.08,
      mode = 0, family = 2, intensity = 0.80, complexity = 0.44, dirt = 0.10, motion = 0.18,
      tail = 0.26, pitch = 12.0, color = 0.58, spread = 0.14, output_mode = 0, pulse_rate = 3.2,
      preview_gate = 1.0, pad_timbre_x = 0.20, pad_timbre_y = 0.90, pad_motion_x = 0.50, pad_motion_y = 0.20,
      lfo1_wave = 2, lfo_depth = 0.08, lfo_rate = 1.10, lfo2_wave = 0, lfo2_depth = 0.10, lfo2_rate = 4.20,
      mseg_depth = 0.18, drive = 0.12, chaos_mix = 0.06, chaos_mode = 0, master_gain = -11.0
    }
  },
  {
    name = 'Glitch Burst',
    synth = {
      layer_gain_digital = 0.75, layer_gain_packet = 1.00, layer_gain_noise = 0.90, layer_gain_resonator = 0.45, layer_gain_chaos = 0.70,
      mode = 0, family = 5, intensity = 0.88, complexity = 0.78, dirt = 0.54, motion = 0.64,
      tail = 0.34, pitch = -5.0, color = 0.48, spread = 0.34, output_mode = 0, pulse_rate = 7.2,
      preview_gate = 1.0, pad_timbre_x = 0.76, pad_timbre_y = 0.46, pad_motion_x = 0.68, pad_motion_y = 0.52,
      lfo1_wave = 1, lfo_depth = 0.34, lfo_rate = 4.80, lfo2_wave = 3, lfo2_depth = 0.42, lfo2_rate = 7.20,
      mseg_depth = 0.48, drive = 0.22, chaos_mix = 0.44, chaos_mode = 2, master_gain = -13.0
    }
  },
  {
    name = 'Scanner Bed',
    synth = {
      layer_gain_digital = 0.55, layer_gain_packet = 0.35, layer_gain_noise = 0.55, layer_gain_resonator = 1.00, layer_gain_chaos = 0.40,
      mode = 1, family = 3, intensity = 0.58, complexity = 0.60, dirt = 0.16, motion = 0.54,
      tail = 0.46, pitch = -7.0, color = 0.40, spread = 0.32, output_mode = 1, pulse_rate = 2.0,
      preview_gate = 1.0, pad_timbre_x = 0.62, pad_timbre_y = 0.40, pad_motion_x = 0.78, pad_motion_y = 0.62,
      lfo1_wave = 0, lfo_depth = 0.36, lfo_rate = 0.42, lfo2_wave = 1, lfo2_depth = 0.28, lfo2_rate = 0.85,
      mseg_depth = 0.40, drive = 0.14, chaos_mix = 0.22, chaos_mode = 1, master_gain = -14.0
    }
  },
  {
    name = 'Reactor Bed',
    synth = {
      layer_gain_digital = 0.45, layer_gain_packet = 0.22, layer_gain_noise = 0.42, layer_gain_resonator = 1.00, layer_gain_chaos = 0.55,
      mode = 1, family = 4, intensity = 0.72, complexity = 0.66, dirt = 0.26, motion = 0.42,
      tail = 0.62, pitch = -12.0, color = 0.30, spread = 0.28, output_mode = 1, pulse_rate = 1.2,
      preview_gate = 1.0, pad_timbre_x = 0.58, pad_timbre_y = 0.26, pad_motion_x = 0.40, pad_motion_y = 0.68,
      lfo1_wave = 0, lfo_depth = 0.28, lfo_rate = 0.26, lfo2_wave = 2, lfo2_depth = 0.24, lfo2_rate = 0.62,
      mseg_depth = 0.34, drive = 0.20, chaos_mix = 0.30, chaos_mode = 0, master_gain = -15.0
    }
  },
  {
    name = 'Data Burst',
    synth = {
      layer_gain_digital = 0.62, layer_gain_packet = 1.00, layer_gain_noise = 0.30, layer_gain_resonator = 0.36, layer_gain_chaos = 0.24,
      mode = 0, family = 6, intensity = 0.86, complexity = 0.82, dirt = 0.20, motion = 0.58,
      tail = 0.26, pitch = 5.0, color = 0.63, spread = 0.21, output_mode = 0, pulse_rate = 8.2,
      preview_gate = 1.0, pad_timbre_x = 0.74, pad_timbre_y = 0.78, pad_motion_x = 0.68, pad_motion_y = 0.44,
      lfo1_wave = 2, lfo_depth = 0.26, lfo_rate = 5.10, lfo2_wave = 3, lfo2_depth = 0.34, lfo2_rate = 6.40,
      mseg_depth = 0.42, drive = 0.16, chaos_mix = 0.22, chaos_mode = 2, master_gain = -12.5
    }
  },
  {
    name = 'Packet Loss',
    synth = {
      layer_gain_digital = 0.70, layer_gain_packet = 0.92, layer_gain_noise = 0.46, layer_gain_resonator = 0.42, layer_gain_chaos = 0.35,
      mode = 0, family = 7, intensity = 0.76, complexity = 0.72, dirt = 0.36, motion = 0.48,
      tail = 0.30, pitch = -2.0, color = 0.50, spread = 0.26, output_mode = 0, pulse_rate = 6.1,
      preview_gate = 1.0, pad_timbre_x = 0.66, pad_timbre_y = 0.52, pad_motion_x = 0.62, pad_motion_y = 0.46,
      lfo1_wave = 1, lfo_depth = 0.22, lfo_rate = 3.10, lfo2_wave = 2, lfo2_depth = 0.28, lfo2_rate = 4.80,
      mseg_depth = 0.30, drive = 0.19, chaos_mix = 0.24, chaos_mode = 0, master_gain = -12.5
    }
  },
  {
    name = 'Scanner Orbit',
    synth = {
      layer_gain_digital = 0.36, layer_gain_packet = 0.20, layer_gain_noise = 0.28, layer_gain_resonator = 1.00, layer_gain_chaos = 0.48,
      mode = 1, family = 8, intensity = 0.66, complexity = 0.44, dirt = 0.24, motion = 0.72,
      tail = 0.70, pitch = -9.0, color = 0.34, spread = 0.40, output_mode = 1, pulse_rate = 1.1,
      preview_gate = 1.0, pad_timbre_x = 0.52, pad_timbre_y = 0.30, pad_motion_x = 0.84, pad_motion_y = 0.78,
      lfo1_wave = 0, lfo_depth = 0.42, lfo_rate = 0.34, lfo2_wave = 1, lfo2_depth = 0.30, lfo2_rate = 0.58,
      mseg_depth = 0.46, drive = 0.17, chaos_mix = 0.34, chaos_mode = 1, master_gain = -14.0
    }
  },
  {
    name = 'Metallic Chirp',
    synth = {
      layer_gain_digital = 1.00, layer_gain_packet = 0.92, layer_gain_noise = 0.10, layer_gain_resonator = 0.30, layer_gain_chaos = 0.12,
      mode = 0, family = 9, intensity = 0.74, complexity = 0.60, dirt = 0.06, motion = 0.22,
      tail = 0.20, pitch = 8.0, color = 0.84, spread = 0.18, output_mode = 0, pulse_rate = 6.4,
      preview_gate = 1.0, pad_timbre_x = 0.24, pad_timbre_y = 0.88, pad_motion_x = 0.48, pad_motion_y = 0.28,
      lfo1_wave = 2, lfo_depth = 0.16, lfo_rate = 3.40, lfo2_wave = 0, lfo2_depth = 0.14, lfo2_rate = 5.80,
      mseg_depth = 0.22, drive = 0.08, chaos_mix = 0.08, chaos_mode = 0, master_gain = -11.0
    }
  },
  {
    name = 'Subcursor Rumble',
    synth = {
      layer_gain_digital = 0.40, layer_gain_packet = 0.20, layer_gain_noise = 0.35, layer_gain_resonator = 1.00, layer_gain_chaos = 0.85,
      mode = 1, family = 10, intensity = 0.58, complexity = 0.72, dirt = 0.48, motion = 0.56,
      tail = 0.68, pitch = -14.0, color = 0.26, spread = 0.36, output_mode = 1, pulse_rate = 1.0,
      preview_gate = 1.0, pad_timbre_x = 0.64, pad_timbre_y = 0.24, pad_motion_x = 0.72, pad_motion_y = 0.68,
      lfo1_wave = 1, lfo_depth = 0.32, lfo_rate = 0.48, lfo2_wave = 3, lfo2_depth = 0.38, lfo2_rate = 0.72,
      mseg_depth = 0.44, drive = 0.28, chaos_mix = 0.56, chaos_mode = 2, master_gain = -15.5
    }
  },
  {
    name = 'Bit Crush',
    synth = {
      layer_gain_digital = 0.68, layer_gain_packet = 1.00, layer_gain_noise = 0.42, layer_gain_resonator = 0.32, layer_gain_chaos = 0.28,
      mode = 0, family = 11, intensity = 0.82, complexity = 0.88, dirt = 0.66, motion = 0.52,
      tail = 0.24, pitch = 3.0, color = 0.42, spread = 0.28, output_mode = 0, pulse_rate = 9.6,
      preview_gate = 1.0, pad_timbre_x = 0.80, pad_timbre_y = 0.64, pad_motion_x = 0.58, pad_motion_y = 0.42,
      lfo1_wave = 3, lfo_depth = 0.24, lfo_rate = 7.20, lfo2_wave = 2, lfo2_depth = 0.36, lfo2_rate = 8.60,
      mseg_depth = 0.38, drive = 0.34, chaos_mix = 0.20, chaos_mode = 0, master_gain = -13.5
    }
  },
  {
    name = 'Ephemeral Echo',
    synth = {
      layer_gain_digital = 0.08, layer_gain_packet = 0.05, layer_gain_noise = 0.02, layer_gain_resonator = 1.00, layer_gain_chaos = 0.10,
      mode = 1, family = 12, intensity = 0.62, complexity = 0.30, dirt = 0.08, motion = 0.68,
      tail = 0.88, pitch = -6.0, color = 0.56, spread = 0.48, output_mode = 1, pulse_rate = 0.8,
      preview_gate = 1.0, pad_timbre_x = 0.50, pad_timbre_y = 0.50, pad_motion_x = 0.80, pad_motion_y = 0.76,
      lfo1_wave = 0, lfo_depth = 0.48, lfo_rate = 0.26, lfo2_wave = 0, lfo2_depth = 0.32, lfo2_rate = 0.42,
      mseg_depth = 0.52, drive = 0.06, chaos_mix = 0.12, chaos_mode = 0, master_gain = -16.0,
      character = 0.78, e2_grain_mix = 0.28, e2_spectral_mix = 0.74, e2_reverse_mix = 0.88, e2_safety = 0.80
    }
  },
  {
    name = 'Quantum Dust',
    synth = {
      layer_gain_digital = 0.62, layer_gain_packet = 0.74, layer_gain_noise = 0.36, layer_gain_resonator = 0.58, layer_gain_chaos = 0.42,
      mode = 0, family = 11, intensity = 0.76, complexity = 0.70, dirt = 0.34, motion = 0.60,
      tail = 0.36, pitch = 6.0, color = 0.68, spread = 0.30, output_mode = 0, pulse_rate = 8.8,
      preview_gate = 1.0, pad_timbre_x = 0.72, pad_timbre_y = 0.64, pad_motion_x = 0.66, pad_motion_y = 0.54,
      lfo1_wave = 3, lfo_depth = 0.28, lfo_rate = 6.20, lfo2_wave = 2, lfo2_depth = 0.38, lfo2_rate = 7.80,
      mseg_depth = 0.42, drive = 0.24, chaos_mix = 0.30, chaos_mode = 2, master_gain = -13.2,
      character = 0.84, e2_grain_mix = 0.92, e2_spectral_mix = 0.56, e2_reverse_mix = 0.46, e2_safety = 0.66
    }
  },
  {
    name = 'Holo Veil',
    synth = {
      layer_gain_digital = 0.28, layer_gain_packet = 0.16, layer_gain_noise = 0.20, layer_gain_resonator = 0.94, layer_gain_chaos = 0.24,
      mode = 1, family = 8, intensity = 0.54, complexity = 0.40, dirt = 0.14, motion = 0.70,
      tail = 0.82, pitch = -4.0, color = 0.48, spread = 0.44, output_mode = 1, pulse_rate = 1.1,
      preview_gate = 1.0, pad_timbre_x = 0.58, pad_timbre_y = 0.36, pad_motion_x = 0.78, pad_motion_y = 0.74,
      lfo1_wave = 0, lfo_depth = 0.40, lfo_rate = 0.36, lfo2_wave = 1, lfo2_depth = 0.30, lfo2_rate = 0.52,
      mseg_depth = 0.50, drive = 0.10, chaos_mix = 0.22, chaos_mode = 1, master_gain = -14.8,
      character = 0.66, e2_grain_mix = 0.20, e2_spectral_mix = 0.82, e2_reverse_mix = 0.90, e2_safety = 0.90
    }
  }
}

function PresetManager.GetNames()
  local out = {}
  for index = 1, #PRESETS do
    out[index] = PRESETS[index].name
  end
  return out
end

local function getMergedFactorySynth(index)
  local preset = PRESETS[index]
  if not preset then
    return nil
  end
  local merged = State.DeepCopy(State.GetDefault().synth)
  for k, v in pairs(preset.synth) do
    merged[k] = v
  end
  return merged, preset.name
end

local DISCRETE_KEYS = {
  mode = true,
  family = true,
  output_mode = true,
  lfo1_wave = true,
  lfo2_wave = true,
  chaos_mode = true,
  e2_cpu_quality = true,
  timbre_x_target = true,
  timbre_y_target = true,
  motion_x_target = true,
  motion_y_target = true,
  bind_x_target = true,
  bind_y_target = true,
  timbre_x_invert = true,
  timbre_y_invert = true,
  motion_x_invert = true,
  motion_y_invert = true,
  bind_x_invert = true,
  bind_y_invert = true
}

function PresetManager.MorphFactory(state, index_a, index_b, t)
  local a, name_a = getMergedFactorySynth(index_a)
  local b, name_b = getMergedFactorySynth(index_b)
  if not a or not b then
    return false, 'Invalid preset index for morph.'
  end

  local mix = math.max(0, math.min(1, tonumber(t) or 0.5))
  local out = State.DeepCopy(State.GetDefault().synth)

  for key, default_value in pairs(out) do
    local va = a[key]
    local vb = b[key]
    if type(va) == 'number' and type(vb) == 'number' then
      if DISCRETE_KEYS[key] then
        out[key] = (mix < 0.5) and va or vb
      else
        out[key] = va + (vb - va) * mix
      end
    elseif va ~= nil then
      out[key] = va
    else
      out[key] = default_value
    end
  end

  out.timbre_pad_x = out.pad_timbre_x
  out.timbre_pad_y = out.pad_timbre_y
  out.motion_pad_x = out.pad_motion_x
  out.motion_pad_y = out.pad_motion_y

  State.ReplaceSynth(state, out)
  state.ui.status = string.format('Morph: %s -> %s (%.0f%%)', name_a, name_b, mix * 100)
  state.ui.status_is_error = false
  return true
end

function PresetManager.Apply(state, index)
  local merged, preset_name = getMergedFactorySynth(index)
  if not merged then
    return false
  end
  merged.timbre_pad_x = merged.pad_timbre_x
  merged.timbre_pad_y = merged.pad_timbre_y
  merged.motion_pad_x = merged.pad_motion_x
  merged.motion_pad_y = merged.pad_motion_y
  State.ReplaceSynth(state, merged)
  state.ui.selected_preset = index
  state.ui.status = 'Preset loaded: ' .. preset_name
  state.ui.status_is_error = false
  return true
end

-- =========================================================
-- User Preset CRUD  (persisted via REAPER ExtState)
-- =========================================================

local EXT_SECTION  = 'ReaSciFi_v1'
local EXT_LIST_KEY = 'UserPresets_List'
local r = reaper

-- Serialize synth table to a pipe-delimited k=v string.
local function serializeSynth(synth)
  local parts = {}
  for k, v in pairs(synth) do
    if type(v) == 'number' then
      parts[#parts + 1] = k .. '=' .. string.format('%.5f', v)
    end
  end
  table.sort(parts)
  return table.concat(parts, '|')
end

-- Deserialize k=v pipe string back to a synth table.
local function deserializeSynth(str)
  local synth = {}
  for k, v in string.gmatch(str, '([^|=]+)=([^|]+)') do
    local n = tonumber(v)
    if n then synth[k] = n end
  end
  return synth
end

-- Returns sorted list of saved user preset names.
function PresetManager.GetUserNames()
  local list_str = r.GetExtState(EXT_SECTION, EXT_LIST_KEY)
  local names = {}
  if list_str and list_str ~= '' then
    for name in string.gmatch(list_str, '([^|]+)') do
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

  local function getMergedUserSynth(name)
    if not name or name == '' then
      return nil
    end
    local data = r.GetExtState(EXT_SECTION, name)
    if not data or data == '' then
      return nil
    end
    local parsed = deserializeSynth(data)
    local merged = State.DeepCopy(State.GetDefault().synth)
    for k, v in pairs(parsed) do
      merged[k] = v
    end
    return merged
  end

function PresetManager.MorphUser(state, name_a, name_b, t)
  local a = getMergedUserSynth(name_a)
  local b = getMergedUserSynth(name_b)
  if not a or not b then
    return false, 'Invalid user preset for morph.'
  end

  local mix = math.max(0, math.min(1, tonumber(t) or 0.5))
  local out = State.DeepCopy(State.GetDefault().synth)

  for key, default_value in pairs(out) do
    local va = a[key]
    local vb = b[key]
    if type(va) == 'number' and type(vb) == 'number' then
      if DISCRETE_KEYS[key] then
        out[key] = (mix < 0.5) and va or vb
      else
        out[key] = va + (vb - va) * mix
      end
    elseif va ~= nil then
      out[key] = va
    else
      out[key] = default_value
    end
  end

  out.timbre_pad_x = out.pad_timbre_x
  out.timbre_pad_y = out.pad_timbre_y
  out.motion_pad_x = out.pad_motion_x
  out.motion_pad_y = out.pad_motion_y

  State.ReplaceSynth(state, out)
  state.ui.status = string.format('Morph User: %s -> %s (%.0f%%)', name_a, name_b, mix * 100)
  state.ui.status_is_error = false
  return true
end
-- Saves current state.synth under the given name. Overwrites if exists.
function PresetManager.SaveUser(name, state)
  if not name or name == '' then return false end
  local data = serializeSynth(state.synth)
  r.SetExtState(EXT_SECTION, name, data, true)
  -- Append to list if not already present.
  local list_str = r.GetExtState(EXT_SECTION, EXT_LIST_KEY)
  if not string.find('|' .. (list_str or '') .. '|', '|' .. name .. '|', 1, true) then
    list_str = (list_str and list_str ~= '') and (list_str .. '|' .. name) or name
    r.SetExtState(EXT_SECTION, EXT_LIST_KEY, list_str, true)
  end
  return true
end

-- Loads stored user preset into state.synth. Merges field-by-field so any
-- missing fields keep their current value.
function PresetManager.LoadUser(name, state)
  local data = r.GetExtState(EXT_SECTION, name)
  if not data or data == '' then return false end
  local synth = deserializeSynth(data)
  for k, v in pairs(synth) do
    if state.synth[k] ~= nil then
      state.synth[k] = v
    end
  end
  if synth.timbre_pad_x == nil then state.synth.timbre_pad_x = state.synth.pad_timbre_x end
  if synth.timbre_pad_y == nil then state.synth.timbre_pad_y = state.synth.pad_timbre_y end
  if synth.motion_pad_x == nil then state.synth.motion_pad_x = state.synth.pad_motion_x end
  if synth.motion_pad_y == nil then state.synth.motion_pad_y = state.synth.pad_motion_y end
  return true
end

-- Deletes a user preset by name.
function PresetManager.DeleteUser(name)
  if not name or name == '' then return end
  r.DeleteExtState(EXT_SECTION, name, true)
  local list_str = r.GetExtState(EXT_SECTION, EXT_LIST_KEY) or ''
  -- Remove from list.
  local new_parts = {}
  for n in string.gmatch(list_str, '([^|]+)') do
    if n ~= name then new_parts[#new_parts + 1] = n end
  end
  r.SetExtState(EXT_SECTION, EXT_LIST_KEY, table.concat(new_parts, '|'), true)
end

return PresetManager