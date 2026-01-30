-- ReaSFX GUI Module
-- v2.0 - Extracted GUI logic
local Gui = {}
local r = reaper

-- =========================================================
-- COLORS (matched to sbp_AmbientGen style)
-- =========================================================
local COLORS = {
    -- Darker theme matching sbp_AmbientGen
    accent = 0x226757FF,       -- C_GEN_TEAL
    accent_hover = 0x29D0A9FF, -- C_GEN_HOVR
    bg = 0x1E1E1EFF,           -- darker main background
    bg_panel = 0x181818FF,     -- darker panel/title
    bg_input = 0x151515FF,     -- darker input fields
    bg_child = 0x1E1E1EFF,     -- same as bg
    border = 0x2A2A2AFF,       -- subtle border
    btn = 0x333333FF,          -- darker buttons
    btn_hover = 0x404040FF,    -- button hover
    text = 0xDEDEDEFF,         -- C_TEXT
    white_key = 0xCCCCCCFF,
    black_key = 0x0A0A0AFF,
    active_key = 0xD46A3FFF,
    active_multi = 0xD4AA3FFF,
    mute_active = 0xD4AA3FFF,
    text_dim = 0x707070FF,     -- dimmer text
    xy_bg = 0x151515FF,        -- match frame bg
    xy_grid = 0x333333FF,      -- match btn color
    layer_col = 0x22675799,
    smart_col = 0x750D5C99,
    insert_btn = 0x226757FF,   -- teal
    capture_btn = 0xD4753FFF,
    capture_hover = 0xE08545FF
}

Gui.COLORS = COLORS

-- =========================================================
-- THEME
-- =========================================================
function Gui.BeginChildBox(ctx, label, w, h)
    -- No border for flat design like sbp_AmbientGen
    return r.ImGui_BeginChild(ctx, label, w, h, 0, 0)
end

function Gui.PushTheme(ctx)
    if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then return end

    -- Colors (21 total) - matched to sbp_AmbientGen style
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x00000000)  -- transparent child bg for flat look
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_MenuBarBg(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLORS.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COLORS.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COLORS.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLORS.bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), COLORS.btn)      -- grey, not blue
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLORS.btn_hover) -- grey, not blue
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLORS.accent_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), COLORS.border)

    -- Style vars - rounded corners, tighter spacing (7 total)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)
end

function Gui.PopTheme(ctx)
    r.ImGui_PopStyleColor(ctx, 21)
    r.ImGui_PopStyleVar(ctx, 7)
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

-- Note name helper
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local function note_name(n)
  local octave = math.floor(n / 12) - 1
  local name = NOTE_NAMES[(n % 12) + 1]
  return string.format("%s%d", name, octave)
end

function Gui.DrawKeyboard(ctx, Core, CONFIG)
    -- Compact keyboard 36-62
    local base_note = 36
    local num_keys = 62 - 36 + 1
    local key_w = 24  -- narrower keys
    local key_h = 55  -- shorter keys
    local kb_w = num_keys * key_w + 2
    r.ImGui_BeginGroup(ctx)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 0)
    for i = 0, num_keys - 1 do
        local note = base_note + i
        local is_active = (Core.Project.selected_note == note)
        local n = note % 12
        local is_black = (n==1 or n==3 or n==6 or n==8 or n==10)
        local col = is_black and COLORS.black_key or COLORS.white_key
        if is_active then col = COLORS.active_key end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (not is_black or is_active) and 0x000000FF or 0xFFFFFFFF)
        r.ImGui_PushID(ctx, i)
        if r.ImGui_Button(ctx, note_name(note), key_w, key_h) then
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
    r.ImGui_TextColored(ctx, COLORS.accent, "Selected Key: " .. note_name(Core.Project.selected_note or base_note))
end

-- =========================================================
-- SETS TABS (with per-set MIDI controls)
-- =========================================================
local MIDI_COLORS = {
    slider_bg = 0x151515FF,      -- frame background
    slider_fill = 0x226757FF,    -- match accent
    slider_fill_invert = 0x755C0DFF,
    midi_enabled = 0x226757FF,   -- match accent
    midi_disabled = 0x333333FF   -- subtle gray
}


function Gui.DrawSetsTabs(ctx, Core)
    r.ImGui_Separator(ctx)
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return end

    -- Show active set info (tag + track)
    local active_set = k.sets[Core.Project.selected_set]
    if active_set then
        local tag_label = Core.GetSetLabel(Core.Project.selected_set, active_set)
        local track_info = ""
        if active_set.target_track_name and active_set.target_track_name ~= "" then
            track_info = " → " .. active_set.target_track_name
        elseif active_set.target_track and active_set.target_track > 0 then
            track_info = " → Track " .. active_set.target_track
        end
        r.ImGui_TextColored(ctx, COLORS.active_key, "Active: " .. tag_label .. track_info)
    end

    -- Narrow velocity columns (compact)
    local col_width = 32  -- narrow fixed width
    local label_w = 80    -- label column for text
    local table_w = col_width * 16 + label_w + 8

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

    -- ROW 1: Set buttons (S1-S16) + label "Сети"
    r.ImGui_SetNextItemWidth(ctx, table_w)
    if r.ImGui_BeginTable(ctx, "SetsGrid", 17, table_flags) then
        -- Setup columns
        for i = 1, 16 do
            r.ImGui_TableSetupColumn(ctx, "C"..i, r.ImGui_TableColumnFlags_WidthFixed(), col_width)
        end
        r.ImGui_TableSetupColumn(ctx, "Label", r.ImGui_TableColumnFlags_WidthFixed(), label_w)

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
            if r.ImGui_Button(ctx, "S"..i, col_width, 18) then
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
                local tip = "Click: Select\nShift+Click: Add Layer\nAlt+Click: Clear"
                if s.tag and s.tag ~= "" then
                    tip = s.tag .. "\n" .. tip
                end
                if s.target_track_name and s.target_track_name ~= "" then
                    tip = tip .. "\nTrack: " .. s.target_track_name
                elseif s.target_track and s.target_track > 0 then
                    tip = tip .. "\nTrack: " .. s.target_track
                end
                r.ImGui_SetTooltip(ctx, tip)
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
        local slider_height = 45  -- compact height
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
                if r.ImGui_Button(ctx, "X", col_width-4, 16) then
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
                if r.ImGui_Button(ctx, "I", col_width-4, 16) then
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
  local table_flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()
  local table_opened = r.ImGui_BeginTable(ctx, "ModMatrix", 3, table_flags, 240)
  if not table_opened then
    if Core and Core.Log then Core.Log("[GUI] Failed to open ModMatrix table") end
    return
  end
  r.ImGui_TableSetupColumn(ctx, "Param", r.ImGui_TableColumnFlags_WidthFixed(), 55)
  r.ImGui_TableSetupColumn(ctx, "Event", r.ImGui_TableColumnFlags_WidthStretch(), 1)
  r.ImGui_TableSetupColumn(ctx, "Set", r.ImGui_TableColumnFlags_WidthStretch(), 1)
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
  Rw("Volume", s.rnd_vol, Core.Project.g_rnd_vol, 12, function(v)s.rnd_vol=v end, function(v)Core.Project.g_rnd_vol=v end)
  Rw("Pitch", s.rnd_pitch, Core.Project.g_rnd_pitch, 12, function(v)s.rnd_pitch=v end, function(v)Core.Project.g_rnd_pitch=v end)
  Rw("Pan", s.rnd_pan, Core.Project.g_rnd_pan, 100, function(v)s.rnd_pan=v end, function(v)Core.Project.g_rnd_pan=v end)
  Rw("Position", s.rnd_pos, Core.Project.g_rnd_pos, 0.2, function(v)s.rnd_pos=v end, function(v)Core.Project.g_rnd_pos=v end)
  Rw("Desync", s.rnd_offset, Core.Project.g_rnd_offset, 0.5, function(v)s.rnd_offset=v end, function(v)Core.Project.g_rnd_offset=v end)
  Rw("Fade", s.rnd_fade, Core.Project.g_rnd_fade, 0.5, function(v)s.rnd_fade=v end, function(v)Core.Project.g_rnd_fade=v end)
  Rw("Speed", s.rnd_len, Core.Project.g_rnd_len, 1.0, function(v)s.rnd_len=v end, function(v)Core.Project.g_rnd_len=v end)
  r.ImGui_EndTable(ctx)
end

-- =========================================================
-- SMART LOOP PARAMS
-- =========================================================
function Gui.DrawSmartLoopParams(ctx, s, kb_w)
  r.ImGui_BeginGroup(ctx)
  r.ImGui_TextDisabled(ctx, "SMART LOOP")
  r.ImGui_Text(ctx, "Crossfade")
  r.ImGui_SetNextItemWidth(ctx, kb_w and math.min(140, kb_w/3-10) or 140)
  local cf_changed, cf_val = r.ImGui_SliderDouble(ctx, "##slcf", s.loop_crossfade or 0.003, 0.001, 0.100, "%.3fs")
  if cf_changed then s.loop_crossfade = cf_val end
  r.ImGui_Text(ctx, "Sync Mode")
  r.ImGui_SetNextItemWidth(ctx, kb_w and math.min(140, kb_w/3-10) or 140)
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
-- ATMOSPHERE LOOP PARAMS
-- =========================================================
function Gui.DrawAtmosphereParams(ctx, s, avail_w)
  r.ImGui_BeginGroup(ctx)
  r.ImGui_TextDisabled(ctx, "ATMOSPHERE LOOP")

  -- Crossfade duration
  r.ImGui_Text(ctx, "Crossfade")
  r.ImGui_SetNextItemWidth(ctx, avail_w and math.min(140, avail_w/3-10) or 140)
  local cf_changed, cf_val = r.ImGui_SliderDouble(ctx, "##atmocf", s.atmo_crossfade or 2.0, 0.1, 10.0, "%.1fs")
  if cf_changed then s.atmo_crossfade = cf_val end

  -- Random toggle
  local rnd_ch, rnd_v = r.ImGui_Checkbox(ctx, "Random Select", s.atmo_random ~= false)
  if rnd_ch then s.atmo_random = rnd_v end

  r.ImGui_TextColored(ctx, COLORS.text_dim, "Fills Time Selection")
  r.ImGui_TextColored(ctx, COLORS.text_dim, "with overlapping loops")

  r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- SEQUENCER PARAMS
-- =========================================================
function Gui.DrawSequencerParams(ctx, s, Core, kb_w)
  r.ImGui_BeginGroup(ctx)
  r.ImGui_TextDisabled(ctx, "SEQ SETTINGS")
  r.ImGui_SetNextItemWidth(ctx, kb_w and math.min(140, kb_w/3-10) or 140)
  if r.ImGui_BeginCombo(ctx, "##sqm", ({"Repeat First", "Random Pool", "Stitch Random"})[s.seq_mode+1]) then
    if r.ImGui_Selectable(ctx, "Repeat First", s.seq_mode==0) then s.seq_mode=0 end
    if r.ImGui_Selectable(ctx, "Random Pool", s.seq_mode==1) then s.seq_mode=1 end
    if r.ImGui_Selectable(ctx, "Stitch Random", s.seq_mode==2) then s.seq_mode=2 end
    r.ImGui_EndCombo(ctx)
  end
  if s.seq_mode ~= 2 then
    local function Drag(lbl, val, step, cb)
      r.ImGui_Text(ctx, lbl)
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, kb_w and math.min(70, kb_w/6-10) or 70)
      local ch, nv = r.ImGui_DragDouble(ctx, "##"..lbl, val, step, 0, 100, "%.3f")
      if ch then cb(nv) end
      return ch
    end
    local changed = false
    if Drag("Rate", s.seq_rate, 0.005, function(v) s.seq_rate = math.max(0.01, v) end) then changed = true end
    if Drag("Len", s.seq_len, 0.005, function(v) s.seq_len = math.max(0.01, v) end) then changed = true end
    if Drag("Fade", s.seq_fade, 0.001, function(v) s.seq_fade = math.max(0.001, v) end) then changed = true end
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
-- Mode 0: Pan/Vol - direct control for step work
-- Mode 1: Pitch/Rate - direct control for speed/pitch
-- Mode 2: Custom - configurable direct control (right-click to assign)
local XY_MODES = {
    { name = "Pan/Vol", labelY_top = "+12", labelY_bot = "-inf", labelX_left = "L", labelX_right = "R" },
    { name = "Pitch/Rate", labelY_top = "+12st", labelY_bot = "-12st", labelX_left = "0.5x", labelX_right = "2x" },
    { name = "Custom", labelY_top = "Y", labelY_bot = "", labelX_left = "", labelX_right = "X", dynamic = true }
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

    -- Lighter background with very subtle quadrant highlighting
    local quad_base = 0x252525FF      -- lighter base
    local quad_active = 0x2A2A30FF    -- very subtle highlight

    local qx = s.xy_x >= 0.5 and 1 or 0
    local qy = s.xy_y >= 0.5 and 1 or 0

    -- Draw quadrants
    local tl_col = (qx == 0 and qy == 1) and quad_active or quad_base
    local tr_col = (qx == 1 and qy == 1) and quad_active or quad_base
    local bl_col = (qx == 0 and qy == 0) and quad_active or quad_base
    local br_col = (qx == 1 and qy == 0) and quad_active or quad_base

    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+half, p[2]+half, tl_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2], p[1]+size, p[2]+half, tr_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2]+half, p[1]+half, p[2]+size, bl_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2]+half, p[1]+size, p[2]+size, br_col, 4)

    -- Border
    r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+size, p[2]+size, 0x3A3A3AFF, 4)

    -- Guide circles (more visible for blind zones)
    local circle_col = 0x40404080  -- more visible
    r.ImGui_DrawList_AddCircle(dl, p[1]+half, p[2]+half, half*0.35, circle_col, 32)
    r.ImGui_DrawList_AddCircle(dl, p[1]+half, p[2]+half, half*0.7, circle_col, 32)

    -- Center lines (more visible)
    r.ImGui_DrawList_AddLine(dl, p[1]+half, p[2], p[1]+half, p[2]+size, 0x505050FF)
    r.ImGui_DrawList_AddLine(dl, p[1], p[2]+half, p[1]+size, p[2]+half, 0x505050FF)

    -- Diagonal guides
    r.ImGui_DrawList_AddLine(dl, p[1], p[2], p[1]+size, p[2]+size, 0x30303060)
    r.ImGui_DrawList_AddLine(dl, p[1]+size, p[2], p[1], p[2]+size, 0x30303060)

    -- Labels based on mode - positioned along center cross
    local labels = XY_MODES[mode+1]
    -- Y axis: top label (centered horizontally on top of center line)
    if labels.labelY_top then
        r.ImGui_DrawList_AddText(dl, p[1]+half-12, p[2]+2, 0xAAAAAAFF, labels.labelY_top)
    end
    -- Y axis: bottom label (centered horizontally on bottom of center line)
    if labels.labelY_bot then
        r.ImGui_DrawList_AddText(dl, p[1]+half-12, p[2]+size-14, 0xAAAAAAFF, labels.labelY_bot)
    end
    -- X axis: left label (centered vertically on left of center line)
    if labels.labelX_left then
        r.ImGui_DrawList_AddText(dl, p[1]+2, p[2]+half-6, 0xAAAAAAFF, labels.labelX_left)
    end
    -- X axis: right label (centered vertically on right of center line)
    if labels.labelX_right then
        r.ImGui_DrawList_AddText(dl, p[1]+size-20, p[2]+half-6, 0xAAAAAAFF, labels.labelX_right)
    end

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

        -- Custom mode: direct parameter control (only in Custom mode)
        if mode == 2 then
            r.ImGui_Separator(ctx)
            r.ImGui_TextColored(ctx, COLORS.accent, "CUSTOM AXES")
            r.ImGui_TextColored(ctx, COLORS.text_dim, "Assign params to X/Y axes")

            -- Initialize custom tables if needed
            local function InitCustom(name, def_axis, def_min, def_max)
                if type(s[name]) ~= "table" then
                    s[name] = { axis = def_axis, min = def_min, max = def_max }
                end
            end
            InitCustom("custom_vol", 0, -12, 12)
            InitCustom("custom_pitch", 0, -12, 12)
            InitCustom("custom_pan", 1, -100, 100)
            InitCustom("custom_rate", 0, 0.5, 2.0)
            InitCustom("custom_pos", 0, -0.1, 0.1)
            InitCustom("custom_desync", 0, 0, 0.2)

            -- Helper for custom param row (always show all fields)
            local function CustomRow(label, field, unit)
                local cfg = s[field]
                r.ImGui_PushID(ctx, field)

                -- Axis selector
                local opts = {"--", "X", "Y"}
                r.ImGui_SetNextItemWidth(ctx, 30)
                if r.ImGui_BeginCombo(ctx, "##ax", opts[cfg.axis+1]) then
                    for ai = 0, 2 do
                        if r.ImGui_Selectable(ctx, opts[ai+1], cfg.axis == ai) then
                            cfg.axis = ai
                        end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_SameLine(ctx)

                -- Label
                r.ImGui_Text(ctx, label)
                r.ImGui_SameLine(ctx, 95)

                -- Min/Max - always show, but disabled if not assigned
                if cfg.axis == 0 then
                    r.ImGui_BeginDisabled(ctx)
                end

                r.ImGui_SetNextItemWidth(ctx, 40)
                local ch_min, v_min = r.ImGui_InputDouble(ctx, "##min", cfg.min, 0, 0, "%.1f")
                if ch_min then cfg.min = v_min end
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 40)
                local ch_max, v_max = r.ImGui_InputDouble(ctx, "##max", cfg.max, 0, 0, "%.1f")
                if ch_max then cfg.max = v_max end
                r.ImGui_SameLine(ctx)
                r.ImGui_TextColored(ctx, COLORS.text_dim, unit)

                if cfg.axis == 0 then
                    r.ImGui_EndDisabled(ctx)
                end

                r.ImGui_PopID(ctx)
            end

            CustomRow("Volume", "custom_vol", "dB")
            CustomRow("Pitch", "custom_pitch", "st")
            CustomRow("Pan", "custom_pan", "%")
            CustomRow("Rate", "custom_rate", "x")
            CustomRow("Position", "custom_pos", "s")
            CustomRow("Desync", "custom_desync", "s")

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, "Reset to Pan only", -1, 0) then
                s.custom_vol = { axis = 0, min = -12, max = 12 }
                s.custom_pitch = { axis = 0, min = -12, max = 12 }
                s.custom_pan = { axis = 1, min = -100, max = 100 }
                s.custom_rate = { axis = 0, min = 0.5, max = 2.0 }
                s.custom_pos = { axis = 0, min = -0.1, max = 0.1 }
                s.custom_desync = { axis = 0, min = 0, max = 0.2 }
            end
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

    -- Coordinates display based on mode
    local value_text = ""
    if mode == 0 then
        -- Pan/Vol mode
        local pan = (s.xy_x - 0.5) * 2  -- -1 to +1
        local vol_db = (s.xy_y - 0.5) * 24  -- -12 to +12 (centered at 0)
        if s.xy_y < 0.1 then vol_db = -60 end  -- near bottom = -inf
        local pan_str = pan < -0.05 and string.format("L%.0f%%", math.abs(pan)*100) or
                        pan > 0.05 and string.format("R%.0f%%", pan*100) or "C"
        value_text = string.format("%s  %.1fdB", pan_str, vol_db)
    elseif mode == 1 then
        -- Pitch/Rate mode
        local pitch = (s.xy_y - 0.5) * 24  -- -12 to +12 semitones
        local rate = 0.5 + s.xy_x * 1.5  -- 0.5x to 2x
        value_text = string.format("%.1fst  %.2fx", pitch, rate)
    else
        -- Custom mode: show assigned values
        local parts = {}
        local function AddCustomValue(field, label, fmt)
            if type(s[field]) == "table" and s[field].axis > 0 then
                local cfg = s[field]
                local axis_val = cfg.axis == 1 and s.xy_x or s.xy_y
                local val = cfg.min + axis_val * (cfg.max - cfg.min)
                table.insert(parts, string.format(label .. ":" .. fmt, val))
            end
        end
        AddCustomValue("custom_vol", "Vol", "%.0f")
        AddCustomValue("custom_pitch", "Pit", "%.1f")
        AddCustomValue("custom_pan", "Pan", "%.0f")
        AddCustomValue("custom_rate", "Rate", "%.2f")
        value_text = #parts > 0 and table.concat(parts, " ") or string.format("X:%.0f%% Y:%.0f%%", s.xy_x*100, s.xy_y*100)
    end
    r.ImGui_TextColored(ctx, COLORS.text_dim, value_text)
    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- SET MIXER PAD (dedicated pad for corner mixing)
-- =========================================================
function Gui.DrawSetMixerPad(ctx, Core, pad_size)
    local size = pad_size or 180
    local corners = Core.Project.xy_corners
    local k = Core.Project.keys[Core.Project.selected_note]

    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "SET MIXER")

    -- Center the pad
    local avail = r.ImGui_GetContentRegionAvail(ctx)
    if avail > size then
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail - size) * 0.5)
    end

    local p = { r.ImGui_GetCursorScreenPos(ctx) }
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local half = size / 2

    -- Lighter quadrant backgrounds with subtle highlighting
    local quad_empty = 0x252525FF       -- lighter empty
    local quad_assigned = 0x2A352AFF    -- subtle green tint when assigned

    -- Get colors for each corner (assigned vs empty)
    local tl_base = corners.top_left and quad_assigned or quad_empty
    local tr_base = corners.top_right and quad_assigned or quad_empty
    local bl_base = corners.bottom_left and quad_assigned or quad_empty
    local br_base = corners.bottom_right and quad_assigned or quad_empty

    -- Highlight active quadrant based on cursor position (very subtle)
    local mx, my = Core.Project.mixer_x, Core.Project.mixer_y
    local qx = mx >= 0.5 and 1 or 0
    local qy = my >= 0.5 and 1 or 0

    local tl_col = (qx == 0 and qy == 1) and (tl_base + 0x050508FF - 0xFF) or tl_base
    local tr_col = (qx == 1 and qy == 1) and (tr_base + 0x050508FF - 0xFF) or tr_base
    local bl_col = (qx == 0 and qy == 0) and (bl_base + 0x050508FF - 0xFF) or bl_base
    local br_col = (qx == 1 and qy == 0) and (br_base + 0x050508FF - 0xFF) or br_base

    -- Draw quadrants with rounded corners
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+half, p[2]+half, tl_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2], p[1]+size, p[2]+half, tr_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2]+half, p[1]+half, p[2]+size, bl_col, 4)
    r.ImGui_DrawList_AddRectFilled(dl, p[1]+half, p[2]+half, p[1]+size, p[2]+size, br_col, 4)

    -- Border
    r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+size, p[2]+size, 0x4A4A4AFF, 4)

    -- Guide circles (more visible)
    local circle_col = 0x40404080
    r.ImGui_DrawList_AddCircle(dl, p[1]+half, p[2]+half, half*0.35, circle_col, 32)
    r.ImGui_DrawList_AddCircle(dl, p[1]+half, p[2]+half, half*0.7, circle_col, 32)

    -- Center lines (more visible)
    r.ImGui_DrawList_AddLine(dl, p[1]+half, p[2], p[1]+half, p[2]+size, 0x505050FF)
    r.ImGui_DrawList_AddLine(dl, p[1], p[2]+half, p[1]+size, p[2]+half, 0x505050FF)

    -- Diagonal guides
    r.ImGui_DrawList_AddLine(dl, p[1], p[2], p[1]+size, p[2]+size, 0x30303060)
    r.ImGui_DrawList_AddLine(dl, p[1]+size, p[2], p[1], p[2]+size, 0x30303060)

    -- Corner labels (set assignments with tags)
    local function GetCornerLabel(corner_key)
        local set_idx = corners[corner_key]
        if set_idx and k and k.sets[set_idx] then
            local s = k.sets[set_idx]
            local has_data = #s.events > 0
            -- Use tag if available, otherwise S1, S2, etc.
            if s.tag and s.tag ~= "" then
                -- Truncate tag to 4 chars for display
                local short_tag = s.tag:sub(1, 4)
                return short_tag .. (has_data and "*" or "")
            end
            return "S" .. set_idx .. (has_data and "*" or "")
        end
        return "--"
    end

    r.ImGui_DrawList_AddText(dl, p[1]+4, p[2]+4, 0xAAAAAAFF, GetCornerLabel("top_left"))
    r.ImGui_DrawList_AddText(dl, p[1]+size-35, p[2]+4, 0xAAAAAAFF, GetCornerLabel("top_right"))
    r.ImGui_DrawList_AddText(dl, p[1]+4, p[2]+size-16, 0xAAAAAAFF, GetCornerLabel("bottom_left"))
    r.ImGui_DrawList_AddText(dl, p[1]+size-35, p[2]+size-16, 0xAAAAAAFF, GetCornerLabel("bottom_right"))

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx, "##mixerpad", size, size)
    local is_active = r.ImGui_IsItemActive(ctx)

    if r.ImGui_IsItemHovered(ctx) then
        if Core.Project.xy_mixer_mode == 0 then
            r.ImGui_SetTooltip(ctx, "Set Mixer: Drag to control track volumes\nEnable Latch/Write on tracks for automation")
        else
            r.ImGui_SetTooltip(ctx, "Drag to mix between corner sets")
        end
    end

    if is_active then
        local mx_screen, my_screen = r.ImGui_GetMousePos(ctx)
        Core.Project.mixer_x = math.max(0, math.min(1, (mx_screen - p[1]) / size))
        Core.Project.mixer_y = math.max(0, math.min(1, 1 - (my_screen - p[2]) / size))

        -- Set Mixer mode: apply to track volumes in real-time
        if Core.Project.xy_mixer_mode == 0 then
            Core.ApplySetMixerToTracks(Core.Project.mixer_x, Core.Project.mixer_y)
        end
    end

    -- Draw cursor position
    local px = p[1] + Core.Project.mixer_x * size
    local py = p[2] + (1 - Core.Project.mixer_y) * size
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, 8, COLORS.accent)
    r.ImGui_DrawList_AddLine(dl, px, p[2], px, p[2]+size, 0x66666666)
    r.ImGui_DrawList_AddLine(dl, p[1], py, p[1]+size, py, 0x66666666)

    -- Show weights
    local w = Core.CalculateCornerWeights(Core.Project.mixer_x, Core.Project.mixer_y)
    r.ImGui_TextColored(ctx, COLORS.text_dim,
        string.format("TL:%.0f%% TR:%.0f%% BL:%.0f%% BR:%.0f%%",
            w.top_left*100, w.top_right*100, w.bottom_left*100, w.bottom_right*100))

    -- Reset button
    if r.ImGui_Button(ctx, "Reset##mixer", 50, 0) then
        Core.Project.mixer_x = 0.5
        Core.Project.mixer_y = 0.5
    end

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

    -- Helper function for corner dropdown (shows tags)
    local function CornerDropdown(corner_key)
        local current_idx = corners[corner_key] or 0
        local current_label = "--"
        if current_idx > 0 and k and k.sets[current_idx] then
            local s = k.sets[current_idx]
            if s.tag and s.tag ~= "" then
                current_label = s.tag:sub(1, 5)
            else
                current_label = "S" .. current_idx
            end
        end
        r.ImGui_SetNextItemWidth(ctx, 55)
        if r.ImGui_BeginCombo(ctx, "##" .. corner_key, current_label) then
            if r.ImGui_Selectable(ctx, "--", current_idx == 0) then
                corners[corner_key] = nil
            end
            for i = 1, 16 do
                local s = k and k.sets[i]
                local has_data = s and #s.events > 0
                local lbl
                if s and s.tag and s.tag ~= "" then
                    lbl = s.tag:sub(1, 8) .. (has_data and " *" or "")
                else
                    lbl = "S" .. i .. (has_data and " *" or "")
                end
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

    -- SET MIXER: Write toggle
    if Core.Project.set_mixer_write then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xCC4444FF)
        if r.ImGui_Button(ctx, "● WRITE", 70, 0) then
            Core.Project.set_mixer_write = false
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, 0xFF6666FF, "Recording...")
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x446644FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x558855FF)
        if r.ImGui_Button(ctx, "WRITE", 70, 0) then
            Core.Project.set_mixer_write = true
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Play + drag")
    end

    r.ImGui_EndGroup(ctx)
end

-- =========================================================
-- MAIN CONTROLS
-- =========================================================

function Gui.DrawMainControls(ctx, Core, opts)
    opts = opts or {}
    if Gui.BeginChildBox(ctx, "MA", 0, 250) then  -- taller to avoid scroll
      -- Main 2-column layout: Left (Settings) | Right (Quick Control)
      if r.ImGui_BeginTable(ctx, "MainLayout", opts.no_quick and 1 or 2) then
        r.ImGui_TableSetupColumn(ctx, "Settings", r.ImGui_TableColumnFlags_WidthStretch(), 2.5)
        if not opts.no_quick then
          r.ImGui_TableSetupColumn(ctx, "QuickCtrl", r.ImGui_TableColumnFlags_WidthFixed(), 220)
        end
        r.ImGui_TableNextRow(ctx)
        -- LEFT SIDE: Deep Settings (3 sub-columns)
        r.ImGui_TableNextColumn(ctx)
        local k = Core.Project.keys[Core.Project.selected_note]
        if k then
          local s = k.sets[Core.Project.selected_set]
          -- Match keyboard width
          local base_note = 36
          local num_keys = 62 - 36 + 1
          local key_w = 26  -- match keyboard
          local kb_w = num_keys * key_w + 2
          local avail_w = r.ImGui_GetContentRegionAvail(ctx)
          if r.ImGui_BeginTable(ctx, "SettingsGrid", 3, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "SC1", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "SC2", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "SC3", r.ImGui_TableColumnFlags_WidthStretch(), 1.2)
            r.ImGui_TableNextRow(ctx)
            -- SUB-COL 1: Capture / Base
            r.ImGui_TableNextColumn(ctx)
            -- Set header: SET N [tag] (count)
            local set_header = "SET " .. Core.Project.selected_set
            if s.tag and s.tag ~= "" then
                set_header = set_header .. " [" .. s.tag .. "]"
            end
            set_header = set_header .. " (" .. #s.events .. ")"
            r.ImGui_TextColored(ctx, COLORS.active_key, set_header)

            -- Tag input
            r.ImGui_Text(ctx, "Tag:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.min(80, avail_w/4-10))
            local tag_ch, tag_v = r.ImGui_InputText(ctx, "##tag", s.tag or "", r.ImGui_InputTextFlags_None())
            if tag_ch then s.tag = tag_v end

            -- Track assignment
            r.ImGui_Text(ctx, "Track:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.min(80, avail_w/4-10))
            local track_options = {"Selected"}
            local track_count = r.CountTracks(0)
            for ti = 1, math.min(track_count, 32) do
                local track = r.GetTrack(0, ti - 1)
                local _, tname = r.GetTrackName(track)
                table.insert(track_options, ti .. ": " .. tname:sub(1, 8))
            end
            local current_track_idx = s.target_track or 0
            if r.ImGui_BeginCombo(ctx, "##trk", track_options[current_track_idx + 1] or "Selected") then
                for ti = 0, #track_options - 1 do
                    if r.ImGui_Selectable(ctx, track_options[ti + 1], current_track_idx == ti) then
                        s.target_track = ti
                        -- Also store track name for persistence
                        if ti > 0 then
                            local track = r.GetTrack(0, ti - 1)
                            if track then
                                local _, tname = r.GetTrackName(track)
                                s.target_track_name = tname
                            end
                        else
                            s.target_track_name = ""
                        end
                    end
                end
                r.ImGui_EndCombo(ctx)
            end

            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.capture_btn)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.capture_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xC06530FF)
            if r.ImGui_Button(ctx, "CAPTURE (+)", math.min(130, avail_w/3-10), 28) then
              Core.CaptureToActiveSet()
            end
            r.ImGui_PopStyleColor(ctx, 3)
            local fc_ch, fc_v = r.ImGui_Checkbox(ctx, "Cursor Follow Mouse", Core.FollowMouseCursor)
            if fc_ch then Core.FollowMouseCursor = fc_v end
            r.ImGui_Text(ctx, "Gap:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.min(60, avail_w/6-10))
            local gt, gtv = r.ImGui_DragDouble(ctx, "##gap", Core.Project.group_thresh, 0.01, 0.01, 2.0, "%.2fs")
            if gt then Core.Project.group_thresh = gtv end
            r.ImGui_Text(ctx, "Start:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.min(90, avail_w/6-10))
            if r.ImGui_BeginCombo(ctx, "##trg", ({"Key Down", "Key Up"})[s.trigger_on+1]) then
              if r.ImGui_Selectable(ctx, "Key Down", s.trigger_on==0) then s.trigger_on=0 end
              if r.ImGui_Selectable(ctx, "Key Up", s.trigger_on==1) then s.trigger_on=1 end
              r.ImGui_EndCombo(ctx)
            end
            local _, b = r.ImGui_Checkbox(ctx, "Snap Offset", Core.Project.use_snap_align)
            if _ then Core.Project.use_snap_align=b end
            r.ImGui_Text(ctx, "Dest:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.min(100, avail_w/3-10))
            if r.ImGui_BeginCombo(ctx, "##pm", ({"Track(s)", "FIPM", "Fixed Lanes"})[Core.Project.placement_mode+1]) then
              if r.ImGui_Selectable(ctx, "Track(s)", Core.Project.placement_mode==0) then Core.Project.placement_mode=0 end
              if r.ImGui_Selectable(ctx, "FIPM", Core.Project.placement_mode==1) then Core.Project.placement_mode=1 end
              if r.ImGui_Selectable(ctx, "Fixed Lanes", Core.Project.placement_mode==2) then Core.Project.placement_mode=2 end
              r.ImGui_EndCombo(ctx)
            end
            -- SUB-COL 2: Modes
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Text(ctx, "TRIGGER MODE")
            r.ImGui_SetNextItemWidth(ctx, math.min(140, avail_w/3-10))
            local trigger_modes = {"One Shot", "Sequencer", "Smart Loop", "Atmosphere"}
            if r.ImGui_BeginCombo(ctx, "##tm", trigger_modes[Core.Project.trigger_mode+1] or "One Shot") then
              if r.ImGui_Selectable(ctx, "One Shot", Core.Project.trigger_mode==0) then Core.Project.trigger_mode=0 end
              if r.ImGui_Selectable(ctx, "Sequencer", Core.Project.trigger_mode==1) then Core.Project.trigger_mode=1 end
              if r.ImGui_Selectable(ctx, "Smart Loop", Core.Project.trigger_mode==2) then Core.Project.trigger_mode=2 end
              if r.ImGui_Selectable(ctx, "Atmosphere", Core.Project.trigger_mode==3) then Core.Project.trigger_mode=3 end
              r.ImGui_EndCombo(ctx)
            end
            if s and Core.Project.trigger_mode == 0 then
              r.ImGui_Dummy(ctx, 0, 5)
              r.ImGui_Text(ctx, "Event Select:")
              r.ImGui_SetNextItemWidth(ctx, math.min(140, avail_w/3-10))
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
              -- Зменшено відступ між блоками
              r.ImGui_Dummy(ctx, 0, 2)
              Gui.DrawSequencerParams(ctx, s, Core, avail_w)
            elseif s and Core.Project.trigger_mode == 2 then
              -- Smart Loop params
              r.ImGui_Dummy(ctx, 0, 2)
              Gui.DrawSmartLoopParams(ctx, s, avail_w)
            elseif s and Core.Project.trigger_mode == 3 then
              -- Atmosphere Loop params
              r.ImGui_Dummy(ctx, 0, 2)
              Gui.DrawAtmosphereParams(ctx, s, avail_w)
            end
            -- SUB-COL 3: Randomize Matrix
            r.ImGui_TableNextColumn(ctx)
            -- Зменшено відступ між блоками
            r.ImGui_Dummy(ctx, 0, 2)
            if s then Gui.DrawModulationMatrix(ctx, s, Core) end
            r.ImGui_EndTable(ctx)
          end

          -- RIGHT SIDE: Quick Control (XY Pad + Corner Mixer)
          if not opts.no_quick then
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_TextColored(ctx, COLORS.accent, "QUICK CONTROL")
            r.ImGui_Separator(ctx)
            if s then
                Gui.DrawXYPad(ctx, s, Core, 190)
                r.ImGui_Spacing(ctx)
                Gui.DrawCornerMixer(ctx, Core)
            end
          end
        end
        r.ImGui_EndTable(ctx)
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_Separator(ctx)
end

return Gui
