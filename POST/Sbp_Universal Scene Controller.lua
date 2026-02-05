-- @description sbp_Universal Scene Controller
-- @version 1.0
-- @author Reaper Senior Scripter
-- @about
--   Fast scene management tool for scene automation, mixers and more.
-- @changelog
--   Initial Release
local r = reaper

-- =========================================================
-- INIT
-- =========================================================
local info = debug.getinfo(1, 'S')
local shim = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
if r.file_exists(shim) then dofile(shim) end

if not r.ImGui_CreateContext then
    r.ShowConsoleMsg("Error: ReaImGui is required.\n")
    return
end

local HAS_JS = r.APIExists('JS_Dialog_BrowseForSaveFile')
local ctx = r.ImGui_CreateContext('Universal Scene Ctrl')

-- =========================================================
-- CONSTANTS
-- =========================================================
local SLOT_TRACK = -1
local P_VOL   = 0
local P_PAN   = 1
local P_WIDTH = 2
local P_MUTE  = 3

-- =========================================================
-- THEME
-- =========================================================
local COL_ACCENT  = 0x0D755CFF -- Deep Teal
local COL_ACCENT_HOV = 0x0A5F4AFF -- Darker Teal for hover
local COL_ORANGE  = 0xD4753FFF
local COL_ORANGE_HOV = 0xB56230FF -- Darker Orange for hover
local COL_RED_DIM = 0xAA4444FF -- Dim Red for Delete
local COL_RED_HOV = 0x8A3636FF -- Darker Red for hover
local COL_BG      = 0x111111FF
local COL_TEXT    = 0xEEEEEEFF
local COL_FRAME   = 0x2A2A2AFF
local COL_TRANS   = 0x00000000 

local function PushWindowTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),       COL_BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(),  COL_BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(),        COL_BG)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10.0, 10.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2.0)
end

local function PopWindowTheme()
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 3)
end

local function PushElementTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),        COL_FRAME)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x383838FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),  0x444444FF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),        COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),       COL_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x1FA888FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),           0x444444FF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),         0x282828FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),  0x383838FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),   0x444444FF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),         0x333333FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(),  0x444444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),   0x555555FF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),           COL_TEXT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(),      0x333333FF)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),  2.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),   6.0, 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(),   4.0, 3.0) 
end

local function PopElementTheme()
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 15)
end

local function DrawHeader(label)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_ACCENT)
    r.ImGui_Text(ctx, string.upper(label))
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
end

-- =========================================================
-- MATH
-- =========================================================
local function Serialize(val)
    if type(val) == "table" then
        local tmp = {}
        for k, v in pairs(val) do
            local key = type(k) == "number" and "["..k.."]=" or "[\""..k.."\"]="
            table.insert(tmp, key .. Serialize(v))
        end
        return "{" .. table.concat(tmp, ",") .. "}"
    elseif type(val) == "string" then return string.format("%q", val)
    else return tostring(val) end
end

local function Unserialize(s)
    local f, err = load("return " .. s)
    if not f then return nil end
    return f()
end

local function Lerp(a, b, t) return a + (b - a) * t end

local function CleanStr(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"):lower())
end

local function Warp(val, curve) return val ^ curve end
local function Unwarp(val, curve) return val ^ (1.0 / curve) end

local function NormToReal(norm, min, max, curve)
    min = min or 0.0; max = max or 1.0; curve = curve or 1.0
    local warped = Warp(norm, curve)
    return min + (warped * (max - min))
end

local function RealToNorm(real, min, max, curve)
    min = min or 0.0; max = max or 1.0; curve = curve or 1.0
    if max == min then return 0.0 end
    local lin = (real - min) / (max - min)
    if lin < 0.0 then lin = 0.0 end
    if lin > 1.0 then lin = 1.0 end
    return Unwarp(lin, curve)
end

local function DB2Gain(db) return 10 ^ (db / 20) end
local function Gain2DB(gain) 
    if gain <= 0.000001 then return -144.0 end
    return 20 * math.log(gain, 10) 
end

-- =========================================================
-- STATE
-- =========================================================
local EXT_SECTION = "CinematicSceneCtrl"
local EXT_KEY = "SessionData"

local CONFIG = {
    target_track_name = "AMB_BUS",
    smoothing = 0.2,
    auto_shape = 1,
    fade_time = 0.0,
    write_raw = true,
    params = {}
}

local scenes = { { name = "Front", color = 0x4488FF, values = {} } }
local state = { is_active = true, last_values = {}, need_save = false }
for i=1, 128 do state.last_values[i] = 0.5 end 

-- =========================================================
-- REAPER ACCESSORS
-- =========================================================
local function GetTrackByName(name)
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
        if CleanStr(track_name) == CleanStr(name) then return track end
    end
    return nil
end

local function GetParamNameFromFX(track, slot, param_id)
    if slot == SLOT_TRACK then
        if param_id == P_VOL then return "Volume" end
        if param_id == P_PAN then return "Pan" end
        if param_id == P_WIDTH then return "Width" end
        if param_id == P_MUTE then return "Mute" end
        return "Unknown"
    end
    if not track then return "N/A" end
    local retval, buf = r.TrackFX_GetParamName(track, slot, param_id, "")
    if retval then return buf end
    return "Unknown"
end

local function GetFXName(track, slot)
    if slot == SLOT_TRACK then return "Track Parameter" end
    if not track then return "Track Not Found" end
    local retval, buf = r.TrackFX_GetFXName(track, slot, "")
    if retval then return buf end
    return "Empty Slot"
end

local function TranslateToReaper(p, human_val)
    if p.slot == SLOT_TRACK then
        if p.param_id == P_VOL then return DB2Gain(human_val) end
        if p.param_id == P_PAN or p.param_id == P_WIDTH then return human_val / 100.0 end 
        return human_val
    end
    return human_val 
end

local function TranslateToHuman(p, reaper_val)
    if p.slot == SLOT_TRACK then
        if p.param_id == P_VOL then return Gain2DB(reaper_val) end
        if p.param_id == P_PAN or p.param_id == P_WIDTH then return reaper_val * 100.0 end
        return reaper_val
    end
    return reaper_val
end

local function UpdateParamRange(track, p)
    if p.slot == SLOT_TRACK then
        if p.param_id == P_VOL then
            if p.min == 0 and p.max == 1 then p.min = -100.0; p.max = 12.0; p.curve = 1.0 end
        elseif p.param_id == P_PAN or p.param_id == P_WIDTH then
            if p.min == 0 and p.max == 1 then p.min = -100.0; p.max = 100.0; p.curve = 1.0 end
        elseif p.param_id == P_MUTE then
            p.min = 0.0; p.max = 1.0; 
        end
        return
    end

    if not track then return end
    local val, min_val, max_val = r.TrackFX_GetParam(track, p.slot, p.param_id)
    if min_val and max_val then
        if min_val ~= max_val then
            p.min = min_val; p.max = max_val
        else
            if p.min == 0 and p.max == 0 then p.min = 0.0; p.max = 1.0 end
        end
    end
end

local function GetItemAtTime(track, position)
    if r.BR_GetMediaItemByTime then return r.BR_GetMediaItemByTime(track, position) end
    local count = r.CountTrackMediaItems(track)
    for i = 0, count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if position >= pos and position < (pos + len) then return item end
    end
    return nil
end

-- =========================================================
-- LOGIC
-- =========================================================
local function AddFXParameter()
    table.insert(CONFIG.params, { label = "New FX Param", slot = 0, param_id = 0, min=0, max=1, curve=1.0, current_norm=0.5 })
    for _, scene in ipairs(scenes) do while #scene.values < #CONFIG.params do table.insert(scene.values, 0.5) end end
    state.need_save = true
end

local function AddTrackParameter(type_id, label)
    local t_min, t_max, t_curve = 0, 1, 1.0
    if type_id == P_VOL then t_min=-100; t_max=12 end
    if type_id == P_PAN then t_min=-100; t_max=100 end
    
    table.insert(CONFIG.params, { label = label, slot = SLOT_TRACK, param_id = type_id, min=t_min, max=t_max, curve=t_curve, current_norm=0.5 })
    for _, scene in ipairs(scenes) do while #scene.values < #CONFIG.params do table.insert(scene.values, 0.5) end end
    state.need_save = true
end

local function RemoveParameter(index)
    if #CONFIG.params <= 1 then return end
    table.remove(CONFIG.params, index)
    table.remove(state.last_values, index)
    for _, scene in ipairs(scenes) do if scene.values[index] then table.remove(scene.values, index) end end
    state.need_save = true
end

local function LoadState()
    local retval, str = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
    if retval == 1 and str ~= "" then
        local data = Unserialize(str)
        if data then
            if data.config then 
                for k,v in pairs(data.config) do CONFIG[k] = v end
                if CONFIG.params then
                    for _, p in ipairs(CONFIG.params) do
                        if not p.min then p.min = 0.0 end
                        if not p.max then p.max = 1.0 end
                        if not p.curve then p.curve = 1.0 end
                    end
                end
            end
            if data.scenes then scenes = data.scenes end
        end
    end
end

local function SaveState()
    if not state.need_save then return end
    local data = { config = CONFIG, scenes = scenes }
    r.SetProjExtState(0, EXT_SECTION, EXT_KEY, Serialize(data))
    r.MarkProjectDirty(0)
    state.need_save = false
end

local function ExportToFile()
    if not HAS_JS then r.ShowConsoleMsg("JS_API required.\n") return end
    local retval, file = r.JS_Dialog_BrowseForSaveFile("Export", "", "scenes.txt", "Text files (.txt)\0*.txt\0")
    if retval and file ~= "" then
        local f = io.open(file, "w")
        if f then f:write(Serialize({ config = CONFIG, scenes = scenes })); f:close() end
    end
end

local function ImportFromFile()
    if not HAS_JS then return end
    local retval, file = r.JS_Dialog_BrowseForOpenFiles("Import", "", "scenes.txt", "Text files (.txt)\0*.txt\0", false)
    if retval and file ~= "" then
        local f = io.open(file, "r")
        if f then
            local data = Unserialize(f:read("*all"))
            f:close()
            if data then CONFIG = data.config; scenes = data.scenes; state.need_save = true end
        end
    end
end

-- =========================================================
-- AUTOMATION & SETTERS
-- =========================================================
local function ApplyValueToTrackOrFX(track, p, human_val)
    local reaper_val = TranslateToReaper(p, human_val)
    if p.slot == SLOT_TRACK then
        if p.param_id == P_VOL then r.SetMediaTrackInfo_Value(track, "D_VOL", reaper_val)
        elseif p.param_id == P_PAN then r.SetMediaTrackInfo_Value(track, "D_PAN", reaper_val)
        elseif p.param_id == P_WIDTH then r.SetMediaTrackInfo_Value(track, "D_WIDTH", reaper_val)
        elseif p.param_id == P_MUTE then r.SetMediaTrackInfo_Value(track, "B_MUTE", (reaper_val > 0.5 and 1 or 0))
        end
    else
        local linear_norm = RealToNorm(human_val, p.min, p.max, 1.0)
        r.TrackFX_SetParamNormalized(track, p.slot, p.param_id, linear_norm)
    end
end

local function WriteAutomationToSelection()
    local track = GetTrackByName(CONFIG.target_track_name)
    if not track then return end
    
    for _, p in ipairs(CONFIG.params) do UpdateParamRange(track, p) end
    
    local item_count = r.CountSelectedMediaItems(0)
    if item_count == 0 then return end

    r.Undo_BeginBlock()
    local envelopes = {}
    for i, p in ipairs(CONFIG.params) do
        local env = nil
        if p.slot == SLOT_TRACK then
            if p.param_id == P_VOL then env = r.GetTrackEnvelopeByName(track, "Volume") end
            if p.param_id == P_PAN then env = r.GetTrackEnvelopeByName(track, "Pan") end
            if p.param_id == P_WIDTH then env = r.GetTrackEnvelopeByName(track, "Width") end
            if p.param_id == P_MUTE then env = r.GetTrackEnvelopeByName(track, "Mute") end
            if not env then r.SetTrackAutomationMode(track, 1) end 
            if env then envelopes[i] = env end
        else
            env = r.GetFXEnvelope(track, p.slot, p.param_id, true)
            if env then 
                envelopes[i] = env 
                local br_env = r.BR_EnvAlloc(env, false) 
                if br_env then
                     local active, visible, armed, inLane, laneHeight, defaultShape, _, _, _, _, faderScaling = r.BR_EnvGetProperties(br_env)
                     r.BR_EnvSetProperties(br_env, true, true, armed, inLane, laneHeight, defaultShape, faderScaling)
                     r.BR_EnvFree(br_env, true)
                end
            end
        end
    end

    for i = 0, item_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local take = r.GetActiveTake(item)
        local raw_name = take and r.GetTakeName(take) or select(2, r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false))
        local tag_name = CleanStr(raw_name)
        
        local scene = nil
        for _, s in ipairs(scenes) do if CleanStr(s.name) == tag_name then scene = s; break end end

        if scene then
            for p_idx, env in pairs(envelopes) do
                local p_conf = CONFIG.params[p_idx]
                local stored_norm = scene.values[p_idx] or 0.5
                local human_val = NormToReal(stored_norm, p_conf.min, p_conf.max, p_conf.curve)
                local write_val = TranslateToReaper(p_conf, human_val)
                
                if CONFIG.write_raw == false and p_conf.slot ~= SLOT_TRACK then
                     write_val = RealToNorm(human_val, p_conf.min, p_conf.max, 1.0)
                end
                
                if CONFIG.fade_time > 0.001 and CONFIG.auto_shape ~= 1 then
                    local half_fade = CONFIG.fade_time / 2
                    local start_time = math.max(0, pos - half_fade)
                    local end_time = pos + half_fade
                    local _, old_val = r.Envelope_Evaluate(env, start_time, 0, 0)
                    r.InsertEnvelopePoint(env, start_time, old_val, CONFIG.auto_shape, 0, true, true)
                    r.InsertEnvelopePoint(env, end_time, write_val, 1, 0, true, true)
                else
                    r.InsertEnvelopePoint(env, pos, write_val, 1, 0, true, true)
                end
            end
        end
    end
    for _, env in pairs(envelopes) do r.Envelope_SortPoints(env) end
    r.Undo_EndBlock("Write Scene Automation", -1)
    r.UpdateArrange()
end

local function CaptureValues(scene_idx)
    local track = GetTrackByName(CONFIG.target_track_name)
    if not track then return end
    local scene = scenes[scene_idx]
    if not scene then return end
    for _, p in ipairs(CONFIG.params) do UpdateParamRange(track, p) end
    
    for i, p in ipairs(CONFIG.params) do
        local reaper_val = 0
        if p.slot == SLOT_TRACK then
            if p.param_id == P_VOL then reaper_val = r.GetMediaTrackInfo_Value(track, "D_VOL")
            elseif p.param_id == P_PAN then reaper_val = r.GetMediaTrackInfo_Value(track, "D_PAN")
            elseif p.param_id == P_WIDTH then reaper_val = r.GetMediaTrackInfo_Value(track, "D_WIDTH")
            elseif p.param_id == P_MUTE then reaper_val = r.GetMediaTrackInfo_Value(track, "B_MUTE") end
        else
            local lin_norm = r.TrackFX_GetParamNormalized(track, p.slot, p.param_id)
            reaper_val = NormToReal(lin_norm, p.min, p.max, 1.0)
        end
        local human_val = TranslateToHuman(p, reaper_val)
        scene.values[i] = RealToNorm(human_val, p.min, p.max, p.curve)
    end
    state.need_save = true
end

local function ProcessTimeline()
    if not state.is_active then return end
    local play_pos = (r.GetPlayState() == 0) and r.GetCursorPosition() or r.GetPlayPosition()
    
    local scene_track = r.GetSelectedTrack(0,0)
    local target_scene = nil
    if scene_track then
        local item = GetItemAtTime(scene_track, play_pos)
        if item then
            local take = r.GetActiveTake(item)
            local tag_name = CleanStr(take and r.GetTakeName(take) or select(2, r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)) or "")
            for _, sc in ipairs(scenes) do if CleanStr(sc.name) == tag_name then target_scene = sc; break end end
        end
    end

    local amb_track = GetTrackByName(CONFIG.target_track_name)
    if amb_track and target_scene then
        local k = (r.GetPlayState() == 0) and 1.0 or (1.0 - CONFIG.smoothing)
        for i, param_cfg in ipairs(CONFIG.params) do
            local target_ui_norm = target_scene.values[i] or 0.5
            if not state.last_values[i] then state.last_values[i] = target_ui_norm end
            state.last_values[i] = Lerp(state.last_values[i], target_ui_norm, k)
            
            local human_val = NormToReal(state.last_values[i], param_cfg.min, param_cfg.max, param_cfg.curve)
            ApplyValueToTrackOrFX(amb_track, param_cfg, human_val)
            
            param_cfg.current_norm = state.last_values[i]
        end
    end
end

local function ApplySceneToSelection(scene_data)
    local count = r.CountSelectedMediaItems(0)
    if count == 0 then return end
    r.Undo_BeginBlock()
    local n_col = r.ColorToNative(math.floor((scene_data.color>>16&0xFF)), math.floor((scene_data.color>>8&0xFF)), math.floor((scene_data.color&0xFF)))|0x1000000
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", n_col)
        local take = r.GetActiveTake(item)
        if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", scene_data.name, true)
        else r.GetSetMediaItemInfo_String(item, "P_NOTES", scene_data.name, true) end
        r.UpdateItemInProject(item)
    end
    r.Undo_EndBlock("Tag Scene: " .. scene_data.name, -1)
    r.UpdateArrange()
end

-- =========================================================
-- UI DRAWING
-- =========================================================
local function DrawUI()
    PushWindowTheme() 
    local rv, open = r.ImGui_Begin(ctx, 'Universal Scene Controller v17.0', true, r.ImGui_WindowFlags_NoCollapse())
    
    if rv then
        PushElementTheme() 
        local amb_track = GetTrackByName(CONFIG.target_track_name)

        DrawHeader("Setup")
        
        r.ImGui_Text(ctx, "TARGET TRACK")
        r.ImGui_SetNextItemWidth(ctx, -1)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_FRAME)
        local ch, v = r.ImGui_InputTextWithHint(ctx, "##track", "Enter Track Name", CONFIG.target_track_name)
        r.ImGui_PopStyleColor(ctx)
        
        if ch then CONFIG.target_track_name = v; state.need_save = true end
        if not amb_track and CONFIG.target_track_name ~= "" then r.ImGui_TextColored(ctx, 0xFF4444FF, "Track not found!") end
        
        if HAS_JS then
            if r.ImGui_Button(ctx, "Import Presets") then ImportFromFile() end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Export Presets") then ExportToFile() end
        end

        r.ImGui_Spacing(ctx)

        -- PARAMS TABLE
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0.0) 
        local flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_Resizable()
        if r.ImGui_BeginTable(ctx, 'SetupTable', 8, flags) then
            r.ImGui_TableSetupColumn(ctx, "Name", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "Slot", r.ImGui_TableColumnFlags_WidthFixed(), 35)
            r.ImGui_TableSetupColumn(ctx, "ID", r.ImGui_TableColumnFlags_WidthFixed(), 35)
            r.ImGui_TableSetupColumn(ctx, "Min", r.ImGui_TableColumnFlags_WidthFixed(), 45)
            r.ImGui_TableSetupColumn(ctx, "Max", r.ImGui_TableColumnFlags_WidthFixed(), 45)
            r.ImGui_TableSetupColumn(ctx, "Curve", r.ImGui_TableColumnFlags_WidthFixed(), 40)
            r.ImGui_TableSetupColumn(ctx, "Test", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "Del", r.ImGui_TableColumnFlags_WidthFixed(), 20)
            r.ImGui_TableHeadersRow(ctx)

            for i, p in ipairs(CONFIG.params) do
                r.ImGui_PushID(ctx, i)
                r.ImGui_TableNextRow(ctx)
                p.min = p.min or 0.0; p.max = p.max or 1.0; p.curve = p.curve or 1.0

                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_TRANS)

                r.ImGui_TableSetColumnIndex(ctx, 0); r.ImGui_SetNextItemWidth(ctx, -1)
                local c1, n = r.ImGui_InputText(ctx, "##lbl", p.label); if c1 then p.label=n; state.need_save=true end
                -- Tooltip showing FX and parameter names from REAPER
                if r.ImGui_IsItemHovered(ctx) then
                    local fx_name = GetFXName(amb_track, p.slot)
                    local param_name = GetParamNameFromFX(amb_track, p.slot, p.param_id)
                    r.ImGui_SetTooltip(ctx, "FX: " .. fx_name .. "\nParam: " .. param_name)
                end
                
                r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_SetNextItemWidth(ctx, -1)
                if p.slot == SLOT_TRACK then r.ImGui_TextDisabled(ctx, "TRK")
                else
                    local c2, s = r.ImGui_DragInt(ctx, "##slot", p.slot, 0.1, 0, 16)
                    if c2 then
                        p.slot = s
                        UpdateParamRange(amb_track, p)
                        -- Auto-fill label with parameter name from new FX slot
                        local param_name = GetParamNameFromFX(amb_track, p.slot, p.param_id)
                        if param_name and param_name ~= "Unknown" and param_name ~= "N/A" then
                            p.label = param_name
                        end
                        state.need_save = true
                    end
                end
                -- Tooltip for FX name
                if r.ImGui_IsItemHovered(ctx) then
                    local fx_name = GetFXName(amb_track, p.slot)
                    r.ImGui_SetTooltip(ctx, "FX: " .. fx_name)
                end

                r.ImGui_TableSetColumnIndex(ctx, 2); r.ImGui_SetNextItemWidth(ctx, -1)
                if p.slot == SLOT_TRACK then
                    local id_name = "UNK"
                    if p.param_id == P_VOL then id_name="VOL" elseif p.param_id == P_PAN then id_name="PAN" elseif p.param_id == P_WIDTH then id_name="WID" elseif p.param_id == P_MUTE then id_name="MUT" end
                    r.ImGui_TextDisabled(ctx, id_name)
                else
                    local chg, pid = r.ImGui_DragInt(ctx, "##pid", p.param_id, 0.2, 0, 2000)
                    if chg then
                        p.param_id = pid
                        UpdateParamRange(amb_track, p)
                        -- Auto-fill label with parameter name from REAPER
                        local param_name = GetParamNameFromFX(amb_track, p.slot, p.param_id)
                        if param_name and param_name ~= "Unknown" and param_name ~= "N/A" then
                            p.label = param_name
                        end
                        state.need_save = true
                    end
                end
                -- Tooltip for parameter name
                if r.ImGui_IsItemHovered(ctx) then
                    local param_name = GetParamNameFromFX(amb_track, p.slot, p.param_id)
                    r.ImGui_SetTooltip(ctx, "Param: " .. param_name)
                end
                
                r.ImGui_TableSetColumnIndex(ctx, 3); r.ImGui_SetNextItemWidth(ctx, -1)
                local c_min, n_min = r.ImGui_InputDouble(ctx, "##min", p.min, 0, 0, "%.1f"); if c_min then p.min = n_min; state.need_save=true end
                if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "RangePreset") end

                r.ImGui_TableSetColumnIndex(ctx, 4); r.ImGui_SetNextItemWidth(ctx, -1)
                local c_max, n_max = r.ImGui_InputDouble(ctx, "##max", p.max, 0, 0, "%.1f"); if c_max then p.max = n_max; state.need_save=true end
                if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "RangePreset") end
                
                r.ImGui_TableSetColumnIndex(ctx, 5); r.ImGui_SetNextItemWidth(ctx, -1)
                local c_crv, n_crv = r.ImGui_DragDouble(ctx, "##crv", p.curve, 0.05, 0.1, 4.0, "%.2f")
                if c_crv then p.curve = n_crv; state.need_save = true end
                -- Right-click to reset curve to 1.0 (linear)
                if r.ImGui_IsItemClicked(ctx, 1) then p.curve = 1.0; state.need_save = true end

                r.ImGui_PopStyleColor(ctx) 

                if r.ImGui_BeginPopup(ctx, "RangePreset") then
                    r.ImGui_Text(ctx, "Quick Range:")
                    if r.ImGui_Selectable(ctx, "JSFX Volume (-144..18)") then p.min=-144; p.max=18; p.curve=0.25; state.need_save=true end
                    if r.ImGui_Selectable(ctx, "Track Volume (-100..12 dB)") then p.min=-100; p.max=12; p.curve=1.0; state.need_save=true end
                    if r.ImGui_Selectable(ctx, "Pan/Width (-100..100 %)") then p.min=-100; p.max=100; p.curve=1.0; state.need_save=true end
                    r.ImGui_EndPopup(ctx)
                end

                r.ImGui_TableSetColumnIndex(ctx, 6); r.ImGui_SetNextItemWidth(ctx, -1)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_FRAME)
                local real_val = NormToReal(p.current_norm, p.min, p.max, p.curve)
                
                local fmt_drag = "%.3f"
                local step = 0.001
                if p.slot == SLOT_TRACK then
                    if p.param_id == P_VOL then fmt_drag = "%.1f dB"
                    elseif p.param_id == P_PAN then fmt_drag = "%.0f %%"; step = 0.01
                    elseif p.param_id == P_MUTE then fmt_drag = "%.0f"; step = 1.0 end
                end
                
                local c_val, new_real = r.ImGui_SliderDouble(ctx, "##val", real_val, p.min, p.max, fmt_drag)
                r.ImGui_PopStyleColor(ctx)
                if c_val then
                    p.current_norm = RealToNorm(new_real, p.min, p.max, p.curve)
                    ApplyValueToTrackOrFX(amb_track, p, new_real)
                end
                -- Right-click to reset to center
                if r.ImGui_IsItemClicked(ctx, 1) then
                    p.current_norm = 0.5
                    local default_real = NormToReal(0.5, p.min, p.max, p.curve)
                    ApplyValueToTrackOrFX(amb_track, p, default_real)
                end

                -- DELETE BUTTON (SQUARE & RED)
                r.ImGui_TableSetColumnIndex(ctx, 7)
                local btn_size = r.ImGui_GetFrameHeight(ctx)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2.0)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_RED_DIM)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_RED_HOV)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_RED_HOV)
                if r.ImGui_Button(ctx, "X##del"..i, btn_size, btn_size) then RemoveParameter(i) end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopStyleVar(ctx)
                
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_PopStyleVar(ctx)
        
        -- DUAL BUTTONS
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
          local btn_w = (avail_w * 0.5) - 4
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT_HOV)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT_HOV)
          if r.ImGui_Button(ctx, "+ ADD FX PARAM", btn_w) then AddFXParameter() end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "+ ADD TRACK PARAM", btn_w) then r.ImGui_OpenPopup(ctx, "AddTrkParam") end
          r.ImGui_PopStyleColor(ctx, 3)
        
        if r.ImGui_BeginPopup(ctx, "AddTrkParam") then
            if r.ImGui_Selectable(ctx, "Track Volume") then AddTrackParameter(P_VOL, "Track Volume") end
            if r.ImGui_Selectable(ctx, "Track Pan") then AddTrackParameter(P_PAN, "Track Pan") end
            if r.ImGui_Selectable(ctx, "Track Width") then AddTrackParameter(P_WIDTH, "Track Width") end
            if r.ImGui_Selectable(ctx, "Track Mute") then AddTrackParameter(P_MUTE, "Track Mute") end
            r.ImGui_EndPopup(ctx)
        end

        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

        DrawHeader("Scene Library")

        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0.0) 
        local num_cols = 4 + #CONFIG.params
        if r.ImGui_BeginTable(ctx, 'ScenesTable', num_cols, flags) then
            r.ImGui_TableSetupColumn(ctx, "Col", r.ImGui_TableColumnFlags_WidthFixed(), 20)
            r.ImGui_TableSetupColumn(ctx, "Scene Name", r.ImGui_TableColumnFlags_WidthStretch())
            for _, p in ipairs(CONFIG.params) do r.ImGui_TableSetupColumn(ctx, p.label, r.ImGui_TableColumnFlags_WidthFixed(), 65) end
            r.ImGui_TableSetupColumn(ctx, "Settings", r.ImGui_TableColumnFlags_WidthFixed(), 60)
            r.ImGui_TableSetupColumn(ctx, "Tag", r.ImGui_TableColumnFlags_WidthFixed(), 50)
            r.ImGui_TableHeadersRow(ctx)

            for i, scene in ipairs(scenes) do
                r.ImGui_PushID(ctx, i + 100) 
                r.ImGui_TableNextRow(ctx)
                
                r.ImGui_TableSetColumnIndex(ctx, 0)
                local cc, nc = r.ImGui_ColorEdit4(ctx, "##c", scene.color, r.ImGui_ColorEditFlags_NoInputs()|r.ImGui_ColorEditFlags_NoLabel())
                if cc then scene.color = nc; state.need_save = true end
                
                r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_SetNextItemWidth(ctx, -1)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_TRANS)
                local cn, nn = r.ImGui_InputText(ctx, "##n", scene.name); if cn then scene.name = nn; state.need_save = true end
                
                -- WILDCARDS CONTEXT MENU
                if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "NameWildcards") end
                if r.ImGui_BeginPopup(ctx, "NameWildcards") then
                    local function App(txt) scene.name = scene.name .. (scene.name == "" and "" or " ") .. txt; state.need_save = true end
                    r.ImGui_TextDisabled(ctx, " SCENES")
                    if r.ImGui_Selectable(ctx, "General") then App("General") end
                    if r.ImGui_Selectable(ctx, "Motion") then App("Motion") end
                    if r.ImGui_Selectable(ctx, "Zoom") then App("Zoom") end
                    if r.ImGui_Selectable(ctx, "Pan") then App("Pan") end
                    if r.ImGui_Selectable(ctx, "Tilt") then App("Tilt") end
                    if r.ImGui_Selectable(ctx, "Roll") then App("Roll") end                   
                    if r.ImGui_Selectable(ctx, "Flip") then App("Flip") end
                    r.ImGui_Separator(ctx)
                    r.ImGui_TextDisabled(ctx, "POSITIONS")
                    if r.ImGui_Selectable(ctx, "Left") then App("Left") end
                    if r.ImGui_Selectable(ctx, "Right") then App("Right") end
                    if r.ImGui_Selectable(ctx, "Front") then App("Front") end
                    if r.ImGui_Selectable(ctx, "Rear") then App("Rear") end
                    r.ImGui_Separator(ctx)                    
                    r.ImGui_TextDisabled(ctx, "SHOTS")
                    if r.ImGui_Selectable(ctx, "CU (Close-Up)") then App("CU") end
                    if r.ImGui_Selectable(ctx, "MS (Medium)") then App("MS") end
                    if r.ImGui_Selectable(ctx, "WS (Wide)") then App("WS") end
                    if r.ImGui_Selectable(ctx, "ECU (Extreme)") then App("ECU") end
                    r.ImGui_Separator(ctx)
                    r.ImGui_TextDisabled(ctx, "ANGLES")
                    if r.ImGui_Selectable(ctx, "45 deg") then App("45deg") end
                    if r.ImGui_Selectable(ctx, "-45 deg") then App("-45deg") end
                    if r.ImGui_Selectable(ctx, "90 deg") then App("90deg") end
                    if r.ImGui_Selectable(ctx, "-90 deg") then App("-90deg") end
                    if r.ImGui_Selectable(ctx, "180 deg") then App("180deg") end
                    r.ImGui_Separator(ctx)
                    r.ImGui_TextDisabled(ctx, "MOTION")
                    if r.ImGui_Selectable(ctx, "Flip") then App("Flip") end
                    if r.ImGui_Selectable(ctx, "Pass-by") then App("Pass-by") end
                    if r.ImGui_Selectable(ctx, "Static") then App("Static") end
                    if r.ImGui_Selectable(ctx, "Rotate") then App("Rotate") end
                    r.ImGui_EndPopup(ctx)
                end
                
                r.ImGui_PopStyleColor(ctx)
                
                for p_idx, p_conf in ipairs(CONFIG.params) do
                    r.ImGui_PushID(ctx, p_idx) 
                    r.ImGui_TableSetColumnIndex(ctx, 1 + p_idx); r.ImGui_SetNextItemWidth(ctx, -1)
                    
                    if not scene.values[p_idx] then scene.values[p_idx] = 0.5 end
                    local stored_norm = scene.values[p_idx]
                    local real_val_display = NormToReal(stored_norm, p_conf.min, p_conf.max, p_conf.curve)
                    
                    local step = 0.001
                    local fmt_drag = "%.3f"
                    if p_conf.slot == SLOT_TRACK then
                        if p_conf.param_id == P_VOL then fmt_drag = "%.1f dB"
                        elseif p_conf.param_id == P_PAN then fmt_drag = "%.0f %%"; step = 0.01
                        elseif p_conf.param_id == P_MUTE then fmt_drag = "%.0f"; step = 1.0 end
                    end
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL_TRANS)
                    local cv, v_real_new = r.ImGui_DragDouble(ctx, "##v", real_val_display, step, p_conf.min, p_conf.max, fmt_drag)
                    r.ImGui_PopStyleColor(ctx)

                    if cv then
                        scene.values[p_idx] = RealToNorm(v_real_new, p_conf.min, p_conf.max, p_conf.curve)
                        state.need_save = true
                    end
                    -- Right-click to reset to center (0.5)
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        scene.values[p_idx] = 0.5
                        state.need_save = true
                    end
                    r.ImGui_PopID(ctx)
                end
                
                r.ImGui_TableSetColumnIndex(ctx, num_cols - 2)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2.0)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ORANGE_HOV)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ORANGE_HOV)
                if r.ImGui_Button(ctx, "Capture##cap") then CaptureValues(i) end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopStyleVar(ctx)
                
                r.ImGui_TableSetColumnIndex(ctx, num_cols - 1)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2.0)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_RED_DIM)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_RED_HOV)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_RED_HOV)
                if r.ImGui_Button(ctx, "Apply##app") then ApplySceneToSelection(scene) end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopStyleVar(ctx)
                
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_PopStyleVar(ctx) 
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ACCENT)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ACCENT_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ACCENT_HOV)
        if r.ImGui_Button(ctx, "ADD NEW PRESET", -1) then
            local new_vals = {}; for k=1, #CONFIG.params do new_vals[k] = 0.5 end
            table.insert(scenes, { name = "New Scene", color = 0xCCCCCCFF, values = new_vals })
            state.need_save = true
        end
        r.ImGui_PopStyleColor(ctx, 3)

        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

        DrawHeader("Automation")
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL_ORANGE)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL_ORANGE_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL_ORANGE_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x111111FF)
        if r.ImGui_Button(ctx, "WRITE AUTOMATION", -1, 30) then WriteAutomationToSelection() end
        r.ImGui_PopStyleColor(ctx, 4)

        r.ImGui_Spacing(ctx)

        if r.ImGui_BeginTable(ctx, "AutoOpts", 3) then
            r.ImGui_TableSetupColumn(ctx, "1", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "2", r.ImGui_TableColumnFlags_WidthFixed(), 80)
            r.ImGui_TableSetupColumn(ctx, "3", r.ImGui_TableColumnFlags_WidthFixed(), 100)
            r.ImGui_TableNextRow(ctx)

            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_SetNextItemWidth(ctx, -1)
            if r.ImGui_BeginCombo(ctx, "##shape", (CONFIG.auto_shape == 1 and "Square" or (CONFIG.auto_shape == 0 and "Linear" or "Bezier"))) then
                if r.ImGui_Selectable(ctx, "Square", CONFIG.auto_shape == 1) then CONFIG.auto_shape = 1; state.need_save = true end
                if r.ImGui_Selectable(ctx, "Linear", CONFIG.auto_shape == 0) then CONFIG.auto_shape = 0; state.need_save = true end
                if r.ImGui_Selectable(ctx, "Bezier", CONFIG.auto_shape == 5) then CONFIG.auto_shape = 5; state.need_save = true end
                r.ImGui_EndCombo(ctx)
            end

            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_SetNextItemWidth(ctx, -1)
            if CONFIG.auto_shape == 1 then r.ImGui_BeginDisabled(ctx, true) end
            local cf, nf = r.ImGui_DragDouble(ctx, "##fade", CONFIG.fade_time, 0.05, 0.0, 30.0, "%.2f s")
            if cf then CONFIG.fade_time = nf; state.need_save = true end
            -- Right-click to reset fade to 0
            if r.ImGui_IsItemClicked(ctx, 1) then CONFIG.fade_time = 0.0; state.need_save = true end
            if CONFIG.auto_shape == 1 then r.ImGui_EndDisabled(ctx) end

            r.ImGui_TableSetColumnIndex(ctx, 2)
            local c_raw, new_raw = r.ImGui_Checkbox(ctx, "Raw Values", CONFIG.write_raw)
            if c_raw then CONFIG.write_raw = new_raw; state.need_save = true end

            r.ImGui_EndTable(ctx)
        end

        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx)

        local _, active = r.ImGui_Checkbox(ctx, "MONITORING ACTIVE", state.is_active)
        state.is_active = active
        r.ImGui_SameLine(ctx)
        r.ImGui_PushItemWidth(ctx, 100)
        local sm_ch, smooth = r.ImGui_SliderDouble(ctx, "Smoothing", CONFIG.smoothing, 0.0, 0.99, "%.2f")
        if sm_ch then CONFIG.smoothing = smooth; state.need_save = true end
        -- Right-click to reset smoothing to default (0.2)
        if r.ImGui_IsItemClicked(ctx, 1) then CONFIG.smoothing = 0.2; state.need_save = true end
        r.ImGui_PopItemWidth(ctx)

        PopElementTheme() 
        r.ImGui_End(ctx)
    end
    
    PopWindowTheme()
    return open
end

local function Main()
    LoadState()
    local function Loop()
        local status, err = pcall(function()
            SaveState(); ProcessTimeline(); local open = DrawUI(); if open then r.defer(Loop) end
        end)
        if not status then r.ShowConsoleMsg("Error: " .. tostring(err)) end
    end
    Loop()
end

Main()