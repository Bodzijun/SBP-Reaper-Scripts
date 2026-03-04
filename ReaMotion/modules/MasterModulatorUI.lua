---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local MasterModulatorUI = {}

local r = reaper

local COL_BG = 0x171717FF
local COL_FRAME = 0x2A2A2AFF
local COL_ACCENT = 0x2D8C6DFF
local COL_ORANGE = 0xD46A3FFF
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

-- Draw compact Master LFO + MSEG module (side by side)
-- params = {
--   getMasterLFO       : function() -> lfo table
--   getMasterMSEG      : function() -> mseg table
--   getMasterMSEGPositions : function() -> positions array
--   ensureMasterMSEGData   : function()
--   evaluateLFO        : function(lfo, t) -> y_norm
--   markDirty          : function()
--   interaction        : table (active_pad, active_point, modulator_param_setup_open)
-- }
function MasterModulatorUI.DrawCompact(ctx, forced_w, params)
  params.ensureMasterMSEGData()
  local mseg = params.getMasterMSEG()
  local positions = params.getMasterMSEGPositions()
  local master_lfo = params.getMasterLFO()
  local markDirty = params.markDirty
  local interaction = params.interaction
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local avail_w = forced_w or r.ImGui_GetContentRegionAvail(ctx)
  local graph_h = 155
  local total_w = math.max(200, avail_w)
  local col_w = math.max(140, math.floor((total_w - 8) * 0.5))

  -- Master LFO + MSEG (2 columns side by side)
  if r.ImGui_BeginTable(ctx, 'compact_master_both', 2, r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, 'lfo_col', r.ImGui_TableColumnFlags_WidthFixed(), col_w)
    r.ImGui_TableSetupColumn(ctx, 'mseg_col', r.ImGui_TableColumnFlags_WidthFixed(), col_w)

    -- ===== LFO COLUMN =====
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, 'LFO')

    -- LFO Graph
    r.ImGui_InvisibleButton(ctx, '##compact_lfo_canvas', col_w - 8, graph_h)
    local lx1, ly1 = r.ImGui_GetItemRectMin(ctx)
    local lx2, ly2 = r.ImGui_GetItemRectMax(ctx)

    r.ImGui_DrawList_AddRectFilled(dl, lx1, ly1, lx2, ly2, COL_PANEL, 4)
    r.ImGui_DrawList_AddRect(dl, lx1, ly1, lx2, ly2, 0x3A3A3AFF, 4)

    local function lfoPx(nx) return lx1 + (clamp(nx, 0.0, 1.0) * (lx2 - lx1)) end
    local function lfoPy(ny) return ly2 - (clamp(ny, 0.0, 1.0) * (ly2 - ly1)) end

    -- LFO Grid
    local lfo_grid = math.max(1, math.min(32, math.floor(master_lfo.rate + 0.5)))
    for i = 0, lfo_grid do
      local tx = i / lfo_grid
      local vx = lfoPx(tx)
      r.ImGui_DrawList_AddLine(dl, vx, ly1, vx, ly2, COL_GRID, 1)
    end
    for i = 0, 4 do
      local hy = ly1 + ((ly2 - ly1) * i / 4)
      r.ImGui_DrawList_AddLine(dl, lx1, hy, lx2, hy, COL_GRID, 1)
    end

    local line_col = master_lfo.enabled and 0x35D7AFFF or 0x777777FF
    local prev_x, prev_y = nil, nil
    local steps = 600
    for i = 0, steps do
      local t_norm = i / steps
      -- Calculate modulated LFO value for visual feedback
      local mseg_val = params.evaluateMasterMSEGAt and params.evaluateMasterMSEGAt(t_norm) or 0.8
      local lfo_params = {
        enabled = true,
        rate = master_lfo.rate,
        rate_sweep = master_lfo.rate_sweep,
        depth_ramp = master_lfo.depth_ramp,
        shape = master_lfo.shape,
        invert = master_lfo.invert,
        random_steps = master_lfo.random_steps,
        depth = clamp((master_lfo.depth or 0.6) + (mseg_val * (master_lfo.mseg_to_lfo_depth or 0.0)), 0.0, 1.0),
        offset = clamp(master_lfo.offset or 0.5, 0.0, 1.0),
        phase_offset = mseg_val * (master_lfo.mseg_to_lfo_rate or 0.0)
      }
      local lfo_val = params.evaluateLFO(lfo_params, t_norm)
      local mixed_val = lfo_val

      local mseg_mod_amt = master_lfo.lfo_to_mseg_depth or 0.0
      local modulated_mseg = mseg_val
      if mseg_mod_amt ~= 0 then
        modulated_mseg = clamp(mseg_val * (1.0 + (lfo_val - 0.5) * mseg_mod_amt * 2.0), 0.0, 1.0)
      end

      local mode = math.floor(tonumber(master_lfo.mode) or 0)
      if mode == 1 then     -- Add
        mixed_val = clamp(modulated_mseg + (lfo_val - 0.5), 0.0, 1.0)
      elseif mode == 2 then -- Multiply
        mixed_val = clamp(modulated_mseg * (lfo_val * 2.0), 0.0, 1.0)
      elseif mode == 3 then -- Subtract
        mixed_val = clamp(modulated_mseg - lfo_val, 0.0, 1.0)
      elseif mode == 4 then -- Min
        mixed_val = math.min(modulated_mseg, lfo_val)
      elseif mode == 5 then -- Max
        mixed_val = math.max(modulated_mseg, lfo_val)
      elseif mode == 6 then -- Power
        mixed_val = clamp(modulated_mseg ^ (lfo_val * 4.0), 0.0, 1.0)
      else                  -- Replace (Modulator Only)
        mixed_val = lfo_val
      end

      local sx = lfoPx(t_norm)
      local sy = lfoPy(mixed_val)
      if prev_x then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, sx, sy, line_col, 2.0)
      end
      prev_x = sx
      prev_y = sy
    end

    -- LFO Controls
    r.ImGui_PushID(ctx, 'lfo_controls')

    -- Row 1: Enable, Shape, Depth, Offset(fill)
    local lfo_row_w = col_w - 8
    local gap = 4
    local lfo_w_toggle = 20
    local lfo_w_shape = math.floor(lfo_row_w * 0.22)
    local lfo_w_depth = math.floor(lfo_row_w * 0.26)
    local lfo_w_rate = math.floor(lfo_row_w * 0.30)
    local lfo_w_sync = 45

    -- Persistent double-click reset state (survives across frames)
    if not master_lfo._dbl_reset then master_lfo._dbl_reset = {} end
    local dbl = master_lfo._dbl_reset
    -- Clear any held resets when mouse released
    if not r.ImGui_IsMouseDown(ctx, 0) then
      for k in pairs(dbl) do dbl[k] = nil end
    end

    r.ImGui_SetNextItemWidth(ctx, lfo_w_toggle)
    local c_en, v_en = r.ImGui_Checkbox(ctx, '##lfo_en', master_lfo.enabled)
    if c_en then
      master_lfo.enabled = v_en; markDirty()
    end

    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_SetNextItemWidth(ctx, lfo_w_shape)
    local c_shape, v_shape = r.ImGui_Combo(ctx, '##shape', master_lfo.shape or 0, 'Sin\0Tri\0SawUp\0SawDn\0Sqr\0Rnd\0')
    if c_shape then
      master_lfo.shape = math.max(0, math.min(5, math.floor(tonumber(v_shape) or 0)))
      markDirty()
    end

    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_SetNextItemWidth(ctx, lfo_w_depth)
    local c_depth, v_depth = r.ImGui_SliderDouble(ctx, '##depth', master_lfo.depth or 0.6, 0.0, 1.0, 'Depth: %.2f')
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      dbl.depth = 0.6
    end
    if dbl.depth then
      master_lfo.depth = dbl.depth; markDirty()
    elseif c_depth then
      master_lfo.depth = clamp(tonumber(v_depth) or 0.6, 0.0, 1.0)
      markDirty()
    end

    r.ImGui_SameLine(ctx, 0, gap)
    local lfo_w_offset = math.max(40, r.ImGui_GetContentRegionAvail(ctx))
    r.ImGui_SetNextItemWidth(ctx, lfo_w_offset)
    local c_offset, v_offset = r.ImGui_SliderDouble(ctx, '##offset', master_lfo.offset or 0.5, 0.0, 1.0, 'Offset: %.2f')
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      dbl.offset = 0.5
    end
    if dbl.offset then
      master_lfo.offset = dbl.offset; markDirty()
    elseif c_offset then
      master_lfo.offset = clamp(tonumber(v_offset) or 0.5, 0.0, 1.0)
      markDirty()
    end

    -- Row 2: Rate/Sync, Setup, Sync btn, Mode(fill)
    if master_lfo.sync_to_bpm then
      local sync_divisions = { 2, 4, 8, 16, 32, 64 }
      local idx_now = math.max(1, math.min(#sync_divisions, math.floor(tonumber(master_lfo.sync_div_idx) or 2)))
      r.ImGui_SetNextItemWidth(ctx, lfo_w_rate)
      local c_sync_idx, v_sync_idx = r.ImGui_SliderInt(ctx, '##rate_sync', idx_now, 1, #sync_divisions, '1/%d')
      if c_sync_idx then
        master_lfo.sync_div_idx = math.max(1, math.min(#sync_divisions, math.floor(tonumber(v_sync_idx) or idx_now)))
        markDirty()
      end
    else
      r.ImGui_SetNextItemWidth(ctx, lfo_w_rate)
      local c_rate, v_rate = r.ImGui_SliderDouble(ctx, '##rate', master_lfo.rate or 2.0, 0.05, 256.0, 'Rate: %.2f')
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        dbl.rate = 2.0
      end
      if dbl.rate then
        master_lfo.rate = dbl.rate; markDirty()
      elseif c_rate then
        master_lfo.rate = clamp(tonumber(v_rate) or 2.0, 0.05, 256.0)
        markDirty()
      end
    end

    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
    if r.ImGui_Button(ctx, 'Setup##master_lfo_adv_setup', 45, 0) then
      r.ImGui_OpenPopup(ctx, 'master_lfo_adv_setup_popup')
    end

    r.ImGui_PopStyleColor(ctx)

    if r.ImGui_BeginPopup(ctx, 'master_lfo_adv_setup_popup') then
      r.ImGui_Text(ctx, 'Master LFO Advanced')
      r.ImGui_Separator(ctx)

      -- --- Math / Cross-Modulation ---
      r.ImGui_TextColored(ctx, COL_ORANGE, 'Cross-Modulation (Math)')

      if r.ImGui_BeginTable(ctx, 'master_lfo_setup_table', 2, r.ImGui_TableFlags_SizingFixedFit()) then
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
        local c_fm, v_fm = r.ImGui_SliderDouble(ctx, '##mseg_to_lfo_rate', master_lfo.mseg_to_lfo_rate or 0.0, -2.0, 2.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.mseg_to_lfo_rate = 0.0
        end
        if dbl.mseg_to_lfo_rate then
          master_lfo.mseg_to_lfo_rate = dbl.mseg_to_lfo_rate; markDirty()
        elseif c_fm then
          master_lfo.mseg_to_lfo_rate = v_fm
          markDirty()
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
        local c_am, v_am = r.ImGui_SliderDouble(ctx, '##mseg_to_lfo_depth', master_lfo.mseg_to_lfo_depth or 0.0, -1.0,
          1.0,
          '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.mseg_to_lfo_depth = 0.0
        end
        if dbl.mseg_to_lfo_depth then
          master_lfo.mseg_to_lfo_depth = dbl.mseg_to_lfo_depth; markDirty()
        elseif c_am then
          master_lfo.mseg_to_lfo_depth = v_am
          markDirty()
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
        local c_l2m, v_l2m = r.ImGui_SliderDouble(ctx, '##lfo_to_mseg_depth', master_lfo.lfo_to_mseg_depth or 0.0, -1.0,
          1.0, '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.lfo_to_mseg_depth = 0.0
        end
        if dbl.lfo_to_mseg_depth then
          master_lfo.lfo_to_mseg_depth = dbl.lfo_to_mseg_depth; markDirty()
        elseif c_l2m then
          master_lfo.lfo_to_mseg_depth = v_l2m
          markDirty()
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
        local c_sweep2, v_sweep2 = r.ImGui_SliderDouble(ctx, '##sweep_master_lfo_popup', master_lfo.rate_sweep or 0.0,
          -1.0,
          1.0, '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.rate_sweep_p = 0.0
        end
        if dbl.rate_sweep_p then
          master_lfo.rate_sweep = dbl.rate_sweep_p; markDirty()
        elseif c_sweep2 then
          master_lfo.rate_sweep = clamp(tonumber(v_sweep2) or 0.0, -1.0, 1.0)
          markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, 'Rate sweep: changes rate symmetrically over time')
        end

        -- Random Steps
        if (master_lfo.shape or 0) == 5 then
          r.ImGui_TableNextRow(ctx)
          r.ImGui_TableNextColumn(ctx)
          r.ImGui_AlignTextToFramePadding(ctx)
          local txt_st = 'Steps Rnd'
          local tw_st = r.ImGui_CalcTextSize(ctx, txt_st)
          r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + r.ImGui_GetContentRegionAvail(ctx) - tw_st - 4)
          r.ImGui_Text(ctx, txt_st)
          r.ImGui_TableNextColumn(ctx)
          r.ImGui_SetNextItemWidth(ctx, -1)
          local c_steps, v_steps = r.ImGui_SliderInt(ctx, '##steps_master_lfo_popup', master_lfo.random_steps or 8, 2, 32)
          if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            dbl.random_steps_p = 8
          end
          if dbl.random_steps_p then
            master_lfo.random_steps = dbl.random_steps_p; markDirty()
          elseif c_steps then
            master_lfo.random_steps = v_steps
            markDirty()
          end
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
        local c_dramp, v_dramp = r.ImGui_SliderDouble(ctx, '##dramp_master_lfo_global', master_lfo.depth_ramp or 0.0,
          -1.0,
          1.0, '%.2f')
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          dbl.depth_ramp_p = 0.0
        end
        if dbl.depth_ramp_p then
          master_lfo.depth_ramp = dbl.depth_ramp_p; markDirty()
        elseif c_dramp then
          master_lfo.depth_ramp = clamp(tonumber(v_dramp) or 0.0, -1.0, 1.0)
          markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, 'Depth ramp: fade in / fade out')
        end

        r.ImGui_EndTable(ctx)
      end

      -- Invert
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Invert')
      r.ImGui_SameLine(ctx, 0, 4)
      local c_inv, v_inv = r.ImGui_Checkbox(ctx, '##invert_master_lfo_global', master_lfo.invert or false)
      if c_inv then
        master_lfo.invert = v_inv
        markDirty()
      end

      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SameLine(ctx, 0, gap)
    local sync_was_on = master_lfo.sync_to_bpm
    if sync_was_on then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    end
    if r.ImGui_Button(ctx, 'Sync##lfo_sync', lfo_w_sync) then
      master_lfo.sync_to_bpm = not master_lfo.sync_to_bpm
      markDirty()
    end
    if sync_was_on then
      r.ImGui_PopStyleColor(ctx)
    end

    r.ImGui_SameLine(ctx, 0, gap)
    local current_mode = math.max(1, math.min(6, math.floor(tonumber(master_lfo.mode) or 1)))
    local lfo_w_mode = math.max(40, r.ImGui_GetContentRegionAvail(ctx))
    r.ImGui_SetNextItemWidth(ctx, lfo_w_mode)
    local c_mode, v_mode = r.ImGui_Combo(ctx, '##lfo_mode', current_mode - 1,
      'Add\0Multiply\0Subtract\0Min\0Max\0Power\0')
    if c_mode then
      master_lfo.mode = v_mode + 1
      markDirty()
    end

    r.ImGui_PopID(ctx)

    -- ===== MSEG COLUMN =====
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, 'MSEG')

    -- MSEG Graph
    local CAHP = 8
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) - CAHP)
    r.ImGui_InvisibleButton(ctx, '##compact_mseg_canvas', (col_w - 8) + CAHP * 2, graph_h)
    local _cmx1, my1 = r.ImGui_GetItemRectMin(ctx)
    local _cmx2, my2 = r.ImGui_GetItemRectMax(ctx)
    local mx1, mx2 = _cmx1 + CAHP, _cmx2 - CAHP

    r.ImGui_DrawList_AddRectFilled(dl, mx1, my1, mx2, my2, COL_PANEL, 4)
    r.ImGui_DrawList_AddRect(dl, mx1, my1, mx2, my2, 0x3A3A3AFF, 4)

    local function px(nx) return mx1 + (clamp(nx, 0.0, 1.0) * (mx2 - mx1)) end
    local function py(ny) return my2 - (clamp(ny, 0.0, 1.0) * (my2 - my1)) end

    -- MSEG Grid
    for i = 1, #positions do
      local vx = px(positions[i])
      r.ImGui_DrawList_AddLine(dl, vx, my1, vx, my2, COL_GRID, 1)
    end
    for i = 0, 4 do
      local hy = my1 + ((my2 - my1) * i / 4)
      r.ImGui_DrawList_AddLine(dl, mx1, hy, mx2, hy, COL_GRID, 1)
    end

    for i = 1, #positions - 1 do
      local x_a     = positions[i]
      local x_b     = positions[i + 1]
      local y_a     = mseg.values[i] or 0.8
      local y_b     = mseg.values[i + 1] or y_a

      local shape   = math.floor(tonumber(mseg.segment_shapes[i]) or 0)
      local is_sel  = (i == (mseg.selected_segment or 1))
      local seg_col = is_sel and 0x22DDB5FF or COL_ACCENT
      local seg_w   = is_sel and 2.5 or 1.5
      local prev_sx = px(x_a)
      local prev_sy = py(y_a)
      for s = 1, 14 do
        local t = s / 14
        local st = t
        if shape == 1 then
          st = t * t
        elseif shape == 2 then
          local inv = 1.0 - t
          st = 1.0 - (inv * inv)
        elseif shape == 4 then
          local tension = mseg.segment_tensions and mseg.segment_tensions[i] or mseg.curve_tension or 0.0
          tension = clamp(tonumber(tension), -1.0, 1.0)
          local cp1 = (tension < 0) and -tension or 0.0
          local cp2 = (tension > 0) and (1.0 - tension) or 1.0
          local inv_t = 1.0 - t
          st = (3 * inv_t * inv_t * t * cp1) +
              (3 * inv_t * t * t * cp2) +
              (t * t * t)
        elseif shape == 5 then
          st = (t < 1.0) and 0.0 or 1.0
        end
        local nx = x_a + ((x_b - x_a) * t)
        local ny = y_a + ((y_b - y_a) * st)
        local sx = px(nx)
        local sy = py(ny)
        r.ImGui_DrawList_AddLine(dl, prev_sx, prev_sy, sx, sy, seg_col, seg_w)
        prev_sx = sx
        prev_sy = sy
      end
    end

    -- Interactive points with click detection
    local is_clicked = r.ImGui_IsItemClicked(ctx)
    local is_active = r.ImGui_IsItemActive(ctx)

    for i = 1, #positions do
      local cx_p = px(positions[i])
      local cy_p = py(mseg.values[i] or 0.8)
      local is_active_pt = (interaction.active_pad == 'compact_mseg' and interaction.active_point == i)
      local pt_r = is_active_pt and 5 or 4

      if i == 1 then
        -- Start point: grey circle (like vector pad)
        r.ImGui_DrawList_AddCircle(dl, cx_p, cy_p, pt_r, 0x808080FF, 0, 1.5)
      elseif i == #positions then
        -- End point: arrow tip (like vector pad)
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
        -- Middle points: filled accent with white outline
        r.ImGui_DrawList_AddCircleFilled(dl, cx_p, cy_p, pt_r, COL_ACCENT)
        r.ImGui_DrawList_AddCircle(dl, cx_p, cy_p, pt_r, 0xFFFFFFFF, 0, 1.5)
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
        interaction.active_pad = 'compact_mseg'
        interaction.active_point = best_idx
        mseg.selected_segment = (best_idx > 1) and (best_idx - 1) or 1
      end
    end

    if is_active and interaction.active_pad == 'compact_mseg' and interaction.active_point then
      local idx = interaction.active_point
      if idx >= 1 and idx <= #positions then
        local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)

        if idx > 1 and idx < #positions and (mseg.mode or 0) == 0 then
          local nx = clamp((mouse_x - mx1) / math.max(1.0, (mx2 - mx1)), (positions[idx - 1] or 0.0) + 0.01,
            (positions[idx + 1] or 1.0) - 0.01)
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
    r.ImGui_PushID(ctx, 'mseg_controls')

    local mseg_row_w = col_w - 8
    local mseg_w_mode = math.floor(mseg_row_w * 0.22)
    local mseg_w_all = 35
    local mseg_w_bars = math.floor(mseg_row_w * 0.30)

    -- Row 1: Mode, Shape(fill)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Mode')
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_SetNextItemWidth(ctx, mseg_w_mode)
    local c_mseg_mode, v_mseg_mode = r.ImGui_Combo(ctx, '##mseg_mode', mseg.mode or 0, 'Manual\0Musical\0')
    if c_mseg_mode then
      mseg.mode = math.floor(tonumber(v_mseg_mode) or 0)
      markDirty()
      params.ensureMasterMSEGData()
      positions = params.getMasterMSEGPositions()
    end

    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Shape')
    r.ImGui_SameLine(ctx, 0, 4)
    local seg_idx = mseg.selected_segment or 1
    local mseg_shape_fill = math.max(50, r.ImGui_GetContentRegionAvail(ctx))
    r.ImGui_SetNextItemWidth(ctx, mseg_shape_fill)
    local shape_cur = math.floor(tonumber(mseg.segment_shapes[seg_idx]) or tonumber(mseg.curve_mode) or 0)
    local c_mshape, v_mshape = r.ImGui_Combo(ctx, '##mseg_shape', shape_cur,
      'Linear\0Ease In\0Ease Out\0S-Curve\0Bezier\0Square\0')
    if c_mshape then
      local next_shape = math.floor(tonumber(v_mshape) or 0)
      mseg.segment_shapes[seg_idx] = next_shape
      if mseg.apply_all_shapes then
        for i = 1, math.max(1, #positions - 1) do
          mseg.segment_shapes[i] = next_shape
        end
      end
      markDirty()
    end

    -- Row 2: All + Pts/Bars/Div + Bezier Tension
    local show_tension = (shape_cur == 4)
    local tension_w = show_tension and 110 or 0

    -- All button (always first in Row 2)
    local all_on = (mseg.apply_all_shapes == true)
    if all_on then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
    end
    if r.ImGui_Button(ctx, 'All##mseg_all', mseg_w_all, 0) then
      mseg.apply_all_shapes = not all_on
      if mseg.apply_all_shapes then
        local base_shape = math.floor(tonumber(mseg.segment_shapes[seg_idx]) or 0)
        local base_ten = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
        mseg.curve_tension = base_ten
        for i = 1, math.max(1, #positions - 1) do
          mseg.segment_shapes[i] = base_shape
          mseg.segment_tensions = mseg.segment_tensions or {}
          mseg.segment_tensions[i] = base_ten
        end
      end
      markDirty()
    end
    if all_on then
      r.ImGui_PopStyleColor(ctx)
    end

    if (mseg.mode or 0) == 0 then
      -- Manual mode: All + Pts + [Bezier Tension]
      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Pts')
      r.ImGui_SameLine(ctx, 0, 4)
      local pts_fill = math.max(30, r.ImGui_GetContentRegionAvail(ctx) - (show_tension and (tension_w + 4) or 0))
      r.ImGui_SetNextItemWidth(ctx, pts_fill)
      local c_pts, v_pts = r.ImGui_SliderInt(ctx, '##mseg_pts', mseg.points or 2, 2, 8, '%d')
      if c_pts then
        mseg.points = math.floor(tonumber(v_pts) or 2)
        markDirty()
        params.ensureMasterMSEGData()
        positions = params.getMasterMSEGPositions()
      end

      if show_tension then
        r.ImGui_SameLine(ctx, 0, 4)
        r.ImGui_SetNextItemWidth(ctx, tension_w)
        local cur_ten = mseg.segment_tensions and mseg.segment_tensions[seg_idx] or mseg.curve_tension or 0.0
        local c_ten, v_ten = r.ImGui_SliderDouble(ctx, '##mseg_tension', cur_ten, -1.0, 1.0, 'Bezier: %.2f')
        -- Persistent reset state for MSEG tension
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
            for i = 1, math.max(1, #positions - 1) do mseg.segment_tensions[i] = 0.0 end
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
            for i = 1, math.max(1, #positions - 1) do mseg.segment_tensions[i] = new_ten end
          else
            mseg.segment_tensions = mseg.segment_tensions or {}
            mseg.segment_tensions[seg_idx] = new_ten
          end
          markDirty()
        end
      end
    else
      -- Musical mode: All + Bars + Div(fill)
      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Bars')
      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_SetNextItemWidth(ctx, mseg_w_bars)
      local c_bars, v_bars = r.ImGui_SliderInt(ctx, '##mseg_bars', mseg.bars or 4, 1, 16, '%d')
      if c_bars then
        mseg.bars = math.floor(tonumber(v_bars) or 4)
        markDirty()
        params.ensureMasterMSEGData()
        positions = params.getMasterMSEGPositions()
      end

      r.ImGui_SameLine(ctx, 0, 4)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_Text(ctx, 'Div')
      r.ImGui_SameLine(ctx, 0, 4)
      local div_fill = math.max(30, r.ImGui_GetContentRegionAvail(ctx))
      r.ImGui_SetNextItemWidth(ctx, div_fill)
      local c_div, v_div = r.ImGui_SliderInt(ctx, '##mseg_div', mseg.division or 2, 1, 8, '%d')
      if c_div then
        mseg.division = math.floor(tonumber(v_div) or 2)
        markDirty()
        params.ensureMasterMSEGData()
        positions = params.getMasterMSEGPositions()
      end
    end

    r.ImGui_PopID(ctx)

    r.ImGui_EndTable(ctx)
  end
end

return MasterModulatorUI
