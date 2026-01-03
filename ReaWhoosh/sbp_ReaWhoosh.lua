-- @description ReaWhoosh v2.5 (Stable & Features)
-- @author SBP & Gemini
-- @version 2.5
-- @about ReaWhoosh is a tool for automatically creating whoosh-type sound effects (flybys, whistles, object movement) directly in Reaper.
-- The system consists of a graphical control interface (Lua) and a table-wave/chaotic synthesiser (sbp_WhooshEngine.jsfx).
--https://forum.cockos.com/showthread.php?t=305805
--Support the developer: PayPal - bodzik@gmail.com

-- =========================================================
-- @changelog
-- v2.0    
-- Stable release with new GUI, new features and improved WhooshEngine.jsfx
-- v2.1 
-- Visual improvements to the interface have been made
-- An arrow has been added to vectors for better visual understanding of the direction of the vector over time
-- The behaviour of vectors has been improved; they are now easier to control
-- v2.2
-- Fixed Preset system (Factory presets now load correctly)
-- Added Global User Presets (Save/Delete) via ExtState
-- some fixes and improvements to the GUI.
-- Added GMEM support for visual metering.
-- Added VU Meters for mixer channels.
-- Added Stereo Analyzer/Goniometer + Sub Meter.
-- Rearranged Layout: Randomize moved to Header, Options moved to right.
-- v2.5 (!need updated sbp_WhooshEngine.jsfx!)
-- Pad Chopper added! Control its speed and depth with vectors. Gate shape control in options.
-- Improved mixer performance, works for increase and decrease, stereoscope added.
-- Two modes for creating swishes have been introduced (in the options): classic and new, where the Peak position is set by the position of the Edit Cursor on the timeline within the Time Selection.
-- Envelope shapes can now be set in the options. 5. Randomise can now be configured. In the options, you can choose which pads will be randomised.
-- Visual improvements to the interface

-- =========================================================

local r = reaper
local ctx = r.ImGui_CreateContext('ReaWhoosh')
r.gmem_attach('sbp_whoosh') 

-- FORWARD DECLARATIONS
local GenerateWhoosh 

-- =========================================================
-- 1. CONSTANTS
-- =========================================================
local C_TEXT        = 0xE0E0E0FF
local C_BTN_SEC     = 0x444444FF
local C_BTN_ACTIVE  = 0x2D8C6DFF
local C_MUTE_ACTIVE = 0xFF4040FF
local C_FRAME_BG    = 0x00000060
local C_PAD_BG      = 0x00000050
local C_ACCENT_DEF  = 0x2D8C6DFF
local C_BG_DEF      = 0x252525FF
local C_ORANGE      = 0xD46A3FFF -- Orange Color for OFF state
local C_WHITE       = 0xFFFFFFFF
local C_GREY        = 0x888888FF
local C_SLIDER_BG   = 0x00000090

local PAD_SQUARE    = 170 
local MIX_W         = 20  
local MIX_H         = 130 

-- Heights
local PAD_DRAW_H    = 170 
local CONTAINER_H   = 210 

-- DATA
local settings = {
    track_name = "Whoosh FX",
    output_mode = 0, 
    col_accent = C_ACCENT_DEF,
    col_bg = C_BG_DEF,
    master_vol = -6.0,
    env_shape = 0, 
    peak_mode = 0,
    -- Randomization Masks
    rand_src = true, rand_morph = true, rand_filt = true,
    rand_dop = true, rand_space = true, rand_chop = true, rand_env = false   
}

local config = {
    peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
    src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
    cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
    morph_s_x=0.0, morph_s_y=1.0, morph_p_x=0.5, morph_p_y=0.5, morph_e_x=0.0, morph_e_y=0.0,
    dop_s_x=0.0, dop_s_y=0.5, dop_p_x=0.5, dop_p_y=0.5, dop_e_x=1.0, dop_e_y=0.5,
    spc_s_x=0.0, spc_s_y=0.0, spc_p_x=0.5, spc_p_y=1.0, spc_e_x=1.0, spc_e_y=0.5,
    
    -- Chopper
    chop_s_x=0.0, chop_s_y=0.0, chop_p_x=0.5, chop_p_y=0.0, chop_e_x=0.0, chop_e_y=0.0,
    chop_enable=true, chop_shape=0.0,

    sub_freq = 55, sub_enable = true, sub_vol = 0.8,
    chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, saw_pwm = 0.1,
    saw_detune = 0.0,
    flange_wet=0.0, flange_feed=0.0, verb_size=0.5, rev_damp = 0.5,
    dbl_time = 30, dbl_wide = 0.5,
    mute_w = false, mute_s = false, mute_c = false, mute_e = false,
    trim_w = 1.0, trim_s = 1.0, trim_c = 1.0, trim_e = 1.0, 
    current_preset = "Default"
}

-- Default Factory Presets
local FACTORY_PRESETS = {
    ["Default"] = {
        peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
        src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
        cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
        sub_freq = 55, sub_vol = 0.8, sub_enable = true,
        chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0,
        flange_wet=0.0, verb_size=0.5, dbl_wide = 0.5,
        chop_s_x=0.0, chop_s_y=0.0, chop_p_x=0.0, chop_p_y=0.0, chop_e_x=0.0, chop_e_y=0.0,
        chop_enable=true, chop_shape=0.0
    }
}

local USER_PRESETS = {} 
local PRESET_INPUT_BUF = ""
local SHOW_SAVE_MODAL = false
local DO_FOCUS_INPUT = false
local PRESET_SECTION = "ReaWhoosh_UserPresets"
local PRESET_LIST_KEY = "PRESET_LIST"

local IDX = {
    mix_vol1 = 0, mix_vol2 = 1, mix_vol3 = 2, mix_vol4 = 3, 
    sub_freq = 4, sub_direct_vol = 5,
    chua_rate = 6, chua_shape = 7, chua_timbre = 8,
    filt_morph_x = 9, filt_morph_y = 10, filt_freq = 11, filt_res = 12,
    flange_feed = 13, flange_wet = 14,
    verb_size = 15, verb_wet = 16,
    pan_x = 17, pan_y = 18, width = 19, out_mode = 20, 
    master_vol = 21,
    trim_w = 22, trim_s = 23, trim_c = 24, trim_e = 25,
    saw_pwm = 26,
    rev_damp = 27, dbl_mix = 28, dbl_time = 29, dbl_wide = 30,
    saw_detune = 31,
    chop_depth = 32, chop_rate = 33, chop_shape = 34,
    global_pitch = 43 
}

local interaction = { dragging_pad = nil, dragging_point = nil, last_update_time = 0, dragging_peak = false }
local scope_history = {} 

-- =========================================================
-- SYSTEM
-- =========================================================
function SafeCol(c, def) return (type(c)=="number") and c or (def or C_WHITE) end
function Clamp(val, min, max) return math.min(math.max(val or 0, min or 0), max or 1) end

-- COLOR DARKENER FOR HOVER
function DarkenColor(col)
    local r = (col >> 24) & 0xFF
    local g = (col >> 16) & 0xFF
    local b = (col >> 8)  & 0xFF
    local a = col & 0xFF
    
    r = math.floor(r * 0.8)
    g = math.floor(g * 0.8)
    b = math.floor(b * 0.8)
    
    return (r << 24) | (g << 16) | (b << 8) | a
end

function ValidateConfig()
    if not config.peak_pos then config.peak_pos = 0.5 end
    if not config.saw_detune then config.saw_detune = 0.0 end
    if config.chop_enable == nil then config.chop_enable = true end
    if not config.chop_shape then config.chop_shape = 0.0 end
end

function SaveSettings()
    local str = string.format("name=%s;mode=%d;c1=%d;c3=%d;mv=%.2f;shp=%d;pm=%d;rs=%d;rm=%d;rf=%d;rd=%d;rsp=%d;rc=%d;re=%d", 
        settings.track_name, settings.output_mode, 
        SafeCol(settings.col_accent, C_ACCENT_DEF), SafeCol(settings.col_bg, C_BG_DEF), settings.master_vol or -6.0,
        settings.env_shape or 0, settings.peak_mode or 0,
        settings.rand_src and 1 or 0, settings.rand_morph and 1 or 0, settings.rand_filt and 1 or 0, 
        settings.rand_dop and 1 or 0, settings.rand_space and 1 or 0, settings.rand_chop and 1 or 0, settings.rand_env and 1 or 0)
    r.SetExtState("ReaWhoosh_v45", "Global_Settings", str, true)
end

function LoadSettings()
    local str = r.GetExtState("ReaWhoosh_v45", "Global_Settings")
    if str and str ~= "" then
        for k, v in string.gmatch(str, "(%w+)=([^;]+)") do
            if k == "name" then settings.track_name = v
            elseif k == "mode" then settings.output_mode = tonumber(v) or 0
            elseif k == "c1" then settings.col_accent = tonumber(v) or C_ACCENT_DEF
            elseif k == "c3" then settings.col_bg = tonumber(v) or C_BG_DEF
            elseif k == "mv" then settings.master_vol = tonumber(v) or -6.0
            elseif k == "shp" then settings.env_shape = tonumber(v) or 0
            elseif k == "pm" then settings.peak_mode = tonumber(v) or 0
            elseif k == "rs" then settings.rand_src = (tonumber(v)==1)
            elseif k == "rm" then settings.rand_morph = (tonumber(v)==1)
            elseif k == "rf" then settings.rand_filt = (tonumber(v)==1)
            elseif k == "rd" then settings.rand_dop = (tonumber(v)==1)
            elseif k == "rsp" then settings.rand_space = (tonumber(v)==1)
            elseif k == "rc" then settings.rand_chop = (tonumber(v)==1)
            elseif k == "re" then settings.rand_env = (tonumber(v)==1)
            end
        end
    end
    ValidateConfig()
end

-- PRESET SYSTEM -------------------------------------------
function SerializeConfig()
    local str = ""
    for k, v in pairs(config) do
        if k ~= "current_preset" then
            local val = tostring(v)
            if type(v) == "boolean" then val = v and "1" or "0" end
            str = str .. k .. "=" .. val .. "::"
        end
    end
    return str
end

function DeserializeAndApply(str)
    if not str then return end
    for k, v in string.gmatch(str, "(.-)=([^:]+)::") do
        if config[k] ~= nil then
            if type(config[k]) == "number" then config[k] = tonumber(v)
            elseif type(config[k]) == "boolean" then config[k] = (v == "1")
            else config[k] = v end
        end
    end
end

function LoadUserPresets()
    USER_PRESETS = {}
    local list_str = r.GetExtState(PRESET_SECTION, PRESET_LIST_KEY)
    if not list_str or list_str == "" then return end
    
    for name in list_str:gmatch("([^|]+)") do
        if name and name ~= "" then
            local data = r.GetExtState(PRESET_SECTION, name)
            if data and data ~= "" then
                USER_PRESETS[name] = data
            end
        end
    end
end

function SaveUserPreset(name)
    if name == "" then return end
    local data = SerializeConfig()
    r.SetExtState(PRESET_SECTION, name, data, true)
    local list_str = r.GetExtState(PRESET_SECTION, PRESET_LIST_KEY)
    local exists = false
    for n in list_str:gmatch("([^|]+)") do
        if n == name then exists = true; break end
    end
    if not exists then
        list_str = list_str .. name .. "|"
        r.SetExtState(PRESET_SECTION, PRESET_LIST_KEY, list_str, true)
    end
    LoadUserPresets()
    config.current_preset = name
end

function DeleteUserPreset(name)
    if not USER_PRESETS[name] then return end
    r.DeleteExtState(PRESET_SECTION, name, true)
    local list_str = r.GetExtState(PRESET_SECTION, PRESET_LIST_KEY)
    local new_list = ""
    for n in list_str:gmatch("([^|]+)") do
        if n ~= name then new_list = new_list .. n .. "|" end
    end
    r.SetExtState(PRESET_SECTION, PRESET_LIST_KEY, new_list, true)
    LoadUserPresets()
    config.current_preset = "Default"
    ApplyPreset("Default")
end

function ApplyPreset(name)
    local data = nil
    if FACTORY_PRESETS[name] then
        for k,v in pairs(FACTORY_PRESETS[name]) do config[k] = v end
        config.current_preset = name
        return
    elseif USER_PRESETS[name] then
        data = USER_PRESETS[name]
    end
    if data then
        DeserializeAndApply(data)
        config.current_preset = name
    end
end
------------------------------------------------------------

function ScaleVal(env, val)
    if not env then return val end
    return r.ScaleToEnvelopeMode(r.GetEnvelopeScalingMode(env), val)
end

function ToPitch(norm)
    if not norm then return 0 end
    return (norm * 24) - 12 
end

function GetOrAddFX(track, name)
    local cnt = r.TrackFX_GetCount(track)
    for i = 0, cnt - 1 do
        local _, buf = r.TrackFX_GetFXName(track, i, "")
        if buf:lower():find(name:lower(), 1, true) then return i end
    end
    return r.TrackFX_AddByName(track, name, false, -1)
end

function FindParamByName(track, fx_idx, search_str)
    local num = r.TrackFX_GetNumParams(track, fx_idx)
    for i = 0, num - 1 do
        local _, param_name = r.TrackFX_GetParamName(track, fx_idx, i, "")
        if param_name:lower():find(search_str:lower()) then return i end
    end
    return -1 
end

function FindTrackByName(name)
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name then return track end
    end
    return nil
end

function SetEnvVisible(env)
    if not env then return end
    local br_env = r.BR_EnvAlloc(env, false)
    if br_env then
        local active, visible, armed, inLane, laneHeight, defaultShape, _, _, _, _, faderScaling = r.BR_EnvGetProperties(br_env)
        if not visible or not armed then
            r.BR_EnvSetProperties(br_env, true, true, true, inLane, laneHeight, defaultShape, faderScaling)
            r.BR_EnvFree(br_env, true)
        else
            r.BR_EnvFree(br_env, false)
        end
    else
        local retval, str = r.GetEnvelopeStateChunk(env, "", false)
        if retval then
            local new_str = str:gsub("VIS 0", "VIS 1"):gsub("ARM 0", "ARM 1")
            r.SetEnvelopeStateChunk(env, new_str, false)
        end
    end
end

function ShowAllEnvelopes() 
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local vol_env = r.GetTrackEnvelopeByName(track, "Volume")
    if vol_env then SetEnvVisible(vol_env) end
    local fx_idx = GetOrAddFX(track, "sbp_WhooshEngine")
    IDX.global_pitch = FindParamByName(track, fx_idx, "Global Pitch")
    if IDX.global_pitch == -1 then IDX.global_pitch = FindParamByName(track, fx_idx, "pitch") end
    if IDX.global_pitch == -1 then IDX.global_pitch = 43 end 
    if IDX.global_pitch >= 0 then
        local pitch_env = r.GetFXEnvelope(track, fx_idx, IDX.global_pitch, true) 
        if pitch_env then SetEnvVisible(pitch_env) end
    end
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

function ToggleEnvelopes() r.Main_OnCommand(41151, 0) end

function RandomizeConfig()
    local function rf() return math.random() end
    
    if settings.rand_env then
        config.peak_pos = 0.2 + rf() * 0.6
        if settings.env_shape == 0 then
            config.tens_attack = (rf() * 2.0) - 1.0
            config.tens_release = (rf() * 2.0) - 1.0
        end
    end
    
    if settings.rand_src then 
        config.src_s_x = rf(); config.src_s_y = rf(); config.src_p_x = rf(); config.src_p_y = rf(); config.src_e_x = rf(); config.src_e_y = rf()
        config.sub_freq = 30 + math.floor(rf()*90)
    end
    
    if settings.rand_morph then
        config.morph_s_x = rf(); config.morph_s_y = rf(); config.morph_p_x = rf(); config.morph_p_y = rf(); config.morph_e_x = rf(); config.morph_e_y = rf()
    end
    
    if settings.rand_filt then
        config.cut_s_x = rf(); config.cut_s_y = rf(); config.cut_p_x = rf(); config.cut_p_y = rf(); config.cut_e_x = rf(); config.cut_e_y = rf()
    end
    
    if settings.rand_dop then
        config.dop_s_x = rf(); config.dop_s_y = rf(); config.dop_p_x = rf(); config.dop_p_y = rf(); config.dop_e_x = rf(); config.dop_e_y = rf()
    end

    if settings.rand_space then
        config.spc_s_x = rf(); config.spc_s_y = rf(); config.spc_p_x = rf(); config.spc_p_y = rf(); config.spc_e_x = rf(); config.spc_e_y = rf()
    end
    
    if settings.rand_chop then
        config.chop_s_x = rf(); config.chop_s_y = rf(); config.chop_p_x = rf(); config.chop_p_y = rf(); config.chop_e_x = rf(); config.chop_e_y = rf()
    end
end

-- =========================================================
-- AUTOMATION
-- =========================================================

function CreateEnvelopeCurveTrack(track, env_name, t_s, t_p, t_e, val_silence, val_peak, t_att, t_rel)
    local env = r.GetTrackEnvelopeByName(track, env_name)
    if not env then 
        if env_name=="Volume" then r.Main_OnCommand(40406,0) end
        env = r.GetTrackEnvelopeByName(track, env_name)
    end
    if not env then return end
    SetEnvVisible(env)
    r.DeleteEnvelopePointRange(env, t_s-0.001, t_e+0.001)
    local v_s = ScaleVal(env, val_silence)
    local v_p = ScaleVal(env, val_peak)
    
    local shape = 5 
    if settings.env_shape == 1 then shape = 0 end 
    if settings.env_shape == 2 then shape = 2 end 

    local tens_att_val = (shape == 5) and t_att or 0
    local tens_rel_val = (shape == 5) and t_rel or 0

    r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, 5, true) 
    r.InsertEnvelopePoint(env, t_p, v_p, 0, 0, 5, true)    
    r.InsertEnvelopePoint(env, t_e, v_s, 0, 0, 5, true) 
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-3, t_s, v_s, shape, tens_att_val, true, true) 
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-2, t_p, v_p, shape, tens_rel_val, true, true) 
    r.Envelope_SortPoints(env)
end

function Create3PointRampFX(track, fx_idx, param_idx, t_s, t_p, t_e, v_s, v_p, v_e)
    if fx_idx < 0 or param_idx < 0 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true) 
    if env then
        SetEnvVisible(env)
        r.DeleteEnvelopePointRange(env, t_s-0.001, t_e+0.001)
        r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, false, true)
        r.InsertEnvelopePoint(env, t_p, v_p, 0, 0, false, true)
        r.InsertEnvelopePoint(env, t_e, v_e, 0, 0, false, true)
        r.Envelope_SortPoints(env)
    end
end

function UpdateAutomationOnly(flags)
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then return end
    
    local length = end_time - start_time
    local peak_time = start_time + (length * config.peak_pos)
    
    if settings.peak_mode == 1 and not interaction.dragging_peak and not interaction.dragging_pad then
        local cursor_pos = r.GetCursorPosition()
        local margin = length * 0.1 
        if cursor_pos > (start_time + margin) and cursor_pos < (end_time - margin) then
            config.peak_pos = (cursor_pos - start_time) / length
            peak_time = cursor_pos
        end
    end

    local fx = GetOrAddFX(track, "sbp_WhooshEngine")
    
    if IDX.global_pitch == -1 then
        IDX.global_pitch = FindParamByName(track, fx, "Global Pitch")
        if IDX.global_pitch == -1 then IDX.global_pitch = FindParamByName(track, fx, "pitch") end
        if IDX.global_pitch == -1 then IDX.global_pitch = 43 end 
    end
    
    local sub_vol_idx = FindParamByName(track, fx, "Sub Vol")
    if sub_vol_idx == -1 then sub_vol_idx = FindParamByName(track, fx, "Sub Direct") end
    if sub_vol_idx >= 0 then IDX.sub_direct_vol = sub_vol_idx end
    local sub_freq_idx = FindParamByName(track, fx, "Sub Freq")
    if sub_freq_idx >= 0 then IDX.sub_freq = sub_freq_idx end
    
    local det_idx = FindParamByName(track, fx, "Detune")
    if det_idx >= 0 then IDX.saw_detune = det_idx end
    
    local chop_depth_idx = FindParamByName(track, fx, "Chop: Depth")
    if chop_depth_idx >= 0 then IDX.chop_depth = chop_depth_idx end
    local chop_rate_idx = FindParamByName(track, fx, "Chop: Rate")
    if chop_rate_idx >= 0 then IDX.chop_rate = chop_rate_idx end
    local chop_shape_idx = FindParamByName(track, fx, "Chop: Shape")
    if chop_shape_idx >= 0 then IDX.chop_shape = chop_shape_idx end

    r.TrackFX_SetParam(track, fx, IDX.out_mode, settings.output_mode)
    r.TrackFX_SetParam(track, fx, IDX.sub_freq, config.sub_freq)
    r.TrackFX_SetParam(track, fx, IDX.sub_direct_vol, config.sub_enable and config.sub_vol or 0)
    
    r.TrackFX_SetParam(track, fx, IDX.trim_w, config.trim_w)
    r.TrackFX_SetParam(track, fx, IDX.trim_s, config.trim_s)
    r.TrackFX_SetParam(track, fx, IDX.trim_c, config.trim_c)
    r.TrackFX_SetParam(track, fx, IDX.trim_e, config.trim_e)
    r.TrackFX_SetParam(track, fx, IDX.chop_shape, config.chop_shape)

    r.TrackFX_SetParam(track, fx, IDX.saw_pwm, config.saw_pwm)
    r.TrackFX_SetParam(track, fx, IDX.saw_detune, config.saw_detune)
    
    r.TrackFX_SetParam(track, fx, IDX.chua_rate, config.chua_rate)
    r.TrackFX_SetParam(track, fx, IDX.chua_shape, config.chua_shape)
    r.TrackFX_SetParam(track, fx, IDX.chua_timbre, config.chua_timbre)
    
    r.TrackFX_SetParam(track, fx, IDX.flange_wet, config.flange_wet)
    r.TrackFX_SetParam(track, fx, IDX.flange_feed, config.flange_feed)
    r.TrackFX_SetParam(track, fx, IDX.dbl_wide, config.dbl_wide)
    r.TrackFX_SetParam(track, fx, IDX.dbl_time, config.dbl_time)
    r.TrackFX_SetParam(track, fx, IDX.rev_damp, config.rev_damp)
    r.TrackFX_SetParam(track, fx, IDX.verb_size, config.verb_size)

    r.Undo_BeginBlock()
    r.SetOnlyTrackSelected(track)
    
    if flags == "all" or flags == "env" or flags == "vol" then
        CreateEnvelopeCurveTrack(track, "Volume", start_time, peak_time, end_time, 0.0, 1.0, config.tens_attack, config.tens_release)
    end

    if flags == "all" or flags == "env" then
        local function SCurve(t) return t*t*t / (t*t*t + (1-t)*(1-t)*(1-t)) end
        local function get_vols(x, y) 
            local sx, sy = SCurve(x), SCurve(y)
            return (1-sx)*sy, sx*sy, (1-sx)*(1-sy), sx*(1-sy) 
        end
        local v1_s, v2_s, v3_s, v4_s = get_vols(config.src_s_x, config.src_s_y)
        local v1_p, v2_p, v3_p, v4_p = get_vols(config.src_p_x, config.src_p_y)
        local v1_e, v2_e, v3_e, v4_e = get_vols(config.src_e_x, config.src_e_y)
        
        if config.mute_w then v1_s=0;v1_p=0;v1_e=0 end
        if config.mute_s then v2_s=0;v2_p=0;v2_e=0 end
        if config.mute_c then v3_s=0;v3_p=0;v3_e=0 end
        if config.mute_e then v4_s=0;v4_p=0;v4_e=0 end
        Create3PointRampFX(track, fx, IDX.mix_vol1, start_time, peak_time, end_time, v1_s, v1_p, v1_e)
        Create3PointRampFX(track, fx, IDX.mix_vol2, start_time, peak_time, end_time, v2_s, v2_p, v2_e)
        Create3PointRampFX(track, fx, IDX.mix_vol3, start_time, peak_time, end_time, v3_s, v3_p, v3_e)
        Create3PointRampFX(track, fx, IDX.mix_vol4, start_time, peak_time, end_time, v4_s, v4_p, v4_e)

        Create3PointRampFX(track, fx, IDX.filt_morph_x, start_time, peak_time, end_time, config.morph_s_x, config.morph_p_x, config.morph_e_x)
        Create3PointRampFX(track, fx, IDX.filt_morph_y, start_time, peak_time, end_time, config.morph_s_y, config.morph_p_y, config.morph_e_y)
        Create3PointRampFX(track, fx, IDX.filt_freq, start_time, peak_time, end_time, config.cut_s_x, config.cut_p_x, config.cut_e_x)
        Create3PointRampFX(track, fx, IDX.filt_res, start_time, peak_time, end_time, config.cut_s_y*0.98, config.cut_p_y*0.98, config.cut_e_y*0.98)

        if settings.output_mode == 0 then
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, config.spc_s_x, config.spc_p_x, config.spc_e_x)
            local function GetDblRev(y, x) return y * (1-x), y * x end
            local d_s, r_s = GetDblRev(config.spc_s_y, config.spc_s_x)
            local d_p, r_p = GetDblRev(config.spc_p_y, config.spc_p_x)
            local d_e, r_e = GetDblRev(config.spc_e_y, config.spc_e_x)
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, d_s, d_p, d_e)
            Create3PointRampFX(track, fx, IDX.verb_wet, start_time, peak_time, end_time, r_s, r_p, r_e)
            Create3PointRampFX(track, fx, IDX.pan_x, start_time, peak_time, end_time, config.dop_s_x, config.dop_p_x, config.dop_e_x)
        else
            Create3PointRampFX(track, fx, IDX.pan_x, start_time, peak_time, end_time, config.spc_s_x, config.spc_p_x, config.spc_e_x)
            Create3PointRampFX(track, fx, IDX.pan_y, start_time, peak_time, end_time, config.spc_s_y, config.spc_p_y, config.spc_e_y)
            Create3PointRampFX(track, fx, IDX.verb_wet, start_time, peak_time, end_time, config.dop_s_x, config.dop_p_x, config.dop_e_x)
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, 0, 0, 0)
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, 0, 0, 0)
        end
        
        -- Chopper Automation (X=Rate, Y=Depth) IF ENABLED
        local ch_s_y = config.chop_enable and config.chop_s_y or 0
        local ch_p_y = config.chop_enable and config.chop_p_y or 0
        local ch_e_y = config.chop_enable and config.chop_e_y or 0
        
        Create3PointRampFX(track, fx, IDX.chop_rate, start_time, peak_time, end_time, config.chop_s_x, config.chop_p_x, config.chop_e_x)
        Create3PointRampFX(track, fx, IDX.chop_depth, start_time, peak_time, end_time, ch_s_y, ch_p_y, ch_e_y)

        if IDX.global_pitch >= 0 then
            local p_s = ToPitch(config.dop_s_y)
            local p_p = ToPitch(config.dop_p_y)
            local p_e = ToPitch(config.dop_e_y)
            Create3PointRampFX(track, fx, IDX.global_pitch, start_time, peak_time, end_time, p_s, p_p, p_e)
            r.TrackFX_SetParam(track, fx, IDX.global_pitch, p_p)
        end
    end
    r.Undo_EndBlock("Update Whoosh", 4)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

-- =========================================================
-- UI DRAWING
-- =========================================================

function DrawEnvelopePreview(w, h, col_acc)
    r.ImGui_Dummy(ctx, w, h)
    local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    
    local draw_h = PAD_DRAW_H 
    if not w or w <= 0 then w = 170 end
    
    col_acc = SafeCol(col_acc, 0x2D8C6DFF)
    
    local changed = false
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + draw_h, C_FRAME_BG, 4)
    r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + w, p_y + draw_h, 0xFFFFFF30, 4)
    
    local peak_pos = config.peak_pos or 0.5
    local peak_x = p_x + (w * peak_pos)
    local peak_y = p_y + 10
    local start_y, end_y, end_x = p_y + draw_h - 10, p_y + draw_h - 10, p_x + w
    
    r.ImGui_SetCursorScreenPos(ctx, peak_x - 5, p_y)
    r.ImGui_InvisibleButton(ctx, "##peak_drag", 10, draw_h)
    
    if r.ImGui_IsItemActive(ctx) then
        interaction.dragging_peak = true
        local dx = r.ImGui_GetMouseDelta(ctx)
        config.peak_pos = Clamp(config.peak_pos + (dx/w), 0.1, 0.9); changed = true
    else
        interaction.dragging_peak = false
    end
    
    r.ImGui_DrawList_AddLine(draw_list, peak_x, p_y+5, peak_x, p_y+draw_h-5, 0xFFFFFF30)
    r.ImGui_DrawList_AddCircle(draw_list, p_x+10, start_y, 6, C_GREY, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, peak_x-6, peak_y-6, peak_x+6, peak_y+6, 0xFFFFFFFF)
    
    local arrow_size = 7
    local dx = (end_x-10) - peak_x
    local dy = end_y - peak_y
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 0.1 then
        dx = dx / len
        dy = dy / len
        local perp_x, perp_y = -dy, dx
        local tip_x, tip_y = end_x-10, end_y
        local base_x, base_y = (end_x-10) - dx * arrow_size, end_y - dy * arrow_size
        local left_x, left_y = base_x - perp_x * (arrow_size * 0.7), base_y - perp_y * (arrow_size * 0.7)
        local right_x, right_y = base_x + perp_x * (arrow_size * 0.7), base_y + perp_y * (arrow_size * 0.7)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, tip_x, tip_y, left_x, left_y, right_x, right_y, col_acc)
    else
        r.ImGui_DrawList_AddCircleFilled(draw_list, end_x-10, end_y, 6, col_acc)
    end

    if settings.env_shape == 0 then -- BEZIER (Default)
        local function GetCPs(t, x1, y1, x2, y2)
            local mx, my = (x1+x2)*0.5, (y1+y2)*0.5; local str = math.abs(t) * 100
            if t > 0 then return mx, my - str else return mx, my + str end
        end
        local c1x, c1y = GetCPs(-config.tens_attack, p_x, start_y, peak_x, peak_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, c1x, c1y, c1x, c1y, peak_x, peak_y, col_acc, 2, 20)
        local c2x, c2y = GetCPs(config.tens_release, peak_x, peak_y, end_x, end_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x, peak_y, c2x, c2y, c2x, c2y, end_x-10, end_y, col_acc, 2, 20)
    elseif settings.env_shape == 1 then -- LINEAR
        r.ImGui_DrawList_AddLine(draw_list, p_x+10, start_y, peak_x, peak_y, col_acc, 2)
        r.ImGui_DrawList_AddLine(draw_list, peak_x, peak_y, end_x-10, end_y, col_acc, 2)
    elseif settings.env_shape == 2 then -- SLOW START/END
        local tension_scale = 0.4 
        local cp1_x = p_x+10 + (peak_x - (p_x+10)) * tension_scale
        local cp2_x = peak_x - (peak_x - (p_x+10)) * tension_scale
        local cp3_x = peak_x + (end_x - peak_x) * tension_scale
        local cp4_x = end_x - (end_x - peak_x) * tension_scale
        r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, cp1_x, start_y, cp2_x, peak_y, peak_x, peak_y, col_acc, 2, 20)
        r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x, peak_y, cp3_x, peak_y, cp4_x, end_y, end_x-10, end_y, col_acc, 2, 20)
    end
    
    if settings.env_shape == 0 then
        local slider_w = w * 0.35 * 0.7 
        local margin_side = 45
        local margin_bot = 35
        local y_pos = p_y + draw_h - margin_bot
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x444444FF) 
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col_acc)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 1) 
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 16) 
        
        r.ImGui_SetCursorScreenPos(ctx, p_x + margin_side, y_pos)
        r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv1, v1 = r.ImGui_SliderDouble(ctx, "##Att", config.tens_attack, -1, 1, "Att: %.2f"); 
        if rv1 then config.tens_attack=v1; changed=true end
        
        r.ImGui_SetCursorScreenPos(ctx, p_x + w - slider_w - margin_side, y_pos)
        r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv2, v2 = r.ImGui_SliderDouble(ctx, "##Rel", config.tens_release, -1, 1, "Rel: %.2f"); 
        if rv2 then config.tens_release=v2; changed=true end
        
        r.ImGui_PopStyleVar(ctx, 4)
        r.ImGui_PopStyleColor(ctx, 2)
    end
    
    return changed
end

function DrawVectorPad(label, p_idx, w, h, col_acc, col_bg)
    if p_idx == 4 then -- DOPPLER (Square)
        w = PAD_DRAW_H 
    elseif p_idx == 6 then -- CHOPPER (Remaining)
        w = r.ImGui_GetContentRegionAvail(ctx) -- Use ALL remaining width (No Spacing subtractions)
    else
        if not w or w <= 0 then w = 170 end
    end
    
    if not h or h <= 0 then h = 170 end
    
    r.ImGui_Dummy(ctx, w, h)
    local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    
    local draw_h = PAD_DRAW_H
    
    col_acc = SafeCol(col_acc, 0x2D8C6DFF)
    col_bg = SafeCol(col_bg, 0x252525FF)
    
    local changed = false
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + draw_h, C_FRAME_BG, 4)
    r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + w, p_y + draw_h, 0xFFFFFF30, 4)
    r.ImGui_DrawList_AddLine(draw_list, p_x + w*0.5, p_y, p_x + w*0.5, p_y + draw_h, col_bg + 0x20202020)
    r.ImGui_DrawList_AddLine(draw_list, p_x, p_y + draw_h*0.5, p_x + w, p_y + draw_h*0.5, col_bg + 0x20202020)
    
    local txt_col = 0xFFFFFF60
    local t1,t2,t3,t4="","","",""
    
    if p_idx == 4 then 
        if settings.output_mode == 0 then t1="L"; t2="R"; t3="Pitch-"; t4="Pitch+"
        else t1="Dry"; t2="Wet"; t3="Pitch-"; t4="Pitch+" end
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+5, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-25, p_y+5, txt_col, t2)
        r.ImGui_DrawList_AddText(draw_list, p_x+w*0.5-20, p_y+draw_h-18, txt_col, t3)
        r.ImGui_DrawList_AddText(draw_list, p_x+w*0.5-20, p_y+5, txt_col, t4)
    elseif p_idx == 6 then -- Chopper Labels
        t1="Slow"; t2="Fast"; t3="Clean"; t4="Deep"
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+draw_h-18, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-35, p_y+draw_h-18, txt_col, t2)
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+5, txt_col, t3)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-35, p_y+5, txt_col, t4)
        
        -- REMOVED TOGGLE BUTTON HERE

    elseif p_idx == 5 then -- Space Labels
        if settings.output_mode == 0 then t1="Dbl"; t2="Rev"; t3="Mono"; t4="Spread"
        else t1="Front L"; t2="Front R"; t3="Rear L"; t4="Rear R" end
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+5, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-30, p_y+5, txt_col, t2) -- Aligned Right
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+draw_h-18, txt_col, t3)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-45, p_y+draw_h-18, txt_col, t4)
    else
        if p_idx==1 then t1="White";t2="Saw";t3="Chua";t4="Ext"
        elseif p_idx==2 then t1="HP";t2="BR";t3="LP";t4="BP"
        elseif p_idx==3 then t1="Res";t4="Cut" end
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+5, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-30, p_y+5, txt_col, t2)
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+draw_h-18, txt_col, t3)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-30, p_y+draw_h-18, txt_col, t4)
    end

    local hit_margin = 8
    r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
    r.ImGui_InvisibleButton(ctx, label, w + hit_margin*2, draw_h + hit_margin*2)
    local is_clicked = r.ImGui_IsItemClicked(ctx)
    local is_active = r.ImGui_IsItemActive(ctx)
    
    local sx, sy, px, py, ex, ey
    if p_idx==1 then sx = config.src_s_x or 0; sy = config.src_s_y or 1; px=config.src_p_x or 0.5; py=config.src_p_y or 0.5; ex=config.src_e_x or 1; ey=config.src_e_y or 1
    elseif p_idx==2 then sx = config.morph_s_x or 0; sy = config.morph_s_y or 0; px=config.morph_p_x or 0.5; py=config.morph_p_y or 0.5; ex=config.morph_e_x or 1; ey=config.morph_e_y or 1
    elseif p_idx==3 then sx = config.cut_s_x or 0; sy = config.cut_s_y or 0; px=config.cut_p_x or 0.5; py=config.cut_p_y or 0.5; ex=config.cut_e_x or 1; ey=config.cut_e_y or 1
    elseif p_idx==4 then sx = config.dop_s_x or 0; sy = config.dop_s_y or 0.5; px=config.dop_p_x or 0.5; py=config.dop_p_y or 0.5; ex=config.dop_e_x or 1; ey=config.dop_e_y or 0.5
    elseif p_idx==5 then sx = config.spc_s_x or 0; sy = config.spc_s_y or 0; px=config.spc_p_x or 0.5; py=config.spc_p_y or 0.5; ex=config.spc_e_x or 1; ey=config.spc_e_y or 1 
    elseif p_idx==6 then sx = config.chop_s_x or 0; sy = config.chop_s_y or 0; px=config.chop_p_x or 0; py=config.chop_p_y or 0; ex=config.chop_e_x or 0; ey=config.chop_e_y or 0 end
    
    if is_clicked then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*h
        local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*h
        local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*h
        local hit_r = 1000 
        interaction.dragging_pad = p_idx
        local dist_s = (mx-s_sc_x)^2+(my-s_sc_y)^2
        local dist_p = (mx-p_sc_x)^2+(my-p_sc_y)^2
        local dist_e = (mx-e_sc_x)^2+(my-e_sc_y)^2
        if dist_s < hit_r and dist_s < dist_p and dist_s < dist_e then interaction.dragging_point = 1
        elseif dist_p < hit_r and dist_p < dist_e then interaction.dragging_point = 2
        elseif dist_e < hit_r then interaction.dragging_point = 3
        else interaction.dragging_pad = nil end 
    end
    if not r.ImGui_IsMouseDown(ctx, 0) then interaction.dragging_pad = nil end

    if is_active and interaction.dragging_pad == p_idx then
        local dx, dy = r.ImGui_GetMouseDelta(ctx)
        local dnx, dny = dx/w, -dy/h
        if interaction.dragging_point == 1 then sx=Clamp(sx+dnx,0,1); sy=Clamp(sy+dny,0,1); changed=true
        elseif interaction.dragging_point == 2 then px=Clamp(px+dnx,0,1); py=Clamp(py+dny,0,1); changed=true
        elseif interaction.dragging_point == 3 then ex=Clamp(ex+dnx,0,1); ey=Clamp(ey+dny,0,1); changed=true end
        if changed then
            if p_idx==1 then config.src_s_x,config.src_s_y,config.src_p_x,config.src_p_y,config.src_e_x,config.src_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==2 then config.morph_s_x,config.morph_s_y,config.morph_p_x,config.morph_p_y,config.morph_e_x,config.morph_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==3 then config.cut_s_x,config.cut_s_y,config.cut_p_x,config.cut_p_y,config.cut_e_x,config.cut_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==4 then config.dop_s_x,config.dop_s_y,config.dop_p_x,config.dop_p_y,config.dop_e_x,config.dop_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==5 then config.spc_s_x,config.spc_s_y,config.spc_p_x,config.spc_p_y,config.spc_e_x,config.spc_e_y = sx,sy,px,py,ex,ey 
            elseif p_idx==6 then config.chop_s_x,config.chop_s_y,config.chop_p_x,config.chop_p_y,config.chop_e_x,config.chop_e_y = sx,sy,px,py,ex,ey end
        end
    end

    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*h
    local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*h
    local e_x, e_y = p_x + ex*w, p_y + (1-ey)*h
    r.ImGui_DrawList_AddLine(draw_list, s_x, s_y, p_x_d, p_y_d, col_acc & 0xFFFFFF40, 2)
    r.ImGui_DrawList_AddLine(draw_list, p_x_d, p_y_d, e_x, e_y, col_acc & 0xFFFFFF40, 2)
    
    r.ImGui_DrawList_AddCircle(draw_list, s_x, s_y, 5, 0xAAAAAAFF, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x_d-4, p_y_d-4, p_x_d+4, p_y_d+4, 0xFFFFFFFF)
    -- End point as triangle arrow
    local arrow_size = 7
    local dx = e_x - p_x_d
    local dy = e_y - p_y_d
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 0.1 then
        dx = dx / len
        dy = dy / len
        local perp_x, perp_y = -dy, dx
        local tip_x, tip_y = e_x, e_y
        local base_x, base_y = e_x - dx * arrow_size, e_y - dy * arrow_size
        local left_x, left_y = base_x - perp_x * (arrow_size * 0.7), base_y - perp_y * (arrow_size * 0.7)
        local right_x, right_y = base_x + perp_x * (arrow_size * 0.7), base_y + perp_y * (arrow_size * 0.7)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, tip_x, tip_y, left_x, left_y, right_x, right_y, col_acc)
    else
        r.ImGui_DrawList_AddCircleFilled(draw_list, e_x, e_y, 6, col_acc)
    end
    
    return changed
end

-- MAIN FUNCTION DEFINED BEFORE LOOP
function GenerateWhoosh()
    r.PreventUIRefresh(1)
    local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then r.ShowMessageBox("Select time!", "Error", 0); r.PreventUIRefresh(-1); return end
    
    local track = FindTrackByName(settings.track_name)
    if not track then
        r.InsertTrackAtIndex(r.CountTracks(0), true)
        track = r.GetTrack(0, r.CountTracks(0)-1)
        r.GetSetMediaTrackInfo_String(track, "P_NAME", settings.track_name, true)
    end
    r.SetMediaTrackInfo_Value(track, "I_NCHAN", settings.output_mode == 1 and 6 or 2)
    
    local fx = GetOrAddFX(track, "sbp_WhooshEngine")
    local item = r.CreateNewMIDIItemInProj(track, start_time, end_time, false)
    r.SetMediaItemSelected(item, true)
    
    local take = r.GetActiveTake(item)
    if take then
        local len = r.MIDI_GetPPQPosFromProjTime(take, end_time)
        r.MIDI_InsertNote(take, false, false, 0, len, 0, 60, 100, false)
    end
    
    if IDX.global_pitch == -1 then 
        IDX.global_pitch = FindParamByName(track, fx, "Global Pitch")
        if IDX.global_pitch == -1 then IDX.global_pitch = 43 end
    end
    
    UpdateAutomationOnly("all")
    r.PreventUIRefresh(-1)
    ShowAllEnvelopes()
end

function Loop()
    local c_bg = SafeCol(settings.col_bg, 0x252525FF)
    local c_acc = SafeCol(settings.col_accent, 0x2D8C6DFF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x202020FF)
    
    -- Removed Global Forced Green Hover
    -- r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c_acc + 0x10101000) 
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c_acc)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE0E0E0FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), c_acc)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), c_acc)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000060)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x00000080)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x00000080)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), c_acc)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12) 
    
    r.ImGui_SetNextWindowSizeConstraints(ctx, 950, 750, 1600, 1200)
    
    local visible, open = r.ImGui_Begin(ctx, 'ReaWhoosh v4.5', true)
    if visible then
        local changed_any = false
        
        -- HEADER
        r.ImGui_Text(ctx, "PRESETS:"); r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 200)
        if r.ImGui_BeginCombo(ctx, "##presets", config.current_preset) then
            r.ImGui_TextDisabled(ctx, "-- Factory --")
            for name, _ in pairs(FACTORY_PRESETS) do 
                if r.ImGui_Selectable(ctx, name, config.current_preset == name) then 
                    ApplyPreset(name)
                    changed_any=true 
                end 
            end
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "-- User --")
            for name, _ in pairs(USER_PRESETS) do
                if r.ImGui_Selectable(ctx, name, config.current_preset == name) then 
                    ApplyPreset(name)
                    changed_any=true 
                end
            end
            r.ImGui_EndCombo(ctx) 
        end
        r.ImGui_SameLine(ctx)
        
        -- PRESET BUTTONS
        if r.ImGui_Button(ctx, "+", 24, 0) then SHOW_SAVE_MODAL = true; PRESET_INPUT_BUF = "My Preset"; DO_FOCUS_INPUT = true end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "-", 24, 0) then 
            if USER_PRESETS[config.current_preset] then 
                DeleteUserPreset(config.current_preset)
                changed_any = true
            end 
        end

        -- RANDOMIZE Button
        r.ImGui_SameLine(ctx)
        
        local rand_col = 0xD46A3FFF
        local rand_hov = DarkenColor(rand_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rand_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rand_hov)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), rand_col)
        
        if r.ImGui_Button(ctx, "Randomize", 80, 0) then RandomizeConfig(); changed_any=true end
        r.ImGui_PopStyleColor(ctx, 3)

        -- OPTIONS Button
        r.ImGui_SameLine(ctx)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_Dummy(ctx, avail_w - 85, 0) -- Spacer
        r.ImGui_SameLine(ctx)
        
        local opt_hov = DarkenColor(c_acc)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_acc)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), opt_hov)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c_acc)
        
        if r.ImGui_Button(ctx, "Options", 80) then r.ImGui_OpenPopup(ctx, "Settings") end
        r.ImGui_PopStyleColor(ctx, 3)
        
        -- MODALS
        if SHOW_SAVE_MODAL then r.ImGui_OpenPopup(ctx, "Save Preset") end
        if r.ImGui_BeginPopupModal(ctx, "Save Preset", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Preset Name:")
            if DO_FOCUS_INPUT then
                r.ImGui_SetKeyboardFocusHere(ctx)
                DO_FOCUS_INPUT = false
            end
            local ret, str = r.ImGui_InputText(ctx, "##pname", PRESET_INPUT_BUF)
            if ret then PRESET_INPUT_BUF = str end
            if r.ImGui_Button(ctx, "SAVE", 100, 0) then
                SaveUserPreset(PRESET_INPUT_BUF)
                SHOW_SAVE_MODAL = false
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "CANCEL", 100, 0) then
                SHOW_SAVE_MODAL = false
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_EndPopup(ctx)
        end

        if r.ImGui_BeginPopupModal(ctx, "Settings", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_TextDisabled(ctx, "-- Track Name --")
            local rv, txt = r.ImGui_InputText(ctx, "##trname", settings.track_name)
            if rv then settings.track_name = txt; SaveSettings() end
            r.ImGui_Separator(ctx)

            r.ImGui_TextDisabled(ctx, "-- Output Mode --")
            if r.ImGui_RadioButton(ctx, "Stereo", settings.output_mode==0) then settings.output_mode=0; changed_any=true end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Surround", settings.output_mode==1) then settings.output_mode=1; changed_any=true end
            
            if settings.output_mode == 1 then
                r.ImGui_TextColored(ctx, 0xFF9900FF, "Don't forget to switch Track & Master to Multichannel!")
            end
            
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "-- Envelope Shape --")
            if r.ImGui_RadioButton(ctx, "Default (Bezier)", settings.env_shape==0) then settings.env_shape=0 end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Linear", settings.env_shape==1) then settings.env_shape=1 end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Slow Start/End", settings.env_shape==2) then settings.env_shape=2 end

            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "-- Peak Behavior --")
            if r.ImGui_RadioButton(ctx, "Manual (Slider)", settings.peak_mode==0) then settings.peak_mode=0 end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Follow Edit Cursor", settings.peak_mode==1) then settings.peak_mode=1 end

            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "-- Chopper Settings --")
            local rv_s, v_s = r.ImGui_SliderDouble(ctx, "Chopper Shape", config.chop_shape, 0, 1, "Hard -> Soft")
            if rv_s then config.chop_shape = v_s; changed_any=true end
            
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "-- Randomization Targets --")
            local _, b1 = r.ImGui_Checkbox(ctx, "Source Mix", settings.rand_src); if _ then settings.rand_src=b1 end
            r.ImGui_SameLine(ctx)
            local _, b2 = r.ImGui_Checkbox(ctx, "Morph Filter", settings.rand_morph); if _ then settings.rand_morph=b2 end
            r.ImGui_SameLine(ctx)
            local _, b3 = r.ImGui_Checkbox(ctx, "Cut/Res", settings.rand_filt); if _ then settings.rand_filt=b3 end
            local _, b4 = r.ImGui_Checkbox(ctx, "Doppler", settings.rand_dop); if _ then settings.rand_dop=b4 end
            r.ImGui_SameLine(ctx)
            local _, b5 = r.ImGui_Checkbox(ctx, "Space (FX)", settings.rand_space); if _ then settings.rand_space=b5 end
            r.ImGui_SameLine(ctx)
            local _, b6 = r.ImGui_Checkbox(ctx, "Chopper", settings.rand_chop); if _ then settings.rand_chop=b6 end
            local _, b7 = r.ImGui_Checkbox(ctx, "Volume Env", settings.rand_env); if _ then settings.rand_env=b7 end

            if r.ImGui_Button(ctx, "Close") then SaveSettings(); r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_EndPopup(ctx)
        end

        r.ImGui_Separator(ctx)

        -- 3 COLS
        if r.ImGui_BeginTable(ctx, "MainTable", 2) then
            r.ImGui_TableSetupColumn(ctx, "LeftQuad", r.ImGui_TableColumnFlags_WidthFixed(), 430) 
            r.ImGui_TableSetupColumn(ctx, "RightCol", r.ImGui_TableColumnFlags_WidthStretch()) 
            
            -- LEFT
            r.ImGui_TableNextColumn(ctx)
            if r.ImGui_BeginTable(ctx, "PadsGrid", 2) then
                r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Source Mix"); if DrawVectorPad("##src", 1, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Morph Filter"); if DrawVectorPad("##morph", 2, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                
                -- Capture start of Row 2 for alignment
                r.ImGui_TableNextColumn(ctx) 
                local row2_y = select(2, r.ImGui_GetCursorScreenPos(ctx))
                
                r.ImGui_Text(ctx, "Space Pad"); if DrawVectorPad("##space", 5, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Cut / Res"); if DrawVectorPad("##cut", 3, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                r.ImGui_EndTable(ctx)
                
                -- Store the anchor Y for right column
                settings.anchor_y = row2_y
            end
            
            -- RIGHT
            r.ImGui_TableNextColumn(ctx)
            local right_w = r.ImGui_GetContentRegionAvail(ctx)
            
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
            
            -- 1. TOP BLOCK
            if r.ImGui_BeginChild(ctx, "TopBlock", 0, CONTAINER_H, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_Text(ctx, " Volume Envelope") 
                if DrawEnvelopePreview(right_w, PAD_DRAW_H, c_acc) then changed_any=true end
                r.ImGui_EndChild(ctx)
            end
            
            -- 2. BOTTOM BLOCK (Aligned to Left Column Row 2)
            if settings.anchor_y then
               local cx = select(1, r.ImGui_GetCursorScreenPos(ctx))
               r.ImGui_SetCursorScreenPos(ctx, cx, settings.anchor_y)
            end

            if r.ImGui_BeginChild(ctx, "BotBlock", 0, CONTAINER_H, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                if r.ImGui_BeginTable(ctx, "SplitPads", 2) then
                    r.ImGui_TableSetupColumn(ctx, "Dop", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE + 50) 
                    r.ImGui_TableSetupColumn(ctx, "Gran", r.ImGui_TableColumnFlags_WidthStretch()) 

                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, " Doppler Pad")
                    if DrawVectorPad("##doppler", 4, -1, PAD_DRAW_H, c_acc, c_bg) then changed_any=true end
                    
                    r.ImGui_TableNextColumn(ctx); 
                    -- Title with Toggle (REMOVED TOGGLE)
                    r.ImGui_Text(ctx, " Texture / Chopper  ")
                    
                    -- REMOVED SameLine HERE
                    
                    -- REMOVED BUTTON CODE HERE
                    
                    if DrawVectorPad("##granular", 6, -1, PAD_DRAW_H, c_acc, c_bg) then changed_any=true end
                    
                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_EndChild(ctx)
            end
            
            r.ImGui_PopStyleVar(ctx, 1)
            
            r.ImGui_EndTable(ctx)
        end
        
        r.ImGui_Separator(ctx)
        
        -- BOTTOM
        if r.ImGui_BeginTable(ctx, "BotTable", 4, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "Mix", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "Gen", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "FX", r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, "Actions", r.ImGui_TableColumnFlags_WidthFixed(), 150) 

            -- 1. FADERS
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Text(ctx, "MIXER")
            
            -- MASTER VOL
            r.ImGui_BeginGroup(ctx)
                r.ImGui_Text(ctx, "Mst")
                r.ImGui_PushID(ctx, "Mst")
                r.ImGui_SetNextItemWidth(ctx, 30) 
                local rv, v = r.ImGui_VSliderDouble(ctx, "##v", 30, MIX_H + 25, settings.master_vol, -60, 12, "")
                r.ImGui_PopID(ctx); if rv then settings.master_vol=v; changed_any=true end
            r.ImGui_EndGroup(ctx); r.ImGui_SameLine(ctx)

            -- MIX STRIPS WITH VERTICAL METERS
            local function DrawStrip(lbl, val, muted, meter_idx)
                r.ImGui_BeginGroup(ctx)
                r.ImGui_Text(ctx, lbl)
                r.ImGui_PushID(ctx, lbl)
                
                -- Fader (Max 1.35 = +2.5dB Boost)
                r.ImGui_SetNextItemWidth(ctx, 15) 
                local rv, v = r.ImGui_VSliderDouble(ctx, "##v", 15, MIX_H, val, 0, 1.35, "")
                if rv then val=v; changed_any=true end
                r.ImGui_PopID(ctx)
                
                -- METER (Next to fader)
                r.ImGui_SameLine(ctx)
                local m_val = r.gmem_read(meter_idx) or 0
                -- Scaling: 0dB (1.0) is at 0.75 height. Max is +6dB.
                local m_norm = math.min(m_val * 0.75, 1.0) 
                
                r.ImGui_Dummy(ctx, 8, MIX_H)
                local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx)
                local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx)
                local dl = r.ImGui_GetWindowDrawList(ctx)
                
                -- BG
                r.ImGui_DrawList_AddRectFilled(dl, p_min_x, p_min_y, p_max_x, p_max_y, 0x000000FF)
                
                -- Fill
                local height_px = (p_max_y - p_min_y)
                local fill_h = height_px * m_norm
                
                -- Color Logic (Green -> Red if clipping)
                local col = 0x2D8C6DFF
                if m_norm > 0.75 then col = 0xFF4040FF end 
                
                r.ImGui_DrawList_AddRectFilled(dl, p_min_x, p_max_y - fill_h, p_max_x, p_max_y, col)
                
                -- 0dB Line (at 75%)
                local zero_y = p_min_y + (height_px * 0.25)
                r.ImGui_DrawList_AddLine(dl, p_min_x-2, zero_y, p_max_x+2, zero_y, 0xFFFFFF80)

                r.ImGui_PushID(ctx, "m_"..lbl)
                if muted then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF4040FF) else r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000060) end
                if r.ImGui_Button(ctx, "M", 25, 20) then muted = not muted; changed_any=true end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_PopID(ctx)
                r.ImGui_EndGroup(ctx)
                return val, muted
            end
            
            config.trim_w, config.mute_w = DrawStrip("W", config.trim_w, config.mute_w, 0); r.ImGui_SameLine(ctx)
            config.trim_s, config.mute_s = DrawStrip("S", config.trim_s, config.mute_s, 1); r.ImGui_SameLine(ctx)
            config.trim_c, config.mute_c = DrawStrip("C", config.trim_c, config.mute_c, 2); r.ImGui_SameLine(ctx)
            config.trim_e, config.mute_e = DrawStrip("E", config.trim_e, config.mute_e, 3); r.ImGui_SameLine(ctx)
            
            -- SUB
            r.ImGui_BeginGroup(ctx)
            r.ImGui_Text(ctx, "Sub")
            r.ImGui_PushID(ctx, "Sub")
            r.ImGui_SetNextItemWidth(ctx, 15)
            local rv_sv, v_sv = r.ImGui_VSliderDouble(ctx, "##v", 15, MIX_H, config.sub_vol, 0, 1.35, "")
            if rv_sv then config.sub_vol=v_sv; changed_any=true end
            r.ImGui_PopID(ctx)
            
            -- SUB METER
            r.ImGui_SameLine(ctx)
            local s_val = r.gmem_read(6) or 0
            local s_norm = math.min(s_val * 0.75, 1.0)
            
            r.ImGui_Dummy(ctx, 8, MIX_H)
            local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx)
            local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx)
            local dl = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, p_min_x, p_min_y, p_max_x, p_max_y, 0x000000FF)
            local fill_h = (p_max_y - p_min_y) * s_norm
            local col = 0x2D8C6DFF
            if s_norm > 0.75 then col = 0xFF4040FF end
            r.ImGui_DrawList_AddRectFilled(dl, p_min_x, p_max_y - fill_h, p_max_x, p_max_y, col)
            local zero_y = p_min_y + ((p_max_y - p_min_y) * 0.25)
            r.ImGui_DrawList_AddLine(dl, p_min_x-2, zero_y, p_max_x+2, zero_y, 0xFFFFFF80)

            r.ImGui_PushID(ctx, "s_on")
            local btn_col = config.sub_enable and c_acc or C_ORANGE
            local hov_col = DarkenColor(btn_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hov_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_col)
            
            if r.ImGui_Button(ctx, config.sub_enable and "ON" or "OFF", 25, 20) then 
                config.sub_enable = not config.sub_enable
                changed_any=true 
            end
            r.ImGui_PopStyleColor(ctx, 3); 
            r.ImGui_PopID(ctx); r.ImGui_EndGroup(ctx)

            -- 2. GENERATORS
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Text(ctx, "GENERATORS")
            r.ImGui_SetNextItemWidth(ctx, 150); local rv, v = r.ImGui_SliderInt(ctx, "Base Hz", config.sub_freq, 30, 120); if rv then config.sub_freq=v; changed_any=true end
            r.ImGui_Separator(ctx) 
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Saw PWM", config.saw_pwm, 0, 1); if rv then config.saw_pwm=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Saw Detune", config.saw_detune, -50, 50, "%.1f ct"); if rv then config.saw_detune=v; changed_any=true end
            
            r.ImGui_Separator(ctx) 
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Chua Rate", config.chua_rate, 0, 0.5); if rv then config.chua_rate=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Chua Shape", config.chua_shape, 10, 45); if rv then config.chua_shape=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Chua Timbre", config.chua_timbre, -20, 20); if rv then config.chua_timbre=v; changed_any=true end

            -- 3. EFFECTS
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Text(ctx, "EFFECTS")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Flg Mix", config.flange_wet, 0, 1); if rv then config.flange_wet=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Flg Feed", config.flange_feed, 0, 1); if rv then config.flange_feed=v; changed_any=true end
            r.ImGui_Separator(ctx)
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Dbl Spread", config.dbl_wide, 0, 1); if rv then config.dbl_wide=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderInt(ctx, "Dbl Delay", config.dbl_time, 10, 60); if rv then config.dbl_time=v; changed_any=true end
            r.ImGui_Separator(ctx)
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Damp", config.rev_damp, 0, 1); if rv then config.rev_damp=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Size", config.verb_size, 0, 1); if rv then config.verb_size=v; changed_any=true end

            -- 4. BUTTONS & ANALYZER
            
            r.ImGui_TableNextColumn(ctx)
            
            -- ANALYZER
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local p = {r.ImGui_GetCursorScreenPos(ctx)}
            local an_w, an_h = 140, 80
            r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+an_w, p[2]+an_h, 0x000000FF)
            r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+an_w, p[2]+an_h, 0x444444FF)
            
            -- Crosshairs
            local cx, cy = p[1] + an_w*0.5, p[2] + an_h*0.5
            r.ImGui_DrawList_AddLine(dl, cx, p[2], cx, p[2]+an_h, 0xFFFFFF20)
            r.ImGui_DrawList_AddLine(dl, p[1], cy, p[1]+an_w, cy, 0xFFFFFF20)

            -- Scope with VISUAL GATE
            local l_raw = r.gmem_read(7) or 0
            local r_raw = r.gmem_read(8) or 0
            
            if math.abs(l_raw) < 0.005 then l_raw = 0 end
            if math.abs(r_raw) < 0.005 then r_raw = 0 end

            local sensitivity = 2.5
            local mid = (l_raw + r_raw) * 0.5 * sensitivity
            local side = (l_raw - r_raw) * 0.5 * sensitivity
            
            local dot_x = cx + side * (an_w * 0.5)
            local dot_y = cy - mid * (an_h * 0.5) 
            
            dot_x = Clamp(dot_x, p[1], p[1]+an_w)
            dot_y = Clamp(dot_y, p[2], p[2]+an_h)

            -- History Trail
            table.insert(scope_history, 1, {x=dot_x, y=dot_y})
            if #scope_history > 20 then table.remove(scope_history) end
            
            for i, point in ipairs(scope_history) do
                local alpha = math.floor(255 * (1 - (i/#scope_history)))
                local col = (c_acc & 0xFFFFFF00) | alpha
                r.ImGui_DrawList_AddCircleFilled(dl, point.x, point.y, 3 - (i*0.1), col)
            end

            r.ImGui_DrawList_AddCircleFilled(dl, dot_x, dot_y, 4, 0xFFFFFFFF) -- Main dot white
            
            r.ImGui_Dummy(ctx, an_w, an_h + 10)

            -- BUTTONS STACKED (Toggle Envs)
            local btn_c = 0xD46A3FFF
            local hov_c = DarkenColor(btn_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hov_c)
            if r.ImGui_Button(ctx, "Toggle Envs", 140, 40) then ToggleEnvelopes() end
            r.ImGui_PopStyleColor(ctx, 2)
            
            -- GENERATE (Accent)
            local gen_c = c_acc
            local gen_hov = DarkenColor(gen_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), gen_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), gen_hov)
            if r.ImGui_Button(ctx, "GENERATE", 140, 60) then GenerateWhoosh() end
            r.ImGui_PopStyleColor(ctx, 2)

            r.ImGui_EndTable(ctx)
        end

        if changed_any then 
            local now = r.time_precise()
            if now - interaction.last_update_time > 0.05 or not r.ImGui_IsMouseDown(ctx, 0) then
                UpdateAutomationOnly("env")
                interaction.last_update_time = now
            end
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1) -- Pop GrabRounding
    r.ImGui_PopStyleColor(ctx, 13); r.ImGui_PopStyleVar(ctx, 3)
    if open then r.defer(Loop) end
end

LoadSettings()
LoadUserPresets() -- Load user presets on startup
r.defer(Loop)