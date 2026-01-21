-- ReaSFX GUI Module
-- v2.0 - Extracted GUI logic
local Gui = {}
local r = reaper

-- =========================================================
-- COLORS
-- =========================================================
local COLORS = {
    accent=0x0D755CFF, accent_hover=0x149675FF,
    bg=0x1E1E1EFF, bg_panel=0x252525FF, bg_input=0x141414FF,
    white_key=0xDDDDDDFF, black_key=0x111111FF,
    active_key=0xD46A3FFF, active_multi=0xD4AA3FFF, mute_active=0xD4AA3FFF,
    text_dim=0x909090FF, xy_bg=0x111111FF, xy_grid=0x333333FF,
    layer_col=0x0D755C99, smart_col=0x750D5C99, insert_btn=0x0D755CFF
}

Gui.COLORS = COLORS

-- =========================================================
-- THEME
-- =========================================================
function Gui.BeginChildBox(ctx, label, w, h)
    local border = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1
    return r.ImGui_BeginChild(ctx, label, w, h, border, 0)
end

function Gui.PushTheme(ctx)
    if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then return end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COLORS.accent_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COLORS.active_key)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x353535FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x454545FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x252525FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE0E0E0FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLORS.bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x303030FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLORS.bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLORS.active_key)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.active_key)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
end

function Gui.PopTheme(ctx)
    r.ImGui_PopStyleColor(ctx, 15)
    r.ImGui_PopStyleVar(ctx, 2)
end

-- =========================================================
-- TOP BAR
-- =========================================================
function Gui.DrawTopBar(ctx, Core)
    r.ImGui_TextDisabled(ctx, Core.LastLog)
    r.ImGui_SameLine(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + avail_w - 100)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.insert_btn)
    if r.ImGui_Button(ctx, "INSERT (K)", 100, 0) then
        local cursor = r.GetPlayState()~=0 and r.GetPlayPosition() or r.GetCursorPosition()
        Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 0)
        -- Instant Release
        Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 1)
        Core.SmartLoopRelease(Core.Project.selected_note, Core.Project.selected_set, cursor, cursor+0.1)
    end
    r.ImGui_PopStyleColor(ctx, 1)
end

-- =========================================================
-- KEYBOARD
-- =========================================================
function Gui.DrawKeyboard(ctx, Core, CONFIG)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 0)
    for i = 0, CONFIG.num_keys - 1 do
        local note = CONFIG.base_note + i
        local is_active = (Core.Project.selected_note == note)
        local n = note % 12
        local is_black = (n==1 or n==3 or n==6 or n==8 or n==10)
        local col = is_black and COLORS.black_key or COLORS.white_key
        if is_active then col = COLORS.active_key end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (not is_black or is_active) and 0x000000FF or 0xFFFFFFFF)
        r.ImGui_PushID(ctx, i)
        if r.ImGui_Button(ctx, tostring(note), 28, 80) then
            Core.Project.selected_note = note
            Core.InitKey(note)
            Core.Project.multi_sets = {}
        end
        r.ImGui_PopID(ctx)
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_SameLine(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_EndGroup(ctx)
    r.ImGui_TextColored(ctx, COLORS.accent, "Selected Key: " .. Core.Project.selected_note)
end

-- =========================================================
-- SETS TABS
-- =========================================================
function Gui.DrawSetsTabs(ctx, Core)
    r.ImGui_Separator(ctx)
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return end
    for i = 1, 16 do
        local is_main = (Core.Project.selected_set == i)
        local is_multi = false
        for _,v in ipairs(Core.Project.multi_sets) do
            if v==i then is_multi=true break end
        end
        local has_data = k.sets[i] and #k.sets[i].events > 0
        local col = 0x333333FF
        if is_main then col = COLORS.active_key
        elseif is_multi then col = COLORS.active_multi
        elseif has_data then col = COLORS.accent end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (is_main or is_multi) and 0x000000FF or 0xE0E0E0FF)
        if r.ImGui_Button(ctx, "S"..i, 35, 20) then
            if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt()) then
                Core.ClearSet(Core.Project.selected_note, i)
            elseif r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
                if is_multi then
                    for idx,v in ipairs(Core.Project.multi_sets) do
                        if v==i then table.remove(Core.Project.multi_sets, idx) break end
                    end
                else
                    table.insert(Core.Project.multi_sets, i)
                end
            else
                Core.Project.selected_set = i
                Core.Project.multi_sets = {}
            end
        end
        r.ImGui_PopStyleColor(ctx, 2)
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Click: Select\nShift+Click: Add Layer\nAlt+Click: Clear")
        end
        if i < 16 then r.ImGui_SameLine(ctx) end
    end
    r.ImGui_Separator(ctx)
end

-- =========================================================
-- EVENT SLOTS
-- =========================================================
function Gui.DrawEventsSlots(ctx, Core, CONFIG)
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return end
    local s = k.sets[Core.Project.selected_set]
    if not s or #s.events == 0 then
        r.ImGui_TextDisabled(ctx, "No Events.")
        return
    end
    r.ImGui_NewLine(ctx)
    for i, evt in ipairs(s.events) do
        r.ImGui_PushID(ctx, i)
        r.ImGui_BeginGroup(ctx)
            -- ✨ Show section type for smart events
            local lbl = string.format("E%02d", i)
            if evt.section_type then
                lbl = evt.section_type  -- "START", "LOOP", or "RELEASE"
            elseif evt.is_smart then
                lbl = lbl .. " (S)"
            end
            if evt.has_release and not evt.section_type then
                lbl = lbl .. " (R)"
            end
            r.ImGui_TextColored(ctx, evt.is_smart and COLORS.active_multi or COLORS.accent, lbl)
            local w = CONFIG.slot_width
            local p = {r.ImGui_GetCursorScreenPos(ctx)}
            local dl = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_InvisibleButton(ctx, "l", w, math.max(20, #evt.items*7))
            if r.ImGui_IsItemActive(ctx) then
                Core.StartPreview(evt, i)
            else
                if Core.PreviewID == i then Core.StopPreview() end
            end
            for li=1, #evt.items do
                local y1 = p[2] + (li-1)*7
                r.ImGui_DrawList_AddRectFilled(dl, p[1], y1, p[1]+w, y1+6,
                    (evt.items[li] and evt.items[li].smart) and COLORS.smart_col or COLORS.layer_col)
            end
            local mc = evt.muted and COLORS.mute_active or 0x555555FF
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mc)
            if r.ImGui_Button(ctx, "M", w, 0) then evt.muted = not evt.muted end
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SetNextItemWidth(ctx, w)
            local _, np = r.ImGui_SliderInt(ctx, "##p", evt.probability, 0, 100, "")
            if _ then evt.probability=np end
            r.ImGui_TextColored(ctx, COLORS.text_dim, "P: " .. evt.probability .. "%")
            r.ImGui_SetNextItemWidth(ctx, w)
            local _, nv = r.ImGui_SliderDouble(ctx, "##v", evt.vol_offset or 0, -12, 12, "")
            if _ then evt.vol_offset=nv end
            r.ImGui_TextColored(ctx, COLORS.text_dim, "V: " .. string.format("%+.1f", evt.vol_offset or 0))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA4444FF)
            if r.ImGui_Button(ctx, "X", w, 0) then
                Core.DeleteEvent(Core.Project.selected_note, Core.Project.selected_set, i)
            end
            r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_EndGroup(ctx)
        r.ImGui_PopID(ctx)
        r.ImGui_SameLine(ctx)
    end
    r.ImGui_NewLine(ctx)
end

-- =========================================================
-- MODULATION MATRIX
-- =========================================================
function Gui.DrawModulationMatrix(ctx, s, Core)
    if not r.ImGui_BeginTable(ctx, "ModMatrix", 3, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
        return
    end
    r.ImGui_TableSetupColumn(ctx, "P", r.ImGui_TableColumnFlags_WidthFixed(), 40)
    r.ImGui_TableSetupColumn(ctx, "Evt", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Set", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableHeadersRow(ctx)

    local function Rw(n,sv,gv,mx,sf,gf)
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_Text(ctx, n)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx,-1)
        local c1,v1=r.ImGui_SliderDouble(ctx,"##s"..n,sv,0,mx,"%.2f")
        if c1 then sf(v1) end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx,-1)
        local c2,v2=r.ImGui_SliderDouble(ctx,"##g"..n,gv,0,mx,"%.2f")
        if c2 then gf(v2) end
    end

    Rw("Vol", s.rnd_vol, Core.Project.g_rnd_vol, 12,
        function(v)s.rnd_vol=v end, function(v)Core.Project.g_rnd_vol=v end)
    Rw("Pit", s.rnd_pitch, Core.Project.g_rnd_pitch, 12,
        function(v)s.rnd_pitch=v end, function(v)Core.Project.g_rnd_pitch=v end)
    Rw("Pan", s.rnd_pan, Core.Project.g_rnd_pan, 100,
        function(v)s.rnd_pan=v end, function(v)Core.Project.g_rnd_pan=v end)
    Rw("Pos", s.rnd_pos, Core.Project.g_rnd_pos, 0.2,
        function(v)s.rnd_pos=v end, function(v)Core.Project.g_rnd_pos=v end)
    Rw("Off", s.rnd_offset, Core.Project.g_rnd_offset, 1.0,
        function(v)s.rnd_offset=v end, function(v)Core.Project.g_rnd_offset=v end)
    Rw("Fad", s.rnd_fade, Core.Project.g_rnd_fade, 0.5,
        function(v)s.rnd_fade=v end, function(v)Core.Project.g_rnd_fade=v end)
    Rw("Len", s.rnd_len, Core.Project.g_rnd_len, 1.0,
        function(v)s.rnd_len=v end, function(v)Core.Project.g_rnd_len=v end)

    r.ImGui_EndTable(ctx)
end

-- =========================================================
-- SEQUENCER PARAMS
-- =========================================================
function Gui.DrawSequencerParams(ctx, s)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "SEQ SETTINGS")

    r.ImGui_SetNextItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "##sqm", ({"Repeat First", "Random Pool", "Stitch Random"})[s.seq_mode+1]) then
        if r.ImGui_Selectable(ctx, "Repeat First", s.seq_mode==0) then s.seq_mode=0 end
        if r.ImGui_Selectable(ctx, "Random Pool", s.seq_mode==1) then s.seq_mode=1 end
        if r.ImGui_Selectable(ctx, "Stitch Random", s.seq_mode==2) then s.seq_mode=2 end
        r.ImGui_EndCombo(ctx)
    end

    if r.ImGui_BeginTable(ctx, "SeqT", 2) then
        r.ImGui_TableSetupColumn(ctx, "L", r.ImGui_TableColumnFlags_WidthFixed(), 40)
        r.ImGui_TableSetupColumn(ctx, "V", r.ImGui_TableColumnFlags_WidthStretch())

        local function Drag(lbl, val, step, cb)
            r.ImGui_TableNextRow(ctx)
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Text(ctx, lbl)
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local ch, nv = r.ImGui_DragDouble(ctx, "##"..lbl, val, step, 0, 100, "%.3f")
            if ch then cb(nv) end
        end

        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_Text(ctx, "Cnt")
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local c, v = r.ImGui_InputInt(ctx, "##cnt", s.seq_count)
        if c then s.seq_count = math.max(1, v) end

        Drag("Rate", s.seq_rate, 0.005, function(v) s.seq_rate = math.max(0.01, v) end)
        Drag("Len", s.seq_len, 0.005, function(v) s.seq_len = math.max(0.01, v) end)
        Drag("Fade", s.seq_fade, 0.001, function(v) s.seq_fade = math.max(0.001, v) end)
        r.ImGui_EndTable(ctx)
    end
    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- XY PAD
-- =========================================================
function Gui.DrawXYPad(ctx, s)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "PERFORM (XY)")
    local size = 160
    local avail = r.ImGui_GetContentRegionAvail(ctx)
    if avail > size then
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail-size)*0.5)
    end

    local p = { r.ImGui_GetCursorScreenPos(ctx) }
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+size, p[2]+size, COLORS.xy_bg, 4)
    r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+size, p[2]+size, COLORS.xy_grid, 4)
    r.ImGui_DrawList_AddText(dl, p[1]+2, p[2]+2, 0xAAAAAAFF, "Intens")
    r.ImGui_DrawList_AddText(dl, p[1]+size-40, p[2]+size-14, 0xAAAAAAFF, "Spread")
    r.ImGui_InvisibleButton(ctx, "XYPad", size, size)
    if r.ImGui_IsItemActive(ctx) then
        local mx, my = r.ImGui_GetMousePos(ctx)
        s.xy_x = math.max(0, math.min(1, (mx - p[1]) / size))
        s.xy_y = math.max(0, math.min(1, 1 - (my - p[2]) / size))
    end
    local px = p[1] + s.xy_x * size
    local py = p[2] + (1 - s.xy_y) * size
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, 6, COLORS.accent)
    r.ImGui_DrawList_AddLine(dl, px, p[2], px, p[2]+size, COLORS.xy_grid)
    r.ImGui_DrawList_AddLine(dl, p[1], py, p[1]+size, py, COLORS.xy_grid)
    r.ImGui_TextColored(ctx, COLORS.text_dim, string.format("X:%.0f%% Y:%.0f%%", s.xy_x*200, s.xy_y*200))
    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- MAIN CONTROLS
-- =========================================================
function Gui.DrawMainControls(ctx, Core)
    if Gui.BeginChildBox(ctx, "MA", 0, 240) then
        if r.ImGui_BeginTable(ctx, "LT", 4) then
            r.ImGui_TableSetupColumn(ctx, "C1", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C2", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C3", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C4", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableNextRow(ctx)

            -- COL 1: Capture / Base
            r.ImGui_TableNextColumn(ctx)
            local k = Core.Project.keys[Core.Project.selected_note]
            if k then
                local s = k.sets[Core.Project.selected_set]
                r.ImGui_TextColored(ctx, COLORS.active_key, "SET " .. Core.Project.selected_set)

                local avail = r.ImGui_GetContentRegionAvail(ctx)
                r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail-140)*0.5)
                if r.ImGui_Button(ctx, "CAPTURE (+)", 140, 40) then
                    Core.CaptureToActiveSet()
                end

                r.ImGui_SetNextItemWidth(ctx, 140)
                local gt, gtv = r.ImGui_DragDouble(ctx, "Gap Thrs", Core.Project.group_thresh, 0.01, 0.01, 2.0, "%.2fs")
                if gt then Core.Project.group_thresh = gtv end

                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##trg", ({"Start: Key Down", "Start: Key Up"})[s.trigger_on+1]) then
                    if r.ImGui_Selectable(ctx, "Key Down", s.trigger_on==0) then s.trigger_on=0 end
                    if r.ImGui_Selectable(ctx, "Key Up", s.trigger_on==1) then s.trigger_on=1 end
                    r.ImGui_EndCombo(ctx)
                end

                local _, b = r.ImGui_Checkbox(ctx, "Snap Offset", Core.Project.use_snap_align)
                if _ then Core.Project.use_snap_align=b end

                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##pm", ({"Rel Layers", "Old FIPM", "Fixed Lanes"})[Core.Project.placement_mode+1]) then
                    if r.ImGui_Selectable(ctx, "Rel Layers", false) then Core.Project.placement_mode=0 end
                    if r.ImGui_Selectable(ctx, "Old FIPM", false) then Core.Project.placement_mode=1 end
                    if r.ImGui_Selectable(ctx, "Fixed Lanes", false) then Core.Project.placement_mode=2 end
                    r.ImGui_EndCombo(ctx)
                end
                if s then r.ImGui_Text(ctx, "Count: " .. #s.events) end

                -- COL 2: Modes
                r.ImGui_TableNextColumn(ctx)
                r.ImGui_Text(ctx, "TRIGGER MODE")
                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##tm", ({"One Shot", "Sequencer", "Smart Loop"})[Core.Project.trigger_mode+1]) then
                    if r.ImGui_Selectable(ctx, "One Shot", false) then Core.Project.trigger_mode=0 end
                    if r.ImGui_Selectable(ctx, "Sequencer", false) then Core.Project.trigger_mode=1 end
                    if r.ImGui_Selectable(ctx, "Smart Loop", false) then Core.Project.trigger_mode=2 end
                    r.ImGui_EndCombo(ctx)
                end

                if s and Core.Project.trigger_mode == 1 then
                    r.ImGui_Dummy(ctx, 0, 10)
                    Gui.DrawSequencerParams(ctx, s)
                end

                -- COL 3: Matrix
                r.ImGui_TableNextColumn(ctx)
                if s then Gui.DrawModulationMatrix(ctx, s, Core) end

                -- COL 4: XY
                r.ImGui_TableNextColumn(ctx)
                if s then Gui.DrawXYPad(ctx, s) end
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Separator(ctx)
end

return Gui
