-- @description ReaWhoosh v1 (Filter Update & Graph Fix)
-- @author SBP_&_Gemini
-- @version 1.1
-- @about
--It is a script designed for the fast and flexible creation of whoosh effects.
--Features:
--Real-time Updates: You can continue tweaking the curves in the script after the item is generated — all parameters update in real-time!
--Sound Sources: White noise, Pink noise, Chua Osc (best tweaked manually or used with presets), and an Empty Container for your favorite synth.
--Flexible Routing: Feel free to send audio from other tracks to channels 7/8 of the container and morph them as well.
--Expandable: The script is flexible, allowing you to easily add your own effects.

--changelog:
--ver 1.1
--Improved sound source mixing algorithm (penetration strength reduced))

local r = reaper
local ctx = r.ImGui_CreateContext('ReaWhoosh')

-- === 1. STATIC UI CONSTANTS ===
local UI_CONST = {
    text = 0xE0E0E0FF,
    text_dim = 0xAAAAAAFF,
    grid_color = 0xFFFFFF20,
    peak_line  = 0xFFFFFF40, 
    point_start = 0xAAAAAAFF, 
    point_peak = 0xFFFFFFFF, 
    point_end = 0x2D8C6DFF,
    btn_sec = 0x444444FF, 
    btn_sec_hover = 0x555555FF,
    btn_del = 0x802020FF, 
    btn_del_hover = 0xA03030FF,
    frame_bg = 0x00000060,
    frame_bg_hover = 0x404040FF,
    pad_bg_static = 0x00000050,
    child_bg = 0x00000000
}

-- === 2. SETTINGS & DEFAULTS ===
local DEFAULT_SETTINGS = {
    track_name = "Whoosh FX",
    col_accent = 0x2D8C6DFF, -- Green
    col_bg = 0x252525FF
}

local settings = {
    track_name = DEFAULT_SETTINGS.track_name,
    col_accent = DEFAULT_SETTINGS.col_accent,
    col_bg = DEFAULT_SETTINGS.col_bg
}

-- === 3. INDICES ===
local EXT_SECTION = "ReaWhoosh_v12"
local EXT_KEY_PRESETS = "UserPresets_List"
local EXT_KEY_SETTINGS = "Global_Settings"

local IDX = {
    filt_morph_x = 1, 
    filt_morph_y = 2, 
    filt_freq = 3, 
    filt_res = 5, -- Hertz 2 version index
    
    flange_feed = 1, flange_wet = 2,
    verb_wet = 0, verb_size = 2,
    width_param = 0,
    mix_vol1 = 0, mix_vol2 = 1, mix_vol3 = 2, mix_vol4 = 3
}

-- === 4. CONFIG STATE ===
local config = {
    peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
    
    morph_s_x=0.0, morph_s_y=1.0, morph_p_x=0.5, morph_p_y=0.5, morph_e_x=0.0, morph_e_y=0.0,
    cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
    pan_s_x=0.5, pan_s_y=0.0, pan_p_x=0.5, pan_p_y=1.0, pan_e_x=0.5, pan_e_y=0.0,
    src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,

    flange_enable=true, flange_wet=0.85, flange_feed=0.75,
    verb_enable=true, verb_wet=0.85, verb_size=0.75,
    
    current_preset = "Default",
    new_preset_name = ""
}

-- === 5. FACTORY PRESETS ===
local FACTORY_PRESETS = {
    ["Default"] = {
        peak=0.6, att=0.6, rel=-0.4,
        msx=0.0, msy=1.0, mpx=0.5, mpy=0.5, mex=0.0, mey=0.0,
        csx=0.1, csy=0.1, cpx=1.0, cpy=0.8, cex=0.1, cey=0.1,
        psx=0.5, psy=0.0, ppx=0.5, ppy=1.0, pex=0.5, pey=0.0,
        ssx=0.0, ssy=1.0, spx=0.2, spy=0.8, sex=0.0, sey=1.0 
    },
    ["Sci-Fi Pass"] = {
        peak=0.5, att=0.2, rel=0.2,
        msx=0.0, msy=0.0, mpx=1.0, mpy=1.0, mex=0.0, mey=0.0,
        csx=0.2, csy=0.1, cpx=0.9, cpy=0.9, cex=0.2, cey=0.1,
        psx=0.0, psy=0.5, ppx=0.5, ppy=1.0, pex=1.0, pey=0.5,
        ssx=0.0, ssy=0.0, spx=1.0, spy=0.0, sex=0.0, sey=0.0 
    },
    ["Dark Impact"] = {
        peak=0.1, att=-0.8, rel=0.6,
        msx=0.5, msy=0.5, mpx=0.5, mpy=0.5, mex=0.5, mey=0.5,
        csx=0.8, csy=0.1, cpx=0.1, cpy=0.5, cex=0.0, cey=0.0,
        psx=0.5, psy=1.0, ppx=0.5, ppy=0.5, pex=0.5, pey=0.0,
        ssx=1.0, ssy=0.0, spx=1.0, spy=0.0, sex=0.0, sey=1.0 
    }
}

-- === HELPERS ===
function Map(val, in_min, in_max, out_min, out_max) return out_min + (val - in_min) * (out_max - out_min) / (in_max - in_min) end
function Clamp(val, min, max) return math.min(math.max(val, min), max) end

function FindTrackByName(name)
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name then return track end
    end
    return nil
end

-- === SETTINGS & PRESET FUNCTIONS ===
function SaveSettings()
    local str = string.format("name=%s;c1=%d;c3=%d", 
        settings.track_name, settings.col_accent, settings.col_bg)
    r.SetExtState(EXT_SECTION, EXT_KEY_SETTINGS, str, true)
end

function LoadSettings()
    local str = r.GetExtState(EXT_SECTION, EXT_KEY_SETTINGS)
    if str and str ~= "" then
        for k, v in string.gmatch(str, "(%w+)=([^;]+)") do
            if k == "name" then settings.track_name = v
            elseif k == "c1" then settings.col_accent = tonumber(v)
            elseif k == "c3" then settings.col_bg = tonumber(v)
            end
        end
    end
end

function SerializeConfig()
    return string.format(
        "peak=%.2f;att=%.2f;rel=%.2f;"..
        "msx=%.2f;msy=%.2f;mpx=%.2f;mpy=%.2f;mex=%.2f;mey=%.2f;"..
        "csx=%.2f;csy=%.2f;cpx=%.2f;cpy=%.2f;cex=%.2f;cey=%.2f;"..
        "psx=%.2f;psy=%.2f;ppx=%.2f;ppy=%.2f;pex=%.2f;pey=%.2f;"..
        "ssx=%.2f;ssy=%.2f;spx=%.2f;spy=%.2f;sex=%.2f;sey=%.2f",
        config.peak_pos, config.tens_attack, config.tens_release,
        config.morph_s_x, config.morph_s_y, config.morph_p_x, config.morph_p_y, config.morph_e_x, config.morph_e_y,
        config.cut_s_x, config.cut_s_y, config.cut_p_x, config.cut_p_y, config.cut_e_x, config.cut_e_y,
        config.pan_s_x, config.pan_s_y, config.pan_p_x, config.pan_p_y, config.pan_e_x, config.pan_e_y,
        config.src_s_x, config.src_s_y, config.src_p_x, config.src_p_y, config.src_e_x, config.src_e_y
    )
end

function DeserializeConfig(str)
    local p = {}
    for k, v in string.gmatch(str, "(%w+)=([%d.-]+)") do p[k] = tonumber(v) end
    return p
end

function ApplyPreset(name)
    local p = FACTORY_PRESETS[name]
    if not p then 
        local data = r.GetExtState(EXT_SECTION, name)
        if data and data ~= "" then p = DeserializeConfig(data) end
    end
    if p then
        config.current_preset = name
        config.peak_pos = p.peak or 0.6; config.tens_attack = p.att or 0.6; config.tens_release = p.rel or -0.4
        config.morph_s_x=p.msx; config.morph_s_y=p.msy; config.morph_p_x=p.mpx; config.morph_p_y=p.mpy; config.morph_e_x=p.mex; config.morph_e_y=p.mey
        config.cut_s_x=p.csx; config.cut_s_y=p.csy; config.cut_p_x=p.cpx; config.cut_p_y=p.cpy; config.cut_e_x=p.cex; config.cut_e_y=p.cey
        config.pan_s_x=p.psx; config.pan_s_y=p.psy; config.pan_p_x=p.ppx; config.pan_p_y=p.ppy; config.pan_e_x=p.pex; config.pan_e_y=p.pey
        config.src_s_x=p.ssx; config.src_s_y=p.ssy; config.src_p_x=p.spx; config.src_p_y=p.spy; config.src_e_x=p.sex; config.src_e_y=p.sey
    end
end

function LoadPreset(name) ApplyPreset(name) end

function SaveUserPreset(name)
    if name == "" then return end
    local data = SerializeConfig()
    r.SetExtState(EXT_SECTION, name, data, true)
    local list_str = r.GetExtState(EXT_SECTION, EXT_KEY_PRESETS)
    if not list_str:find(name .. "|") then
        r.SetExtState(EXT_SECTION, EXT_KEY_PRESETS, list_str .. name .. "|", true)
    end
    config.current_preset = name
end

function DeleteUserPreset(name)
    if not name or name == "" or FACTORY_PRESETS[name] then return end
    r.DeleteExtState(EXT_SECTION, name, true)
    local list_str = r.GetExtState(EXT_SECTION, EXT_KEY_PRESETS)
    local new_list = list_str:gsub(name .. "|", "")
    r.SetExtState(EXT_SECTION, EXT_KEY_PRESETS, new_list, true)
    config.current_preset = "Default"
    ApplyPreset("Default")
end

function RandomizeConfig()
    local function rfloat() return math.random() end
    config.current_preset = "Randomized"
    config.peak_pos = 0.2 + rfloat() * 0.6
    config.morph_s_x = rfloat(); config.morph_s_y = rfloat(); config.morph_p_x = rfloat(); config.morph_p_y = rfloat(); config.morph_e_x = rfloat(); config.morph_e_y = rfloat()
    config.cut_s_x = rfloat()*0.5; config.cut_s_y = rfloat()*0.5; config.cut_p_x = 0.5+rfloat()*0.5; config.cut_p_y = 0.5+rfloat()*0.5; config.cut_e_x = rfloat()*0.5; config.cut_e_y = rfloat()*0.5
    config.pan_s_x = rfloat(); config.pan_s_y = rfloat(); config.pan_p_x = rfloat(); config.pan_p_y = rfloat(); config.pan_e_x = rfloat(); config.pan_e_y = rfloat()
    config.src_s_x = rfloat()*0.5; config.src_s_y = 0.5+rfloat()*0.5; config.src_p_x = rfloat(); config.src_p_y = rfloat(); config.src_e_x = rfloat(); config.src_e_y = rfloat()
end

-- === REAPER LOGIC ===

function GetOrAddFX(track, name_variants)
    if type(name_variants) == "string" then name_variants = {name_variants} end
    local cnt = r.TrackFX_GetCount(track)
    for i = 0, cnt - 1 do
        local _, buf = r.TrackFX_GetFXName(track, i, "")
        for _, v in ipairs(name_variants) do
            if buf:lower():find(v:lower(), 1, true) then return i end
        end
    end
    return r.TrackFX_AddByName(track, name_variants[1], false, -1)
end

function SetFXPinMappings(track, fx_idx, output_chan_pair)
    local pin_L = output_chan_pair * 2
    local pin_R = output_chan_pair * 2 + 1
    local mask_L = 1 << pin_L
    local mask_R = 1 << pin_R
    r.TrackFX_SetPinMappings(track, fx_idx, 1, 0, mask_L, 0) 
    r.TrackFX_SetPinMappings(track, fx_idx, 1, 1, mask_R, 0) 
end

function ToggleEnvelopes()
    local track = FindTrackByName(settings.track_name)
    if not track then track = r.GetSelectedTrack(0, 0) end
    if track then
        r.SetOnlyTrackSelected(track)
        r.Main_OnCommand(40891, 0) 
    end
end

-- === AUTOMATION ===

function GetOrShowTrackEnvelope(track, env_key)
    local names = {env_key}
    if env_key == "Pan" then names = {"Pan", "Панорама"} end
    local env = nil
    for _, name in ipairs(names) do env = r.GetTrackEnvelopeByName(track, name); if env then break end end
    if not env then
        r.SetOnlyTrackSelected(track)
        if env_key == "Pan" then r.Main_OnCommand(40407, 0) end
        if env_key == "Volume" then r.Main_OnCommand(40406, 0) end 
        for _, name in ipairs(names) do env = r.GetTrackEnvelopeByName(track, name); if env then break end end
    end
    return env
end

function ScaleVal(env, val)
    if not env then return val end
    local scaling_mode = r.GetEnvelopeScalingMode(env)
    return r.ScaleToEnvelopeMode(scaling_mode, val)
end

function CreateEnvelopeCurveTrack(track, env_name, t_s, t_p, t_e, val_silence, val_peak, t_att, t_rel)
    local env = GetOrShowTrackEnvelope(track, env_name)
    if not env then return end
    
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    
    local v_sil = ScaleVal(env, val_silence)
    local v_peak = ScaleVal(env, val_peak)
    
    r.InsertEnvelopePoint(env, t_s, v_sil, 0, 0, 5, true) 
    r.InsertEnvelopePoint(env, t_p, v_peak, 0, 0, 5, true)    
    r.InsertEnvelopePoint(env, t_e, v_sil, 0, 0, 5, true) 
    
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-3, t_s, v_sil, 5, -t_att, true, true) 
    r.SetEnvelopePoint(env, r.CountEnvelopePoints(env)-2, t_p, v_peak, 5, -t_rel, true, true) 
    r.Envelope_SortPoints(env)
end

function Create3PointRampFX(track, fx_idx, param_idx, t_s, t_p, t_e, v_s, v_p, v_e)
    if not fx_idx or fx_idx < 0 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true)
    if not env then return end
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, false, true)
    r.InsertEnvelopePoint(env, t_p, v_p, 0, 0, false, true)
    r.InsertEnvelopePoint(env, t_e, v_e, 0, 0, false, true)
    r.Envelope_SortPoints(env)
end

function Create3PointRampTrack(track, env_name, t_s, t_p, t_e, v_s, v_p, v_e)
    local env = GetOrShowTrackEnvelope(track, env_name)
    if not env then return end
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, false, true)
    r.InsertEnvelopePoint(env, t_p, v_p, 0, 0, false, true)
    r.InsertEnvelopePoint(env, t_e, v_e, 0, 0, false, true)
    r.Envelope_SortPoints(env)
end

function CreateLinearRampFX(track, fx_idx, param_idx, t_s, t_e, v_s, v_e)
    if not fx_idx or fx_idx < 0 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true)
    if not env then return end
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    r.InsertEnvelopePoint(env, t_s, v_s, 0, 0, false, true)
    r.InsertEnvelopePoint(env, t_e, v_e, 0, 0, false, true)
    r.Envelope_SortPoints(env)
end

function UpdateAutomationOnly(flags)
    local update_vol = (flags == nil or flags == "all" or flags == "vol")
    local update_env = (flags == nil or flags == "all" or flags == "env")
    
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then return end
    local length = end_time - start_time
    local peak_time = start_time + (length * config.peak_pos)
    
    local fx_filter = GetOrAddFX(track, {"State Variable Morphing Filter (Hertz 2)", "statevariable_Hz_2"})
    local fx_flange = GetOrAddFX(track, {"Guitar/Flanger"})
    local fx_verb = GetOrAddFX(track, {"ReaVerbate"})
    local fx_width = GetOrAddFX(track, {"Simple Stereo Width Control", "denisfilippov"}) 
    local fx_mixer = GetOrAddFX(track, {"8x Stereo to 1x Stereo Mixer", "IX/Mixer_8xS-1xS"})

    local old_vol_fx = GetOrAddFX(track, {"Volume Adjustment", "utility/volume"})
    if old_vol_fx >= 0 then r.TrackFX_Delete(track, old_vol_fx) end

    if fx_flange >= 0 then r.TrackFX_SetEnabled(track, fx_flange, config.flange_enable) end
    if fx_verb >= 0 then r.TrackFX_SetEnabled(track, fx_verb, config.verb_enable) end

    r.Undo_BeginBlock() 
    r.SetOnlyTrackSelected(track)
    
    if update_vol then
        CreateEnvelopeCurveTrack(track, "Volume", start_time, peak_time, end_time, 0.0, 1.0, config.tens_attack, config.tens_release)
    end

    if update_env then
        -- 2. PAN / WIDTH 
        local pan_s = Map(config.pan_s_x, 0, 1, 1, -1); local pan_p = Map(config.pan_p_x, 0, 1, 1, -1); local pan_e = Map(config.pan_e_x, 0, 1, 1, -1)
        Create3PointRampTrack(track, "Pan", start_time, peak_time, end_time, pan_s, pan_p, pan_e)
        if fx_width >= 0 then
            local w_s = Map(config.pan_s_y, 0, 1, 0.0, 1.0); local w_p = Map(config.pan_p_y, 0, 1, 0.0, 1.0); local w_e = Map(config.pan_e_y, 0, 1, 0.0, 1.0)
            Create3PointRampFX(track, fx_width, IDX.width_param, start_time, peak_time, end_time, w_s, w_p, w_e)
        end

        -- 3. FILTER
        if fx_filter >= 0 then
            Create3PointRampFX(track, fx_filter, IDX.filt_morph_x, start_time, peak_time, end_time, config.morph_s_x, config.morph_p_x, config.morph_e_x)
            Create3PointRampFX(track, fx_filter, IDX.filt_morph_y, start_time, peak_time, end_time, config.morph_s_y, config.morph_p_y, config.morph_e_y)
            Create3PointRampFX(track, fx_filter, IDX.filt_freq, start_time, peak_time, end_time, config.cut_s_x*100, config.cut_p_x*100, config.cut_e_x*100)
            Create3PointRampFX(track, fx_filter, IDX.filt_res, start_time, peak_time, end_time, config.cut_s_y*24, config.cut_p_y*24, config.cut_e_y*24)
        end
        
        -- 4. SOURCE MIXER (NEW S-CURVE ALGO)
        if fx_mixer >= 0 then
            -- S-Curve helper: t^3 / (t^3 + (1-t)^3)
            -- This makes values stick to 0 and 1, creating a steeper transition in the middle.
            -- Result: Less bleed between pads.
            local function SCurve(t)
                return t*t*t / (t*t*t + (1-t)*(1-t)*(1-t))
            end
            
            local function get_vols(x, y) 
                -- Apply S-Curve to coordinates
                local sx, sy = SCurve(x), SCurve(y)
                return (1-sx)*sy, sx*sy, (1-sx)*(1-sy), sx*(1-sy) 
            end
            
            local v1_s, v2_s, v3_s, v4_s = get_vols(config.src_s_x, config.src_s_y)
            local v1_p, v2_p, v3_p, v4_p = get_vols(config.src_p_x, config.src_p_y)
            local v1_e, v2_e, v3_e, v4_e = get_vols(config.src_e_x, config.src_e_y)
            
            local function db(val) return val < 0.01 and -120 or 20*math.log(val, 10) end
            Create3PointRampFX(track, fx_mixer, IDX.mix_vol1, start_time, peak_time, end_time, db(v1_s), db(v1_p), db(v1_e))
            Create3PointRampFX(track, fx_mixer, IDX.mix_vol2, start_time, peak_time, end_time, db(v2_s), db(v2_p), db(v2_e))
            Create3PointRampFX(track, fx_mixer, IDX.mix_vol3, start_time, peak_time, end_time, db(v3_s), db(v3_p), db(v3_e))
            Create3PointRampFX(track, fx_mixer, IDX.mix_vol4, start_time, peak_time, end_time, db(v4_s), db(v4_p), db(v4_e))
        end

        -- 5. FX (dB mapped)
        if fx_flange >= 0 then
            local w, f = Map(config.flange_wet, 0, 1, -120, 6), Map(config.flange_feed, 0, 1, -120, 6)
            CreateLinearRampFX(track, fx_flange, IDX.flange_feed, start_time, end_time, f, f)
            CreateLinearRampFX(track, fx_flange, IDX.flange_wet, start_time, end_time, w, w)
        end
        if fx_verb >= 0 then
            local w, s = config.verb_wet, config.verb_size
            CreateLinearRampFX(track, fx_verb, IDX.verb_wet, start_time, end_time, w, w)
            CreateLinearRampFX(track, fx_verb, IDX.verb_size, start_time, end_time, s, s)
        end
    end
    r.UpdateArrange()
    r.Undo_EndBlock("Update Whoosh Params", 4)
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
    
    r.SetMediaTrackInfo_Value(track, "I_NCHAN", 8)
    r.SetMediaTrackInfo_Value(track, "B_MUTE", 1)

    local fx_w = GetOrAddFX(track, {"White Noise Generator"})
    local fx_p = GetOrAddFX(track, {"Pink Noise Generator"})
    local fx_c = GetOrAddFX(track, {"Chua Oscillator", "TiaR_Chua"})
    local fx_u = GetOrAddFX(track, {"Container"}) 
    SetFXPinMappings(track, fx_w, 0); SetFXPinMappings(track, fx_p, 1)
    SetFXPinMappings(track, fx_c, 2); SetFXPinMappings(track, fx_u, 3)
    
    GetOrAddFX(track, {
        "JS: Mixer_8xS-1xS (8 x stereo to 1 x stereo) [IX/Mixer_8xS-1xS]",
        "JS: Mixer_8xS-1xS", "IX/Mixer_8xS-1xS", "8x Stereo to 1x Stereo Mixer"
    })
    
    GetOrAddFX(track, {"State Variable Morphing Filter (Hertz 2)", "statevariable_Hz_2"})
    
    GetOrAddFX(track, {"Guitar/Flanger"})
    GetOrAddFX(track, {"ReaVerbate"})
    GetOrAddFX(track, {"Simple Stereo Width Control", "denisfilippov"}) 

    local item = r.CreateNewMIDIItemInProj(track, start_time, end_time, false)
    r.SetMediaItemSelected(item, true)
    
    UpdateAutomationOnly("all")
    r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
    r.PreventUIRefresh(-1)
end

-- === UI ===

function DrawVectorPad(label, p_idx, w, h)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local p_x, p_y = r.ImGui_GetCursorScreenPos(ctx)
    local changed = false

    r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + h, UI_CONST.pad_bg_static, 4) 
    r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + w, p_y + h, 0xFFFFFF30, 4)
    r.ImGui_DrawList_AddLine(draw_list, p_x + w*0.5, p_y, p_x + w*0.5, p_y + h, settings.col_bg + 0x20202020)
    r.ImGui_DrawList_AddLine(draw_list, p_x, p_y + h*0.5, p_x + w, p_y + h*0.5, settings.col_bg + 0x20202020)
    
    local txt_col = 0xFFFFFF60
    
    if p_idx == 1 then 
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + 5, txt_col, "HP")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 25, p_y + 5, txt_col, "BR")
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + h - 18, txt_col, "LP")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 25, p_y + h - 18, txt_col, "BP")
    elseif p_idx == 2 then 
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + 5, txt_col, "Res")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 30, p_y + h - 18, txt_col, "Cut")
    elseif p_idx == 3 then 
        r.ImGui_DrawList_AddText(draw_list, p_x + w*0.5 - 15, p_y + 5, txt_col, "Wide")
        r.ImGui_DrawList_AddText(draw_list, p_x + w*0.5 - 15, p_y + h - 18, txt_col, "Mono")
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + h*0.5 - 8, txt_col, "L")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 15, p_y + h*0.5 - 8, txt_col, "R")
    elseif p_idx == 4 then 
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + 5, txt_col, "White")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 30, p_y + 5, txt_col, "Pink")
        r.ImGui_DrawList_AddText(draw_list, p_x + 5, p_y + h - 18, txt_col, "Chua")
        r.ImGui_DrawList_AddText(draw_list, p_x + w - 35, p_y + h - 18, txt_col, "Cont")
    end

    r.ImGui_InvisibleButton(ctx, label, w, h)
    local is_active = r.ImGui_IsItemActive(ctx)
    
    local sx, sy, px, py, ex, ey
    if p_idx==1 then sx,sy,px,py,ex,ey = config.morph_s_x, config.morph_s_y, config.morph_p_x, config.morph_p_y, config.morph_e_x, config.morph_e_y
    elseif p_idx==2 then sx,sy,px,py,ex,ey = config.cut_s_x, config.cut_s_y, config.cut_p_x, config.cut_p_y, config.cut_e_x, config.cut_e_y
    elseif p_idx==3 then sx,sy,px,py,ex,ey = config.pan_s_x, config.pan_s_y, config.pan_p_x, config.pan_p_y, config.pan_e_x, config.pan_e_y
    else sx,sy,px,py,ex,ey = config.src_s_x, config.src_s_y, config.src_p_x, config.src_p_y, config.src_e_x, config.src_e_y end
    
    if is_active then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local dx, dy = r.ImGui_GetMouseDelta(ctx)
        local dnx, dny = dx/w, -dy/h
        local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*h
        local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*h
        local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*h
        local ds, dp, de = (mx-s_sc_x)^2+(my-s_sc_y)^2, (mx-p_sc_x)^2+(my-p_sc_y)^2, (mx-e_sc_x)^2+(my-e_sc_y)^2
        
        if ds < 600 and ds < dp and ds < de then sx=Clamp(sx+dnx,0,1); sy=Clamp(sy+dny,0,1); changed=true
        elseif dp < 600 and dp < de then px=Clamp(px+dnx,0,1); py=Clamp(py+dny,0,1); changed=true
        elseif de < 600 then ex=Clamp(ex+dnx,0,1); ey=Clamp(ey+dny,0,1); changed=true end
        
        if p_idx==1 then config.morph_s_x,config.morph_s_y,config.morph_p_x,config.morph_p_y,config.morph_e_x,config.morph_e_y = sx,sy,px,py,ex,ey
        elseif p_idx==2 then config.cut_s_x,config.cut_s_y,config.cut_p_x,config.cut_p_y,config.cut_e_x,config.cut_e_y = sx,sy,px,py,ex,ey
        elseif p_idx==3 then config.pan_s_x,config.pan_s_y,config.pan_p_x,config.pan_p_y,config.pan_e_x,config.pan_e_y = sx,sy,px,py,ex,ey
        else config.src_s_x,config.src_s_y,config.src_p_x,config.src_p_y,config.src_e_x,config.src_e_y = sx,sy,px,py,ex,ey end
    end

    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*h
    local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*h
    local e_x, e_y = p_x + ex*w, p_y + (1-ey)*h
    r.ImGui_DrawList_AddLine(draw_list, s_x, s_y, p_x_d, p_y_d, settings.col_accent & 0xFFFFFF40, 2)
    r.ImGui_DrawList_AddLine(draw_list, p_x_d, p_y_d, e_x, e_y, settings.col_accent & 0xFFFFFF40, 2)
    r.ImGui_DrawList_AddCircle(draw_list, s_x, s_y, 5, UI_CONST.point_start, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x_d-4, p_y_d-4, p_x_d+4, p_y_d+4, UI_CONST.point_peak)
    r.ImGui_DrawList_AddCircleFilled(draw_list, e_x, e_y, 6, UI_CONST.point_end)

    return changed
end

function DrawEnvelopePreview(w, h)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local p_x, p_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + h, UI_CONST.pad_bg_static, 4)
    
    local peak_x = p_x + (w * config.peak_pos)
    local peak_y = p_y + 5
    local start_y = p_y + h - 5
    local end_y = p_y + h - 5
    local end_screen_x = p_x + w

    local function GetTensionCPs(t, p1x, p1y, p2x, p2y)
        local c1x = p1x + (p2x - p1x) * 0.33
        local c1y = p1y + (p2y - p1y) * 0.33
        local c2x = p1x + (p2x - p1x) * 0.66
        local c2y = p1y + (p2y - p1y) * 0.66
        
        local strength = 0.8 * math.abs(t)
        if t > 0 then 
            local target_x, target_y = math.max(p1x, p2x), math.max(p1y, p2y) 
            c1x, c1y = c1x + (target_x - c1x)*strength*0.5, c1y + (target_y - c1y)*strength
            c2x, c2y = c2x + (target_x - c2x)*strength*0.5, c2y + (target_y - c2y)*strength
        elseif t < 0 then 
            local target_x, target_y = math.min(p1x, p2x), math.min(p1y, p2y) 
            c1x, c1y = c1x + (target_x - c1x)*strength*0.5, c1y + (target_y - c1y)*strength
            c2x, c2y = c2x + (target_x - c2x)*strength*0.5, c2y + (target_y - c2y)*strength
        end
        return c1x, c1y, c2x, c2y
    end

    -- Inverted Attack Slider Visual
    local acp1x, acp1y, acp2x, acp2y = GetTensionCPs(-config.tens_attack, p_x, start_y, peak_x, peak_y)
    local rcp1x, rcp1y, rcp2x, rcp2y = GetTensionCPs(config.tens_release, peak_x, peak_y, end_screen_x, end_y)

    r.ImGui_DrawList_PathClear(draw_list)
    r.ImGui_DrawList_AddBezierCubic(draw_list, p_x, start_y, acp1x, acp1y, acp2x, acp2y, peak_x, peak_y, settings.col_accent, 2, 20)
    r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x, peak_y, rcp1x, rcp1y, rcp2x, rcp2y, end_screen_x, end_y, settings.col_accent, 2, 20)
    
    r.ImGui_DrawList_AddLine(draw_list, peak_x, p_y, peak_x, p_y + h, UI_CONST.peak_line, 1)
    r.ImGui_DrawList_AddCircle(draw_list, p_x, start_y, 4, UI_CONST.point_start, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, peak_x - 3, peak_y - 3, peak_x + 3, peak_y + 3, UI_CONST.point_peak)
    r.ImGui_DrawList_AddCircleFilled(draw_list, end_screen_x, end_y, 4, UI_CONST.point_end)
end


function Loop()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1AFF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), settings.col_bg); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x202020FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x202020FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.col_accent + 0x10101000); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.col_accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_CONST.text); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.col_accent); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.col_accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), UI_CONST.frame_bg); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), UI_CONST.frame_bg_hover); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), UI_CONST.frame_bg_hover); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), settings.col_accent)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8)

    r.ImGui_SetNextWindowSize(ctx, 500, 950, r.ImGui_Cond_FirstUseEver()) 
    
    local visible, open = r.ImGui_Begin(ctx, 'ReaWhoosh v12.12', true)
    if visible then
        local win_w = r.ImGui_GetContentRegionAvail(ctx)
        local changed_any = false
        local vol_changed = false
        
        -- HEADER
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        local btn_w = 40
        local spacing = 32
        local flexible_w = avail_w - (60 + (btn_w * 3) + spacing)
        local combo_w = flexible_w * 0.55
        local input_w = flexible_w * 0.45
        
        r.ImGui_Text(ctx, "PRESETS:")
        r.ImGui_SameLine(ctx)
        
        r.ImGui_SetNextItemWidth(ctx, combo_w)
        if r.ImGui_BeginCombo(ctx, "##presets", config.current_preset) then
            r.ImGui_TextDisabled(ctx, "Factory:")
            for name, _ in pairs(FACTORY_PRESETS) do
                if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any = true; vol_changed = true end
            end
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "User:")
            local user_list = r.GetExtState(EXT_SECTION, EXT_KEY_PRESETS)
            for name in string.gmatch(user_list, "([^|]+)") do
                if r.ImGui_Selectable(ctx, name, config.current_preset == name) then LoadPreset(name, false); changed_any = true; vol_changed = true end
            end
            r.ImGui_EndCombo(ctx) 
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, input_w)
        _, config.new_preset_name = r.ImGui_InputText(ctx, "##newname", config.new_preset_name)
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "S", btn_w) then SaveUserPreset(config.new_preset_name) end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UI_CONST.btn_del); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), UI_CONST.btn_del_hover)
        if r.ImGui_Button(ctx, "D", btn_w) then DeleteUserPreset(config.current_preset) end
        r.ImGui_PopStyleColor(ctx, 2)
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "[ OPT ]", btn_w) then r.ImGui_OpenPopup(ctx, "Settings") end

        -- Randomize Button (Full Width New Row)
        if r.ImGui_Button(ctx, "RANDOMIZE CONFIGURATION", -1) then RandomizeConfig(); changed_any = true; vol_changed = true end
        
        -- SETTINGS MODAL
        if r.ImGui_BeginPopupModal(ctx, "Settings", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Track Name:")
            local rv2, txt = r.ImGui_InputText(ctx, "##trname", settings.track_name)
            if rv2 then settings.track_name = txt; SaveSettings() end
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Theme Colors:")
            
            local function ColEdit(label, col)
                local retval, new_col = r.ImGui_ColorEdit4(ctx, label, col, r.ImGui_ColorEditFlags_NoInputs())
                return new_col, retval
            end
            
            local c_ch; settings.col_accent, c_ch = ColEdit("Accent", settings.col_accent)
            if c_ch then SaveSettings() end
            local c_ch3; settings.col_bg, c_ch3 = ColEdit("BG", settings.col_bg)
            if c_ch3 then SaveSettings() end
            
            if r.ImGui_Button(ctx, "Close", 120, 0) then r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_EndPopup(ctx)
        end

        -- MAIN CONTROLS
        r.ImGui_Separator(ctx)

        if r.ImGui_BeginChild(ctx, "child_env", win_w, 160, 0) then 
            DrawEnvelopePreview(win_w, 80); 
            r.ImGui_Dummy(ctx, win_w, 82) 
            r.ImGui_PushItemWidth(ctx, win_w); local rv, v = r.ImGui_SliderDouble(ctx, '##peak', config.peak_pos, 0.1, 0.9, 'Peak'); if rv then config.peak_pos = v; changed_any = true; vol_changed = true end; r.ImGui_PopItemWidth(ctx)
            r.ImGui_PushItemWidth(ctx, (win_w*0.5)-5); rv, v = r.ImGui_SliderDouble(ctx, '##att', config.tens_attack, -1.0, 1.0, 'In'); if rv then config.tens_attack = v; changed_any = true; vol_changed = true end
            r.ImGui_SameLine(ctx); rv, v = r.ImGui_SliderDouble(ctx, '##rel', config.tens_release, -1.0, 1.0, 'Out'); if rv then config.tens_release = v; changed_any = true; vol_changed = true end; r.ImGui_PopItemWidth(ctx)
            r.ImGui_EndChild(ctx)
        end
        
        local pad_s = (win_w / 2) - 12; if pad_s < 100 then pad_s = 100 end 
        if r.ImGui_BeginChild(ctx, "child_pads", win_w, (pad_s*2)+30, 0) then
            r.ImGui_BeginGroup(ctx); if DrawVectorPad("##src", 4, pad_s, pad_s) then changed_any=true end; r.ImGui_EndGroup(ctx) 
            r.ImGui_SameLine(ctx); r.ImGui_BeginGroup(ctx); if DrawVectorPad("##morph", 1, pad_s, pad_s) then changed_any=true end; r.ImGui_EndGroup(ctx) 
            r.ImGui_BeginGroup(ctx); if DrawVectorPad("##tone", 2, pad_s, pad_s) then changed_any=true end; r.ImGui_EndGroup(ctx) 
            r.ImGui_SameLine(ctx); r.ImGui_BeginGroup(ctx); if DrawVectorPad("##stereo", 3, pad_s, pad_s) then changed_any=true end; r.ImGui_EndGroup(ctx) 
            r.ImGui_EndChild(ctx)
        end
        
        if r.ImGui_BeginChild(ctx, "child_fx", win_w, 100, 0) then
            local hw = (win_w*0.5)-25 
            r.ImGui_Checkbox(ctx, "##f", config.flange_enable); r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, settings.col_accent, "Flange")
            r.ImGui_SameLine(ctx, 100); r.ImGui_PushItemWidth(ctx, hw-40); local rv, v = r.ImGui_SliderDouble(ctx, '##fw', config.flange_wet, 0, 1, "Mix"); if rv then config.flange_wet=v; changed_any=true end
            r.ImGui_SameLine(ctx); rv, v = r.ImGui_SliderDouble(ctx, '##ff', config.flange_feed, 0, 1, "Feed"); if rv then config.flange_feed=v; changed_any=true end; r.ImGui_PopItemWidth(ctx)
            r.ImGui_Checkbox(ctx, "##v", config.verb_enable); r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, settings.col_accent, "Reverb")
            r.ImGui_SameLine(ctx, 100); r.ImGui_PushItemWidth(ctx, hw-40); rv, v = r.ImGui_SliderDouble(ctx, '##vw', config.verb_wet, 0, 1, "Mix"); if rv then config.verb_wet=v; changed_any=true end
            r.ImGui_SameLine(ctx); rv, v = r.ImGui_SliderDouble(ctx, '##vs', config.verb_size, 0, 1, "Size"); if rv then config.verb_size=v; changed_any=true end; r.ImGui_PopItemWidth(ctx)
            r.ImGui_EndChild(ctx)
        end

        local btn_env_w = 110
        local btn_gen_w = win_w - btn_env_w - 10 
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), UI_CONST.btn_sec); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), UI_CONST.btn_sec_hover)
        if r.ImGui_Button(ctx, "SHOW ENVS", btn_env_w, 40) then ToggleEnvelopes() end
        r.ImGui_PopStyleColor(ctx, 2); 
        
        r.ImGui_SameLine(ctx)
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.col_accent); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.col_accent + 0x10101000); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
        if r.ImGui_Button(ctx, 'GENERATE', btn_gen_w, 40) then GenerateWhoosh() end
        r.ImGui_PopStyleColor(ctx, 3)

        if changed_any then 
            if vol_changed then UpdateAutomationOnly("all") 
            else UpdateAutomationOnly("env") end
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 14); r.ImGui_PopStyleVar(ctx, 3)
    if open then r.defer(Loop) end
end

LoadSettings()
r.defer(Loop)
