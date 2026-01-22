-- @description ReaSFX Sampler (Modular)
-- @version 2.0.0
-- @author SBP & AI
-- @about
--   Advanced sampler for foley and sound effects in film post-production.
--   Features: Smart Loop, 16 Sets per Key, XY Performance Pad, Preset System
-- @changelog
--   v2.0.0 - Modular architecture, BuildSmartLoop implemented, Preset system added
-- @donation Donate via PayPal: mailto:bodzik@gmail.com

local r = reaper

-- === DEPENDENCY CHECK === --
if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("Please install ReaImGui via ReaPack", "Error", 0)
    return
end

-- === DETECT SCRIPT PATH === --
local script_path = ({r.get_action_context()})[2]
local script_dir = script_path:match("(.+[\\/])") or ""
local modules_dir = script_dir .. "modules" .. (package.config:sub(1,1) == "\\" and "\\" or "/")

-- === LOAD MODULES === --
package.path = package.path .. ";" .. modules_dir .. "?.lua"

local Core = require("Core")
local Gui = require("GUI")
local Preset = require("Preset")

-- === CONFIG === --
local CONFIG = {
    group_threshold = 0.5,
    global_key = 75,       -- 'K'
    base_note = 36,
    num_keys = 30,
    slot_width = 50,
    layer_height = 6
}

local has_js_api = r.APIExists('JS_VKeys_GetState')
local has_sws = r.APIExists('Xen_StartSourcePreview')

-- === ANTI-DING === --
if has_js_api then r.JS_VKeys_Intercept(CONFIG.global_key, 1) end

function ReleaseKeys()
    if has_js_api then r.JS_VKeys_Intercept(CONFIG.global_key, -1) end
end

r.atexit(ReleaseKeys)

-- === GLOBAL INPUT HANDLER === --
function HandleGlobalInput()
    if has_js_api then
        local state = r.JS_VKeys_GetState(0)
        local is_down = state:byte(CONFIG.global_key) ~= 0
        local cursor = r.GetPlayState()~=0 and r.GetPlayPosition() or r.GetCursorPosition()

        if is_down and not Core.Input.was_down then
            Core.KeyState.held = true
            Core.KeyState.start_pos = cursor
            Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 0)
        elseif not is_down and Core.Input.was_down then
            Core.KeyState.held = false
            Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 1)
            Core.SmartLoopRelease(Core.Project.selected_note, Core.Project.selected_set, Core.KeyState.start_pos, cursor)
        end

        Core.Input.was_down = is_down
    end
end

-- === AUTO-SAVE === --
local last_save_time = r.time_precise()
local AUTO_SAVE_INTERVAL = 30 -- seconds

function AutoSave()
    local now = r.time_precise()
    if (now - last_save_time) > AUTO_SAVE_INTERVAL then
        Preset.SaveProjectState(Core)
        last_save_time = now
    end
end

-- === MAIN LOOP === --
local ctx = nil

function Loop()
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        ctx = r.ImGui_CreateContext('ReaSFX_v2')
    end

    if ctx then
        if r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then
            r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
        end

        HandleGlobalInput()
        AutoSave()
        Core.UpdateMouseCursor()
        Core.PollMIDI()
        Core.PollVectorRecording()

        Gui.PushTheme(ctx)
        local v, o = r.ImGui_Begin(ctx, 'ReaSFX Sampler v2.0', true, r.ImGui_WindowFlags_MenuBar())

        if v then
            -- Menu Bar
            if r.ImGui_BeginMenuBar(ctx) then
                if r.ImGui_BeginMenu(ctx, "File") then
                    if r.ImGui_MenuItem(ctx, "Save State") then
                        Preset.SaveProjectState(Core)
                    end
                    if r.ImGui_MenuItem(ctx, "Load State") then
                        Preset.LoadProjectState(Core)
                    end
                    r.ImGui_Separator(ctx)
                    if r.ImGui_MenuItem(ctx, "Export Preset...") then
                        local retval, filename = r.GetUserFileNameForRead("", "Export ReaSFX Preset", ".rsfx")
                        if retval then
                            Preset.ExportToFile(Core, filename)
                        end
                    end
                    if r.ImGui_MenuItem(ctx, "Import Preset...") then
                        local retval, filename = r.GetUserFileNameForRead("", "Import ReaSFX Preset", ".rsfx")
                        if retval then
                            Preset.ImportFromFile(Core, filename)
                        end
                    end
                    r.ImGui_EndMenu(ctx)
                end
                Gui.DrawTopBar(ctx, Core)
                r.ImGui_EndMenuBar(ctx)
            end

            -- Main UI
            Gui.DrawKeyboard(ctx, Core, CONFIG)
            Gui.DrawSetsTabs(ctx, Core)
            Gui.DrawMainControls(ctx, Core)

            -- Events section
            if Gui.BeginChildBox(ctx, "Ev", 0, 0) then
                Gui.DrawEventsSlots(ctx, Core, CONFIG)
                r.ImGui_Separator(ctx)
                local k = Core.Project.keys[Core.Project.selected_note]
                if k then
                    local s = k.sets[Core.Project.selected_set]
                    if s then Gui.DrawFXChain(ctx, s, Core) end
                end
                r.ImGui_EndChild(ctx)
            end

            r.ImGui_End(ctx)
        end

        -- Draw Log Window (separate window)
        Gui.DrawLogWindow(ctx, Core)

        Gui.PopTheme(ctx)

        if o then
            r.defer(Loop)
        else
            ReleaseKeys()
            if r.ImGui_DestroyContext then
                r.ImGui_DestroyContext(ctx)
            end
        end
    end
end

-- === LOAD SAVED STATE ON START === --
Preset.LoadProjectState(Core)

-- === START === --
r.Undo_BeginBlock()
Loop()
r.Undo_EndBlock("ReaSFX v2", -1)
