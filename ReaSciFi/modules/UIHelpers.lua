---@diagnostic disable: undefined-field

local UIHelpers = {}
local r = reaper

UIHelpers.COL_BG = 0x1A1A1AFF
UIHelpers.COL_FRAME = 0x2D2D2DFF
UIHelpers.COL_TEXT = 0xE6EAEDFF
UIHelpers.COL_ACCENT = 0x2D8C6DFF
UIHelpers.COL_ORANGE = 0xD46A3FFF
UIHelpers.COL_WARN = 0xC05050FF
UIHelpers.COL_PANEL = 0x202020FF
UIHelpers.COL_GRID = 0xFFFFFF18
UIHelpers.COL_HANDLE = 0xF2F2F2FF
UIHelpers.COL_LINE = 0x42C59BFF

function UIHelpers.PushTheme(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), UIHelpers.COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), UIHelpers.COL_PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), UIHelpers.COL_FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x474747FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_TEXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1F5A3EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x28714EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x329363FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x323232FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3E3E3EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x4A4A4AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x232323FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x2B2B2BFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), 0x1F1F1FFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), UIHelpers.COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x3EAF88FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x474747FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x474747FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorHovered(), 0x595959FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorActive(), 0x6A6A6AFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 12)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 7)
end

function UIHelpers.PopTheme(ctx)
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, 22)
end

function UIHelpers.Clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function UIHelpers.DrawSectionHeader(ctx, label)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UIHelpers.COL_ORANGE)
  r.ImGui_Text(ctx, label)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_Separator(ctx)
end

function UIHelpers.DrawXYPad(ctx, label, x_value, y_value, size)
  size = size or 150
  local changed = false
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local start_x, start_y = r.ImGui_GetCursorScreenPos(ctx)
  local visible_label = label or ''
  local item_id = label or 'xy_pad'

  local hash_pos = string.find(visible_label, '##', 1, true)
  if hash_pos then
    visible_label = string.sub(visible_label, 1, hash_pos - 1)
  end

  if visible_label ~= '' then
    r.ImGui_Text(ctx, visible_label)
  end
  r.ImGui_InvisibleButton(ctx, '##' .. item_id, size, size)

  local pad_x, pad_y = r.ImGui_GetItemRectMin(ctx)
  local pad_x2, pad_y2 = r.ImGui_GetItemRectMax(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)

  r.ImGui_DrawList_AddRectFilled(draw_list, pad_x, pad_y, pad_x2, pad_y2, UIHelpers.COL_PANEL, 4)
  r.ImGui_DrawList_AddRect(draw_list, pad_x, pad_y, pad_x2, pad_y2, 0x3D464FFF, 4, 0, 1.0)

  local mid_x = pad_x + (pad_x2 - pad_x) * 0.5
  local mid_y = pad_y + (pad_y2 - pad_y) * 0.5
  r.ImGui_DrawList_AddLine(draw_list, mid_x, pad_y, mid_x, pad_y2, UIHelpers.COL_GRID, 1.0)
  r.ImGui_DrawList_AddLine(draw_list, pad_x, mid_y, pad_x2, mid_y, UIHelpers.COL_GRID, 1.0)

  local handle_x = pad_x + x_value * (pad_x2 - pad_x)
  local handle_y = pad_y2 - y_value * (pad_y2 - pad_y)
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local grab_radius = 18
  local dx = mouse_x - handle_x
  local dy = mouse_y - handle_y
  local near_handle = (dx * dx + dy * dy) <= (grab_radius * grab_radius)
  local edge_pad = 12
  local in_extended_pad = mouse_x >= (pad_x - edge_pad) and mouse_x <= (pad_x2 + edge_pad)
    and mouse_y >= (pad_y - edge_pad) and mouse_y <= (pad_y2 + edge_pad)

  if (hovered or active or near_handle or in_extended_pad) and r.ImGui_IsMouseDown(ctx, 0) then
    x_value = UIHelpers.Clamp((mouse_x - pad_x) / (pad_x2 - pad_x), 0.0, 1.0)
    y_value = 1.0 - UIHelpers.Clamp((mouse_y - pad_y) / (pad_y2 - pad_y), 0.0, 1.0)
    changed = true
    handle_x = pad_x + x_value * (pad_x2 - pad_x)
    handle_y = pad_y2 - y_value * (pad_y2 - pad_y)
  end

  local handle_col = active and UIHelpers.COL_ORANGE or UIHelpers.COL_HANDLE
  r.ImGui_DrawList_AddCircleFilled(draw_list, handle_x, handle_y, 6, handle_col)
  r.ImGui_DrawList_AddCircle(draw_list, handle_x, handle_y, 8, UIHelpers.COL_LINE, 0, 1.5)

  r.ImGui_Text(ctx, string.format('X %.2f  Y %.2f', x_value, y_value))
  if start_y > 0 then
    r.ImGui_Dummy(ctx, 0, 2)
  end

  return changed, x_value, y_value
end

return UIHelpers