-- @description ReaWhoosh v2.1 (Stable & Features)
-- @author SBP & Gemini
-- @version 2.1
-- @about ReaWhoosh is a tool for automatically creating whoosh-type sound effects (flybys, whistles, object movement) directly in Reaper.
-- The system consists of a graphical control interface (Lua) and a table-wave/chaotic synthesiser (sbp_WhooshEngine.jsfx).
--https://forum.cockos.com/showthread.php?t=305805
--Support the developer: PayPal - bodzik@gmail.com
--Presets in this version 2.0 do not work. Under development.
-- =========================================================
-- @changelog
-- v2.0    
-- Stable release with new GUI, new features and improved WhooshEngine.jsfx
-- v2.1 
-- Visual improvements to the interface have been made
-- An arrow has been added to vectors for better visual understanding of the direction of the vector over time
-- The behaviour of vectors has been improved; they are now easier to control
-- =========================================================



local r = reaper
local ctx = r.ImGui_CreateContext('ReaWhoosh')

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
local C_ORANGE      = 0xFF9900FF
local C_WHITE       = 0xFFFFFFFF
local C_GREY        = 0x888888FF
local C_SLIDER_BG   = 0x00000090

local PAD_SQUARE    = 170 
local MIX_W         = 20  
local MIX_H         = 130 

-- Heights
local PAD_DRAW_H    = 170 
local CONTAINER_H   = 195 

-- DATA
local settings = {
    track_name = "Whoosh FX",
    output_mode = 0, 
    col_accent = C_ACCENT_DEF,
    col_bg = C_BG_DEF,
    master_vol = -6.0
}

local config = {
    peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
    src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
    cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
    morph_s_x=0.0, morph_s_y=1.0, morph_p_x=0.5, morph_p_y=0.5, morph_e_x=0.0, morph_e_y=0.0,
    dop_s_x=0.0, dop_s_y=0.5, dop_p_x=0.5, dop_p_y=0.5, dop_e_x=1.0, dop_e_y=0.5,
    spc_s_x=0.0, spc_s_y=0.0, spc_p_x=0.5, spc_p_y=1.0, spc_e_x=1.0, spc_e_y=0.5,
    sub_freq = 55, sub_enable = true, sub_vol = 0.8,
    chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, saw_pwm = 0.1,
    saw_detune = 0.0,
    flange_wet=0.0, flange_feed=0.0, verb_size=0.5, rev_damp = 0.5,
    dbl_time = 30, dbl_wide = 0.5,
    mute_w = false, mute_s = false, mute_c = false, mute_e = false,
    trim_w = 1.0, trim_s = 1.0, trim_c = 1.0, trim_e = 1.0, 
    current_preset = "Default"
}

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
    global_pitch = 43 
}

local interaction = { dragging_pad = nil, dragging_point = nil, last_update_time = 0 }

-- =========================================================
-- SYSTEM
-- =========================================================
function SafeCol(c, def) return (type(c)=="number") and c or (def or C_WHITE) end
function Clamp(val, min, max) return math.min(math.max(val or 0, min or 0), max or 1) end

function ValidateConfig()
    if not config.peak_pos then config.peak_pos = 0.5 end
    if not config.saw_detune then config.saw_detune = 0.0 end
end

function SaveSettings()
    local str = string.format("name=%s;mode=%d;c1=%d;c3=%d;mv=%.2f", 
        settings.track_name, settings.output_mode, 
        SafeCol(settings.col_accent, C_ACCENT_DEF), SafeCol(settings.col_bg, C_BG_DEF), settings.master_vol or -6.0)
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
            end
        end
    end
    ValidateConfig()
end

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
    config.peak_pos = 0.2 + rf() * 0.6
    config.src_s_x = rf(); config.src_s_y = rf(); config.src_p_x = rf(); config.src_p_y = rf(); config.src_e_x = rf(); config.src_e_y = rf()
    config.morph_s_x = rf(); config.morph_s_y = rf(); config.morph_p_x = rf(); config.morph_p_y = rf(); config.morph_e_x = rf(); config.morph_e_y = rf()
    config.cut_s_x = rf(); config.cut_s_y = rf(); config.cut_p_x = rf(); config.cut_p_y = rf(); config.cut_e_x = rf(); config.cut_e_y = rf()
    config.dop_s_x = rf(); config.dop_s_y = rf(); config.dop_p_x = rf(); config.dop_p_y = rf(); config.dop_e_x = rf(); config.dop_e_y = rf()
    config.spc_s_x = rf(); config.spc_s_y = rf(); config.spc_p_x = rf(); config.spc_p_y = rf(); config.spc_e_x = rf(); config.spc_e_y = rf()
    config.sub_freq = 30 + math.floor(rf()*90)
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
    r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, 5, true) 
    r.InsertEnvelopePoint(env, t_p, v_p, 0, 0, 5, true)    
    r.InsertEnvelopePoint(env, t_e, v_s, 0, 0, 5, true) 
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-3, t_s, v_s, 5, t_att, true, true) 
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-2, t_p, v_p, 5, t_rel, true, true) 
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
    local peak_time = start_time + ((end_time - start_time) * config.peak_pos)
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
    
    r.TrackFX_SetParam(track, fx, IDX.out_mode, settings.output_mode)
    r.TrackFX_SetParam(track, fx, IDX.sub_freq, config.sub_freq)
    r.TrackFX_SetParam(track, fx, IDX.sub_direct_vol, config.sub_enable and config.sub_vol or 0)
    
    r.TrackFX_SetParam(track, fx, IDX.trim_w, config.trim_w)
    r.TrackFX_SetParam(track, fx, IDX.trim_s, config.trim_s)
    r.TrackFX_SetParam(track, fx, IDX.trim_c, config.trim_c)
    r.TrackFX_SetParam(track, fx, IDX.trim_e, config.trim_e)

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
        local dx = r.ImGui_GetMouseDelta(ctx)
        config.peak_pos = Clamp(config.peak_pos + (dx/w), 0.1, 0.9); changed = true
    end
    
    r.ImGui_DrawList_AddLine(draw_list, peak_x, p_y+5, peak_x, p_y+draw_h-5, 0xFFFFFF30)
    r.ImGui_DrawList_AddCircle(draw_list, p_x+10, start_y, 6, C_GREY, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, peak_x-6, peak_y-6, peak_x+6, peak_y+6, 0xFFFFFFFF)
    -- End point as triangle arrow
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

    local function GetCPs(t, x1, y1, x2, y2)
        local mx, my = (x1+x2)*0.5, (y1+y2)*0.5; local str = math.abs(t) * 100
        if t > 0 then return mx, my - str else return mx, my + str end
    end
    local c1x, c1y = GetCPs(-config.tens_attack, p_x, start_y, peak_x, peak_y)
    r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, c1x, c1y, c1x, c1y, peak_x, peak_y, col_acc, 2, 20)
    local c2x, c2y = GetCPs(config.tens_release, peak_x, peak_y, end_x, end_y)
    r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x, peak_y, c2x, c2y, c2x, c2y, end_x-10, end_y, col_acc, 2, 20)
    
    local slider_w = w * 0.35 * 0.7 -- reduce length by 30%
    local margin_side = 45
    local margin_bot = 35
    local y_pos = p_y + draw_h - margin_bot
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x444444FF) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col_acc)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 1) -- thinner vertical padding -> thinner slider
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 16) -- keep grab size
    
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
    
    return changed
end

function DrawVectorPad(label, p_idx, w, h, col_acc, col_bg)
    if p_idx == 4 then
        w = r.ImGui_GetContentRegionAvail(ctx)
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
        if settings.output_mode == 0 then
            t1="L"; t2="R"; t3="Pitch-"; t4="Pitch+"
        else
            t1="Dry"; t2="Wet"; t3="Pitch-"; t4="Pitch+"
        end
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y + draw_h*0.5 - 7, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-25, p_y + draw_h*0.5 - 7, txt_col, t2)
        r.ImGui_DrawList_AddText(draw_list, p_x+w*0.5-20, p_y+draw_h-18, txt_col, t3)
        r.ImGui_DrawList_AddText(draw_list, p_x+w*0.5-20, p_y+5, txt_col, t4)
    elseif p_idx == 5 then 
        if settings.output_mode == 0 then
            t1="Dbl"; t2="Rev"; t3="Mono"; t4="Wide"
        else
            t1="Front L"; t2="Front R"; t3="Rear L"; t4="Rear R"
        end
        r.ImGui_DrawList_AddText(draw_list, p_x+5, p_y+5, txt_col, t1)
        r.ImGui_DrawList_AddText(draw_list, p_x+w-45, p_y+5, txt_col, t2)
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
    elseif p_idx==5 then sx = config.spc_s_x or 0; sy = config.spc_s_y or 0; px=config.spc_p_x or 0.5; py=config.spc_p_y or 0.5; ex=config.spc_e_x or 1; ey=config.spc_e_y or 1 end
    
    if is_clicked then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*draw_h
        local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*draw_h
        local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*draw_h
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
        local dnx, dny = dx/w, -dy/draw_h
        if interaction.dragging_point == 1 then sx=Clamp(sx+dnx,0,1); sy=Clamp(sy+dny,0,1); changed=true
        elseif interaction.dragging_point == 2 then px=Clamp(px+dnx,0,1); py=Clamp(py+dny,0,1); changed=true
        elseif interaction.dragging_point == 3 then ex=Clamp(ex+dnx,0,1); ey=Clamp(ey+dny,0,1); changed=true end
        if changed then
            if p_idx==1 then config.src_s_x,config.src_s_y,config.src_p_x,config.src_p_y,config.src_e_x,config.src_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==2 then config.morph_s_x,config.morph_s_y,config.morph_p_x,config.morph_p_y,config.morph_e_x,config.morph_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==3 then config.cut_s_x,config.cut_s_y,config.cut_p_x,config.cut_p_y,config.cut_e_x,config.cut_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==4 then config.dop_s_x,config.dop_s_y,config.dop_p_x,config.dop_p_y,config.dop_e_x,config.dop_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==5 then config.spc_s_x,config.spc_s_y,config.spc_p_x,config.spc_p_y,config.spc_e_x,config.spc_e_y = sx,sy,px,py,ex,ey end
        end
    end

    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*draw_h
    local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*draw_h
    local e_x, e_y = p_x + ex*w, p_y + (1-ey)*draw_h
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
        r.ImGui_DrawList_AddTriangleFilled(draw_list, tip_x, tip_y, left_x, left_y, right_x, right_y, 0x2D8C6DFF)
    else
        r.ImGui_DrawList_AddCircleFilled(draw_list, e_x, e_y, 6, 0x2D8C6DFF)
    end
    
    return changed
end

function Loop()
    local c_bg = SafeCol(settings.col_bg, 0x252525FF)
    local c_acc = SafeCol(settings.col_accent, 0x2D8C6DFF)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c_acc + 0x10101000)
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
    
    local visible, open = r.ImGui_Begin(ctx, 'ReaWhoosh v2.1', true)
    if visible then
        local changed_any = false
        
        -- HEADER
        r.ImGui_Text(ctx, "PRESETS:"); r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 200)
        if r.ImGui_BeginCombo(ctx, "##presets", config.current_preset) then
            for name, _ in pairs(FACTORY_PRESETS) do if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any=true end end
            r.ImGui_EndCombo(ctx) 
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Options", 80) then r.ImGui_OpenPopup(ctx, "Settings") end
        
        if r.ImGui_BeginPopupModal(ctx, "Settings", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            if r.ImGui_RadioButton(ctx, "Stereo", settings.output_mode==0) then settings.output_mode=0; changed_any=true end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Surround", settings.output_mode==1) then settings.output_mode=1; changed_any=true end
            if r.ImGui_Button(ctx, "Close") then r.ImGui_CloseCurrentPopup(ctx) end
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
                r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Space Pad"); if DrawVectorPad("##space", 5, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Cut / Res"); if DrawVectorPad("##cut", 3, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true end
                r.ImGui_EndTable(ctx)
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
            
            -- 2. BOTTOM BLOCK
            if r.ImGui_BeginChild(ctx, "BotBlock", 0, CONTAINER_H, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_Text(ctx, " Doppler Pad")
                if DrawVectorPad("##doppler", 4, -1, PAD_DRAW_H, c_acc, c_bg) then changed_any=true end
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
            
            r.ImGui_BeginGroup(ctx)
                r.ImGui_Text(ctx, "Mst")
                r.ImGui_PushID(ctx, "Mst")
                r.ImGui_SetNextItemWidth(ctx, 30) 
                local rv, v = r.ImGui_VSliderDouble(ctx, "##v", 30, MIX_H + 25, settings.master_vol, -60, 12, "")
                r.ImGui_PopID(ctx); if rv then settings.master_vol=v; changed_any=true end
            r.ImGui_EndGroup(ctx); r.ImGui_SameLine(ctx)

            local function DrawStrip(lbl, val, muted)
                r.ImGui_BeginGroup(ctx)
                r.ImGui_Text(ctx, lbl)
                r.ImGui_PushID(ctx, lbl)
                r.ImGui_SetNextItemWidth(ctx, MIX_W) 
                local rv, v = r.ImGui_VSliderDouble(ctx, "##v", MIX_W, MIX_H, val, 0, 1, "")
                if rv then val=v; changed_any=true end
                r.ImGui_PopID(ctx)
                r.ImGui_PushID(ctx, "m_"..lbl)
                if muted then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF4040FF) else r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000060) end
                if r.ImGui_Button(ctx, "M", MIX_W, 20) then muted = not muted; changed_any=true end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_PopID(ctx)
                r.ImGui_EndGroup(ctx)
                return val, muted
            end
            
            config.trim_w, config.mute_w = DrawStrip("W", config.trim_w, config.mute_w); r.ImGui_SameLine(ctx)
            config.trim_s, config.mute_s = DrawStrip("S", config.trim_s, config.mute_s); r.ImGui_SameLine(ctx)
            config.trim_c, config.mute_c = DrawStrip("C", config.trim_c, config.mute_c); r.ImGui_SameLine(ctx)
            config.trim_e, config.mute_e = DrawStrip("E", config.trim_e, config.mute_e); r.ImGui_SameLine(ctx)
            
            r.ImGui_BeginGroup(ctx)
            r.ImGui_Text(ctx, "Sub")
            r.ImGui_PushID(ctx, "Sub")
            r.ImGui_SetNextItemWidth(ctx, MIX_W)
            local rv_sv, v_sv = r.ImGui_VSliderDouble(ctx, "##v", MIX_W, MIX_H, config.sub_vol, 0, 1, "")
            if rv_sv then config.sub_vol=v_sv; changed_any=true end
            r.ImGui_PopID(ctx)
            r.ImGui_PushID(ctx, "s_on")
            if config.sub_enable then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_acc) else r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000060) end
            if r.ImGui_Button(ctx, "on", MIX_W, 20) then config.sub_enable = not config.sub_enable; changed_any=true end
            r.ImGui_PopStyleColor(ctx, 1); r.ImGui_PopID(ctx); r.ImGui_EndGroup(ctx)

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
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Dbl Wide", config.dbl_wide, 0, 1); if rv then config.dbl_wide=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderInt(ctx, "Dbl Time", config.dbl_time, 10, 60); if rv then config.dbl_time=v; changed_any=true end
            r.ImGui_Separator(ctx)
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Damp", config.rev_damp, 0, 1); if rv then config.rev_damp=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Size", config.verb_size, 0, 1); if rv then config.verb_size=v; changed_any=true end

            -- 4. BUTTONS
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Dummy(ctx, 0, 20)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xD46A3FFF)
            if r.ImGui_Button(ctx, "Randomize", -1, 45) then RandomizeConfig(); changed_any=true end
            r.ImGui_PopStyleColor(ctx, 1)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xD46A3FFF)
            if r.ImGui_Button(ctx, "Show Envs", -1, 45) then ToggleEnvelopes() end
            r.ImGui_PopStyleColor(ctx, 1)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_acc)
            if r.ImGui_Button(ctx, "GENERATE", -1, 70) then GenerateWhoosh() end
            r.ImGui_PopStyleColor(ctx, 1)

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
    r.ImGui_PopStyleColor(ctx, 14); r.ImGui_PopStyleVar(ctx, 3)
    if open then r.defer(Loop) end
end

LoadSettings()
r.defer(Loop)
