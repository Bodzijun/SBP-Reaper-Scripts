-- @description SBP ReaMotion Pad
-- @version 0.99
-- @author SBP & AI
-- @about
--   # SBP ReaMotion Pad
--   A powerful modulation and automation workstation for REAPER.

--   Features:
--   - Vector Pad for morphing between 4 parameter states.
--   - Master LFO and MSEG modulators with cross-modulation (FM/AM).
--   - Independent Modulator with 7 mixing modes (Individual, Add, Multiply, Subtract, Min, Max, Power).
--   - Real-time modulation preview and recording (Bake to automation items).
--   - Advanced LFO parameters: Rate Sweep, Depth Ramp, and Random Steps.
--   - Integrated preset system and state randomization.
--
--   [**Donate / Support**](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=bodzik@gmail.com&item_name=ReaMotionPad+Support&currency_code=USD)
-- @donation https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=bodzik@gmail.com&item_name=ReaMotionPad+Support&currency_code=USD

-- @changelog
--   v0.99 (2026-03-25)
--     + Prepare routing switched to folder parent-send offsets (no explicit child->folder sends).
--     + Added cleanup of legacy explicit sends to prevent 1/2 duplication.
--   v0.98 (2026-03-25)
--     + Fixed Prepare routing: Ext tracks correctly map to folder channels 1/2, 3/4, 5/6, 7/8.
--     + Fixed Prepare item positioning: without time selection, items keep original timeline position.
--   v0.97 (2026-03-25)
--     + External Mixer: fixed center volume dip for 4-corner morphing.
--     + Switched corner mix mapping to equal-power gain with proper JSFX dB slider conversion.
--   v0.96 (2026-03-05)
--     + Fixed dont't work Tack Volume and Pan modulation targets in Link mode.
--   v0.95 (2026-03-04)
--     + Added MIDI CC Modulation Support (MIDI Editor & Track Envelopes)
--     + Real-time modulation for MIDI Editor CC lanes (modwheel, pitch, etc.)
--     + "Bake" support for MIDI takes (Piano Roll)
--     + Automatic target detection for MIDI CC Track Envelopes
--     + UI feedback for active MIDI targets in Sel.Env mode
--     + increased Rate ranges for LFOs
--   v0.9 (2026-03-03)
--   - Added "Solo" mode for Selected Envelope (automatically disables other targets).
--   - Force LFO/MSEG power-on when Selected Envelope is enabled.
--   - Robust JSFX physical scaling fix using fx_type detection (fixes -20..20 slider issues).
--   - UI Exclusivity: Selected Envelope now mutually exclusive with Pad/Master targets.
--   - Fixed "Calling End() too many times!" ImGui error in Link popup.
--   - Fixed silent failure of Link button when track is not selected (added error message).
--   - Increased setup popup width to 310px to prevent label clipping.
--   - Dynamic visual feedback: Sel.Env uses orange color; modulators turn yellow when soloed.
--   v0.8 (2026-03-01)
--   - Integrated Modulator Math (Cross-Modulation) settings into Setup popups.
--   - Added 7 Mixing Modes for Independent LFO (Add, Multiply, Subtract, etc.).
--   - Improved LFO -> MSEG modulation visibility using multiplicative scaling (AM).
--   - Fixed Depth Ramp functionality and restored visual graph updates.
--   - Added 'Steps Rnd' slider for Randomize LFO shape (Setup Menu).
--   - Implemented Double-Click to Reset (to 0.0) for all advanced sliders.
--   - Refined Setup UI layout with right-aligned sliders and table-based labels.
--   - Optimized UI variable management for Independent Modulators.

-- @provides
--   [main] sbp_ReaMotionPad.lua
--   modules/State.lua
--   modules/SegmentEngine.lua
--   modules/PadEngine.lua
--   modules/BindingRegistry.lua
--   modules/AutomationWriter.lua
--   modules/UIHelpers.lua
--   modules/PadUI.lua
--   modules/MasterModulatorUI.lua
--   modules/IndependentModulatorUI.lua
--   modules/SettingsUI.lua
--   modules/LiveAutomation.lua
--   modules/Randomizer.lua
--   modules/PresetManager.lua
--   modules/JSFXSync.lua
--   modules/MorphEngine.lua
--   [nomain] sbp_ReaMotionPad_Mixer.jsfx

---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch, lowercase-global, deprecated

local r = reaper

local info = debug.getinfo(1, 'S')
local script_path = info.source:match('@(.*[\\/])') or ''
local shim = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
if r.file_exists(shim) then
  dofile(shim)
end
if not r.ImGui_CreateContext then
  return
end

local function loadModule(name)
  local ok, mod = pcall(dofile, script_path .. 'modules/' .. name .. '.lua')
  if not ok then
    return nil
  end
  return mod
end

-- Load all modules
local State = loadModule('State')
local SegmentEngine = loadModule('SegmentEngine')
local PadEngine = loadModule('PadEngine')
local BindingRegistry = loadModule('BindingRegistry')
local AutomationWriter = loadModule('AutomationWriter')
local UIHelpers = loadModule('UIHelpers')
local PadUI = loadModule('PadUI')
local MasterModulatorUI = loadModule('MasterModulatorUI')
local IndependentModulatorUI = loadModule('IndependentModulatorUI')
-- LinkModuleUI and ExternalUI: code integrated into PadUI and main script
local SettingsUI = loadModule('SettingsUI')
local LiveAutomation = loadModule('LiveAutomation')
local Randomizer = loadModule('Randomizer')
local PresetManager = loadModule('PresetManager')
local JSFXSync = loadModule('JSFXSync')
local MorphEngine = loadModule('MorphEngine')

if not (State and SegmentEngine and PadEngine and BindingRegistry and AutomationWriter) then
  return
end

local ctx = r.ImGui_CreateContext('SBP ReaMotion Pad')

-- Use colors from UIHelpers module
local COL_BG = UIHelpers.COL_BG
local COL_FRAME = UIHelpers.COL_FRAME
local COL_TEXT = UIHelpers.COL_TEXT
local COL_ACCENT = UIHelpers.COL_ACCENT
local COL_WARN = UIHelpers.COL_WARN
local COL_ORANGE = UIHelpers.COL_ORANGE
local COL_GRID = UIHelpers.COL_GRID
local COL_LINE = UIHelpers.COL_LINE
local COL_HANDLE = UIHelpers.COL_HANDLE
local COL_PANEL = UIHelpers.COL_PANEL

local PAD_W = 220
local PAD_H = 220
local SEG_H = 86

local AXIS_LIST = {
  'X',
  'Y'
}

local SIDE_LIST = {
  'Left',
  'Right',
  'Top',
  'Bottom'
}

local DIV_LIST = { 1, 2, 4, 8, 16 }
local EXT_MIXER_CANDIDATES = {
  'JS: sbp_ReaMotionPad_Mixer',
  'JS: Utility/sbp_ReaMotionPad_Mixer',
  'JS: IX/Mixer_8xS-1xS',
  'JS: Utility/8x Stereo to 1x Stereo Mixer',
  'JS: Utility/4x Stereo to 1x Stereo Mixer'
}

local app = {
  state = State.Load(),
  dirty = false,
  fx_cache = {},
  param_cache = {},
  status = '',
  auto_save_counter = 0
}

local interaction = {
  active_pad = nil,
  active_point = nil,
  seg_active_idx = nil,
  pad_setup_open = false,
  pad_setup_target = nil,
  pad_setup_jsfx_synced = false,
  options_open = false,
  modulator_param_setup_open = nil,
  write_auto = app.state.setup.auto_write,
  pending_write = false,
  pending_write_track = nil,
  pending_bake = false,
  pending_bake_track = nil,
  pending_bounce = false,
  pending_bounce_track = nil
}

if not app.state.setup then
  app.state.setup = {}
end
if app.state.setup.live_write_enabled == nil then
  app.state.setup.live_write_enabled = false
end
LiveAutomation.SetEnabled(app.state.setup.live_write_enabled)

local function clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end





local function getPadSegmentPositions(pad)
  if not pad then
    return { 0.0, 1.0 }
  end

  if type(pad.segment) ~= 'table' then
    pad.segment = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      curve_mode = 0,
      segment_shapes = { 0 }
    }
  end

  local seg = pad.segment

  -- Sync seg.points with actual pad.points count only if manual_positions is empty (first load)
  if pad.points and #pad.points >= 2 and (not seg.manual_positions or #seg.manual_positions == 0) then
    seg.points = #pad.points
  end

  local mode = math.floor(tonumber(seg.mode) or 0)

  if mode == 1 then
    local div = math.max(1, math.min(8, math.floor(tonumber(seg.division) or 2)))
    local count = div + 1
    seg.points = count -- Sync points count with musical segmentation
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = i / (count - 1)
    end
    return out
  end

  local points = math.max(2, math.min(8, math.floor(tonumber(seg.points) or 2)))
  if type(seg.manual_positions) ~= 'table' then
    seg.manual_positions = {}
  end

  local pos = seg.manual_positions

  -- Always ensure positions array matches seg.points count
  -- This handles both increasing and decreasing point count
  local need_update = (#pos ~= points)
  if not need_update and #pos > 0 then
    -- Check if positions are properly distributed
    local expected = (points - 1) > 0 and (1.0 / (points - 1)) or 0
    if #pos >= 2 then
      local actual_step = (pos[#pos] - pos[1]) / (#pos - 1)
      need_update = (math.abs(actual_step - expected) > 0.01)
    end
  end

  if need_update then
    -- Redistribute all positions evenly
    for i = 1, points do
      pos[i] = (i - 1) / (points - 1)
    end
  end

  -- Truncate or extend positions array to match points count
  for i = #pos, points + 1, -1 do
    pos[i] = nil
  end
  for i = #pos + 1, points do
    pos[i] = (i - 1) / (points - 1)
  end

  -- Lock first and last positions to time selection boundaries
  -- First point = start of time selection (0.0)
  -- Last point = end of time selection (1.0)
  pos[1] = 0.0
  pos[points] = 1.0

  -- Validate intermediate points
  for i = 2, points - 1 do
    local left = (pos[i - 1] or 0.0) + 0.01
    local right = (pos[i + 1] or 1.0) - 0.01
    pos[i] = clamp(pos[i] or 0.5, left, right)
  end

  return pos
end

local function ensureSegmentShapes(pad)
  if not pad then
    return
  end
  if type(pad.segment) ~= 'table' then
    return
  end

  local seg = pad.segment
  if type(seg.segment_shapes) ~= 'table' then
    seg.segment_shapes = {}
  end

  local positions = getPadSegmentPositions(pad)
  local count = math.max(1, #positions - 1)
  local default_shape = math.max(0, math.min(5, math.floor(tonumber(seg.curve_mode) or 0)))

  for i = 1, count do
    seg.segment_shapes[i] = math.max(0, math.min(5, math.floor(tonumber(seg.segment_shapes[i]) or default_shape)))
  end
  for i = #seg.segment_shapes, count + 1, -1 do
    seg.segment_shapes[i] = nil
  end
end

local function resegmentPadRealtime(pad)
  if not pad then
    return false
  end

  local positions = getPadSegmentPositions(pad)
  if #positions < 2 then
    return false
  end

  local old_points = pad.points
  local eval_at_x

  if old_points and #old_points >= 2 then
    local old_pad = { points = old_points, enabled = true }
    eval_at_x = function(x)
      return PadEngine.EvaluatePadY(old_pad, x)
    end
  elseif pad.sx ~= nil then
    local old_pad = {
      sx = pad.sx,
      sy = pad.sy,
      px = pad.px,
      py = pad.py,
      ex = pad.ex,
      ey = pad.ey,
      enabled = true
    }
    eval_at_x = function(x)
      return PadEngine.EvaluatePadY(old_pad, x)
    end
  else
    eval_at_x = function()
      return 0.5
    end
  end

  local changed = false
  local count_changed = (not old_points) or (#old_points ~= #positions)
  local new_points = {}

  -- Preserve start and end Y values from old points (prevent drift)
  -- Use the actual first/last point Y values, not interpolated ones
  local start_y = old_points and old_points[1] and tonumber(old_points[1].y) or 0.5
  local end_y = old_points and old_points[#old_points] and tonumber(old_points[#old_points].y) or 0.5

  -- Preserve start and end X positions from old points (prevent X drift on pad)
  local start_x = old_points and old_points[1] and tonumber(old_points[1].x) or 0.0
  local end_x = old_points and old_points[#old_points] and tonumber(old_points[#old_points].x) or 1.0

  -- Compute curve length and mapping for equidistant points along the curve
  local num_samples = 100
  local curve_lens = { 0.0 }
  local total_len = 0.0
  local prev_sx = start_x
  local prev_sy = start_y

  for i = 1, num_samples do
    local t_x = start_x + (end_x - start_x) * (i / num_samples)
    local t_y = eval_at_x(t_x)
    local dx = t_x - prev_sx
    local dy = t_y - prev_sy
    local segment_len = math.sqrt(dx * dx + dy * dy)
    total_len = total_len + segment_len
    curve_lens[i + 1] = total_len
    prev_sx = t_x
    prev_sy = t_y
  end

  for i = 1, #positions do
    local x_pos, y_val

    if i == 1 then
      x_pos = start_x
      y_val = start_y
    elseif i == #positions then
      x_pos = end_x
      y_val = end_y
    else
      -- Find X coordinate corresponding to evenly distributed length
      local target_len = total_len * ((i - 1) / (#positions - 1))

      -- Binary search or linear search for target_len in curve_lens
      local sample_idx = 1
      for j = 1, num_samples do
        if curve_lens[j + 1] >= target_len then
          sample_idx = j
          break
        end
      end

      local len_start = curve_lens[sample_idx]
      local len_end = curve_lens[sample_idx + 1]
      local fraction = 0.0
      if len_end > len_start then
        fraction = (target_len - len_start) / (len_end - len_start)
      end

      local t_start = (sample_idx - 1) / num_samples
      local t_end = sample_idx / num_samples
      local t = t_start + (t_end - t_start) * fraction

      x_pos = start_x + (end_x - start_x) * t
      y_val = eval_at_x(x_pos)
    end

    new_points[i] = { x = x_pos, y = clamp(y_val, 0.0, 1.0) }
  end

  if not old_points or #old_points ~= #new_points then
    changed = true
  else
    for i = 1, #new_points do
      local ox = tonumber(old_points[i].x) or 0.0
      local oy = tonumber(old_points[i].y) or 0.5
      if math.abs(ox - new_points[i].x) > 0.0001 or math.abs(oy - new_points[i].y) > 0.0001 then
        changed = true
        break
      end
    end
  end

  pad.points = new_points
  pad.sx = nil
  pad.sy = nil
  pad.px = nil
  pad.py = nil
  pad.ex = nil
  pad.ey = nil

  ensureSegmentShapes(pad)

  return changed
end

local function pushTheme()
  UIHelpers.PushTheme(ctx)
end

local function popTheme()
  UIHelpers.PopTheme(ctx)
end

local function markDirty()
  app.dirty = true
  app.state.dirty = true -- For LiveAutomation module
end

local function drawHeader(label)
  UIHelpers.DrawHeader(ctx, label)
end

local function getTargetTrack()
  local tr = UIHelpers.GetTargetTrack(app.state.setup)
  if tr and r.ValidatePtr(tr, 'MediaTrack*') then
    return tr
  end
  return nil
end

local function refreshFXCache(track)
  app.fx_cache = BindingRegistry.ListFX(track)
  app.param_cache = {}
end

local function getParams(track, fx_index)
  if fx_index < 0 then return {} end
  if not app.param_cache[fx_index] then
    app.param_cache[fx_index] = BindingRegistry.ListParams(track, fx_index)
  end
  return app.param_cache[fx_index]
end

local function randomizePad(p)
  p.sx = math.random()
  p.sy = math.random()
  p.px = math.random()
  p.py = math.random()
  p.ex = math.random()
  p.ey = math.random()
end

local function randomizeState()
  app.status = Randomizer.Randomize(app.state, markDirty)
end

-- Morph It function
local function morphIt()
  app.status = 'Processing morph...' -- Clear previous status

  local items = MorphEngine.GetSelectedItemsInTimeSelection()
  if #items == 0 then
    app.status = 'No items selected for morph'
    return
  end

  if #items > 4 then
    app.status = 'Maximum 4 items supported (for 4 stereo inputs to JSFX)'
    return
  end

  -- Get the first selected item's track to determine insert position
  local first_track = r.GetMediaItemTrack(items[1])
  local first_track_num = r.GetMediaTrackInfo_Value(first_track, 'IP_TRACKNUMBER')

  -- Create folder name based on selection
  local folder_name = 'Morph'
  if #items == 1 then
    local _, item_name = r.GetSetMediaItemInfo_String(items[1], 'P_NAME', '', false)
    if item_name and item_name ~= '' then
      folder_name = 'Morph: ' .. item_name
    end
  end

  -- Pass External pad data for envelope writing
  local ext_pad = app.state.external and app.state.external.pad

  -- Use settings from State - morph_mute_originals now means "copy and mute"
  local success, result = MorphEngine.MorphItems({
    folder_name = folder_name,
    insert_at_index = first_track_num - 1,
    copy_and_mute = app.state.setup.morph_mute_originals,
    ext_pad = ext_pad -- Pass External pad data
  }, app.state)

  if success and result then
    -- Set the folder track as the target track for the script
    local folder_track = result.folder_track
    if folder_track and result.child_tracks then
      local _, folder_name_str = r.GetSetMediaTrackInfo_String(folder_track, 'P_NAME', '', false)
      app.state.setup.target_track_name = folder_name_str or ''
      markDirty()
      app.status = string.format('Morphed %d items into folder with %d child tracks',
        #items, #result.child_tracks)
    else
      app.status = 'Morph completed but folder track is missing'
    end
  else
    local err_msg = result and tostring(result) or 'Unknown error'
    app.status = 'Morph failed: ' .. err_msg
  end
end

-- Preset system state
local preset_state = {
  selected_idx = -1,
  combo_list = '(none)\0',
  presets = {},
  save_popup_open = false,
  save_name = '',
  needs_refresh = true
}

local function refreshPresetList()
  if PresetManager then
    preset_state.presets = PresetManager.ListPresets(script_path)
    preset_state.combo_list = PresetManager.BuildComboList(preset_state.presets)
    -- Clamp selection
    if preset_state.selected_idx >= #preset_state.presets then
      preset_state.selected_idx = #preset_state.presets - 1
    end
    preset_state.needs_refresh = false
  end
end

local function drawTopBar(track)
  local setup = app.state.setup

  -- Refresh preset list on first frame or when flagged
  if preset_state.needs_refresh then
    refreshPresetList()
  end

  local action = UIHelpers.DrawTopBar(ctx, setup, markDirty, refreshFXCache, preset_state)

  if action == 'options' then
    interaction.options_open = true
  elseif action == 'reset' then
    local new_state = State.GetDefault()
    app.state = new_state
    markDirty()
    app.status = 'Reset to defaults'
  elseif action == 'preset_select' then
    -- Load selected preset
    local idx = preset_state.selected_idx + 1 -- 0-based -> 1-based
    local p = preset_state.presets[idx]
    if p then
      local data, err = PresetManager.LoadPresetFile(p.path)
      if data then
        PresetManager.ApplyPresetData(app.state, data)
        markDirty()
        app.status = 'Loaded preset: ' .. p.name
      else
        app.status = 'Error loading preset: ' .. tostring(err)
      end
    end
  elseif action == 'preset_save' then
    -- Open save dialog
    preset_state.save_popup_open = true
    -- Default name: current preset name or track name
    local idx = preset_state.selected_idx + 1
    local p = preset_state.presets[idx]
    if p then
      preset_state.save_name = p.name
    else
      preset_state.save_name = setup.target_track_name ~= '' and setup.target_track_name or 'My Preset'
    end
    r.ImGui_OpenPopup(ctx, 'Save Preset##save_popup')
  elseif action == 'preset_delete' then
    local idx = preset_state.selected_idx + 1
    local p = preset_state.presets[idx]
    if p then
      PresetManager.DeletePresetFile(p.path)
      preset_state.needs_refresh = true
      preset_state.selected_idx = -1
      app.status = 'Deleted preset: ' .. p.name
    end
  end

  -- Save popup
  if r.ImGui_BeginPopupModal(ctx, 'Save Preset##save_popup', true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
    r.ImGui_Text(ctx, 'Preset name:')
    r.ImGui_SetNextItemWidth(ctx, 250)
    local c_n, v_n = r.ImGui_InputText(ctx, '##preset_save_name', preset_state.save_name)
    if c_n then preset_state.save_name = v_n end

    r.ImGui_Dummy(ctx, 0, 6)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x38A882FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x25755AFF)
    if r.ImGui_Button(ctx, 'Save##confirm', 120, 0) then
      if preset_state.save_name ~= '' then
        local ok, path = PresetManager.SavePresetFile(script_path, preset_state.save_name, app.state)
        if ok then
          app.status = 'Saved preset: ' .. preset_state.save_name
          preset_state.needs_refresh = true
          -- Select the saved preset
          refreshPresetList()
          for i, p in ipairs(preset_state.presets) do
            if p.name == preset_state.save_name then
              preset_state.selected_idx = i - 1
              break
            end
          end
        else
          app.status = 'Error saving preset'
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_SameLine(ctx, 0, 8)
    if r.ImGui_Button(ctx, 'Cancel##cancel_save', 120, 0) then
      r.ImGui_CloseCurrentPopup(ctx)
    end

    r.ImGui_EndPopup(ctx)
  end
end

local pad_ui_params = {
  interaction = interaction,
  markDirty = markDirty,
  resegmentPadRealtime = resegmentPadRealtime,
  getPadSegmentPositions = getPadSegmentPositions,
  ensureSegmentShapes = ensureSegmentShapes,
}

local function drawVectorPad(title, pad, id, w, h, corner_labels, seg_id)
  return PadUI.DrawVectorPad(ctx, title, pad, id, w, h, corner_labels, seg_id, pad_ui_params)
end

local function drawPadSegmentationModule(pad, seg_id, w)
  PadUI.DrawSegmentationModule(ctx, pad, seg_id, w, pad_ui_params)
end

-- Forward declarations
local getIndependentLFO
local getIndependentMSEG
local evaluateIndependentMSEGAt

local function drawPadGrid()
  local src = app.state.external and app.state.external.sources or {}
  local external_corner_labels = {
    tl = (src[1] and src[1].name) or 'Ext 1',
    tr = (src[2] and src[2].name) or 'Ext 2',
    bl = (src[3] and src[3].name) or 'Ext 3',
    br = (src[4] and src[4].name) or 'Ext 4'
  }

  -- Helper: build corner labels from link binding source param names
  local function buildLinkCornerLabels(pad, defaults)
    local link_cfg = pad and pad.link
    if not link_cfg or not link_cfg.sources then return defaults end
    local labels = {}
    local keys = { 'tl', 'tr', 'bl', 'br' }
    local default_names = { 'Param 1', 'Param 2', 'Param 3', 'Param 4' }
    for i = 1, 4 do
      local src = link_cfg.sources[i]
      local name = nil
      if src and src.enabled ~= false then
        if src.target_type == 'track_vol' then
          name = 'Trk Vol'
        elseif src.target_type == 'track_pan' then
          name = 'Trk Pan'
        elseif src.param_name and src.param_name ~= '' then
          name = src.param_name:sub(1, 12)
        end
      end
      labels[keys[i]] = name or default_names[i]
    end
    return labels
  end

  if r.ImGui_BeginTable(ctx, 'pad_grid_main', 4, r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, 'c1', r.ImGui_TableColumnFlags_WidthFixed(), PAD_W + 14)
    r.ImGui_TableSetupColumn(ctx, 'c2', r.ImGui_TableColumnFlags_WidthFixed(), PAD_W + 14)
    r.ImGui_TableSetupColumn(ctx, 'c3', r.ImGui_TableColumnFlags_WidthFixed(), PAD_W + 14)
    r.ImGui_TableSetupColumn(ctx, 'c4', r.ImGui_TableColumnFlags_WidthFixed(), 430)

    r.ImGui_TableNextColumn(ctx)
    local ok1, err1 = pcall(drawVectorPad, 'External Mixer', app.state.external.pad, '##pad_ext', PAD_W, PAD_H,
      external_corner_labels, 'seg_ext')
    local ok2, err2 = pcall(drawPadSegmentationModule, app.state.external.pad, 'seg_ext', PAD_W)

    r.ImGui_TableNextColumn(ctx)
    local link_a_labels = buildLinkCornerLabels(app.state.pads.link_a)
    local ok3, err3 = pcall(drawVectorPad, 'Link A', app.state.pads.link_a, '##pad_a', PAD_W, PAD_H, link_a_labels,
      'seg_a')
    local ok4, err4 = pcall(drawPadSegmentationModule, app.state.pads.link_a, 'seg_a', PAD_W)

    r.ImGui_TableNextColumn(ctx)
    local link_b_labels = buildLinkCornerLabels(app.state.pads.link_b)
    local ok5, err5 = pcall(drawVectorPad, 'Link B', app.state.pads.link_b, '##pad_b', PAD_W, PAD_H, link_b_labels,
      'seg_b')
    local ok6, err6 = pcall(drawPadSegmentationModule, app.state.pads.link_b, 'seg_b', PAD_W)

    r.ImGui_TableNextColumn(ctx)
    local tr = getTargetTrack()
    local fx_l = tr and BindingRegistry.ListFX(tr) or {}
    local eval_mixed = function(t)
      local lfo = getIndependentLFO()
      local mseg_raw = evaluateIndependentMSEGAt(t)
      local mseg_val = mseg_raw

      local lfo_params = {
        enabled = true,
        rate = lfo.rate,
        rate_sweep = lfo.rate_sweep,
        depth_ramp = lfo.depth_ramp,
        shape = lfo.shape,
        invert = lfo.invert,
        random_steps = lfo.random_steps,
        depth = clamp((lfo.depth or 0.6) + (mseg_raw * (lfo.mseg_to_lfo_depth or 0.0)), 0.0, 1.0),
        offset = clamp(lfo.offset or 0.5, 0.0, 1.0),
        phase_offset = mseg_raw * (lfo.mseg_to_lfo_rate or 0.0)
      }

      local lfo_val = PadEngine.EvaluateLFO(lfo_params, t)

      local mseg_mod_amt = lfo.lfo_to_mseg_depth or 0.0
      if mseg_mod_amt ~= 0 then
        -- Multiplicative modulation for better visibility
        mseg_val = clamp(mseg_raw * (1.0 + (lfo_val - 0.5) * mseg_mod_amt * 2.0), 0.0, 1.0)
      end

      local mode = math.floor(tonumber(lfo.mode) or 0)
      if mode == 1 then     -- Add
        return clamp(mseg_val + (lfo_val - 0.5), 0.0, 1.0)
      elseif mode == 2 then -- Multiply
        return clamp(mseg_val * (lfo_val * 2.0), 0.0, 1.0)
      elseif mode == 3 then -- Subtract
        return clamp(mseg_val - lfo_val, 0.0, 1.0)
      elseif mode == 4 then -- Min
        return math.min(mseg_val, lfo_val)
      elseif mode == 5 then -- Max
        return math.max(mseg_val, lfo_val)
      elseif mode == 6 then -- Power
        return clamp(mseg_val ^ (lfo_val * 4.0), 0.0, 1.0)
      end
      -- Replace
      return lfo_val
    end
    local ok7, err7 = pcall(IndependentModulatorUI.DrawModule, ctx, 420, PAD_H, getIndependentLFO, getIndependentMSEG,
      eval_mixed, evaluateIndependentMSEGAt,
      markDirty, interaction, tr, fx_l, app.state.setup.auto_write.sel_env)
    if not ok7 then
      r.ImGui_TextColored(ctx, 0xFF0000FF, 'Error drawing mod UI:\n' .. tostring(err7))
    end

    r.ImGui_EndTable(ctx)
  end
end

local function getMasterMSEG()
  if type(app.state.master_mseg) ~= 'table' then
    app.state.master_mseg = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      curve_mode = 0,
      segment_shapes = { 0 },
      values = { 0.8, 0.8 },
      selected_segment = 1,
      apply_all_shapes = false,
      curve_tension = 0.0
    }
  end
  if app.state.master_mseg.apply_all_shapes == nil then
    app.state.master_mseg.apply_all_shapes = false
  end
  if app.state.master_mseg.curve_tension == nil then
    app.state.master_mseg.curve_tension = 0.0
  end
  return app.state.master_mseg
end

local function getMasterLFO()
  local sync_divisions = { 2, 4, 8, 16, 32, 64 }

  if type(app.state.master_lfo) ~= 'table' then
    app.state.master_lfo = {
      enabled = false,
      rate = 2.0,
      depth = 0.6,
      offset = 0.5,
      shape = 0,
      mode = 0,
      sync_to_bpm = false,
      random_steps = 8,
      sync_div_idx = 2,
      rate_sweep = 0.0 -- Rate sweep: -1 to 1 (negative = decay, positive = increase)
    }
  end

  local lfo = app.state.master_lfo
  if lfo.enabled == nil then lfo.enabled = false end
  if lfo.sync_to_bpm == nil then lfo.sync_to_bpm = false end
  if lfo.random_steps == nil then lfo.random_steps = 8 end
  if lfo.sync_div_idx == nil then lfo.sync_div_idx = 2 end
  if lfo.rate_sweep == nil then lfo.rate_sweep = 0.0 end
  lfo.rate = clamp(tonumber(lfo.rate) or 2.0, 0.05, 256.0)
  lfo.depth = clamp(tonumber(lfo.depth) or 0.6, 0.0, 1.0)
  lfo.offset = clamp(tonumber(lfo.offset) or 0.5, 0.0, 1.0)
  lfo.shape = math.max(0, math.min(5, math.floor(tonumber(lfo.shape) or 0)))
  lfo.mode = math.max(0, math.min(6, math.floor(tonumber(lfo.mode) or 0)))
  lfo.random_steps = math.max(2, math.min(32, math.floor(tonumber(lfo.random_steps) or 8)))
  lfo.sync_div_idx = math.max(1, math.min(#sync_divisions, math.floor(tonumber(lfo.sync_div_idx) or 2)))
  lfo.rate_sweep = clamp(tonumber(lfo.rate_sweep) or 0.0, -1.0, 1.0)

  -- Synchronize with BPM if enabled
  if lfo.sync_to_bpm then
    local bpm = r.Master_GetTempo()
    local div = sync_divisions[lfo.sync_div_idx] or 4
    local mult = div / 4.0
    lfo.rate = math.max(0.05, math.min(256.0, (bpm / 60.0) * mult))
    local sync_grid = { 2, 3, 4, 6, 8, 12, 16, 24, 32 }
    local best = sync_grid[1]
    local best_d = math.abs(lfo.random_steps - best)
    for i = 2, #sync_grid do
      local d = math.abs(lfo.random_steps - sync_grid[i])
      if d < best_d then
        best_d = d
        best = sync_grid[i]
      end
    end
    lfo.random_steps = best
  end

  return lfo
end

getIndependentLFO = function()
  local sync_divisions = { 2, 4, 8, 16, 32, 64 }

  if not app.state.independent_modulator then
    app.state.independent_modulator = {}
  end
  if not app.state.independent_modulator.lfo then
    app.state.independent_modulator.lfo = {
      enabled = false,
      rate = 2.0,
      depth = 0.6,
      offset = 0.5,
      shape = 0,
      mode = 1, -- режим індивідуал за замовченням
      sync_to_bpm = false,
      random_steps = 8,
      sync_div_idx = 2,
      waveform_name = "Sine",
      phase = 0.0,
      random_seed = 1000,
      rate_sweep = 0.0, -- Rate sweep: -1 to 1
      param = {
        enabled = false,
        fx_guid = '',
        fx_name = '',
        param_index = 0,
        param_name = '',
        min = 0.0,
        max = 1.0,
        invert = false,
        search = '',
        curve = 'linear',
        bipolar = false,
        scale = 1.0,
        offset = 0.0
      }
    }
  end

  local lfo = app.state.independent_modulator.lfo
  if lfo.enabled == nil then lfo.enabled = false end
  if lfo.sync_to_bpm == nil then lfo.sync_to_bpm = false end
  if lfo.random_steps == nil then lfo.random_steps = 8 end
  if lfo.sync_div_idx == nil then lfo.sync_div_idx = 2 end
  if lfo.waveform_name == nil then lfo.waveform_name = "Sine" end
  if lfo.phase == nil then lfo.phase = 0.0 end
  if lfo.random_seed == nil then lfo.random_seed = 1000 end
  if lfo.rate_sweep == nil then lfo.rate_sweep = 0.0 end
  if type(lfo.param) ~= 'table' then
    lfo.param = {
      enabled = false,
      fx_guid = '',
      fx_name = '',
      param_index = 0,
      param_name = '',
      min = 0.0,
      max = 1.0,
      invert = false,
      search = '',
      curve = 'linear',
      bipolar = false,
      scale = 1.0,
      offset = 0.0
    }
  else
    if lfo.param.curve == nil then lfo.param.curve = 'linear' end
    if lfo.param.bipolar == nil then lfo.param.bipolar = false end
    if lfo.param.scale == nil then lfo.param.scale = 1.0 end
    if lfo.param.offset == nil then lfo.param.offset = 0.0 end
  end
  -- Auto-migrate min/max for JSFX if needed (як у Link)
  if lfo.param.fx_guid ~= '' and lfo.param.param_index ~= nil then
    local track = getTargetTrack()
    if track then
      for i, fx in ipairs(BindingRegistry.ListFX(track)) do
        if fx.guid == lfo.param.fx_guid then
          local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx.index, lfo.param.param_index)
          if p_min ~= nil and p_max ~= nil and p_max > p_min then
            if (lfo.param.min == 0 and lfo.param.max == 1) or (lfo.param.min == nil or lfo.param.max == nil) then
              lfo.param.min = p_min
              lfo.param.max = p_max
            end
          end
        end
      end
    end
  end
  lfo.rate = clamp(tonumber(lfo.rate) or 2.0, 0.05, 256.0)
  lfo.depth = clamp(tonumber(lfo.depth) or 0.6, 0.0, 1.0)
  lfo.offset = clamp(tonumber(lfo.offset) or 0.5, 0.0, 1.0)
  lfo.shape = math.max(0, math.min(5, math.floor(tonumber(lfo.shape) or 0)))
  lfo.mode = math.max(0, math.min(6, math.floor(tonumber(lfo.mode) or 0)))
  lfo.random_steps = math.max(2, math.min(32, math.floor(tonumber(lfo.random_steps) or 8)))
  lfo.sync_div_idx = math.max(1, math.min(#sync_divisions, math.floor(tonumber(lfo.sync_div_idx) or 2)))

  if lfo.sync_to_bpm then
    local bpm = r.Master_GetTempo()
    local div = sync_divisions[lfo.sync_div_idx] or 4
    local mult = div / 4.0
    lfo.rate = math.max(0.05, math.min(256.0, (bpm / 60.0) * mult))
    local sync_grid = { 2, 3, 4, 6, 8, 12, 16, 24, 32 }
    local best = sync_grid[1]
    local best_d = math.abs(lfo.random_steps - best)
    for i = 2, #sync_grid do
      local d = math.abs(lfo.random_steps - sync_grid[i])
      if d < best_d then
        best_d = d
        best = sync_grid[i]
      end
    end
    lfo.random_steps = best
  end

  return lfo
end

getIndependentMSEG = function()
  if not app.state.independent_modulator then
    app.state.independent_modulator = {}
  end
  if not app.state.independent_modulator.mseg then
    app.state.independent_modulator.mseg = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      curve_mode = 0,
      segment_shapes = { 0 },
      values = { 0.8, 0.8 },
      selected_segment = 1,
      apply_all_shapes = false,
      param = {
        enabled = false,
        fx_guid = '',
        fx_name = '',
        param_index = 0,
        param_name = '',
        min = 0.0,
        max = 1.0,
        invert = false,
        search = '',
        curve = 'linear',
        bipolar = false,
        scale = 1.0,
        offset = 0.0
      }
    }
  end

  local mseg = app.state.independent_modulator.mseg
  mseg.mode = math.max(0, math.min(1, math.floor(tonumber(mseg.mode) or 0)))
  mseg.points = math.max(2, math.min(8, math.floor(tonumber(mseg.points) or 2)))
  mseg.division = math.max(1, math.min(8, math.floor(tonumber(mseg.division) or 2)))
  mseg.bars = math.max(1, math.min(16, math.floor(tonumber(mseg.bars) or 4)))
  mseg.curve_mode = math.max(0, math.min(5, math.floor(tonumber(mseg.curve_mode) or 0)))
  mseg.selected_segment = math.max(1, math.floor(tonumber(mseg.selected_segment) or 1))
  if type(mseg.manual_positions) ~= 'table' then mseg.manual_positions = { 0.0, 1.0 } end
  if type(mseg.segment_shapes) ~= 'table' then mseg.segment_shapes = { 0 } end
  if type(mseg.values) ~= 'table' then mseg.values = { 0.8, 0.8 } end
  if mseg.apply_all_shapes == nil then mseg.apply_all_shapes = false end
  if type(mseg.param) ~= 'table' then
    mseg.param = {
      enabled = false,
      fx_guid = '',
      fx_name = '',
      param_index = 0,
      param_name = '',
      min = 0.0,
      max = 1.0,
      invert = false,
      search = '',
      curve = 'linear',
      bipolar = false,
      scale = 1.0,
      offset = 0.0
    }
  else
    if mseg.param.curve == nil then mseg.param.curve = 'linear' end
    if mseg.param.bipolar == nil then mseg.param.bipolar = false end
    if mseg.param.scale == nil then mseg.param.scale = 1.0 end
    if mseg.param.offset == nil then mseg.param.offset = 0.0 end
  end
  -- Auto-migrate min/max for JSFX if needed (як у Link)
  if mseg.param.fx_guid ~= '' and mseg.param.param_index ~= nil then
    local track = getTargetTrack()
    if track then
      for i, fx in ipairs(BindingRegistry.ListFX(track)) do
        if fx.guid == mseg.param.fx_guid then
          local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx.index, mseg.param.param_index)
          if p_min ~= nil and p_max ~= nil and p_max > p_min then
            if (mseg.param.min == 0 and mseg.param.max == 1) or (mseg.param.min == nil or mseg.param.max == nil) then
              mseg.param.min = p_min
              mseg.param.max = p_max
            end
          end
        end
      end
    end
  end

  return mseg
end



local function getMasterMSEGPositions()
  local mseg = getMasterMSEG()
  local mode = math.floor(tonumber(mseg.mode) or 0)

  if mode == 1 then
    local bars = math.max(1, math.min(16, math.floor(tonumber(mseg.bars) or 4)))
    local div = math.max(1, math.min(8, math.floor(tonumber(mseg.division) or 2)))
    local count = (bars * div) + 1
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = i / (count - 1)
    end
    return out
  end

  local points = math.max(2, math.min(8, math.floor(tonumber(mseg.points) or 2)))
  if type(mseg.manual_positions) ~= 'table' then
    mseg.manual_positions = {}
  end

  local pos = mseg.manual_positions

  -- Redistribute points if count changed
  if #pos ~= points then
    for i = #pos, points + 1, -1 do
      pos[i] = nil
    end
    for i = 1, points do
      pos[i] = (i - 1) / (points - 1)
    end
  end

  -- Lock first and last positions
  pos[1] = 0.0
  pos[points] = 1.0

  -- Validate intermediate points
  for i = 2, points - 1 do
    local left = (pos[i - 1] or 0.0) + 0.01
    local right = (pos[i + 1] or 1.0) - 0.01
    pos[i] = clamp(pos[i] or 0.5, left, right)
  end

  return pos
end

local function ensureMasterMSEGData()
  local mseg = getMasterMSEG()
  local positions = getMasterMSEGPositions()
  local count = #positions

  if type(mseg.values) ~= 'table' then mseg.values = {} end
  if type(mseg.segment_shapes) ~= 'table' then mseg.segment_shapes = {} end

  for i = 1, count do
    mseg.values[i] = clamp(tonumber(mseg.values[i]) or 0.8, 0.0, 1.0)
  end
  for i = #mseg.values, count + 1, -1 do
    mseg.values[i] = nil
  end

  local default_shape = math.max(0, math.min(5, math.floor(tonumber(mseg.curve_mode) or 0)))
  for i = 1, math.max(1, count - 1) do
    mseg.segment_shapes[i] = math.max(0, math.min(5, math.floor(tonumber(mseg.segment_shapes[i]) or default_shape)))
  end
  for i = #mseg.segment_shapes, count, -1 do
    mseg.segment_shapes[i] = nil
  end

  mseg.selected_segment = clamp(math.floor(tonumber(mseg.selected_segment) or 1), 1, math.max(1, count - 1))
end

local function evaluateMasterMSEGAt(t)
  ensureMasterMSEGData()
  local mseg = getMasterMSEG()
  local positions = getMasterMSEGPositions()
  local tt = clamp(t, 0.0, 1.0)

  local idx = 1
  for i = 1, #positions - 1 do
    if tt <= positions[i + 1] then
      idx = i
      break
    end
    idx = i
  end
  if idx >= #positions then idx = #positions - 1 end

  local x1 = positions[idx]
  local x2 = positions[idx + 1]
  local y1 = mseg.values[idx] or 0.8
  local y2 = mseg.values[idx + 1] or y1
  local dx = math.max(0.0001, x2 - x1)
  local lt = clamp((tt - x1) / dx, 0.0, 1.0)
  local shape = math.floor(tonumber(mseg.segment_shapes[idx]) or tonumber(mseg.curve_mode) or 0)

  local st = lt
  if shape == 1 then
    st = lt * lt
  elseif shape == 2 then
    local inv = 1.0 - lt
    st = 1.0 - (inv * inv)
  elseif shape == 3 then
    st = lt * lt * (3.0 - (2.0 * lt))
  elseif shape == 4 then
    -- Bezier with tension
    local tension = mseg.segment_tensions and mseg.segment_tensions[idx] or mseg.curve_tension or 0.0
    tension = clamp(tonumber(tension), -1.0, 1.0)
    local cp1 = (tension < 0) and -tension or 0.0
    local cp2 = (tension > 0) and (1.0 - tension) or 1.0
    local inv_t = 1.0 - lt
    st = (3 * inv_t * inv_t * lt * cp1) +
        (3 * inv_t * lt * lt * cp2) +
        (lt * lt * lt)
  elseif shape == 5 then
    -- Square (instant jump at 50%)
    st = lt < 0.5 and 0.0 or 1.0
  end

  return clamp(y1 + ((y2 - y1) * st), 0.0, 1.0)
end

local function evaluateMasterOutputAt(t)
  local lfo = getMasterLFO()
  local mseg_val = evaluateMasterMSEGAt(t)

  if lfo.enabled then
    -- Cross-Modulation logic
    local lfo_params = {
      enabled = true,
      rate = lfo.rate,
      rate_sweep = lfo.rate_sweep,
      depth_ramp = lfo.depth_ramp,
      shape = lfo.shape,
      invert = lfo.invert,
      random_steps = lfo.random_steps,
      depth = clamp((lfo.depth or 0.6) + (mseg_val * (lfo.mseg_to_lfo_depth or 0.0)), 0.0, 1.0),
      offset = clamp(lfo.offset or 0.5, 0.0, 1.0),
      phase_offset = mseg_val * (lfo.mseg_to_lfo_rate or 0.0)
    }

    local lfo_val = PadEngine.EvaluateLFO(lfo_params, t)

    local mseg_mod_amt = lfo.lfo_to_mseg_depth or 0.0
    if mseg_mod_amt ~= 0 then
      -- Multiplicative modulation for better visibility (AM style)
      mseg_val = clamp(mseg_val * (1.0 + (lfo_val - 0.5) * mseg_mod_amt * 2.0), 0.0, 1.0)
    end

    local mode = math.floor(tonumber(lfo.mode) or 0)
    if mode == 1 then     -- Add
      return clamp(mseg_val + (lfo_val - 0.5), 0.0, 1.0)
    elseif mode == 2 then -- Multiply
      return clamp(mseg_val * (lfo_val * 2.0), 0.0, 1.0)
    elseif mode == 3 then -- Subtract
      return clamp(mseg_val - lfo_val, 0.0, 1.0)
    elseif mode == 4 then -- Min
      return math.min(mseg_val, lfo_val)
    elseif mode == 5 then -- Max
      return math.max(mseg_val, lfo_val)
    elseif mode == 6 then -- Power
      return clamp(mseg_val ^ (lfo_val * 4.0), 0.0, 1.0)
    end
    -- mode 0: Replace
    return lfo_val
  end

  return mseg_val
end

local function getMasterLfoModeName(mode)
  local names = {
    [1] = 'Add',
    [2] = 'Multiply',
    [3] = 'Subtract',
    [4] = 'Min',
    [5] = 'Max',
    [6] = 'Power'
  }
  return names[mode] or 'Add'
end

local function getIndependentMSEGPositions()
  local mseg = getIndependentMSEG()
  local mode = math.floor(tonumber(mseg.mode) or 0)

  if mode == 1 then
    -- Musical mode: calculate positions from bars/division
    local bars = math.max(1, math.min(16, math.floor(tonumber(mseg.bars) or 4)))
    local div = math.max(1, math.min(8, math.floor(tonumber(mseg.division) or 2)))
    local count = (bars * div) + 1
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = i / (count - 1)
    end
    return out
  end

  -- Manual mode: use mseg.points to determine count
  local points = math.max(2, math.min(8, math.floor(tonumber(mseg.points) or 2)))

  -- Initialize manual_positions if needed
  if type(mseg.manual_positions) ~= 'table' then
    mseg.manual_positions = {}
  end
  local pos = mseg.manual_positions

  -- Sync positions array to match points count
  local need_update = (#pos ~= points)
  if not need_update and #pos > 0 then
    local expected = (points - 1) > 0 and (1.0 / (points - 1)) or 0
    if #pos >= 2 then
      local actual_step = (pos[#pos] - pos[1]) / (#pos - 1)
      need_update = (math.abs(actual_step - expected) > 0.01)
    end
  end

  if need_update then
    for i = 1, points do pos[i] = (i - 1) / (points - 1) end
  end

  for i = #pos, points + 1, -1 do pos[i] = nil end
  for i = #pos + 1, points do pos[i] = (i - 1) / (points - 1) end

  -- Lock first and last positions
  pos[1] = 0.0
  pos[points] = 1.0

  -- Validate intermediate points (prevent overlap)
  for i = 2, points - 1 do
    local left = (pos[i - 1] or 0.0) + 0.01
    local right = (pos[i + 1] or 1.0) - 0.01
    pos[i] = clamp(pos[i] or 0.5, left, right)
  end

  return pos
end

local function ensureIndependentMSEGData()
  local mseg = getIndependentMSEG()
  local positions = getIndependentMSEGPositions()
  local count = #positions

  if type(mseg.values) ~= 'table' then mseg.values = {} end
  if type(mseg.segment_shapes) ~= 'table' then mseg.segment_shapes = {} end

  for i = 1, count do
    mseg.values[i] = clamp(tonumber(mseg.values[i]) or 0.8, 0.0, 1.0)
  end
  for i = #mseg.values, count + 1, -1 do
    mseg.values[i] = nil
  end

  local seg_count = math.max(1, count - 1)
  for i = 1, seg_count do
    mseg.segment_shapes[i] = math.max(0, math.min(5, math.floor(tonumber(mseg.segment_shapes[i]) or 0)))
  end
  for i = #mseg.segment_shapes, seg_count + 1, -1 do
    mseg.segment_shapes[i] = nil
  end

  mseg.selected_segment = math.max(1, math.min(seg_count, math.floor(tonumber(mseg.selected_segment) or 1)))
end



evaluateIndependentMSEGAt = function(t)
  ensureIndependentMSEGData()
  local mseg = getIndependentMSEG()
  local positions = getIndependentMSEGPositions()
  local tt = clamp(t, 0.0, 1.0)

  local idx = 1
  for i = 1, #positions - 1 do
    if tt <= positions[i + 1] then
      idx = i
      break
    end
    idx = i
  end
  if idx >= #positions then idx = #positions - 1 end

  local x1 = positions[idx]
  local x2 = positions[idx + 1]
  local y1 = mseg.values[idx] or 0.8
  local y2 = mseg.values[idx + 1] or y1
  local dx = math.max(0.0001, x2 - x1)
  local lt = clamp((tt - x1) / dx, 0.0, 1.0)
  local shape = math.floor(tonumber(mseg.segment_shapes[idx]) or tonumber(mseg.curve_mode) or 0)

  local st = lt
  if shape == 1 then
    st = lt * lt
  elseif shape == 2 then
    local inv = 1.0 - lt
    st = 1.0 - (inv * inv)
  elseif shape == 3 then
    st = lt * lt * (3.0 - (2.0 * lt))
  elseif shape == 4 then
    -- Bezier with tension
    local tension = mseg.segment_tensions and mseg.segment_tensions[idx] or mseg.curve_tension or 0.0
    tension = clamp(tonumber(tension), -1.0, 1.0)
    local cp1 = (tension < 0) and -tension or 0.0
    local cp2 = (tension > 0) and (1.0 - tension) or 1.0
    local inv_t = 1.0 - lt
    st = (3 * inv_t * inv_t * lt * cp1) +
        (3 * inv_t * lt * lt * cp2) +
        (lt * lt * lt)
  elseif shape == 5 then
    -- Square (instant jump at 50%)
    st = lt < 0.5 and 0.0 or 1.0
  end

  return clamp(y1 + ((y2 - y1) * st), 0.0, 1.0)
end

local function evaluateIndependentOutputAt(t)
  local lfo = getIndependentLFO()
  local mseg_raw = evaluateIndependentMSEGAt(t)
  local mseg_val = mseg_raw

  if lfo.enabled then
    local lfo_params = {
      enabled = true,
      rate = lfo.rate,
      rate_sweep = lfo.rate_sweep,
      depth_ramp = lfo.depth_ramp,
      shape = lfo.shape,
      invert = lfo.invert,
      random_steps = lfo.random_steps,
      depth = clamp((lfo.depth or 0.6) + (mseg_raw * (lfo.mseg_to_lfo_depth or 0.0)), 0.0, 1.0),
      offset = clamp(lfo.offset or 0.5, 0.0, 1.0),
      phase_offset = mseg_raw * (lfo.mseg_to_lfo_rate or 0.0)
    }

    local lfo_val = PadEngine.EvaluateLFO(lfo_params, t)

    local mseg_mod_amt = lfo.lfo_to_mseg_depth or 0.0
    if mseg_mod_amt ~= 0 then
      -- Multiplicative modulation for better visibility (AM style)
      mseg_val = clamp(mseg_val * (1.0 + (lfo_val - 0.5) * mseg_mod_amt * 2.0), 0.0, 1.0)
    end

    local mode = math.floor(tonumber(lfo.mode) or 0)
    if mode == 1 then     -- Add
      return clamp(mseg_val + (lfo_val - 0.5), 0.0, 1.0)
    elseif mode == 2 then -- Multiply
      return clamp(mseg_val * (lfo_val * 2.0), 0.0, 1.0)
    elseif mode == 3 then -- Subtract
      return clamp(mseg_val - lfo_val, 0.0, 1.0)
    elseif mode == 4 then -- Min
      return math.min(mseg_val, lfo_val)
    elseif mode == 5 then -- Max
      return math.max(mseg_val, lfo_val)
    elseif mode == 6 then -- Power
      return clamp(mseg_val ^ (lfo_val * 4.0), 0.0, 1.0)
    end
    -- mode 0: Replace
    return lfo_val
  end

  return mseg_val
end

local function drawCompactMasterLFOMSEG(forced_w)
  MasterModulatorUI.DrawCompact(ctx, forced_w, {
    getMasterLFO = getMasterLFO,
    getMasterMSEG = getMasterMSEG,
    getMasterMSEGPositions = getMasterMSEGPositions,
    ensureMasterMSEGData = ensureMasterMSEGData,
    evaluateLFO = PadEngine.EvaluateLFO,
    evaluateMasterMSEGAt = evaluateMasterMSEGAt,
    markDirty = markDirty,
    interaction = interaction,
  })
end
local function findOrCreateMixer(track, allow_create)
  if not track or type(track) ~= 'userdata' or not r.ValidatePtr(track, 'MediaTrack*') then
    return -1, false
  end

  if allow_create == nil then
    allow_create = true
  end

  local custom_token = 'sbp_ReaMotionPad_Mixer'
  local mixer_idx = -1
  local is_custom = false
  local fx_count = r.TrackFX_GetCount(track)

  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i)
    if string.find(fx_name, custom_token, 1, true) then
      mixer_idx = i
      is_custom = true
      break
    end
  end

  if mixer_idx < 0 then
    for i = 0, fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(track, i)
      if string.find(fx_name, 'Mixer_8xS-1xS', 1, true) then
        mixer_idx = i
        is_custom = false
        break
      end
    end
  end

  if mixer_idx == -1 and allow_create then
    for _, candidate in ipairs(EXT_MIXER_CANDIDATES) do
      -- instantiate=-1000 inserts at position 0 (first in chain)
      local idx = r.TrackFX_AddByName(track, candidate, false, -1000)
      if idx >= 0 then
        mixer_idx = idx
        is_custom = string.find(candidate, custom_token, 1, true) ~= nil
        break
      end
    end
  end

  -- If found but not at position 0, move it to the front
  if mixer_idx > 0 then
    r.TrackFX_CopyToTrack(track, mixer_idx, track, 0, true)
    mixer_idx = 0
  end

  if mixer_idx >= 0 then
    local _, fx_name = r.TrackFX_GetFXName(track, mixer_idx)
    is_custom = string.find(fx_name or '', custom_token, 1, true) ~= nil
  end

  return mixer_idx, is_custom
end

local function configureMotionMixerInputs(track, mixer_idx)
  if not track or mixer_idx < 0 then return end

  local sources = (app.state.external and app.state.external.sources) or {}
  for i = 1, 4 do
    local src = sources[i] or {}
    local ch_l = math.max(1, math.min(63, math.floor(tonumber(src.ch_l) or ((i - 1) * 2 + 1))))
    local ch_r = math.max(ch_l, math.min(64, math.floor(tonumber(src.ch_r) or (ch_l + 1))))
    local ch_count = math.max(1, math.min(16, (ch_r - ch_l) + 1))

    -- JSFX sliders: ch_start=params[5-8] range <1,63,1>, ch_count=params[9-12] range <1,16,1>
    local start_param_idx = 5 + (i - 1)
    local count_param_idx = 9 + (i - 1)

    local _, start_min, start_max = r.TrackFX_GetParamEx(track, mixer_idx, start_param_idx)
    local _, count_min, count_max = r.TrackFX_GetParamEx(track, mixer_idx, count_param_idx)

    local start_norm = (ch_l - start_min) / math.max(0.001, start_max - start_min)
    local count_norm = (ch_count - count_min) / math.max(0.001, count_max - count_min)

    r.TrackFX_SetParamNormalized(track, mixer_idx, start_param_idx, clamp(start_norm, 0.0, 1.0))
    r.TrackFX_SetParamNormalized(track, mixer_idx, count_param_idx, clamp(count_norm, 0.0, 1.0))
  end
end

local function dbToNormalized(db, min_db, max_db)
  local clamped_db = math.max(min_db, math.min(max_db, db))
  return (clamped_db - min_db) / (max_db - min_db)
end

local function normalizedToDb(norm, min_db, max_db)
  return min_db + (norm * (max_db - min_db))
end

local function gainToJsfxDbNorm(gain_lin)
  local g = math.max(0.0, tonumber(gain_lin) or 0.0)
  if g <= 0.001 then
    return 0.0
  end
  local db = 20.0 * (math.log(g) / math.log(10))
  return clamp((db + 60.0) / 66.0, 0.0, 1.0)
end

local function ensureLinkBinding(pad)
  if not pad or type(pad) ~= 'table' then
    return nil
  end
  if type(pad.link) ~= 'table' then
    pad.link = {}
  end

  if type(pad.link.sources) ~= 'table' then
    pad.link.sources = {}
  end

  for i = 1, 4 do
    if type(pad.link.sources[i]) ~= 'table' then
      pad.link.sources[i] = {
        enabled = true,
        fx_guid = '',
        fx_name = '',
        param_index = 0,
        param_name = '',
        min = 0.0,
        max = 1.0,
        invert = false,
        search = '',
        curve = 'linear',
        bipolar = false,
        scale = 1.0,
        offset = 0.0,
        axis = 'xy'
      }
    else
      local s = pad.link.sources[i]
      if s.curve == nil then s.curve = 'linear' end
      if s.bipolar == nil then s.bipolar = false end
      if s.scale == nil then s.scale = 1.0 end
      if s.offset == nil then s.offset = 0.0 end
      if s.axis == nil then s.axis = 'xy' end
    end
  end

  return pad.link
end

local function drawLinkParamBlock(idx, corner_name, link_cfg, track, fx_list)
  local src = link_cfg.sources[idx]
  if not src or not track or not fx_list then return end

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 17, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

  local child_flags = r.ImGui_WindowFlags_NoScrollWithMouse() -- Allow scrollbar
  r.ImGui_BeginChild(ctx, 'link_child_' .. idx, 260, 280, child_flags)

  -- Set content position: 15px top padding, 10px left indent for all rows
  r.ImGui_SetCursorPosY(ctx, 15)
  r.ImGui_Indent(ctx, 10)

  r.ImGui_TextColored(ctx, COL_ACCENT, string.format('Param %d - %s', idx, corner_name))

  r.ImGui_SameLine(ctx, 0, 10)
  local c_on, v_on = r.ImGui_Checkbox(ctx, 'On##link_on_' .. idx, src.enabled ~= false)
  if c_on then
    src.enabled = v_on
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 10)
  r.ImGui_SetNextItemWidth(ctx, 50)
  local axis_items = 'X\0Y\0XY\0'
  local axis_idx = 0
  if src.axis == 'y' then
    axis_idx = 1
  elseif src.axis == 'xy' then
    axis_idx = 2
  end
  local c_axis, v_axis = r.ImGui_Combo(ctx, '##link_axis_' .. idx, axis_idx, axis_items)
  if c_axis then
    local axes = { 'x', 'y', 'xy' }
    src.axis = axes[v_axis + 1] or 'x'
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 3)

  -- Target type selector (FX / Track Vol / Track Pan)
  if src.target_type == nil then
    src.target_type = 'fx' -- Default to FX
  end
  local target_items = 'FX\0Trk Vol\0Trk Pan\0'
  local target_idx = 0
  if src.target_type == 'track_vol' then
    target_idx = 1
  elseif src.target_type == 'track_pan' then
    target_idx = 2
  end
  local c_target, v_target = r.ImGui_Combo(ctx, '##link_target_' .. idx, target_idx, target_items)
  if c_target then
    local targets = { 'fx', 'track_vol', 'track_pan' }
    src.target_type = targets[v_target + 1] or 'fx'
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 3)

  local fx_sel = 0
  local fx_valid = true -- Track if FX is still valid

  if src.target_type == 'fx' then
    if src.fx_guid ~= '' then
      for i, fx in ipairs(fx_list) do
        if fx.guid == src.fx_guid then
          fx_sel = i
          break
        end
      end
      if fx_sel == 0 then fx_valid = false end -- FX not found
    elseif src.fx_name ~= '' then
      for i, fx in ipairs(fx_list) do
        if fx.name == src.fx_name then
          fx_sel = i
          break
        end
      end
      if fx_sel == 0 then fx_valid = false end -- FX not found
    end

    -- Show warning if FX is deleted
    if not fx_valid then
      r.ImGui_TextColored(ctx, 0xFF5050FF, '⚠ FX not found (deleted?)')
      r.ImGui_Dummy(ctx, 0, 4)
      if r.ImGui_Button(ctx, 'Clear##clear_missing_' .. idx, -1, 0) then
        src.fx_guid = ''
        src.fx_name = ''
        src.param_index = 0
        src.param_name = ''
        markDirty()
      end
      r.ImGui_Dummy(ctx, 0, 4)
    end

    local fx_label = (fx_sel > 0 and fx_list[fx_sel] and fx_list[fx_sel].name) or 'Select FX'
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'FX:')
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_SetNextItemWidth(ctx, 160)
    if r.ImGui_BeginCombo(ctx, '##link_fx_' .. idx, fx_label) then
      for i, fx in ipairs(fx_list) do
        if r.ImGui_Selectable(ctx, fx.name, i == fx_sel) then
          src.fx_guid = fx.guid or ''
          src.fx_name = fx.name or ''
          src.param_index = 0
          src.param_name = ''
          src.enabled = true
          markDirty()
        end
      end
      r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SameLine(ctx, 0, 4)
    if r.ImGui_Button(ctx, 'Pick##pick_' .. idx, 50, 0) then
      local has_touched, tr_idx, item_idx, take_idx, fx_idx, param_idx = r.GetTouchedOrFocusedFX(0)

      if has_touched and item_idx == -1 then -- only track FX, not item FX
        -- Extract actual FX index (remove flags)
        local actual_fx_idx = fx_idx & 0xFFFFFF

        -- Get the track that was touched
        local touched_track
        if tr_idx == -1 then
          touched_track = reaper.GetMasterTrack(app.project)
        else
          touched_track = reaper.GetTrack(app.project, tr_idx)
        end

        -- Check if it's the same track we're working with
        if touched_track == track then
          local _, fx_name = r.TrackFX_GetFXName(track, actual_fx_idx)
          local last_fx = nil

          -- Find matching FX in our list
          for i, fx in ipairs(fx_list) do
            if fx.name == fx_name then
              last_fx = fx
              break
            end
          end

          -- Populate the parameter block
          if last_fx and param_idx >= 0 then
            src.fx_guid = last_fx.guid or ''
            src.fx_name = last_fx.name or ''

            -- Get available parameters for this FX
            local params = BindingRegistry.ListParams(track, actual_fx_idx)
            if params and #params > param_idx and params[param_idx + 1] then
              local p_idx_new = params[param_idx + 1].index
              src.param_index = p_idx_new
              src.param_name = params[param_idx + 1].name or ''
              src.enabled = true -- Auto-enable on Pick
              -- Auto-fill physical range from REAPER
              local _, p_min, p_max = r.TrackFX_GetParamEx(track, actual_fx_idx, p_idx_new)
              if p_min ~= nil and p_max ~= nil and p_max > p_min then
                src.min = p_min
                src.max = p_max
              end
              -- Default to Y axis for simple 1D param control
              if src.axis == 'xy' then src.axis = 'y' end
              markDirty()
            end
          end
        end
      end
    end
  elseif src.target_type == 'track_vol' then
    r.ImGui_TextColored(ctx, 0x808080FF, 'Target: Track Volume')
    r.ImGui_Dummy(ctx, 0, 4)
  elseif src.target_type == 'track_pan' then
    r.ImGui_TextColored(ctx, 0x808080FF, 'Target: Track Pan')
    r.ImGui_Dummy(ctx, 0, 4)
  end

  local params = {}
  if fx_sel > 0 and fx_list[fx_sel] then
    params = BindingRegistry.ListParams(track, fx_list[fx_sel].index)
  end

  local search = tostring(src.search or '')
  local search_l = search:lower()
  local filtered = {}
  for _, p in ipairs(params) do
    local n = tostring(p.name or '')
    if search_l == '' or n:lower():find(search_l, 1, true) then
      filtered[#filtered + 1] = p
    end
  end

  local param_label = (src.param_name ~= '' and src.param_name) or 'Select Param'
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Param:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 140)
  if r.ImGui_BeginCombo(ctx, '##link_param_' .. idx, param_label) then
    for i, p in ipairs(filtered) do
      local is_sel = (src.param_index == p.index)
      -- Append param index for uniqueness in combo when names duplicate
      local param_display = string.format('%s##param_%d_%d', p.name, idx, p.index or i)
      if r.ImGui_Selectable(ctx, param_display, is_sel) then
        src.param_index = p.index
        src.param_name = p.name or ''
        -- Auto-fill physical range from REAPER
        if fx_sel > 0 and fx_list[fx_sel] then
          local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_list[fx_sel].index, p.index)
          if p_min ~= nil and p_max ~= nil and p_max > p_min then
            src.min = p_min
            src.max = p_max
          end
        end
        -- Default to Y axis for simple 1D param control (XY is for full 2D corner mixing)
        if src.axis == 'xy' then src.axis = 'y' end
        -- Вмикаємо лише поточний, не вимикаючи інші
        src.enabled = true
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 51)
  local c_search, v_search = r.ImGui_InputTextWithHint(ctx, '##link_search_' .. idx, 'F...', search)
  if c_search then
    src.search = v_search
  end

  r.ImGui_Dummy(ctx, 0, 2)

  -- Min/Max + Auto-fill button
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Min:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 50)
  local c_min, v_min = r.ImGui_InputDouble(ctx, '##link_min_' .. idx, tonumber(src.min) or 0.0, 0.0, 0.0, '%.6g')
  if c_min then
    src.min = v_min
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Max:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 50)
  local c_max, v_max = r.ImGui_InputDouble(ctx, '##link_max_' .. idx, tonumber(src.max) or 1.0, 0.0, 0.0, '%.6g')
  if c_max then
    src.max = v_max
    markDirty()
  end

  -- Auto button: reads actual param range from REAPER and fills Min/Max
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_PopStyleColor(ctx, 2)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1a5c3aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x28794dFF)
  if r.ImGui_Button(ctx, 'Auto##link_auto_' .. idx, 50, 0) then
    if fx_sel > 0 and fx_list[fx_sel] then
      local fx_i = fx_list[fx_sel].index
      local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_i, src.param_index or 0)
      if p_min ~= nil and p_max ~= nil and p_max > p_min then
        src.min = p_min
        src.max = p_max
        markDirty()
      end
    end
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 2)

  -- Curve type
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Curve:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 130)
  local curve_items = 'Linear\0Smooth\0Exponential\0Logarithmic\0'
  local curve_idx = 0
  if src.curve == 'smooth' then
    curve_idx = 1
  elseif src.curve == 'exponential' then
    curve_idx = 2
  elseif src.curve == 'logarithmic' then
    curve_idx = 3
  end
  local c_curve, v_curve = r.ImGui_Combo(ctx, '##link_curve_' .. idx, curve_idx, curve_items)
  if c_curve then
    local curves = { 'linear', 'smooth', 'exponential', 'logarithmic' }
    src.curve = curves[v_curve + 1] or 'linear'
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 10)
  local c_bipolar, v_bipolar = r.ImGui_Checkbox(ctx, 'Bipolar##link_bipolar_' .. idx, src.bipolar == true)
  if c_bipolar then
    src.bipolar = v_bipolar
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 2)

  -- Scale and Offset
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Scale:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_scale, v_scale = r.ImGui_InputDouble(ctx, '##link_scale_' .. idx, src.scale or 1.0, 0.1, 0.5, '%.2f')
  if c_scale then
    src.scale = v_scale
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Offset:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_offset, v_offset = r.ImGui_InputDouble(ctx, '##link_offset_' .. idx, src.offset or 0.0, 0.01, 0.1, '%.2f')
  if c_offset then
    src.offset = v_offset
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 2)

  -- Invert + Clear button
  local c_inv, v_inv = r.ImGui_Checkbox(ctx, 'Invert##link_inv_' .. idx, src.invert == true)
  if c_inv then
    src.invert = v_inv
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  if r.ImGui_Button(ctx, 'Clear##clear_' .. idx, 50, 0) then
    src.fx_guid = ''
    src.fx_name = ''
    src.param_index = 0
    src.param_name = ''
    src.min = 0.0
    src.max = 1.0
    src.enabled = false
    src.search = ''
    markDirty()
  end

  r.ImGui_Unindent(ctx, 10)
  r.ImGui_EndChild(ctx)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopStyleVar(ctx, 4)
end

local function drawIndependentModulatorParamSetup(modulator_type, param_cfg, track, fx_list)
  -- modulator_type: 'lfo' or 'mseg'
  if not param_cfg or not track or not fx_list then return end

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 17, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

  local child_w, child_h = 310, 280
  local child_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() |
      r.ImGui_WindowFlags_NoSavedSettings()
  -- Change child ID so ImGui resets its stored size
  r.ImGui_BeginChild(ctx, 'mod_param_child_v2_' .. modulator_type, child_w, child_h, child_flags)

  r.ImGui_SetCursorPosY(ctx, 15)
  r.ImGui_Indent(ctx, 10)

  r.ImGui_TextColored(ctx, COL_ACCENT, modulator_type == 'lfo' and 'LFO Parameter' or 'MSEG Parameter')

  r.ImGui_SameLine(ctx, 0, 10)
  local c_on, v_on = r.ImGui_Checkbox(ctx, 'Enable##mod_param_en_' .. modulator_type, param_cfg.enabled ~= false)
  if c_on then
    param_cfg.enabled = v_on
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 2)

  local fx_sel = 0
  if param_cfg.fx_guid ~= '' then
    for i, fx in ipairs(fx_list) do
      if fx.guid == param_cfg.fx_guid then
        fx_sel = i
        break
      end
    end
  elseif param_cfg.fx_name ~= '' then
    for i, fx in ipairs(fx_list) do
      if fx.name == param_cfg.fx_name then
        fx_sel = i
        break
      end
    end
  end

  local fx_label = (fx_sel > 0 and fx_list[fx_sel] and fx_list[fx_sel].name) or 'Select FX'
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'FX:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 160)
  if r.ImGui_BeginCombo(ctx, '##mod_fx_' .. modulator_type, fx_label) then
    for i, fx in ipairs(fx_list) do
      if r.ImGui_Selectable(ctx, fx.name, i == fx_sel) then
        param_cfg.fx_guid = fx.guid or ''
        param_cfg.fx_name = fx.name or ''
        param_cfg.param_index = 0
        param_cfg.param_name = ''
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  if r.ImGui_Button(ctx, 'Pick##mod_pick_' .. modulator_type, 50, 0) then
    local has_touched, tr_idx, item_idx, take_idx, fx_idx, param_idx = r.GetTouchedOrFocusedFX(0)

    if has_touched and item_idx == -1 then -- only track FX, not item FX
      local actual_fx_idx = fx_idx & 0xFFFFFF

      local touched_track
      if tr_idx == -1 then
        touched_track = reaper.GetMasterTrack(app.project)
      else
        touched_track = reaper.GetTrack(app.project, tr_idx)
      end

      if touched_track == track then
        local _, fx_name = r.TrackFX_GetFXName(track, actual_fx_idx)
        local last_fx = nil

        for i, fx in ipairs(fx_list) do
          if fx.name == fx_name then
            last_fx = fx
            break
          end
        end

        if last_fx and param_idx >= 0 then
          param_cfg.fx_guid = last_fx.guid or ''
          param_cfg.fx_name = last_fx.name or ''

          local params = BindingRegistry.ListParams(track, actual_fx_idx)
          if params and #params > param_idx and params[param_idx + 1] then
            param_cfg.param_index = params[param_idx + 1].index
            param_cfg.param_name = params[param_idx + 1].name or ''
            param_cfg.enabled = true -- Auto-enable on pick
            markDirty()
          end
        end
      end
    end
  end

  local params = {}
  if fx_sel > 0 and fx_list[fx_sel] then
    params = BindingRegistry.ListParams(track, fx_list[fx_sel].index)
  end

  local search = tostring(param_cfg.search or '')
  local search_l = search:lower()
  local filtered = {}
  for _, p in ipairs(params) do
    local n = tostring(p.name or '')
    if search_l == '' or n:lower():find(search_l, 1, true) then
      filtered[#filtered + 1] = p
    end
  end

  local param_label = (param_cfg.param_name ~= '' and param_cfg.param_name) or 'Select Param'
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Param:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 140)
  if r.ImGui_BeginCombo(ctx, '##mod_param_' .. modulator_type, param_label) then
    for i, p in ipairs(filtered) do
      local is_sel = (param_cfg.param_index == p.index)
      local param_display = string.format('%s##mod_param_%s_%d', p.name, modulator_type, p.index or i)
      if r.ImGui_Selectable(ctx, param_display, is_sel) then
        param_cfg.param_index = p.index
        param_cfg.param_name = p.name or ''
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 51)
  local c_search, v_search = r.ImGui_InputTextWithHint(ctx, '##mod_search_' .. modulator_type, 'F...', search)
  if c_search then
    param_cfg.search = v_search
  end

  r.ImGui_Dummy(ctx, 0, 1)

  -- Min/Max in one row
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Min:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 90)
  local c_min, v_min = r.ImGui_InputInt(ctx, '##mod_min_' .. modulator_type, math.floor(tonumber(param_cfg.min) or 0), 1,
    10)
  if c_min then
    param_cfg.min = v_min
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Max:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 90)
  local c_max, v_max = r.ImGui_InputInt(ctx, '##mod_max_' .. modulator_type, math.floor(tonumber(param_cfg.max) or 1), 1,
    10)
  if c_max then
    param_cfg.max = v_max
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 1)

  -- Curve type
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Curve:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 130)
  local curve_items = 'Linear\0Smooth\0Exponential\0Logarithmic\0'
  local curve_idx = 0
  if param_cfg.curve == 'smooth' then
    curve_idx = 1
  elseif param_cfg.curve == 'exponential' then
    curve_idx = 2
  elseif param_cfg.curve == 'logarithmic' then
    curve_idx = 3
  end
  local c_curve, v_curve = r.ImGui_Combo(ctx, '##mod_curve_' .. modulator_type, curve_idx, curve_items)
  if c_curve then
    local curves = { 'linear', 'smooth', 'exponential', 'logarithmic' }
    param_cfg.curve = curves[v_curve + 1] or 'linear'
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 10)
  local c_bipolar, v_bipolar = r.ImGui_Checkbox(ctx, 'Bipolar##mod_bipolar_' .. modulator_type, param_cfg.bipolar == true)
  if c_bipolar then
    param_cfg.bipolar = v_bipolar
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 3)

  -- Scale and Offset
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Scale:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_scale, v_scale = r.ImGui_InputDouble(ctx, '##mod_scale_' .. modulator_type, param_cfg.scale or 1.0, 0.1, 0.5,
    '%.2f')
  if c_scale then
    param_cfg.scale = v_scale
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Offset:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_offset, v_offset = r.ImGui_InputDouble(ctx, '##mod_offset_' .. modulator_type, param_cfg.offset or 0.0, 0.01,
    0.1, '%.2f')
  if c_offset then
    param_cfg.offset = v_offset
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 1)

  -- Invert + Clear button
  local c_inv, v_inv = r.ImGui_Checkbox(ctx, 'Invert##mod_inv_' .. modulator_type, param_cfg.invert == true)
  if c_inv then
    param_cfg.invert = v_inv
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  if r.ImGui_Button(ctx, 'Clear##mod_clear_' .. modulator_type, 50, 0) then
    param_cfg.fx_guid = ''
    param_cfg.fx_name = ''
    param_cfg.param_index = 0
    param_cfg.param_name = ''
    param_cfg.enabled = false
    param_cfg.min = 0.0
    param_cfg.max = 1.0
    param_cfg.search = ''
    markDirty()
  end

  -- Auto min/max button (after Invert)
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1a5c3aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x28794dFF)
  if r.ImGui_Button(ctx, 'Auto min/max##mod_auto_' .. modulator_type, 110, 0) then
    if fx_sel > 0 and fx_list[fx_sel] and param_cfg.param_index ~= nil then
      local fx_i = fx_list[fx_sel].index
      local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_i, param_cfg.param_index)
      if p_min ~= nil and p_max ~= nil and p_max > p_min then
        param_cfg.min = p_min
        param_cfg.max = p_max
        markDirty()
      end
    end
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Unindent(ctx, 10)
  r.ImGui_EndChild(ctx)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopStyleVar(ctx, 4)
end

local function drawPadSetupPopup()
  if not interaction.pad_setup_open then return end

  -- Supports External pad and Link A/B targets
  if interaction.pad_setup_target ~= 'seg_ext' and interaction.pad_setup_target ~= 'seg_a' and interaction.pad_setup_target ~= 'seg_b' then
    interaction.pad_setup_open = false
    return
  end

  -- Rounded window corners
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)

  -- Fixed window size for 2x2 quadrant layout + controls
  local window_w = 560
  local window_h = 730 -- Reduced height for compact layout
  r.ImGui_SetNextWindowSize(ctx, window_w, window_h, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowPos(ctx, 300, 150, r.ImGui_Cond_FirstUseEver())

  -- NoResize flag for fixed-size window
  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize()
  local title = (interaction.pad_setup_target == 'seg_ext')
      and 'External Pad Setup - 4 Corner Sources'
      or 'Link Pad Setup'
  local visible, open = r.ImGui_Begin(ctx, title, true, flags)
  if not open then
    interaction.pad_setup_open = false
    interaction.pad_setup_jsfx_synced = false
  end

  if visible then
    local track = getTargetTrack()
    if not track then
      r.ImGui_TextColored(ctx, 0xC05050FF, 'Error: No target track selected.')
      r.ImGui_Text(ctx, 'Please select a track or use the Track selector in the top bar.')
      r.ImGui_Dummy(ctx, 0, 10)
      if r.ImGui_Button(ctx, 'Close', 120, 0) then
        interaction.pad_setup_open = false
      end
    else
      if interaction.pad_setup_target == 'seg_a' or interaction.pad_setup_target == 'seg_b' then
        local pad = (interaction.pad_setup_target == 'seg_a') and app.state.pads.link_a or app.state.pads.link_b
        local title_text = (interaction.pad_setup_target == 'seg_a') and 'Link A - Parameter Morph' or
            'Link B - Parameter Morph'
        local link_cfg = ensureLinkBinding(pad)

        r.ImGui_TextColored(ctx, 0xFFD700FF, title_text)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)

        if not link_cfg then
          r.ImGui_TextDisabled(ctx, 'Pad data not available.')
        else
          local fx_list = BindingRegistry.ListFX(track)

          -- Validate that configured FX still exist
          for idx = 1, 4 do
            local src = link_cfg.sources[idx]
            if src and src.fx_guid ~= '' then
              local fx_found = false
              for _, fx in ipairs(fx_list) do
                if fx.guid == src.fx_guid then
                  fx_found = true
                  break
                end
              end
              if not fx_found and src.fx_name ~= '' then
                -- FX was deleted, clear the binding
                src.fx_guid = ''
                src.param_index = 0
                src.param_name = ''
                markDirty()
              end
            end
          end

          if r.ImGui_BeginTable(ctx, 'link_quad_table', 2, r.ImGui_TableFlags_SizingFixedFit()) then
            r.ImGui_TableSetupColumn(ctx, 'left_col', r.ImGui_TableColumnFlags_WidthFixed(), 260)
            r.ImGui_TableSetupColumn(ctx, 'right_col', r.ImGui_TableColumnFlags_WidthFixed(), 260)

            -- Equal vertical spacing for table
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8)

            r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 290) -- Row height
            r.ImGui_TableNextColumn(ctx)
            drawLinkParamBlock(1, 'Top-Left', link_cfg, track, fx_list)

            r.ImGui_TableNextColumn(ctx)
            drawLinkParamBlock(2, 'Top-Right', link_cfg, track, fx_list)

            r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 290) -- Row height
            r.ImGui_TableNextColumn(ctx)
            drawLinkParamBlock(3, 'Bottom-Left', link_cfg, track, fx_list)

            r.ImGui_TableNextColumn(ctx)
            drawLinkParamBlock(4, 'Bottom-Right', link_cfg, track, fx_list)

            r.ImGui_PopStyleVar(ctx)
            r.ImGui_EndTable(ctx)
          end
        end

        r.ImGui_Dummy(ctx, 0, 6)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 3)
        if r.ImGui_Button(ctx, 'Close', 120, 0) then
          interaction.pad_setup_open = false
          interaction.pad_setup_jsfx_synced = false
        end
      end

      -- External pad setup
      if interaction.pad_setup_target == 'seg_ext' then
        -- Sync JSFX on popup open (once)
        if not interaction.pad_setup_jsfx_synced then
          local track = getTargetTrack()
          if track then
            local mixer_idx, is_custom = findOrCreateMixer(track, true)
            if mixer_idx >= 0 and is_custom then
              configureMotionMixerInputs(track, mixer_idx)
            end
          end
          interaction.pad_setup_jsfx_synced = true
        end

        r.ImGui_TextColored(ctx, 0xFFD700FF, 'External Pad Setup - Corner Sources')
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)

        local label_w = 60
        local right_w = 90

        local function rightLabel(text)
          local txt_w = r.ImGui_CalcTextSize(ctx, text)
          local col_w = r.ImGui_GetContentRegionAvail(ctx)
          local start_x = r.ImGui_GetCursorPosX(ctx)
          r.ImGui_SetCursorPosX(ctx, start_x + math.max(0, col_w - txt_w))
          r.ImGui_Text(ctx, text)
        end

        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 8, 6)
        if r.ImGui_BeginTable(ctx, 'src_tbl_master', 2, r.ImGui_TableFlags_SizingFixedFit()) then
          r.ImGui_TableSetupColumn(ctx, 'left_c', r.ImGui_TableColumnFlags_WidthFixed(), 260)
          r.ImGui_TableSetupColumn(ctx, 'right_c', r.ImGui_TableColumnFlags_WidthFixed(), 260)

          local sources = app.state.external and app.state.external.sources or {}
          for idx = 1, 4 do
            r.ImGui_TableNextColumn(ctx)
            local src = sources[idx] or {}
            local quad_w, quad_h = 260, 290
            local child_flags = r.ImGui_WindowFlags_NoScrollbar()
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

            r.ImGui_BeginChild(ctx, 'src_child_' .. idx, quad_w, quad_h, child_flags)
            r.ImGui_SetCursorPosY(ctx, 10)
            r.ImGui_Indent(ctx, 10)

            local corner_names = { 'Top-Left', 'Top-Right', 'Bottom-Left', 'Bottom-Right' }
            r.ImGui_TextColored(ctx, COL_ACCENT, (corner_names[idx] or ('Source ' .. idx)))
            r.ImGui_Dummy(ctx, 0, 4)

            if r.ImGui_BeginTable(ctx, 'src_tbl_' .. idx, 3, r.ImGui_TableFlags_SizingFixedFit()) then
              r.ImGui_TableSetupColumn(ctx, 'lbl', r.ImGui_TableColumnFlags_WidthFixed(), label_w)
              r.ImGui_TableSetupColumn(ctx, 'main', r.ImGui_TableColumnFlags_WidthStretch())
              r.ImGui_TableSetupColumn(ctx, 'right', r.ImGui_TableColumnFlags_WidthFixed(), right_w)

              -- Name
              r.ImGui_TableNextRow(ctx)
              r.ImGui_TableNextColumn(ctx)
              rightLabel('Name:')
              r.ImGui_TableNextColumn(ctx)
              r.ImGui_SetNextItemWidth(ctx, -1)
              local c_name, v_name = r.ImGui_InputText(ctx, '##name', src.name or ('Ext ' .. idx))
              if c_name then
                src.name = v_name
                markDirty()
              end
              r.ImGui_TableNextColumn(ctx)
              local on_text_w = r.ImGui_CalcTextSize(ctx, 'On')
              local on_check_w = r.ImGui_GetFrameHeight(ctx)
              local on_col_w = r.ImGui_GetContentRegionAvail(ctx)
              local on_total_w = on_text_w + 2 + on_check_w
              local on_start_x = r.ImGui_GetCursorPosX(ctx)
              r.ImGui_SetCursorPosX(ctx, on_start_x + math.max(0, (on_col_w - on_total_w) * 0.5))
              r.ImGui_Text(ctx, 'On')
              r.ImGui_SameLine(ctx, 0, 2)
              local c_on, v_on = r.ImGui_Checkbox(ctx, '##on', src.enabled ~= false)
              if c_on then
                src.enabled = v_on
                markDirty()
              end

              -- Channel L
              r.ImGui_TableNextRow(ctx)
              r.ImGui_TableNextColumn(ctx)
              rightLabel('Ch L:')
              r.ImGui_TableNextColumn(ctx)
              r.ImGui_SetNextItemWidth(ctx, -1)
              local ch_l = math.floor(tonumber(src.ch_l) or ((idx - 1) * 2 + 1))
              local c_l, v_l = r.ImGui_SliderInt(ctx, '##ch_l', ch_l, 1, 64)
              if c_l then
                src.ch_l = v_l
                markDirty()
              end

              -- Channel R
              r.ImGui_TableNextRow(ctx)
              r.ImGui_TableNextColumn(ctx)
              rightLabel('Ch R:')
              r.ImGui_TableNextColumn(ctx)
              r.ImGui_SetNextItemWidth(ctx, -1)
              local ch_r = math.floor(tonumber(src.ch_r) or (ch_l + 1))
              local c_r, v_r = r.ImGui_SliderInt(ctx, '##ch_r', ch_r, 1, 64)
              if c_r then
                src.ch_r = v_r
                markDirty()
              end

              r.ImGui_EndTable(ctx)
            end

            r.ImGui_Unindent(ctx, 10)
            r.ImGui_EndChild(ctx)
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_PopStyleVar(ctx, 2)
          end
          r.ImGui_EndTable(ctx)
        end
        r.ImGui_PopStyleVar(ctx)

        r.ImGui_Dummy(ctx, 0, 6)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 3)

        if r.ImGui_Button(ctx, 'Close', 120, 0) then
          interaction.pad_setup_open = false
          interaction.pad_setup_jsfx_synced = false
          local track = getTargetTrack()
          if track then
            local mixer_idx, is_custom = findOrCreateMixer(track, true)
            if mixer_idx >= 0 and is_custom then
              configureMotionMixerInputs(track, mixer_idx)
            end
          end
        end
      end
    end
  end

  r.ImGui_End(ctx)
  r.ImGui_PopStyleVar(ctx, 2) -- WindowRounding, WindowPadding
end

-- Forward declarations
local writeAutomation
local bakeAutomationItems
local bounceTimeSelection
local hideTrackEnvelopes
local areEnvelopesVisible
local buildIndependentModulatorTargets
local buildLinkTargets

-- Check if track envelopes are visible
areEnvelopesVisible = function(track)
  if not track then return false end
  local count = r.CountTrackEnvelopes(track)
  if count == 0 then return false end
  for i = 0, count - 1 do
    local env = r.GetTrackEnvelope(track, i)
    local _, chunk = r.GetEnvelopeStateChunk(env, '', false)
    if chunk:find('VIS 1') then
      return true
    end
  end
  return false
end

local function drawSetupAndSegment(track)
  -- MASTER header
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_ACCENT)
  r.ImGui_Text(ctx, 'MASTER')
  r.ImGui_PopStyleColor(ctx)

  -- Full-width separator
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, cx, cy, cx + avail_w, cy, 0x3A3A3AFF, 1)
  -- Reduced padding

  -- Table: Master LFO/MSEG | Action buttons
  local master_table_open = r.ImGui_BeginTable(ctx, 'master_layout', 2, r.ImGui_TableFlags_SizingFixedFit())
  if master_table_open then
    local actions_w = 430
    local table_spacing = 8
    local master_w = math.max(200, avail_w - actions_w - table_spacing)
    r.ImGui_TableSetupColumn(ctx, 'master_lfo_mseg', r.ImGui_TableColumnFlags_WidthFixed(), master_w)
    r.ImGui_TableSetupColumn(ctx, 'actions', r.ImGui_TableColumnFlags_WidthFixed(), actions_w)

    r.ImGui_TableNextColumn(ctx)
    -- Master LFO/MSEG
    drawCompactMasterLFOMSEG(master_w)

    r.ImGui_TableNextColumn(ctx)

    -- ===== Action buttons columns =====
    local col_x = r.ImGui_GetCursorPosX(ctx)
    local gap = 8

    -- Write Automation Targets
    r.ImGui_Dummy(ctx, 0, 2)
    local wa = app.state.setup.auto_write
    r.ImGui_SetCursorPosX(ctx, col_x)
    local c_ext, v_ext = r.ImGui_Checkbox(ctx, 'Ext##w_ext', wa.external)
    if c_ext then
      wa.external = v_ext
      if v_ext then wa.sel_env = false end
      app.dirty = true
    end
    r.ImGui_SameLine(ctx, 0, 10)
    local c_mvol, v_mvol = r.ImGui_Checkbox(ctx, 'M.Vol##w_mvol', wa.master_vol)
    if c_mvol then
      wa.master_vol = v_mvol
      if v_mvol then wa.sel_env = false end
      app.dirty = true
    end
    r.ImGui_SameLine(ctx, 0, 10)
    local c_a, v_a = r.ImGui_Checkbox(ctx, 'Link A##w_a', wa.pad_a)
    if c_a then
      wa.pad_a = v_a
      if v_a then wa.sel_env = false end
      app.dirty = true
    end
    r.ImGui_SameLine(ctx, 0, 10)
    local c_b, v_b = r.ImGui_Checkbox(ctx, 'Link B##w_b', wa.pad_b)
    if c_b then
      wa.pad_b = v_b
      if v_b then wa.sel_env = false end
      app.dirty = true
    end

    r.ImGui_SameLine(ctx, 0, 10)
    if wa.sel_env then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), UIHelpers.COL_YELLOW) end
    local c_lfo, v_lfo = r.ImGui_Checkbox(ctx, 'LFO##w_lfo', wa.lfo)
    if c_lfo then
      wa.lfo = v_lfo; app.dirty = true
    end
    if wa.sel_env then r.ImGui_PopStyleColor(ctx) end

    r.ImGui_SameLine(ctx, 0, 10)
    if wa.sel_env then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), UIHelpers.COL_YELLOW) end
    local c_mseg, v_mseg = r.ImGui_Checkbox(ctx, 'MSEG##w_mseg', wa.mseg)
    if c_mseg then
      wa.mseg = v_mseg; app.dirty = true
    end
    if wa.sel_env then r.ImGui_PopStyleColor(ctx) end

    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), UIHelpers.COL_ORANGE)
    local c_sel, v_sel = r.ImGui_Checkbox(ctx, 'Sel.Env##w_sel', wa.sel_env or false)
    if c_sel then
      wa.sel_env = v_sel
      if v_sel then
        -- Solo mode: disable others, force Control-header modulators on
        wa.external = false
        wa.master_vol = false
        wa.pad_a = false
        wa.pad_b = false
        wa.lfo = true
        wa.mseg = true

        -- Force the actual modulator power states to ON for immediate result
        local lfo = getIndependentLFO()
        local mseg = getIndependentMSEG()
        if lfo then lfo.enabled = true end
        if mseg then mseg.enabled = true end
      end
      app.dirty = true
    end
    r.ImGui_PopStyleColor(ctx)

    r.ImGui_SetCursorPosX(ctx, col_x)
    if wa.sel_env then
      local mod_targets = buildIndependentModulatorTargets(track, false)
      if #mod_targets > 0 then
        local target = mod_targets[1]
        local target_text = "Target: "
        if target.is_midi_take_cc then
          local lane_name = (target.cc_lane == 0x201 and "Pitch") or (target.cc_lane == 0x203 and "Ch Press") or
              (target.cc_lane and ("CC #" .. target.cc_lane) or "Unknown CC")
          target_text = target_text .. "MIDI Editor (" .. lane_name .. ")"
        elseif target.env then
          local ok, retval, e_name = pcall(r.GetEnvelopeName, target.env)
          local env_name = (ok and retval and e_name) or "Selected Envelope"
          target_text = target_text .. env_name
        end
        r.ImGui_SetCursorPosX(ctx, col_x)
        r.ImGui_TextColored(ctx, UIHelpers.COL_YELLOW, target_text)
      else
        r.ImGui_TextColored(ctx, 0x777777FF, "Target: (No envelope selected)")
      end
    end
    r.ImGui_Dummy(ctx, 0, 6)

    local btn_w_row1 = math.floor((actions_w - gap * 2) / 3) -- 3 buttons: Randomize + Write + Morph
    local btn_w_row2 = math.floor((actions_w - gap * 2) / 3) -- 3 buttons: Bake + Bounce + Hide Env

    -- Row 1: Prepare + WRITE + Randomize
    r.ImGui_SetCursorPosX(ctx, col_x)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xcd4444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xe05555FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xb03333FF)
    if r.ImGui_Button(ctx, 'Prepare', btn_w_row1, 48) then
      morphIt()
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_SameLine(ctx, 0, gap)
    local live_on = LiveAutomation.IsEnabled()
    local btn_text = live_on and 'Stop Live##write_btn' or 'WRITE'
    if live_on then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_WARN)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xCC6464FF)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xA03C3CFF)
    else
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x38A882FF)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x25755AFF)
    end
    if r.ImGui_Button(ctx, btn_text, btn_w_row1, 48) then
      if live_on then
        -- Stop live automation
        LiveAutomation.SetEnabled(false)
        app.status = 'Live automation stopped'
      else
        -- WRITE automation and enable live mode for real-time updates
        if track then
          -- Only create JSFX mixer if External or Master Vol are enabled
          local needs_mixer = wa.external or wa.master_vol
          local mixer_ok = true
          if needs_mixer then
            local mixer_idx, is_custom = findOrCreateMixer(track, true)
            if mixer_idx < 0 or not is_custom then
              mixer_ok = false
              app.status = 'Failed to create SBP ReaMotionPad Mixer'
            end
          end
          if mixer_ok then
            -- Write automation points
            writeAutomation(track)
            -- Enable live automation for real-time updates (pass track!)
            LiveAutomation.SetEnabled(true, track)
            -- Force rebuild of targets
            app.state.dirty = true
            app.status = 'WRITE: Automation + Live mode ON'
          end
        else
          app.status = 'No target track selected'
        end
      end
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x38A882FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x25755AFF)
    if r.ImGui_Button(ctx, 'Randomize', btn_w_row1, 48) then
      randomizeState()
    end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_Dummy(ctx, 0, 1)
    -- Row 2: secondary actions (3 buttons)
    local row_w2 = btn_w_row2 * 3 + gap * 2
    r.ImGui_SetCursorPosX(ctx, col_x + math.max(0, actions_w - row_w2))

    -- Bake button (orange)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xE07A50FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB55832FF)
    if r.ImGui_Button(ctx, 'Bake', btn_w_row2, 35) then
      -- Stop live automation before baking
      LiveAutomation.SetEnabled(false)
      interaction.pending_bake = true
      interaction.pending_bake_track = track
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_SameLine(ctx, 0, gap)

    -- Bounce button (orange)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xE07A50FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB55832FF)
    if r.ImGui_Button(ctx, 'Bounce', btn_w_row2, 35) then
      interaction.pending_bounce = true
      interaction.pending_bounce_track = track
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_SameLine(ctx, 0, gap)

    -- Hide/Show Env toggle button (orange)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xE07A50FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB55832FF)
    if r.ImGui_Button(ctx, 'Show/Hide Env', btn_w_row2, 35) then
      r.Main_OnCommand(40890, 0)
    end
    r.ImGui_PopStyleColor(ctx, 3)

    -- Preset slots (1-10): right-click = save, left-click = load
    r.ImGui_Dummy(ctx, 0, 4)
    r.ImGui_SetCursorPosX(ctx, col_x)
    local dl_pre = r.ImGui_GetWindowDrawList(ctx)
    local px_pre, py_pre = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddLine(dl_pre, px_pre, py_pre, px_pre + actions_w, py_pre, 0x3A3A3AFF, 1)
    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_SetCursorPosX(ctx, col_x)
    r.ImGui_TextColored(ctx, 0x707070FF, 'Save States')
    r.ImGui_SetCursorPosX(ctx, col_x)
    local preset_total_w = actions_w
    local preset_gap = 4
    local preset_btn_w = math.floor((preset_total_w - preset_gap * 9) / 10)
    for i = 1, 10 do
      if i > 1 then r.ImGui_SameLine(ctx, 0, preset_gap) end
      local has_preset = State.HasPreset(i)
      local track_name = has_preset and State.GetPresetTrackName(i) or nil
      if has_preset then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2D8C6D99)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2D8C6DBB)
      else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x33333399)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x44444499)
      end
      local clicked_left = r.ImGui_Button(ctx, tostring(i) .. '##preset_slot_' .. i, preset_btn_w, 22)
      local clicked_right = r.ImGui_IsItemClicked(ctx, 1)
      r.ImGui_PopStyleColor(ctx, 2)
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        if has_preset then
          r.ImGui_Text(ctx, 'Track: ' .. (track_name or '(unnamed)'))
          r.ImGui_TextDisabled(ctx, 'Left: Load    Right: Save')
        else
          r.ImGui_TextDisabled(ctx, '(empty slot)')
          r.ImGui_TextDisabled(ctx, 'Right-click to save here')
        end
        r.ImGui_EndTooltip(ctx)
      end
      if clicked_left and has_preset then
        local data = State.LoadPreset(i)
        if data then
          local s = app.state
          if type(data.pads) == 'table' then s.pads = data.pads end
          if type(data.master_lfo) == 'table' then s.master_lfo = data.master_lfo end
          if type(data.master_mseg) == 'table' then s.master_mseg = data.master_mseg end
          if type(data.lfo) == 'table' then s.lfo = data.lfo end
          if type(data.env) == 'table' then s.env = data.env end
          if type(data.bindings) == 'table' then s.bindings = data.bindings end
          if type(data.independent_modulator) == 'table' then s.independent_modulator = data.independent_modulator end
          app.status = 'Preset ' .. i .. ' loaded'
          markDirty()
        end
      end
      if clicked_right then
        local tname = ''
        if track then
          local _, n = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
          tname = n or ''
        end
        if tname == '' then tname = app.state.setup.target_track_name or '' end
        State.SavePreset(app.state, i, tname)
        app.status = 'Preset ' .. i .. ' saved'
      end
    end

    r.ImGui_EndTable(ctx)
  end

  -- Process pending write action after table is closed
  if interaction.pending_write then
    interaction.pending_write = false
    local track = interaction.pending_write_track
    interaction.pending_write_track = nil
    if track then
      writeAutomation(track)
      LiveAutomation.SetEnabled(true, track)
      app.state.dirty = true
    end
  end

  -- Process pending bake action after table is closed
  if interaction.pending_bake then
    interaction.pending_bake = false
    local track = interaction.pending_bake_track
    interaction.pending_bake_track = nil
    if track then
      bakeAutomationItems(track)
      LiveAutomation.SetEnabled(false) -- Stop live automation after bake
    end
  end

  -- Process pending bounce action after table is closed
  if interaction.pending_bounce then
    interaction.pending_bounce = false
    local track = interaction.pending_bounce_track
    interaction.pending_bounce_track = nil
    if track then
      bounceTimeSelection(track)
    end
  end

  -- Status bar logic removed as requested by user
end
local function buildPadPointList(pad, start_t, end_t)
  local len = math.max(0.001, end_t - start_t)
  if not pad then return {} end
  ensureSegmentShapes(pad)
  local seg = pad.segment or {}
  local positions = getPadSegmentPositions(pad)

  if not positions or #positions < 2 then
    positions = { 0.0, 1.0 }
  else
    positions[1] = 0.0
    positions[#positions] = 1.0
  end

  local out = {}
  local seg_count = math.max(1, #positions - 1)
  for i = 1, #positions do
    local t_norm = clamp(positions[i], 0.0, 1.0)
    -- The shape at point i determines the curve to point i+1
    -- So we just use seg_idx = i
    local seg_idx = math.min(i, seg_count)
    local shape = math.floor(tonumber((seg.segment_shapes or {})[seg_idx]) or tonumber(seg.curve_mode) or 0)
    local env_shape = AutomationWriter.MapEnvelopeShape(shape)

    -- In REAPER, end points of the envelope should just be linear since they don't have a NEXT point
    if i == #positions then
      env_shape = 0
    end

    local t_val = seg.segment_tensions and seg.segment_tensions[seg_idx] or seg.curve_tension or 0.0
    local cur_ten = clamp(tonumber(t_val) or 0.0, -1.0, 1.0)
    local env_tension = 0.0
    if shape == 4 then
      env_tension = cur_ten
    end
    out[#out + 1] = {
      time = start_t + (len * t_norm),
      t = t_norm,
      shape = shape,
      tension = cur_ten,
      env_shape = env_shape,
      env_tension = env_tension
    }
  end

  if #out < 2 then
    out = {
      { time = start_t, t = 0.0 },
      { time = end_t,   t = 1.0 }
    }
  end

  return out
end

local function buildPointList(start_t, end_t)
  -- Legacy API for External pad
  return buildPadPointList(app.state.external.pad, start_t, end_t)
end

local function buildMasterMSEGPointList(start_t, end_t)
  local len = math.max(0.001, end_t - start_t)

  -- Master MSEG has its own segmentation
  ensureMasterMSEGData()
  local mseg = getMasterMSEG()
  local positions = getMasterMSEGPositions()

  if not positions or #positions < 2 then
    positions = { 0.0, 1.0 }
  else
    positions[1] = 0.0
    positions[#positions] = 1.0
  end

  local out = {}
  local seg_count = math.max(1, #positions - 1)
  local tension = clamp(tonumber(mseg.curve_tension) or 0.0, -1.0, 1.0)
  for i = 1, #positions do
    local t_norm = clamp(positions[i], 0.0, 1.0)
    local seg_idx = math.min(i, seg_count)
    local shape = math.floor(tonumber((mseg.segment_shapes or {})[seg_idx]) or tonumber(mseg.curve_mode) or 0)
    local env_shape = AutomationWriter.MapEnvelopeShape(shape)

    local t_val = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
    local tension = clamp(tonumber(t_val), -1.0, 1.0)

    if i == #positions then
      env_shape = 0
    end

    local env_tension = 0.0
    if shape == 4 then -- Bezier
      env_tension = tension
    end
    out[#out + 1] = {
      time = start_t + (len * t_norm),
      t = t_norm,
      shape = shape,
      tension = tension,
      env_shape = env_shape,
      env_tension = env_tension
    }
  end

  if #out < 2 then
    out = {
      { time = start_t, t = 0.0 },
      { time = end_t,   t = 1.0 }
    }
  end

  return out
end

local function buildMasterOutputPointList(start_t, end_t)
  local lfo = getMasterLFO()
  if not lfo.enabled then
    return buildMasterMSEGPointList(start_t, end_t)
  end

  local len = math.max(0.001, end_t - start_t)
  local base_rate = math.max(0.05, tonumber(lfo.rate) or 2.0)
  -- Count is based on maximum possible frequency
  local rate_sweep = math.abs(tonumber(lfo.rate_sweep) or 0.0)
  local fm_mod = math.abs(tonumber(lfo.mseg_to_lfo_rate) or 0.0)
  local max_cycles = base_rate * (1.0 + rate_sweep + (fm_mod * 4.0))

  local points_per_cycle = 28
  local count = math.floor(max_cycles * points_per_cycle) + 1
  count = math.max(32, math.min(1500, count))

  local out = {}
  for i = 0, count - 1 do
    local t_norm = i / math.max(1, count - 1)
    out[#out + 1] = {
      time = start_t + (len * t_norm),
      t = t_norm,
      shape = 0,
      tension = 0.0,
      env_shape = 0,
      env_tension = 0.0
    }
  end

  return out
end

-- Build point list for Independent MSEG (uses its own segmentation)
local function buildIndependentMSEGPointList(start_t, end_t)
  local mseg = getIndependentMSEG()
  local len = math.max(0.001, end_t - start_t)

  -- MSEG mode - use MSEG segmentation
  local positions = getIndependentMSEGPositions()
  local point_count = #positions
  local seg_count = math.max(1, point_count - 1) -- Segments = Points - 1

  local out = {}
  for i = 1, point_count do
    local t_norm = positions[i] or (i - 1) / math.max(1, point_count - 1)

    -- Get shape and tension for the segment FORWARD from this point
    local seg_idx = math.min(i, seg_count)

    local shape = math.floor(tonumber(mseg.segment_shapes[seg_idx]) or tonumber(mseg.curve_mode) or 0)
    local t_val = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
    local tension = clamp(tonumber(t_val), -1.0, 1.0)

    -- Map shape to REAPER envelope shape ID
    local env_shape = AutomationWriter.MapEnvelopeShape(shape)

    if i == point_count then
      env_shape = 0
    end

    -- Convert tension to REAPER's range (-1 to 1) for Bezier only
    local env_tension = 0.0
    if shape == 4 then -- Bezier
      env_tension = tension
    end

    out[#out + 1] = {
      time = start_t + (len * t_norm),
      t = t_norm,
      shape = shape,
      tension = tension,
      env_shape = env_shape,
      env_tension = env_tension
    }
  end

  return out
end

local function buildIndependentOutputPointList(start_t, end_t)
  local lfo = getIndependentLFO()
  if not lfo.enabled then
    return buildIndependentMSEGPointList(start_t, end_t)
  end

  local len = math.max(0.001, end_t - start_t)
  local base_rate = math.max(0.05, tonumber(lfo.rate) or 2.0)
  -- Count is based on maximum possible frequency
  local rate_sweep = math.abs(tonumber(lfo.rate_sweep) or 0.0)
  local max_cycles = base_rate * (1.0 + rate_sweep)

  local points_per_cycle = 28
  local count = math.floor(max_cycles * points_per_cycle) + 1
  count = math.max(24, math.min(1000, count))

  local out = {}
  for i = 0, count - 1 do
    local t_norm = i / math.max(1, count - 1)
    out[#out + 1] = {
      time = start_t + (len * t_norm),
      t = t_norm,
      shape = 0,
      tension = 0.0,
      env_shape = 0,
      env_tension = 0.0
    }
  end

  return out
end

local function collectWriteTargets(track, allow_create)
  local targets = {}
  for _, b in ipairs(app.state.bindings) do
    if b.enabled then
      local env = BindingRegistry.ResolveEnvelope(track, b)
      if env then
        targets[#targets + 1] = {
          env = env,
          value_at = function(t)
            local side_val = PadEngine.EvaluatePadSide(app.state.external.pad, t, b.side or 0)
            return BindingRegistry.RemapValue(b, side_val)
          end
        }
      end
    end
  end

  if #targets == 0 then
    if track then
      local mixer_idx, is_custom_mixer = findOrCreateMixer(track, allow_create ~= false)
      if mixer_idx >= 0 then
        if is_custom_mixer then
          configureMotionMixerInputs(track, mixer_idx)
        end

        local create_env = (allow_create ~= false)

        local src_cfg = (app.state.external and app.state.external.sources) or {}

        -- S-curve function for smooth cross-fading between 4 sources
        local function SCurve(t)
          return t * t * t / (t * t * t + (1 - t) * (1 - t) * (1 - t))
        end

        -- External pad provides XY coordinates (2D trajectory)
        local function getExternalPadXY(t)
          local ext_positions = getPadSegmentPositions(app.state.external.pad)
          local x, y = PadEngine.EvaluateExternalPadXY(app.state.external.pad, t, ext_positions)
          return clamp(x, 0.0, 1.0), clamp(y, 0.0, 1.0)
        end

        -- Get 4 channel weights from XY coordinates (4-corner mixer)
        local function get_vols(x, y)
          local sx = SCurve(clamp(x, 0.0, 1.0))
          local sy = SCurve(clamp(y, 0.0, 1.0))
          return (1 - sx) * sy, sx * sy, (1 - sx) * (1 - sy), sx * (1 - sy)
        end

        -- Store value_at functions for all channels
        local channel_funcs = {}
        local start_param = is_custom_mixer and 1 or 0
        local end_param = is_custom_mixer and 4 or 3

        local num_params = r.TrackFX_GetNumParams(track, mixer_idx)
        if is_custom_mixer and num_params < 5 then
          app.status = 'External mixer exposes only ' .. tostring(num_params) .. ' params'
          return targets
        elseif (not is_custom_mixer) and num_params < 4 then
          app.status = 'JS mixer exposes only ' .. tostring(num_params) .. ' params'
          return targets
        end

        -- Custom mixer: params 1-4 = Source 1-4; JS mixer: params 0-3 = 4 channels
        for ch = start_param, end_param do
          local env = r.GetFXEnvelope(track, mixer_idx, ch, create_env)
          if env and type(env) == 'userdata' then
            local cfg_idx = is_custom_mixer and ch or (ch + 1)
            local cfg = app.state.mixer.channels[cfg_idx] or { min = 0.0, max = 1.0 }
            local mn = cfg.min or 0.0
            local mx = cfg.max or 1.0

            local src_idx = is_custom_mixer and ch or (ch + 1)
            local src = src_cfg[src_idx] or {}
            local src_enabled = src.enabled ~= false
            local src_gain = clamp(tonumber(src.gain) or 1.0, 0.0, 2.0)

            channel_funcs[ch] = function(t)
              local pad_x, pad_y = getExternalPadXY(t)
              local w1, w2, w3, w4 = get_vols(pad_x, pad_y)

              -- Equal-power corner gains: reduces audible dip while crossing center.
              local g1 = math.sqrt(math.max(0.0, w1))
              local g2 = math.sqrt(math.max(0.0, w2))
              local g3 = math.sqrt(math.max(0.0, w3))
              local g4 = math.sqrt(math.max(0.0, w4))

              local vol = (ch == 0 and g1) or (ch == 1 and g2) or (ch == 2 and g3) or g4
              if is_custom_mixer then
                local rel = ch - 1
                vol = (rel == 0 and g1) or (rel == 1 and g2) or (rel == 2 and g3) or g4
              end

              if not src_enabled then
                vol = 0.0
              else
                vol = clamp(vol * src_gain, 0.0, 2.0)
              end

              -- Custom JSFX expects normalized dB slider; convert from linear gain.
              local jsfx_norm = gainToJsfxDbNorm(vol)
              local norm_val = mn + (jsfx_norm * (mx - mn))
              return norm_val, pad_x, pad_y, vol
            end

            targets[#targets + 1] = {
              env = env,
              fx_index = mixer_idx,
              param_index = ch,
              value_at = function(t)
                local val, _, _, _ = channel_funcs[ch](t)
                return val
              end
            }
          end
        end

        if #targets > 0 then
          app.status = is_custom_mixer and 'Writing to MotionPad JSFX (Master + 4 sources)' or
              'Writing to JS Mixer (4 channels via Source Mix)'
        end
      end
    end
  end

  return targets
end

buildLinkTargets = function(pad, track, allow_create)
  if not pad or not track then return {} end
  local link_cfg = ensureLinkBinding(pad)
  if not link_cfg or not link_cfg.sources then return {} end

  local targets = {}
  local fx_count = r.TrackFX_GetCount(track)
  local positions = getPadSegmentPositions(pad)
  local create_env = (allow_create ~= false)

  for idx = 1, 4 do
    local src = link_cfg.sources[idx]
    if src and src.enabled then
      local target_type = src.target_type or 'fx'
      local env = nil
      local fx_index = -1
      local param_index = 0
      local param_min = 0.0
      local param_max = 1.0
      local is_jsfx = false

      if target_type == 'fx' then
        -- FX Parameter target
        if (src.param_name or '') ~= '' and (src.fx_guid or '') ~= '' then
          local src_guid_norm = tostring(src.fx_guid or ''):lower()
          fx_index = -1

          for fx_idx = 0, fx_count - 1 do
            local fx_guid = r.TrackFX_GetFXGUID(track, fx_idx)
            if tostring(fx_guid or ''):lower() == src_guid_norm then
              fx_index = fx_idx
              break
            end
          end

          if fx_index < 0 and (src.fx_name or '') ~= '' then
            for fx_idx = 0, fx_count - 1 do
              local _, fx_name = r.TrackFX_GetFXName(track, fx_idx)
              if fx_name == src.fx_name then
                fx_index = fx_idx
                break
              end
            end
          end

          if fx_index >= 0 then
            param_index = math.max(0, math.floor(tonumber(src.param_index) or 0))
            env = r.GetFXEnvelope(track, fx_index, param_index, create_env)
            if env then
              local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_index, param_index)
              param_min = p_min or 0.0
              param_max = p_max or 1.0
              local _, fx_name = r.TrackFX_GetFXName(track, fx_index)
              is_jsfx = fx_name and fx_name:sub(1, 3) == 'JS:'
            end
          end
        end
      elseif target_type == 'track_vol' then
        env = r.GetTrackEnvelopeByName(track, 'Volume')
        if not env and create_env then
          local sel_tracks = {}
          for i = 0, r.CountSelectedTracks(0) - 1 do sel_tracks[#sel_tracks + 1] = r.GetSelectedTrack(0, i) end
          r.SetOnlyTrackSelected(track)
          r.Main_OnCommand(40406, 0) -- Track: Toggle track volume envelope visible
          env = r.GetTrackEnvelopeByName(track, 'Volume')
          r.Main_OnCommand(40297, 0) -- Unselect all tracks
          for _, t in ipairs(sel_tracks) do r.SetTrackSelected(t, true) end
        end
        param_min, param_max = 0.0, 1.0
      elseif target_type == 'track_pan' then
        env = r.GetTrackEnvelopeByName(track, 'Pan')
        if not env and create_env then
          local sel_tracks = {}
          for i = 0, r.CountSelectedTracks(0) - 1 do sel_tracks[#sel_tracks + 1] = r.GetSelectedTrack(0, i) end
          r.SetOnlyTrackSelected(track)
          r.Main_OnCommand(40407, 0) -- Track: Toggle track pan envelope visible
          env = r.GetTrackEnvelopeByName(track, 'Pan')
          r.Main_OnCommand(40297, 0) -- Unselect all tracks
          for _, t in ipairs(sel_tracks) do r.SetTrackSelected(t, true) end
        end
        param_min, param_max = -1.0, 1.0
      end

      local scaling_mode = 0
      if env and type(env) == 'userdata' then
        scaling_mode = r.GetEnvelopeScalingMode(env)

        -- Auto-migrate for FX params
        local cur_smin = tonumber(src.min) or 0.0
        local cur_smax = tonumber(src.max) or 1.0

        if target_type == 'fx' then
          local is_default_range = (math.abs(cur_smin) < 0.0001 and math.abs(cur_smax - 1.0) < 0.0001)
          if is_default_range and param_max > param_min and (param_min < -0.001 or param_max > 1.001) then
            src.min = param_min
            src.max = param_max
            cur_smin = param_min
            cur_smax = param_max
          end
        end

        -- Pre-compute normalized src range
        local norm_src_min, norm_src_max
        if param_max > param_min then
          norm_src_min = (cur_smin - param_min) / (param_max - param_min)
          norm_src_max = (cur_smax - param_min) / (param_max - param_min)
        else
          norm_src_min = 0.0
          norm_src_max = 1.0
        end
        norm_src_min = math.max(-1.0, math.min(2.0, norm_src_min))
        norm_src_max = math.max(-1.0, math.min(2.0, norm_src_max))

        targets[#targets + 1] = {
          env = env,
          fx_index = fx_index,
          param_index = param_index,
          target_type = target_type,
          value_is_normalized = (target_type == 'fx' and not is_jsfx),
          value_at = function(t_norm)
            local live_positions = getPadSegmentPositions(pad)
            local pad_x, pad_y = PadEngine.EvaluateExternalPadXY(pad, t_norm, live_positions)
            local pad_val
            if src.axis == 'x' then
              pad_val = pad_x
            elseif src.axis == 'y' then
              pad_val = pad_y
            else
              local function scurve(v)
                local v3 = v * v * v
                local inv3 = (1 - v) * (1 - v) * (1 - v)
                return (v3 + inv3 > 0) and v3 / (v3 + inv3) or 0.5
              end
              local sx_val = scurve(clamp(pad_x, 0, 1))
              local sy_val = scurve(clamp(pad_y, 0, 1))
              if idx == 1 then
                pad_val = (1 - sx_val) * sy_val
              elseif idx == 2 then
                pad_val = sx_val * sy_val
              elseif idx == 3 then
                pad_val = (1 - sx_val) * (1 - sy_val)
              elseif idx == 4 then
                pad_val = sx_val * (1 - sy_val)
              else
                pad_val = pad_y
              end
            end
            if src.curve == 'smooth' then
              pad_val = 3 * pad_val * pad_val - 2 * pad_val * pad_val * pad_val
            elseif src.curve == 'exponential' then
              pad_val = pad_val * pad_val
            elseif src.curve == 'logarithmic' then
              pad_val = math.sqrt(math.max(0.0, pad_val))
            end
            pad_val = pad_val * (src.scale or 1.0) + (src.offset or 0.0)
            pad_val = clamp(pad_val, 0.0, 1.0)
            local norm_val
            if src.bipolar then
              local bipolar_val = pad_val * 2.0 - 1.0
              local center_norm = (norm_src_min + norm_src_max) * 0.5
              local half_range  = (norm_src_max - norm_src_min) * 0.5
              norm_val          = center_norm + bipolar_val * half_range
            else
              norm_val = norm_src_min + pad_val * (norm_src_max - norm_src_min)
            end
            norm_val = clamp(norm_val, 0.0, 1.0)
            if src.invert then
              norm_val = 1.0 - norm_val
            end

            -- Final scaling based on target type
            if target_type == 'track_vol' and scaling_mode > 0 then
              -- Fader scaling for Volume
              return r.ScaleToEnvelopeMode(scaling_mode, norm_val)
            elseif target_type == 'track_pan' then
              -- Pan is -1..1
              return (norm_val * 2.0) - 1.0
            elseif is_jsfx then
              -- JSFX physical range
              return param_min + norm_val * (param_max - param_min)
            end
            -- Default normalized
            return norm_val
          end
        }
      end
    end
  end

  return targets
end

local function writeLinkAutomation(pad, track, points, shape, tension)
  if not pad or not track then return 0 end

  local targets = buildLinkTargets(pad, track, true)
  if #targets == 0 then
    app.status = 'No Link parameters configured'
    return 0
  end

  return AutomationWriter.WriteOverwrite(track, targets, points, shape, tension, app.state.setup.trim_mode)
end

local function collectMasterMSEGTarget(track, allow_create)
  if not track then return nil end

  local mixer_idx, is_custom_mixer = findOrCreateMixer(track, allow_create ~= false)
  if mixer_idx < 0 then
    return nil
  end

  local create_env = (allow_create ~= false)
  local env_master = r.GetFXEnvelope(track, mixer_idx, 0, create_env)
  if not env_master or type(env_master) ~= 'userdata' then return nil end

  return {
    env = env_master,
    fx_index = mixer_idx,
    param_index = 0,
    value_at = function(t)
      return evaluateMasterOutputAt(t)
    end
  }
end

buildIndependentModulatorTargets = function(track, allow_create)
  if not track then return {} end

  local targets = {}
  local fx_count = r.TrackFX_GetCount(track)
  local create_env = (allow_create ~= false)

  -- LFO Parameter
  local lfo = getIndependentLFO()
  if interaction.write_auto.lfo and lfo and lfo.param and lfo.param.enabled and (lfo.param.param_name or '') ~= '' and (lfo.param.fx_guid or '') ~= '' then
    local src_guid_norm = tostring(lfo.param.fx_guid or ''):lower()
    local fx_index = -1

    for fx_idx = 0, fx_count - 1 do
      local fx_guid = r.TrackFX_GetFXGUID(track, fx_idx)
      local fx_guid_norm = tostring(fx_guid or ''):lower()
      if fx_guid_norm ~= '' and fx_guid_norm == src_guid_norm then
        fx_index = fx_idx
        break
      end
    end

    if fx_index < 0 and (lfo.param.fx_name or '') ~= '' then
      for fx_idx = 0, fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(track, fx_idx)
        if fx_name == lfo.param.fx_name then
          fx_index = fx_idx
          break
        end
      end
    end

    if fx_index >= 0 then
      local p_idx = math.max(0, math.floor(tonumber(lfo.param.param_index) or 0))
      local env = r.GetFXEnvelope(track, fx_index, p_idx, create_env)
      if env then
        local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_index, p_idx)
        local param_min = (p_min ~= nil) and p_min or 0.0
        local param_max = (p_max ~= nil) and p_max or 1.0
        local _, fx_name = r.TrackFX_GetFXName(track, fx_index)
        local is_jsfx = fx_name and fx_name:sub(1, 3) == 'JS:'

        -- Auto-migrate for FX params (same as Link A)
        local src = lfo.param
        local cur_smin = tonumber(src.min) or 0.0
        local cur_smax = tonumber(src.max) or 1.0
        local is_default_range = (math.abs(cur_smin) < 0.0001 and math.abs(cur_smax - 1.0) < 0.0001)
        if is_default_range and param_max > param_min and (param_min < -0.001 or param_max > 1.001) then
          src.min = param_min
          src.max = param_max
          cur_smin = param_min
          cur_smax = param_max
        end

        -- Pre-compute normalized src range
        local norm_src_min, norm_src_max
        if param_max > param_min then
          norm_src_min = (cur_smin - param_min) / (param_max - param_min)
          norm_src_max = (cur_smax - param_min) / (param_max - param_min)
        else
          norm_src_min = 0.0
          norm_src_max = 1.0
        end
        norm_src_min = math.max(-1.0, math.min(2.0, norm_src_min))
        norm_src_max = math.max(-1.0, math.min(2.0, norm_src_max))

        targets[#targets + 1] = {
          env = env,
          fx_index = fx_index,
          param_index = p_idx,
          point_type = ((math.floor(tonumber(lfo.mode) or 0) == 3) and 'lfo') or 'combined',
          value_is_normalized = not is_jsfx,
          value_at = function(t_norm)
            -- mode 3 (Individual): raw LFO shape; modes 0-2: combined LFO+MSEG signal
            local lfo_mode = math.floor(tonumber(lfo.mode) or 0)
            local lfo_val = (lfo_mode == 3)
                and PadEngine.EvaluateLFO(getIndependentLFO(), t_norm)
                or evaluateIndependentOutputAt(t_norm)
            local src = lfo.param

            -- Apply curve
            if src.curve == 'smooth' then
              lfo_val = 3 * lfo_val * lfo_val - 2 * lfo_val * lfo_val * lfo_val
            elseif src.curve == 'exponential' then
              lfo_val = lfo_val * lfo_val
            elseif src.curve == 'logarithmic' then
              lfo_val = math.sqrt(lfo_val)
            end

            -- Apply invert
            if src.invert then
              lfo_val = 1.0 - lfo_val
            end

            -- Apply bipolar
            if src.bipolar then
              lfo_val = (lfo_val * 2.0) - 1.0
            end

            -- Apply scale and offset
            lfo_val = (lfo_val * (src.scale or 1.0)) + (src.offset or 0.0)

            -- Convert to normalized range for this parameter
            local norm_val = norm_src_min + lfo_val * (norm_src_max - norm_src_min)
            norm_val = clamp(norm_val, 0.0, 1.0)

            -- Return in correct format (JSFX wants physical, others want normalized)
            if is_jsfx then
              return param_min + norm_val * (param_max - param_min)
            else
              return norm_val
            end
          end,
          value_at_norm = function(t_norm)
            local lfo_mode = math.floor(tonumber(lfo.mode) or 0)
            local lfo_v = (lfo_mode == 3) and PadEngine.EvaluateLFO(getIndependentLFO(), t_norm) or
                evaluateIndependentOutputAt(t_norm)
            local s = lfo.param
            if s.curve == 'smooth' then
              lfo_v = 3 * lfo_v * lfo_v - 2 * lfo_v * lfo_v * lfo_v
            elseif s.curve == 'exponential' then
              lfo_v = lfo_v * lfo_v
            elseif s.curve == 'logarithmic' then
              lfo_v = math.sqrt(lfo_v)
            end
            if s.invert then lfo_v = 1.0 - lfo_v end
            if s.bipolar then lfo_v = (lfo_v * 2.0) - 1.0 end
            lfo_v = (lfo_v * (s.scale or 1.0)) + (s.offset or 0.0)
            return clamp(norm_src_min + lfo_v * (norm_src_max - norm_src_min), 0.0, 1.0)
          end
        }
      end
    end
  end

  -- MSEG Parameter
  local mseg = getIndependentMSEG()
  if interaction.write_auto.mseg and mseg and mseg.param and mseg.param.enabled and (mseg.param.param_name or '') ~= '' and (mseg.param.fx_guid or '') ~= '' then
    local src_guid_norm = tostring(mseg.param.fx_guid or ''):lower()
    local fx_index = -1

    for fx_idx = 0, fx_count - 1 do
      local fx_guid = r.TrackFX_GetFXGUID(track, fx_idx)
      local fx_guid_norm = tostring(fx_guid or ''):lower()
      if fx_guid_norm ~= '' and fx_guid_norm == src_guid_norm then
        fx_index = fx_idx
        break
      end
    end

    if fx_index < 0 and (mseg.param.fx_name or '') ~= '' then
      for fx_idx = 0, fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(track, fx_idx)
        if fx_name == mseg.param.fx_name then
          fx_index = fx_idx
          break
        end
      end
    end

    if fx_index >= 0 then
      local p_idx = math.max(0, math.floor(tonumber(mseg.param.param_index) or 0))
      local env = r.GetFXEnvelope(track, fx_index, p_idx, create_env)
      if env then
        local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_index, p_idx)
        local param_min = (p_min ~= nil) and p_min or 0.0
        local param_max = (p_max ~= nil) and p_max or 1.0
        local _, fx_name = r.TrackFX_GetFXName(track, fx_index)
        local is_jsfx = fx_name and fx_name:sub(1, 3) == 'JS:'

        -- Auto-migrate for FX params (same as Link A)
        local src = mseg.param
        local cur_smin = tonumber(src.min) or 0.0
        local cur_smax = tonumber(src.max) or 1.0
        local is_default_range = (math.abs(cur_smin) < 0.0001 and math.abs(cur_smax - 1.0) < 0.0001)
        if is_default_range and param_max > param_min and (param_min < -0.001 or param_max > 1.001) then
          src.min = param_min
          src.max = param_max
          cur_smin = param_min
          cur_smax = param_max
        end

        -- Pre-compute normalized src range
        local norm_src_min, norm_src_max
        if param_max > param_min then
          norm_src_min = (cur_smin - param_min) / (param_max - param_min)
          norm_src_max = (cur_smax - param_min) / (param_max - param_min)
        else
          norm_src_min = 0.0
          norm_src_max = 1.0
        end
        norm_src_min = math.max(-1.0, math.min(2.0, norm_src_min))
        norm_src_max = math.max(-1.0, math.min(2.0, norm_src_max))

        targets[#targets + 1] = {
          env = env,
          fx_index = fx_index,
          param_index = p_idx,
          point_type = 'mseg',
          value_is_normalized = not is_jsfx,
          value_at = function(t_norm)
            local mseg_val = evaluateIndependentMSEGAt(t_norm)
            local src = mseg.param

            -- Apply curve
            if src.curve == 'smooth' then
              mseg_val = 3 * mseg_val * mseg_val - 2 * mseg_val * mseg_val * mseg_val
            elseif src.curve == 'exponential' then
              mseg_val = mseg_val * mseg_val
            elseif src.curve == 'logarithmic' then
              mseg_val = math.sqrt(mseg_val)
            end

            -- Apply invert
            if src.invert then
              mseg_val = 1.0 - mseg_val
            end

            -- Apply bipolar
            if src.bipolar then
              mseg_val = (mseg_val * 2.0) - 1.0
            end

            -- Apply scale and offset
            mseg_val = (mseg_val * (src.scale or 1.0)) + (src.offset or 0.0)

            -- Convert to normalized range for this parameter
            local norm_val = norm_src_min + mseg_val * (norm_src_max - norm_src_min)
            norm_val = clamp(norm_val, 0.0, 1.0)

            -- Return in correct format (JSFX wants physical, others want normalized)
            if is_jsfx then
              return param_min + norm_val * (param_max - param_min)
            else
              return norm_val
            end
          end,
          value_at_norm = function(t_norm)
            local mseg_v = evaluateIndependentMSEGAt(t_norm)
            local s = mseg.param
            if s.curve == 'smooth' then
              mseg_v = 3 * mseg_v * mseg_v - 2 * mseg_v * mseg_v * mseg_v
            elseif s.curve == 'exponential' then
              mseg_v = mseg_v * mseg_v
            elseif s.curve == 'logarithmic' then
              mseg_v = math.sqrt(mseg_v)
            end
            if s.invert then mseg_v = 1.0 - mseg_v end
            if s.bipolar then mseg_v = (mseg_v * 2.0) - 1.0 end
            mseg_v = (mseg_v * (s.scale or 1.0)) + (s.offset or 0.0)
            return clamp(norm_src_min + mseg_v * (norm_src_max - norm_src_min), 0.0, 1.0)
          end
        }
      end
    end
  end

  -- FALLBACK: Target Selected Envelope if Sel.Env toggle is active
  local wa = app.state.setup.auto_write
  if wa.sel_env then
    local sel_env = r.GetSelectedEnvelope(0)
    if sel_env and r.ValidatePtr(sel_env, 'TrackEnvelope*') then
      local ok, parent_tr, fx_idx, p_idx = pcall(r.Envelope_GetParentTrack, sel_env)
      if ok and parent_tr == track then
        fx_idx = fx_idx or -1
        p_idx = p_idx or -1

        local param_min, param_max = 0.0, 1.0
        local is_physical = false

        -- Detect if it's a MIDI CC Track Envelope
        local is_midi_cc_env = false
        if fx_idx == -1 then
          local ok, retval, e_name = pcall(r.GetEnvelopeName, sel_env)
          local env_name = (ok and retval and e_name) or ""
          if env_name ~= "" and (env_name:find('MIDI CC') or env_name:find('Pitch') or env_name:find('Channel Pressure')) then
            is_midi_cc_env = true
            is_physical = true -- MIDI CCs use 0-127 physical range (or 0-16383 for Pitch)
            if env_name:find('Pitch') then
              param_min, param_max = 0, 16383
            else
              param_min, param_max = 0, 127
            end
          end
        end

        if fx_idx >= 0 then
          local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_idx, p_idx)
          param_min = p_min or 0.0
          param_max = p_max or 1.0

          -- Robust JSFX check + physical range detection
          local ok, retval, fx_type = pcall(r.TrackFX_GetNamedConfigParm, track, fx_idx, 'fx_type')
          if ok and retval and (fx_type == 'jsfx' or fx_type == 'JS') then
            is_physical = true
          elseif (param_min ~= 0 or param_max ~= 1) then
            -- Some special internal or third-party params report physical ranges
            is_physical = true
          end
        end

        local scaling_mode = r.GetEnvelopeScalingMode(sel_env)

        targets[#targets + 1] = {
          env = sel_env,
          fx_index = fx_idx,
          param_index = p_idx,
          is_midi_cc_env = is_midi_cc_env,
          point_type = 'combined',
          value_is_normalized = not is_physical,
          value_at = function(t_norm)
            local mod_val = evaluateIndependentOutputAt(t_norm)
            if scaling_mode > 0 then
              -- Volume (1) or other REAPER-native scaled types
              return r.ScaleToEnvelopeMode(scaling_mode, mod_val)
            elseif is_physical then
              -- JSFX or MIDI CC / Pitch
              return param_min + mod_val * (param_max - param_min)
            end
            -- Default VST or linear normalized 0..1
            return mod_val
          end,
          value_at_norm = function(t_norm)
            return evaluateIndependentOutputAt(t_norm)
          end
        }
      end
    else
      -- No envelope selected, check for active MIDI Editor CC lane
      local midieditor = r.MIDIEditor_GetActive()
      if midieditor then
        local take = r.MIDIEditor_GetTake(midieditor)
        if take and r.ValidatePtr(take, 'MediaItem_Take*') then
          local ok, lane = pcall(r.MIDIEditor_GetSetting_int, midieditor, 'last_clicked_cc_lane')
          if ok and lane then
            -- lane: 0-127=CC, 0x100|(0-31)=14-bit CC, 0x201=pitch, 0x203=ch pressure
            if (lane >= 0 and lane <= 127) or lane == 0x201 or lane == 0x203 then
              targets[#targets + 1] = {
                take = take,
                cc_lane = lane,
                is_midi_take_cc = true,
                point_type = 'combined',
                value_at = function(t_norm)
                  local mod_val = evaluateIndependentOutputAt(t_norm)
                  if lane == 0x201 then -- Pitch
                    return math.floor(mod_val * 16383)
                  else
                    return math.floor(mod_val * 127)
                  end
                end
              }
            end
          end
        end
      end
    end
  end

  return targets
end

writeAutomation = function(track)
  if r.CountTracks(0) == 0 then
    app.status = 'No tracks in project.'
    return
  end

  if not track then
    app.status = 'Target track not found.'
    return
  end

  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if end_t <= start_t then
    -- FALLBACK: 1 measure
    local bpm = r.Master_GetTempo()
    local beat_len = 60.0 / math.max(1, bpm)
    start_t = r.GetCursorPosition()
    end_t = start_t + (beat_len * 4.0)
  end

  -- Create undo point for automation write
  r.Undo_BeginBlock2(0)
  -- Force project modification for undo by creating/deleting a dummy track
  local num_tracks = r.CountTracks(0)
  r.InsertTrackAtIndex(0, true)
  local dummy_track = r.GetTrack(0, 0)
  if dummy_track then
    r.DeleteTrack(dummy_track)
  end

  local shape = app.state.setup.write_shape or 1
  local tension = app.state.setup.write_tension or 0.0
  local count = 0

  -- Write External pad automation (4 mixer sources) - only if Ext enabled
  if interaction.write_auto.external then
    local points = buildPointList(start_t, end_t)
    local targets = collectWriteTargets(track, true)
    if #targets > 0 then
      count = AutomationWriter.WriteOverwrite(track, targets, points, shape, tension, app.state.setup.trim_mode)
    end
  end

  -- Write Master Volume (combined Master LFO + MSEG) with its own segmentation
  if interaction.write_auto.master_vol then
    local master_target = collectMasterMSEGTarget(track, true)
    if master_target then
      local master_points = buildMasterOutputPointList(start_t, end_t)
      local master_count = AutomationWriter.WriteOverwrite(track, { master_target }, master_points, shape, tension,
        app.state.setup.trim_mode)
      count = count + master_count
    end
  end

  -- Write Link A parameters
  if interaction.write_auto.pad_a and app.state.pads.link_a then
    local link_a_points = buildPadPointList(app.state.pads.link_a, start_t, end_t)
    local link_a_count = writeLinkAutomation(app.state.pads.link_a, track, link_a_points, shape, tension)
    count = count + link_a_count
  end

  -- Write Link B parameters
  if interaction.write_auto.pad_b and app.state.pads.link_b then
    local link_b_points = buildPadPointList(app.state.pads.link_b, start_t, end_t)
    local link_b_count = writeLinkAutomation(app.state.pads.link_b, track, link_b_points, shape, tension)
    count = count + link_b_count
  end

  -- Write Independent Modulator parameters
  local mod_targets = buildIndependentModulatorTargets(track, true)
  if #mod_targets > 0 then
    local lists = { lfo = {}, mseg = {}, combined = {} }
    for _, t in ipairs(mod_targets) do
      table.insert(lists[t.point_type or 'combined'], t)
    end

    if #lists.lfo > 0 then
      local pts = buildIndependentOutputPointList(start_t, end_t)
      count = count + AutomationWriter.WriteOverwrite(track, lists.lfo, pts, shape, tension, app.state.setup.trim_mode)
    end
    if #lists.mseg > 0 then
      local pts = buildIndependentMSEGPointList(start_t, end_t)
      count = count + AutomationWriter.WriteOverwrite(track, lists.mseg, pts, shape, tension, app.state.setup.trim_mode)
    end
    if #lists.combined > 0 then
      local pts = buildIndependentOutputPointList(start_t, end_t)
      count = count +
          AutomationWriter.WriteOverwrite(track, lists.combined, pts, shape, tension, app.state.setup.trim_mode)
    end
  end

  if count == 0 then
    app.status = 'No valid targets found.'
  else
    app.status = 'Written points: ' .. tostring(count)
  end

  -- End undo block
  r.Undo_EndBlock2(0, 'ReaMotion Pad: Write Automation', -1)
end

bakeAutomationItems = function(track)
  if r.CountTracks(0) == 0 then
    app.status = 'No tracks in project.'
    return
  end

  if not track then
    app.status = 'Target track not found.'
    return
  end

  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if end_t <= start_t then
    app.status = 'Set time selection first.'
    return
  end

  -- Create undo point for bake
  r.Undo_BeginBlock2(0)
  -- Force project modification for undo by creating/deleting a dummy track
  r.InsertTrackAtIndex(0, true)
  local dummy_track = r.GetTrack(0, 0)
  if dummy_track then
    r.DeleteTrack(dummy_track)
  end

  local shape = app.state.setup.write_shape or 1
  local tension = app.state.setup.write_tension or 0.0
  local envs = {}
  local total_written = 0

  local function addEnv(env)
    if env and type(env) == 'userdata' then
      envs[env] = true
    end
  end

  if interaction.write_auto.external then
    local targets = collectWriteTargets(track, true)
    if #targets > 0 then
      local points = buildPointList(start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, targets, points, shape, tension, app.state.setup.trim_mode)
      for _, t in ipairs(targets) do
        addEnv(t.env)
      end
    end
  end

  if interaction.write_auto.master_vol then
    local master_target = collectMasterMSEGTarget(track, true)
    if master_target then
      local master_points = buildMasterOutputPointList(start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, { master_target }, master_points, shape, tension,
            app.state.setup.trim_mode)
      addEnv(master_target.env)
    end
  end

  if interaction.write_auto.pad_a and app.state.pads.link_a then
    local link_a_targets = buildLinkTargets(app.state.pads.link_a, track, true)
    if #link_a_targets > 0 then
      local link_a_points = buildPadPointList(app.state.pads.link_a, start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, link_a_targets, link_a_points, shape, tension, app.state.setup
            .trim_mode)
      for _, t in ipairs(link_a_targets) do
        addEnv(t.env)
      end
    end
  end

  if interaction.write_auto.pad_b and app.state.pads.link_b then
    local link_b_targets = buildLinkTargets(app.state.pads.link_b, track, true)
    if #link_b_targets > 0 then
      local link_b_points = buildPadPointList(app.state.pads.link_b, start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, link_b_targets, link_b_points, shape, tension, app.state.setup
            .trim_mode)
      for _, t in ipairs(link_b_targets) do
        addEnv(t.env)
      end
    end
  end

  -- Independent Modulator parameters
  local mod_targets = buildIndependentModulatorTargets(track, true)
  if #mod_targets > 0 then
    local lists = { lfo = {}, mseg = {}, combined = {} }
    for _, t in ipairs(mod_targets) do
      table.insert(lists[t.point_type or 'combined'], t)
    end

    if #lists.lfo > 0 then
      local pts = buildIndependentOutputPointList(start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, lists.lfo, pts, shape, tension, app.state.setup.trim_mode)
      for _, t in ipairs(lists.lfo) do addEnv(t.env) end
    end
    if #lists.mseg > 0 then
      local pts = buildIndependentMSEGPointList(start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, lists.mseg, pts, shape, tension, app.state.setup.trim_mode)
      for _, t in ipairs(lists.mseg) do addEnv(t.env) end
    end
    if #lists.combined > 0 then
      local pts = buildIndependentOutputPointList(start_t, end_t)
      total_written = total_written +
          AutomationWriter.WriteOverwrite(track, lists.combined, pts, shape, tension, app.state.setup.trim_mode)
      for _, t in ipairs(lists.combined) do addEnv(t.env) end
    end
  end

  if total_written == 0 then
    app.status = 'No valid targets to bake.'
    return
  end

  local len = math.max(0.001, end_t - start_t)
  local baked = 0
  for env, _ in pairs(envs) do
    local idx = r.InsertAutomationItem(env, -1, start_t, len)
    if idx >= 0 then
      baked = baked + 1
    end
  end

  -- Disable live automation after bake
  LiveAutomation.SetEnabled(false)

  app.status = 'Baked items: ' .. tostring(baked)

  -- End undo block
  r.Undo_EndBlock2(0, 'ReaMotion Pad: Bake Automation', -1)
end

bounceTimeSelection = function(track)
  if not track then
    app.status = 'Target track not found.'
    return
  end

  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if end_t <= start_t then
    app.status = 'Set time selection first.'
    return
  end

  -- Create undo point for bounce
  r.Undo_BeginBlock2(0)
  -- Force project modification for undo by creating/deleting a dummy track
  r.InsertTrackAtIndex(0, true)
  local dummy_track = r.GetTrack(0, 0)
  if dummy_track then
    r.DeleteTrack(dummy_track)
  end

  -- Tail (render хвіст)
  local tail_sec = tonumber(app.state.setup.render_tail_sec or 0)
  if tail_sec and tail_sec > 0 then
    end_t = end_t + tail_sec
  end

  local selected = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.IsTrackSelected(tr) then
      selected[#selected + 1] = tr
    end
  end

  r.SetOnlyTrackSelected(track)
  -- Render channels (з опцій)
  local ch = tonumber(app.state.setup.render_channels or 2)
  r.SetMediaTrackInfo_Value(track, 'I_NCHAN', ch)
  -- Встановити розширений time selection до bounce
  r.GetSet_LoopTimeRange2(0, true, false, start_t, end_t, false)
  local render_cmd = (ch > 2) and 41720 or 41719
  r.Main_OnCommand(render_cmd, 0)

  for _, tr in ipairs(selected) do
    r.SetTrackSelected(tr, true)
  end
  r.UpdateArrange()
  app.status = 'Bounce done.'

  -- End undo block
  r.Undo_EndBlock2(0, 'ReaMotion Pad: Bounce', -1)
end

hideTrackEnvelopes = function(track, show)
  if not track then
    app.status = 'Target track not found.'
    return
  end
  local count = r.CountTrackEnvelopes(track)
  if count == 0 then
    app.status = 'No envelopes on track.'
    return
  end
  for i = 0, count - 1 do
    local env = r.GetTrackEnvelope(track, i)
    local _, chunk = r.GetEnvelopeStateChunk(env, '', false)
    if show then
      chunk = chunk:gsub('VIS 0', 'VIS 1')
    else
      chunk = chunk:gsub('VIS 1', 'VIS 0')
    end
    r.SetEnvelopeStateChunk(env, chunk, false)
  end
  r.UpdateArrange()
  app.status = show and 'Envelopes shown (' .. tostring(count) .. ')' or 'Envelopes hidden (' .. tostring(count) .. ')'
end

local function drawModulatorParamSetupPopup()
  if not interaction.modulator_param_setup_open then return end

  local track = getTargetTrack()
  local fx_list = BindingRegistry.ListFX(track) or {}

  if not track then
    interaction.modulator_param_setup_open = nil
    return
  end

  local mod_type = interaction.modulator_param_setup_open
  local mod_obj

  if mod_type == 'lfo' then
    mod_obj = getIndependentLFO()
  elseif mod_type == 'mseg' then
    mod_obj = getIndependentMSEG()
  else
    interaction.modulator_param_setup_open = nil
    return
  end

  local param_cfg = mod_obj.param or {}

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
  r.ImGui_SetNextWindowSize(ctx, 300, 360, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowPos(ctx, 100, 100, r.ImGui_Cond_FirstUseEver())

  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoSavedSettings() |
      r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()

  local win_title = (mod_type == 'lfo' and 'LFO Parameter Setup' or 'MSEG Parameter Setup') ..
      '###mod_param_win_v2_' .. mod_type
  local visible, open = r.ImGui_Begin(ctx, win_title, true, flags)

  if not open then
    interaction.modulator_param_setup_open = nil
  end

  if visible then
    drawIndependentModulatorParamSetup(mod_type, param_cfg, track, fx_list)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    local close_btn_w = 70
    r.ImGui_SetCursorPosX(ctx, (300 - close_btn_w) / 2)
    if r.ImGui_Button(ctx, 'Close', close_btn_w, 0) then
      interaction.modulator_param_setup_open = nil
    end
  end

  r.ImGui_End(ctx)
  r.ImGui_PopStyleVar(ctx, 2)
end

local function drawBottomPanels(track)
  -- Reduced padding
  drawSetupAndSegment(track)
end

local function drawMain()
  local track = getTargetTrack()
  pushTheme()
  r.ImGui_SetNextWindowSize(ctx, 1178, 750, r.ImGui_Cond_Always())
  local visible, open = r.ImGui_Begin(ctx, 'SBP ReaMotion Pad', true,
    r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize())

  if visible then
    drawTopBar(track)
    -- Reduced padding
    drawPadGrid()
    drawBottomPanels(track)
  end

  r.ImGui_End(ctx)

  -- Вікна-попапи (тільки поза основним)
  drawModulatorParamSetupPopup()
  drawPadSetupPopup()
  if interaction.options_open then
    SettingsUI.DrawOptionsWindow(ctx, app, interaction, markDirty)
  end

  popTheme()
  return open
end

local function maybeAutosave()
  if not app.dirty then
    if app.waiting_for_item_deactivate and not r.ImGui_IsAnyItemActive(ctx) then
      -- In case dirty was cleared manually but we were waiting
      app.waiting_for_item_deactivate = false
    end
    return
  end

  if r.ImGui_IsAnyItemActive(ctx) then
    app.waiting_for_item_deactivate = true
  else
    if app.waiting_for_item_deactivate then
      State.Save(app.state)
      r.Undo_OnStateChangeEx2(0, 'ReaMotionPad: UI Change', 8, -1)
      app.dirty = false
      app.waiting_for_item_deactivate = false
      app.auto_save_counter = 0
    else
      app.auto_save_counter = app.auto_save_counter + 1
      if app.auto_save_counter >= 30 then
        State.Save(app.state)
        r.Undo_OnStateChangeEx2(0, 'ReaMotionPad: Value Update', 8, -1)
        app.dirty = false
        app.auto_save_counter = 0
      end
    end
  end
end

local function updateLiveAutomation()
  -- Use LiveAutomation module for live updates
  if not LiveAutomation then
    return
  end
  if LiveAutomation.IsEnabled() then
    local track = getTargetTrack()
    LiveAutomation.Update(
      track,
      app.state,
      interaction,
      {
        collectWriteTargets = collectWriteTargets,
        buildLinkTargets = buildLinkTargets,
        buildIndependentModulatorTargets = buildIndependentModulatorTargets,
        collectMasterMSEGTarget = collectMasterMSEGTarget
      },
      buildPadPointList,
      buildMasterOutputPointList,
      buildIndependentOutputPointList,
      buildIndependentMSEGPointList,
      markDirty
    )
  end
end

local function loop()
  local ok, result = pcall(function()
    return drawMain()
  end)

  if not ok then
    r.ShowConsoleMsg("SBP ReaMotion Pad Error:\n" .. tostring(result) .. "\n")
    State.Save(app.state)
    return
  end

  local open = result

  updateLiveAutomation()

  maybeAutosave()

  if open then
    r.defer(loop)
  else
    State.Save(app.state)
  end
end

loop()
