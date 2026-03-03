---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local PadUI = {}

local r = reaper

local COL_BG = 0x171717FF
local COL_FRAME = 0x2A2A2AFF
local COL_TEXT = 0xE8E8E8FF
local COL_ACCENT = 0x2D8C6DFF
local COL_GRID = 0xFFFFFF20
local COL_PANEL = 0x111111FF
local COL_HANDLE = 0xEAEAEAFF

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Draw vector-mode pad (3-point: start, peak, end) or multi-point segmented pad
-- params = { interaction, markDirty }
function PadUI.DrawVectorPad(ctx, title, pad, id, w, h, corner_labels, seg_id, params)
  local interaction = params.interaction
  local markDirty = params.markDirty

  r.ImGui_Text(ctx, title)
  r.ImGui_Dummy(ctx, w, h)

  local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  r.ImGui_DrawList_AddRectFilled(dl, p_x, p_y, p_x + w, p_y + h, COL_PANEL, 4)
  r.ImGui_DrawList_AddRect(dl, p_x, p_y, p_x + w, p_y + h, 0x3A3A3AFF, 4)

  r.ImGui_DrawList_PushClipRect(dl, p_x, p_y, p_x + w, p_y + h, true)

  r.ImGui_DrawList_AddLine(dl, p_x + w * 0.5, p_y, p_x + w * 0.5, p_y + h, COL_GRID, 1)
  r.ImGui_DrawList_AddLine(dl, p_x, p_y + h * 0.5, p_x + w, p_y + h * 0.5, COL_GRID, 1)

  local txt_col = 0xFFFFFF60
  local function DT(tx, x, y) r.ImGui_DrawList_AddText(dl, x, y, txt_col, tx) end
  local mid_x = p_x + (w * 0.5)
  local mid_y = p_y + (h * 0.5)
  if corner_labels then
    DT(tostring(corner_labels.tl or 'Ext 1'), p_x + 4, p_y + 3)
    local tr_text = tostring(corner_labels.tr or 'Ext 2')
    local tr_w = r.ImGui_CalcTextSize(ctx, tr_text)
    DT(tr_text, p_x + w - tr_w - 4, p_y + 3)
    DT(tostring(corner_labels.bl or 'Ext 3'), p_x + 4, p_y + h - 15)
    local br_text = tostring(corner_labels.br or 'Ext 4')
    local br_w = r.ImGui_CalcTextSize(ctx, br_text)
    DT(br_text, p_x + w - br_w - 4, p_y + h - 15)
  else
    DT("Left", p_x + 3, mid_y - 8)
    DT("Right", p_x + w - 35, mid_y - 8)
    DT("Top", mid_x - 12, p_y + 3)
    DT("Bottom", mid_x - 25, p_y + h - 15)
  end

  local center_x = p_x + w * 0.5
  local center_y = p_y + h * 0.5
  local max_r = math.sqrt((w * 0.5) ^ 2 + (h * 0.5) ^ 2)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.75, 0xFFFFFF15, 0, 1)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.50, 0xFFFFFF20, 0, 1)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.35, 0xFFFFFF2A, 0, 1)

  local hit_margin = 8
  r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
  r.ImGui_InvisibleButton(ctx, id, w + hit_margin * 2, h + hit_margin * 2)

  -- Right mouse click opens Setup popup
  if seg_id and r.ImGui_IsItemClicked(ctx, 1) then
    interaction.pad_setup_open = true
    interaction.pad_setup_target = seg_id
    interaction.pad_setup_jsfx_synced = false
  end

  local is_clicked = r.ImGui_IsItemClicked(ctx)
  local is_active = r.ImGui_IsItemActive(ctx)
  local changed = false
  local is_vector_mode = (pad.sx ~= nil or pad.points == nil)

  if is_vector_mode then
    if not pad.sx then pad.sx = 0.0 end
    if not pad.sy then pad.sy = 0.2 end
    if not pad.px then pad.px = 0.5 end
    if not pad.py then pad.py = 0.8 end
    if not pad.ex then pad.ex = 1.0 end
    if not pad.ey then pad.ey = 0.2 end

    local sx, sy = pad.sx, pad.sy
    local px, py = pad.px, pad.py
    local ex, ey = pad.ex, pad.ey

    if is_clicked then
      local mx, my = r.ImGui_GetMousePos(ctx)
      local s_sc_x, s_sc_y = p_x + sx * w, p_y + (1 - sy) * h
      local p_sc_x, p_sc_y = p_x + px * w, p_y + (1 - py) * h
      local e_sc_x, e_sc_y = p_x + ex * w, p_y + (1 - ey) * h

      local hit_r = 1000
      interaction.active_pad = id
      local dist_s = (mx - s_sc_x) ^ 2 + (my - s_sc_y) ^ 2
      local dist_p = (mx - p_sc_x) ^ 2 + (my - p_sc_y) ^ 2
      local dist_e = (mx - e_sc_x) ^ 2 + (my - e_sc_y) ^ 2

      if dist_s < hit_r and dist_s < dist_p and dist_s < dist_e then
        interaction.active_point = 1
      elseif dist_p < hit_r and dist_p < dist_e then
        interaction.active_point = 2
      elseif dist_e < hit_r then
        interaction.active_point = 3
      else
        interaction.active_pad = nil
      end
    end

    if not r.ImGui_IsMouseDown(ctx, 0) then
      interaction.active_pad = nil
    end

    if is_active and interaction.active_pad == id then
      local dx, dy = r.ImGui_GetMouseDelta(ctx)
      local dnx, dny = dx / w, -dy / h

      if interaction.active_point == 1 then
        sx = clamp(sx + dnx, 0, 1)
        sy = clamp(sy + dny, 0, 1)
        changed = true
      elseif interaction.active_point == 2 then
        px = clamp(px + dnx, 0, 1)
        py = clamp(py + dny, 0, 1)
        changed = true
      elseif interaction.active_point == 3 then
        ex = clamp(ex + dnx, 0, 1)
        ey = clamp(ey + dny, 0, 1)
        changed = true
      end

      if changed then
        pad.sx, pad.sy = sx, sy
        pad.px, pad.py = px, py
        pad.ex, pad.ey = ex, ey
        markDirty()
      end
    end

    local s_x, s_y = p_x + sx * w, p_y + (1 - sy) * h
    local p_x_d, p_y_d = p_x + px * w, p_y + (1 - py) * h
    local e_x, e_y = p_x + ex * w, p_y + (1 - ey) * h

    r.ImGui_DrawList_AddLine(dl, s_x, s_y, p_x_d, p_y_d, COL_ACCENT, 1)
    r.ImGui_DrawList_AddLine(dl, p_x_d, p_y_d, e_x, e_y, COL_ACCENT, 1)

    r.ImGui_DrawList_AddCircle(dl, s_x, s_y, 4, 0x808080FF, 0, 1.5)

    r.ImGui_DrawList_AddCircleFilled(dl, p_x_d, p_y_d, 4, COL_ACCENT)
    r.ImGui_DrawList_AddCircle(dl, p_x_d, p_y_d, 4, 0xFFFFFFFF, 0, 1.5)

    local arrow_size = 6
    local dx = e_x - p_x_d
    local dy = e_y - p_y_d
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.001 then
      dx = dx / len
      dy = dy / len
      local perp_x = -dy
      local perp_y = dx
      local tip_x = e_x
      local tip_y = e_y
      local base_x = e_x - dx * arrow_size
      local base_y = e_y - dy * arrow_size
      local wing_size = arrow_size * 0.5
      r.ImGui_DrawList_AddTriangleFilled(dl,
        tip_x, tip_y,
        base_x - perp_x * wing_size, base_y - perp_y * wing_size,
        base_x + perp_x * wing_size, base_y + perp_y * wing_size,
        COL_ACCENT)
    end
  else
    if not pad.points or #pad.points < 2 then
      pad.points = { { x = 0.0, y = 0.2 }, { x = 0.5, y = 0.8 }, { x = 1.0, y = 0.2 } }
    end

    local function px_coord(norm_x) return p_x + clamp(norm_x, 0.0, 1.0) * w end
    local function py_coord(norm_y) return p_y + h - clamp(norm_y, 0.0, 1.0) * h end

    local mx, my = r.ImGui_GetMousePos(ctx)
    local function dist2(ax, ay, bx, by)
      local dx, dy = ax - bx, ay - by
      return dx * dx + dy * dy
    end

    if is_clicked then
      local best_i, best_d = nil, nil
      for i = 1, #pad.points do
        local px_i = px_coord(pad.points[i].x)
        local py_i = py_coord(pad.points[i].y)
        local d = dist2(mx, my, px_i, py_i)
        if not best_d or d < best_d then
          best_d = d; best_i = i
        end
      end
      interaction.active_pad = id
      interaction.active_point = best_i
    end

    if is_active and interaction.active_pad == id and interaction.active_point then
      local idx = tonumber(interaction.active_point) or 1
      if idx >= 1 and idx <= #pad.points then
        local nx = clamp((mx - p_x) / math.max(1, w), 0.0, 1.0)
        local ny = clamp(1.0 - ((my - p_y) / math.max(1, h)), 0.0, 1.0)

        if math.abs((pad.points[idx].x or 0) - nx) > 0.0001 or math.abs((pad.points[idx].y or 0) - ny) > 0.0001 then
          pad.points[idx].x = nx
          pad.points[idx].y = ny
          changed = true
        end
      end
    end

    if r.ImGui_IsMouseReleased(ctx, 0) then
      interaction.active_pad = nil
      interaction.active_point = nil
    end

    if changed then markDirty() end

    for i = 1, #pad.points - 1 do
      local x1 = px_coord(pad.points[i].x)
      local y1 = py_coord(pad.points[i].y)
      local x2 = px_coord(pad.points[i + 1].x)
      local y2 = py_coord(pad.points[i + 1].y)
      r.ImGui_DrawList_AddLine(dl, x1, y1, x2, y2, COL_ACCENT, 1)
    end

    for i, pt in ipairs(pad.points) do
      local cpx = px_coord(pt.x)
      local cpy = py_coord(pt.y)

      if i == 1 then
        r.ImGui_DrawList_AddCircle(dl, cpx, cpy, 4, 0x808080FF, 0, 1.5)
      elseif i == #pad.points then
        local prev_pt = pad.points[i - 1]
        local prev_x = px_coord(prev_pt.x)
        local prev_y = py_coord(prev_pt.y)

        local arrow_size = 6
        local dx = cpx - prev_x
        local dy = cpy - prev_y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.001 then
          dx = dx / len
          dy = dy / len
          local perp_x = -dy
          local perp_y = dx
          local tip_x = cpx
          local tip_y = cpy
          local base_x = cpx - dx * arrow_size
          local base_y = cpy - dy * arrow_size
          local wing_size = arrow_size * 0.5
          r.ImGui_DrawList_AddTriangleFilled(dl,
            tip_x, tip_y,
            base_x - perp_x * wing_size, base_y - perp_y * wing_size,
            base_x + perp_x * wing_size, base_y + perp_y * wing_size,
            COL_ACCENT)
        end
      else
        r.ImGui_DrawList_AddCircleFilled(dl, cpx, cpy, 4, COL_ACCENT)
        r.ImGui_DrawList_AddCircle(dl, cpx, cpy, 4, 0xFFFFFFFF, 0, 1.5)
      end
    end
  end

  r.ImGui_DrawList_PopClipRect(dl)
  return changed or false
end

-- Draw pad segmentation controls
-- params = { interaction, markDirty, resegmentPadRealtime, getPadSegmentPositions, ensureSegmentShapes }
function PadUI.DrawSegmentationModule(ctx, pad, seg_id, w, params)
  if not pad then return end
  local interaction = params.interaction
  local markDirty = params.markDirty

  if type(pad.segment) ~= 'table' then
    pad.segment = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      curve_mode = 0,
      curve_tension = 0.0,
      segment_shapes = { 0 }
    }
  end

  local seg = pad.segment
  local mode = math.floor(tonumber(seg.mode) or 0)

  r.ImGui_PushID(ctx, seg_id)
  local line_w = w - 10
  local combo_w = 64
  local spacing = 4

  r.ImGui_SetNextItemWidth(ctx, combo_w)
  local changed_mode, v_mode = r.ImGui_Combo(ctx, 'Dot', mode, 'Manual\0Musical\0')
  if changed_mode then
    seg.mode = math.floor(tonumber(v_mode) or 0)
    markDirty()
    params.resegmentPadRealtime(pad)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  if mode == 0 then
    r.ImGui_SetNextItemWidth(ctx, math.max(50, line_w - combo_w - spacing - 10))
    local points = math.max(2, math.min(8, math.floor(tonumber(seg.points) or 2)))
    local changed_pts, v_pts = r.ImGui_SliderInt(ctx, '##pts', points, 2, 8, '%d Dots')
    if changed_pts then
      local new_pts = math.floor(tonumber(v_pts) or 2)
      seg.points = new_pts
      markDirty()
      params.resegmentPadRealtime(pad)
    end
  else
    r.ImGui_SetNextItemWidth(ctx, math.max(50, line_w - combo_w - spacing - 10))
    local div = math.max(1, math.min(8, math.floor(tonumber(seg.division) or 2)))
    local changed_div, v_div = r.ImGui_SliderInt(ctx, '##div', div, 1, 8, '%d Segs')
    if changed_div then
      seg.division = math.floor(tonumber(v_div) or 2)
      markDirty()
      params.resegmentPadRealtime(pad)
    end
  end

  local positions = params.getPadSegmentPositions(pad)
  local draw_h = 36
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x1, y1 = cx, cy + 2
  local x2, y2 = cx + (w), cy + draw_h
  local mid_y = (y1 + y2) * 0.5

  r.ImGui_SetCursorScreenPos(ctx, x1, y1)
  r.ImGui_InvisibleButton(ctx, '##seg_vis', x2 - x1, y2 - y1)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)

  if mode == 0 and hovered and r.ImGui_IsMouseClicked(ctx, 0) then
    local mx = ({ r.ImGui_GetMousePos(ctx) })[1]
    local best_idx, best_dist = nil, nil
    for i = 2, #positions - 1 do
      local seg_x = x1 + (positions[i] * (x2 - x1))
      local dist = math.abs(mx - seg_x)
      if dist < 9 and (not best_dist or dist < best_dist) then
        best_idx = i
        best_dist = dist
      end
    end
    interaction.seg_active_idx = best_idx
  end

  if mode == 0 and active and interaction.seg_active_idx then
    local mx = ({ r.ImGui_GetMousePos(ctx) })[1]
    local idx = math.floor(tonumber(interaction.seg_active_idx) or 0)
    if idx > 1 and idx < #positions then
      local left = (positions[idx - 1] or 0.0) + 0.01
      local right = (positions[idx + 1] or 1.0) - 0.01
      local nx = clamp((mx - x1) / math.max(1.0, (x2 - x1)), left, right)
      if math.abs((positions[idx] or 0.0) - nx) > 0.0001 then
        positions[idx] = nx
        markDirty()
      end
    end
  end

  if not r.ImGui_IsMouseDown(ctx, 0) then
    interaction.seg_active_idx = nil
  end

  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, COL_PANEL, 3)
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, 0x3A3A3AFF, 3)

  for i = 1, #positions do
    local sx = x1 + ((positions[i] or 0.0) * (x2 - x1))
    local line_width = (i == 1 or i == #positions) and 2 or 1
    r.ImGui_DrawList_AddLine(dl, sx, y1, sx, y2, COL_ACCENT, line_width)
    if i > 1 and i < #positions then
      local active_pt = interaction.seg_active_idx == i
      local radius = active_pt and 4 or 3
      r.ImGui_DrawList_AddCircleFilled(dl, sx, mid_y, radius, mode == 0 and 0xFFFFFFFF or 0x808080FF)
    end
  end

  r.ImGui_Dummy(ctx, w, 2)

  params.ensureSegmentShapes(pad)
  if seg.curve_tension == nil then
    seg.curve_tension = 0.0
  end

  local seg_count = math.max(1, #positions - 1)
  seg.selected_segment = clamp(math.floor(tonumber(seg.selected_segment) or 1), 1, seg_count)

  r.ImGui_Text(ctx, 'Seg')
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_SetNextItemWidth(ctx, 46)
  local c_seg, v_seg = r.ImGui_SliderInt(ctx, '##seg_idx', seg.selected_segment, 1, seg_count)
  if c_seg then
    seg.selected_segment = math.floor(tonumber(v_seg) or 1)
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  local c_all, v_all = r.ImGui_Checkbox(ctx, 'All##seg_all', seg.apply_all == true)
  if c_all then
    seg.apply_all = v_all
    if seg.apply_all == true then
      local shape_cur = math.floor(tonumber(seg.segment_shapes[seg.selected_segment]) or tonumber(seg.curve_mode) or 0)
      seg.curve_mode = shape_cur
      for i = 1, seg_count do
        seg.segment_shapes[i] = shape_cur
      end
    end
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_SetNextItemWidth(ctx, 97)
  local shape_cur = math.floor(tonumber(seg.segment_shapes[seg.selected_segment]) or tonumber(seg.curve_mode) or 0)
  local c_shape, v_shape = r.ImGui_Combo(ctx, '##seg_shape', shape_cur,
    'Linear\0Ease In\0Ease Out\0S-Curve\0Bezier\0Square\0')
  if c_shape then
    local new_shape = math.floor(tonumber(v_shape) or 0)
    seg.curve_mode = new_shape
    if seg.apply_all == true then
      for i = 1, seg_count do
        seg.segment_shapes[i] = new_shape
      end
    else
      seg.segment_shapes[seg.selected_segment] = new_shape
    end
    markDirty()
  end

  r.ImGui_Text(ctx, 'Tens')
  r.ImGui_SameLine(ctx, 0, 6)
  local setup_w = 70
  r.ImGui_SetNextItemWidth(ctx, math.max(60, line_w - setup_w - spacing - 19))
  local c_ten, v_ten = r.ImGui_SliderDouble(ctx, '##seg_tension', seg.curve_tension, 0.0, 1.0)
  if c_ten then
    seg.curve_tension = clamp(tonumber(v_ten) or 0.0, 0.0, 1.0)
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT)
  if r.ImGui_Button(ctx, 'Link##seg_setup_' .. seg_id, setup_w, 0) then
    interaction.pad_setup_open = true
    interaction.pad_setup_target = seg_id
    interaction.pad_setup_jsfx_synced = false
  end
  r.ImGui_PopStyleColor(ctx, 3)

  r.ImGui_PopID(ctx)
end

return PadUI
