---@diagnostic disable: undefined-field

local State = {}

local function deepCopy(value)
  if type(value) ~= 'table' then
    return value
  end
  local out = {}
  for key, entry in pairs(value) do
    out[key] = deepCopy(entry)
  end
  return out
end

function State.DeepCopy(value)
  return deepCopy(value)
end

function State.GetDefault()
  return {
    version = '0.1.0',
    setup = {
      target_track_name = '',
      follow_selected_track = true,
      auto_preview = true
    },
    ui = {
      selected_preset = 1,
      status = 'Ready.',
      status_is_error = false,
      loaded_user_preset_name = nil,
      -- User preset panel state (not persisted in synth presets).
      user_preset_names = {},
      user_preset_sel   = 1,
      user_preset_input = '',
      quick_profile_sel = 0,
      morph_user_a_sel = 1,
      morph_user_b_sel = 1,
      morph_t = 0.50,
      morph_enabled = false,
      batch_count = 8,
      batch_prefix = 'ReaSciFi',
      batch_randomize = true,
      batch_gap_ms = 20,
      batch_midi_rand_enabled = false,
      batch_midi_pitch = 69,
      batch_midi_pitch_rand = false,
      batch_midi_pitch_min = 60,
      batch_midi_pitch_max = 84,
      batch_midi_vel = 110,
      batch_midi_vel_rand = false,
      batch_midi_vel_min = 85,
      batch_midi_vel_max = 127,
      batch_midi_len_ms = 30,
      batch_midi_len_rand = false,
      batch_midi_len_min_ms = 15,
      batch_midi_len_max_ms = 60,
      batch_midi_autofit_range = true
    },
    -- Randomizer masks: which parameter groups are eligible for randomization.
    rand_masks = {
      osc        = true,
      packet     = true,
      noise      = true,
      modulation = true,
      chaos      = true,
      tail       = true,
      family     = false   -- opt-in: randomize family/sound-type
    },
    -- Randomizer style: 0=Mild, 1=Creative, 2=Extreme.
    rand_style = 1,
    synth = {
      mode = 0,
      follow_note_len = 0,
      family = 0,
      layer_gain_digital = 1.0,
      layer_gain_packet = 1.0,
      layer_gain_noise = 1.0,
      layer_gain_resonator = 1.0,
      layer_gain_chaos = 1.0,
      intensity = 0.68,
      complexity = 0.42,
      dirt = 0.18,
      motion = 0.35,
      tail = 0.30,
      pitch = 0.0,
      color = 0.56,
      spread = 0.22,
      output_mode = 0,
      pulse_rate = 4.0,
      preview_gate = 1.0,
      pad_timbre_x = 0.22,
      pad_timbre_y = 0.76,
      pad_motion_x = 0.50,
      pad_motion_y = 0.30,
      lfo1_wave = 0,
      lfo_depth = 0.28,
      lfo_rate = 1.40,
      lfo2_wave = 1,
      lfo2_depth = 0.22,
      lfo2_rate = 0.62,
      mseg_depth = 0.24,
      character = 0.50,
      e2_grain_mix = 0.55,
      e2_spectral_mix = 0.50,
      e2_reverse_mix = 0.48,
      e2_safety = 0.65,
      e2_cpu_quality = 1,
      timbre_pad_x = 0.22,
      timbre_pad_y = 0.76,
      timbre_x_target = 19,
      timbre_y_target = 20,
      timbre_x_amount = 1.00,
      timbre_y_amount = 1.00,
      timbre_x_invert = 0,
      timbre_y_invert = 0,
      motion_pad_x = 0.50,
      motion_pad_y = 0.30,
      motion_x_target = 21,
      motion_y_target = 22,
      motion_x_amount = 1.00,
      motion_y_amount = 1.00,
      motion_x_invert = 0,
      motion_y_invert = 0,
      bind_pad_x = 0.50,
      bind_pad_y = 0.50,
      bind_x_target = 0,
      bind_y_target = 3,
      bind_x_amount = 1.00,
      bind_y_amount = 1.00,
      bind_x_invert = 0,
      bind_y_invert = 0,
      drive = 0.10,
      chaos_mix = 0.20,
      chaos_mode = 0,
      master_gain = -12.0
    }
  }
end

function State.ReplaceSynth(target_state, synth_data)
  if type(target_state) ~= 'table' or type(synth_data) ~= 'table' then
    return
  end
  target_state.synth = deepCopy(synth_data)
end

return State