-- @description SBP ReaWhoosh - Advanced Whoosh Generator
-- @author SBP & AI
-- @version 3.5.3
-- @about ReaWhoosh is a tool for automatically creating whoosh-type sound effects.
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @provides
--   [main] .
--   modules/SurroundWindow.lua
-- @changelog
--    v3.5.3 (2026-02-20)
--    Minor bug fixes and performance improvements.
--    v3.5.2 (2026-02-19)
--    Added Full Circles mode for unlimited rotations using internal phase accumulator. Surround modes now: Vector 3-point / Circle Arc 3-point / Full Circles. Removed Speed multiplier from Circle Arc (now for arcs only), added Rotations Count & Start Angle for Full Circles mode. Fixed proper VBAP 5.1 panning with mono source distribution.
--    v3.5.1 (2026-02-19)
--    Fixed: Surround Circle mode Speed now works correctly (Speed=1.0 means exactly 1 rotation, Speed=2.0 means 2 rotations).
--    Fixed: Audio dropout issue during circular surround motion - implemented proper VBAP panning algorithm for ITU-R BS.775 5.1 speaker layout.
--    Fixed: Removed broken play_position calculation in WhooshEngine - Circle mode now uses automation-driven sur_path_x/y coordinates (same as Vector mode).
--    v3.5.0 (2026-02-19)
--    Added dedicated Surround Path window (UTI 5.1) with two modes: 3-point Vector and 3-point Circle. Space Pad now keeps stereo-style FX behavior in both output modes, while surround movement is handled in the new window. Added new WhooshEngine surround sliders and preset/settings integration. Fixed: Circle mode always uses linear curves for uniform rotation (independent of Volume Shape inheritance). (2026-02-19)
--    Fixed: All Sur.Path automations (surround panning) now use linear interpolation (shape=2) for smooth motion independent of Volume Shape setting. This ensures correct spatial panning in both Vector and Circle modes. (2026-02-19)
--    Added option: "All envelopes inherit Volume Shape" (Options > Envelope Settings). Now, if enabled, all envelopes use the same shape and bezier tension as Volume. Integrated with presets and UI. (2026-02-19)

---@diagnostic disable-next-line: undefined-global
local r = reaper
local ctx = r.ImGui_CreateContext('ReaWhoosh')
r.gmem_attach('sbp_whoosh') 

local script_path = debug.getinfo(1, 'S').source:match("@(.*[\\/])") or ""
local ok_surround, err_surround = pcall(dofile, script_path .. "modules/SurroundWindow.lua")
if not ok_surround then
    r.ShowConsoleMsg("[ReaWhoosh] Failed to load modules/SurroundWindow.lua: " .. tostring(err_surround) .. "\n")
    function BuildSurroundPathPoints(cfg)
        return cfg.sur_v_s_x or 0, cfg.sur_v_s_y or 0, cfg.sur_v_p_x or 0.5, cfg.sur_v_p_y or 1, cfg.sur_v_e_x or 1, cfg.sur_v_e_y or 0.5
    end
    function GetSurroundLivePoint(cfg, t_norm)
        local sx, sy, px, py, ex, ey = BuildSurroundPathPoints(cfg)
        local t = Clamp(t_norm or 0.5, 0, 1)
        if t <= 0.5 then
            local k = t * 2.0
            return sx + (px - sx) * k, sy + (py - sy) * k
        end
        local k = (t - 0.5) * 2.0
        return px + (ex - px) * k, py + (ey - py) * k
    end
    function DrawSurroundWindow()
        return false, false
    end
end

-- FORWARD DECLARATIONS
local GenerateWhoosh 

-- =========================================================
-- 1. CONSTANTS
-- =========================================================
local C_TEXT        = 0xE0E0E0FF
local C_BTN_SEC     = 0x444444FF
local C_BTN_ACTIVE  = 0x2D8C6DFF
local C_MUTE_ACTIVE = 0xCC4444FF
local C_FRAME_BG    = 0x00000060
local C_PAD_BG      = 0x00000050
local C_ACCENT_DEF  = 0x2D8C6DFF
local C_BG_DEF      = 0x252525FF
local C_ORANGE      = 0xD46A3FFF
local C_WHITE       = 0xFFFFFFFF
local C_GREY        = 0x888888FF
local C_SLIDER_BG   = 0x00000090

local PAD_SQUARE    = 170 
local MIX_W         = 25  
local MIX_H         = 150 
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
    pitch_mode = 0,
    audio_pitch = 0.0,
    -- Randomization Masks
    rand_src = true, rand_morph = true, rand_filt = true,
    rand_dop = true, rand_space = true, rand_chop = true, rand_env = false,
    rand_surround = true,
    env_inherit_shape = false,
    sur_win_open = false
}

local config = {
    peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
    rise_slope = 0.0,
    src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
    cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
    morph_s_x=0.0, morph_s_y=1.0, morph_p_x=0.5, morph_p_y=0.5, morph_e_x=0.0, morph_e_y=0.0,
    dop_s_x=0.0, dop_s_y=0.5, dop_p_x=0.5, dop_p_y=0.5, dop_e_x=1.0, dop_e_y=0.5,
    spc_s_x=0.0, spc_s_y=0.0, spc_p_x=0.5, spc_p_y=1.0, spc_e_x=1.0, spc_e_y=0.5,
    sur_mode = 0,
    sur_v_s_x=0.0, sur_v_s_y=0.0, sur_v_p_x=0.5, sur_v_p_y=1.0, sur_v_e_x=1.0, sur_v_e_y=0.5,
    sur_c_len=0.9, sur_c_off=0.0, sur_c_dir=false,
    sur_full_rot=1.0, sur_full_off=0.25,
    sur_c_s_x=1.0, sur_c_s_y=0.5, sur_c_p_x=0.5, sur_c_p_y=1.0, sur_c_e_x=0.0, sur_c_e_y=0.5,
    
    chop_s_x=0.0, chop_s_y=0.0, chop_p_x=0.5, chop_p_y=0.0, chop_e_x=0.0, chop_e_y=0.0,
    chop_enable=true, chop_shape=0.0,

    link_s_x=0.0, link_s_y=0.0, link_p_x=0.5, link_p_y=1.0, link_e_x=1.0, link_e_y=0.0,
    link_bindings = {
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0}
    },

    sub_freq = 55, sub_enable = true, sub_vol = 0.8, sub_sat = 0.0,
    
    noise_type = 0, noise_tone = 0.0,
    osc_shape_type = 1, osc_pwm = 0.1, osc_detune = 0.0, osc_drive = 0.0, osc_octave = 0.0, osc_tone = 0.0,
    chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, chua_alpha = 15.6,
    sat_drive = 0.0, crush_mix = 0.0, crush_rate = 1.0, punch_amt = 0.0, ring_metal = 0.0, noise_routing = 0,
    
    flange_wet=0.0, flange_feed=0.0, verb_size=0.5, rev_damp = 0.5, verb_tail = 0.5,
    dbl_time = 30, dbl_wide = 0.5,
    
    doppler_air = 0.5, 
    grain_size = 1, -- 0=512, 1=1024, 2=2048, 3=4096

    mute_w = false, mute_o = false, mute_c = false, mute_e = false,
    trim_w = 1.0, trim_o = 1.0, trim_c = 1.0, trim_e = 1.0, 
    current_preset = "Default",
    bounce_tail = 0.5
}

local FACTORY_PRESETS = {
    ["Default"] = {
        peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4, rise_slope = 0.0,
        audio_pitch = 0.0,
        src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
        cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
        sur_mode = 0,
        sur_v_s_x=0.0, sur_v_s_y=0.0, sur_v_p_x=0.5, sur_v_p_y=1.0, sur_v_e_x=1.0, sur_v_e_y=0.5,
        sur_c_len=0.9, sur_c_off=0.0, sur_c_dir=false,
        sur_full_rot=1.0, sur_full_off=0.0,
        sub_freq = 55, sub_vol = 0.8, sub_enable = true, sub_sat = 0.0,
        noise_type = 0, noise_tone = 0.0, noise_routing = 0,
        osc_shape_type = 1, osc_pwm = 0.1, osc_detune = 0.0, osc_drive = 0.0, osc_octave = 0.0, osc_tone = 0.0,
        chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, chua_alpha = 15.6,
        sat_drive = 0.0, crush_mix = 0.0, crush_rate = 1.0,
        punch_amt = 0.0,
        pitch_mode = 0, doppler_air = 0.5, grain_size = 1,
        flange_wet=0.0, verb_size=0.5, dbl_wide = 0.5, rev_damp = 0.5, verb_tail = 0.5,
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
    env_val = 0, global_pitch = 1, master_vol = 2, out_mode = 3, pitch_mode = 4,
    mix_noise = 5, noise_type = 6, noise_tone = 7,
    mix_osc = 8, osc_shape = 9, osc_pwm = 10, osc_detune = 11, osc_drive = 12,
    mix_chua = 13, chua_rate = 14, chua_shape = 15, chua_timbre = 16, chua_alpha = 17,
    mix_sub = 18, sub_freq = 19, sub_sat = 20, mix_ext = 21,
    filt_morph_x = 22, filt_morph_y = 23, filt_freq = 24, filt_res = 25,
    flange_mix = 26, flange_feed = 27, dbl_mix = 28, dbl_time = 29, dbl_wide = 30,
    verb_mix = 31, verb_size = 32, verb_damp = 33, verb_tail = 34,
    sat_drive = 35, crush_mix = 36, crush_rate = 37, punch_amt = 38,
    chop_depth = 39, chop_rate = 40, chop_shape = 41,
    pan_x = 42, pan_y = 43, width = 44,
    trim_w = 45, trim_o = 46, trim_c = 47, trim_e = 48,
    ring_metal = 49, osc_octave = 50, audio_pitch = 51, osc_tone = 52, noise_routing = 53,
    doppler_air = 54, grain_size = 55,
    sur_mode = 56, sur_path_x = 57, sur_path_y = 58,
    sur_arc_len = 59, sur_arc_off = 60, sur_full_rotations = 61, sur_direction = 62, sur_full_offset = 63
}

local interaction = { dragging_pad = nil, dragging_point = nil, last_update_time = 0, dragging_peak = false }
local surround_env_dirty = false
local pads_dirty = false
local scope_history = {} 
local track_cache = {}
local track_cache_time = 0
local preset_cache = {}
local last_preset_applied = ""
local color_cache = {}
local fx_cache = {} 
local FX_NAME = "sbp_WhooshEngine"

function SafeCol(c, def) return (type(c)=="number") and c or (def or C_WHITE) end
function Clamp(val, min, max) return math.min(math.max(val or 0, min or 0), max or 1) end

function DarkenColor(col)
    local r = (col >> 24) & 0xFF
    local g = (col >> 16) & 0xFF
    local b = (col >> 8)  & 0xFF
    local a = col & 0xFF
    r = math.floor(r * 0.8); g = math.floor(g * 0.8); b = math.floor(b * 0.8)
    return (r << 24) | (g << 16) | (b << 8) | a
end

function LightenColor(col, factor)
    factor = factor or 1.12
    local r = math.min(255, math.floor(((col >> 24) & 0xFF) * factor))
    local g = math.min(255, math.floor(((col >> 16) & 0xFF) * factor))
    local b = math.min(255, math.floor(((col >> 8)  & 0xFF) * factor))
    local a = col & 0xFF
    return (r << 24) | (g << 16) | (b << 8) | a
end

function ValidateConfig()
    if not config.peak_pos then config.peak_pos = 0.5 end
    if not config.grain_size then config.grain_size = 1 end
    if not config.doppler_air then config.doppler_air = 0.5 end
    if config.sur_mode == nil then config.sur_mode = 0 end
    config.sur_mode = Clamp(config.sur_mode, 0, 2)
    if config.sur_c_len == nil then config.sur_c_len = 0.9 end
    config.sur_c_len = Clamp(config.sur_c_len, 0.05, 0.9)
    if config.sur_c_off == nil then config.sur_c_off = 0.0 end
    if config.sur_full_rot == nil then config.sur_full_rot = 1.0 end
    if config.sur_full_off == nil then config.sur_full_off = 0.25 end
    if config.sur_c_dir == nil then config.sur_c_dir = false end
    if config.sur_v_s_x == nil then config.sur_v_s_x = 0.0 end
    if config.sur_v_s_y == nil then config.sur_v_s_y = 0.0 end
    if config.sur_v_p_x == nil then config.sur_v_p_x = 0.5 end
    if config.sur_v_p_y == nil then config.sur_v_p_y = 1.0 end
    if config.sur_v_e_x == nil then config.sur_v_e_x = 1.0 end
    if config.sur_v_e_y == nil then config.sur_v_e_y = 0.5 end
    if settings.rand_surround == nil then settings.rand_surround = true end
    -- Завжди починаємо без Surround Window
    settings.sur_win_open = false
end

function SaveSettings()
    local str = string.format(
        "name=%s;mode=%d;c1=%d;c3=%d;mv=%.2f;shp=%d;pm=%d;rs=%d;rm=%d;rf=%d;rd=%d;rsp=%d;rc=%d;re=%d;rsr=%d;esh=%d",
        settings.track_name, settings.output_mode,
        SafeCol(settings.col_accent, C_ACCENT_DEF), SafeCol(settings.col_bg, C_BG_DEF), settings.master_vol or -6.0,
        settings.env_shape or 0, settings.peak_mode or 0,
        settings.rand_src and 1 or 0, settings.rand_morph and 1 or 0, settings.rand_filt and 1 or 0,
        settings.rand_dop and 1 or 0, settings.rand_space and 1 or 0, settings.rand_chop and 1 or 0, settings.rand_env and 1 or 0,
        settings.rand_surround and 1 or 0, settings.env_inherit_shape and 1 or 0
    )
    r.SetExtState("ReaWhoosh_v3", "Global_Settings", str, true)
end

function LoadSettings()
    local str = r.GetExtState("ReaWhoosh_v3", "Global_Settings")
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
            elseif k == "rsr" then settings.rand_surround = (tonumber(v)==1)
            elseif k == "esh" then settings.env_inherit_shape = (tonumber(v)==1)
            end
        end
    end
    ValidateConfig()
end

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
            if data and data ~= "" then USER_PRESETS[name] = data end
        end
    end
end

function SaveUserPreset(name)
    if name == "" then return end
    local data = SerializeConfig()
    r.SetExtState(PRESET_SECTION, name, data, true)
    local list_str = r.GetExtState(PRESET_SECTION, PRESET_LIST_KEY)
    local exists = false
    for n in list_str:gmatch("([^|]+)") do if n == name then exists = true; break end end
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
    for n in list_str:gmatch("([^|]+)") do if n ~= name then new_list = new_list .. n .. "|" end end
    r.SetExtState(PRESET_SECTION, PRESET_LIST_KEY, new_list, true)
    LoadUserPresets()
    config.current_preset = "Default"
    ApplyPreset("Default")
end

function ApplyPreset(name)
    if last_preset_applied == name then return end
    local data = nil
    if FACTORY_PRESETS[name] then
        for k,v in pairs(FACTORY_PRESETS[name]) do config[k] = v end
        config.current_preset = name
        last_preset_applied = name
        return
    elseif USER_PRESETS[name] then data = USER_PRESETS[name] end
    if data then
        if not preset_cache[name] then preset_cache[name] = data end
        DeserializeAndApply(preset_cache[name])
        config.current_preset = name
        last_preset_applied = name
    end
end

function ToPitch(norm) return (norm * 24) - 12 end
function ToAudioPitch(norm) return (norm * 72) - 36 end

function GetOrAddFX(track, name)
    local track_ptr = tostring(track)
    if fx_cache[track_ptr] then
        local cached_idx = fx_cache[track_ptr]
        local _, buf = r.TrackFX_GetFXName(track, cached_idx)
        if buf and buf:lower():find(name:lower(), 1, true) then return cached_idx end
    end
    local cnt = r.TrackFX_GetCount(track)
    for i = 0, cnt - 1 do
        local _, buf = r.TrackFX_GetFXName(track, i)
        if buf:lower():find(name:lower(), 1, true) then fx_cache[track_ptr] = i; return i end
    end
    local idx = r.TrackFX_AddByName(track, name, false, -1)
    fx_cache[track_ptr] = idx
    return idx
end

function FindTrackByName(name)
    local now = r.time_precise()
    if track_cache[name] and now - track_cache_time < 0.5 then
        local track = track_cache[name]
        if r.ValidatePtr(track, "MediaTrack*") then return track end
    end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name then track_cache[name] = track; track_cache_time = now; return track end
    end
    track_cache[name] = nil
    return nil
end

function SetEnvVisible(env)
    if not env then return end
    local retval, str = r.GetEnvelopeStateChunk(env, "", false)
    if retval then
        local new_str = str:gsub("VIS %d", "VIS 1"):gsub("ARM %d", "ARM 1")
        if not str:find("VIS") then new_str = new_str:gsub("ACT %d", "ACT 1\nVIS 1") end
        r.SetEnvelopeStateChunk(env, new_str, false)
    end
end

function ShowAllEnvelopes() 
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local fx_idx = GetOrAddFX(track, "sbp_WhooshEngine")
    local env = r.GetFXEnvelope(track, fx_idx, IDX.env_val, true)
    if env then SetEnvVisible(env) end
    local pitch_env = r.GetFXEnvelope(track, fx_idx, IDX.global_pitch, true) 
    if pitch_env then SetEnvVisible(pitch_env) end
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

function ToggleEnvelopes() r.Main_OnCommand(41151, 0) end

function ResetPitchEnvelope()
    config.dop_s_y = 0.5; config.dop_p_y = 0.5; config.dop_e_y = 0.5
    if config.pitch_mode == 2 then config.audio_pitch = 0.0 end
end

function RandomizeConfig()
    local function rf() return math.random() end
    if settings.rand_env then
        config.peak_pos = 0.2 + rf() * 0.6
        if settings.env_shape == 0 then config.tens_attack = (rf() * 2.0) - 1.0; config.tens_release = (rf() * 2.0) - 1.0 end
    end
    if settings.rand_src then 
        config.src_s_x = rf(); config.src_s_y = rf(); config.src_p_x = rf(); config.src_p_y = rf(); config.src_e_x = rf(); config.src_e_y = rf()
        config.sub_freq = 30 + math.floor(rf()*90)
        config.osc_shape_type = math.random(0,3)
        config.osc_pwm = rf() * 0.5
        config.osc_detune = (rf() * 100) - 50
        config.osc_drive = rf() * 0.7
        config.osc_tone = (rf() * 2) - 1
        config.noise_type = math.random(0,2)
        config.noise_tone = (rf() * 2) - 1
        config.noise_routing = math.random(0, 1)
        config.chua_alpha = -20 + (rf() * 40)
        config.sub_sat = rf() * 0.5
    end
    if settings.rand_morph then config.morph_s_x = rf(); config.morph_s_y = rf(); config.morph_p_x = rf(); config.morph_p_y = rf(); config.morph_e_x = rf(); config.morph_e_y = rf() end
    if settings.rand_filt then config.cut_s_x = rf(); config.cut_s_y = rf(); config.cut_p_x = rf(); config.cut_p_y = rf(); config.cut_e_x = rf(); config.cut_e_y = rf() end
    
    if settings.rand_dop then
        config.dop_s_x = rf(); config.dop_s_y = rf(); config.dop_p_x = rf(); config.dop_p_y = rf(); config.dop_e_x = rf(); config.dop_e_y = rf()
        config.pitch_mode = math.random(0, 3) 
        config.doppler_air = rf()
    end

    if settings.rand_space then
        config.spc_s_x = rf(); config.spc_s_y = rf(); config.spc_p_x = rf(); config.spc_p_y = rf(); config.spc_e_x = rf(); config.spc_e_y = rf()
        config.sat_drive = rf() * 0.8; config.crush_mix = rf() * 0.5; config.crush_rate = 0.3 + (rf() * 0.7)
    end
    if settings.rand_surround then
        config.sur_mode = math.random(0, 2)
        config.sur_v_s_x = rf(); config.sur_v_s_y = rf(); config.sur_v_p_x = rf(); config.sur_v_p_y = rf(); config.sur_v_e_x = rf(); config.sur_v_e_y = rf()
        config.sur_c_len = 0.05 + rf() * 0.85
        config.sur_c_off = rf()
        config.sur_c_dir = (math.random(0, 1) == 1)
        config.sur_full_rot = 0.5 + rf() * 3.5
        config.sur_full_off = rf()
    end
    if settings.rand_chop then config.chop_s_x = rf(); config.chop_s_y = rf(); config.chop_p_x = rf(); config.chop_p_y = rf(); config.chop_e_x = rf(); config.chop_e_y = rf() end
end

function Create3PointRampFX(track, fx_idx, param_idx, t_s, t_p, t_e, v_s, v_p, v_e, shape_override, tens_att, tens_rel)
    if fx_idx < 0 or param_idx < 0 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true) 
    if env then
        SetEnvVisible(env)
        r.DeleteEnvelopePointRange(env, t_s-0.001, t_e+0.001)
        local sh = 0; local ta, tr = 0, 0
        if shape_override then
            if shape_override == 0 then sh = 5; ta = tens_att; tr = tens_rel
            elseif shape_override == 1 then sh = 5; ta = tens_att; tr = tens_rel
            elseif shape_override == 2 then sh = 2; ta = 0; tr = 0 end
        end
        local ins_ta = (sh == 5) and ta or 0; local ins_tp = (sh == 5) and tr or 0
        r.InsertEnvelopePoint(env, t_s, v_s, sh, ins_ta, true, true)
        r.InsertEnvelopePoint(env, t_p, v_p, sh, ins_tp, true, true)
        r.InsertEnvelopePoint(env, t_e, v_e, sh, 0, true, true)
        if sh ~= 0 then
            local cnt = r.CountEnvelopePoints(env)
            if sh == 5 then
                r.SetEnvelopePoint(env, cnt-3, t_s, v_s, sh, ta, true, true)
                r.SetEnvelopePoint(env, cnt-2, t_p, v_p, sh, tr, true, true)
                r.SetEnvelopePoint(env, cnt-1, t_e, v_e, sh, 0,  true, true)
            else
                r.SetEnvelopePoint(env, cnt-3, t_s, v_s, sh, 0, true, true)
                r.SetEnvelopePoint(env, cnt-2, t_p, v_p, sh, 0, true, true)
                r.SetEnvelopePoint(env, cnt-1, t_e, v_e, sh, 0, true, true)
            end
        end
        r.Envelope_SortPoints(env)
    end
end

function Create5PointRampFX(track, fx_idx, param_idx, t_s, t_p, t_e, v_s, v_p, v_e, tension)
    if fx_idx < 0 or param_idx < 0 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true) 
    if env then
        SetEnvVisible(env)
        r.DeleteEnvelopePointRange(env, t_s-0.001, t_e+0.001)
        local total_len = t_e - t_s; local spread = total_len * 0.15
        local t_2 = t_p - spread; local t_4 = t_p + spread
        if t_2 < t_s then t_2 = t_s + (t_p - t_s) * 0.1 end
        if t_4 > t_e then t_4 = t_p + (t_e - t_p) * 0.9 end
        local sh = 5 
        r.InsertEnvelopePoint(env, t_s, v_s, sh, 0, true, true)
        r.InsertEnvelopePoint(env, t_2, v_s, sh, tension, true, true)
        r.InsertEnvelopePoint(env, t_p, v_p, sh, tension, true, true)
        r.InsertEnvelopePoint(env, t_4, v_e, sh, 0, true, true)
        r.InsertEnvelopePoint(env, t_e, v_e, sh, 0, true, true)
        r.Envelope_SortPoints(env)
    end
end

function ClearPanAutomations(should_clear_surround)
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local fx = GetOrAddFX(track, FX_NAME)
        local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if start_time == end_time then
            r.ShowConsoleMsg("ReaWhoosh: Select time range to reset pan/surround envelopes.\n")
            return
        end

        local function ResetEnvRange(env, value)
            if not env then return end
            r.DeleteEnvelopePointRange(env, start_time - 0.001, end_time + 0.001)
            r.InsertEnvelopePoint(env, start_time, value, 0, 0, true, true)
            r.InsertEnvelopePoint(env, end_time, value, 0, 0, true, true)
            r.Envelope_SortPoints(env)
        end
    
    if should_clear_surround then
        -- Видалити Surround Path automations при переходу в Stereo
        local env_sur_x = r.GetFXEnvelope(track, fx, IDX.sur_path_x, false)
        local env_sur_y = r.GetFXEnvelope(track, fx, IDX.sur_path_y, false)
        ResetEnvRange(env_sur_x, 0.5)
        ResetEnvRange(env_sur_y, 0.0)
    else
        -- Видалити Stereo Pan automations при переходу в Surround
        local env_pan_x = r.GetFXEnvelope(track, fx, IDX.pan_x, false)
        local env_pan_y = r.GetFXEnvelope(track, fx, IDX.pan_y, false)
        ResetEnvRange(env_pan_x, 0.5)
        ResetEnvRange(env_pan_y, 0.5)
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

    local fx = GetOrAddFX(track, FX_NAME)
    
    r.TrackFX_SetParam(track, fx, IDX.out_mode, settings.output_mode)
    r.TrackFX_SetParam(track, fx, IDX.master_vol, settings.master_vol)
    r.TrackFX_SetParam(track, fx, IDX.pitch_mode, config.pitch_mode or 0)
    
    r.TrackFX_SetParam(track, fx, IDX.sub_freq, config.sub_freq)
    r.TrackFX_SetParam(track, fx, IDX.mix_sub, config.sub_enable and config.sub_vol or 0)
    r.TrackFX_SetParam(track, fx, IDX.sub_sat, config.sub_sat or 0)
    r.TrackFX_SetParam(track, fx, IDX.noise_type, config.noise_type or 0)
    r.TrackFX_SetParam(track, fx, IDX.noise_tone, config.noise_tone or 0)
    r.TrackFX_SetParam(track, fx, IDX.noise_routing, config.noise_routing or 0)
    r.TrackFX_SetParam(track, fx, IDX.osc_shape, config.osc_shape_type)
    r.TrackFX_SetParam(track, fx, IDX.osc_pwm, config.osc_pwm)
    r.TrackFX_SetParam(track, fx, IDX.osc_detune, config.osc_detune)
    r.TrackFX_SetParam(track, fx, IDX.osc_drive, config.osc_drive or 0)
    r.TrackFX_SetParam(track, fx, IDX.osc_octave, config.osc_octave or 0)
    r.TrackFX_SetParam(track, fx, IDX.osc_tone, config.osc_tone or 0)
    r.TrackFX_SetParam(track, fx, IDX.chua_rate, config.chua_rate)
    r.TrackFX_SetParam(track, fx, IDX.chua_shape, config.chua_shape)
    r.TrackFX_SetParam(track, fx, IDX.chua_timbre, config.chua_timbre)
    r.TrackFX_SetParam(track, fx, IDX.chua_alpha, config.chua_alpha or 15.6)
    r.TrackFX_SetParam(track, fx, IDX.sat_drive, config.sat_drive or 0)
    r.TrackFX_SetParam(track, fx, IDX.crush_mix, config.crush_mix or 0)
    r.TrackFX_SetParam(track, fx, IDX.crush_rate, config.crush_rate or 1.0)
    r.TrackFX_SetParam(track, fx, IDX.punch_amt, config.punch_amt or 0)
    r.TrackFX_SetParam(track, fx, IDX.ring_metal, config.ring_metal or 0)
    r.TrackFX_SetParam(track, fx, IDX.trim_w, config.mute_w and 0 or config.trim_w)
    r.TrackFX_SetParam(track, fx, IDX.trim_o, config.mute_o and 0 or config.trim_o)
    r.TrackFX_SetParam(track, fx, IDX.trim_c, config.mute_c and 0 or config.trim_c)
    r.TrackFX_SetParam(track, fx, IDX.trim_e, config.mute_e and 0 or config.trim_e)
    r.TrackFX_SetParam(track, fx, IDX.chop_shape, config.chop_shape)
    r.TrackFX_SetParam(track, fx, IDX.flange_mix, config.flange_wet)
    r.TrackFX_SetParam(track, fx, IDX.flange_feed, config.flange_feed)
    r.TrackFX_SetParam(track, fx, IDX.dbl_wide, config.dbl_wide)
    r.TrackFX_SetParam(track, fx, IDX.dbl_time, config.dbl_time)
    r.TrackFX_SetParam(track, fx, IDX.verb_damp, config.rev_damp)
    r.TrackFX_SetParam(track, fx, IDX.verb_tail, config.verb_tail or 0.5)
    r.TrackFX_SetParam(track, fx, IDX.verb_size, config.verb_size)
    r.TrackFX_SetParam(track, fx, IDX.doppler_air, config.doppler_air or 0.5)
    r.TrackFX_SetParam(track, fx, IDX.grain_size, config.grain_size or 1)
    local sur_px, sur_py = GetSurroundLivePoint(config, config.peak_pos or 0.5)
    r.TrackFX_SetParam(track, fx, IDX.sur_mode, config.sur_mode or 0)
    r.TrackFX_SetParam(track, fx, IDX.sur_path_x, sur_px or 0.5)
    r.TrackFX_SetParam(track, fx, IDX.sur_path_y, sur_py or 0.0)
    r.TrackFX_SetParam(track, fx, IDX.sur_arc_len, config.sur_c_len or 0.9)
    r.TrackFX_SetParam(track, fx, IDX.sur_arc_off, config.sur_c_off or 0.0)
    r.TrackFX_SetParam(track, fx, IDX.sur_full_rotations, config.sur_full_rot or 1.0)
    r.TrackFX_SetParam(track, fx, IDX.sur_direction, config.sur_c_dir and 1 or 0)
    r.TrackFX_SetParam(track, fx, IDX.sur_full_offset, config.sur_full_off or 0.0)

    r.Undo_BeginBlock()
    r.SetOnlyTrackSelected(track)
    
    if flags == "all" or flags == "env" or flags == "vol" then
        local ta, tr = config.tens_attack, config.tens_release
        if settings.env_shape == 1 then
            local slope = config.rise_slope or 0
            local tmag = slope * 0.9
            if config.peak_pos > 0.5 then ta = tmag; tr = 0 else ta = 0; tr = -tmag end
        end
        Create3PointRampFX(track, fx, IDX.env_val, start_time, peak_time, end_time, 0.0, 1.0, 0.0, settings.env_shape, ta, tr)
    end

    if flags == "all" or flags == "env" then
        local function SCurve(t) return t*t*t / (t*t*t + (1-t)*(1-t)*(1-t)) end
        local function get_vols(x, y) local sx, sy = SCurve(x), SCurve(y); return (1-sx)*sy, sx*sy, (1-sx)*(1-sy), sx*(1-sy) end
        local v1_s, v2_s, v3_s, v4_s = get_vols(config.src_s_x, config.src_s_y)
        local v1_p, v2_p, v3_p, v4_p = get_vols(config.src_p_x, config.src_p_y)
        local v1_e, v2_e, v3_e, v4_e = get_vols(config.src_e_x, config.src_e_y)
        
        if config.mute_w then v1_s=0;v1_p=0;v1_e=0 end
        if config.mute_o then v2_s=0;v2_p=0;v2_e=0 end
        if config.mute_c then v3_s=0;v3_p=0;v3_e=0 end
        if config.mute_e then v4_s=0;v4_p=0;v4_e=0 end
        

                local inherit_shape = settings.env_inherit_shape and settings.env_shape or nil
                local inherit_ta, inherit_tr = config.tens_attack, config.tens_release
                if settings.env_inherit_shape then
                    if settings.env_shape == 1 then
                        local slope = config.rise_slope or 0
                        local tmag = slope * 0.9
                        if config.peak_pos > 0.5 then inherit_ta = tmag; inherit_tr = 0 else inherit_ta = 0; inherit_tr = -tmag end
                    end
                end
                Create3PointRampFX(track, fx, IDX.mix_noise, start_time, peak_time, end_time, v1_s, v1_p, v1_e, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.mix_osc, start_time, peak_time, end_time, v2_s, v2_p, v2_e, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.mix_chua, start_time, peak_time, end_time, v3_s, v3_p, v3_e, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.mix_ext, start_time, peak_time, end_time, v4_s, v4_p, v4_e, inherit_shape, inherit_ta, inherit_tr)

                Create3PointRampFX(track, fx, IDX.filt_morph_x, start_time, peak_time, end_time, config.morph_s_x, config.morph_p_x, config.morph_e_x, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_morph_y, start_time, peak_time, end_time, config.morph_s_y, config.morph_p_y, config.morph_e_y, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_freq, start_time, peak_time, end_time, config.cut_s_x, config.cut_p_x, config.cut_e_x, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_res, start_time, peak_time, end_time, config.cut_s_y*0.98, config.cut_p_y*0.98, config.cut_e_y*0.98, inherit_shape, inherit_ta, inherit_tr)

        if settings.output_mode == 0 then
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, config.spc_s_x, config.spc_p_x, config.spc_e_x, inherit_shape, inherit_ta, inherit_tr)
            local function GetDblRev(y, x) return y * (1-x), y * x end
            local d_s, r_s = GetDblRev(config.spc_s_y, config.spc_s_x)
            local d_p, r_p = GetDblRev(config.spc_p_y, config.spc_p_x)
            local d_e, r_e = GetDblRev(config.spc_e_y, config.spc_e_x)
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, d_s, d_p, d_e, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.verb_mix, start_time, peak_time, end_time, r_s, r_p, r_e, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.pan_x, start_time, peak_time, end_time, config.dop_s_x, config.dop_p_x, config.dop_e_x, nil, 0, 0)
            Create3PointRampFX(track, fx, IDX.sur_path_x, start_time, peak_time, end_time, 0.5, 0.5, 0.5)
            Create3PointRampFX(track, fx, IDX.sur_path_y, start_time, peak_time, end_time, 0.0, 0.0, 0.0)
        else
            local d_s, r_s = config.spc_s_y * (1-config.spc_s_x), config.spc_s_y * config.spc_s_x
            local d_p, r_p = config.spc_p_y * (1-config.spc_p_x), config.spc_p_y * config.spc_p_x
            local d_e, r_e = config.spc_e_y * (1-config.spc_e_x), config.spc_e_y * config.spc_e_x
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, config.spc_s_x, config.spc_p_x, config.spc_e_x, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, d_s, d_p, d_e, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.verb_mix, start_time, peak_time, end_time, r_s, r_p, r_e, inherit_shape, inherit_ta, inherit_tr)

            local sx, sy, px, py, ex, ey = BuildSurroundPathPoints(config)
            Create3PointRampFX(track, fx, IDX.pan_x, start_time, peak_time, end_time, sx, px, ex, nil, 0, 0)
            Create3PointRampFX(track, fx, IDX.pan_y, start_time, peak_time, end_time, sy, py, ey, nil, 0, 0)
            
            -- Sur.Path ніколи не наслідує форму, завжди linear для точної панорами
            Create3PointRampFX(track, fx, IDX.sur_path_x, start_time, peak_time, end_time, sx, px, ex, nil, 0, 0)
            Create3PointRampFX(track, fx, IDX.sur_path_y, start_time, peak_time, end_time, sy, py, ey, nil, 0, 0)
        end
        
        local ch_s_y = config.chop_enable and config.chop_s_y or 0
        local ch_p_y = config.chop_enable and config.chop_p_y or 0
        local ch_e_y = config.chop_enable and config.chop_e_y or 0
        Create3PointRampFX(track, fx, IDX.chop_rate, start_time, peak_time, end_time, config.chop_s_x, config.chop_p_x, config.chop_e_x, inherit_shape, inherit_ta, inherit_tr)
        Create3PointRampFX(track, fx, IDX.chop_depth, start_time, peak_time, end_time, ch_s_y, ch_p_y, ch_e_y, inherit_shape, inherit_ta, inherit_tr)

        if config.link_bindings then
            for i, bd in ipairs(config.link_bindings) do
                if bd.enabled and bd.fx_name ~= "" and bd.param_name ~= "" then
                    local fx_idx = -1
                    local cnt = r.TrackFX_GetCount(track)
                    for f=0, cnt-1 do local _, nm = r.TrackFX_GetFXName(track, f) if nm == bd.fx_name then fx_idx = f; break end end
                    
                    if fx_idx >= 0 then
                        local p_idx = -1
                        local p_cnt = r.TrackFX_GetNumParams(track, fx_idx)
                        for p=0, p_cnt-1 do local _, pnm = r.TrackFX_GetParamName(track, fx_idx, p) if pnm == bd.param_name then p_idx = p; break end end
                        
                        if p_idx >= 0 then
                            local s, p, e
                            if bd.axis == 0 then s, p, e = config.link_s_x, config.link_p_x, config.link_e_x
                            else s, p, e = config.link_s_y, config.link_p_y, config.link_e_y end
                            if bd.invert then s=1-s; p=1-p; e=1-e end
                            local mn = bd.min or 0.0; local mx = bd.max or 1.0; local range = mx - mn
                            s = mn + s * range; p = mn + p * range; e = mn + e * range
                            Create3PointRampFX(track, fx_idx, p_idx, start_time, peak_time, end_time, s, p, e, inherit_shape, inherit_ta, inherit_tr)
                        end
                    end
                end
            end
        end

        if IDX.global_pitch >= 0 then
            if config.pitch_mode == 3 then
                -- Physics Doppler використовує спеціальні 5-точкові криві, не успадковує форму
                local max_rng = 24 
                local range = 6 + (config.dop_p_y * 30)
                local p_start = range; local p_end = -range
                Create5PointRampFX(track, fx, IDX.audio_pitch, start_time, peak_time, end_time, p_start, 0.0, p_end, 0.6)
                r.TrackFX_SetParam(track, fx, IDX.audio_pitch, 0.0) 
            elseif config.pitch_mode == 2 then
                local ap_s = ToAudioPitch(config.dop_s_y)
                local ap_p = ToAudioPitch(config.dop_p_y)
                local ap_e = ToAudioPitch(config.dop_e_y)
                Create3PointRampFX(track, fx, IDX.audio_pitch, start_time, peak_time, end_time, ap_s, ap_p, ap_e, inherit_shape, inherit_ta, inherit_tr)
                r.TrackFX_SetParam(track, fx, IDX.audio_pitch, ap_p)
            else
                local p_s = ToPitch(config.dop_s_y)
                local p_p = ToPitch(config.dop_p_y)
                local p_e = ToPitch(config.dop_e_y)
                Create3PointRampFX(track, fx, IDX.global_pitch, start_time, peak_time, end_time, p_s, p_p, p_e, inherit_shape, inherit_ta, inherit_tr)
                r.TrackFX_SetParam(track, fx, IDX.global_pitch, p_p)
            end
        end
    end
    r.Undo_EndBlock("Update Whoosh", 4)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

-- =========================================================
-- UI DRAWING FUNCTIONS
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
    local peak_x_draw = Clamp(peak_x, p_x + 6, p_x + w - 6)
    local peak_x_vis = peak_x_draw
    local hit_w = 20
    r.ImGui_SetCursorScreenPos(ctx, peak_x_draw - hit_w * 0.5, p_y)
    r.ImGui_InvisibleButton(ctx, "##peak_drag", hit_w, draw_h)
    if r.ImGui_IsItemActive(ctx) then
        interaction.dragging_peak = true
        local dx = r.ImGui_GetMouseDelta(ctx)
        local min_peak = (settings.env_shape == 1) and 0.0 or 0.1
        local max_peak = (settings.env_shape == 1) and 1.0 or 0.9
        config.peak_pos = Clamp(config.peak_pos + (dx/w), min_peak, max_peak); changed = true
        peak_x = p_x + (w * config.peak_pos)
        peak_x_draw = Clamp(peak_x, p_x + 6, p_x + w - 6)
        peak_x_vis = peak_x_draw
    else
        interaction.dragging_peak = false
    end
    r.ImGui_DrawList_AddLine(draw_list, peak_x_vis, p_y+5, peak_x_vis, p_y+draw_h-5, 0xFFFFFF30)
    r.ImGui_DrawList_AddCircle(draw_list, p_x+10, start_y, 6, C_GREY, 0, 2)
    r.ImGui_DrawList_AddRectFilled(draw_list, peak_x_vis-6, peak_y-8, peak_x_vis+6, peak_y+4, 0xFFFFFFFF)
    local arrow_size = 7
    local dx = (end_x-10) - peak_x_vis; local dy = end_y - peak_y
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 0.1 then
        dx = dx / len; dy = dy / len
        local perp_x, perp_y = -dy, dx
        local tip_x, tip_y = end_x-10, end_y
        local base_x, base_y = (end_x-10) - dx * arrow_size, end_y - dy * arrow_size
        local left_x, left_y = base_x - perp_x * (arrow_size * 0.7), base_y - perp_y * (arrow_size * 0.7)
        local right_x, right_y = base_x + perp_x * (arrow_size * 0.7), base_y + perp_y * (arrow_size * 0.7)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, tip_x, tip_y, left_x, left_y, right_x, right_y, col_acc)
    else r.ImGui_DrawList_AddCircleFilled(draw_list, end_x-10, end_y, 6, col_acc) end
    local rise_ta, rise_tr = 0, 0
    if settings.env_shape == 1 then
        local slope = config.rise_slope or 0; local tmag = slope * 0.6 
        if config.peak_pos > 0.5 then rise_ta = tmag; rise_tr = 0 else rise_ta = 0; rise_tr = -tmag end
    end
    if settings.env_shape == 0 then 
        local function GetCPs(t, x1, y1, x2, y2) local mx, my = (x1+x2)*0.5, (y1+y2)*0.5; local str = math.abs(t) * 100; if t > 0 then return mx, my - str else return mx, my + str end end
        local c1x, c1y = GetCPs(-config.tens_attack, p_x, start_y, peak_x_vis, peak_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, c1x, c1y, c1x, c1y, peak_x_vis, peak_y, col_acc, 2, 20)
        local c2x, c2y = GetCPs(config.tens_release, peak_x_vis, peak_y, end_x, end_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x_vis, peak_y, c2x, c2y, c2x, c2y, end_x-10, end_y, col_acc, 2, 20)
    elseif settings.env_shape == 1 then 
        local function GetCPs(t, x1, y1, x2, y2) local mx, my = (x1+x2)*0.5, (y1+y2)*0.5; local str = math.abs(t) * 100; if t > 0 then return mx, my - str else return mx, my + str end end
        if config.peak_pos > 0.5 then
            local c1x, c1y = GetCPs(-rise_ta, p_x, start_y, peak_x_vis, peak_y)
            r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, c1x, c1y, c1x, c1y, peak_x_vis, peak_y, col_acc, 2, 20)
            r.ImGui_DrawList_AddLine(draw_list, peak_x_vis, peak_y, end_x-10, end_y, col_acc, 2)
        else
            r.ImGui_DrawList_AddLine(draw_list, p_x+10, start_y, peak_x_vis, peak_y, col_acc, 2)
            local c2x, c2y = GetCPs(rise_tr, peak_x_vis, peak_y, end_x, end_y)
            r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x_vis, peak_y, c2x, c2y, c2x, c2y, end_x-10, end_y, col_acc, 2, 20)
        end
    elseif settings.env_shape == 2 then 
        local tension_scale = 0.4 
        local cp1_x = p_x+10 + (peak_x_vis - (p_x+10)) * tension_scale; local cp2_x = peak_x_vis - (peak_x_vis - (p_x+10)) * tension_scale
        local cp3_x = peak_x_vis + (end_x - peak_x_vis) * tension_scale; local cp4_x = end_x - (end_x - peak_x_vis) * tension_scale
        r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, cp1_x, start_y, cp2_x, peak_y, peak_x_vis, peak_y, col_acc, 2, 20)
        r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x_vis, peak_y, cp3_x, peak_y, cp4_x, end_y, end_x-10, end_y, col_acc, 2, 20)
    end
    if settings.env_shape == 0 then
        local slider_w = w * 0.35 * 0.7; local margin_side = 45; local margin_bot = 35; local y_pos = p_y + draw_h - margin_bot
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x444444FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col_acc)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 12); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 1); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 16) 
        r.ImGui_SetCursorScreenPos(ctx, p_x + margin_side, y_pos); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv1, v1 = r.ImGui_SliderDouble(ctx, "##Att", config.tens_attack, -1, 1, "Att: %.2f"); if rv1 then config.tens_attack=v1; changed=true end
        r.ImGui_SetCursorScreenPos(ctx, p_x + w - slider_w - margin_side, y_pos); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv2, v2 = r.ImGui_SliderDouble(ctx, "##Rel", config.tens_release, -1, 1, "Rel: %.2f"); if rv2 then config.tens_release=v2; changed=true end
        r.ImGui_PopStyleVar(ctx, 4); r.ImGui_PopStyleColor(ctx, 2)
    elseif settings.env_shape == 1 then
        local slider_w = w * 0.35 * 0.7; local margin_bot = 35; local y_pos = p_y + draw_h - margin_bot
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x444444FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col_acc)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 12); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 1); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 16) 
        r.ImGui_SetCursorScreenPos(ctx, p_x + (w - slider_w) * 0.5, y_pos); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv_r, v_r = r.ImGui_SliderDouble(ctx, "##RiseSlope", config.rise_slope or 0, 0, 1, "Rise Slope: %.2f"); if rv_r then config.rise_slope = v_r; changed=true end
        r.ImGui_PopStyleVar(ctx, 4); r.ImGui_PopStyleColor(ctx, 2)
    end
    return changed
end

function DrawVectorPad(label, p_idx, w, h, col_acc, col_bg)
    if p_idx == 4 then w = PAD_DRAW_H elseif p_idx == 6 then w = PAD_SQUARE else if not w or w <= 0 then w = 170 end end
    if not h or h <= 0 then h = 170 end
    r.ImGui_Dummy(ctx, w, h)
    local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local draw_h = PAD_DRAW_H
    col_acc = SafeCol(col_acc, 0x2D8C6DFF); col_bg = SafeCol(col_bg, 0x252525FF)
    local changed = false
    r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + w, p_y + draw_h, C_FRAME_BG, 4)
    r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + w, p_y + draw_h, 0xFFFFFF30, 4)
    if p_idx ~= 6 then
        r.ImGui_DrawList_AddLine(draw_list, p_x + w*0.5, p_y, p_x + w*0.5, p_y + draw_h, 0xFFFFFF30, 1.5)
        r.ImGui_DrawList_AddLine(draw_list, p_x, p_y + draw_h*0.5, p_x + w, p_y + draw_h*0.5, 0xFFFFFF30, 1.5)
    end
    local txt_col = 0xFFFFFF60; local t1,t2,t3,t4="","","",""
    if p_idx == 4 then 
        if settings.output_mode == 0 then t1="L"; t2="R"; t3="Pitch-"; t4="Pitch+" else t1=""; t2=""; t3="Pitch-"; t4="Pitch+" end
    elseif p_idx == 6 then t1="Slow"; t2="Fast"; t3="No gate"; t4="Deep gate"
    elseif p_idx == 5 then 
        t1="Dbl"; t2="Rev"; t3="Mono"; t4="Wide"
    elseif p_idx == 1 then t1="Noise";t2="Osc";t3="Chua";t4="Ext"
    elseif p_idx == 2 then t1="HP";t2="BR";t3="LP";t4="BP"
    elseif p_idx == 3 then t1="Res";t4="Cut" end
    if t1~="" or t2~="" or t3~="" or t4~="" then
        local function DT(tx, x, y) r.ImGui_DrawList_AddText(draw_list, x, y, txt_col, tx) end
        if p_idx == 4 then
            local tw1, th1 = r.ImGui_CalcTextSize(ctx, t1); local tw2, th2 = r.ImGui_CalcTextSize(ctx, t2); local tw3, th3 = r.ImGui_CalcTextSize(ctx, t3); local tw4, th4 = r.ImGui_CalcTextSize(ctx, t4)
            local mid_x = p_x + (w * 0.5); local mid_y = p_y + (draw_h * 0.5)
            if t3 ~= "" then DT(t3, mid_x - (tw3 * 0.5), p_y + 5) end
            if t4 ~= "" then DT(t4, mid_x - (tw4 * 0.5), p_y + draw_h - th4 - 5) end
            if settings.output_mode == 0 then
                if t1 ~= "" then DT(t1, p_x + 5, mid_y - (th1 * 0.5)) end
                if t2 ~= "" then DT(t2, p_x + w - tw2 - 5, mid_y - (th2 * 0.5)) end
            end
        elseif p_idx == 5 or p_idx == 6 then
            local tw1, th1 = r.ImGui_CalcTextSize(ctx, t1); local tw2, th2 = r.ImGui_CalcTextSize(ctx, t2); local tw3, th3 = r.ImGui_CalcTextSize(ctx, t3); local tw4, th4 = r.ImGui_CalcTextSize(ctx, t4)
            DT(t1, p_x + 5, p_y + 5); DT(t2, p_x + w - tw2 - 5, p_y + 5); DT(t3, p_x + 5, p_y + draw_h - th3 - 5); DT(t4, p_x + w - tw4 - 5, p_y + draw_h - th4 - 5)
        else
            DT(t1, p_x+5, p_y+5); DT(t2, p_x+w-25, p_y+5); DT(t3, p_x+5, p_y+draw_h-18); DT(t4, p_x+w-25, p_y+draw_h-18)
        end
    end
    local hit_margin = 8
    r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
    r.ImGui_InvisibleButton(ctx, label, w + hit_margin*2, draw_h + hit_margin*2)
    local is_clicked = r.ImGui_IsItemClicked(ctx); local is_active = r.ImGui_IsItemActive(ctx)
    local sx, sy, px, py, ex, ey
    if p_idx==1 then sx = config.src_s_x; sy = config.src_s_y; px=config.src_p_x; py=config.src_p_y; ex=config.src_e_x; ey=config.src_e_y
    elseif p_idx==2 then sx = config.morph_s_x; sy = config.morph_s_y; px=config.morph_p_x; py=config.morph_p_y; ex=config.morph_e_x; ey=config.morph_e_y
    elseif p_idx==3 then sx = config.cut_s_x; sy = config.cut_s_y; px=config.cut_p_x; py=config.cut_p_y; ex=config.cut_e_x; ey=config.cut_e_y
    elseif p_idx==4 then sx = config.dop_s_x; sy = config.dop_s_y; px=config.dop_p_x; py=config.dop_p_y; ex=config.dop_e_x; ey=config.dop_e_y
    elseif p_idx==5 then sx = config.spc_s_x; sy = config.spc_s_y; px=config.spc_p_x; py=config.spc_p_y; ex=config.spc_e_x; ey=config.spc_e_y 
    elseif p_idx==6 then sx = config.chop_s_x; sy = config.chop_s_y; px=config.chop_p_x; py=config.chop_p_y; ex=config.chop_e_x; ey=config.chop_e_y 
    elseif p_idx==7 then sx = config.link_s_x; sy = config.link_s_y; px=config.link_p_x; py=config.link_p_y; ex=config.link_e_x; ey=config.link_e_y end
    if is_clicked then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*h; local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*h; local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*h
        local hit_r = 1000 
        interaction.dragging_pad = p_idx
        local dist_s = (mx-s_sc_x)^2+(my-s_sc_y)^2; local dist_p = (mx-p_sc_x)^2+(my-p_sc_y)^2; local dist_e = (mx-e_sc_x)^2+(my-e_sc_y)^2
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
            elseif p_idx==6 then config.chop_s_x,config.chop_s_y,config.chop_p_x,config.chop_p_y,config.chop_e_x,config.chop_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==7 then config.link_s_x,config.link_s_y,config.link_p_x,config.link_p_y,config.link_e_x,config.link_e_y = sx,sy,px,py,ex,ey end
        end
    end
    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*h; local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*h; local e_x, e_y = p_x + ex*w, p_y + (1-ey)*h
    r.ImGui_DrawList_AddLine(draw_list, s_x, s_y, p_x_d, p_y_d, col_acc, 1); r.ImGui_DrawList_AddLine(draw_list, p_x_d, p_y_d, e_x, e_y, col_acc, 1)
    r.ImGui_DrawList_PushClipRect(draw_list, p_x, p_y, p_x + w, p_y + draw_h, true)
    local center_x = p_x + w * 0.5; local center_y = p_y + draw_h * 0.5; local max_r = math.sqrt((w*0.5)^2 + (draw_h*0.5)^2)
    if p_idx == 4 then
        local function add_square(scale, col) local half = max_r * scale; r.ImGui_DrawList_AddRect(draw_list, center_x - half, center_y - half, center_x + half, center_y + half, col, 0, 0, 1) end
        add_square(0.75, 0xFFFFFF15); add_square(0.50, 0xFFFFFF20); add_square(0.35, 0xFFFFFF2A)
    elseif p_idx == 6 then
        local x = p_x + 8; local gap = w * 0.22; local decay = 0.72; local min_gap = w * 0.028
        for _ = 1, 32 do if x > p_x + w - 8 then break end; r.ImGui_DrawList_AddLine(draw_list, x, p_y + 6, x, p_y + draw_h - 6, 0xFFFFFF20, 1); gap = math.max(min_gap, gap * decay); x = x + gap end
    else
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.75, 0xFFFFFF15, 0, 1)
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.50, 0xFFFFFF20, 0, 1)
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.35, 0xFFFFFF2A, 0, 1)
    end
    r.ImGui_DrawList_PopClipRect(draw_list)
    r.ImGui_DrawList_AddCircle(draw_list, s_x, s_y, 5, 0xAAAAAAFF, 0, 2); r.ImGui_DrawList_AddRectFilled(draw_list, p_x_d-4, p_y_d-4, p_x_d+4, p_y_d+4, 0xFFFFFFFF)
    local arrow_size = 7
    local dx = e_x - p_x_d; local dy = e_y - p_y_d; local len = math.sqrt(dx*dx + dy*dy)
    if len > 0.1 then
        dx = dx / len; dy = dy / len
        local perp_x, perp_y = -dy, dx; local tip_x, tip_y = e_x, e_y
        local base_x, base_y = e_x - dx * arrow_size, e_y - dy * arrow_size
        local left_x, left_y = base_x - perp_x * (arrow_size * 0.7), base_y - perp_y * (arrow_size * 0.7)
        local right_x, right_y = base_x + perp_x * (arrow_size * 0.7), base_y + perp_y * (arrow_size * 0.7)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, tip_x, tip_y, left_x, left_y, right_x, right_y, col_acc)
    else r.ImGui_DrawList_AddCircleFilled(draw_list, e_x, e_y, 6, col_acc) end
    return changed
end

function BounceToNewTrack()
    r.PreventUIRefresh(1); r.Undo_BeginBlock()
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local has_ts = ts_end > ts_start
    local whoosh_track = FindTrackByName(settings.track_name)
    if not whoosh_track then r.ShowMessageBox("Track '" .. settings.track_name .. "' not found.", "Error", 0); r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce failed", -1); return end
    local items_to_mute = {}
    local render_start, render_end
    local tail_duration = config.bounce_tail or 0.5
    -- Перевірка існуючого Bounce-рендеру у таймселекшені
    local stem_name = (settings.output_mode == 1) and "ReaWhoosh Renders (Surround)" or "ReaWhoosh Renders"
    local stem_track = FindTrackByName(stem_name)
    local found_existing = false
    if has_ts and stem_track then
      local item_count = r.CountTrackMediaItems(stem_track)
      for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(stem_track, i)
        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if math.abs(item_pos - ts_start) < 0.01 and math.abs((item_pos + item_len) - ts_end) < 0.01 then
          found_existing = true
          break
        end
      end
    end
    if found_existing then
            local res = r.ShowMessageBox("Bounce file already exists in this time selection.\n\nRender to a new track (index +1)?\n\n(Press 'Yes' to render to a new track, 'No' to cancel)", "Warning", 4)
            if res == 6 then -- Yes
                -- Add new track after stem_track
                local idx = -1
                for i = 0, r.CountTracks(0)-1 do
                    if r.GetTrack(0, i) == stem_track then idx = i; break end
                end
                if idx ~= -1 then
                    r.InsertTrackAtIndex(idx+1, true)
                    local new_stem_track = r.GetTrack(0, idx+1)
                    if not new_stem_track or not r.ValidatePtr(new_stem_track, "MediaTrack*") then
                        r.ShowConsoleMsg("[Bounce] Error: Failed to create destination stem track.\n")
                        r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce cancelled", -1); return
                    end
                    -- Find next available suffix for naming
                    local suffix = 1
                    local new_name = stem_name .. "_" .. suffix
                    local name_exists = true
                    while name_exists do
                        name_exists = false
                        for i = 0, r.CountTracks(0)-1 do
                            local tr = r.GetTrack(0, i)
                            local retval, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                            if tr_name == new_name then name_exists = true; break end
                        end
                        if name_exists then suffix = suffix + 1; new_name = stem_name .. "_" .. suffix end
                    end
                    r.GetSetMediaTrackInfo_String(new_stem_track, "P_NAME", new_name, true)
                    stem_track = new_stem_track
                else
                    r.ShowConsoleMsg("[Bounce] Error: Could not find stem track index.\n")
                    r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce cancelled", -1); return
                end
            else
                r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce cancelled", -1); return
            end
    end
    for i = 0, r.CountMediaItems(0) - 1 do
        local item = r.GetMediaItem(0, i)
        if r.IsMediaItemSelected(item) and r.GetMediaItem_Track(item) == whoosh_track then table.insert(items_to_mute, item) end
    end
    if #items_to_mute > 0 then
        render_start = math.huge; render_end = -math.huge
        for _, item in ipairs(items_to_mute) do
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            render_start = math.min(render_start, item_pos); render_end = math.max(render_end, item_pos + item_len)
        end
        render_end = render_end + tail_duration
    elseif has_ts then
        render_start, render_end = ts_start, ts_end + tail_duration
        local item_count = r.CountTrackMediaItems(whoosh_track)
        for i = 0, item_count - 1 do
            local item = r.GetTrackMediaItem(whoosh_track, i)
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
            if item_pos < ts_end and item_end > ts_start then table.insert(items_to_mute, item) end
        end
    else
        r.ShowMessageBox("Select an item or time selection to bounce.", "Error", 0); r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce failed", -1); return
    end
    if #items_to_mute == 0 then r.ShowMessageBox("No items to bounce.", "Error", 0); r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce failed", -1); return end
    local desired_ch = (settings.output_mode == 1) and 6 or 2

    if not stem_track or not r.ValidatePtr(stem_track, "MediaTrack*") then
        local insert_idx = r.CountTracks(0)
        r.InsertTrackAtIndex(insert_idx, true)
        stem_track = r.GetTrack(0, insert_idx)
        if not stem_track or not r.ValidatePtr(stem_track, "MediaTrack*") then
            r.ShowConsoleMsg("[Bounce] Error: Destination stem track is invalid.\n")
            r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce failed", -1); return
        end
        r.GetSetMediaTrackInfo_String(stem_track, "P_NAME", stem_name, true)
    end

    r.SetMediaTrackInfo_Value(stem_track, "I_NCHAN", desired_ch)

    local track_channels = r.GetMediaTrackInfo_Value(whoosh_track, "I_NCHAN")
    if track_channels ~= desired_ch then r.SetMediaTrackInfo_Value(whoosh_track, "I_NCHAN", desired_ch) end
    r.GetSet_LoopTimeRange(true, false, render_start, render_end, false)
    r.SetOnlyTrackSelected(whoosh_track)
    r.UpdateArrange()
    local existing_tracks = {}
    for i = 0, r.CountTracks(0) - 1 do existing_tracks[r.GetTrack(0, i)] = true end
    local render_cmd = (settings.output_mode == 1) and 41720 or 41719
    r.Main_OnCommand(render_cmd, 0)
    local new_tracks = {}
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        if not existing_tracks[tr] and tr ~= stem_track then table.insert(new_tracks, tr) end
    end
    if not stem_track or not r.ValidatePtr(stem_track, "MediaTrack*") then
        r.ShowConsoleMsg("[Bounce] Error: Destination track lost before item move.\n")
        r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce failed", -1); return
    end

    for _, tr in ipairs(new_tracks) do
        local item_cnt = r.CountTrackMediaItems(tr)
        for i = item_cnt-1, 0, -1 do local it = r.GetTrackMediaItem(tr, i); r.MoveMediaItemToTrack(it, stem_track) end
    end
    for i = #new_tracks, 1, -1 do r.DeleteTrack(new_tracks[i]) end
    r.SetMediaTrackInfo_Value(whoosh_track, "B_MUTE", 0); r.SetMediaTrackInfo_Value(stem_track, "B_MUTE", 0)
    for _, item in ipairs(items_to_mute) do r.SetMediaItemInfo_Value(item, "B_MUTE", 1) end
    r.SetOnlyTrackSelected(stem_track)
    r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce item to stem track", 0)
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
    local fx = GetOrAddFX(track, FX_NAME)
        local item = r.CreateNewMIDIItemInProj(track, start_time, end_time, false)
        if not item then
            r.ShowConsoleMsg("ReaWhoosh error: CreateNewMIDIItemInProj returned nil. Check time selection and track state.\n")
            r.PreventUIRefresh(-1)
            return
        end
        r.SetMediaItemSelected(item, true)
    local take = r.GetActiveTake(item)
    if take then
        local len = r.MIDI_GetPPQPosFromProjTime(take, end_time)
        r.MIDI_InsertNote(take, false, false, 0, len, 0, 60, 100, false)
    end
    UpdateAutomationOnly("all")
    r.PreventUIRefresh(-1)
    ShowAllEnvelopes()
end

function Loop()
    local c_bg = SafeCol(settings.col_bg, 0x252525FF)
    local c_acc = SafeCol(settings.col_accent, 0x2D8C6DFF)
    local c_btn = 0x202020FF; local c_btn_hov = LightenColor(c_btn, 1.12)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1AFF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), 0x202020FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), 0x202020FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_btn); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c_btn_hov)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c_acc); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE0E0E0FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), c_acc); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), c_acc)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000060); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x00000080)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x00000080); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), c_acc)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 8); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12) 
    r.ImGui_SetNextWindowSizeConstraints(ctx, 1200, 500, 1200, 900)
    
        local visible, open = r.ImGui_Begin(ctx, 'ReaWhoosh', true)
        -- Обработка пробела для Play/Stop
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space()) then
            r.OnPlayButton()
        end
        if visible then
        local changed_any = false; local changed_pads = false 
        
        r.ImGui_Text(ctx, "PRESETS:"); r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 200)
        if r.ImGui_BeginCombo(ctx, "##presets", config.current_preset) then
            if not USER_PRESETS then LoadUserPresets() end
            r.ImGui_TextDisabled(ctx, "-- Factory --")
            for name, _ in pairs(FACTORY_PRESETS) do if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any=true end end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- User --")
            for name, _ in pairs(USER_PRESETS) do if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any=true end end
            r.ImGui_EndCombo(ctx) 
        end
        r.ImGui_SameLine(ctx); local add_c = 0x2D8C6DFF; r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), add_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(add_c))
        if r.ImGui_Button(ctx, "+", 24, 0) then SHOW_SAVE_MODAL = true; PRESET_INPUT_BUF = "My Preset"; DO_FOCUS_INPUT = true end
        r.ImGui_PopStyleColor(ctx, 2); r.ImGui_SameLine(ctx); local del_c = 0xCC4444FF; r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), del_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(del_c))
        if r.ImGui_Button(ctx, "-", 24, 0) then if USER_PRESETS[config.current_preset] then DeleteUserPreset(config.current_preset); changed_any = true end end
        r.ImGui_PopStyleColor(ctx, 2)
        
        -- Output Mode (зліва біля пресетів)
        r.ImGui_SameLine(ctx); r.ImGui_Dummy(ctx, 10, 0); r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "Mode:"); r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Stereo", settings.output_mode==0) then
            settings.output_mode=0; changed_any=true; SaveSettings()
            if settings.sur_win_open then settings.sur_win_open = false end
            ClearPanAutomations(true)  -- Видалити Surround automations
        end
        r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "Surround##ModeRadio", settings.output_mode==1) then
            settings.output_mode=1; changed_any=true; SaveSettings()
            ClearPanAutomations(false)  -- Видалити Stereo automations
        end
        
        -- Surround Window button (зліва, помаранчева, disabled в Stereo mode)
        r.ImGui_SameLine(ctx); r.ImGui_Dummy(ctx, 10, 0); r.ImGui_SameLine(ctx)
        if settings.output_mode == 0 then
            r.ImGui_BeginDisabled(ctx, true)
        end
        local sur_btn_col = settings.sur_win_open and DarkenColor(C_ORANGE) or C_ORANGE
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), sur_btn_col); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(C_ORANGE))
        if r.ImGui_Button(ctx, "SurroundPan##WindowBtn", 85) then settings.sur_win_open = not settings.sur_win_open end
        r.ImGui_PopStyleColor(ctx, 2)
        if settings.output_mode == 0 then
            r.ImGui_EndDisabled(ctx)
        end
        
        -- Spacing до Options справа (з відступом від краю)
        r.ImGui_SameLine(ctx); local avail_w = r.ImGui_GetContentRegionAvail(ctx); r.ImGui_Dummy(ctx, avail_w - 90, 0)
        r.ImGui_SameLine(ctx); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_acc); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(c_acc))
        if r.ImGui_Button(ctx, "Options", 80) then r.ImGui_OpenPopup(ctx, "Settings") end
        r.ImGui_PopStyleColor(ctx, 2)
        
        if SHOW_SAVE_MODAL then r.ImGui_OpenPopup(ctx, "Save Preset") end
        if r.ImGui_BeginPopupModal(ctx, "Save Preset", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Preset Name:"); if DO_FOCUS_INPUT then r.ImGui_SetKeyboardFocusHere(ctx); DO_FOCUS_INPUT = false end
            local ret, str = r.ImGui_InputText(ctx, "##pname", PRESET_INPUT_BUF); if ret then PRESET_INPUT_BUF = str end
            if r.ImGui_Button(ctx, "SAVE", 100, 0) then SaveUserPreset(PRESET_INPUT_BUF); SHOW_SAVE_MODAL = false; r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "CANCEL", 100, 0) then SHOW_SAVE_MODAL = false; r.ImGui_CloseCurrentPopup(ctx) end
            r.ImGui_EndPopup(ctx)
        end

                if r.ImGui_BeginPopupModal(ctx, "Settings", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
                    r.ImGui_TextDisabled(ctx, "-- Track Name --")
                    local rv, txt = r.ImGui_InputText(ctx, "##trname", settings.track_name); if rv then settings.track_name = txt; SaveSettings() end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Peak Behavior --")
                    if r.ImGui_RadioButton(ctx, "Manual (Slider)", settings.peak_mode==0) then settings.peak_mode=0 end
                    r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "Follow Edit Cursor", settings.peak_mode==1) then settings.peak_mode=1 end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Envelope Settings --")
                      local _, inh = r.ImGui_Checkbox(ctx, "All envelopes inherit Volume Shape", settings.env_inherit_shape); if _ then settings.env_inherit_shape = inh; SaveSettings() end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Chopper Settings --")
                    local rv_s, v_s = r.ImGui_SliderDouble(ctx, "Chopper Shape", config.chop_shape, 0, 1, "Hard -> Soft"); if rv_s then config.chop_shape = v_s; changed_any=true end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Randomization Targets --")
                    local _, b1 = r.ImGui_Checkbox(ctx, "Source Mix", settings.rand_src); if _ then settings.rand_src=b1 end
                    r.ImGui_SameLine(ctx); local _, b2 = r.ImGui_Checkbox(ctx, "Morph Filter", settings.rand_morph); if _ then settings.rand_morph=b2 end
                    r.ImGui_SameLine(ctx); local _, b3 = r.ImGui_Checkbox(ctx, "Cut/Res", settings.rand_filt); if _ then settings.rand_filt=b3 end
                    local _, b4 = r.ImGui_Checkbox(ctx, "Doppler", settings.rand_dop); if _ then settings.rand_dop=b4 end
                    r.ImGui_SameLine(ctx); local _, b5 = r.ImGui_Checkbox(ctx, "Space (FX)", settings.rand_space); if _ then settings.rand_space=b5 end
                    r.ImGui_SameLine(ctx); local _, b6 = r.ImGui_Checkbox(ctx, "Chopper", settings.rand_chop); if _ then settings.rand_chop=b6 end
                    local _, b7 = r.ImGui_Checkbox(ctx, "Volume Env", settings.rand_env); if _ then settings.rand_env=b7 end
                    r.ImGui_SameLine(ctx); local _, b8 = r.ImGui_Checkbox(ctx, "Surround Path", settings.rand_surround); if _ then settings.rand_surround=b8 end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Bounce Settings --")
                    local rv_tail, v_tail = r.ImGui_SliderDouble(ctx, "Bounce Tail (seconds)", config.bounce_tail or 0.5, 0.0, 3.0, "%.2f"); if rv_tail then config.bounce_tail = v_tail; changed_any = true end
                    if r.ImGui_Button(ctx, "Close") then SaveSettings(); r.ImGui_CloseCurrentPopup(ctx) end
                    r.ImGui_EndPopup(ctx)
                end

        local sur_changed, sur_path_changed = DrawSurroundWindow(ctx, r, settings, config, c_acc)
        if sur_changed then
            changed_any = true
            if sur_path_changed then surround_env_dirty = true end
        end

        r.ImGui_Separator(ctx)

        if r.ImGui_BeginTable(ctx, "MainTable", 2, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "PadGrid", r.ImGui_TableColumnFlags_WidthStretch(), 1.2)
            r.ImGui_TableSetupColumn(ctx, "EnvMix", r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
            r.ImGui_TableNextColumn(ctx); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 4)
            if r.ImGui_BeginTable(ctx, "PadsGrid3x3", 3, r.ImGui_TableFlags_SizingStretchProp()) then
                local function PadCell(title, id, pad_idx)
                    r.ImGui_Text(ctx, title); if DrawVectorPad(id, pad_idx, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true; changed_pads=true end
                end
                r.ImGui_TableNextColumn(ctx); PadCell("Source Mix", "##src", 1); r.ImGui_TableNextColumn(ctx); PadCell("Morph Filter", "##morph", 2)
                r.ImGui_TableNextColumn(ctx); PadCell("Doppler Pad", "##doppler", 4); r.ImGui_TableNextColumn(ctx); PadCell("Space Pad", "##space", 5)
                r.ImGui_TableNextColumn(ctx); PadCell("Cut / Res", "##cut", 3); r.ImGui_TableNextColumn(ctx); PadCell("Chopper", "##granular", 6)
                r.ImGui_EndTable(ctx)
            end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_TableNextColumn(ctx); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0); local right_w = r.ImGui_GetContentRegionAvail(ctx)
            if r.ImGui_BeginChild(ctx, "EnvBlock", 0, PAD_SQUARE + 24, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_Text(ctx, " Volume Envelope"); if DrawEnvelopePreview(right_w, PAD_SQUARE - 20, c_acc) then changed_any=true; changed_pads=true end
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_Dummy(ctx, 0, 6); local mm_h = math.max(PAD_SQUARE, MIX_H + 70) 
            if r.ImGui_BeginChild(ctx, "MeterMixBlock", 0, mm_h, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 0)
                if r.ImGui_BeginTable(ctx, "StereoMixerRow", 2, r.ImGui_TableFlags_SizingStretchProp()) then
                    r.ImGui_TableSetupColumn(ctx, "StereoCol", r.ImGui_TableColumnFlags_WidthStretch())
                    r.ImGui_TableSetupColumn(ctx, "MixerCol", r.ImGui_TableColumnFlags_WidthStretch())
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Link ext. parameters")
                    if DrawVectorPad("##link", 7, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true; changed_pads=true end
                    
                    if r.ImGui_BeginPopupContextItem(ctx, "##link_ctx") then
                        r.ImGui_TextDisabled(ctx, "Link Configuration (Up to 4)"); r.ImGui_Separator(ctx)
                        local track = FindTrackByName(settings.track_name)
                        if track then
                            if not config.link_bindings then config.link_bindings = {} end
                            for i=1,4 do
                                if not config.link_bindings[i] then config.link_bindings[i] = {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0} end
                                local bd = config.link_bindings[i]; if bd.min == nil then bd.min = 0.0 end; if bd.max == nil then bd.max = 1.0 end
                                r.ImGui_PushID(ctx, "lnk"..i)
                                local _, b = r.ImGui_Checkbox(ctx, "##en", bd.enabled); if _ then bd.enabled=b; changed_any=true end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 100)
                                if r.ImGui_BeginCombo(ctx, "##fx", bd.fx_name~="" and bd.fx_name or "FX..") then
                                    local cnt = r.TrackFX_GetCount(track)
                                    for f=0, cnt-1 do local _, nm = r.TrackFX_GetFXName(track, f); if r.ImGui_Selectable(ctx, nm, bd.fx_name==nm) then bd.fx_name=nm; bd.param_name=""; changed_any=true end end
                                    r.ImGui_EndCombo(ctx)
                                end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 100)
                                if r.ImGui_BeginCombo(ctx, "##par", bd.param_name~="" and bd.param_name or "Param..") then
                                    local fx_idx = -1; local cnt = r.TrackFX_GetCount(track)
                                    for f=0, cnt-1 do local _, nm = r.TrackFX_GetFXName(track, f) if nm == bd.fx_name then fx_idx=f; break end end
                                    if fx_idx >= 0 then
                                        local p_cnt = r.TrackFX_GetNumParams(track, fx_idx)
                                        for p=0, p_cnt-1 do local _, pnm = r.TrackFX_GetParamName(track, fx_idx, p); if r.ImGui_Selectable(ctx, pnm, bd.param_name==pnm) then bd.param_name=pnm; changed_any=true end end
                                    else r.ImGui_TextDisabled(ctx, "FX not found") end
                                    r.ImGui_EndCombo(ctx)
                                end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 40)
                                if r.ImGui_BeginCombo(ctx, "##ax", bd.axis==0 and "X" or "Y") then
                                    if r.ImGui_Selectable(ctx, "X", bd.axis==0) then bd.axis=0; changed_any=true end; if r.ImGui_Selectable(ctx, "Y", bd.axis==1) then bd.axis=1; changed_any=true end; r.ImGui_EndCombo(ctx)
                                end
                                r.ImGui_SameLine(ctx); local _, inv = r.ImGui_Checkbox(ctx, "Inv", bd.invert); if _ then bd.invert=inv; changed_any=true end
                                r.ImGui_SameLine(ctx); r.ImGui_TextDisabled(ctx, "|"); r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
                                local rv_min, v_min = r.ImGui_DragDouble(ctx, "##min", bd.min, 0.01, 0, 1, "Min=%.2f"); if rv_min then bd.min = v_min; if bd.min > bd.max then bd.min=bd.max end; changed_any=true end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
                                local rv_max, v_max = r.ImGui_DragDouble(ctx, "##max", bd.max, 0.01, 0, 1, "Max=%.2f"); if rv_max then bd.max = v_max; if bd.max < bd.min then bd.max=bd.min end; changed_any=true end
                                r.ImGui_PopID(ctx)
                            end
                        else r.ImGui_TextDisabled(ctx, "Track not found") end
                        r.ImGui_EndPopup(ctx)
                    end

                    r.ImGui_TableNextColumn(ctx)
                    local s_w, s_m, s_b = 16, 7, 24 
                    local function DrawStrip(lbl, val, state_bool, meter_idx, is_sub)
                        r.ImGui_BeginGroup(ctx)
                        local w = r.ImGui_CalcTextSize(ctx, lbl); local center_pos = r.ImGui_GetCursorPosX(ctx) + (s_b - w) / 2
                        r.ImGui_SetCursorPosX(ctx, center_pos); r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, lbl)
                        r.ImGui_PushID(ctx, lbl); r.ImGui_SetNextItemWidth(ctx, s_w)
                        local rv, v = r.ImGui_VSliderDouble(ctx, "##v", s_w, MIX_H, val, 0, 1.35, "")
                        if rv then val=v; changed_any=true end
                        r.ImGui_PopID(ctx); r.ImGui_SameLine(ctx, 0, 2)
                        local m_val = tonumber(r.gmem_read(meter_idx)) or 0; local m_norm = math.min(m_val * 0.75, 1.0)
                        r.ImGui_Dummy(ctx, s_m, MIX_H); local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx); local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx); local dlm = r.ImGui_GetWindowDrawList(ctx)
                        r.ImGui_DrawList_AddRectFilled(dlm, p_min_x, p_min_y, p_max_x, p_max_y, 0x111111FF)
                        local fill_h = (p_max_y - p_min_y) * m_norm; local col = 0x2D8C6DFF; if m_norm > 0.75 then col = 0xCC4444FF end
                        r.ImGui_DrawList_AddRectFilled(dlm, p_min_x, p_max_y - fill_h, p_max_x, p_max_y, col)
                        local db0_norm = 1.0 / 1.35; local marker_y = p_max_y - (p_max_y - p_min_y) * db0_norm; r.ImGui_DrawList_AddLine(dlm, p_min_x, marker_y, p_max_x, marker_y, 0xFFFFFF60, 1)
                        r.ImGui_Dummy(ctx, 0, 2); r.ImGui_PushID(ctx, "m_"..lbl)
                        if is_sub then
                            local is_on = state_bool; local b_col = is_on and 0x2D8C6DFF or 0x444444FF
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), b_col); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(b_col, 1.2))
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
                            if r.ImGui_Button(ctx, is_on and "ON" or "OFF", s_b, 18) then state_bool = not state_bool; changed_any=true end
                            r.ImGui_PopStyleVar(ctx); r.ImGui_PopStyleColor(ctx, 2)
                        else
                            local muted = state_bool; local m_col = muted and 0xCC4444FF or 0x444444FF; local m_hov = LightenColor(m_col, 1.2)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), m_col); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), m_hov)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
                            if r.ImGui_Button(ctx, "M", s_b, 18) then muted = not muted; changed_any=true end
                            r.ImGui_PopStyleVar(ctx); r.ImGui_PopStyleColor(ctx, 2); state_bool = muted
                        end
                        r.ImGui_PopID(ctx); r.ImGui_EndGroup(ctx); return val, state_bool
                    end
                    config.trim_w, config.mute_w = DrawStrip("Nois", config.trim_w, config.mute_w, 0, false); r.ImGui_SameLine(ctx, 0, 4)
                    config.trim_o, config.mute_o = DrawStrip("Osc", config.trim_o, config.mute_o, 1, false); r.ImGui_SameLine(ctx, 0, 4)
                    config.trim_c, config.mute_c = DrawStrip("Chua", config.trim_c, config.mute_c, 2, false); r.ImGui_SameLine(ctx, 0, 4)
                    config.trim_e, config.mute_e = DrawStrip("Ext", config.trim_e, config.mute_e, 3, false); r.ImGui_SameLine(ctx, 0, 4)
                    config.sub_vol, config.sub_enable = DrawStrip("Sub", config.sub_vol, config.sub_enable, 7, true)
                    r.ImGui_SameLine(ctx, 0, 8); r.ImGui_BeginGroup(ctx)
                    local mst_lbl = "Mst"; local s_w_mst, s_h_mst = 36, MIX_H + 20 
                    local w_m = r.ImGui_CalcTextSize(ctx, mst_lbl); local center_m = r.ImGui_GetCursorPosX(ctx) + (s_w_mst - w_m) / 2
                    r.ImGui_SetCursorPosX(ctx, center_m); r.ImGui_Text(ctx, mst_lbl)
                    r.ImGui_PushID(ctx, "Mst"); local is_surround = (settings.output_mode == 1); local ch_count = is_surround and 6 or 2
                    r.ImGui_InvisibleButton(ctx, "##mst_hit", s_w_mst, s_h_mst)
                    local hit_active = r.ImGui_IsItemActive(ctx); local hit_hover = r.ImGui_IsItemHovered(ctx)
                    local min_x, min_y = r.ImGui_GetItemRectMin(ctx); local max_x, max_y = r.ImGui_GetItemRectMax(ctx); local dlm = r.ImGui_GetWindowDrawList(ctx)
                    r.ImGui_DrawList_AddRectFilled(dlm, min_x, min_y, max_x, max_y, 0x111111FF, 4)
                    local h = max_y - min_y; local gap = 1; local bar_w = (s_w_mst - (ch_count + 1) * gap) / ch_count
                    local m_min_db, m_max_db = -60, 21
                    for i = 0, ch_count - 1 do
                        local m_val = tonumber(r.gmem_read(4 + i)) or 0; local db = 20 * math.log(math.max(m_val, 0.00001), 10); local m_norm = Clamp((db - m_min_db) / (m_max_db - m_min_db), 0, 1)
                        local x1 = min_x + gap + i * (bar_w + gap); local x2 = x1 + bar_w; local fill = h * m_norm
                        local col = m_norm > (1/1.35) and 0xCC4444FF or 0x2D8C6DFF
                        r.ImGui_DrawList_AddRectFilled(dlm, x1, max_y - fill, x2, max_y, col, 2, r.ImGui_DrawFlags_RoundCornersBottom())
                    end
                    local function GetDbNorm(db_val) return Clamp((db_val - m_min_db) / (m_max_db - m_min_db), 0, 1) end
                    local marker_positions = {{db = -60, label = ""}, {db = -48, label = ""}, {db = -36, label = ""}, {db = -24, label = ""}, {db = -12, label = ""}, {db = 0, label = "0dB"}, {db = 12, label = ""}}
                    for _, marker in ipairs(marker_positions) do if marker.db == 0 then local norm = GetDbNorm(marker.db); local y = max_y - norm * h; r.ImGui_DrawList_AddLine(dlm, min_x, y, max_x, y, 0xFFFFFF60, 1) end end
                    local norm_v = Clamp((settings.master_vol - m_min_db) / (m_max_db - m_min_db), 0, 1)
                    local thumb_y = max_y - norm_v * h; local t_h = 13; local t_w = s_w_mst - 4; local thumb_col = 0xAAAAAAFF
                    r.ImGui_DrawList_AddRectFilled(dlm, min_x + 2, thumb_y - t_h * 0.5, min_x + 2 + t_w, thumb_y + t_h * 0.5, thumb_col, 4)
                    if hit_active then local my = select(2, r.ImGui_GetMousePos(ctx)); local norm = Clamp((max_y - my) / h, 0, 1); local v = m_min_db + norm * (m_max_db - m_min_db); if math.abs(v - settings.master_vol) > 0.01 then settings.master_vol = v; changed_any = true end end
                    if hit_hover and r.ImGui_IsMouseReleased(ctx, 0) and not hit_active then local my = select(2, r.ImGui_GetMousePos(ctx)); local norm = Clamp((max_y - my) / h, 0, 1); local v = m_min_db + norm * (m_max_db - m_min_db); if v ~= settings.master_vol then settings.master_vol = v; changed_any = true end end
                    r.ImGui_PopID(ctx); r.ImGui_EndGroup(ctx)
                    r.ImGui_SameLine(ctx, 0, 15); r.ImGui_BeginGroup(ctx)
                    r.ImGui_Text(ctx, "Scope"); local an_w, an_h = 140, MIX_H + 20; r.ImGui_Dummy(ctx, an_w, an_h)
                    local p_x, p_y = r.ImGui_GetItemRectMin(ctx); local dl = r.ImGui_GetWindowDrawList(ctx)
                    r.ImGui_DrawList_AddRectFilled(dl, p_x, p_y, p_x+an_w, p_y+an_h, 0x000000FF); r.ImGui_DrawList_AddRect(dl, p_x, p_y, p_x+an_w, p_y+an_h, 0x444444FF)
                    local cx, cy = p_x + an_w*0.5, p_y + an_h*0.5; r.ImGui_DrawList_AddLine(dl, cx, p_y, cx, p_y+an_h, 0xFFFFFF20); r.ImGui_DrawList_AddLine(dl, p_x, cy, p_x+an_w, cy, 0xFFFFFF20)
                    local l_raw = tonumber(r.gmem_read(10)) or 0; local r_raw = tonumber(r.gmem_read(11)) or 0; if math.abs(l_raw) < 0.005 then l_raw = 0 end; if math.abs(r_raw) < 0.005 then r_raw = 0 end
                    local sensitivity = 2.5; local mid = (l_raw + r_raw) * 0.5 * sensitivity; local side = (l_raw - r_raw) * 0.5 * sensitivity
                    local dot_x = cx + side * (an_w * 0.5); local dot_y = cy - mid * (an_h * 0.5); dot_x = Clamp(dot_x, p_x, p_x+an_w); dot_y = Clamp(dot_y, p_y, p_y+an_h)
                    if #scope_history >= 20 then table.remove(scope_history) end; table.insert(scope_history, 1, {x=dot_x, y=dot_y})
                    for i, point in ipairs(scope_history) do local alpha = math.floor(255 * (1 - (i/#scope_history))); local col = (c_acc & 0xFFFFFF00) | alpha; r.ImGui_DrawList_AddCircleFilled(dl, point.x, point.y, 3 - (i*0.1), col) end
                    r.ImGui_DrawList_AddCircleFilled(dl, dot_x, dot_y, 4, 0xFFFFFFFF); r.ImGui_EndGroup(ctx); r.ImGui_Dummy(ctx, 0, 4)
                end
                r.ImGui_EndTable(ctx); r.ImGui_PopStyleVar(ctx, 1); r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx, 1); r.ImGui_EndTable(ctx)
        end

        r.ImGui_Separator(ctx)

        if r.ImGui_BeginTable(ctx, "BotGrid", 9, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "Gen1", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE + 55); r.ImGui_TableSetupColumn(ctx, "Gen2", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE + 55)
            r.ImGui_TableSetupColumn(ctx, "FX1", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE + 55); r.ImGui_TableSetupColumn(ctx, "FX2", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE + 40)
            r.ImGui_TableSetupColumn(ctx, "Btn1"); r.ImGui_TableSetupColumn(ctx, "Btn2"); r.ImGui_TableSetupColumn(ctx, "Btn3"); r.ImGui_TableSetupColumn(ctx, "Btn4"); r.ImGui_TableSetupColumn(ctx, "Btn5")

            r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "GENERATORS A"); r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "Noise:"); r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##noisetype", (config.noise_type==0 and "White" or config.noise_type==1 and "Pink" or "Crackle")) then
                if r.ImGui_Selectable(ctx, "White", config.noise_type==0) then config.noise_type=0; changed_any=true end
                if r.ImGui_Selectable(ctx, "Pink", config.noise_type==1) then config.noise_type=1; changed_any=true end
                if r.ImGui_Selectable(ctx, "Crackle", config.noise_type==2) then config.noise_type=2; changed_any=true end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Tone/Color##noise", config.noise_tone, -1, 1, "%.2f"); if rv then config.noise_tone=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##noiserout", (config.noise_routing==0 and "Clean" or "Pitched")) then
                if r.ImGui_Selectable(ctx, "Clean", config.noise_routing==0) then config.noise_routing=0; changed_any=true end
                if r.ImGui_Selectable(ctx, "Pitched", config.noise_routing==1) then config.noise_routing=1; changed_any=true end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Oscillator:")
            r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##osctype", (config.osc_shape_type==0 and "Sine" or config.osc_shape_type==1 and "Saw" or config.osc_shape_type==2 and "Square" or "Triangle")) then
                if r.ImGui_Selectable(ctx, "Sine", config.osc_shape_type==0) then config.osc_shape_type=0; changed_any=true end
                if r.ImGui_Selectable(ctx, "Saw", config.osc_shape_type==1) then config.osc_shape_type=1; changed_any=true end
                if r.ImGui_Selectable(ctx, "Square", config.osc_shape_type==2) then config.osc_shape_type=2; changed_any=true end
                if r.ImGui_Selectable(ctx, "Triangle", config.osc_shape_type==3) then config.osc_shape_type=3; changed_any=true end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Shift", config.osc_octave, -24, 24, "%.1f st"); if rv then config.osc_octave=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Tone/Color##osc", config.osc_tone, -1, 1, "%.2f"); if rv then config.osc_tone=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "PWM/Shape", config.osc_pwm, 0, 1); if rv then config.osc_pwm=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Detune", config.osc_detune, -50, 50, "%.1f ct"); if rv then config.osc_detune=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Drive", config.osc_drive, 0, 1); if rv then config.osc_drive=v; changed_any=true end

            r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "GENERATORS B"); r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "Chua:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rate", config.chua_rate, 0, 0.5); if rv then config.chua_rate=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Shape", config.chua_shape, 10, 45); if rv then config.chua_shape=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Timbre", config.chua_timbre, -20, 20); if rv then config.chua_timbre=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Alpha (Chaos)", config.chua_alpha, -20, 20); if rv then config.chua_alpha=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Sub:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderInt(ctx, "Sub Freq", config.sub_freq, 30, 120); if rv then config.sub_freq=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Sub Sat", config.sub_sat, 0, 1); if rv then config.sub_sat=v; changed_any=true end

            r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "EFFECTS A"); r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "Saturation:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Sat Drive", config.sat_drive, 0, 1); if rv then config.sat_drive=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Bitcrusher:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Crush Mix", config.crush_mix, 0, 1); if rv then config.crush_mix=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Crush Rate", config.crush_rate, 0.1, 1); if rv then config.crush_rate=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Punch:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Punch", config.punch_amt, 0, 1); if rv then config.punch_amt=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Ring Mod:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Metal Mix", config.ring_metal, 0, 1); if rv then config.ring_metal=v; changed_any=true end

            r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "EFFECTS B"); r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "Flanger:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Flg Mix", config.flange_wet, 0, 1); if rv then config.flange_wet=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Flg Feed", config.flange_feed, 0, 1); if rv then config.flange_feed=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "Doubler:")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Dbl Spread", config.dbl_wide, 0, 1); if rv then config.dbl_wide=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderInt(ctx, "Dbl Delay", config.dbl_time, 10, 60); if rv then config.dbl_time=v; changed_any=true end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "pre-Rev (Diffusion):")
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Damp", config.rev_damp, 0, 1); if rv then config.rev_damp=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Tail", config.verb_tail, 0, 1); if rv then config.verb_tail=v; changed_any=true end
            r.ImGui_SetNextItemWidth(ctx, 150); rv, v = r.ImGui_SliderDouble(ctx, "Rev Size", config.verb_size, 0, 1); if rv then config.verb_size=v; changed_any=true end

            local rand_w, tog_w = 95, 96
            r.ImGui_TableNextColumn(ctx); r.ImGui_Dummy(ctx, 1, 1); r.ImGui_TableNextColumn(ctx); r.ImGui_Dummy(ctx, 1, 1); r.ImGui_TableNextColumn(ctx); r.ImGui_Dummy(ctx, 1, 1); r.ImGui_TableNextColumn(ctx); r.ImGui_Dummy(ctx, 1, 1)

            r.ImGui_TableNextColumn(ctx) -- Btn5
            r.ImGui_TextDisabled(ctx, "Envelope Shape:")
            r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##Envelope Shape", (settings.env_shape==0 and "Whoosh (Bezier)" or settings.env_shape==1 and "Rise (edge)" or "Soft (slow)")) then
                if r.ImGui_Selectable(ctx, "Whoosh (Bezier)", settings.env_shape==0) then settings.env_shape=0 end
                if r.ImGui_Selectable(ctx, "Rise (edge)", settings.env_shape==1) then settings.env_shape=1 end
                if r.ImGui_Selectable(ctx, "Soft (slow)", settings.env_shape==2) then settings.env_shape=2 end
                r.ImGui_EndCombo(ctx)
            end
            
-- 2. Doppler Mode + Reset Button
            r.ImGui_TextDisabled(ctx, "Doppler Mode:")
            
            -- Зменшуємо ширину Combo, щоб вмістити кнопку Reset поруч
            r.ImGui_SetNextItemWidth(ctx, 105) 
            local mode_str = "Pitch Shift"; if config.pitch_mode == 1 then mode_str = "Freq Shift" elseif config.pitch_mode == 2 then mode_str = "Audio Pitch" elseif config.pitch_mode == 3 then mode_str = "Physical Doppler" end
            if r.ImGui_BeginCombo(ctx, "##Pitch Mode", mode_str) then
                if r.ImGui_Selectable(ctx, "Pitch Shift", config.pitch_mode==0) then config.pitch_mode=0; changed_any=true end
                if r.ImGui_Selectable(ctx, "Freq Shift", config.pitch_mode==1) then config.pitch_mode=1; changed_any=true end
                if r.ImGui_Selectable(ctx, "Audio Pitch", config.pitch_mode==2) then config.pitch_mode=2; changed_any=true end
                if r.ImGui_Selectable(ctx, "Physical Doppler", config.pitch_mode==3) then config.pitch_mode=3; changed_any=true end
                r.ImGui_EndCombo(ctx)
            end
            
            -- Кнопка Reset тепер тут, в одному рядку з вибором режиму
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xCC4444FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xDD5555FF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xAA3333FF)
            if r.ImGui_Button(ctx, "Reset", 37, 0) then ResetPitchEnvelope(); changed_any=true; changed_pads=true end
            r.ImGui_PopStyleColor(ctx, 3)
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Resets the pitch envelopes for Freq-Pitch Shift. Use when switching to Audio-PhysDop mode.") end
            
             -- 3. Grain Size
            r.ImGui_TextDisabled(ctx, "Grain Size:")
            r.ImGui_SetNextItemWidth(ctx, 150)
            local grain_str = "1024 (Short)"
            if config.grain_size == 0 then grain_str = "512 (Tiny)" elseif config.grain_size == 2 then grain_str = "2048 (Med)" elseif config.grain_size == 3 then grain_str = "4096 (Long)" end
            if r.ImGui_BeginCombo(ctx, "##GrainSize", grain_str) then
                if r.ImGui_Selectable(ctx, "512 (Tiny)", config.grain_size==0) then config.grain_size=0; changed_any=true end
                if r.ImGui_Selectable(ctx, "1024 (Short)", config.grain_size==1) then config.grain_size=1; changed_any=true end
                if r.ImGui_Selectable(ctx, "2048 (Medium)", config.grain_size==2) then config.grain_size=2; changed_any=true end
                if r.ImGui_Selectable(ctx, "4096 (Long)", config.grain_size==3) then config.grain_size=3; changed_any=true end
                r.ImGui_EndCombo(ctx)
            end

            -- 4. Air Absorption (Тільки для режиму 3)
            if config.pitch_mode == 3 then
                r.ImGui_SetNextItemWidth(ctx, 150)
                local rv_air, v_air = r.ImGui_SliderDouble(ctx, "Air Abs", config.doppler_air or 0.5, 0, 1, "%.2f"); if rv_air then config.doppler_air = v_air; changed_any = true end
            end

            r.ImGui_Separator(ctx); r.ImGui_Dummy(ctx, 0, 5)

            local rand_c = 0xD46A3FFF; local rand_hov = DarkenColor(rand_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rand_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rand_hov)
            if r.ImGui_Button(ctx, "Randomize", rand_w, 30) then RandomizeConfig(); changed_any = true end
            r.ImGui_PopStyleColor(ctx, 2); r.ImGui_SameLine(ctx)
            local btn_c = 0x2D8C6DFF; local hov_c = DarkenColor(btn_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hov_c)
            if r.ImGui_Button(ctx, "Toggle Envs", tog_w, 30) then ToggleEnvelopes() end
            r.ImGui_PopStyleColor(ctx, 2)

            local gen_c = c_acc; local gen_hov = DarkenColor(gen_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), gen_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), gen_hov)
            if r.ImGui_Button(ctx, "GENERATE", 200, 50) then GenerateWhoosh() end
            r.ImGui_PopStyleColor(ctx, 2)

            local bounce_c = C_MUTE_ACTIVE; local bounce_hov = LightenColor(bounce_c, 1.08); local bounce_act = DarkenColor(bounce_c)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bounce_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), bounce_hov); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), bounce_act)
            if r.ImGui_Button(ctx, "BOUNCE", 200, 40) then BounceToNewTrack() end
            r.ImGui_PopStyleColor(ctx, 3)

            r.ImGui_EndTable(ctx)
        end

        if changed_any then 
            local track = FindTrackByName(settings.track_name)
            if track then
                local fx = GetOrAddFX(track, FX_NAME)
                r.TrackFX_SetParam(track, fx, IDX.out_mode, settings.output_mode)
                r.TrackFX_SetParam(track, fx, IDX.master_vol, settings.master_vol)
                r.TrackFX_SetParam(track, fx, IDX.pitch_mode, config.pitch_mode or 0)
                r.TrackFX_SetParam(track, fx, IDX.sub_freq, config.sub_freq)
                r.TrackFX_SetParam(track, fx, IDX.mix_sub, config.sub_enable and config.sub_vol or 0)
                r.TrackFX_SetParam(track, fx, IDX.sub_sat, config.sub_sat or 0)
                r.TrackFX_SetParam(track, fx, IDX.noise_type, config.noise_type or 0)
                r.TrackFX_SetParam(track, fx, IDX.noise_tone, config.noise_tone or 0)
                r.TrackFX_SetParam(track, fx, IDX.noise_routing, config.noise_routing or 0)
                r.TrackFX_SetParam(track, fx, IDX.osc_shape, config.osc_shape_type)
                r.TrackFX_SetParam(track, fx, IDX.osc_pwm, config.osc_pwm)
                r.TrackFX_SetParam(track, fx, IDX.osc_detune, config.osc_detune)
                r.TrackFX_SetParam(track, fx, IDX.osc_drive, config.osc_drive or 0)
                r.TrackFX_SetParam(track, fx, IDX.osc_octave, config.osc_octave or 0)
                r.TrackFX_SetParam(track, fx, IDX.osc_tone, config.osc_tone or 0)
                r.TrackFX_SetParam(track, fx, IDX.chua_rate, config.chua_rate)
                r.TrackFX_SetParam(track, fx, IDX.chua_shape, config.chua_shape)
                r.TrackFX_SetParam(track, fx, IDX.chua_timbre, config.chua_timbre)
                r.TrackFX_SetParam(track, fx, IDX.chua_alpha, config.chua_alpha or 15.6)
                r.TrackFX_SetParam(track, fx, IDX.sat_drive, config.sat_drive or 0)
                r.TrackFX_SetParam(track, fx, IDX.crush_mix, config.crush_mix or 0)
                r.TrackFX_SetParam(track, fx, IDX.crush_rate, config.crush_rate or 1.0)
                r.TrackFX_SetParam(track, fx, IDX.punch_amt, config.punch_amt or 0)
                r.TrackFX_SetParam(track, fx, IDX.ring_metal, config.ring_metal or 0)
                r.TrackFX_SetParam(track, fx, IDX.trim_w, config.mute_w and 0 or config.trim_w)
                r.TrackFX_SetParam(track, fx, IDX.trim_o, config.mute_o and 0 or config.trim_o)
                r.TrackFX_SetParam(track, fx, IDX.trim_c, config.mute_c and 0 or config.trim_c)
                r.TrackFX_SetParam(track, fx, IDX.trim_e, config.mute_e and 0 or config.trim_e)
                r.TrackFX_SetParam(track, fx, IDX.chop_shape, config.chop_shape)
                r.TrackFX_SetParam(track, fx, IDX.flange_mix, config.flange_wet)
                r.TrackFX_SetParam(track, fx, IDX.flange_feed, config.flange_feed)
                r.TrackFX_SetParam(track, fx, IDX.dbl_wide, config.dbl_wide)
                r.TrackFX_SetParam(track, fx, IDX.dbl_time, config.dbl_time)
                r.TrackFX_SetParam(track, fx, IDX.verb_damp, config.rev_damp)
                r.TrackFX_SetParam(track, fx, IDX.verb_tail, config.verb_tail or 0.5)
                r.TrackFX_SetParam(track, fx, IDX.verb_size, config.verb_size)
                r.TrackFX_SetParam(track, fx, IDX.doppler_air, config.doppler_air or 0.5)
                r.TrackFX_SetParam(track, fx, IDX.grain_size, config.grain_size or 1)
                local sur_px, sur_py = GetSurroundLivePoint(config, config.peak_pos or 0.5)
                r.TrackFX_SetParam(track, fx, IDX.sur_mode, config.sur_mode or 0)
                r.TrackFX_SetParam(track, fx, IDX.sur_path_x, sur_px or 0.5)
                r.TrackFX_SetParam(track, fx, IDX.sur_path_y, sur_py or 0.0)
                r.TrackFX_SetParam(track, fx, IDX.sur_arc_len, config.sur_c_len or 0.9)
                r.TrackFX_SetParam(track, fx, IDX.sur_arc_off, config.sur_c_off or 0.0)
                r.TrackFX_SetParam(track, fx, IDX.sur_full_rotations, config.sur_full_rot or 1.0)
                r.TrackFX_SetParam(track, fx, IDX.sur_direction, config.sur_c_dir and 1 or 0)
                r.TrackFX_SetParam(track, fx, IDX.sur_full_offset, config.sur_full_off or 0.0)
            end
            
            if changed_pads then
                pads_dirty = true
                surround_env_dirty = false
                local now_t = r.time_precise()
                if now_t - (interaction.last_update_time or 0) > 0.05 then
                    UpdateAutomationOnly("env")
                    interaction.last_update_time = now_t
                end
            elseif surround_env_dirty and r.ImGui_IsMouseDown(ctx, 0) then
                local now_t = r.time_precise()
                if now_t - (interaction.last_update_time or 0) > 0.08 then
                    UpdateAutomationOnly("env")
                    interaction.last_update_time = now_t
                end
            elseif surround_env_dirty and not r.ImGui_IsMouseDown(ctx, 0) then
                UpdateAutomationOnly("env")
                surround_env_dirty = false
                changed_any = false
                interaction.last_update_time = r.time_precise()
            elseif not r.ImGui_IsMouseDown(ctx, 0) then
                UpdateAutomationOnly("env")
                changed_any = false
                interaction.last_update_time = r.time_precise()
            end
        end
        if pads_dirty and not r.ImGui_IsMouseDown(ctx, 0) then
            UpdateAutomationOnly("env")
            pads_dirty = false
            interaction.last_update_time = r.time_precise()
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 14); r.ImGui_PopStyleVar(ctx, 4)
    if open then r.defer(Loop) end
end

LoadSettings()
LoadUserPresets()
r.atexit(SaveSettings)
r.defer(Loop)