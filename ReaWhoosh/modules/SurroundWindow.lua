local function sw_clamp(v, mn, mx)
  if v == nil then return mn end
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function sw_polar_norm(deg, r_norm)
  local rad = math.rad(deg)
  local x = 0.5 + r_norm * math.sin(rad)
  local y = 0.5 + r_norm * math.cos(rad)
  return x, y
end

local function sw_circle_point(config, t)
  local len = sw_clamp(config.sur_c_len or 1.0, 0.05, 1.0)
  local offset = config.sur_c_off or 0.0
  local direction = config.sur_c_dir and -1 or 1
  local a = (offset + (t * direction)) * len * math.pi * 2.0
  local path_r = 0.42
  local x = 0.5 + path_r * math.cos(a)
  local y = 0.5 + path_r * math.sin(a)
  return sw_clamp(x, 0, 1), sw_clamp(y, 0, 1)
end

local function sw_circle_tangent(config, t)
  local len = sw_clamp(config.sur_c_len or 1.0, 0.05, 1.0)
  local direction = config.sur_c_dir and -1 or 1
  local offset = config.sur_c_off or 0.0
  local a = (offset + (t * direction)) * len * math.pi * 2.0
  local da = direction * len * math.pi * 2.0
  local path_r = 0.42
  local dx = -path_r * math.sin(a) * da
  local dy = path_r * math.cos(a) * da
  return dx, dy
end

function BuildSurroundPathPoints(config)
  local mode = config.sur_mode or 0
  if mode < 0.5 then
    return sw_clamp(config.sur_v_s_x or 0.0, 0, 1), sw_clamp(config.sur_v_s_y or 0.0, 0, 1),
           sw_clamp(config.sur_v_p_x or 0.5, 0, 1), sw_clamp(config.sur_v_p_y or 1.0, 0, 1),
           sw_clamp(config.sur_v_e_x or 1.0, 0, 1), sw_clamp(config.sur_v_e_y or 0.5, 0, 1)
  end

  local s_x, s_y = sw_circle_point(config, 0.0)
  local p_x, p_y = sw_circle_point(config, 0.5)
  local e_x, e_y = sw_circle_point(config, 1.0)

  config.sur_c_s_x, config.sur_c_s_y = s_x, s_y
  config.sur_c_p_x, config.sur_c_p_y = p_x, p_y
  config.sur_c_e_x, config.sur_c_e_y = e_x, e_y

  return s_x, s_y, p_x, p_y, e_x, e_y
end

function GetSurroundLivePoint(config, t_norm)
  local s_x, s_y, p_x, p_y, e_x, e_y = BuildSurroundPathPoints(config)
  local t = sw_clamp(t_norm or 0.5, 0, 1)
  if t <= 0.5 then
    local k = t * 2.0
    return s_x + (p_x - s_x) * k, s_y + (p_y - s_y) * k
  end
  local k = (t - 0.5) * 2.0
  return p_x + (e_x - p_x) * k, p_y + (e_y - p_y) * k
end

function DrawSurroundWindow(ctx, r, settings, config, col_acc)
  if not settings.sur_win_open then
    return false, false
  end

  local changed = false
  local changed_path = false
  local visible, open = r.ImGui_Begin(ctx, "Surround Path (UTI 5.1)", true, r.ImGui_WindowFlags_AlwaysAutoResize())
  settings.sur_win_open = open

  if visible then
    local mode = config.sur_mode or 0
    local is_vec = mode < 0.5
    local is_circle = mode >= 0.5

    local rv_vec, v_vec = r.ImGui_Checkbox(ctx, "Vector 3-point", is_vec)
    if rv_vec and v_vec then config.sur_mode = 0; changed = true end
    r.ImGui_SameLine(ctx)
    local rv_cir, v_cir = r.ImGui_Checkbox(ctx, "Circle 3-point", is_circle)
    if rv_cir and v_cir then config.sur_mode = 1; changed = true end

    r.ImGui_Separator(ctx)

    local view_size = 420
    r.ImGui_Dummy(ctx, view_size, view_size)
    local x0, y0 = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + view_size, y0 + view_size, 0x00000066, 6)
    r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + view_size, y0 + view_size, 0xFFFFFF33, 6)

    local function tx(nx) return x0 + nx * view_size end
    local function ty(ny) return y0 + (1.0 - ny) * view_size end
    local cx = x0 + view_size * 0.5
    local cy = y0 + view_size * 0.5
    local outer_r = view_size * 0.42

    -- Vector mode: квадратна grid, Circle mode: ITU-кола
    if is_vec then
      -- Квадратна сітка для Vector mode
      local grid_step = view_size * 0.42
      r.ImGui_DrawList_AddRect(dl, cx - grid_step, cy - grid_step, cx + grid_step, cy + grid_step, 0xFFFFFF30, 0, 0, 1.5)
      r.ImGui_DrawList_AddRect(dl, cx - grid_step * 0.66, cy - grid_step * 0.66, cx + grid_step * 0.66, cy + grid_step * 0.66, 0xFFFFFF18, 0, 0, 1)
      r.ImGui_DrawList_AddLine(dl, cx, y0 + 10, cx, y0 + view_size - 10, 0xFFFFFF1C, 1)
      r.ImGui_DrawList_AddLine(dl, x0 + 10, cy, x0 + view_size - 10, cy, 0xFFFFFF1C, 1)
    else
      -- Круглі кола для Circle mode
      r.ImGui_DrawList_AddCircle(dl, cx, cy, outer_r, 0xFFFFFF30, 0, 1.5)
      r.ImGui_DrawList_AddCircle(dl, cx, cy, outer_r * 0.66, 0xFFFFFF18, 0, 1)
      r.ImGui_DrawList_AddLine(dl, cx, y0 + 10, cx, y0 + view_size - 10, 0xFFFFFF1C, 1)
      r.ImGui_DrawList_AddLine(dl, x0 + 10, cy, x0 + view_size - 10, cy, 0xFFFFFF1C, 1)
    end

    -- Колонки 5.1: L/R/C/Ls/Rs + LFE
    local speakers_circle = {
      {"C", 0}, {"L", -30}, {"R", 30}, {"Ls", -110}, {"Rs", 110}
    }
    local speakers_vector = {
      {"C", 0}, {"L", -45}, {"R", 45}, {"Ls", -135}, {"Rs", 135}
    }
    local speakers = is_vec and speakers_vector or speakers_circle

    for _, sp in ipairs(speakers) do
      local nx, ny = sw_polar_norm(sp[2], 0.42)
      local sx, sy = tx(nx), ty(ny)
      r.ImGui_DrawList_AddCircleFilled(dl, sx, sy, 5, 0xA8A8A8FF)
      
      -- Підписи зовні в Circle mode
      if is_circle then
        local rad = math.rad(sp[2])
        local txt_r = 0.48
        local txt_x = 0.5 + txt_r * math.sin(rad)
        local txt_y = 0.5 + txt_r * math.cos(rad)
        local txt_sx, txt_sy = tx(txt_x), ty(txt_y)
        r.ImGui_DrawList_AddText(dl, txt_sx - 8, txt_sy - 7, 0xFFFFFFFF, sp[1])
      else
        r.ImGui_DrawList_AddText(dl, sx + 7, sy - 7, 0xFFFFFFFF, sp[1])
      end
    end
    
    local lfe_x, lfe_y = tx(0.5), ty(0.5)
    r.ImGui_DrawList_AddCircleFilled(dl, lfe_x, lfe_y, 5, 0x7F7F7FFF)
    r.ImGui_DrawList_AddText(dl, lfe_x + 7, lfe_y - 7, 0xFFFFFFFF, "LFE")

    local s_x, s_y, p_x, p_y, e_x, e_y = BuildSurroundPathPoints(config)

    if is_vec then
      local hit_margin = 8
      r.ImGui_SetCursorScreenPos(ctx, x0 - hit_margin, y0 - hit_margin)
      r.ImGui_InvisibleButton(ctx, "##surround_drag", view_size + hit_margin * 2, view_size + hit_margin * 2)
      local active = r.ImGui_IsItemActive(ctx)

      if r.ImGui_IsItemClicked(ctx) then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local pts = {
          {tx(s_x), ty(s_y), 1},
          {tx(p_x), ty(p_y), 2},
          {tx(e_x), ty(e_y), 3}
        }
        local best = nil
        local best_d = math.huge
        for _, pt in ipairs(pts) do
          local d = (mx - pt[1]) * (mx - pt[1]) + (my - pt[2]) * (my - pt[2])
          if d < best_d then best = pt[3]; best_d = d end
        end
        config.sur_drag = best
      end

      if not r.ImGui_IsMouseDown(ctx, 0) then
        config.sur_drag = nil
      end

      if active and config.sur_drag then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local nx = sw_clamp((mx - x0) / view_size, 0, 1)
        local ny = sw_clamp(1.0 - ((my - y0) / view_size), 0, 1)
        if config.sur_drag == 1 then
          config.sur_v_s_x, config.sur_v_s_y = nx, ny
        elseif config.sur_drag == 2 then
          config.sur_v_p_x, config.sur_v_p_y = nx, ny
        else
          config.sur_v_e_x, config.sur_v_e_y = nx, ny
        end
        changed = true
        changed_path = true
        s_x, s_y, p_x, p_y, e_x, e_y = BuildSurroundPathPoints(config)
      end

      local xs, ys = tx(s_x), ty(s_y)
      local xp, yp = tx(p_x), ty(p_y)
      local xe, ye = tx(e_x), ty(e_y)
      r.ImGui_DrawList_AddLine(dl, xs, ys, xp, yp, col_acc, 2)
      r.ImGui_DrawList_AddLine(dl, xp, yp, xe, ye, col_acc, 2)
      r.ImGui_DrawList_AddCircle(dl, xs, ys, 6, 0xAAAAAAFF, 0, 2)
      r.ImGui_DrawList_AddRectFilled(dl, xp - 5, yp - 5, xp + 5, yp + 5, 0xFFFFFFFF)
      
      -- Стрілка за напрямком руху (від p до e)
      local ax, ay = xe - xp, ye - yp
      local ln = math.sqrt(ax * ax + ay * ay)
      if ln > 0.01 then
        ax = ax / ln
        ay = ay / ln
        local px, py = -ay, ax
        local as = 9
        local bx, by = xe - ax * as, ye - ay * as
        local lx, ly = bx - px * 5, by - py * 5
        local rx, ry = bx + px * 5, by + py * 5
        r.ImGui_DrawList_AddTriangleFilled(dl, xe, ye, lx, ly, rx, ry, col_acc)
      else
        r.ImGui_DrawList_AddCircleFilled(dl, xe, ye, 6, col_acc)
      end
    else
      local path_steps = 84
      local last_x, last_y = nil, nil
      for i = 0, path_steps do
        local t = i / path_steps
        local pxn, pyn = sw_circle_point(config, t)
        local sx, sy = tx(pxn), ty(pyn)
        if last_x then
          r.ImGui_DrawList_AddLine(dl, last_x, last_y, sx, sy, col_acc, 2)
        end
        last_x, last_y = sx, sy
      end

      local xs, ys = tx(s_x), ty(s_y)
      local xp, yp = tx(p_x), ty(p_y)
      local xe, ye = tx(e_x), ty(e_y)
      r.ImGui_DrawList_AddCircle(dl, xs, ys, 6, 0xAAAAAAFF, 0, 2)
      r.ImGui_DrawList_AddRectFilled(dl, xp - 5, yp - 5, xp + 5, yp + 5, 0xFFFFFFFF)
      
      -- Стрілка за напрямком траєкторії (tangent)
      local tx_dir, ty_dir = sw_circle_tangent(config, 1.0)
      local ln = math.sqrt(tx_dir * tx_dir + ty_dir * ty_dir)
      if ln > 0.01 then
        local ax = tx_dir / ln
        local ay = -ty_dir / ln
        local px, py = -ay, ax
        local as = 9
        local bx, by = xe - ax * as, ye - ay * as
        local lx, ly = bx - px * 5, by - py * 5
        local rx, ry = bx + px * 5, by + py * 5
        r.ImGui_DrawList_AddTriangleFilled(dl, xe, ye, lx, ly, rx, ry, col_acc)
      else
        r.ImGui_DrawList_AddCircleFilled(dl, xe, ye, 6, col_acc)
      end

      r.ImGui_Separator(ctx)
      r.ImGui_SetNextItemWidth(ctx, view_size)
      local rv_l, v_l = r.ImGui_SliderDouble(ctx, "Length", config.sur_c_len or 1.0, 0.05, 1.0, "%.2f")
      if rv_l then config.sur_c_len = v_l; changed = true; changed_path = true end
      r.ImGui_SetNextItemWidth(ctx, view_size)
      local rv_o, v_o = r.ImGui_SliderDouble(ctx, "Offset", config.sur_c_off or 0.0, 0.0, 1.0, "%.2f")
      if rv_o then config.sur_c_off = v_o; changed = true; changed_path = true end
      r.ImGui_SetNextItemWidth(ctx, view_size)
      local rv_s, v_s = r.ImGui_SliderDouble(ctx, "Speed", config.sur_c_speed or 1.0, 0.1, 10.0, "%.2f")
      if rv_s then config.sur_c_speed = v_s; changed = true end
      local rv_d, v_d = r.ImGui_Checkbox(ctx, "Direction CW", config.sur_c_dir == true)
      if rv_d then config.sur_c_dir = v_d; changed = true; changed_path = true end
    end

    r.ImGui_Separator(ctx)
    r.ImGui_TextDisabled(ctx, "5.1 Surround: L/R/C/Ls/Rs + LFE")
    if is_vec then
      r.ImGui_TextDisabled(ctx, "Vector mode: square field, drag start / middle / end points")
      r.ImGui_TextDisabled(ctx, "Speaker position = hard sound (no phantom)")
    else
      r.ImGui_TextDisabled(ctx, "Circle mode: Length 1.0 = full circle, Speed multiplies rotation")
    end
  end

  r.ImGui_End(ctx)
  return changed, changed_path
end
