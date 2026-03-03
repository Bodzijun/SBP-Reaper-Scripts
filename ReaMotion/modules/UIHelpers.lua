---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local UIHelpers = {}

local r = reaper

-- Color constants
UIHelpers.COL_BG = 0x171717FF
UIHelpers.COL_FRAME = 0x2A2A2AFF
UIHelpers.COL_TEXT = 0xE8E8E8FF
UIHelpers.COL_ACCENT = 0x2D8C6DFF
UIHelpers.COL_WARN = 0xC05050FF
UIHelpers.COL_ORANGE = 0xD46A3FFF
UIHelpers.COL_YELLOW = 0xEDD050FF
UIHelpers.COL_GRID = 0xFFFFFF20
UIHelpers.COL_LINE = 0x2EC8A0FF
UIHelpers.COL_HANDLE = 0xEAEAEAFF
UIHelpers.COL_PANEL = 0x111111FF

-- Push theme colors and styles
function UIHelpers.PushTheme(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), UIHelpers.COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), UIHelpers.COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), UIHelpers.COL_FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_TEXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UIHelpers.COL_FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x454545FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x303030FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x404040FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x42B48DFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x333333FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorHovered(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorActive(), 0x555555FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), UIHelpers.COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), UIHelpers.COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1D1D1DFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10.0, 10.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 7.0, 6.0)
end

-- Pop theme colors and styles
function UIHelpers.PopTheme(ctx)
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, 22)
end

-- Draw header with accent color
function UIHelpers.DrawHeader(ctx, label)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_ACCENT)
  r.ImGui_Text(ctx, label)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_Separator(ctx)
end

-- Clamp utility
function UIHelpers.Clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Map envelope shapes between internal and Reaper formats
function UIHelpers.MapEnvelopeShape(shape)
  if shape == 1 then
    return 4
  elseif shape == 2 then
    return 3
  elseif shape == 3 then
    return 2
  elseif shape == 4 then
    return 5
  elseif shape == 5 then
    return 1
  end
  return 0
end

-- Draw top bar with track selector, reset, presets, and options button
function UIHelpers.DrawTopBar(ctx, setup, markDirty, refreshFXCache, preset_state)
  local r = reaper
  preset_state = preset_state or {}

  r.ImGui_Text(ctx, 'Track:')
  r.ImGui_SameLine(ctx, 0, 6)

  local track = UIHelpers.GetTargetTrack(setup)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xE07A50FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB55832FF)
  if track and r.ImGui_Button(ctx, 'Use Selected##top', 90, 0) then
    local _, name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    setup.target_track_name = name or ''
    refreshFXCache(track)
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 3)

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 140)
  local c_name, v_name = r.ImGui_InputText(ctx, '##target_top', setup.target_track_name)
  if c_name then
    setup.target_track_name = v_name
    markDirty()
  end

  -- Reset button (right after track name)
  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xE05555FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xF07070FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xC03030FF)
  local action = nil
  if r.ImGui_Button(ctx, 'Reset All', 60, 0) then
    action = 'reset'
  end
  r.ImGui_PopStyleColor(ctx, 3)

  if not track then
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_TextColored(ctx, UIHelpers.COL_WARN, 'No track')
  end

  -- Right-aligned section: Preset controls + Options
  local sep_w = r.ImGui_CalcTextSize(ctx, '|')
  local preset_w = r.ImGui_CalcTextSize(ctx, 'Preset:')
  -- Total: sep + 6 + "Preset:" + 4 + combo(140) + 4 + Save(42) + 4 + Del(32) + 8 + sep + 6 + Options(60)
  local right_total = sep_w + 6 + preset_w + 4 + 140 + 4 + 42 + 4 + 32 + 8 + sep_w + 6 + 60
  r.ImGui_SameLine(ctx)
  local avail_x = r.ImGui_GetContentRegionAvail(ctx)
  local cur_x = r.ImGui_GetCursorPosX(ctx)
  local right_start = cur_x + avail_x - right_total
  if right_start > cur_x then
    r.ImGui_SetCursorPosX(ctx, right_start)
  end

  -- Preset controls
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xAAAAAAFF)
  r.ImGui_Text(ctx, '|')
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_Text(ctx, 'Preset:')
  r.ImGui_SameLine(ctx, 0, 4)

  r.ImGui_SetNextItemWidth(ctx, 140)
  local combo_list = preset_state.combo_list or '(none)\0'
  local sel_idx = preset_state.selected_idx or -1
  local c_preset, v_preset = r.ImGui_Combo(ctx, '##preset_combo', sel_idx, combo_list)
  if c_preset then
    action = 'preset_select'
    preset_state.selected_idx = v_preset
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x38A882FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x25755AFF)
  if r.ImGui_Button(ctx, 'Save##preset', 42, 0) then
    action = 'preset_save'
  end
  r.ImGui_PopStyleColor(ctx, 3)

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xE05555FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xF07070FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xC03030FF)
  if r.ImGui_Button(ctx, 'Del##preset', 32, 0) then
    action = 'preset_delete'
  end
  r.ImGui_PopStyleColor(ctx, 3)

  -- Separator + Options
  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xAAAAAAFF)
  r.ImGui_Text(ctx, '|')
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x38A882FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x25755AFF)
  if r.ImGui_Button(ctx, 'Options', 60, 0) then
    action = 'options'
  end
  r.ImGui_PopStyleColor(ctx, 3)

  return action
end

-- Get target track by name or selected
function UIHelpers.GetTargetTrack(setup)
  local r = reaper
  if setup.target_track_name ~= '' then
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
      local track = r.GetTrack(0, i)
      local _, tr_name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
      if tr_name == setup.target_track_name then
        return track
      end
    end
  end
  return r.GetSelectedTrack(0, 0)
end

-- Draw separator line
function UIHelpers.DrawSeparator(ctx)
  local r = reaper
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, cx, cy, cx + avail_w, cy, 0x3A3A3AFF, 1)
  r.ImGui_Dummy(ctx, 0, 2)
end

-- Right-aligned label helper
function UIHelpers.RightLabel(ctx, text)
  local r = reaper
  local txt_w = r.ImGui_CalcTextSize(ctx, text)
  local col_w = r.ImGui_GetContentRegionAvail(ctx)
  local start_x = r.ImGui_GetCursorPosX(ctx)
  r.ImGui_SetCursorPosX(ctx, start_x + math.max(0, col_w - txt_w))
  r.ImGui_Text(ctx, text)
end

return UIHelpers
