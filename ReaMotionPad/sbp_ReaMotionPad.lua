-- @description SBP ReaMotion Pad
-- @author SBP & AI
-- @version 0.2.1
-- @about
--   Modulation and automation writer for external plugin parameters in time selection.
-- @provides
--   [main] .
--   modules/State.lua
--   modules/SegmentEngine.lua
--   modules/PadEngine.lua
--   modules/BindingRegistry.lua
--   modules/AutomationWriter.lua
-- @changelog
--   v0.2.1 (2026-02-20)
--   Reworked layout to exact 1+3 pad concept and added visual vector segmentation module.
--   Segmentation now drives write points for all 4 pads (musical bars or manual horizontal dots).
--   Removed volume-shaper style workflow from primary UI.
--   v0.2.0 (2026-02-20)
--   UI redesign to ReaWhoosh-style layout with vector point pads and dark custom theme.
--   v0.1.0 (2026-02-20)
--   Initial modular MVP: segment module, 3 link pads, external pad with 4 sources,
--   morph/lfo/env modulators, hybrid FX binding, overwrite automation write.

---@diagnostic disable: undefined-field

local r = reaper

local info = debug.getinfo(1, 'S')
local script_path = info.source:match('@(.*[\\/])') or ''
local shim = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
if r.file_exists(shim) then
  dofile(shim)
end

if not r.ImGui_CreateContext then
  r.ShowConsoleMsg('[ReaMotionPad] Error: ReaImGui is required.\n')
  return
end

local function loadModule(name)
  local ok, mod = pcall(dofile, script_path .. 'modules/' .. name .. '.lua')
  if not ok then
    r.ShowConsoleMsg('[ReaMotionPad] Failed to load module ' .. name .. ': ' .. tostring(mod) .. '\n')
    return nil
  end
  return mod
end

local State = loadModule('State')
local SegmentEngine = loadModule('SegmentEngine')
local PadEngine = loadModule('PadEngine')
local BindingRegistry = loadModule('BindingRegistry')
local AutomationWriter = loadModule('AutomationWriter')

if not (State and SegmentEngine and PadEngine and BindingRegistry and AutomationWriter) then
  return
end

local ctx = r.ImGui_CreateContext('SBP ReaMotion Pad')

local COL_BG = 0x171717FF
local COL_FRAME = 0x2A2A2AFF
local COL_TEXT = 0xE8E8E8FF
local COL_ACCENT = 0x2D8C6DFF
local COL_WARN = 0xC05050FF
local COL_ORANGE = 0xD46A3FFF
local COL_GRID = 0xFFFFFF20
local COL_LINE = 0x2EC8A0FF
local COL_HANDLE = 0xEAEAEAFF
local COL_PANEL = 0x111111FF

local PAD_W = 170
local PAD_H = 170
local ENV_W = 430
local ENV_H = 170
local SEG_H = 90

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

local DIV_LIST = {1, 2, 4, 8, 16}

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
  seg_active_idx = nil
}

local function clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

local function evaluatePadVector(pad, t)
  if not pad then return 0.5 end
  t = clamp(t, 0.0, 1.0)
  
  local sx = clamp(pad.sx or 0.0, 0.0, 1.0)
  local sy = clamp(pad.sy or 0.0, 0.0, 1.0)
  local px = clamp(pad.px or 0.5, 0.0, 1.0)
  local py = clamp(pad.py or 0.5, 0.0, 1.0)
  local ex = clamp(pad.ex or 1.0, 0.0, 1.0)
  local ey = clamp(pad.ey or 1.0, 0.0, 1.0)
  
  if t <= px then
    if px < 0.0001 then return sy end
    local local_t = t / px
    return sy + (py - sy) * local_t
  else
    if (1.0 - px) < 0.0001 then return py end
    local local_t = (t - px) / (1.0 - px)
    return py + (ey - py) * local_t
  end
end

local function pushTheme()
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_TEXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x454545FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x303030FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x404040FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x42B48DFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x333333FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorHovered(), 0x444444FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorActive(), 0x555555FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COL_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1D1D1DFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10.0, 10.0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 7.0, 6.0)
end

local function popTheme()
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, 22)
end

local function markDirty()
  app.dirty = true
end

local function drawHeader(label)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_ACCENT)
  r.ImGui_Text(ctx, label)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_Separator(ctx)
end

local function getTargetTrack()
  local setup = app.state.setup
  if setup.target_track_name ~= '' then
    return BindingRegistry.GetTrackByName(setup.target_track_name)
  end
  return r.GetSelectedTrack(0, 0)
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
  local s = app.state
  math.randomseed(s.setup.random_seed or os.time())

  if s.random.pad_a then randomizePad(s.pads.link_a) end
  if s.random.pad_b then randomizePad(s.pads.link_b) end
  if s.random.pad_c then randomizePad(s.pads.link_c) end
  if s.random.morph then randomizePad(s.pads.morph) end

  if s.random.lfo then
    s.lfo.lfo1.rate = math.random() * 8.0
    s.lfo.lfo1.depth = math.random()
    s.lfo.lfo2.rate = math.random() * 8.0
    s.lfo.lfo2.depth = math.random()
  end

  if s.random.env then
    s.env.env1.attack = math.random() * 0.4
    s.env.env1.decay = math.random() * 0.5
    s.env.env1.sustain = math.random()
    s.env.env1.release = math.random() * 0.5
  end

  s.setup.random_seed = (s.setup.random_seed or 1001) + 7
  app.status = 'Randomized'
  markDirty()
end

local function drawTopBar(track)
  r.ImGui_Text(ctx, 'SBP ReaMotion Pad v0.2.1')
  r.ImGui_SameLine(ctx, 300)
  if not track then
    r.ImGui_TextColored(ctx, COL_WARN, 'No track selected')
  end
end

local function drawVectorPad(title, pad, id, w, h)
  r.ImGui_Text(ctx, title)
  r.ImGui_Dummy(ctx, w, h)
  
  local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  
  r.ImGui_DrawList_AddRectFilled(dl, p_x, p_y, p_x + w, p_y + h, COL_PANEL, 4)
  r.ImGui_DrawList_AddRect(dl, p_x, p_y, p_x + w, p_y + h, 0x3A3A3AFF, 4)
  
  r.ImGui_DrawList_AddLine(dl, p_x + w*0.5, p_y, p_x + w*0.5, p_y + h, COL_GRID, 1)
  r.ImGui_DrawList_AddLine(dl, p_x, p_y + h*0.5, p_x + w, p_y + h*0.5, COL_GRID, 1)
  
  local txt_col = 0xFFFFFF60
  local function DT(tx, x, y) r.ImGui_DrawList_AddText(dl, x, y, txt_col, tx) end
  local mid_x = p_x + (w * 0.5)
  local mid_y = p_y + (h * 0.5)
  DT("Left", p_x + 3, mid_y - 8)
  DT("Right", p_x + w - 35, mid_y - 8)
  DT("Top", mid_x - 12, p_y + 3)
  DT("Bottom", mid_x - 25, p_y + h - 15)
  
  local center_x = p_x + w * 0.5
  local center_y = p_y + h * 0.5
  local max_r = math.sqrt((w*0.5)^2 + (h*0.5)^2)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.75, 0xFFFFFF15, 0, 1)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.50, 0xFFFFFF20, 0, 1)
  r.ImGui_DrawList_AddCircle(dl, center_x, center_y, max_r * 0.35, 0xFFFFFF2A, 0, 1)
  
  local hit_margin = 8
  r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
  r.ImGui_InvisibleButton(ctx, id, w + hit_margin*2, h + hit_margin*2)
  
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
      local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*h
      local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*h
      local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*h
      
      local hit_r = 1000
      interaction.active_pad = id
      local dist_s = (mx-s_sc_x)^2+(my-s_sc_y)^2
      local dist_p = (mx-p_sc_x)^2+(my-p_sc_y)^2
      local dist_e = (mx-e_sc_x)^2+(my-e_sc_y)^2
      
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
      local dnx, dny = dx/w, -dy/h
      
      if interaction.active_point == 1 then
        sx = clamp(sx+dnx, 0, 1)
        sy = clamp(sy+dny, 0, 1)
        changed = true
      elseif interaction.active_point == 2 then
        px = clamp(px+dnx, 0, 1)
        py = clamp(py+dny, 0, 1)
        changed = true
      elseif interaction.active_point == 3 then
        ex = clamp(ex+dnx, 0, 1)
        ey = clamp(ey+dny, 0, 1)
        changed = true
      end
      
      if changed then
        pad.sx, pad.sy = sx, sy
        pad.px, pad.py = px, py
        pad.ex, pad.ey = ex, ey
        markDirty()
      end
    end
    
    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*h
    local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*h
    local e_x, e_y = p_x + ex*w, p_y + (1-ey)*h
    
    r.ImGui_DrawList_AddLine(dl, s_x, s_y, p_x_d, p_y_d, COL_ACCENT, 1)
    r.ImGui_DrawList_AddLine(dl, p_x_d, p_y_d, e_x, e_y, COL_ACCENT, 1)
    
    r.ImGui_DrawList_AddCircle(dl, s_x, s_y, 4, 0x808080FF, 0, 1.5)
    
    r.ImGui_DrawList_AddCircleFilled(dl, p_x_d, p_y_d, 4, COL_ACCENT)
    r.ImGui_DrawList_AddCircle(dl, p_x_d, p_y_d, 4, 0xFFFFFFFF, 0, 1.5)
    
    local arrow_size = 6
    local dx = e_x - p_x_d
    local dy = e_y - p_y_d
    local len = math.sqrt(dx*dx + dy*dy)
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
      pad.points = {{x = 0.0, y = 0.2}, {x = 0.5, y = 0.8}, {x = 1.0, y = 0.2}}
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
        if not best_d or d < best_d then best_d = d; best_i = i end
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
      local x2 = px_coord(pad.points[i+1].x)
      local y2 = py_coord(pad.points[i+1].y)
      r.ImGui_DrawList_AddLine(dl, x1, y1, x2, y2, COL_ACCENT, 1)
    end
    
    for i, pt in ipairs(pad.points) do
      local cpx = px_coord(pt.x)
      local cpy = py_coord(pt.y)
      
      if i == 1 then
        r.ImGui_DrawList_AddCircle(dl, cpx, cpy, 4, 0x808080FF, 0, 1.5)
      elseif i == #pad.points then
        local prev_pt = pad.points[i-1]
        local prev_x = px_coord(prev_pt.x)
        local prev_y = py_coord(prev_pt.y)
        
        local arrow_size = 6
        local dx = cpx - prev_x
        local dy = cpy - prev_y
        local len = math.sqrt(dx*dx + dy*dy)
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
  
  return changed or false
end

local function getSegmentPositions()
  local seg = app.state.segment
  local mode = math.floor(tonumber(seg.mode) or 0)

  if mode == 1 then
    local bars = math.max(1, math.floor(tonumber(seg.bars) or 4))
    local div = math.max(1, math.floor(tonumber(seg.division) or 2))
    local count = (bars * div) + 1
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = i / (count - 1)
    end
    return out
  end

  local points = math.max(2, math.min(8, math.floor(tonumber(seg.points) or 4)))
  if type(seg.manual_positions) ~= 'table' then
    seg.manual_positions = {}
  end

  if #seg.manual_positions ~= points then
    seg.manual_positions = {}
    for i = 0, points - 1 do
      seg.manual_positions[#seg.manual_positions + 1] = i / (points - 1)
    end
  end

  seg.manual_positions[1] = 0.0
  seg.manual_positions[#seg.manual_positions] = 1.0
  for i = 2, #seg.manual_positions - 1 do
    local left = seg.manual_positions[i - 1] + 0.01
    local right = seg.manual_positions[i + 1] - 0.01
    seg.manual_positions[i] = clamp(seg.manual_positions[i], left, right)
  end

  return seg.manual_positions
end

local function getSegmentPositions()
  local seg = app.state.segment
  local mode = math.floor(tonumber(seg.mode) or 0)

  if mode == 1 then
    local bars = math.max(1, math.floor(tonumber(seg.bars) or 4))
    local div = math.max(1, math.floor(tonumber(seg.division) or 2))
    local count = (bars * div) + 1
    local out = {}
    for i = 0, count - 1 do
      out[#out + 1] = i / (count - 1)
    end
    return out
  end

  local points = math.max(2, math.min(8, math.floor(tonumber(seg.points) or 4)))
  local out = {}
  for i = 0, points - 1 do
    out[#out + 1] = i / (points - 1)
  end
  return out
end

local function drawSegmentationModule(w, h)
  drawHeader('Segmentation')
  
  local seg = app.state.segment
  local mode = math.floor(tonumber(seg.mode) or 0)
  
  r.ImGui_SetNextItemWidth(ctx, 100)
  local changed_mode, v1 = r.ImGui_Combo(ctx, 'Mode##seg', mode, 'Manual\0Musical\0')
  if changed_mode then
    app.state.segment.mode = math.floor(tonumber(v1) or 0)
    markDirty()
  end
  
  r.ImGui_SameLine(ctx, 0, 4)
  if mode == 0 then
    r.ImGui_SetNextItemWidth(ctx, 100)
    local pts_val = math.max(2, math.min(8, math.floor(tonumber(seg.points) or 4)))
    local changed_pts, v2 = r.ImGui_SliderInt(ctx, 'Points##seg', pts_val, 2, 8)
    if changed_pts then
      app.state.segment.points = math.floor(tonumber(v2) or 4)
      markDirty()
    end
  else
    r.ImGui_SetNextItemWidth(ctx, 90)
    local bars_val = math.max(1, math.min(8, math.floor(tonumber(seg.bars) or 4)))
    local changed_bars, v2 = r.ImGui_SliderInt(ctx, 'Bars##seg', bars_val, 1, 8)
    if changed_bars then
      app.state.segment.bars = math.floor(tonumber(v2) or 4)
      markDirty()
    end
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_SetNextItemWidth(ctx, 70)
    local div_val = math.max(1, math.min(4, math.floor(tonumber(seg.division) or 2)))
    local changed_div, v3 = r.ImGui_SliderInt(ctx, 'Division##seg', div_val, 1, 4)
    if changed_div then
      app.state.segment.division = math.floor(tonumber(v3) or 2)
      markDirty()
    end
  end
  
  r.ImGui_SameLine(ctx, 0, 4)
  if r.ImGui_Button(ctx, 'Apply', 50, 0) then
    local positions = getSegmentPositions()
    local point_count = #positions
    
    local function resegmentPadVector(pad)
      if not pad then return end
      if not pad.sx then return end
      
      local sx = clamp(pad.sx or 0.0, 0.0, 1.0)
      local ex = clamp(pad.ex or 1.0, 0.0, 1.0)
      
      local new_points = {}
      for i = 1, #positions do
        local t = positions[i]
        local x_pos = sx + (ex - sx) * t
        local y_val = evaluatePadVector(pad, t)
        new_points[#new_points + 1] = {x = x_pos, y = y_val}
      end
      
      pad.points = new_points
      pad.sx = nil
      pad.sy = nil
      pad.px = nil
      pad.py = nil
      pad.ex = nil
      pad.ey = nil
    end
    
    resegmentPadVector(app.state.pads.link_a)
    resegmentPadVector(app.state.pads.link_b)
    resegmentPadVector(app.state.pads.link_c)
    resegmentPadVector(app.state.external.pad)
    
    app.status = 'Applied: ' .. tostring(point_count) .. ' pts'
    markDirty()
  end
  
  r.ImGui_SameLine(ctx, 0, 4)
  if r.ImGui_Button(ctx, 'Reset', 50, 0) then
    local function resetPadToVector(pad)
      if not pad then return end
      if not pad.points or #pad.points < 2 then return end
      
      local first = pad.points[1]
      local last = pad.points[#pad.points]
      local mid_idx = math.floor(#pad.points / 2) + 1
      local mid = pad.points[mid_idx]
      
      pad.sx = first.x
      pad.sy = first.y
      pad.px = mid.x
      pad.py = mid.y
      pad.ex = last.x
      pad.ey = last.y
      pad.points = nil
    end
    
    resetPadToVector(app.state.pads.link_a)
    resetPadToVector(app.state.pads.link_b)
    resetPadToVector(app.state.pads.link_c)
    resetPadToVector(app.state.external.pad)
    
    app.status = 'Reset to vector mode'
    markDirty()
  end
  
  local positions = getSegmentPositions()
  r.ImGui_TextColored(ctx, 0xA0A0A0FF, mode == 1 and 'Musical' or (#positions .. ' pts'))
  
  local draw_h = 40
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  
  local x1, y1 = cx, cy + 5
  local x2, y2 = cx + avail_w - 10, cy + draw_h - 5
  local mid_y = (y1 + y2) * 0.5
  
  r.ImGui_SetCursorScreenPos(ctx, x1, y1)
  r.ImGui_InvisibleButton(ctx, '##seg_visual', x2 - x1, y2 - y1)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_active = r.ImGui_IsItemActive(ctx)
  
  if mode == 0 and is_active and interaction.seg_active_idx then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local norm_x = clamp((mx - x1) / (x2 - x1), 0.0, 1.0)
    
    local idx = interaction.seg_active_idx
    if idx > 1 and idx < #seg.manual_positions then
      seg.manual_positions[idx] = norm_x
      local left = seg.manual_positions[idx - 1] + 0.01
      local right = seg.manual_positions[idx + 1] - 0.01
      seg.manual_positions[idx] = clamp(seg.manual_positions[idx], left, right)
      markDirty()
    end
  end
  
  if mode == 0 and is_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local best_idx, best_dist = nil, nil
    for i = 2, #positions - 1 do
      local seg_x = x1 + (positions[i] * (x2 - x1))
      local dist = math.abs(mx - seg_x)
      if dist < 8 and (not best_dist or dist < best_dist) then
        best_idx = i
        best_dist = dist
      end
    end
    interaction.seg_active_idx = best_idx
  end
  
  if not r.ImGui_IsMouseDown(ctx, 0) then
    interaction.seg_active_idx = nil
  end
  
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, COL_PANEL, 4)
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, 0x3A3A3AFF, 4)
  
  local seg_w = x2 - x1
  for i = 1, #positions do
    local seg_x = x1 + (positions[i] * seg_w)
    local line_width = (i == 1 or i == #positions) and 2 or 1
    r.ImGui_DrawList_AddLine(dl, seg_x, y1, seg_x, y2, COL_ACCENT, line_width)
    
    local is_draggable = (mode == 0 and i > 1 and i < #positions)
    local pt_color = (i == 1 or i == #positions) and 0xEAEAEAFF or (is_draggable and 0xFFFFFFFF or 0x808080FF)
    local pt_radius = (interaction.seg_active_idx == i) and 5 or 3
    r.ImGui_DrawList_AddCircleFilled(dl, seg_x, mid_y, pt_radius, pt_color)
  end
end

local function drawPadGrid()
  if r.ImGui_BeginTable(ctx, 'pad_grid_main', 3, r.ImGui_TableFlags_SizingFixedFit()) then
    r.ImGui_TableSetupColumn(ctx, 'c1', r.ImGui_TableColumnFlags_WidthFixed(), PAD_W + 10)
    r.ImGui_TableSetupColumn(ctx, 'c2', r.ImGui_TableColumnFlags_WidthFixed(), PAD_W + 10)
    r.ImGui_TableSetupColumn(ctx, 'c3', r.ImGui_TableColumnFlags_WidthFixed(), ENV_W)

    r.ImGui_TableNextColumn(ctx)
    drawVectorPad('External', app.state.external.pad, '##pad_ext', PAD_W, PAD_H)
    r.ImGui_TableNextColumn(ctx)
    drawVectorPad('Link A', app.state.pads.link_a, '##pad_a', PAD_W, PAD_H)
    r.ImGui_TableNextColumn(ctx)
    drawSegmentationModule(ENV_W - 8, SEG_H)

    r.ImGui_TableNextColumn(ctx)
    drawVectorPad('Link B', app.state.pads.link_b, '##pad_b', PAD_W, PAD_H)
    r.ImGui_TableNextColumn(ctx)
    drawVectorPad('Link C', app.state.pads.link_c, '##pad_c', PAD_W, PAD_H)

    r.ImGui_EndTable(ctx)
  end
end

local function drawSourcesPanel()
  drawHeader('External Sources')
  
  for i, src in ipairs(app.state.external.sources) do
    r.ImGui_PushID(ctx, i)
    
    r.ImGui_SetNextItemWidth(ctx, 90)
    local c_name, v_name = r.ImGui_InputText(ctx, '##name_' .. i, src.name or ('Ext ' .. i))
    if c_name then src.name = v_name; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    local ch_on, on_v = r.ImGui_Checkbox(ctx, 'On##src_' .. i, src.enabled)
    if ch_on then src.enabled = on_v; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 45)
    local c_l, v_l = r.ImGui_InputInt(ctx, 'L##src_' .. i, src.ch_l, 0)
    if c_l then src.ch_l = math.max(1, v_l); markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 45)
    local c_r, v_r = r.ImGui_InputInt(ctx, 'R##src_' .. i, src.ch_r, 0)
    if c_r then src.ch_r = math.max(1, v_r); markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 80)
    local c_g, v_g = r.ImGui_SliderDouble(ctx, 'Gain##src_' .. i, src.gain, 0.0, 2.0)
    if c_g then src.gain = v_g; markDirty() end
    
    r.ImGui_PopID(ctx)
  end
end

local function drawSetupAndSegment(track)
  drawHeader('Setup')

  local setup = app.state.setup
  if track and r.ImGui_Button(ctx, 'Use Selected Track', 140, 0) then
    local _, name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    setup.target_track_name = name or ''
    refreshFXCache(track)
    markDirty()
  end
  r.ImGui_SameLine(ctx, 0, 4)
  r.ImGui_SetNextItemWidth(ctx, 120)
  local c_name, v_name = r.ImGui_InputText(ctx, '##target', setup.target_track_name)
  if c_name then
    setup.target_track_name = v_name
    markDirty()
  end
end

local function drawBindingCreate(track)
  if not track then
    r.ImGui_TextDisabled(ctx, 'Select target track to manage bindings.')
    return
  end

  if #app.fx_cache == 0 then
    refreshFXCache(track)
  end

  local ui = app.state.ui
  ui.selected_fx = clamp(ui.selected_fx or 0, 0, math.max(0, #app.fx_cache - 1))

  local fx_title = (#app.fx_cache > 0 and app.fx_cache[ui.selected_fx + 1].name) or 'No FX'
  if r.ImGui_BeginCombo(ctx, 'FX', fx_title) then
    for idx, fx in ipairs(app.fx_cache) do
      if r.ImGui_Selectable(ctx, fx.name, (ui.selected_fx + 1) == idx) then
        ui.selected_fx = idx - 1
        ui.selected_param = 0
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  local selected_fx = app.fx_cache[ui.selected_fx + 1]
  local params = selected_fx and getParams(track, selected_fx.index) or {}
  if #params > 0 then
    ui.selected_param = clamp(ui.selected_param or 0, 0, #params - 1)
  else
    ui.selected_param = 0
  end

  local param_title = (#params > 0 and params[ui.selected_param + 1].name) or 'No Params'
  if r.ImGui_BeginCombo(ctx, 'Param', param_title) then
    for idx, p in ipairs(params) do
      if r.ImGui_Selectable(ctx, p.name, (ui.selected_param + 1) == idx) then
        ui.selected_param = idx - 1
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  ui.selected_side = clamp(ui.selected_side or 0, 0, 3)
  local side_title = SIDE_LIST[ui.selected_side + 1]
  if r.ImGui_BeginCombo(ctx, 'Side', side_title) then
    for i = 0, 3 do
      if r.ImGui_Selectable(ctx, SIDE_LIST[i + 1], i == ui.selected_side) then
        ui.selected_side = i
        markDirty()
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  if r.ImGui_Button(ctx, 'Add Binding', 140, 0) and selected_fx and params[ui.selected_param + 1] then
    local b = BindingRegistry.NewBinding()
    b.fx_guid = selected_fx.guid
    b.fx_name = selected_fx.name
    b.param_index = params[ui.selected_param + 1].index
    b.param_name = params[ui.selected_param + 1].name
    b.label = selected_fx.name .. ' :: ' .. b.param_name
    b.side = ui.selected_side
    app.state.bindings[#app.state.bindings + 1] = b
    app.status = 'Binding added'
    markDirty()
  end
end

local function drawBindings(track)
  drawHeader('Parameter Bindings')
  drawBindingCreate(track)

  for i = #app.state.bindings, 1, -1 do
    local b = app.state.bindings[i]
    r.ImGui_PushID(ctx, i)
    local c0, v0 = r.ImGui_Checkbox(ctx, 'On##bind', b.enabled)
    if c0 then b.enabled = v0; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_TextColored(ctx, 0xA8A8A8FF, (b.label ~= '' and b.label or (b.fx_name .. ' :: ' .. b.param_name)):sub(1, 30))

    local side_idx = clamp(b.side or 0, 0, 3)
    r.ImGui_SetNextItemWidth(ctx, 60)
    if r.ImGui_BeginCombo(ctx, 'Side##bind', SIDE_LIST[side_idx + 1]) then
      for j = 0, 3 do
        if r.ImGui_Selectable(ctx, SIDE_LIST[j + 1], side_idx == j) then
          b.side = j
          markDirty()
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_SameLine(ctx, 0, 4)

    local c1, v1 = r.ImGui_Checkbox(ctx, 'Invert##bind', b.invert)
    if c1 then b.invert = v1; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 70)
    local c2, v2 = r.ImGui_SliderDouble(ctx, 'Min##bind', b.min, 0.0, 1.0)
    if c2 then b.min = v2; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 70)
    local c3, v3 = r.ImGui_SliderDouble(ctx, 'Max##bind', b.max, 0.0, 1.0)
    if c3 then b.max = v3; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)
    
    r.ImGui_SetNextItemWidth(ctx, 70)
    local c4, v4 = r.ImGui_SliderDouble(ctx, 'Curve##bind', b.curve, 0.1, 4.0)
    if c4 then b.curve = v4; markDirty() end
    r.ImGui_SameLine(ctx, 0, 4)

    if r.ImGui_Button(ctx, 'Delete##bind', 55, 0) then
      table.remove(app.state.bindings, i)
      markDirty()
      app.status = 'Binding removed'
    end

    r.ImGui_Separator(ctx)
    r.ImGui_PopID(ctx)
  end
end

local function buildPointList(start_t, end_t)
  local len = math.max(0.001, end_t - start_t)
  local positions = getSegmentPositions()
  local out = {}
  for i = 1, #positions do
    local t_norm = clamp(positions[i], 0.0, 1.0)
    out[#out + 1] = {time = start_t + (len * t_norm), t = t_norm}
  end

  if #out < 2 then
    out = {
      {time = start_t, t = 0.0},
      {time = end_t, t = 1.0}
    }
  end

  return out
end

local function collectWriteTargets(track)
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
  return targets
end

local function writeAutomation(track)
  if r.CountTracks(0) == 0 then
    app.status = 'No tracks in project.'
    r.ShowConsoleMsg('[ReaMotionPad] No tracks in project.\n')
    return
  end

  if not track then
    app.status = 'Target track not found.'
    r.ShowConsoleMsg('[ReaMotionPad] Target track not found.\n')
    return
  end

  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if end_t <= start_t then
    app.status = 'Set time selection first.'
    r.ShowConsoleMsg('[ReaMotionPad] Time selection is empty.\n')
    return
  end

  local points = buildPointList(start_t, end_t)
  local targets = collectWriteTargets(track)
  if #targets == 0 then
    app.status = 'No valid bindings resolved.'
    r.ShowConsoleMsg('[ReaMotionPad] No valid bindings to write.\n')
    return
  end

  local shape = app.state.setup.write_shape or 1
  local tension = app.state.setup.write_tension or 0.0
  local count = AutomationWriter.WriteOverwrite(track, targets, points, shape, tension)
  app.status = 'Written points: ' .. tostring(count)
end

local function drawActions(track)
  if r.ImGui_Button(ctx, 'Randomize', 120, 28) then
    randomizeState()
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3EB895FF)
  if r.ImGui_Button(ctx, 'WRITE AUTOMATION', 170, 28) then
    writeAutomation(track)
  end
  r.ImGui_PopStyleColor(ctx, 2)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Save State', 120, 28) then
    State.Save(app.state)
    app.status = 'State saved'
    app.dirty = false
  end

  if app.status ~= '' then
    r.ImGui_TextColored(ctx, COL_ORANGE, app.status)
  end
end

local function drawRandomMasks()
  drawHeader('Randomization')
  local rnd = app.state.random
  local c1, v1 = r.ImGui_Checkbox(ctx, 'Pad A', rnd.pad_a)
  if c1 then rnd.pad_a = v1; markDirty() end
  r.ImGui_SameLine(ctx)
  local c2, v2 = r.ImGui_Checkbox(ctx, 'Pad B', rnd.pad_b)
  if c2 then rnd.pad_b = v2; markDirty() end
  r.ImGui_SameLine(ctx)
  local c3, v3 = r.ImGui_Checkbox(ctx, 'Pad C', rnd.pad_c)
  if c3 then rnd.pad_c = v3; markDirty() end
  local c4, v4 = r.ImGui_Checkbox(ctx, 'Morph', rnd.morph)
  if c4 then rnd.morph = v4; markDirty() end
  r.ImGui_SameLine(ctx)
  local c5, v5 = r.ImGui_Checkbox(ctx, 'LFO', rnd.lfo)
  if c5 then rnd.lfo = v5; markDirty() end
  r.ImGui_SameLine(ctx)
  local c6, v6 = r.ImGui_Checkbox(ctx, 'Env', rnd.env)
  if c6 then rnd.env = v6; markDirty() end
end

local function drawBottomPanels(track)
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginTable(ctx, 'bottom_panels', 2, r.ImGui_TableFlags_SizingStretchProp()) then
    r.ImGui_TableSetupColumn(ctx, 'left', r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
    r.ImGui_TableSetupColumn(ctx, 'right', r.ImGui_TableColumnFlags_WidthStretch(), 1.1)

    r.ImGui_TableNextColumn(ctx)
    drawSetupAndSegment(track)
    drawSourcesPanel()

    r.ImGui_TableNextColumn(ctx)
    drawBindings(track)
    drawRandomMasks()
    drawActions(track)

    if app.status ~= '' then
      r.ImGui_TextColored(ctx, COL_ORANGE, app.status)
    end

    r.ImGui_EndTable(ctx)
  end
end

local function drawMain()
  local track = getTargetTrack()
  pushTheme()
  local visible, open = r.ImGui_Begin(ctx, 'SBP ReaMotion Pad v0.2.1', true, r.ImGui_WindowFlags_NoCollapse())

  if visible then
    drawTopBar(track)
    r.ImGui_Separator(ctx)
    drawPadGrid()
    drawBottomPanels(track)
    r.ImGui_End(ctx)
  end

  popTheme()
  return open
end

local function maybeAutosave()
  if not app.dirty then return end
  app.auto_save_counter = app.auto_save_counter + 1
  if app.auto_save_counter >= 90 then
    State.Save(app.state)
    app.auto_save_counter = 0
    app.dirty = false
  end
end

local function loop()
  local ok, open = pcall(drawMain)
  if not ok then
    r.ShowConsoleMsg('[ReaMotionPad] UI error: ' .. tostring(open) .. '\n')
    State.Save(app.state)
    return
  end

  maybeAutosave()

  if open then
    r.defer(loop)
  else
    State.Save(app.state)
  end
end

loop()
