---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local ExternalUI = {}

local r = reaper

local COL_ACCENT = 0x2D8C6DFF
local COL_PANEL = 0x111111FF

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Convert dB to normalized value
function ExternalUI.DbToNormalized(db, min_db, max_db)
  min_db = min_db or -60
  max_db = max_db or 6
  if db <= min_db then return 0.0 end
  if db >= max_db then return 1.0 end
  local range = max_db - min_db
  return (db - min_db) / range
end

-- Convert normalized value to dB
function ExternalUI.NormalizedToDb(norm, min_db, max_db)
  min_db = min_db or -60
  max_db = max_db or 6
  norm = math.max(0.0, math.min(1.0, norm))
  local range = max_db - min_db
  return min_db + (range * norm)
end

-- Draw single source quadrant
function ExternalUI.DrawSourceQuadrant(ctx, idx, corner_name, src, ch_cfg, quad_w, quad_h, markDirty, track,
                                       findOrCreateMixer, configureMixerInputs)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

  local child_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  r.ImGui_BeginChild(ctx, 'src_child_' .. idx, quad_w, quad_h, child_flags)

  local content_pad_x = 12
  local content_pad_y = 10
  r.ImGui_SetCursorPos(ctx, content_pad_x, content_pad_y)

  r.ImGui_TextColored(ctx, COL_ACCENT, string.format('Source %d - %s', idx, corner_name))

  local label_w = 42
  local right_w = 44
  local small_w = 46
  local gap = 6

  local function rightLabel(text)
    local txt_w = r.ImGui_CalcTextSize(ctx, text)
    local col_w = r.ImGui_GetContentRegionAvail(ctx)
    local start_x = r.ImGui_GetCursorPosX(ctx)
    r.ImGui_SetCursorPosX(ctx, start_x + math.max(0, col_w - txt_w))
    r.ImGui_Text(ctx, text)
  end

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 8, 6)
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

    -- Channels
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rightLabel('Chan:')
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_SetNextItemWidth(ctx, small_w)
    local ch_l = math.max(1, math.min(63, math.floor(tonumber(src.ch_l) or ((idx - 1) * 2 + 1))))
    local c_ch_l, v_ch_l = r.ImGui_InputInt(ctx, '##ch_l', ch_l, 0, 0)
    local need_update_jsfx = false
    if c_ch_l then
      src.ch_l = clamp(v_ch_l, 1, 63)
      if src.ch_r and src.ch_r < src.ch_l then src.ch_r = src.ch_l end
      markDirty()
      need_update_jsfx = true
    end
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_Text(ctx, '-')
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_SetNextItemWidth(ctx, small_w)
    local ch_r = math.max(ch_l, math.min(64, math.floor(tonumber(src.ch_r) or (ch_l + 1))))
    local c_ch_r, v_ch_r = r.ImGui_InputInt(ctx, '##ch_r', ch_r, 0, 0)
    if c_ch_r then
      src.ch_r = clamp(v_ch_r, src.ch_l or 1, 64)
      markDirty()
      need_update_jsfx = true
    end
    if need_update_jsfx and track and findOrCreateMixer and configureMixerInputs then
      local mixer_idx, is_custom = findOrCreateMixer(track, true)
      if mixer_idx >= 0 and is_custom then
        configureMixerInputs(track, mixer_idx)
      end
    end
    r.ImGui_TableNextColumn(ctx)
    local ch_txt = string.format('(%dch)', (ch_r - ch_l + 1))
    local ch_txt_w = r.ImGui_CalcTextSize(ctx, ch_txt)
    local ch_col_w = r.ImGui_GetContentRegionAvail(ctx)
    local ch_start_x = r.ImGui_GetCursorPosX(ctx)
    r.ImGui_SetCursorPosX(ctx, ch_start_x + math.max(0, (ch_col_w - ch_txt_w) * 0.5))
    r.ImGui_TextDisabled(ctx, ch_txt)

    -- Gain
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rightLabel('Gain:')
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local gain = clamp(tonumber(src.gain) or 1.0, 0.0, 2.0)
    local c_gain, v_gain = r.ImGui_SliderDouble(ctx, '##gain', gain, 0.0, 2.0, '%.2f')
    if c_gain then
      src.gain = v_gain
      markDirty()
    end
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, '')

    -- Min/Max dB
    local min_norm = ch_cfg.min or 0.0
    local max_norm = ch_cfg.max or 1.0
    local min_db = ExternalUI.NormalizedToDb(min_norm, -60, 6)
    local max_db = ExternalUI.NormalizedToDb(max_norm, -60, 6)

    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rightLabel('Min:')
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_SetNextItemWidth(ctx, 56)
    local c_min, v_min = r.ImGui_DragDouble(ctx, '##min_db', min_db, 0.1, -60, 6, '%.1f')
    if c_min then
      ch_cfg.min = ExternalUI.DbToNormalized(v_min, -60, 6)
      markDirty()
    end
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_SetNextItemWidth(ctx, 56)
    local c_max, v_max = r.ImGui_DragDouble(ctx, '##max_db', max_db, 0.1, -60, 6, '%.1f')
    if c_max then
      ch_cfg.max = ExternalUI.DbToNormalized(v_max, -60, 6)
      markDirty()
    end
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, '')

    -- Invert
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, '')
    r.ImGui_TableNextColumn(ctx)
    local c_inv, v_inv = r.ImGui_Checkbox(ctx, 'Invert##inv_' .. idx, src.invert == true)
    if c_inv then
      src.invert = v_inv
      markDirty()
    end
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, '')

    r.ImGui_EndTable(ctx)
  end
  r.ImGui_PopStyleVar(ctx)

  r.ImGui_EndChild(ctx)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopStyleVar(ctx, 3)
end

-- Draw full External Pad Setup popup content
function ExternalUI.DrawSetupPopup(ctx, sources, mixer_channels, markDirty, interaction, track, findOrCreateMixer,
                                   configureMixerInputs)
  r.ImGui_TextColored(ctx, 0xFFD700FF, 'Configure 4 Corner Sources (matches pad layout)')
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 3)

  -- Sync JSFX on popup open
  if not interaction.pad_setup_jsfx_synced and track and findOrCreateMixer and configureMixerInputs then
    local mixer_idx, is_custom = findOrCreateMixer(track, true)
    if mixer_idx >= 0 and is_custom then
      configureMixerInputs(track, mixer_idx)
    end
    interaction.pad_setup_jsfx_synced = true
  end

  -- 2x2 table for 4 quadrants
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 8, 8)
  if r.ImGui_BeginTable(ctx, 'quad_table', 2, r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, 'left_col', r.ImGui_TableColumnFlags_WidthFixed(), 260)
    r.ImGui_TableSetupColumn(ctx, 'right_col', r.ImGui_TableColumnFlags_WidthFixed(), 260)

    -- Top row
    r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 230)
    r.ImGui_TableNextColumn(ctx)
    ExternalUI.DrawSourceQuadrant(ctx, 1, 'Top-Left', sources[1], mixer_channels[1], 260, 230, markDirty, track,
      findOrCreateMixer, configureMixerInputs)

    r.ImGui_TableNextColumn(ctx)
    ExternalUI.DrawSourceQuadrant(ctx, 2, 'Top-Right', sources[2], mixer_channels[2], 260, 230, markDirty, track,
      findOrCreateMixer, configureMixerInputs)

    -- Bottom row
    r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 230)
    r.ImGui_TableNextColumn(ctx)
    ExternalUI.DrawSourceQuadrant(ctx, 3, 'Bottom-Left', sources[3], mixer_channels[3], 260, 230, markDirty, track,
      findOrCreateMixer, configureMixerInputs)

    r.ImGui_TableNextColumn(ctx)
    ExternalUI.DrawSourceQuadrant(ctx, 4, 'Bottom-Right', sources[4], mixer_channels[4], 260, 230, markDirty, track,
      findOrCreateMixer, configureMixerInputs)

    r.ImGui_EndTable(ctx)
  end
  r.ImGui_PopStyleVar(ctx)
end

return ExternalUI
