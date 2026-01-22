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
Gui.ShowLogWindow = false

function Gui.DrawTopBar(ctx, Core)
    r.ImGui_TextDisabled(ctx, Core.LastLog)
    r.ImGui_SameLine(ctx)

    -- Log window toggle button
    if r.ImGui_SmallButton(ctx, "Logs") then
        Gui.ShowLogWindow = not Gui.ShowLogWindow
    end

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
-- LOG WINDOW
-- =========================================================
function Gui.DrawLogWindow(ctx, Core)
    if not Gui.ShowLogWindow then return end

    r.ImGui_SetNextWindowSize(ctx, 600, 400, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, "Debug Logs", true)
    if visible then
        if r.ImGui_Button(ctx, "Clear") then
            Core.LogHistory = {}
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Copy All") then
            r.CF_SetClipboard(table.concat(Core.LogHistory or {}, "\n"))
        end

        r.ImGui_Separator(ctx)

        if r.ImGui_BeginChild(ctx, "LogScroll", 0, 0) then
            for _, log_line in ipairs(Core.LogHistory or {}) do
                r.ImGui_TextWrapped(ctx, log_line)
            end
            r.ImGui_EndChild(ctx)
        end

        r.ImGui_End(ctx)
    end
    if not open then
        Gui.ShowLogWindow = false
    end
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
-- SETS TABS (with per-set MIDI controls)
-- =========================================================
local MIDI_COLORS = {
    slider_bg = 0x333333FF,
    slider_fill = 0x0D755CFF,
    slider_fill_invert = 0x755C0DFF,
    midi_enabled = 0x00AA00FF,
    midi_disabled = 0x555555FF
}

function Gui.DrawSetsTabs(ctx, Core)
    r.ImGui_Separator(ctx)
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return end

    local col_width = 35

    -- Global MIDI enable + Install button
    r.ImGui_BeginGroup(ctx)
    local midi_ch, midi_v = r.ImGui_Checkbox(ctx, "MIDI", Core.Project.midi_enabled)
    if midi_ch then Core.Project.midi_enabled = midi_v end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "MIDI notes 60-89 trigger keys directly")
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Bridge") then
        local jsfx_code = Core.GetMIDIBridgeJSFX()
        local path = r.GetResourcePath() .. "/Effects/ReaSFX_MIDI_Bridge.jsfx"
        local f = io.open(path, "w")
        if f then
            f:write(jsfx_code)
            f:close()
            Core.Log("MIDI Bridge JSFX installed: " .. path)
            r.ShowMessageBox("MIDI Bridge installed!\n\nAdd 'ReaSFX_MIDI_Bridge' to a track with MIDI input.", "ReaSFX", 0)
        end
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Install JSFX MIDI Bridge")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Auto") then
        -- Auto-distribute velocity ranges for enabled sets
        local enabled_sets = {}
        for i = 1, 16 do
            if k.sets[i] and k.sets[i].midi_enabled then
                table.insert(enabled_sets, i)
            end
        end
        local count = #enabled_sets
        if count > 0 then
            local range_size = math.floor(127 / count)
            for idx, set_idx in ipairs(enabled_sets) do
                k.sets[set_idx].velocity_min = (idx - 1) * range_size
                k.sets[set_idx].velocity_max = (idx == count) and 127 or (idx * range_size - 1)
            end
            Core.Log(string.format("Velocity auto-distributed across %d sets", count))
        end
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Auto-distribute velocity across MIDI-enabled sets")
    end
    r.ImGui_EndGroup(ctx)

    r.ImGui_Separator(ctx)

    -- Calculate table width
    local table_flags = r.ImGui_TableFlags_SizingFixedFit()

    -- ROW 1: Set buttons (S1-S16) + label "Сеты"
    if r.ImGui_BeginTable(ctx, "SetsGrid", 17, table_flags) then
        -- Setup columns
        for i = 1, 16 do
            r.ImGui_TableSetupColumn(ctx, "C"..i, r.ImGui_TableColumnFlags_WidthFixed(), col_width)
        end
        r.ImGui_TableSetupColumn(ctx, "Label", r.ImGui_TableColumnFlags_WidthFixed(), 60)

        -- ROW 1: Set buttons
        r.ImGui_TableNextRow(ctx)
        for i = 1, 16 do
            r.ImGui_TableNextColumn(ctx)
            local s = k.sets[i]
            local is_main = (Core.Project.selected_set == i)
            local is_multi = false
            for _,v in ipairs(Core.Project.multi_sets) do
                if v==i then is_multi=true break end
            end
            local has_data = s and #s.events > 0
            local has_midi = s and s.midi_enabled

            local col = 0x333333FF
            if is_main then col = COLORS.active_key
            elseif has_midi then col = 0x8844AAFF
            elseif is_multi then col = COLORS.active_multi
            elseif has_data then col = COLORS.accent end

            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (is_main or is_multi or has_midi) and 0x000000FF or 0xE0E0E0FF)
            r.ImGui_PushID(ctx, "set"..i)
            if r.ImGui_Button(ctx, "S"..i, col_width, 20) then
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
            r.ImGui_PopID(ctx)
            r.ImGui_PopStyleColor(ctx, 2)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Click: Select\nShift+Click: Add Layer\nAlt+Click: Clear")
            end
        end
        -- Label
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextDisabled(ctx, "Sets")

        -- ROW 2: MIDI enable checkboxes
        r.ImGui_TableNextRow(ctx)
        for i = 1, 16 do
            r.ImGui_TableNextColumn(ctx)
            local s = k.sets[i]
            if s then
                r.ImGui_PushID(ctx, "midi"..i)
                local midi_col = s.midi_enabled and MIDI_COLORS.midi_enabled or MIDI_COLORS.midi_disabled
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), midi_col)
                local ch, v = r.ImGui_Checkbox(ctx, "##m", s.midi_enabled)
                if ch then s.midi_enabled = v end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_PopID(ctx)
            end
        end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextDisabled(ctx, "Enable MIDI")

        -- ROW 3: Velocity sliders (vertical, color-filled)
        r.ImGui_TableNextRow(ctx)
        local slider_height = 60
        for i = 1, 16 do
            r.ImGui_TableNextColumn(ctx)
            local s = k.sets[i]
            if s then
                r.ImGui_PushID(ctx, "vel"..i)

                -- Draw custom vertical velocity slider
                local p = { r.ImGui_GetCursorScreenPos(ctx) }
                local dl = r.ImGui_GetWindowDrawList(ctx)

                -- Background
                r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+col_width-4, p[2]+slider_height, MIDI_COLORS.slider_bg, 3)

                -- Calculate fill based on velocity range
                local vel_min = s.velocity_min or 0
                local vel_max = s.velocity_max or 127

                -- Filled portion (from bottom to top)
                local fill_col = s.velocity_invert and MIDI_COLORS.slider_fill_invert or MIDI_COLORS.slider_fill
                local fill_bottom = p[2] + slider_height * (1 - vel_min / 127)
                local fill_top = p[2] + slider_height * (1 - vel_max / 127)

                if s.velocity_invert then
                    -- Inverted: fill from top
                    fill_bottom = p[2] + slider_height * (vel_max / 127)
                    fill_top = p[2] + slider_height * (vel_min / 127)
                end

                r.ImGui_DrawList_AddRectFilled(dl, p[1]+1, fill_top, p[1]+col_width-5, fill_bottom, fill_col, 2)

                -- Border
                r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+col_width-4, p[2]+slider_height, 0x666666FF, 3)

                -- Value text
                local vel_text = string.format("%d", vel_max)
                r.ImGui_DrawList_AddText(dl, p[1]+2, p[2]+slider_height-14, 0xFFFFFFFF, vel_text)

                -- Invisible button for interaction
                r.ImGui_InvisibleButton(ctx, "##vslider", col_width-4, slider_height)

                if r.ImGui_IsItemActive(ctx) then
                    local _, my = r.ImGui_GetMousePos(ctx)
                    local rel_y = 1 - (my - p[2]) / slider_height
                    rel_y = math.max(0, math.min(1, rel_y))
                    local new_vel = math.floor(rel_y * 127)

                    if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
                        -- Shift+drag: adjust min
                        s.velocity_min = math.min(new_vel, s.velocity_max)
                    else
                        -- Normal drag: adjust max
                        s.velocity_max = math.max(new_vel, s.velocity_min)
                    end
                end

                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, string.format("Vel: %d-%d\nDrag: Max\nShift+Drag: Min", vel_min, vel_max))
                end

                r.ImGui_PopID(ctx)
            end
        end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextDisabled(ctx, "Velocity zone")

        -- ROW 4: Clear buttons
        r.ImGui_TableNextRow(ctx)
        for i = 1, 16 do
            r.ImGui_TableNextColumn(ctx)
            local s = k.sets[i]
            if s then
                r.ImGui_PushID(ctx, "clr"..i)
                local has_events = #s.events > 0
                local clr_col = has_events and 0xAA4444FF or 0x444444FF
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), clr_col)
                if r.ImGui_Button(ctx, "X", col_width-4, 18) then
                    Core.ClearSet(Core.Project.selected_note, i)
                end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_PopID(ctx)
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, has_events and "Clear set (" .. #s.events .. " events)" or "Empty")
                end
            end
        end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextDisabled(ctx, "Clear")

        -- ROW 5: Invert buttons
        r.ImGui_TableNextRow(ctx)
        for i = 1, 16 do
            r.ImGui_TableNextColumn(ctx)
            local s = k.sets[i]
            if s then
                r.ImGui_PushID(ctx, "inv"..i)
                local inv_col = s.velocity_invert and MIDI_COLORS.slider_fill_invert or 0x444444FF
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), inv_col)
                if r.ImGui_Button(ctx, "I", col_width-4, 18) then
                    s.velocity_invert = not s.velocity_invert
                end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_PopID(ctx)
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, s.velocity_invert and "Inverted" or "Normal")
                end
            end
        end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_TextDisabled(ctx, "Invert range")

        r.ImGui_EndTable(ctx)
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
    r.ImGui_TextDisabled(ctx, "RANDOMIZE MATRIX")
    local table_opened = r.ImGui_BeginTable(ctx, "ModMatrix", 3, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg())
    if not table_opened then
        -- Defensive: log warning if table not opened
        if Core and Core.Log then Core.Log("[GUI] Failed to open ModMatrix table (ImGui_BeginTable returned false)") end
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
-- SMART LOOP PARAMS
-- =========================================================
function Gui.DrawSmartLoopParams(ctx, s)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "SMART LOOP")

    -- Crossfade slider
    r.ImGui_Text(ctx, "Crossfade")
    r.ImGui_SetNextItemWidth(ctx, 140)
    local cf_changed, cf_val = r.ImGui_SliderDouble(ctx, "##slcf", s.loop_crossfade or 0.003, 0.001, 0.100, "%.3fs")
    if cf_changed then s.loop_crossfade = cf_val end

    -- Sync mode
    r.ImGui_Text(ctx, "Sync Mode")
    r.ImGui_SetNextItemWidth(ctx, 140)
    local sync_modes = {"Free", "Tempo", "Grid"}
    if r.ImGui_BeginCombo(ctx, "##slsync", sync_modes[(s.loop_sync_mode or 0) + 1]) then
        if r.ImGui_Selectable(ctx, "Free", s.loop_sync_mode==0) then s.loop_sync_mode=0 end
        if r.ImGui_Selectable(ctx, "Tempo", s.loop_sync_mode==1) then s.loop_sync_mode=1 end
        if r.ImGui_Selectable(ctx, "Grid", s.loop_sync_mode==2) then s.loop_sync_mode=2 end
        r.ImGui_EndCombo(ctx)
    end

    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- FX CHAIN MANAGER
-- =========================================================
function Gui.DrawFXChain(ctx, s, Core)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "FX CHAIN")

    -- Copy FX from selected item
    if r.ImGui_Button(ctx, "Copy FX from Item", 140, 0) then
        Core.CopyFXToSet()
    end

    -- Clear FX / Show status
    local has_fx = s.fx_source_item and s.fx_count and s.fx_count > 0
    if has_fx then
        if r.ImGui_Button(ctx, "Clear FX", 140, 0) then
            s.fx_source_item = nil
            s.fx_count = 0
            Core.Log("FX source cleared")
        end
        r.ImGui_TextColored(ctx, COLORS.accent, string.format("FX: %d effect(s)", s.fx_count))
    else
        r.ImGui_TextColored(ctx, COLORS.text_dim, "FX: None")
    end

    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- SEQUENCER PARAMS
-- =========================================================
function Gui.DrawSequencerParams(ctx, s, Core)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "SEQ SETTINGS")

    r.ImGui_SetNextItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "##sqm", ({"Repeat First", "Random Pool", "Stitch Random"})[s.seq_mode+1]) then
        if r.ImGui_Selectable(ctx, "Repeat First", s.seq_mode==0) then s.seq_mode=0 end
        if r.ImGui_Selectable(ctx, "Random Pool", s.seq_mode==1) then s.seq_mode=1 end
        if r.ImGui_Selectable(ctx, "Stitch Random", s.seq_mode==2) then s.seq_mode=2 end
        r.ImGui_EndCombo(ctx)
    end

    -- Only show seq params for Repeat First and Random Pool modes
    if s.seq_mode ~= 2 then
        local function Drag(lbl, val, step, cb)
            r.ImGui_Text(ctx, lbl)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 70)
            local ch, nv = r.ImGui_DragDouble(ctx, "##"..lbl, val, step, 0, 100, "%.3f")
            if ch then cb(nv) end
            return ch
        end

        local changed = false
        if Drag("Rate", s.seq_rate, 0.005, function(v) s.seq_rate = math.max(0.01, v) end) then changed = true end
        if Drag("Len", s.seq_len, 0.005, function(v) s.seq_len = math.max(0.01, v) end) then changed = true end
        if Drag("Fade", s.seq_fade, 0.001, function(v) s.seq_fade = math.max(0.001, v) end) then changed = true end

        -- Real-time update on selected items
        if changed and Core then
            Core.UpdateSelectedItemsRealtime(s)
        end
    else
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Stitch uses original")
    end
    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- XY PAD
-- =========================================================
-- Mode labels for XY Pad
local XY_MODES = {
    { name = "Intens/Spread", labelY = "Intens", labelX = "Spread" },
    { name = "Vol/Pitch", labelY = "Vol", labelX = "Pitch" },
    { name = "Pan/Pos", labelY = "Pan", labelX = "Pos" }
}

function Gui.DrawXYPad(ctx, s, Core, pad_size)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "PERFORM (XY)")

    -- Mode selector
    local mode = s.xy_mode or 0
    r.ImGui_SetNextItemWidth(ctx, 100)
    if r.ImGui_BeginCombo(ctx, "##xym", XY_MODES[mode+1].name) then
        for i = 0, 2 do
            if r.ImGui_Selectable(ctx, XY_MODES[i+1].name, mode == i) then
                s.xy_mode = i
            end
        end
        r.ImGui_EndCombo(ctx)
    end

    local size = pad_size or 140
    local avail = r.ImGui_GetContentRegionAvail(ctx)
    if avail > size then
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail-size)*0.5)
    end

    local p = { r.ImGui_GetCursorScreenPos(ctx) }
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local half = size / 2

    -- Draw quadrant backgrounds with subtle highlighting
    local qx = s.xy_x >= 0.5 and 1 or 0  -- which quadrant X (0=left, 1=right)
    local qy = s.xy_y >= 0.5 and 1 or 0  -- which quadrant Y (0=bottom, 1=top)

    -- Quadrant colors (subtle tint for active)
    local quad_inactive = 0x1A1A1AFF
    local quad_active = 0x2A2A3AFF

    -- Top-left (qx=0, qy=1)
    local tl_col = (qx == 0 and qy == 1) and quad_active or quad_inactive
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+half, p[2]+half, tl_col)
    -- Top-right (qx=1, qy=1)
    local tr_col = (qx == 1 and qy == 1) and quad_active or quad_inactive
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2], p[1]+size, p[2]+half, tr_col)
    -- Bottom-left (qx=0, qy=0)
    local bl_col = (qx == 0 and qy == 0) and quad_active or quad_inactive
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2]+half, p[1]+half, p[2]+size, bl_col)
    -- Bottom-right (qx=1, qy=0)
    local br_col = (qx == 1 and qy == 0) and quad_active or quad_inactive
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2]+half, p[1]+size, p[2]+size, br_col)

    -- Border
    r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+size, p[2]+size, COLORS.xy_grid, 4)

    -- Center lines
    r.ImGui_DrawList_AddLine(dl, p[1]+half, p[2], p[1]+half, p[2]+size, 0x444444FF)
    r.ImGui_DrawList_AddLine(dl, p[1], p[2]+half, p[1]+size, p[2]+half, 0x444444FF)

    -- Labels based on mode
    local labels = XY_MODES[mode+1]
    r.ImGui_DrawList_AddText(dl, p[1]+2, p[2]+2, 0xAAAAAAFF, labels.labelY)
    r.ImGui_DrawList_AddText(dl, p[1]+size-30, p[2]+size-14, 0xAAAAAAFF, labels.labelX)

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx, "XYPad", size, size)
    local is_active = r.ImGui_IsItemActive(ctx)
    local is_hovered = r.ImGui_IsItemHovered(ctx)

    if is_active then
        local mx, my = r.ImGui_GetMousePos(ctx)
        s.xy_x = math.max(0, math.min(1, (mx - p[1]) / size))
        s.xy_y = math.max(0, math.min(1, 1 - (my - p[2]) / size))
    elseif s.xy_snap and not is_active then
        -- Snap to center when released
        local snap_speed = 0.15
        s.xy_x = s.xy_x + (0.5 - s.xy_x) * snap_speed
        s.xy_y = s.xy_y + (0.5 - s.xy_y) * snap_speed
        -- Stop snapping when close enough
        if math.abs(s.xy_x - 0.5) < 0.01 then s.xy_x = 0.5 end
        if math.abs(s.xy_y - 0.5) < 0.01 then s.xy_y = 0.5 end
    end

    -- Right-click context menu for MIDI settings
    if is_hovered and r.ImGui_IsMouseClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "XY_MIDI_Menu")
    end

    if r.ImGui_BeginPopup(ctx, "XY_MIDI_Menu") then
        r.ImGui_Text(ctx, "XY MIDI Settings")
        r.ImGui_Separator(ctx)

        -- X Axis CC
        r.ImGui_Text(ctx, "X Axis CC:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 60)
        local x_cc = s.xy_midi_x_cc or -1
        local ch_x, v_x = r.ImGui_InputInt(ctx, "##xcc", x_cc)
        if ch_x then s.xy_midi_x_cc = math.max(-1, math.min(127, v_x)) end

        -- Y Axis CC
        r.ImGui_Text(ctx, "Y Axis CC:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 60)
        local y_cc = s.xy_midi_y_cc or -1
        local ch_y, v_y = r.ImGui_InputInt(ctx, "##ycc", y_cc)
        if ch_y then s.xy_midi_y_cc = math.max(-1, math.min(127, v_y)) end

        -- Channel
        r.ImGui_Text(ctx, "Channel:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 60)
        local ch_ch, v_ch = r.ImGui_InputInt(ctx, "##mch", s.xy_midi_channel or 0)
        if ch_ch then s.xy_midi_channel = math.max(0, math.min(16, v_ch)) end

        r.ImGui_Separator(ctx)

        -- MIDI Learn buttons
        if r.ImGui_Button(ctx, "Learn X", 70, 0) then
            Core.MIDI.learn_mode = "x"
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Learn Y", 70, 0) then
            Core.MIDI.learn_mode = "y"
        end

        -- Apply learned CC
        if Core.MIDI.learn_mode and Core.MIDI.last_cc >= 0 then
            if Core.MIDI.learn_mode == "x" then
                s.xy_midi_x_cc = Core.MIDI.last_cc
            elseif Core.MIDI.learn_mode == "y" then
                s.xy_midi_y_cc = Core.MIDI.last_cc
            end
            Core.MIDI.learn_mode = nil
            Core.MIDI.last_cc = -1
        end

        if Core.MIDI.learn_mode then
            r.ImGui_TextColored(ctx, 0xFFFF00FF, "Move a CC control...")
        end

        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Disable MIDI", -1, 0) then
            s.xy_midi_x_cc = -1
            s.xy_midi_y_cc = -1
        end

        r.ImGui_EndPopup(ctx)
    end

    -- Draw cursor position
    local px = p[1] + s.xy_x * size
    local py = p[2] + (1 - s.xy_y) * size
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, 6, COLORS.accent)
    r.ImGui_DrawList_AddLine(dl, px, p[2], px, p[2]+size, COLORS.xy_grid)
    r.ImGui_DrawList_AddLine(dl, p[1], py, p[1]+size, py, COLORS.xy_grid)

    -- MIDI indicator
    if (s.xy_midi_x_cc or -1) >= 0 or (s.xy_midi_y_cc or -1) >= 0 then
        r.ImGui_DrawList_AddText(dl, p[1]+size-25, p[2]+2, 0x00FF00FF, "MIDI")
    end

    -- Snap checkbox + Reset button
    local snap_ch, snap_v = r.ImGui_Checkbox(ctx, "Snap", s.xy_snap or false)
    if snap_ch then s.xy_snap = snap_v end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Reset", 50, 0) then
        s.xy_x = 0.5
        s.xy_y = 0.5
    end

    -- Coordinates display
    r.ImGui_TextColored(ctx, COLORS.text_dim, string.format("X:%.0f%% Y:%.0f%%", s.xy_x*100, s.xy_y*100))
    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- CORNER MIXER (Krotos-style)
-- =========================================================
function Gui.DrawCornerMixer(ctx, Core)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "CORNER MIXER")

    -- Enable checkbox
    local mix_ch, mix_v = r.ImGui_Checkbox(ctx, "Enable", Core.Project.xy_mixer_enabled)
    if mix_ch then Core.Project.xy_mixer_enabled = mix_v end

    if not Core.Project.xy_mixer_enabled then
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Disabled")
        r.ImGui_EndGroup(ctx)
        return
    end

    -- Corner assignments (2x2 grid)
    local corners = Core.Project.xy_corners
    local k = Core.Project.keys[Core.Project.selected_note]

    -- Build set options list
    local set_options = {"--"}
    for i = 1, 16 do
        local has_data = k and k.sets[i] and #k.sets[i].events > 0
        table.insert(set_options, "S" .. i .. (has_data and "*" or ""))
    end

    -- Helper function for corner dropdown
    local function CornerDropdown(corner_key)
        local current_idx = corners[corner_key] or 0
        local current_label = current_idx > 0 and ("S" .. current_idx) or "--"
        r.ImGui_SetNextItemWidth(ctx, 50)
        if r.ImGui_BeginCombo(ctx, "##" .. corner_key, current_label) then
            if r.ImGui_Selectable(ctx, "--", current_idx == 0) then
                corners[corner_key] = nil
            end
            for i = 1, 16 do
                local has_data = k and k.sets[i] and #k.sets[i].events > 0
                local lbl = "S" .. i .. (has_data and " *" or "")
                if r.ImGui_Selectable(ctx, lbl, current_idx == i) then
                    corners[corner_key] = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
    end

    -- Top row: TL - TR
    r.ImGui_Text(ctx, "TL:")
    r.ImGui_SameLine(ctx)
    CornerDropdown("top_left")
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, 20, 0)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "TR:")
    r.ImGui_SameLine(ctx)
    CornerDropdown("top_right")

    -- Bottom row: BL - BR
    r.ImGui_Text(ctx, "BL:")
    r.ImGui_SameLine(ctx)
    CornerDropdown("bottom_left")
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, 20, 0)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "BR:")
    r.ImGui_SameLine(ctx)
    CornerDropdown("bottom_right")

    r.ImGui_Separator(ctx)

    -- Mode selector
    r.ImGui_Text(ctx, "Mode:")
    r.ImGui_SetNextItemWidth(ctx, 120)
    local mixer_modes = {"Post-FX Balance", "Real-time Insert", "Vector Record"}
    if r.ImGui_BeginCombo(ctx, "##mixmode", mixer_modes[Core.Project.xy_mixer_mode + 1]) then
        for i = 0, 2 do
            if r.ImGui_Selectable(ctx, mixer_modes[i + 1], Core.Project.xy_mixer_mode == i) then
                Core.Project.xy_mixer_mode = i
            end
        end
        r.ImGui_EndCombo(ctx)
    end

    -- Mode-specific controls
    if Core.Project.xy_mixer_mode == 0 then
        -- POST-FX BALANCE
        if r.ImGui_Button(ctx, "Apply to Selection", 120, 0) then
            local s = k and k.sets[Core.Project.selected_set]
            if s then
                Core.ApplyCornerMixToSelection(s.xy_x, s.xy_y)
            end
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Apply current XY mix to selected items")
        end

    elseif Core.Project.xy_mixer_mode == 1 then
        -- REAL-TIME INSERT
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Use K to insert with mix")

    elseif Core.Project.xy_mixer_mode == 2 then
        -- VECTOR RECORDING
        if not Core.VectorRecording.active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x44AA44FF)
            if r.ImGui_Button(ctx, "● REC", 55, 0) then
                Core.StartVectorRecording()
            end
            r.ImGui_PopStyleColor(ctx, 1)
        else
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA4444FF)
            if r.ImGui_Button(ctx, "■ STOP", 55, 0) then
                Core.StopVectorRecording()
            end
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0xFF4444FF, "Recording...")
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Record XY at markers during playback")
        end
    end

    -- Show current weights
    local s = k and k.sets[Core.Project.selected_set]
    if s then
        local w = Core.CalculateCornerWeights(s.xy_x, s.xy_y)
        r.ImGui_TextColored(ctx, COLORS.text_dim,
            string.format("TL:%.0f TR:%.0f BL:%.0f BR:%.0f",
                w.top_left*100, w.top_right*100, w.bottom_left*100, w.bottom_right*100))
    end

    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- MAIN CONTROLS
-- =========================================================
function Gui.DrawMainControls(ctx, Core)
    if Gui.BeginChildBox(ctx, "MA", 0, 280) then
        -- Main 2-column layout: Left (Settings) | Right (Quick Control)
        if r.ImGui_BeginTable(ctx, "MainLayout", 2) then
            r.ImGui_TableSetupColumn(ctx, "Settings", r.ImGui_TableColumnFlags_WidthStretch(), 2.5)
            r.ImGui_TableSetupColumn(ctx, "QuickCtrl", r.ImGui_TableColumnFlags_WidthFixed(), 220)
            r.ImGui_TableNextRow(ctx)

            -- LEFT SIDE: Deep Settings (3 sub-columns)
            r.ImGui_TableNextColumn(ctx)
            local k = Core.Project.keys[Core.Project.selected_note]
            if k then
                local s = k.sets[Core.Project.selected_set]

                if r.ImGui_BeginTable(ctx, "SettingsGrid", 3) then
                    r.ImGui_TableSetupColumn(ctx, "SC1", r.ImGui_TableColumnFlags_WidthStretch(), 1)
                    r.ImGui_TableSetupColumn(ctx, "SC2", r.ImGui_TableColumnFlags_WidthStretch(), 1)
                    r.ImGui_TableSetupColumn(ctx, "SC3", r.ImGui_TableColumnFlags_WidthStretch(), 1.2)
                    r.ImGui_TableNextRow(ctx)

                    -- SUB-COL 1: Capture / Base
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_TextColored(ctx, COLORS.active_key, "SET " .. Core.Project.selected_set)

                    if r.ImGui_Button(ctx, "CAPTURE (+)", 140, 40) then
                        Core.CaptureToActiveSet()
                    end

                    local fc_ch, fc_v = r.ImGui_Checkbox(ctx, "Cursor Follow Mouse", Core.FollowMouseCursor)
                    if fc_ch then Core.FollowMouseCursor = fc_v end

                    r.ImGui_Text(ctx, "Gap:")
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 60)
                    local gt, gtv = r.ImGui_DragDouble(ctx, "##gap", Core.Project.group_thresh, 0.01, 0.01, 2.0, "%.2fs")
                    if gt then Core.Project.group_thresh = gtv end

                    r.ImGui_Text(ctx, "Start:")
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 90)
                    if r.ImGui_BeginCombo(ctx, "##trg", ({"Key Down", "Key Up"})[s.trigger_on+1]) then
                        if r.ImGui_Selectable(ctx, "Key Down", s.trigger_on==0) then s.trigger_on=0 end
                        if r.ImGui_Selectable(ctx, "Key Up", s.trigger_on==1) then s.trigger_on=1 end
                        r.ImGui_EndCombo(ctx)
                    end

                    local _, b = r.ImGui_Checkbox(ctx, "Snap Offset", Core.Project.use_snap_align)
                    if _ then Core.Project.use_snap_align=b end

                    r.ImGui_Text(ctx, "Dest:")
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 100)
                    if r.ImGui_BeginCombo(ctx, "##pm", ({"Track(s)", "FIPM", "Fixed Lanes"})[Core.Project.placement_mode+1]) then
                        if r.ImGui_Selectable(ctx, "Track(s)", Core.Project.placement_mode==0) then Core.Project.placement_mode=0 end
                        if r.ImGui_Selectable(ctx, "FIPM", Core.Project.placement_mode==1) then Core.Project.placement_mode=1 end
                        if r.ImGui_Selectable(ctx, "Fixed Lanes", Core.Project.placement_mode==2) then Core.Project.placement_mode=2 end
                        r.ImGui_EndCombo(ctx)
                    end
                    if s then r.ImGui_Text(ctx, "Count: " .. #s.events) end

                    -- SUB-COL 2: Modes
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_Text(ctx, "TRIGGER MODE")
                    r.ImGui_SetNextItemWidth(ctx, 140)
                    if r.ImGui_BeginCombo(ctx, "##tm", ({"One Shot", "Sequencer", "Smart Loop"})[Core.Project.trigger_mode+1]) then
                        if r.ImGui_Selectable(ctx, "One Shot", false) then Core.Project.trigger_mode=0 end
                        if r.ImGui_Selectable(ctx, "Sequencer", false) then Core.Project.trigger_mode=1 end
                        if r.ImGui_Selectable(ctx, "Smart Loop", false) then Core.Project.trigger_mode=2 end
                        r.ImGui_EndCombo(ctx)
                    end

                    if s and Core.Project.trigger_mode == 0 then
                        r.ImGui_Dummy(ctx, 0, 5)
                        r.ImGui_Text(ctx, "Event Select:")
                        r.ImGui_SetNextItemWidth(ctx, 140)
                        local oneshot_modes = {"Sequential", "Random"}
                        if r.ImGui_BeginCombo(ctx, "##osm", oneshot_modes[(s.oneshot_mode or 1) + 1]) then
                            if r.ImGui_Selectable(ctx, "Sequential", s.oneshot_mode == 0) then s.oneshot_mode = 0 end
                            if r.ImGui_Selectable(ctx, "Random", s.oneshot_mode == 1) then s.oneshot_mode = 1 end
                            r.ImGui_EndCombo(ctx)
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Sequential: Round-robin\nRandom: Random with no repeat")
                        end
                    elseif s and Core.Project.trigger_mode == 1 then
                        r.ImGui_Dummy(ctx, 0, 10)
                        Gui.DrawSequencerParams(ctx, s, Core)
                    elseif s and Core.Project.trigger_mode == 2 then
                        r.ImGui_Dummy(ctx, 0, 10)
                        Gui.DrawSmartLoopParams(ctx, s)
                    end

                    -- SUB-COL 3: Randomize Matrix
                    r.ImGui_TableNextColumn(ctx)
                    if s then Gui.DrawModulationMatrix(ctx, s, Core) end

                    r.ImGui_EndTable(ctx)
                end

                -- RIGHT SIDE: Quick Control (XY Pad + Corner Mixer)
                r.ImGui_TableNextColumn(ctx)
                r.ImGui_TextColored(ctx, COLORS.accent, "QUICK CONTROL")
                r.ImGui_Separator(ctx)

                if s then
                    Gui.DrawXYPad(ctx, s, Core, 190)
                    r.ImGui_Spacing(ctx)
                    Gui.DrawCornerMixer(ctx, Core)
                end
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Separator(ctx)
end

return Gui
