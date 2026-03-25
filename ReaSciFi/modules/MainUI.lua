---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch

local UIHelpers = dofile((debug.getinfo(1, 'S').source:match('@(.*[\\/])') or '') .. 'UIHelpers.lua')

local MainUI = {}
local r = reaper

local FAMILY_NAMES = {
  'Data Chirp', 'Holo Click', 'Alert Ping', 'Scanner Bed', 'Reactor Bed',
  'Glitch Burst', 'Data Burst', 'Packet Loss', 'Scanner Orbit', 'Metallic Chirp',
  'Subcursor Rumble', 'Bit Crush', 'Ephemeral Echo'
}
local MODE_NAMES = { 'One-Shot (MIDI NoteOn)', 'Drone (Continuous)' }
local OUTPUT_NAMES = { 'Stereo', 'Surround' }
local LFO_WAVE_NAMES = { 'Sine', 'Triangle', 'Square', 'S&H' }
local CHAOS_MODE_NAMES = { 'Texture', 'FM', 'Burst' }
local RAND_STYLE_NAMES = { 'Mild', 'Creative', 'Extreme' }
local QUICK_PROFILE_NAMES = { 'Click', 'Whoosh', 'Drone', 'Glitch', 'Scanner', 'Telemetry' }

local BIND_TARGETS = {
  { name = 'Intensity', key = 'intensity', min = 0.0, max = 1.0 },
  { name = 'Complexity', key = 'complexity', min = 0.0, max = 1.0 },
  { name = 'Dirt', key = 'dirt', min = 0.0, max = 1.0 },
  { name = 'Motion', key = 'motion', min = 0.0, max = 1.0 },
  { name = 'Tail', key = 'tail', min = 0.0, max = 1.0 },
  { name = 'Color', key = 'color', min = 0.0, max = 1.0 },
  { name = 'Spread', key = 'spread', min = 0.0, max = 1.0 },
  { name = 'Drive', key = 'drive', min = 0.0, max = 1.0 },
  { name = 'Chaos Mix', key = 'chaos_mix', min = 0.0, max = 1.0 },
  { name = 'LFO1 Depth', key = 'lfo_depth', min = 0.0, max = 1.0 },
  { name = 'LFO1 Rate', key = 'lfo_rate', min = 0.05, max = 12.0 },
  { name = 'LFO2 Depth', key = 'lfo2_depth', min = 0.0, max = 1.0 },
  { name = 'LFO2 Rate', key = 'lfo2_rate', min = 0.05, max = 12.0 },
  { name = 'MSEG Depth', key = 'mseg_depth', min = 0.0, max = 1.0 },
  { name = 'Digital Gain', key = 'layer_gain_digital', min = 0.0, max = 1.0 },
  { name = 'Packet Gain', key = 'layer_gain_packet', min = 0.0, max = 1.0 },
  { name = 'Noise Gain', key = 'layer_gain_noise', min = 0.0, max = 1.0 },
  { name = 'Resonator Gain', key = 'layer_gain_resonator', min = 0.0, max = 1.0 },
  { name = 'Chaos Gain', key = 'layer_gain_chaos', min = 0.0, max = 1.0 }
  ,{ name = 'Pad Timbre X', key = 'pad_timbre_x', min = 0.0, max = 1.0 }
  ,{ name = 'Pad Timbre Y', key = 'pad_timbre_y', min = 0.0, max = 1.0 }
  ,{ name = 'Pad Motion X', key = 'pad_motion_x', min = 0.0, max = 1.0 }
  ,{ name = 'Pad Motion Y', key = 'pad_motion_y', min = 0.0, max = 1.0 }
  ,{ name = 'Pitch', key = 'pitch', min = -24.0, max = 24.0 }
  ,{ name = 'Pulse Rate', key = 'pulse_rate', min = 0.5, max = 12.0 }
  ,{ name = 'Character', key = 'character', min = 0.0, max = 1.0 }
  ,{ name = 'E2 Grain Mix', key = 'e2_grain_mix', min = 0.0, max = 1.0 }
  ,{ name = 'E2 Spectral Mix', key = 'e2_spectral_mix', min = 0.0, max = 1.0 }
  ,{ name = 'E2 Reverse Mix', key = 'e2_reverse_mix', min = 0.0, max = 1.0 }
  ,{ name = 'E2 Safety', key = 'e2_safety', min = 0.0, max = 1.0 }
}

local BIND_TARGET_NAMES = (function()
  local names = {}
  for i = 1, #BIND_TARGETS do names[i] = BIND_TARGETS[i].name end
  return table.concat(names, '\0') .. '\0'
end)()

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function applyBindValue(synth, target_index, axis_value, amount, invert)
  local idx = math.floor((target_index or 0) + 1)
  local target = BIND_TARGETS[idx]
  if not target then return end
  local axis = clamp(axis_value or 0.5, 0.0, 1.0)
  if (tonumber(invert) or 0) >= 0.5 then
    axis = 1.0 - axis
  end
  local mapped = target.min + (target.max - target.min) * axis
  local curr = tonumber(synth[target.key]) or target.min
  synth[target.key] = clamp(lerp(curr, mapped, clamp(amount or 1.0, 0.0, 1.0)), target.min, target.max)
end

local function drawBindPad(ctx, synth, cfg)
  local changed = false
  r.ImGui_Text(ctx, cfg.title)
  r.ImGui_Separator(ctx)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local pad_size = 114
  local pad_x = r.ImGui_GetCursorPosX(ctx) + math.max(0, (avail_w - pad_size) * 0.5)
  r.ImGui_SetCursorPosX(ctx, pad_x)
  local pc, px, py = UIHelpers.DrawXYPad(ctx, '##' .. cfg.id .. '_pad', synth[cfg.pad_x] or 0.5, synth[cfg.pad_y] or 0.5, pad_size)
  if pc then
    synth[cfg.pad_x] = px
    synth[cfg.pad_y] = py
    applyBindValue(synth, synth[cfg.x_target], synth[cfg.pad_x], synth[cfg.x_amount], synth[cfg.x_invert])
    applyBindValue(synth, synth[cfg.y_target], synth[cfg.pad_y], synth[cfg.y_amount], synth[cfg.y_invert])
    changed = true
  end

  r.ImGui_Text(ctx, 'X Target')
  r.ImGui_SetNextItemWidth(ctx, -1)
  local cx_t, vx_t = r.ImGui_Combo(ctx, '##' .. cfg.id .. '_xt', synth[cfg.x_target] or 0, BIND_TARGET_NAMES)
  if cx_t then synth[cfg.x_target] = vx_t; changed = true end
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'X Amt')
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, -52)
  local cx_a, vx_a = r.ImGui_SliderDouble(ctx, '##' .. cfg.id .. '_xa', synth[cfg.x_amount] or 1.0, 0.0, 1.0)
  if cx_a then synth[cfg.x_amount] = vx_a; changed = true end
  r.ImGui_SameLine(ctx)
  local x_inv_bool = (tonumber(synth[cfg.x_invert]) or 0) >= 0.5
  local cx_i, vx_i = r.ImGui_Checkbox(ctx, 'Inv##' .. cfg.id .. '_xi', x_inv_bool)
  if cx_i then synth[cfg.x_invert] = vx_i and 1 or 0; changed = true end

  r.ImGui_Text(ctx, 'Y Target')
  r.ImGui_SetNextItemWidth(ctx, -1)
  local cy_t, vy_t = r.ImGui_Combo(ctx, '##' .. cfg.id .. '_yt', synth[cfg.y_target] or 0, BIND_TARGET_NAMES)
  if cy_t then synth[cfg.y_target] = vy_t; changed = true end
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Y Amt')
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, -52)
  local cy_a, vy_a = r.ImGui_SliderDouble(ctx, '##' .. cfg.id .. '_ya', synth[cfg.y_amount] or 1.0, 0.0, 1.0)
  if cy_a then synth[cfg.y_amount] = vy_a; changed = true end
  r.ImGui_SameLine(ctx)
  local y_inv_bool = (tonumber(synth[cfg.y_invert]) or 0) >= 0.5
  local cy_i, vy_i = r.ImGui_Checkbox(ctx, 'Inv##' .. cfg.id .. '_yi', y_inv_bool)
  if cy_i then synth[cfg.y_invert] = vy_i and 1 or 0; changed = true end

  return changed
end

local function secHeader(ctx, label)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_ORANGE)
  r.ImGui_Text(ctx, label)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_Separator(ctx)
end

local function hoverTip(ctx, text)
  if not text or text == '' then return end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_PushTextWrapPos(ctx, 430)
    r.ImGui_Text(ctx, text)
    r.ImGui_PopTextWrapPos(ctx)
    r.ImGui_EndTooltip(ctx)
  end
end

local function drawPresetCombo(ctx, state, preset_names, actions)
  local preview = preset_names[state.ui.selected_preset] or preset_names[1] or 'Factory Preset'
  r.ImGui_SetNextItemWidth(ctx, 160)
  if r.ImGui_BeginCombo(ctx, 'Preset##mb_preset', preview) then
    for i = 1, #preset_names do
      r.ImGui_PushID(ctx, i)
      local sel = (state.ui.selected_preset == i)
      if r.ImGui_Selectable(ctx, preset_names[i] .. '##mb_item', sel) then
        actions.apply_preset = i
      end
      if sel then
        r.ImGui_SetItemDefaultFocus(ctx)
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function drawConfigRow(ctx, state, actions, preset_names)
  local changed = false
  local synth = state.synth
  local setup = state.setup
  local ui = state.ui

  local tflags = r.ImGui_TableFlags_BordersInnerV()
  if r.ImGui_BeginTable(ctx, 'cfg_tbl##layout', 3, tflags) then
    r.ImGui_TableSetupColumn(ctx, 'col_global', r.ImGui_TableColumnFlags_WidthStretch(), 0.28)
    r.ImGui_TableSetupColumn(ctx, 'col_target', r.ImGui_TableColumnFlags_WidthStretch(), 0.27)
    r.ImGui_TableSetupColumn(ctx, 'col_user', r.ImGui_TableColumnFlags_WidthStretch(), 0.45)

    r.ImGui_TableNextColumn(ctx)
    secHeader(ctx, 'Global')
    r.ImGui_Text(ctx, 'Mode')
    hoverTip(ctx, 'One-Shot waits for a MIDI NoteOn for each trigger. Drone plays continuously and is better for beds/ambience.')
    if synth.mode == 0 then
      -- Reserve horizontal space so the inline one-shot checkbox stays visible.
      r.ImGui_SetNextItemWidth(ctx, -112)
    else
      r.ImGui_SetNextItemWidth(ctx, -1)
    end
    local cm, vm = r.ImGui_Combo(ctx, '##cfg_mode', synth.mode, table.concat(MODE_NAMES, '\0') .. '\0')
    if cm then synth.mode = vm; changed = true end
    hoverTip(ctx, 'Switches the core generator behavior: discrete one-shot or continuous drone.')
    if synth.mode == 0 then
      r.ImGui_SameLine(ctx)
      local follow_note_bool = (tonumber(synth.follow_note_len) or 0) >= 0.5
      local cfn, vfn = r.ImGui_Checkbox(ctx, 'Follow note len##cfg_follow_note_len', follow_note_bool)
      if cfn then synth.follow_note_len = vfn and 1 or 0; changed = true end
      hoverTip(ctx, 'In One-Shot mode, hold MIDI key to sustain the shot body; release key to continue the envelope tail.')
    end
    r.ImGui_Text(ctx, 'Family')
    hoverTip(ctx, 'Family changes the source character. Post FX may respond differently depending on the selected Family.')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local cf, vf = r.ImGui_Combo(ctx, '##cfg_family', synth.family, table.concat(FAMILY_NAMES, '\0') .. '\0')
    if cf then synth.family = vf; changed = true end

    r.ImGui_Text(ctx, 'Quick Profile')
    state.ui.quick_profile_sel = math.floor(tonumber(state.ui.quick_profile_sel) or 0)
    if state.ui.quick_profile_sel < 0 or state.ui.quick_profile_sel > (#QUICK_PROFILE_NAMES - 1) then
      state.ui.quick_profile_sel = 0
    end
    r.ImGui_SetNextItemWidth(ctx, -66)
    local cqp, vqp = r.ImGui_Combo(ctx, '##cfg_quick_profile', state.ui.quick_profile_sel, table.concat(QUICK_PROFILE_NAMES, '\0') .. '\0')
    if cqp then state.ui.quick_profile_sel = vqp; changed = true end
    hoverTip(ctx, 'Quickly sets mode, random masks, and style for a specific sound type.')
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Go##cfg_quick_apply', -1, 0) then
      actions.quick_profile = state.ui.quick_profile_sel
    end
    hoverTip(ctx, 'Applies the selected quick profile and immediately randomizes using its mask setup.')

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Output')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local co, vo = r.ImGui_Combo(ctx, '##cfg_output', synth.output_mode, table.concat(OUTPUT_NAMES, '\0') .. '\0')
    if co then synth.output_mode = vo; changed = true end
    hoverTip(ctx, 'Stereo = 2 channels, Surround = 5.1. This mode affects routing during Print/Batch.')
    r.ImGui_Text(ctx, 'Gain dB')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local cg, vg = r.ImGui_SliderDouble(ctx, '##cfg_gain', synth.master_gain, -36.0, 6.0)
    if cg then synth.master_gain = vg; changed = true end
    hoverTip(ctx, 'Global output level before the safety limiter.')
    if synth.mode == 0 then
      r.ImGui_Text(ctx, 'Preview Rate')
      r.ImGui_SetNextItemWidth(ctx, -1)
      local cpr, vpr = r.ImGui_SliderDouble(ctx, '##cfg_preview_rate', synth.pulse_rate, 0.5, 12.0)
      if cpr then synth.pulse_rate = vpr; changed = true end
      hoverTip(ctx, 'Preview trigger rate in One-Shot mode for quick auditioning without external MIDI.')
    else
      r.ImGui_Text(ctx, 'Preview Gate')
      r.ImGui_SetNextItemWidth(ctx, -1)
      local cpg, vpg = r.ImGui_SliderDouble(ctx, '##cfg_preview_gate', synth.preview_gate, 0.0, 1.0)
      if cpg then synth.preview_gate = vpg; changed = true end
      hoverTip(ctx, 'Preview volume gate in Drone mode.')
    end

    r.ImGui_TableNextColumn(ctx)
    secHeader(ctx, 'Target / Render')
    r.ImGui_Text(ctx, 'Track')
    r.ImGui_SetNextItemWidth(ctx, -62)
    local ct, vt = r.ImGui_InputText(ctx, '##cfg_track', setup.target_track_name)
    if ct then setup.target_track_name = vt; changed = true end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Pick##cfg_pick_track', -1, 0) then
      local sel_tr = r.GetSelectedTrack(0, 0)
      if sel_tr then
        local _, sel_name = r.GetSetMediaTrackInfo_String(sel_tr, 'P_NAME', '', false)
        setup.target_track_name = sel_name or ''
        changed = true
      end
    end
    hoverTip(ctx, 'Uses the current selected track as the Target Track.')
    local cfl, vfl = r.ImGui_Checkbox(ctx, 'Follow##cfg_follow', setup.follow_selected_track)
    if cfl then setup.follow_selected_track = vfl; changed = true end
    hoverTip(ctx, 'When enabled, ReaSciFi follows the selected track and pushes parameters there.')
    r.ImGui_SameLine(ctx)
    local cap, vap = r.ImGui_Checkbox(ctx, 'Auto Preview##cfg_auto', setup.auto_preview)
    if cap then setup.auto_preview = vap; changed = true end
    hoverTip(ctx, 'Automatically syncs parameters to JSFX while moving sliders and pads.')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x8C6A2DFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA87E37FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xC09342FF)
    if r.ImGui_Button(ctx, 'Push To FX##cfg_push', -1, 0) then actions.push_now = true end
    hoverTip(ctx, 'Force-pushes all current parameters to JSFX on the target track.')
    r.ImGui_PopStyleColor(ctx, 3)

    local sc = state.ui.status_is_error and UIHelpers.COL_WARN or UIHelpers.COL_ACCENT
    r.ImGui_TextColored(ctx, sc, state.ui.status or 'Ready.')

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Batch Render')
    local b_count = math.floor(tonumber(ui.batch_count) or 8)
    if b_count < 1 then b_count = 1 end
    if b_count > 128 then b_count = 128 end
    local cbc, vbc = r.ImGui_SliderInt(ctx, 'Count##cfg_batch_count', b_count, 1, 128)
    if cbc then ui.batch_count = vbc; changed = true end
    hoverTip(ctx, 'How many rendered items to create in one batch run.')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local cbp, vbp = r.ImGui_InputText(ctx, 'Prefix##cfg_batch_prefix', ui.batch_prefix or 'ReaSciFi')
    if cbp then ui.batch_prefix = vbp; changed = true end
    hoverTip(ctx, 'Base name for batch items: Prefix_001, Prefix_002, ...')
    local midi_btn_w = 88
    if r.ImGui_Button(ctx, 'MIDI Ctrl##cfg_batch_midi_ctrl', midi_btn_w, 0) then
      r.ImGui_OpenPopup(ctx, 'Batch MIDI Trigger##cfg_batch_midi_popup')
    end
    hoverTip(ctx, 'Open one-shot MIDI trigger controls for batch rendering (pitch/velocity/length and random ranges).')
    r.ImGui_SameLine(ctx)
    local cbr, vbr = r.ImGui_Checkbox(ctx, 'Randomize each##cfg_batch_rand', ui.batch_randomize == true)
    if cbr then ui.batch_randomize = vbr; changed = true end
    hoverTip(ctx, 'Randomizes the current patch before each rendered item.')
    local bgap = math.floor(tonumber(ui.batch_gap_ms) or 20)
    if bgap < 0 then bgap = 0 end
    if bgap > 500 then bgap = 500 end
    local cbg, vbg = r.ImGui_SliderInt(ctx, 'Gap ms##cfg_batch_gap_ms', bgap, 0, 500)
    if cbg then ui.batch_gap_ms = vbg; changed = true end
    hoverTip(ctx, 'Timeline gap between sequential items in batch mode "No" (single track).')
    if r.ImGui_BeginPopup(ctx, 'Batch MIDI Trigger##cfg_batch_midi_popup') then
      r.ImGui_Text(ctx, 'One-Shot MIDI Trigger')
      r.ImGui_Separator(ctx)

      local cen, ven = r.ImGui_Checkbox(ctx, 'Enable MIDI randomize##cfg_batch_midi_enable', ui.batch_midi_rand_enabled == true)
      if cen then ui.batch_midi_rand_enabled = ven; changed = true end

      local pitch = math.floor(tonumber(ui.batch_midi_pitch) or 69)
      if pitch < 0 then pitch = 0 end
      if pitch > 127 then pitch = 127 end
      local cp, vp = r.ImGui_SliderInt(ctx, 'Pitch##cfg_batch_midi_pitch', pitch, 0, 127)
      if cp then ui.batch_midi_pitch = vp; changed = true end
      local cpr, vpr = r.ImGui_Checkbox(ctx, 'Random pitch##cfg_batch_midi_pitch_rand', ui.batch_midi_pitch_rand == true)
      if cpr then ui.batch_midi_pitch_rand = vpr; changed = true end
      local pmin = math.floor(tonumber(ui.batch_midi_pitch_min) or 60)
      local pmax = math.floor(tonumber(ui.batch_midi_pitch_max) or 84)
      if pmin < 0 then pmin = 0 end
      if pmax > 127 then pmax = 127 end
      if pmin > pmax then pmin = pmax end
      local cpmn, vpmn = r.ImGui_SliderInt(ctx, 'Pitch min##cfg_batch_midi_pitch_min', pmin, 0, 127)
      if cpmn then ui.batch_midi_pitch_min = vpmn; changed = true end
      local cpmx, vpmx = r.ImGui_SliderInt(ctx, 'Pitch max##cfg_batch_midi_pitch_max', pmax, 0, 127)
      if cpmx then ui.batch_midi_pitch_max = vpmx; changed = true end

      r.ImGui_Separator(ctx)
      local vel = math.floor(tonumber(ui.batch_midi_vel) or 110)
      if vel < 1 then vel = 1 end
      if vel > 127 then vel = 127 end
      local cv, vv = r.ImGui_SliderInt(ctx, 'Velocity##cfg_batch_midi_vel', vel, 1, 127)
      if cv then ui.batch_midi_vel = vv; changed = true end
      local cvr, vvr = r.ImGui_Checkbox(ctx, 'Random velocity##cfg_batch_midi_vel_rand', ui.batch_midi_vel_rand == true)
      if cvr then ui.batch_midi_vel_rand = vvr; changed = true end
      local vmin = math.floor(tonumber(ui.batch_midi_vel_min) or 85)
      local vmax = math.floor(tonumber(ui.batch_midi_vel_max) or 127)
      if vmin < 1 then vmin = 1 end
      if vmax > 127 then vmax = 127 end
      if vmin > vmax then vmin = vmax end
      local cvmn, vvmn = r.ImGui_SliderInt(ctx, 'Vel min##cfg_batch_midi_vel_min', vmin, 1, 127)
      if cvmn then ui.batch_midi_vel_min = vvmn; changed = true end
      local cvmx, vvmx = r.ImGui_SliderInt(ctx, 'Vel max##cfg_batch_midi_vel_max', vmax, 1, 127)
      if cvmx then ui.batch_midi_vel_max = vvmx; changed = true end

      r.ImGui_Separator(ctx)
      local nlen = math.floor(tonumber(ui.batch_midi_len_ms) or 30)
      if nlen < 5 then nlen = 5 end
      if nlen > 300 then nlen = 300 end
      local cln, vln = r.ImGui_SliderInt(ctx, 'Note len ms##cfg_batch_midi_len', nlen, 5, 300)
      if cln then ui.batch_midi_len_ms = vln; changed = true end
      local clnr, vlnr = r.ImGui_Checkbox(ctx, 'Random note length##cfg_batch_midi_len_rand', ui.batch_midi_len_rand == true)
      if clnr then ui.batch_midi_len_rand = vlnr; changed = true end
      local lmin = math.floor(tonumber(ui.batch_midi_len_min_ms) or 15)
      local lmax = math.floor(tonumber(ui.batch_midi_len_max_ms) or 60)
      if lmin < 5 then lmin = 5 end
      if lmax > 300 then lmax = 300 end
      if lmin > lmax then lmin = lmax end
      local clmn, vlmn = r.ImGui_SliderInt(ctx, 'Len min##cfg_batch_midi_len_min', lmin, 5, 300)
      if clmn then ui.batch_midi_len_min_ms = vlmn; changed = true end
      local clmx, vlmx = r.ImGui_SliderInt(ctx, 'Len max##cfg_batch_midi_len_max', lmax, 5, 300)
      if clmx then ui.batch_midi_len_max_ms = vlmx; changed = true end

      r.ImGui_Separator(ctx)
      local caf, vaf = r.ImGui_Checkbox(ctx, 'Auto fit render range##cfg_batch_midi_autofit', ui.batch_midi_autofit_range == true)
      if caf then ui.batch_midi_autofit_range = vaf; changed = true end
      hoverTip(ctx, 'In One-Shot with no Time Selection, fit render item length to MIDI note length (including random length) plus a small tail.')

      r.ImGui_Separator(ctx)
      r.ImGui_Text(ctx, 'Applies to One-Shot Print/Batch trigger notes.')
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_Separator(ctx)
    local row_w = r.ImGui_GetContentRegionAvail(ctx)
    local half_btn = (row_w - 8) * 0.5
    if r.ImGui_Button(ctx, 'PRINT##cfg_print', half_btn, 30) then actions.print_now = true end
    hoverTip(ctx, 'Single offline render to the stem track using current parameters.')
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'BATCH PRINT##cfg_batch_print', -1, 30) then actions.print_batch = true end
    hoverTip(ctx, 'Renders N items in sequence. At start, asks how to place results across tracks.')

    r.ImGui_TableNextColumn(ctx)
    secHeader(ctx, 'User Presets')
    local unames = ui.user_preset_names or {}
    r.ImGui_SetNextItemWidth(ctx, -60)
    local cun, vun = r.ImGui_InputText(ctx, '##cfg_uname', ui.user_preset_input or '')
    if cun then ui.user_preset_input = vun end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x8C6A2DFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA87E37FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xC09342FF)
    if r.ImGui_Button(ctx, 'Save##cfg_usave', -1, 0) then
      local nm = ui.user_preset_input or ''
      if nm ~= '' then actions.save_user_preset = nm end
    end
    r.ImGui_PopStyleColor(ctx, 3)

    local combo_preview = unames[ui.user_preset_sel or 1] or '(none saved)'
    r.ImGui_SetNextItemWidth(ctx, -1)
    if r.ImGui_BeginCombo(ctx, 'Preset##cfg_ucombo', combo_preview) then
      for i = 1, #unames do
        r.ImGui_PushID(ctx, i + 1000)
        local sel = (ui.user_preset_sel == i)
        if r.ImGui_Selectable(ctx, unames[i] .. '##cfg_uitem', sel) then
          ui.user_preset_sel = i
        end
        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_Button(ctx, 'Load##cfg_uload', -70, 0) then
      local nm = unames[ui.user_preset_sel or 1]
      if nm then actions.load_user_preset = nm end
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x7A2A2AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x963434FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB24242FF)
    if r.ImGui_Button(ctx, 'Del##cfg_udel', -1, 0) then
      local nm = unames[ui.user_preset_sel or 1]
      if nm then actions.delete_user_preset = nm end
    end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_Separator(ctx)
    local morph_enabled = ui.morph_enabled == true
    local cme, vme = r.ImGui_Checkbox(ctx, 'Activate##cfg_morph_enabled', morph_enabled)
    if cme then ui.morph_enabled = vme; changed = true end
    hoverTip(ctx, 'When enabled, A/B and Mix changes are applied in realtime. Disable to tweak manually without preset overwrite.')
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, 'User Morph')
    if #unames > 0 then
      local morph_items = table.concat(unames, '\0') .. '\0'
      ui.morph_user_a_sel = math.floor(tonumber(ui.morph_user_a_sel) or 1)
      ui.morph_user_b_sel = math.floor(tonumber(ui.morph_user_b_sel) or 1)
      if ui.morph_user_a_sel < 1 then ui.morph_user_a_sel = 1 end
      if ui.morph_user_b_sel < 1 then ui.morph_user_b_sel = 1 end
      if ui.morph_user_a_sel > #unames then ui.morph_user_a_sel = #unames end
      if ui.morph_user_b_sel > #unames then ui.morph_user_b_sel = #unames end

      local full_w = r.ImGui_GetContentRegionAvail(ctx)
      local half_w = math.max(60, (full_w - 8) * 0.5)
      r.ImGui_SetNextItemWidth(ctx, half_w)
      local ca, va = r.ImGui_Combo(ctx, '##cfg_morph_user_a', (ui.morph_user_a_sel - 1), morph_items)
      if ca then
        ui.morph_user_a_sel = va + 1
        changed = true
        if ui.morph_enabled == true then actions.apply_morph = true end
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local cb, vb = r.ImGui_Combo(ctx, '##cfg_morph_user_b', (ui.morph_user_b_sel - 1), morph_items)
      if cb then
        ui.morph_user_b_sel = vb + 1
        changed = true
        if ui.morph_enabled == true then actions.apply_morph = true end
      end

      r.ImGui_Text(ctx, 'Mix')
      r.ImGui_SetNextItemWidth(ctx, -1)
      local ct, vt = r.ImGui_SliderDouble(ctx, '##cfg_morph_t_slider', tonumber(ui.morph_t) or 0.5, 0.0, 1.0)
      if ct then
        ui.morph_t = vt
        changed = true
        if ui.morph_enabled == true then actions.apply_morph = true end
      end
      hoverTip(ctx, 'Realtime morph between User Preset A and B. 0 = A, 1 = B.')
    else
      r.ImGui_Text(ctx, 'No user presets saved yet.')
    end

    r.ImGui_Separator(ctx)
    state.rand_style = math.floor(tonumber(state.rand_style) or 1)
    if state.rand_style < 0 or state.rand_style > 2 then
      state.rand_style = 1
    end
    r.ImGui_Text(ctx, 'Randomize Style')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local crs, vrs = r.ImGui_Combo(ctx, '##r_style', state.rand_style, table.concat(RAND_STYLE_NAMES, '\0') .. '\0')
    if crs then state.rand_style = vrs; changed = true end

    r.ImGui_Separator(ctx)
    local m = state.rand_masks
    local c1, v1 = r.ImGui_Checkbox(ctx, 'Osc##r_osc', m.osc); if c1 then m.osc = v1; changed = true end
    r.ImGui_SameLine(ctx)
    local c2, v2 = r.ImGui_Checkbox(ctx, 'Pkt##r_pkt', m.packet); if c2 then m.packet = v2; changed = true end
    r.ImGui_SameLine(ctx)
    local c3, v3 = r.ImGui_Checkbox(ctx, 'Nse##r_nse', m.noise); if c3 then m.noise = v3; changed = true end
    r.ImGui_SameLine(ctx)
    local c4, v4 = r.ImGui_Checkbox(ctx, 'Mod##r_mod', m.modulation); if c4 then m.modulation = v4; changed = true end
    r.ImGui_SameLine(ctx)
    local c5, v5 = r.ImGui_Checkbox(ctx, 'Cha##r_cha', m.chaos); if c5 then m.chaos = v5; changed = true end
    r.ImGui_SameLine(ctx)
    local c6, v6 = r.ImGui_Checkbox(ctx, 'Tail##r_tail', m.tail); if c6 then m.tail = v6; changed = true end
    r.ImGui_SameLine(ctx)
    local c7, v7 = r.ImGui_Checkbox(ctx, 'Fam##r_fam', m.family); if c7 then m.family = v7; changed = true end
    r.ImGui_Separator(ctx)
    local rand_row_w = r.ImGui_GetContentRegionAvail(ctx)
    local rand_btn_w = (rand_row_w - 8) * 0.5
    if r.ImGui_Button(ctx, 'Preview Randomize##rand_preview', rand_btn_w, 0) then actions.undo_randomize = true end
    hoverTip(ctx, 'Restores the previous state before the last randomize action.')
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Next Randomize##rand_next', -1, 0) then actions.randomize = true end
    hoverTip(ctx, 'Generates a new random variation using the current masks and style.')

    r.ImGui_EndTable(ctx)
  end

  return changed
end

local function drawLayersSection(ctx, state)
  local changed = false
  local synth = state.synth

  secHeader(ctx, 'Layers')

  local tflags = r.ImGui_TableFlags_BordersInnerV()
  if r.ImGui_BeginTable(ctx, 'layers_tbl##layout', 5, tflags) then
    r.ImGui_TableSetupColumn(ctx, 'Digital', 0)
    r.ImGui_TableSetupColumn(ctx, 'Packet', 0)
    r.ImGui_TableSetupColumn(ctx, 'Noise', 0)
    r.ImGui_TableSetupColumn(ctx, 'Resonator', 0)
    r.ImGui_TableSetupColumn(ctx, 'Chaos', 0)
    r.ImGui_TableHeadersRow(ctx)

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Gain##dig_gain', synth.layer_gain_digital, 0.0, 1.0)
    if c1 then synth.layer_gain_digital = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Intensity##dig_int', synth.intensity, 0.0, 1.0)
    if c2 then synth.intensity = v2; changed = true end
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Color##dig_color', synth.color, 0.0, 1.0)
    if c3 then synth.color = v3; changed = true end
    local c4, v4 = r.ImGui_SliderDouble(ctx, 'Pitch st##dig_pitch', synth.pitch, -24.0, 24.0)
    if c4 then synth.pitch = v4; changed = true end

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Gain##pkt_gain', synth.layer_gain_packet, 0.0, 1.0)
    if c1 then synth.layer_gain_packet = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Complexity##pkt_comp', synth.complexity, 0.0, 1.0)
    if c2 then synth.complexity = v2; changed = true end
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Timbre X##pkt_tx', synth.pad_timbre_x, 0.0, 1.0)
    if c3 then synth.pad_timbre_x = v3; changed = true end

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Gain##nse_gain', synth.layer_gain_noise, 0.0, 1.0)
    if c1 then synth.layer_gain_noise = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Dirt##nse_dirt', synth.dirt, 0.0, 1.0)
    if c2 then synth.dirt = v2; changed = true end
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Drive##nse_drive', synth.drive, 0.0, 1.0)
    if c3 then synth.drive = v3; changed = true end

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Gain##res_gain', synth.layer_gain_resonator, 0.0, 1.0)
    if c1 then synth.layer_gain_resonator = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Tail##res_tail', synth.tail, 0.0, 1.0)
    if c2 then synth.tail = v2; changed = true end
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Spread##res_spread', synth.spread, 0.0, 1.0)
    if c3 then synth.spread = v3; changed = true end
    local c4, v4 = r.ImGui_SliderDouble(ctx, 'Timbre Y##res_ty', synth.pad_timbre_y, 0.0, 1.0)
    if c4 then synth.pad_timbre_y = v4; changed = true end

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Gain##cha_gain', synth.layer_gain_chaos, 0.0, 1.0)
    if c1 then synth.layer_gain_chaos = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Mix##cha_mix', synth.chaos_mix, 0.0, 1.0)
    if c2 then synth.chaos_mix = v2; changed = true end
    local c3, v3 = r.ImGui_Combo(ctx, '##cha_mode', synth.chaos_mode, table.concat(CHAOS_MODE_NAMES, '\0') .. '\0')
    if c3 then synth.chaos_mode = v3; changed = true end
    local c4, v4 = r.ImGui_SliderDouble(ctx, 'Motion##cha_motion', synth.motion, 0.0, 1.0)
    if c4 then synth.motion = v4; changed = true end

    r.ImGui_EndTable(ctx)
  end

  return changed
end

local function drawEngineSection(ctx, state, actions)
  local changed = false
  local synth = state.synth

  secHeader(ctx, 'Post FX')
  hoverTip(ctx, 'Post FX layers (Engine 2) depend on Family and Character, so audibility can differ across families.')

  local tflags = r.ImGui_TableFlags_BordersInnerV()
  if r.ImGui_BeginTable(ctx, 'engine_tbl##layout', 5, tflags) then
    r.ImGui_TableSetupColumn(ctx, 'Character', 0)
    r.ImGui_TableSetupColumn(ctx, 'Grain Mix', 0)
    r.ImGui_TableSetupColumn(ctx, 'Spectral Mix', 0)
    r.ImGui_TableSetupColumn(ctx, 'Reverse Mix', 0)
    r.ImGui_TableSetupColumn(ctx, 'Safety & Mode', 0)
    r.ImGui_TableHeadersRow(ctx)

    -- Column 1: Character
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c1, v1 = r.ImGui_SliderDouble(ctx, 'Mix##eng_char', synth.character or 0.5, 0.0, 1.0)
    if c1 then synth.character = v1; changed = true end
    hoverTip(ctx, 'Main macro for Post FX intensity. Low values can almost disable E2 layers.')

    -- Column 2: Grain Mix
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Mix##eng_grain', synth.e2_grain_mix or 0.55, 0.0, 1.0)
    if c2 then synth.e2_grain_mix = v2; changed = true end
    hoverTip(ctx, 'Controls contribution of the granular layer in Post FX.')
    r.ImGui_Text(ctx, 'Granular impulses')

    -- Column 3: Spectral Mix
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Mix##eng_spectral', synth.e2_spectral_mix or 0.50, 0.0, 1.0)
    if c3 then synth.e2_spectral_mix = v3; changed = true end
    hoverTip(ctx, 'Controls the spectral shimmer layer. In Economy mode it runs a simplified calculation.')
    r.ImGui_Text(ctx, 'Spectral shimmer')

    -- Column 4: Reverse Mix
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c4, v4 = r.ImGui_SliderDouble(ctx, 'Mix##eng_reverse', synth.e2_reverse_mix or 0.48, 0.0, 1.0)
    if c4 then synth.e2_reverse_mix = v4; changed = true end
    hoverTip(ctx, 'Controls the reverse resonator layer.')
    r.ImGui_Text(ctx, 'Reverse resonator')

    -- Column 5: Safety & Mode
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Spacing(ctx)
    local c5, v5 = r.ImGui_SliderDouble(ctx, 'Safety##eng_safety', synth.e2_safety or 0.65, 0.0, 1.0)
    if c5 then synth.e2_safety = v5; changed = true end
    hoverTip(ctx, 'Output protection amount: anti-DC filtering plus peak limiting.')
    local quality_bool = (tonumber(synth.e2_cpu_quality) or 1) >= 0.5
    local cq, vq = r.ImGui_Checkbox(ctx, 'High CPU Mode##eng_cpu_quality', quality_bool)
    if cq then synth.e2_cpu_quality = vq and 1 or 0; changed = true end
    hoverTip(ctx, 'High CPU = more detailed spectral processing. Economy = lower CPU usage.')

    r.ImGui_EndTable(ctx)
  end

  return changed
end

local function drawModulationSection(ctx, state)
  local changed = false
  local synth = state.synth

  secHeader(ctx, 'Modulation')

  local tflags = r.ImGui_TableFlags_BordersInnerV()
  if r.ImGui_BeginTable(ctx, 'mod_tbl##layout', 4, tflags) then
    r.ImGui_TableSetupColumn(ctx, 'col_timbre', r.ImGui_TableColumnFlags_WidthStretch(), 0.25)
    r.ImGui_TableSetupColumn(ctx, 'col_motion', r.ImGui_TableColumnFlags_WidthStretch(), 0.25)
    r.ImGui_TableSetupColumn(ctx, 'col_user', r.ImGui_TableColumnFlags_WidthStretch(), 0.25)
    r.ImGui_TableSetupColumn(ctx, 'col_lfo', r.ImGui_TableColumnFlags_WidthStretch(), 0.25)

    r.ImGui_TableNextColumn(ctx)
    changed = drawBindPad(ctx, synth, {
      id = 'timbre_bind', title = 'Timbre Pad',
      pad_x = 'timbre_pad_x', pad_y = 'timbre_pad_y',
      x_target = 'timbre_x_target', y_target = 'timbre_y_target',
      x_amount = 'timbre_x_amount', y_amount = 'timbre_y_amount',
      x_invert = 'timbre_x_invert', y_invert = 'timbre_y_invert'
    }) or changed

    r.ImGui_TableNextColumn(ctx)
    changed = drawBindPad(ctx, synth, {
      id = 'motion_bind', title = 'Motion Pad',
      pad_x = 'motion_pad_x', pad_y = 'motion_pad_y',
      x_target = 'motion_x_target', y_target = 'motion_y_target',
      x_amount = 'motion_x_amount', y_amount = 'motion_y_amount',
      x_invert = 'motion_x_invert', y_invert = 'motion_y_invert'
    }) or changed

    r.ImGui_TableNextColumn(ctx)
    changed = drawBindPad(ctx, synth, {
      id = 'user_bind', title = 'User Pad',
      pad_x = 'bind_pad_x', pad_y = 'bind_pad_y',
      x_target = 'bind_x_target', y_target = 'bind_y_target',
      x_amount = 'bind_x_amount', y_amount = 'bind_y_amount',
      x_invert = 'bind_x_invert', y_invert = 'bind_y_invert'
    }) or changed

    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, 'LFO 1')
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Wave')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c1, v1 = r.ImGui_Combo(ctx, '##mod_lfo1_wave', synth.lfo1_wave, table.concat(LFO_WAVE_NAMES, '\0') .. '\0')
    if c1 then synth.lfo1_wave = v1; changed = true end
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Rate##mod_lfo1_rate', synth.lfo_rate, 0.05, 12.0)
    if c2 then synth.lfo_rate = v2; changed = true end
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Depth##mod_lfo1_depth', synth.lfo_depth, 0.0, 1.0)
    if c3 then synth.lfo_depth = v3; changed = true end

    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'LFO 2 / MSEG')
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, 'Wave')
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c4, v4 = r.ImGui_Combo(ctx, '##mod_lfo2_wave', synth.lfo2_wave, table.concat(LFO_WAVE_NAMES, '\0') .. '\0')
    if c4 then synth.lfo2_wave = v4; changed = true end
    local c5, v5 = r.ImGui_SliderDouble(ctx, 'Rate##mod_lfo2_rate', synth.lfo2_rate, 0.05, 12.0)
    if c5 then synth.lfo2_rate = v5; changed = true end
    local c6, v6 = r.ImGui_SliderDouble(ctx, 'Depth##mod_lfo2_depth', synth.lfo2_depth, 0.0, 1.0)
    if c6 then synth.lfo2_depth = v6; changed = true end
    local c7, v7 = r.ImGui_SliderDouble(ctx, 'MSEG Depth##mod_mseg_depth', synth.mseg_depth, 0.0, 1.0)
    if c7 then synth.mseg_depth = v7; changed = true end

    r.ImGui_EndTable(ctx)
  end

  return changed
end

function MainUI.Draw(ctx, state, preset_names, user_preset_names)
  local changed = false
  state.ui.user_preset_names = user_preset_names or {}

  local actions = {
    push_now = false,
    apply_preset = nil,
    print_now = false,
    print_batch = false,
    apply_morph = false,
    randomize = false,
    undo_randomize = false,
    quick_profile = nil,
    save_user_preset = nil,
    load_user_preset = nil,
    delete_user_preset = nil
  }

  if r.ImGui_BeginMenuBar(ctx) then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_ACCENT)
    r.ImGui_Text(ctx, 'ReaSciFi')
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_SameLine(ctx)
    drawPresetCombo(ctx, state, preset_names, actions)
    r.ImGui_EndMenuBar(ctx)
  end

  changed = drawConfigRow(ctx, state, actions, preset_names) or changed
  changed = drawEngineSection(ctx, state, actions) or changed
  changed = drawLayersSection(ctx, state) or changed
  changed = drawModulationSection(ctx, state) or changed

  return changed, actions
end

return MainUI
