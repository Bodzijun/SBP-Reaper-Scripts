---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local SettingsUI = {}

local r = reaper

local SIDE_LIST = { 'A (Green)', 'B (Blue)', 'LFO (Yellow)', 'MSEG (Purple)' }
local COL_ACCENT = 0x2D8C6DFF

-- Local helper to clamp values
local function clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

-- Draw the UI for creating a new binding
function SettingsUI.DrawBindingCreate(ctx, app, track, BindingRegistry, markDirty, SIDE_LIST, getParams, refreshFXCache)
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

-- Draw the list of existing bindings
function SettingsUI.DrawBindings(ctx, app, track, BindingRegistry, markDirty, SIDE_LIST, getParams, refreshFXCache,
                                 drawHeader)
    drawHeader('Parameter Bindings')
    SettingsUI.DrawBindingCreate(ctx, app, track, BindingRegistry, markDirty, SIDE_LIST, getParams, refreshFXCache)

    for i = #app.state.bindings, 1, -1 do
        local b = app.state.bindings[i]
        r.ImGui_PushID(ctx, i)
        local c0, v0 = r.ImGui_Checkbox(ctx, 'On##bind', b.enabled)
        if c0 then
            b.enabled = v0; markDirty()
        end
        r.ImGui_SameLine(ctx, 0, 4)
        r.ImGui_TextColored(ctx, 0xA8A8A8FF,
            (b.label ~= '' and b.label or (b.fx_name .. ' :: ' .. b.param_name)):sub(1, 30))

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
        if c1 then
            b.invert = v1; markDirty()
        end
        r.ImGui_SameLine(ctx, 0, 4)

        r.ImGui_SetNextItemWidth(ctx, 70)
        local c2, v2 = r.ImGui_SliderDouble(ctx, 'Min##bind_' .. tostring(i), b.min, 0.0, 1.0)
        if c2 then
            b.min = v2; markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            b.min = 0.0; markDirty()
        end
        r.ImGui_SameLine(ctx, 0, 4)

        r.ImGui_SetNextItemWidth(ctx, 70)
        local c3, v3 = r.ImGui_SliderDouble(ctx, 'Max##bind_' .. tostring(i), b.max, 0.0, 1.0)
        if c3 then
            b.max = v3; markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            b.max = 1.0; markDirty()
        end
        r.ImGui_SameLine(ctx, 0, 4)

        r.ImGui_SetNextItemWidth(ctx, 70)
        local c4, v4 = r.ImGui_SliderDouble(ctx, 'Curve##bind_' .. tostring(i), b.curve, 0.1, 4.0)
        if c4 then
            b.curve = v4; markDirty()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            b.curve = 1.0; markDirty()
        end
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

-- Draw the global options window
function SettingsUI.DrawOptionsWindow(ctx, app, interaction, markDirty)
    if not interaction.options_open then return end

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 12)
    r.ImGui_SetNextWindowPos(ctx, 150, 100, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSize(ctx, 380, 360, r.ImGui_Cond_FirstUseEver())

    local visible, open = r.ImGui_Begin(ctx, 'Options', true)
    if not open then
        interaction.options_open = false
    end

    if visible then
        -- Randomization options
        if r.ImGui_CollapsingHeader(ctx, 'Randomization', r.ImGui_TreeNodeFlags_DefaultOpen()) then
            r.ImGui_Dummy(ctx, 0, 4)
            local rnd = app.state.random

            local c1, v1 = r.ImGui_Checkbox(ctx, 'Link A##opt_link_a', rnd.pad_a)
            if c1 then
                rnd.pad_a = v1; markDirty()
            end
            r.ImGui_SameLine(ctx, 150)
            local c2, v2 = r.ImGui_Checkbox(ctx, 'Link B##opt_link_b', rnd.pad_b)
            if c2 then
                rnd.pad_b = v2; markDirty()
            end

            r.ImGui_Dummy(ctx, 0, 2)

            local c_ext, v_ext = r.ImGui_Checkbox(ctx, 'Ext##opt_ext', rnd.external)
            if c_ext then
                rnd.external = v_ext; markDirty()
            end
            r.ImGui_SameLine(ctx, 150)
            local c5, v5 = r.ImGui_Checkbox(ctx, 'М. LFO##opt_lfo', rnd.lfo)
            if c5 then
                rnd.lfo = v5; markDirty()
            end

            local c7, v7 = r.ImGui_Checkbox(ctx, 'М. MSEG##opt_mseg', rnd.mseg)
            if c7 then
                rnd.mseg = v7; markDirty()
            end
            r.ImGui_SameLine(ctx, 150)
            local c8, v8 = r.ImGui_Checkbox(ctx, 'LFO##opt_ind_lfo', rnd.ind_lfo)
            if c8 then
                rnd.ind_lfo = v8; markDirty()
            end

            local c9, v9 = r.ImGui_Checkbox(ctx, 'MSEG##opt_ind_mseg', rnd.ind_mseg)
            if c9 then
                rnd.ind_mseg = v9; markDirty()
            end

            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 4)

            r.ImGui_Text(ctx, 'Random Seed:')
            r.ImGui_SameLine(ctx, 100)
            r.ImGui_SetNextItemWidth(ctx, 150)
            local c_seed, v_seed = r.ImGui_InputInt(ctx, '##random_seed', app.state.setup.random_seed or 1001)
            if c_seed then
                app.state.setup.random_seed = v_seed
                markDirty()
            end
        end

        -- Render options
        r.ImGui_Dummy(ctx, 0, 8)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)
        if r.ImGui_CollapsingHeader(ctx, 'Render', r.ImGui_TreeNodeFlags_DefaultOpen()) then
            r.ImGui_Dummy(ctx, 0, 4)

            -- Trim mode option
            if app.state.setup.trim_mode == nil then
                app.state.setup.trim_mode = true
            end
            local c_trim, v_trim = r.ImGui_Checkbox(ctx, 'Trim mode (clear existing points)', app.state.setup.trim_mode)
            if c_trim then
                app.state.setup.trim_mode = v_trim
                markDirty()
            end
            r.ImGui_Dummy(ctx, 0, 4)

            -- Render channels
            r.ImGui_Text(ctx, 'Channel count:')
            r.ImGui_SameLine(ctx, 120)
            local ch_items = '2 (Stereo)\04\06\08\0'
            local ch_idx = 0
            local ch_val = tonumber(app.state.setup.render_channels or 2)
            if ch_val == 4 then ch_idx = 1 elseif ch_val == 6 then ch_idx = 2 elseif ch_val == 8 then ch_idx = 3 end
            local c_ch, v_ch = r.ImGui_Combo(ctx, '##render_channels', ch_idx, ch_items)
            if c_ch then
                local ch_map = { 2, 4, 6, 8 }
                app.state.setup.render_channels = ch_map[v_ch + 1] or 2
                markDirty()
            end
            r.ImGui_Dummy(ctx, 0, 4)
            -- Render tail
            r.ImGui_Text(ctx, 'Tail (sec):')
            r.ImGui_SameLine(ctx, 120)
            r.ImGui_SetNextItemWidth(ctx, 100)
            local tail_val = tonumber(app.state.setup.render_tail_sec or 0)
            local c_tail, v_tail = r.ImGui_InputDouble(ctx, '##render_tail', tail_val, 0.1, 0.5, '%.2f')
            if c_tail then
                app.state.setup.render_tail_sec = math.max(0, v_tail)
                markDirty()
            end
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
        end

        -- Morph options
        r.ImGui_Dummy(ctx, 0, 8)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)
        if r.ImGui_CollapsingHeader(ctx, 'Morph', r.ImGui_TreeNodeFlags_DefaultOpen()) then
            r.ImGui_Dummy(ctx, 0, 4)

            local c_mute, v_mute = r.ImGui_Checkbox(ctx, 'Copy and mute original', app.state.setup.morph_mute_originals)
            if c_mute then
                app.state.setup.morph_mute_originals = v_mute
                markDirty()
            end

            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
        end

        r.ImGui_End(ctx)
    end

    r.ImGui_PopStyleVar(ctx, 2)
end

return SettingsUI
