---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local LinkModuleUI = {}

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

-- Ensure link binding structure exists
function LinkModuleUI.EnsureLinkBinding(pad)
  if not pad then return nil end

  if type(pad.link) ~= 'table' then
    pad.link = {}
  end

  if type(pad.link.sources) ~= 'table' then
    pad.link.sources = {}
  end

  local default_axis_map = { 'x', 'y', 'x', 'y' }

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
        axis = default_axis_map[i] or 'x'
      }
    else
      local s = pad.link.sources[i]
      if s.enabled == nil then s.enabled = true end
      if s.curve == nil then s.curve = 'linear' end
      if s.bipolar == nil then s.bipolar = false end
      if s.scale == nil then s.scale = 1.0 end
      if s.offset == nil then s.offset = 0.0 end
      if s.axis == nil then s.axis = default_axis_map[i] or 'x' end
    end
  end

  return pad.link
end

-- Draw single parameter binding block
function LinkModuleUI.DrawParamBlock(ctx, idx, corner_name, link_cfg, track, fx_list, markDirty)
  local src = link_cfg.sources[idx]
  if not src then return end

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_PANEL)

  local child_w, child_h = 260, 290
  local child_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  r.ImGui_BeginChild(ctx, 'link_src_' .. idx, child_w, child_h, child_flags)

  r.ImGui_TextColored(ctx, COL_ACCENT, corner_name)
  r.ImGui_Dummy(ctx, 0, 4)

  -- Enable checkbox
  local c_en, v_en = r.ImGui_Checkbox(ctx, 'Enable##link_en_' .. idx, src.enabled ~= false)
  if c_en then
    src.enabled = v_en
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 4)

  -- Axis selector
  r.ImGui_Text(ctx, 'Axis:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local axis_idx = (src.axis == 'y') and 1 or 0
  local c_axis, v_axis = r.ImGui_Combo(ctx, '##axis_' .. idx, axis_idx, 'X\0Y\0')
  if c_axis then
    src.axis = (v_axis == 1) and 'y' or 'x'
    markDirty()
  end

  r.ImGui_Dummy(ctx, 0, 2)

  -- FX Selector
  local fx_sel = 0
  if src.fx_guid ~= '' then
    for i, fx in ipairs(fx_list) do
      if fx.guid == src.fx_guid then
        fx_sel = i
        break
      end
    end
  elseif src.fx_name ~= '' then
    for i, fx in ipairs(fx_list) do
      if fx.name == src.fx_name then
        fx_sel = i
        break
      end
    end
  end

  local fx_label = (fx_sel > 0 and fx_list[fx_sel] and fx_list[fx_sel].name) or 'Select FX'
  r.ImGui_Text(ctx, 'FX:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 170)
  if r.ImGui_BeginCombo(ctx, '##link_fx_' .. idx, fx_label) then
    for i, fx in ipairs(fx_list) do
      if r.ImGui_Selectable(ctx, fx.name, i == fx_sel) then
        src.fx_guid = fx.guid or ''
        src.fx_name = fx.name or ''
        src.param_index = 0
        src.param_name = ''
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  if r.ImGui_Button(ctx, 'Pick##link_pick_' .. idx, 50, 0) then
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
            src.fx_guid = fx.guid or ''
            src.fx_name = fx.name or ''
            local params = {}
            local cnt = r.TrackFX_GetNumParams(track, actual_fx_idx)
            for j = 0, cnt - 1 do
              local _, p_name = r.TrackFX_GetParamName(track, actual_fx_idx, j)
              params[#params + 1] = { index = j, name = p_name }
            end
            if params and #params > param_idx and params[param_idx + 1] then
              src.param_index = params[param_idx + 1].index
              src.param_name = params[param_idx + 1].name or ''
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
  r.ImGui_Text(ctx, 'Param:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 150)
  if r.ImGui_BeginCombo(ctx, '##link_param_' .. idx, param_label) then
    for i, p in ipairs(filtered) do
      local is_sel = (src.param_index == p.index)
      if r.ImGui_Selectable(ctx, p.name .. '##link_param_' .. idx .. '_' .. p.index, is_sel) then
        src.param_index = p.index
        src.param_name = p.name or ''
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 45)
  local c_search, v_search = r.ImGui_InputTextWithHint(ctx, '##link_search_' .. idx, 'F...', search)
  if c_search then
    src.search = v_search
  end

  r.ImGui_Dummy(ctx, 0, 2)

  -- Min/Max
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2a2a2aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
  r.ImGui_Text(ctx, 'Min:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 70)
  local c_min, v_min = r.ImGui_InputDouble(ctx, '##link_min_' .. idx, src.min or 0.0, 0.01, 0.1, '%.3f')
  if c_min then
    src.min = clamp(v_min, 0.0, 1.0)
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_Text(ctx, 'Max:')
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 70)
  local c_max, v_max = r.ImGui_InputDouble(ctx, '##link_max_' .. idx, src.max or 1.0, 0.01, 0.1, '%.3f')
  if c_max then
    src.max = clamp(v_max, 0.0, 1.0)
    markDirty()
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_Dummy(ctx, 0, 2)

  -- Invert + Auto
  local c_inv, v_inv = r.ImGui_Checkbox(ctx, 'Invert', src.invert == true)
  if c_inv then
    src.invert = v_inv
    markDirty()
  end

  r.ImGui_SameLine(ctx, 0, 8)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1a5c3aFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x28794dFF)
  if r.ImGui_Button(ctx, 'Auto##link_auto_' .. idx, 60, 0) then
    if fx_sel > 0 and fx_list[fx_sel] and src.param_index ~= nil then
      local fx_i = fx_list[fx_sel].index
      local _, p_min, p_max = r.TrackFX_GetParamEx(track, fx_i, src.param_index)
      if p_min ~= nil and p_max ~= nil and p_max > p_min then
        src.min = p_min
        src.max = p_max
        markDirty()
      end
    end
  end
  r.ImGui_PopStyleColor(ctx, 2)

  r.ImGui_EndChild(ctx)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopStyleVar(ctx, 3)
end

-- Draw full Link Pad Setup popup content
function LinkModuleUI.DrawSetupPopup(ctx, pad, title_text, track, markDirty, interaction)
  local link_cfg = LinkModuleUI.EnsureLinkBinding(pad)

  if not link_cfg then
    r.ImGui_TextDisabled(ctx, 'Pad data not available.')
    return
  end

  local fx_list = BindingRegistry and BindingRegistry.ListFX(track) or {}

  -- Validate FX exist
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

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8)

    r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 290)
    r.ImGui_TableNextColumn(ctx)
    LinkModuleUI.DrawParamBlock(ctx, 1, 'Top-Left', link_cfg, track, fx_list, markDirty)

    r.ImGui_TableNextColumn(ctx)
    LinkModuleUI.DrawParamBlock(ctx, 2, 'Top-Right', link_cfg, track, fx_list, markDirty)

    r.ImGui_TableNextRow(ctx, r.ImGui_TableRowFlags_None(), 290)
    r.ImGui_TableNextColumn(ctx)
    LinkModuleUI.DrawParamBlock(ctx, 3, 'Bottom-Left', link_cfg, track, fx_list, markDirty)

    r.ImGui_TableNextColumn(ctx)
    LinkModuleUI.DrawParamBlock(ctx, 4, 'Bottom-Right', link_cfg, track, fx_list, markDirty)

    r.ImGui_PopStyleVar(ctx)
    r.ImGui_EndTable(ctx)
  end
end

return LinkModuleUI
