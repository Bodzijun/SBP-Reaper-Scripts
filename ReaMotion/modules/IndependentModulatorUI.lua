---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local IndependentModulatorUI = {}

local r = reaper

local COL_BG = 0x171717FF
local COL_FRAME = 0x2A2A2AFF
local COL_ACCENT = 0x2D8C6DFF
local COL_ORANGE = 0xD46A3FFF
local COL_GRID = 0xFFFFFF20
local COL_PANEL = 0x111111FF
local COL_HANDLE = 0xEAEAEAFF
local COL_TEXT = 0xE8E8E8FF

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Draw Independent Modulator (LFO + MSEG with parameter binding)
function IndependentModulatorUI.DrawModule(ctx, w, h, getIndependentLFO, getIndependentMSEG,
                                           evaluateIndependentLFOAt, evaluateIndependentMSEGAt,
                                           markDirty, interaction, track, fx_list, is_sel_env)
  local mseg = getIndependentMSEG()
  local positions = {}

  -- Build positions array
  local mode = math.floor(tonumber(mseg.mode) or 0)
  if mode == 1 then
    local div = math.max(2, math.min(8, math.floor(tonumber(mseg.division) or 2)))
    local count = div + 1
    for i = 0, count - 1 do
      positions[#positions + 1] = i / (count - 1)
    end
  else
    local points = math.max(2, math.min(8, math.floor(tonumber(mseg.points) or 2)))
    if type(mseg.manual_positions) ~= 'table' then
      mseg.manual_positions = {}
    end
    local pos = mseg.manual_positions
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
    pos[1] = 0.0
    pos[points] = 1.0
    for i = 2, points - 1 do
      local left = (pos[i - 1] or 0.0) + 0.01
      local right = (pos[i + 1] or 1.0) - 0.01
      pos[i] = clamp(pos[i] or 0.5, left, right)
    end
    positions = pos
  end

  local lfo = getIndependentLFO()
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local avail_now = math.max(280, r.ImGui_GetContentRegionAvail(ctx) - 8)
  local content_w = math.min(w, avail_now)
  content_w = math.max(280, content_w)

  local side_w = math.max(130, math.min(170, math.floor(content_w * 0.36)))
  local graph_w = math.max(120, content_w - side_w - 12)

  local lfo_h = 218
  local mseg_h = 110

  -- LFO BLOCK
  local header_col = is_sel_env and 0xEDD050FF or 0xFFFFFFFF
  r.ImGui_TextColored(ctx, header_col, 'LFO')
  if r.ImGui_BeginTable(ctx, 'ind_lfo_row', 2) then
    r.ImGui_TableSetupColumn(ctx, 'lfo_graph_col', r.ImGui_TableColumnFlags_WidthFixed(), graph_w)
    r.ImGui_TableSetupColumn(ctx, 'lfo_ctrl_col')

    -- LFO Graph
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_InvisibleButton(ctx, '##ind_lfo_canvas', graph_w, lfo_h)
    local lx1, ly1 = r.ImGui_GetItemRectMin(ctx)
    local lx2, ly2 = r.ImGui_GetItemRectMax(ctx)

    r.ImGui_DrawList_AddRectFilled(dl, lx1, ly1, lx2, ly2, COL_PANEL, 4)
    r.ImGui_DrawList_AddRect(dl, lx1, ly1, lx2, ly2, 0x3A3A3AFF, 4)

    local function lfoPx(nx) return lx1 + (clamp(nx, 0.0, 1.0) * (lx2 - lx1)) end
    local function lfoPy(ny) return ly2 - (clamp(ny, 0.0, 1.0) * (ly2 - ly1)) end

    local lfo_grid = math.max(1, math.min(16, math.floor(lfo.rate + 0.5)))
    for i = 0, lfo_grid do
      local tx = i / lfo_grid
      local vx = lfoPx(tx)
      r.ImGui_DrawList_AddLine(dl, vx, ly1, vx, ly2, COL_GRID, 1)
    end

    local line_col = lfo.enabled and 0x35D7AFFF or 0x777777FF
    local prev_x, prev_y = nil, nil
    local steps = 600
    for i = 0, steps do
      local t_norm = i / steps
      local y_norm = evaluateIndependentLFOAt(t_norm)
      local sx = lfoPx(t_norm)
      local sy = lfoPy(y_norm)
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, sx, sy, line_col, 2.0)
      end
      prev_x = sx
      prev_y = sy
    end

    -- LFO Controls
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_PushID(ctx, 'ind_lfo_controls')

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Enable')
    r.ImGui_SameLine(ctx, 0, 4)
    local c_en, v_en = r.ImGui_Checkbox(ctx, '##ind_lfo_enable', lfo.enabled)
    if c_en then
      lfo.enabled = v_en; markDirty()
    end

    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT)
    if r.ImGui_Button(ctx, 'Link##ind_lfo_link', 50, 0) then
      interaction.modulator_param_setup_open = 'lfo'
    end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_Spacing(ctx)

    local lfo = getIndependentLFO()

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local current_mode = math.floor(tonumber(lfo.mode) or 0)
    local c_mode_lfo, v_mode_lfo = r.ImGui_Combo(ctx, '##mode_ind_lfo', current_mode,
      'Individual (Bypass MSEG)\0Add\0Multiply\0Subtract\0Min\0Max\0Power\0')
    if c_mode_lfo then
      lfo.mode = math.max(0, math.min(6, math.floor(tonumber(v_mode_lfo) or 0)))
      markDirty()
    end

    r.ImGui_Spacing(ctx)

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Shape')
    r.ImGui_SameLine(ctx, 0, 7)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c_shape_lfo, v_shape_lfo = r.ImGui_Combo(ctx, '##shape_ind_lfo', lfo.shape or 0,
      'Sine\0Triangle\0Saw Up\0Saw Down\0Square\0Randomize\0')
    if c_shape_lfo then
      lfo.shape = math.max(0, math.min(5, math.floor(tonumber(v_shape_lfo) or 0)))
      markDirty()
    end

    -- Persistent double-click reset state
    if not lfo._dbl_reset then lfo._dbl_reset = {} end
    local dbl = lfo._dbl_reset
    if not r.ImGui_IsMouseDown(ctx, 0) then
      for k in pairs(dbl) do dbl[k] = nil end
    end

    r.ImGui_Spacing(ctx)

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Rate')
    r.ImGui_SameLine(ctx, 0, 16)
    if lfo.sync_to_bpm then
      local sync_divisions = { 2, 4, 8, 16, 32, 64 }
      local idx_now = math.max(1, math.min(#sync_divisions, math.floor(tonumber(lfo.sync_div_idx) or 2)))
      r.ImGui_SetNextItemWidth(ctx, 84)
      local c_sync_idx, v_sync_idx = r.ImGui_SliderInt(ctx, '##rate_sync_div_idx_ind_lfo', idx_now, 1, #
        sync_divisions)
      if c_sync_idx then
        lfo.sync_div_idx = math.max(1, math.min(#sync_divisions, math.floor(tonumber(v_sync_idx) or idx_now)))
        markDirty()
      end
    else
      r.ImGui_SetNextItemWidth(ctx, 84)
      local c_rate, v_rate = r.ImGui_SliderDouble(ctx, '##rate_ind_lfo', lfo.rate or 2.0, 0.05, 128.0,
        '%.2f cyc')
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        dbl.rate = 2.0
      end
      if dbl.rate then
        lfo.rate = dbl.rate; markDirty()
      elseif c_rate then
        lfo.rate = clamp(tonumber(v_rate) or 2.0, 0.05, 256.0)
        markDirty()
      end
    end

    r.ImGui_SameLine(ctx, 0, 8)
    local sync_was_on = lfo.sync_to_bpm
    if sync_was_on then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    end
    if r.ImGui_Button(ctx, 'Sync##ind_lfo_sync_bpm') then
      lfo.sync_to_bpm = not lfo.sync_to_bpm
      markDirty()
    end
    if sync_was_on then
      r.ImGui_PopStyleColor(ctx)
    end

    r.ImGui_Spacing(ctx)

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Depth')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c_depth, v_depth = r.ImGui_SliderDouble(ctx, '##depth_ind_lfo', lfo.depth or 0.6, 0.0, 1.0, '%.2f')
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      dbl.depth = 0.6
    end
    if dbl.depth then
      lfo.depth = dbl.depth; markDirty()
    elseif c_depth then
      lfo.depth = clamp(tonumber(v_depth) or 0.6, 0.0, 1.0)
      markDirty()
    end

    r.ImGui_Spacing(ctx)

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Offset')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c_offset, v_offset = r.ImGui_SliderDouble(ctx, '##offset_ind_lfo', lfo.offset or 0.5, 0.0, 1.0,
      '%.2f')
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      dbl.offset = 0.5
    end
    if dbl.offset then
      lfo.offset = dbl.offset; markDirty()
    elseif c_offset then
      lfo.offset = clamp(tonumber(v_offset) or 0.5, 0.0, 1.0)
      markDirty()
    end

    r.ImGui_Spacing(ctx)

    -- Setup Button for Advanced LFO features
    local lfo_norm = evaluateIndependentLFOAt(0.5)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, 0xA0A0A0FF, string.format('LFO %.2f', lfo_norm))
    r.ImGui_SameLine(ctx)
    local btn_x = r.ImGui_GetCursorPosX(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx, btn_x + avail_w - 50)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
    if r.ImGui_Button(ctx, 'Setup##ind_lfo_adv_setup', 50, 0) then
      r.ImGui_OpenPopup(ctx, 'ind_lfo_adv_setup_popup')
    end
    r.ImGui_PopStyleColor(ctx)

    local lfo = getIndependentLFO()

    if r.ImGui_BeginPopup(ctx, 'ind_lfo_adv_setup_popup') then
      r.ImGui_Text(ctx, 'LFO Advanced')
      r.ImGui_Separator(ctx)

      -- --- Math / Cross-Modulation ---
      r.ImGui_TextColored(ctx, COL_ORANGE, 'Cross-Modulation (Math)')

      if r.ImGui_BeginTable(ctx, 'ind_lfo_setup_table', 2, r.ImGui_TableFlags_SizingFixedFit()) then
        r.ImGui_TableSetupColumn(ctx, 'label_col', r.ImGui_TableColumnFlags_WidthFixed(), 165)
        r.ImGui_TableSetupColumn(ctx, 'slider_col', r.ImGui_TableColumnFlags_WidthFixed(), 110)

        -- FM: MSEG -> LFO Rate
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_AlignTextToFramePadding(ctx)
        local txt_fm = 'MSEG -> LFO Rate (FM)'
        local tw_fm = r.ImGui_CalcTextSize(ctx, txt_fm)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_fm - 4)
        r.ImGui_Text(ctx, txt_fm)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c_fm, v_fm = r.ImGui_SliderDouble(ctx, '##ind_mseg_to_lfo_rate', lfo.mseg_to_lfo_rate or 0.0, -2.0, 2.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.mseg_to_lfo_rate = 0.0
        end
        if dbl.mseg_to_lfo_rate then
          lfo.mseg_to_lfo_rate = dbl.mseg_to_lfo_rate; markDirty()
        elseif c_fm then
          lfo.mseg_to_lfo_rate = v_fm; markDirty()
        end

        -- AM: MSEG -> LFO Depth
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_AlignTextToFramePadding(ctx)
        local txt_am = 'MSEG -> LFO Depth (AM)'
        local tw_am = r.ImGui_CalcTextSize(ctx, txt_am)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_am - 4)
        r.ImGui_Text(ctx, txt_am)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c_am, v_am = r.ImGui_SliderDouble(ctx, '##ind_mseg_to_lfo_depth', lfo.mseg_to_lfo_depth or 0.0, -1.0, 1.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.mseg_to_lfo_depth = 0.0
        end
        if dbl.mseg_to_lfo_depth then
          lfo.mseg_to_lfo_depth = dbl.mseg_to_lfo_depth; markDirty()
        elseif c_am then
          lfo.mseg_to_lfo_depth = v_am; markDirty()
        end

        -- LFO -> MSEG Depth
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_AlignTextToFramePadding(ctx)
        local txt_l2m = 'LFO -> MSEG Depth'
        local tw_l2m = r.ImGui_CalcTextSize(ctx, txt_l2m)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_l2m - 4)
        r.ImGui_Text(ctx, txt_l2m)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c_l2m, v_l2m = r.ImGui_SliderDouble(ctx, '##ind_lfo_to_mseg_depth', lfo.lfo_to_mseg_depth or 0.0, -1.0, 1.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.lfo_to_mseg_depth = 0.0
        end
        if dbl.lfo_to_mseg_depth then
          lfo.lfo_to_mseg_depth = dbl.lfo_to_mseg_depth; markDirty()
        elseif c_l2m then
          lfo.lfo_to_mseg_depth = v_l2m; markDirty()
        end

        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_Spacing(ctx)

        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextColored(ctx, COL_ORANGE, 'Advanced Parameters')
        r.ImGui_TableNextColumn(ctx)
        -- empty

        -- Random Steps
        if (lfo.shape or 0) == 5 then
          r.ImGui_TableNextRow(ctx)
          r.ImGui_TableNextColumn(ctx)
          r.ImGui_AlignTextToFramePadding(ctx)
          local txt_st = 'Steps Rnd'
          local tw_st = r.ImGui_CalcTextSize(ctx, txt_st)
          r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_st - 4)
          r.ImGui_Text(ctx, txt_st)
          r.ImGui_TableNextColumn(ctx)
          r.ImGui_SetNextItemWidth(ctx, -1)
          local c_steps, v_steps = r.ImGui_SliderInt(ctx, '##steps_ind_lfo_popup', lfo.random_steps or 8, 2, 32)
          if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            dbl.random_steps_p = 8
          end
          if dbl.random_steps_p then
            lfo.random_steps = dbl.random_steps_p; markDirty()
          elseif c_steps then
            lfo.random_steps = v_steps
            markDirty()
          end
        end

        -- Rate Sweep
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_AlignTextToFramePadding(ctx)
        local txt_sw = 'R-Sweep'
        local tw_sw = r.ImGui_CalcTextSize(ctx, txt_sw)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_sw - 4)
        r.ImGui_Text(ctx, txt_sw)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c_sweep, v_sweep = r.ImGui_SliderDouble(ctx, '##sweep_ind_lfo', lfo.rate_sweep or 0.0, -1.0, 1.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.rate_sweep_p = 0.0
        end
        if dbl.rate_sweep_p then
          lfo.rate_sweep = dbl.rate_sweep_p; markDirty()
        elseif c_sweep then
          lfo.rate_sweep = clamp(tonumber(v_sweep) or 0.0, -1.0, 1.0)
          markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Rate sweep: changes rate symmetrically over time")
        end

        -- Depth Ramp
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_AlignTextToFramePadding(ctx)
        local txt_dr = 'Depth Ramp'
        local tw_dr = r.ImGui_CalcTextSize(ctx, txt_dr)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_dr - 4)
        r.ImGui_Text(ctx, txt_dr)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c_dramp, v_dramp = r.ImGui_SliderDouble(ctx, '##dramp_ind_lfo', lfo.depth_ramp or 0.0, -1.0, 1.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.depth_ramp_p = 0.0
        end
        if dbl.depth_ramp_p then
          lfo.depth_ramp = dbl.depth_ramp_p; markDirty()
        elseif c_dramp then
          lfo.depth_ramp = clamp(tonumber(v_dramp) or 0.0, -1.0, 1.0)
          markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Depth ramp: fade in / fade out dynamic depth")
        end

        r.ImGui_EndTable(ctx)
      end

      -- Invert
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Invert')
      r.ImGui_SameLine(ctx, 0, 4)
      local c_inv, v_inv = r.ImGui_Checkbox(ctx, '##invert_ind_lfo', lfo.invert or false)
      if c_inv then
        lfo.invert = v_inv
        markDirty()
      end

      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_PopID(ctx)
    r.ImGui_EndTable(ctx)
  end

  -- MSEG BLOCK
  r.ImGui_TextColored(ctx, header_col, 'MSEG')

  if r.ImGui_BeginTable(ctx, 'master_mseg_row', 2) then
    r.ImGui_TableSetupColumn(ctx, 'mseg_graph_col', r.ImGui_TableColumnFlags_WidthFixed(), graph_w)
    r.ImGui_TableSetupColumn(ctx, 'mseg_ctrl_col')

    -- MSEG Graph
    r.ImGui_TableNextColumn(ctx)
    local CAHP = 8
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) - CAHP)
    r.ImGui_InvisibleButton(ctx, '##master_mseg_canvas', graph_w + CAHP * 2, mseg_h)
    local mx1, my1 = r.ImGui_GetItemRectMin(ctx)
    local mx2, my2 = r.ImGui_GetItemRectMax(ctx)
    local actual_mx1, actual_mx2 = mx1 + CAHP, mx2 - CAHP

    r.ImGui_DrawList_AddRectFilled(dl, actual_mx1, my1, actual_mx2, my2, COL_PANEL, 4)
    r.ImGui_DrawList_AddRect(dl, actual_mx1, my1, actual_mx2, my2, 0x3A3A3AFF, 4)

    local function px(nx) return actual_mx1 + (clamp(nx, 0.0, 1.0) * (actual_mx2 - actual_mx1)) end
    local function py(ny) return my2 - (clamp(ny, 0.0, 1.0) * (my2 - my1)) end

    -- Grid
    for i = 1, #positions do
      local vx = px(positions[i])
      r.ImGui_DrawList_AddLine(dl, vx, my1, vx, my2, COL_GRID, 1)
    end
    for i = 0, 4 do
      local hy = my1 + ((my2 - my1) * i / 4)
      r.ImGui_DrawList_AddLine(dl, actual_mx1, hy, actual_mx2, hy, COL_GRID, 1)
    end

    -- Segments
    for i = 1, #positions - 1 do
      local x_a = positions[i]
      local x_b = positions[i + 1]
      local y_a = mseg.values[i] or 0.8
      local y_b = mseg.values[i + 1] or y_a
      local shape = math.floor(tonumber(mseg.segment_shapes[i]) or 0)
      local is_sel = (i == (mseg.selected_segment or 1))
      local seg_col = is_sel and 0x22DDB5FF or COL_ACCENT
      local seg_w = is_sel and 2.5 or 1.5
      local prev_x = px(x_a)
      local prev_y = py(y_a)
      for s = 1, 14 do
        local t = s / 14
        local st = t
        if shape == 1 then
          st = t * t
        elseif shape == 2 then
          st = 1.0 - ((1.0 - t) * (1.0 - t))
        elseif shape == 3 then
          st = t * t * (3.0 - (2.0 * t))
        elseif shape == 4 then
          local t_val = mseg.segment_tensions and mseg.segment_tensions[i] or mseg.curve_tension or 0.0
          local tension = clamp(tonumber(t_val), -1.0, 1.0)
          local cp1 = (tension < 0) and -tension or 0.0
          local cp2 = (tension > 0) and (1.0 - tension) or 1.0
          local inv_t = 1.0 - t
          st = (3 * inv_t * inv_t * t * cp1) +
              (3 * inv_t * t * t * cp2) +
              (t * t * t)
        elseif shape == 5 then
          -- Square
          st = t < 0.5 and 0.0 or 1.0
        end
        local nx = x_a + ((x_b - x_a) * t)
        local ny = y_a + ((y_b - y_a) * st)
        local sx = px(nx)
        local sy = py(ny)
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, sx, sy, seg_col, seg_w)
        prev_x = sx
        prev_y = sy
      end
    end

    -- Points
    local is_clicked = r.ImGui_IsItemClicked(ctx)
    local is_active = r.ImGui_IsItemActive(ctx)

    for i = 1, #positions do
      local cx_p = px(positions[i])
      local cy_p = py(mseg.values[i] or 0.8)

      if i == 1 then
        -- Start point: grey circle outline
        r.ImGui_DrawList_AddCircle(dl, cx_p, cy_p, 4, 0x808080FF, 0, 1.5)
      elseif i == #positions then
        -- End point: arrow tip
        local prev_px = px(positions[i - 1])
        local prev_py = py(mseg.values[i - 1] or 0.8)
        local arrow_size = 6
        local adx = cx_p - prev_px
        local ady = cy_p - prev_py
        local alen = math.sqrt(adx * adx + ady * ady)
        if alen > 0.001 then
          adx = adx / alen
          ady = ady / alen
          local perp_x = -ady
          local perp_y = adx
          local base_x = cx_p - adx * arrow_size
          local base_y = cy_p - ady * arrow_size
          local wing = arrow_size * 0.5
          r.ImGui_DrawList_AddTriangleFilled(dl,
            cx_p, cy_p,
            base_x - perp_x * wing, base_y - perp_y * wing,
            base_x + perp_x * wing, base_y + perp_y * wing,
            COL_ACCENT)
        end
      else
        -- Middle points: accent circle with white outline
        r.ImGui_DrawList_AddCircleFilled(dl, cx_p, cy_p, 4, COL_ACCENT)
        r.ImGui_DrawList_AddCircle(dl, cx_p, cy_p, 4, 0xFFFFFFFF, 0, 1.5)
      end
    end

    if is_clicked then
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local best_idx = nil
      local best_dist = 16.0
      for i = 1, #positions do
        local cx_p = px(positions[i])
        local cy_p = py(mseg.values[i] or 0.8)
        local dx = mouse_x - cx_p
        local dy = mouse_y - cy_p
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < best_dist then
          best_dist = dist
          best_idx = i
        end
      end
      if best_idx then
        interaction.active_pad = 'ind_mseg'
        interaction.active_point = best_idx
        mseg.selected_segment = (best_idx > 1) and (best_idx - 1) or 1
      end
    end

    if is_active and interaction.active_pad == 'ind_mseg' and interaction.active_point then
      local idx = interaction.active_point
      if idx >= 1 and idx <= #positions then
        local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
        if idx > 1 and idx < #positions and (mseg.mode or 0) == 0 then
          local nx = clamp((mouse_x - actual_mx1) / math.max(1.0, (actual_mx2 - actual_mx1)),
            (positions[idx - 1] or 0.0) + 0.01, (positions[idx + 1] or 1.0) - 0.01)
          if math.abs((positions[idx] or 0.0) - nx) > 0.0001 then
            positions[idx] = nx
            markDirty()
          end
        end
        local ny = clamp(1.0 - ((mouse_y - my1) / math.max(1.0, (my2 - my1))), 0.0, 1.0)
        if math.abs((mseg.values[idx] or 0.0) - ny) > 0.0001 then
          mseg.values[idx] = ny
          markDirty()
        end
      end
    end

    if not r.ImGui_IsMouseDown(ctx, 0) then
      interaction.active_pad = nil
      interaction.active_point = nil
    end

    -- MSEG Controls
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_PushID(ctx, 'master_mseg_controls')

    local seg_idx = mseg.selected_segment or 1

    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c_mseg_mode, v_mseg_mode = r.ImGui_Combo(ctx, '##mseg_mode', mseg.mode or 0, 'Manual\0Musical\0')
    if c_mseg_mode then
      mseg.mode = math.floor(tonumber(v_mseg_mode) or 0)
      -- Clear manual_positions to force recalculation
      mseg.manual_positions = {}
      markDirty()
    end


    r.ImGui_Spacing(ctx)

    if (mseg.mode or 0) == 0 then
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Points')
      r.ImGui_SameLine(ctx)
      local link_w = 46
      r.ImGui_SetNextItemWidth(ctx, r.ImGui_GetContentRegionAvail(ctx) - link_w - 4)
      local c_pts, v_pts = r.ImGui_SliderInt(ctx, '##mseg_pts', mseg.points or 2, 2, 8, '%d')
      if c_pts then
        mseg.points = math.floor(tonumber(v_pts) or 2)
        -- Clear manual_positions to force recalculation
        mseg.manual_positions = {}
        markDirty()
      end
      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT)
      if r.ImGui_Button(ctx, 'Link##ind_mseg_param_setup', link_w, 0) then
        interaction.modulator_param_setup_open = 'mseg'
      end
      r.ImGui_PopStyleColor(ctx, 3)
    else
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Div')
      r.ImGui_SameLine(ctx)

      local link_w = 46
      r.ImGui_SetNextItemWidth(ctx, r.ImGui_GetContentRegionAvail(ctx) - link_w - 4)
      local c_div, v_div = r.ImGui_SliderInt(ctx, '##mseg_div', mseg.division or 2, 2, 8, '%d Segs')
      if c_div then
        mseg.division = math.floor(tonumber(v_div) or 2)
        -- Clear manual_positions to force recalculation
        mseg.manual_positions = {}
        markDirty()
      end

      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT)
      if r.ImGui_Button(ctx, 'Link##ind_mseg_param_setup', link_w, 0) then
        interaction.modulator_param_setup_open = 'mseg'
      end
      r.ImGui_PopStyleColor(ctx, 3)
    end

    r.ImGui_Spacing(ctx)

    local all_on = (mseg.apply_all_shapes == true)
    local c_all, v_all = r.ImGui_Checkbox(ctx, 'All##ind_mseg_all', all_on)
    if c_all then
      mseg.apply_all_shapes = v_all
      if mseg.apply_all_shapes then
        local base_shape = math.floor(tonumber(mseg.segment_shapes[seg_idx]) or 0)
        local base_ten = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
        for i = 1, math.max(1, #positions - 1) do
          mseg.segment_shapes[i] = base_shape
          mseg.segment_tensions = mseg.segment_tensions or {}
          mseg.segment_tensions[i] = base_ten
        end
        mseg.curve_tension = base_ten
      end
      markDirty()
    end

    r.ImGui_SameLine(ctx, 0, 8)
    if not mseg.segment_shapes then mseg.segment_shapes = { 0 } end
    local shape_cur = math.floor(tonumber(mseg.segment_shapes[seg_idx]) or 0)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local c_shape, v_shape = r.ImGui_Combo(ctx, '##mseg_shape', shape_cur,
      'Linear\0Ease In\0Ease Out\0S-Curve\0Bezier\0Square\0')
    if c_shape then
      local next_shape = math.floor(tonumber(v_shape) or 0)
      if mseg.apply_all_shapes then
        for i = 1, math.max(1, #positions - 1) do
          mseg.segment_shapes[i] = next_shape
        end
      else
        mseg.segment_shapes[seg_idx] = next_shape
      end
      markDirty()
    end

    if shape_cur == 4 then
      r.ImGui_Spacing(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Tension')
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local cur_ten = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
      local c_ten, v_ten = r.ImGui_SliderDouble(ctx, '##mseg_tension', cur_ten, -1.0, 1.0, '%.2f')
      -- Use mseg-level persistent reset state
      if not mseg._dbl_reset then mseg._dbl_reset = {} end
      local dbl_m = mseg._dbl_reset
      if not r.ImGui_IsMouseDown(ctx, 0) then
        for k in pairs(dbl_m) do dbl_m[k] = nil end
      end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        dbl_m.tension = true
      end
      if dbl_m.tension then
        if mseg.apply_all_shapes then
          mseg.curve_tension = 0.0
          mseg.segment_tensions = mseg.segment_tensions or {}
          for i = 1, math.max(1, #positions - 1) do
            mseg.segment_tensions[i] = 0.0
          end
        else
          mseg.segment_tensions = mseg.segment_tensions or {}
          mseg.segment_tensions[seg_idx] = 0.0
        end
        markDirty()
      elseif c_ten then
        local new_ten = clamp(tonumber(v_ten) or 0.0, -1.0, 1.0)
        if mseg.apply_all_shapes then
          mseg.curve_tension = new_ten
          mseg.segment_tensions = mseg.segment_tensions or {}
          for i = 1, math.max(1, #positions - 1) do
            mseg.segment_tensions[i] = new_ten
          end
        else
          mseg.segment_tensions = mseg.segment_tensions or {}
          mseg.segment_tensions[seg_idx] = new_ten
        end
        markDirty()
      end
    end
    r.ImGui_PopID(ctx)
    r.ImGui_EndTable(ctx)
  end
end

-- Draw parameter setup popup for independent modulator
function IndependentModulatorUI.DrawParamSetup(ctx, mod_type, param_cfg, track, fx_list, markDirty, interaction)
  if not param_cfg or not track or not fx_list then return end

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 17, 10)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

  local child_w, child_h = 310, 280
  local child_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() |
      r.ImGui_WindowFlags_NoSavedSettings()
  r.ImGui_BeginChild(ctx, 'mod_param_child_' .. mod_type, child_w, child_h, child_flags)

  r.ImGui_SetCursorPosY(ctx, 15)
  r.ImGui_Indent(ctx, 10)

  r.ImGui_TextColored(ctx, COL_ACCENT, mod_type == 'lfo' and 'LFO Parameter' or 'MSEG Parameter')

  r.ImGui_SameLine(ctx, 0, 10)
  local c_on, v_on = r.ImGui_Checkbox(ctx, 'Enable##mod_param_en_' .. mod_type, param_cfg.enabled ~= false)
  if c_on then
    param_cfg.enabled = v_on
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 2)

  -- FX Selector
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
  if r.ImGui_BeginCombo(ctx, '##mod_fx_' .. mod_type, fx_label) then
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
  if r.ImGui_Button(ctx, 'Pick##mod_pick_' .. mod_type, 50, 0) then
    local has_touched, tr_idx, item_idx, take_idx, fx_idx, param_idx = r.GetTouchedOrFocusedFX(0)
    if has_touched and item_idx == -1 then
      local actual_fx_idx = fx_idx & 0xFFFFFF
      local touched_track
      if tr_idx == -1 then
        touched_track = reaper.GetMasterTrack(0)
      else
        touched_track = reaper.GetTrack(0, tr_idx)
      end
      if touched_track == track then
        local _, fx_name = r.TrackFX_GetFXName(track, actual_fx_idx)
        for i, fx in ipairs(fx_list) do
          if fx.name == fx_name then
            param_cfg.fx_guid = fx.guid or ''
            param_cfg.fx_name = fx.name or ''
            local params = {}
            local cnt = r.TrackFX_GetNumParams(track, actual_fx_idx)
            for j = 0, cnt - 1 do
              local _, p_name = r.TrackFX_GetParamName(track, actual_fx_idx, j)
              params[#params + 1] = { index = j, name = p_name }
            end
            if params and #params > param_idx and params[param_idx + 1] then
              param_cfg.param_index = params[param_idx + 1].index
              param_cfg.param_name = params[param_idx + 1].name or ''
              param_cfg.enabled = true
            end
            markDirty()
            break
          end
        end
      end
    end
  end

  -- Parameter Selector
  local params = {}
  if fx_sel > 0 and fx_list[fx_sel] then
    local cnt = r.TrackFX_GetNumParams(track, fx_list[fx_sel].index)
    for i = 0, cnt - 1 do
      local _, p_name = r.TrackFX_GetParamName(track, fx_list[fx_sel].index, i)
      params[#params + 1] = { index = i, name = p_name }
    end
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
  if r.ImGui_BeginCombo(ctx, '##mod_param_' .. mod_type, param_label) then
    for i, p in ipairs(filtered) do
      local is_sel = (param_cfg.param_index == p.index)
      if r.ImGui_Selectable(ctx, p.name .. '##mod_param_' .. mod_type .. '_' .. p.index, is_sel) then
        param_cfg.param_index = p.index
        param_cfg.param_name = p.name or ''
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 51)
  local c_search, v_search = r.ImGui_InputTextWithHint(ctx, '##mod_search_' .. mod_type, 'F...', search)
  if c_search then
    param_cfg.search = v_search
  end

  r.ImGui_Dummy(ctx, 0, 1)

  -- Min/Max
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Min:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 90)
  local c_min, v_min = r.ImGui_InputDouble(ctx, '##mod_min_' .. mod_type, math.floor(tonumber(param_cfg.min) or 0), 0.01,
    10.0, "%.2f")
  if c_min then
    param_cfg.min = v_min
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Max:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 90)
  local c_max, v_max = r.ImGui_InputDouble(ctx, '##mod_max_' .. mod_type, math.floor(tonumber(param_cfg.max) or 1), 0.01,
    10.0, "%.2f")
  if c_max then
    param_cfg.max = v_max
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 1)

  -- Curve
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
  local c_curve, v_curve = r.ImGui_Combo(ctx, '##mod_curve_' .. mod_type, curve_idx, curve_items)
  if c_curve then
    local curves = { 'linear', 'smooth', 'exponential', 'logarithmic' }
    param_cfg.curve = curves[v_curve + 1] or 'linear'
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 10)
  local c_bipolar, v_bipolar = r.ImGui_Checkbox(ctx, 'Bipolar##mod_bipolar_' .. mod_type, param_cfg.bipolar == true)
  if c_bipolar then
    param_cfg.bipolar = v_bipolar
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 3)

  -- Scale/Offset
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Scale:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_scale, v_scale = r.ImGui_InputDouble(ctx, '##mod_scale_' .. mod_type, param_cfg.scale or 1.0, 0.1, 0.5, '%.2f')
  if c_scale then
    param_cfg.scale = v_scale
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_Text(ctx, 'Offset:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local c_offset, v_offset = r.ImGui_InputDouble(ctx, '##mod_offset_' .. mod_type, param_cfg.offset or 0.0, 0.01, 0.1,
    '%.2f')
  if c_offset then
    param_cfg.offset = v_offset
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 1)

  -- Invert + Clear
  local c_inv, v_inv = r.ImGui_Checkbox(ctx, 'Invert##mod_inv_' .. mod_type, param_cfg.invert == true)
  if c_inv then
    param_cfg.invert = v_inv
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  if r.ImGui_Button(ctx, 'Clear##mod_clear_' .. mod_type, 50, 0) then
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

  r.ImGui_Dummy(ctx, 0, 4)

  -- Auto min/max
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1a5c3aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x28794dFF)
  if r.ImGui_Button(ctx, 'Auto min/max##mod_auto_' .. mod_type, 110, 0) then
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

return IndependentModulatorUI
