-- @description SBP ReaWhoosh - Advanced Whoosh Generator
-- @author SBP & AI
-- @version 4.01
-- @about ReaWhoosh is a tool for automatically creating whoosh-type sound effects.
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @provides
--   [main] .
--   modules/SurroundWindow.lua
-- @changelog
--    v4.01 (2026-08-12)
--    Fixed External Input routing and transparent Filter bypass when the Filter pad is disabled.
--    Audio Pitch and Physical Doppler now bypass granular processing at 0 semitones; Grain Size no longer colours a centred external source.
--    Stereo generation no longer creates Surround Path X/Y automation lanes.
--    Improved pad point hit-testing and edge-handle dragging; added up to +12 dB External makeup gain in the mixer.
--    v4.0 (2026-08-12) — Release summary
--    Complete UI 2.0: compact Generator Rack, fixed performance workspace and Effects/Actions strip.
--    New Whoosh, Rise, Soft, Whoosh + Hit and Rise + Hit workflows with responsive envelope previews.
--    Expanded Hit Engine: body, sub, crack, metallic Crash layer, ducking, Drive/Tone and correct Chopper/Panning bypasses.
--    Improved synthesis and FX: expanded oscillator/FM, Noise/Chua/Sub/Ring controls, stable reverb routing and safer Chopper.
--    Production workflow: Tail Preview, non-destructive Replace/Next slot/New layer generation, Bounce and true A/B variations.
--    External Parameter Link supports normalized ranges, target locking, randomization and alphabetical parameter selection.
--    Presets and randomization include current modules; right-click resets every active slider to its factory value.
--    Removed dormant legacy UI duplicates; JSFX parameter indices remain append-only for automation compatibility.
--    v3.9.1 (2026-08-11)
--    Moved Tail Preview duration to Options → Preview Settings.
--    v3.9.0 (2026-08-11)
--    Added Tail Preview: extends REAPER's loop range for auditioning tails while automation stays locked to the original design range.
--    v3.8.3 (2026-08-11)
--    Added Hit → Bypass Chopper and hid JSFX parameters while preserving automation compatibility.
--    v3.8.2 (2026-08-11)
--    Reduced default Hit Crack level; engine v3.8.1 adds clickless onset and a shorter band-limited crack burst.
--    v3.8.1 (2026-08-11)
--    Fixed Generate crash when CreateNewMIDIItemInProj returns a non-usable handle; added pointer validation and track-item fallback.
--    v3.8.0 (2026-08-11)
--    Added the first Hit Engine: impact trigger, transient, body, sub, crack, decay, tone, drive and whoosh ducking.
--    Hit settings use a popup so the main layout remains unchanged.
--    v3.7.2 (2026-08-11)
--    Advanced Rise MIDI notes now end at the impact/peak while the item and FX tails keep the full selection.
--    Spacebar transport now toggles Play/Stop like REAPER and ignores key-repeat restarts.
--    v3.7.1 (2026-08-11)
--    Rise controls moved into the envelope preview; automation commits on mouse release for smoother editing.
--    Pre-hit Dip now affects amplitude only; inherited pitch/filter/gate curves remain monotonic.
--    Rise release is now a short decay shape instead of a long whoosh-style falloff; preview rendering is oversampled.
--    v3.7.0 (2026-08-11)
--    Rebuilt Rise as a true multi-point envelope with Curve, Acceleration, Pre-hit Dip and Release.
--    Rise preview and REAPER automation now share the same generated point data.
--    Added a generic envelope point writer for upcoming Hit and Tail modules.
--    v3.6.1 (2026-08-11)
--    Fixed Circle/Full Circles coordinate orientation to match the 5.1 speaker view and VBAP order.
--    v3.6.0 (2026-08-11)
--    Engine stabilization: centralized the Lua/JSFX parameter registry and static parameter sync.
--    Fixed Full Circles timing so the requested rotation count follows the actual time selection length.
--    Kept all existing JSFX parameter indices stable; the duration control is appended as parameter 65.
--    v3.5.5 (2026-04-12)
--    Performance: Added r.PreventUIRefresh() around envelope batch writes - eliminates 2-3s lag when editing pads (Reaper no longer redraws after each InsertEnvelopePoint).
--    Performance: Increased pad drag throttle from 50ms to 80ms for consistency with surround.
--    Performance: Fixed explicit circle segment count (32) in DrawVectorPad to avoid per-frame auto-calculation overhead.
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

local PAD_SQUARE    = 150 -- keeps the six-pad grid usable beside the Generator Rack
local MIX_W         = 25  
local MIX_H         = 126
local PAD_DRAW_H    = 150
local CONTAINER_H   = 210 

-- DATA
local settings = {
    track_name = "Whoosh FX",
    output_mode = 0, 
    col_accent = C_ACCENT_DEF,
    col_bg = C_BG_DEF,
    master_vol = -6.0,
    env_shape = 0, 
    engine_type = 0, -- 0 Whoosh, 1 Rise, 2 Soft, 3 Whoosh+Hit, 4 Rise+Hit
    peak_mode = 0,
    pitch_mode = 0,
    audio_pitch = 0.0,
    -- Randomization Masks
    rand_src = true, rand_exclude_ext = true, rand_morph = true, rand_filt = true,
    rand_dop = true, rand_space = true, rand_chop = true, rand_env = false,
    rand_surround = true, rand_link = false, rand_link_lock = true,
    rand_noise = true, rand_osc = true, rand_chua = true, rand_sub = true, rand_hit = false,
    env_inherit_shape = false,
    pad_preview_interval = 0.08, -- 0 = update only on mouse release
    sur_win_open = false
}

local config = {
    peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4,
    rise_slope = 0.0, -- legacy preset field, retained for compatibility
    rise_curve = 0, rise_accel = 0.65, rise_dip = 0.0, rise_release = 0.15,
    hit_enable = false, hit_level = 0.8, hit_body = 0.7, hit_sub = 0.65,
    hit_crack = 0.20, hit_crash = 0.0, hit_decay = 0.55, hit_tone = 0.0, hit_drive = 0.2, hit_duck = 0.35, hit_chop_bypass = true, hit_pan_bypass = true,
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
    chop_enable=true, filter_enable=true, doppler_enable=true, space_enable=true, chop_shape=0.0,

    link_s_x=0.0, link_s_y=0.0, link_p_x=0.5, link_p_y=1.0, link_e_x=1.0, link_e_y=0.0, link_enable=true,
    generate_mode=0, generate_gap=0.10, -- 0: replace, 1: next slot, 2: new track
    link_bindings = {
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0},
      {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0}
    },

    sub_freq = 55, sub_enable = true, sub_vol = 0.8, sub_sat = 0.0,
    
    noise_type = 0, noise_tone = 0.0, noise_crackle_density = 0.35,
    osc_shape_type = 1, osc_pwm = 0.1, osc_detune = 0.0, osc_drive = 0.0, osc_octave = 0.0, osc_tone = 0.0, osc_unison_mix = 0.5, osc_voice2_ratio = 1.0, osc_phase_random = 0.0, osc_drift = 0.0, osc_fm_amount = 0.1, osc_fm_source = 0, osc_fm_shape = 0, osc_fm_ratio = 2.0,
    chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, chua_alpha = 15.6,
    sat_drive = 0.0, crush_mix = 0.0, crush_rate = 1.0, punch_amt = 0.0, ring_metal = 0.0, ring_freq = 420.0, ring_shape = 0.0, noise_routing = 0,
    
    flange_wet=0.0, flange_feed=0.0, verb_size=0.5, rev_damp = 0.5, verb_tail = 0.5, reverb_position = 0,
    dbl_time = 30, dbl_wide = 0.5,
    
    doppler_air = 0.5, pitch_clear_on_mode_change = false,
    grain_size = 1, -- 0=512, 1=1024, 2=2048, 3=4096

    mute_w = false, mute_o = false, mute_c = false, mute_e = false,
    trim_w = 1.0, trim_o = 1.0, trim_c = 1.0, trim_e = 1.0, 
    current_preset = "Default",
    bounce_tail = 0.5,
    tail_preview_seconds = 2.0
}

local function SetEngineType(kind)
    settings.engine_type = kind
    settings.env_shape = (kind == 1 or kind == 4) and 1 or (kind == 2 and 2 or 0)
    if kind == 3 or kind == 4 then config.hit_enable = true else config.hit_enable = false end
end
local function EngineTypeName()
    return ({"Whoosh (Bezier)", "Rise", "Soft (slow)", "Whoosh + Hit", "Rise + Hit"})[(settings.engine_type or settings.env_shape or 0) + 1] or "Whoosh (Bezier)"
end

-- Temporary A/B variations are complete in-memory snapshots.  Unlike
-- the compact preset serializer, this preserves nested data such as Link
-- bindings and therefore makes comparison genuinely non-destructive.
local variation_slots = {A=nil, B=nil}
local variation_recalled = false
local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end
-- Fixed factory values for per-slider right-click reset.  Presets and A/B
-- snapshots mutate `config`, so the live table cannot serve as this reference.
local CONFIG_DEFAULTS = DeepCopy(config)
local function ResetSliderOnRightClick(key)
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
        local default = CONFIG_DEFAULTS[key]
        if default ~= nil and config[key] ~= default then
            config[key] = DeepCopy(default)
            return true
        end
    end
    return false
end
local function CaptureVariation(slot)
    variation_slots[slot] = {config=DeepCopy(config), automation=CaptureVariationAutomation and CaptureVariationAutomation() or nil}
end
local function RecallVariation(slot)
    if not variation_slots[slot] then return false end
    local stored = variation_slots[slot]
    local previous_config = DeepCopy(config)
    local snapshot = DeepCopy(stored.config or stored)
    for k in pairs(config) do config[k] = nil end
    for k, v in pairs(snapshot) do config[k] = v end
    ValidateConfig()
    if RestoreVariationAutomation and stored.automation then RestoreVariationAutomation(stored.automation, previous_config) end
    variation_recalled = true
    return true
end
local function DuplicateVariation(from_slot, to_slot)
    if not variation_slots[from_slot] then return false end
    variation_slots[to_slot] = DeepCopy(variation_slots[from_slot])
    return true
end

local FACTORY_PRESETS = {
    ["Default"] = {
        engine_type = 0,
        peak_pos = 0.60, tens_attack = 0.6, tens_release = -0.4, rise_slope = 0.0,
        rise_curve = 0, rise_accel = 0.65, rise_dip = 0.0, rise_release = 0.15,
        hit_enable = false, hit_level = 0.8, hit_body = 0.7, hit_sub = 0.65,
        hit_crack = 0.20, hit_crash = 0.0, hit_decay = 0.55, hit_tone = 0.0, hit_drive = 0.2, hit_duck = 0.35, hit_chop_bypass = true, hit_pan_bypass = true,
        audio_pitch = 0.0,
        src_s_x=0.0, src_s_y=1.0, src_p_x=0.5, src_p_y=0.5, src_e_x=0.0, src_e_y=1.0,
        cut_s_x=0.1, cut_s_y=0.1, cut_p_x=1.0, cut_p_y=0.8, cut_e_x=0.1, cut_e_y=0.1,
        sur_mode = 0,
        sur_v_s_x=0.0, sur_v_s_y=0.0, sur_v_p_x=0.5, sur_v_p_y=1.0, sur_v_e_x=1.0, sur_v_e_y=0.5,
        sur_c_len=0.9, sur_c_off=0.0, sur_c_dir=false,
        sur_full_rot=1.0, sur_full_off=0.0,
        sub_freq = 55, sub_vol = 0.8, sub_enable = true, sub_sat = 0.0,
        noise_type = 0, noise_tone = 0.0, noise_crackle_density = 0.35, noise_routing = 0,
        osc_shape_type = 1, osc_pwm = 0.1, osc_detune = 0.0, osc_drive = 0.0, osc_octave = 0.0, osc_tone = 0.0, osc_unison_mix = 0.5, osc_voice2_ratio = 1.0, osc_phase_random = 0.0, osc_drift = 0.0, osc_fm_amount = 0.1, osc_fm_source = 0, osc_fm_shape = 0, osc_fm_ratio = 2.0,
        chua_rate = 0.05, chua_shape = 28.0, chua_timbre = -2.0, chua_alpha = 15.6,
        sat_drive = 0.0, crush_mix = 0.0, crush_rate = 1.0, punch_amt = 0.0, ring_metal = 0.0, ring_freq = 420.0, ring_shape = 0.0,
        pitch_mode = 0, doppler_air = 0.5, pitch_clear_on_mode_change = false, grain_size = 1,
        flange_wet=0.0, flange_feed=0.0, verb_size=0.5, dbl_time=30, dbl_wide = 0.5, rev_damp = 0.5, verb_tail = 0.5, reverb_position = 0,
        chop_s_x=0.0, chop_s_y=0.0, chop_p_x=0.0, chop_p_y=0.0, chop_e_x=0.0, chop_e_y=0.0,
        chop_enable=true, filter_enable=true, doppler_enable=true, space_enable=true, chop_shape=0.0, link_enable=true, generate_mode=0, generate_gap=0.10,
        link_bindings = {
            {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0, auto_range=true},
            {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0, auto_range=true},
            {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0, auto_range=true},
            {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0, auto_range=true}
        }
    }
}

-- Factory variants inherit every safe Default value, then override only the
-- musical identity.  `engine_type` is metadata: ApplyPreset uses it to switch
-- the matching automation mode instead of passing it to the JSFX config.
local function MakeFactoryPreset(engine_type, overrides)
    local preset = DeepCopy(FACTORY_PRESETS["Default"])
    preset.engine_type = engine_type
    for key, value in pairs(overrides) do preset[key] = type(value) == "table" and DeepCopy(value) or value end
    return preset
end

FACTORY_PRESETS["Whoosh — Air Sweep"] = MakeFactoryPreset(0, {
    peak_pos=0.58, tens_attack=0.35, tens_release=-0.25,
    src_s_x=0.12, src_s_y=0.82, src_p_x=0.46, src_p_y=0.98, src_e_x=0.78, src_e_y=0.42,
    noise_type=1, noise_tone=0.32, osc_shape_type=1, osc_octave=-5, osc_detune=7, osc_drive=0.12,
    cut_s_x=0.18, cut_s_y=0.15, cut_p_x=0.88, cut_p_y=0.38, cut_e_x=0.42, cut_e_y=0.12,
    flange_wet=0.10, flange_feed=0.12, dbl_wide=0.62, verb_size=0.58, verb_tail=0.42
})

FACTORY_PRESETS["Rise — Tension Lift"] = MakeFactoryPreset(1, {
    peak_pos=0.91, rise_curve=0, rise_accel=0.48, rise_dip=0.0, rise_release=0.12,
    src_s_x=0.08, src_s_y=0.68, src_p_x=0.52, src_p_y=0.96, src_e_x=0.86, src_e_y=0.48,
    noise_type=1, noise_tone=0.45, osc_shape_type=1, osc_octave=-2, osc_detune=12, osc_drive=0.18,
    cut_s_x=0.16, cut_s_y=0.12, cut_p_x=0.96, cut_p_y=0.46, cut_e_x=0.78, cut_e_y=0.20,
    chop_enable=true, chop_s_x=0.18, chop_s_y=0.00, chop_p_x=0.62, chop_p_y=0.46, chop_e_x=0.84, chop_e_y=0.22, chop_shape=0.34,
    flange_wet=0.08, dbl_wide=0.68, verb_size=0.62, verb_tail=0.54
})

FACTORY_PRESETS["Soft — Electric Arc"] = MakeFactoryPreset(2, {
    peak_pos=0.64, tens_attack=0.72, tens_release=-0.12,
    src_s_x=0.50, src_s_y=0.95, src_p_x=0.50, src_p_y=1.00, src_e_x=0.50, src_e_y=0.72,
    noise_type=2, noise_tone=0.74, noise_crackle_density=0.84, noise_routing=1,
    osc_shape_type=2, osc_pwm=0.34, osc_octave=10, osc_detune=18, osc_drive=0.30, osc_tone=0.58, osc_unison_mix=0.68, osc_voice2_ratio=1.99,
    cut_s_x=0.52, cut_s_y=0.34, cut_p_x=0.86, cut_p_y=0.72, cut_e_x=0.36, cut_e_y=0.28,
    ring_metal=0.34, ring_freq=1840, ring_shape=0.58, sat_drive=0.16, crush_mix=0.09, crush_rate=0.72,
    flange_wet=0.16, flange_feed=0.22, dbl_wide=0.34, verb_size=0.38, verb_tail=0.28
})

FACTORY_PRESETS["Whoosh + Hit — Trailer"] = MakeFactoryPreset(3, {
    peak_pos=0.66, tens_attack=0.45, tens_release=-0.34,
    src_s_x=0.08, src_s_y=0.78, src_p_x=0.52, src_p_y=0.96, src_e_x=0.70, src_e_y=0.36,
    noise_type=1, noise_tone=0.25, osc_shape_type=0, osc_octave=-10, osc_drive=0.18, osc_fm_amount=0.72, osc_fm_source=0, osc_fm_shape=1, osc_fm_ratio=2.50, osc_unison_mix=0.58, osc_voice2_ratio=1.50, sub_freq=48, sub_sat=0.20,
    hit_enable=true, hit_level=1.10, hit_body=0.88, hit_sub=0.82, hit_crack=0.32, hit_crash=0.24, hit_decay=0.48, hit_tone=0.18, hit_drive=0.30, hit_duck=0.46,
    cut_s_x=0.12, cut_s_y=0.14, cut_p_x=0.94, cut_p_y=0.48, cut_e_x=0.38, cut_e_y=0.12,
    sat_drive=0.12, punch_amt=0.26, dbl_wide=0.66, verb_size=0.55, verb_tail=0.38
})

FACTORY_PRESETS["Rise + Hit — Hybrid Impact"] = MakeFactoryPreset(4, {
    peak_pos=0.90, rise_curve=2, rise_accel=0.82, rise_dip=0.0, rise_release=0.10,
    src_s_x=0.10, src_s_y=0.70, src_p_x=0.50, src_p_y=0.98, src_e_x=0.82, src_e_y=0.42,
    noise_type=1, noise_tone=0.40, osc_shape_type=1, osc_octave=-7, osc_detune=9, osc_drive=0.14, sub_freq=52, sub_sat=0.12,
    hit_enable=true, hit_level=0.96, hit_body=0.72, hit_sub=0.70, hit_crack=0.38, hit_crash=0.36, hit_decay=0.40, hit_tone=0.42, hit_drive=0.24, hit_duck=0.52,
    cut_s_x=0.16, cut_s_y=0.12, cut_p_x=0.98, cut_p_y=0.52, cut_e_x=0.62, cut_e_y=0.18,
    ring_metal=0.12, ring_freq=1250, flange_wet=0.08, dbl_wide=0.58, verb_size=0.60, verb_tail=0.46
})
local FACTORY_PRESET_ORDER = {
    "Default", "Whoosh — Air Sweep", "Rise — Tension Lift", "Soft — Electric Arc",
    "Whoosh + Hit — Trailer", "Rise + Hit — Hybrid Impact"
}

local USER_PRESETS = {} 
local PRESET_INPUT_BUF = ""
local SHOW_SAVE_MODAL = false
local DO_FOCUS_INPUT = false
local PRESET_SECTION = "ReaWhoosh_UserPresets"
local PRESET_LIST_KEY = "PRESET_LIST"

-- Canonical JSFX parameter order. Append new parameters only: existing indices are
-- part of saved REAPER automation and must never be reordered.
local ENGINE_PARAM_ORDER = {
    "env_val", "global_pitch", "master_vol", "out_mode", "pitch_mode",
    "mix_noise", "noise_type", "noise_tone",
    "mix_osc", "osc_shape", "osc_pwm", "osc_detune", "osc_drive",
    "mix_chua", "chua_rate", "chua_shape", "chua_timbre", "chua_alpha",
    "mix_sub", "sub_freq", "sub_sat", "mix_ext",
    "filt_morph_x", "filt_morph_y", "filt_freq", "filt_res",
    "flange_mix", "flange_feed", "dbl_mix", "dbl_time", "dbl_wide",
    "verb_mix", "verb_size", "verb_damp", "verb_tail",
    "sat_drive", "crush_mix", "crush_rate", "punch_amt",
    "chop_depth", "chop_rate", "chop_shape",
    "pan_x", "pan_y", "width",
    "trim_w", "trim_o", "trim_c", "trim_e",
    "ring_metal", "osc_octave", "audio_pitch", "osc_tone", "noise_routing",
    "doppler_air", "grain_size",
    "sur_mode", "sur_path_x", "sur_path_y",
    "sur_arc_len", "sur_arc_off", "sur_full_rotations", "sur_direction", "sur_full_offset",
    "effect_duration",
    "hit_trigger", "hit_enable", "hit_level", "hit_body", "hit_sub",
    "hit_crack", "hit_decay", "hit_tone", "hit_drive", "hit_duck", "hit_chop_bypass", "hit_pan_bypass", "reverb_position", "osc_unison_mix", "osc_voice2_ratio", "osc_phase", "osc_drift", "osc_fm_amount", "osc_fm_source", "osc_fm_shape", "osc_fm_ratio", "noise_crackle_density", "ring_freq", "ring_shape", "hit_crash"
}

local IDX = {}
for param_index, param_name in ipairs(ENGINE_PARAM_ORDER) do
    IDX[param_name] = param_index - 1
end

local interaction = { dragging_pad = nil, dragging_point = nil, last_update_time = 0, dragging_peak = false }
local tail_preview = { active = false, start_time = 0, end_time = 0 }
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

local function GetDesignTimeRange()
    if tail_preview.active then return tail_preview.start_time, tail_preview.end_time end
    return r.GetSet_LoopTimeRange(false, false, 0, 0, false)
end

local function RefreshTailPreviewRange()
    if not tail_preview.active then return end
    local preview_end = tail_preview.end_time + Clamp(config.tail_preview_seconds or 2.0, 0.1, 10.0)
    r.GetSet_LoopTimeRange(true, false, tail_preview.start_time, preview_end, false)
end

local function ToggleTailPreview()
    if tail_preview.active then
        r.GetSet_LoopTimeRange(true, false, tail_preview.start_time, tail_preview.end_time, false)
        tail_preview.active = false
        return
    end
    local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if end_time <= start_time then
        r.ShowMessageBox("Select a time range before enabling Tail Preview.", "ReaWhoosh", 0)
        return
    end
    tail_preview.active, tail_preview.start_time, tail_preview.end_time = true, start_time, end_time
    RefreshTailPreviewRange()
end

local function SyncEngineStaticParams(track, fx, effect_duration)
    if not track or not fx or fx < 0 then return end
    local sur_px, sur_py = GetSurroundLivePoint(config, config.peak_pos or 0.5)
    local values = {
        out_mode = settings.output_mode, master_vol = settings.master_vol,
        pitch_mode = config.pitch_mode or 0,
        sub_freq = config.sub_freq, mix_sub = config.sub_enable and config.sub_vol or 0,
        sub_sat = config.sub_sat or 0,
        noise_type = config.noise_type or 0, noise_tone = config.noise_tone or 0, noise_crackle_density = config.noise_crackle_density or 0.35,
        noise_routing = config.noise_routing or 0,
        osc_shape = config.osc_shape_type, osc_pwm = config.osc_pwm,
        osc_detune = config.osc_detune, osc_drive = config.osc_drive or 0,
        osc_octave = config.osc_octave or 0, osc_tone = config.osc_tone or 0, osc_unison_mix = config.osc_unison_mix or 0.5, osc_voice2_ratio = config.osc_voice2_ratio or 1.0, osc_phase = config.osc_phase_random or config.osc_phase or 0, osc_drift = config.osc_drift or 0, osc_fm_amount = config.osc_fm_amount or 0.1, osc_fm_source = config.osc_fm_source or 0, osc_fm_shape = config.osc_fm_shape or 0, osc_fm_ratio = config.osc_fm_ratio or 2.0,
        chua_rate = config.chua_rate, chua_shape = config.chua_shape,
        chua_timbre = config.chua_timbre, chua_alpha = config.chua_alpha or 15.6,
        sat_drive = config.sat_drive or 0, crush_mix = config.crush_mix or 0,
        crush_rate = config.crush_rate or 1.0, punch_amt = config.punch_amt or 0,
        ring_metal = config.ring_metal or 0, ring_freq = config.ring_freq or 420.0, ring_shape = config.ring_shape or 0,
        trim_w = config.mute_w and 0 or config.trim_w,
        trim_o = config.mute_o and 0 or config.trim_o,
        trim_c = config.mute_c and 0 or config.trim_c,
        trim_e = config.mute_e and 0 or config.trim_e,
        chop_shape = config.chop_shape,
        flange_mix = config.flange_wet, flange_feed = config.flange_feed,
        dbl_wide = config.dbl_wide, dbl_time = config.dbl_time,
        verb_damp = config.rev_damp, verb_tail = config.verb_tail or 0.5,
        verb_size = config.verb_size, reverb_position = config.reverb_position or 0,
        doppler_air = config.doppler_air or 0.5, grain_size = config.grain_size or 1,
        sur_mode = config.sur_mode or 0, sur_path_x = sur_px or 0.5,
        sur_path_y = sur_py or 0.0, sur_arc_len = config.sur_c_len or 0.9,
        sur_arc_off = config.sur_c_off or 0.0,
        sur_full_rotations = config.sur_full_rot or 1.0,
        sur_direction = config.sur_c_dir and 1 or 0,
        sur_full_offset = config.sur_full_off or 0.0,
        effect_duration = math.max(0.01, effect_duration or 1.5),
        hit_enable = config.hit_enable and 1 or 0,
        hit_level = config.hit_level or 0.8, hit_body = config.hit_body or 0.7,
        hit_sub = config.hit_sub or 0.65, hit_crack = config.hit_crack or 0.20, hit_crash = config.hit_crash or 0,
        hit_decay = config.hit_decay or 0.55, hit_tone = config.hit_tone or 0,
        hit_drive = config.hit_drive or 0.2, hit_duck = config.hit_duck or 0.35,
        hit_chop_bypass = config.hit_chop_bypass and 1 or 0,
        hit_pan_bypass = config.hit_pan_bypass and 1 or 0
    }
    for name, value in pairs(values) do
        r.TrackFX_SetParam(track, fx, IDX[name], value)
    end
end

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
    if config.rise_curve == nil then config.rise_curve = 0 end
    config.rise_curve = math.floor(Clamp(config.rise_curve, 0, 3) + 0.5)
    if config.rise_accel == nil then config.rise_accel = Clamp(config.rise_slope or 0.65, 0, 1) end
    if config.rise_dip == nil then config.rise_dip = 0.0 end
    if config.rise_release == nil then config.rise_release = 0.15 end
    config.rise_accel = Clamp(config.rise_accel, 0, 1)
    config.rise_dip = Clamp(config.rise_dip, 0, 1)
    config.rise_release = Clamp(config.rise_release, 0, 1)
    if config.hit_enable == nil then config.hit_enable = false end
    config.hit_level = Clamp(config.hit_level or 0.8, 0, 2)
    config.hit_body = Clamp(config.hit_body or 0.7, 0, 1)
    config.hit_sub = Clamp(config.hit_sub or 0.65, 0, 1)
    config.hit_crack = Clamp(config.hit_crack or 0.20, 0, 1)
    config.hit_crash = Clamp(config.hit_crash or 0, 0, 1)
    config.hit_decay = Clamp(config.hit_decay or 0.55, 0.05, 2.0)
    config.hit_tone = Clamp(config.hit_tone or 0, -1, 1)
    config.hit_drive = Clamp(config.hit_drive or 0.2, 0, 1)
    config.hit_duck = Clamp(config.hit_duck or 0.35, 0, 1)
    if config.hit_chop_bypass == nil then config.hit_chop_bypass = true end
    if config.hit_pan_bypass == nil then config.hit_pan_bypass = true end
    if config.filter_enable == nil then config.filter_enable = true end
    if config.doppler_enable == nil then config.doppler_enable = true end
    if config.space_enable == nil then config.space_enable = true end
    config.reverb_position = math.floor(Clamp(config.reverb_position or 0, 0, 2) + 0.5)
    config.osc_unison_mix = Clamp(config.osc_unison_mix or 0.5, 0, 1)
    config.osc_voice2_ratio = Clamp(config.osc_voice2_ratio or 1.0, 0.5, 4.0)
    if config.osc_phase_random == nil then config.osc_phase_random = config.osc_phase or 0 end
    config.osc_phase_random = Clamp(config.osc_phase_random, 0, 1)
    config.osc_drift = Clamp(config.osc_drift or 0, 0, 1)
    config.osc_fm_amount = Clamp(config.osc_fm_amount or 0.1, 0, 1)
    config.osc_fm_source = math.floor(Clamp(config.osc_fm_source or 0, 0, 2) + 0.5)
    config.osc_fm_shape = math.floor(Clamp(config.osc_fm_shape or 0, 0, 2) + 0.5)
    config.osc_fm_ratio = Clamp(config.osc_fm_ratio or 2.0, 0.25, 8.0)
    config.chua_alpha = Clamp(config.chua_alpha or 15.6, 5.0, 20.0)
    config.noise_crackle_density = Clamp(config.noise_crackle_density or 0.35, 0, 1)
    config.ring_freq = Clamp(config.ring_freq or 420.0, 20, 4000)
    config.ring_shape = Clamp(config.ring_shape or 0, 0, 1)
    if config.link_enable == nil then config.link_enable = true end
    config.generate_mode = math.floor(Clamp(config.generate_mode or 0, 0, 2) + 0.5)
    config.generate_gap = Clamp(config.generate_gap or 0.10, 0, 10)
    config.tail_preview_seconds = Clamp(config.tail_preview_seconds or 2.0, 0.1, 10.0)
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
        "name=%s;mode=%d;c1=%d;c3=%d;mv=%.2f;shp=%d;pm=%d;rs=%d;rm=%d;rf=%d;rd=%d;rsp=%d;rc=%d;re=%d;rsr=%d;rl=%d;rll=%d;esh=%d;rgn=%d;rgo=%d;rgc=%d;rgs=%d;rgh=%d;ppi=%.3f",
        settings.track_name, settings.output_mode,
        SafeCol(settings.col_accent, C_ACCENT_DEF), SafeCol(settings.col_bg, C_BG_DEF), settings.master_vol or -6.0,
        settings.env_shape or 0, settings.peak_mode or 0,
        settings.rand_src and 1 or 0, settings.rand_morph and 1 or 0, settings.rand_filt and 1 or 0,
        settings.rand_dop and 1 or 0, settings.rand_space and 1 or 0, settings.rand_chop and 1 or 0, settings.rand_env and 1 or 0,
        settings.rand_surround and 1 or 0, settings.rand_link and 1 or 0, settings.rand_link_lock and 1 or 0, settings.env_inherit_shape and 1 or 0, settings.rand_noise and 1 or 0, settings.rand_osc and 1 or 0, settings.rand_chua and 1 or 0, settings.rand_sub and 1 or 0, settings.rand_hit and 1 or 0, settings.pad_preview_interval or 0.08
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
            elseif k == "rl" then settings.rand_link = (tonumber(v)==1)
            elseif k == "rll" then settings.rand_link_lock = (tonumber(v)==1)
            elseif k == "esh" then settings.env_inherit_shape = (tonumber(v)==1)
            elseif k == "rgn" then settings.rand_noise = (tonumber(v)==1)
            elseif k == "rgo" then settings.rand_osc = (tonumber(v)==1)
            elseif k == "rgc" then settings.rand_chua = (tonumber(v)==1)
            elseif k == "rgs" then settings.rand_sub = (tonumber(v)==1)
            elseif k == "rgh" then settings.rand_hit = (tonumber(v)==1)
            elseif k == "ppi" then settings.pad_preview_interval = Clamp(tonumber(v) or 0.08, 0, 0.5)
            end
        end
    end
    ValidateConfig()
end

function SerializeConfig()
    local str = ""
    for k, v in pairs(config) do
        if k ~= "current_preset" and type(v) ~= "table" then
            local val = tostring(v)
            if type(v) == "boolean" then val = v and "1" or "0" end
            str = str .. k .. "=" .. val .. "::"
        end
    end
    local function esc(s) return tostring(s or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("|", "%%7C") end
    for i=1,4 do
        local bd = (config.link_bindings or {})[i] or {}
        str = str .. string.format("lb%d=%d|%s|%s|%d|%d|%.12g|%.12g|%d::", i, bd.enabled and 1 or 0, esc(bd.fx_name), esc(bd.param_name), bd.axis or 0, bd.invert and 1 or 0, bd.min or 0, bd.max or 1, bd.auto_range == false and 0 or 1)
    end
    return str
end

function DeserializeAndApply(str)
    if not str then return end
    for k, v in string.gmatch(str, "(.-)=([^:]+)::") do
        if config[k] ~= nil and type(config[k]) ~= "table" then
            if type(config[k]) == "number" then config[k] = tonumber(v)
            elseif type(config[k]) == "boolean" then config[k] = (v == "1")
            else config[k] = v end
        end
    end
    local function unesc(s) return (s:gsub("%%7C", "|"):gsub("%%3A", ":"):gsub("%%25", "%%")) end
    local bindings = {}
    for idx, data in string.gmatch(str, "lb(%d)=([^:]+)::") do
        local en, fx, param, axis, inv, mn, mx, auto = data:match("^(%d+)|([^|]*)|([^|]*)|([%-%d]+)|(%d+)|([^|]+)|([^|]+)|(%d+)$")
        if en then bindings[tonumber(idx)] = {enabled=en=="1", fx_name=unesc(fx), param_name=unesc(param), axis=tonumber(axis) or 0, invert=inv=="1", min=tonumber(mn) or 0, max=tonumber(mx) or 1, auto_range=auto~="0"} end
    end
    if next(bindings) then config.link_bindings = bindings end
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
        local preset = FACTORY_PRESETS[name]
        if preset.engine_type ~= nil then SetEngineType(preset.engine_type) end
        for k,v in pairs(preset) do
            if k ~= "engine_type" then config[k] = type(v) == "table" and DeepCopy(v) or v end
        end
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
    local track = FindTrackByName(settings.track_name)
    local start_time, end_time = GetDesignTimeRange()
    if not track or end_time <= start_time then return end
    local fx = GetOrAddFX(track, FX_NAME)
    for _, param_idx in ipairs({IDX.global_pitch, IDX.audio_pitch}) do
        local env = r.GetFXEnvelope(track, fx, param_idx, false)
        if env then r.DeleteEnvelopePointRange(env, start_time - 0.001, end_time + 0.001); r.Envelope_SortPoints(env) end
    end
end

function RandomizeConfig()
    local function rf() return math.random() end
    if settings.rand_env then
        config.peak_pos = 0.2 + rf() * 0.6
        if settings.env_shape == 0 then
            config.tens_attack = (rf() * 2.0) - 1.0; config.tens_release = (rf() * 2.0) - 1.0
        elseif settings.env_shape == 1 then
            config.peak_pos = 0.75 + rf() * 0.25
            config.rise_curve = math.random(0, 3)
            config.rise_accel = rf()
            config.rise_dip = rf() * 0.65
            config.rise_release = 0.05 + rf() * 0.4
        end
    end
    if settings.rand_src then 
        local function source_point()
            local x, y = rf(), rf()
            -- Ext is the lower-right Source Mix quadrant.  Keep random points
            -- out of it when no external input is part of the sound design.
            if settings.rand_exclude_ext and x > 0.5 and y < 0.5 then y = 0.5 + rf() * 0.5 end
            return x, y
        end
        config.src_s_x, config.src_s_y = source_point(); config.src_p_x, config.src_p_y = source_point(); config.src_e_x, config.src_e_y = source_point()
    end
    if settings.rand_noise then
        config.noise_type = math.random(0,2); config.noise_tone = (rf() * 2) - 1; config.noise_routing = math.random(0, 1); config.noise_crackle_density = rf()
    end
    if settings.rand_osc then
        config.osc_shape_type = math.random(0,3)
        config.osc_pwm = rf(); config.osc_octave = math.floor(rf()*49)-24
        config.osc_detune = (rf() * 100) - 50
        config.osc_drive = rf() * 0.8; config.osc_tone = (rf() * 2) - 1; config.osc_unison_mix=rf(); config.osc_voice2_ratio=0.5+rf()*3.5; config.osc_phase_random=rf(); config.osc_drift=rf()*0.6
        config.osc_fm_amount=rf(); config.osc_fm_source=math.random(0,2); config.osc_fm_shape=math.random(0,2); config.osc_fm_ratio=0.25+rf()*7.75
    end
    if settings.rand_chua then config.chua_rate=0.005+rf()*0.3; config.chua_shape=10+rf()*35; config.chua_timbre=-20+rf()*40; config.chua_alpha=5+rf()*15 end
    if settings.rand_sub then config.sub_freq=30+math.floor(rf()*90); config.sub_sat=rf(); config.sub_vol=0.35+rf()*0.65 end
    if settings.rand_hit and (settings.engine_type == 3 or settings.engine_type == 4) then
        config.hit_enable=true; config.hit_level=0.45+rf()*0.55; config.hit_body=rf(); config.hit_sub=rf(); config.hit_crack=rf()*0.65; config.hit_crash=rf()*0.70; config.hit_decay=0.08+rf()*1.4; config.hit_tone=-1+rf()*2; config.hit_drive=rf()*0.8; config.hit_duck=rf()*0.65
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
    if settings.rand_link then
        -- Link gets a musically usable XY gesture: subdued start/end and a
        -- pronounced peak.  The bindings below target only engine parameters
        -- that no other performance pad writes automation for.
        config.link_s_x, config.link_s_y = rf(), rf() * 0.20
        config.link_p_x, config.link_p_y = 0.25 + rf() * 0.50, 0.55 + rf() * 0.45
        config.link_e_x, config.link_e_y = rf(), rf() * 0.25
        local track = FindTrackByName(settings.track_name)
        if track then
            local fx = GetOrAddFX(track, FX_NAME)
            if fx >= 0 then
                local _, engine_name = r.TrackFX_GetFXName(track, fx)
                if engine_name then
                    if not config.link_bindings or not settings.rand_link_lock then config.link_bindings = {} end
                    local used = {}
                    for _, bd in ipairs(config.link_bindings) do
                        if bd.enabled and bd.fx_name == engine_name and bd.param_name ~= "" then used[bd.param_name] = true end
                    end
                    local x_candidates = {
                        {idx=IDX.ring_freq, min=120, max=1800},
                        {idx=IDX.sat_drive, min=0.10, max=0.75},
                        {idx=IDX.crush_mix, min=0.08, max=0.65}
                    }
                    local y_candidates = {
                        {idx=IDX.ring_shape, min=0, max=1},
                        {idx=IDX.ring_metal, min=0.15, max=0.75},
                        {idx=IDX.flange_feed, min=0.05, max=0.45}
                    }
                    -- Build up to four bindings as X/Y pairs.  Selecting a new
                    -- random target never touches parameters already automated
                    -- by the dedicated performance pads.
                    for slot=1,4 do
                        local pool = (slot % 2 == 1) and x_candidates or y_candidates
                        local candidate = pool[math.random(1, #pool)]
                        local _, param_name = r.TrackFX_GetParamName(track, fx, candidate.idx)
                        local attempts = 0
                        while param_name and used[param_name] and attempts < #pool do
                            candidate = pool[(math.random(1, #pool))]
                            _, param_name = r.TrackFX_GetParamName(track, fx, candidate.idx)
                            attempts = attempts + 1
                        end
                        if param_name and not used[param_name] then
                            local free = nil
                            for i=1,4 do if not config.link_bindings[i] or not config.link_bindings[i].enabled then free=i; break end end
                            if free then
                                config.link_bindings[free] = {enabled=true, fx_name=engine_name, param_name=param_name, axis=(slot % 2 == 1) and 0 or 1, invert=(rf() > 0.5), min=candidate.min, max=candidate.max, auto_range=false}
                                used[param_name] = true
                            end
                        end
                    end
                    config.link_enable = true
                end
            end
        end
    end
end

-- A/B automation snapshots.  Points are kept in native FX-envelope units so
-- JSFX parameters with ranges other than 0..1 restore faithfully.
local function FindFXByName(track, name)
    if not track or not name then return -1 end
    for i=0, r.TrackFX_GetCount(track)-1 do local _, n = r.TrackFX_GetFXName(track, i); if n == name then return i end end
    return -1
end
local function ReadEnvelopePoints(env, t_s, t_e)
    local points = {}
    if not env then return points end
    for i=0, r.CountEnvelopePoints(env)-1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePoint(env, i)
        if ok and time >= t_s-0.001 and time <= t_e+0.001 then points[#points+1] = {time=time, value=value, shape=shape, tension=tension, selected=selected} end
    end
    return points
end
function CaptureVariationAutomation()
    local track = FindTrackByName(settings.track_name); if not track then return nil end
    local t_s, t_e = GetDesignTimeRange(); if t_e <= t_s then return nil end
    local fx = FindFXByName(track, FX_NAME); if fx < 0 then return nil end
    local snap = {track_name=settings.track_name, start_time=t_s, end_time=t_e, engine={}, external={}}
    for p=0, #ENGINE_PARAM_ORDER-1 do snap.engine[p+1] = ReadEnvelopePoints(r.GetFXEnvelope(track, fx, p, false), t_s, t_e) end
    for _, bd in ipairs(config.link_bindings or {}) do
        if bd.enabled and bd.fx_name ~= "" and bd.param_name ~= "" then
            local bfx = FindFXByName(track, bd.fx_name)
            if bfx >= 0 then
                for p=0, r.TrackFX_GetNumParams(track, bfx)-1 do
                    local _, pn = r.TrackFX_GetParamName(track, bfx, p)
                    if pn == bd.param_name then snap.external[#snap.external+1] = {fx_name=bd.fx_name, param_name=pn, points=ReadEnvelopePoints(r.GetFXEnvelope(track, bfx, p, false), t_s, t_e)}; break end
                end
            end
        end
    end
    return snap
end
function RestoreVariationAutomation(snap, previous_config)
    local track = FindTrackByName(snap.track_name or settings.track_name); if not track then return end
    local t_s, t_e = snap.start_time, snap.end_time; if not t_s or not t_e then return end
    local fx = FindFXByName(track, FX_NAME); if fx < 0 then return end
    local function clear_and_write(fx_idx, param_idx, points)
        local env = r.GetFXEnvelope(track, fx_idx, param_idx, false)
        if env then r.DeleteEnvelopePointRange(env, t_s-0.001, t_e+0.001) end
        if #points > 0 then
            env = r.GetFXEnvelope(track, fx_idx, param_idx, true)
            for _, pt in ipairs(points) do r.InsertEnvelopePoint(env, pt.time, pt.value, pt.shape, pt.tension, pt.selected, true) end
        end
        if env then r.Envelope_SortPoints(env) end
    end
    for p=0, #ENGINE_PARAM_ORDER-1 do clear_and_write(fx, p, snap.engine[p+1] or {}) end
    -- Clear both the recalled and the currently active Link targets, then
    -- restore only the points that belonged to the recalled snapshot.
    local ext_points = {}; local ext_targets = {}
    for _, ex in ipairs(snap.external or {}) do ext_points[ex.fx_name .. "\31" .. ex.param_name] = ex; ext_targets[ex.fx_name .. "\31" .. ex.param_name] = true end
    for _, bd in ipairs((previous_config and previous_config.link_bindings) or {}) do if bd.enabled then ext_targets[(bd.fx_name or "") .. "\31" .. (bd.param_name or "")] = true end end
    for key in pairs(ext_targets) do
        local fx_name, param_name = key:match("^(.-)\31(.*)$")
        local ex_fx = FindFXByName(track, fx_name)
        if ex_fx >= 0 then
            for p=0, r.TrackFX_GetNumParams(track, ex_fx)-1 do
                local _, pn = r.TrackFX_GetParamName(track, ex_fx, p)
                if pn == param_name then clear_and_write(ex_fx, p, (ext_points[key] and ext_points[key].points) or {}); break end
            end
        end
    end
    r.GetSet_LoopTimeRange(true, false, t_s, t_e, false)
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

-- Generic normalized envelope writer. Each point is {pos, value, shape, tension},
-- where pos is 0..1 within the selected time range.
function WriteEnvelopePoints(track, fx_idx, param_idx, t_s, t_e, points)
    if fx_idx < 0 or param_idx < 0 or not points or #points < 2 then return end
    local env = r.GetFXEnvelope(track, fx_idx, param_idx, true)
    if not env then return end
    SetEnvVisible(env)
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    local duration = math.max(0.000001, t_e - t_s)
    for _, point in ipairs(points) do
        local pos = Clamp(point[1] or 0, 0, 1)
        local value = Clamp(point[2] or 0, 0, 1)
        r.InsertEnvelopePoint(env, t_s + duration * pos, value, point[3] or 0, point[4] or 0, true, true)
    end
    r.Envelope_SortPoints(env)
end

local function WriteHitTriggerEnvelope(track, fx_idx, t_s, t_e)
    local env = r.GetFXEnvelope(track, fx_idx, IDX.hit_trigger, config.hit_enable == true)
    if not env then return end
    r.DeleteEnvelopePointRange(env, t_s - 0.001, t_e + 0.001)
    if not config.hit_enable then
        r.Envelope_SortPoints(env)
        return
    end
    local impact = t_s + (t_e - t_s) * Clamp(config.peak_pos or 0.97, 0, 1)
    impact = Clamp(impact, t_s + 0.001, t_e - 0.001)
    -- Offline stem rendering can evaluate FX automation in relatively large
    -- blocks.  A 4 ms pulse may fall wholly between two evaluations, leaving
    -- the Hit silent in Bounce.  Keep a short but renderer-safe gate instead;
    -- the JSFX fires only on its rising edge, so this does not lengthen Hit.
    local trigger_hold = 0.030
    r.InsertEnvelopePoint(env, t_s, 0, 0, 0, true, true)
    r.InsertEnvelopePoint(env, math.max(t_s, impact - 0.004), 0, 0, 0, true, true)
    r.InsertEnvelopePoint(env, impact, 1, 0, 0, true, true)
    r.InsertEnvelopePoint(env, math.min(t_e, impact + trigger_hold), 1, 0, 0, true, true)
    r.InsertEnvelopePoint(env, math.min(t_e, impact + trigger_hold + 0.002), 0, 0, 0, true, true)
    r.InsertEnvelopePoint(env, t_e, 0, 0, 0, true, true)
    r.Envelope_SortPoints(env)
end

local function RiseCurveValue(u)
    u = Clamp(u, 0, 1)
    local accel = Clamp(config.rise_accel or 0.65, 0, 1)
    local warped = u ^ (0.5 + accel * 4.5)
    local mode = math.floor(config.rise_curve or 0)
    if mode == 0 then return warped * warped end -- Exponential
    if mode == 1 then return warped end          -- Linear/time-warped
    if mode == 2 then return warped * warped * (3 - 2 * warped) end -- S-curve
    return math.sqrt(warped)                     -- Logarithmic
end

local function EvaluateRiseEnvelopeAt(pos, include_dip)
    local impact = Clamp(config.peak_pos or 0.9, 0.05, 1.0)
    if pos <= impact then
        local u = Clamp(pos / impact, 0, 1)
        local value = RiseCurveValue(u)
        if include_dip and u >= 0.72 and u < 1.0 then
            local triangle = 1 - math.abs(u - 0.88) / 0.12
            value = math.max(0, value - math.max(0, triangle) * Clamp(config.rise_dip or 0, 0, 1) * 0.55)
        end
        return value
    end
    if impact >= 0.999 then return 1 end
    local release_span = math.min(1 - impact, 0.005 + Clamp(config.rise_release or 0.15, 0, 1) * 0.075)
    local u = Clamp((pos - impact) / math.max(0.000001, release_span), 0, 1)
    return (1 - u) * (1 - u)
end

function BuildRiseEnvelopePoints(include_dip)
    if include_dip == nil then include_dip = true end
    local impact = Clamp(config.peak_pos or 0.9, 0.05, 1.0)
    local points, attack_steps = {}, 32
    for i = 0, attack_steps do
        local u = i / attack_steps
        local pos = impact * u
        points[#points + 1] = {pos, EvaluateRiseEnvelopeAt(pos, include_dip), 0, 0}
    end
    if impact < 0.999 then
        local release_span = math.min(1 - impact, 0.005 + Clamp(config.rise_release or 0.15, 0, 1) * 0.075)
        local release_steps = 8
        for i = 1, release_steps do
            local u = i / release_steps
            local pos = impact + release_span * u
            points[#points + 1] = {pos, EvaluateRiseEnvelopeAt(pos, include_dip), 0, 0}
        end
        if impact + release_span < 0.999 then points[#points + 1] = {1.0, 0.0, 0, 0} end
    end
    return points
end

function BuildRiseParameterPoints(v_start, v_impact, v_end)
    local impact = Clamp(config.peak_pos or 0.9, 0.05, 1.0)
    local source, result = BuildRiseEnvelopePoints(false), {}
    for _, point in ipairs(source) do
        local pos, value = point[1], point[2]
        if pos <= impact or impact >= 0.999 then
            value = v_start + (v_impact - v_start) * value
        else
            value = v_end + (v_impact - v_end) * value
        end
        result[#result + 1] = {pos, Clamp(value, 0, 1), 0, 0}
    end
    return result
end

function ClearPanAutomations(should_clear_surround)
    local track = FindTrackByName(settings.track_name)
    if not track then return end
    local fx = GetOrAddFX(track, FX_NAME)
        local start_time, end_time = GetDesignTimeRange()
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

local function SyncGeneratorMidiNoteLength(track, start_time, end_time)
    local target_end = end_time
    if settings.env_shape == 1 then
        -- Rise notes must extend through the short release, otherwise a dry
        -- generator is cut at the peak and the Release slider cannot be heard.
        local impact = Clamp(config.peak_pos or 0.97, 0.05, 1.0)
        local release_span = math.min(1 - impact, 0.005 + Clamp(config.rise_release or 0.15, 0, 1) * 0.075)
        target_end = start_time + (end_time - start_time) * (impact + release_span)
    end
    for item_idx = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, item_idx)
        local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if math.abs(item_start - start_time) < 0.001 and math.abs(item_end - end_time) < 0.001 then
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local _, note_count = r.MIDI_CountEvts(take)
                local target_ppq = r.MIDI_GetPPQPosFromProjTime(take, target_end)
                for note_idx = 0, note_count - 1 do
                    local ok, selected, muted, start_ppq, _, chan, pitch, vel = r.MIDI_GetNote(take, note_idx)
                    if ok and chan == 0 and pitch == 60 then
                        r.MIDI_SetNote(take, note_idx, selected, muted, start_ppq, target_ppq, chan, pitch, vel, true)
                    end
                end
                r.MIDI_Sort(take)
            end
        end
    end
end

function UpdateAutomationOnly(flags, target_track, target_start, target_end)
    local track = target_track or FindTrackByName(settings.track_name)
    if not track then return end
    local start_time, end_time
    if target_start and target_end then start_time, end_time = target_start, target_end
    else start_time, end_time = GetDesignTimeRange() end
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
    
    SyncEngineStaticParams(track, fx, length)
    SyncGeneratorMidiNoteLength(track, start_time, end_time)

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    r.SetOnlyTrackSelected(track)
    
    if flags == "all" or flags == "env" or flags == "vol" then
        if settings.env_shape == 1 then
            WriteEnvelopePoints(track, fx, IDX.env_val, start_time, end_time, BuildRiseEnvelopePoints())
        else
            Create3PointRampFX(track, fx, IDX.env_val, start_time, peak_time, end_time, 0.0, 1.0, 0.0,
                settings.env_shape, config.tens_attack, config.tens_release)
        end
        WriteHitTriggerEnvelope(track, fx, start_time, end_time)
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

                local filt_on = config.filter_enable ~= false
                Create3PointRampFX(track, fx, IDX.filt_morph_x, start_time, peak_time, end_time, filt_on and config.morph_s_x or 0.5, filt_on and config.morph_p_x or 0.5, filt_on and config.morph_e_x or 0.5, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_morph_y, start_time, peak_time, end_time, filt_on and config.morph_s_y or 0.5, filt_on and config.morph_p_y or 0.5, filt_on and config.morph_e_y or 0.5, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_freq, start_time, peak_time, end_time, filt_on and config.cut_s_x or 1.0, filt_on and config.cut_p_x or 1.0, filt_on and config.cut_e_x or 1.0, inherit_shape, inherit_ta, inherit_tr)
                Create3PointRampFX(track, fx, IDX.filt_res, start_time, peak_time, end_time, filt_on and config.cut_s_y*0.98 or 0, filt_on and config.cut_p_y*0.98 or 0, filt_on and config.cut_e_y*0.98 or 0, inherit_shape, inherit_ta, inherit_tr)

        if settings.output_mode == 0 then
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, config.spc_s_x, config.spc_p_x, config.spc_e_x, inherit_shape, inherit_ta, inherit_tr)
            local function GetDblRev(y, x) return y * (1-x), y * x end
            local d_s, r_s = GetDblRev(config.spc_s_y, config.spc_s_x)
            local d_p, r_p = GetDblRev(config.spc_p_y, config.spc_p_x)
            local d_e, r_e = GetDblRev(config.spc_e_y, config.spc_e_x)
            local space_on = config.space_enable ~= false
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, space_on and d_s or 0, space_on and d_p or 0, space_on and d_e or 0, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.verb_mix, start_time, peak_time, end_time, space_on and r_s or 0, space_on and r_p or 0, space_on and r_e or 0, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.pan_x, start_time, peak_time, end_time, config.dop_s_x, config.dop_p_x, config.dop_e_x, nil, 0, 0)
            -- Surround Path lanes are relevant only in Surround mode. Do not
            -- create them for Stereo projects; remove legacy points in this
            -- generated range without creating a new envelope.
            for _, param_idx in ipairs({IDX.sur_path_x, IDX.sur_path_y}) do
                local env = r.GetFXEnvelope(track, fx, param_idx, false)
                if env then
                    r.DeleteEnvelopePointRange(env, start_time - 0.001, end_time + 0.001)
                    r.Envelope_SortPoints(env)
                end
            end
        else
            local d_s, r_s = config.spc_s_y * (1-config.spc_s_x), config.spc_s_y * config.spc_s_x
            local d_p, r_p = config.spc_p_y * (1-config.spc_p_x), config.spc_p_y * config.spc_p_x
            local d_e, r_e = config.spc_e_y * (1-config.spc_e_x), config.spc_e_y * config.spc_e_x
            local space_on = config.space_enable ~= false
            Create3PointRampFX(track, fx, IDX.width, start_time, peak_time, end_time, space_on and config.spc_s_x or 0.5, space_on and config.spc_p_x or 0.5, space_on and config.spc_e_x or 0.5, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.dbl_mix, start_time, peak_time, end_time, space_on and d_s or 0, space_on and d_p or 0, space_on and d_e or 0, inherit_shape, inherit_ta, inherit_tr)
            Create3PointRampFX(track, fx, IDX.verb_mix, start_time, peak_time, end_time, space_on and r_s or 0, space_on and r_p or 0, space_on and r_e or 0, inherit_shape, inherit_ta, inherit_tr)

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

        if config.link_enable ~= false and config.link_bindings then
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
                            -- FX envelopes use the parameter's native range, while
                            -- the Link pad always stays 0..1.  Auto range makes a
                            -- JSFX slider such as 20..4000 Hz cover its full span.
                            local auto_range = bd.auto_range ~= false
                            local native_min, native_max = 0.0, 1.0
                            local _, pmin, pmax = r.TrackFX_GetParamEx(track, fx_idx, p_idx)
                            if pmin ~= nil and pmax ~= nil and pmax > pmin then native_min, native_max = pmin, pmax end
                            if auto_range then bd.min, bd.max = native_min, native_max end
                            local mn = bd.min or native_min; local mx = bd.max or native_max; local range = mx - mn
                            s = mn + s * range; p = mn + p * range; e = mn + e * range
                            Create3PointRampFX(track, fx_idx, p_idx, start_time, peak_time, end_time, s, p, e, inherit_shape, inherit_ta, inherit_tr)
                        end
                    end
                end
            end
        end

        if IDX.global_pitch >= 0 then
            if config.doppler_enable == false then
                Create3PointRampFX(track, fx, IDX.global_pitch, start_time, peak_time, end_time, 0, 0, 0)
                Create3PointRampFX(track, fx, IDX.audio_pitch, start_time, peak_time, end_time, 0, 0, 0)
            elseif config.pitch_mode == 3 then
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
    r.PreventUIRefresh(-1)
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
        local min_peak = (settings.env_shape == 1) and 0.5 or 0.1
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
    if settings.env_shape ~= 1 then
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
    end
    if settings.env_shape == 0 then 
        local function GetCPs(t, x1, y1, x2, y2) local mx, my = (x1+x2)*0.5, (y1+y2)*0.5; local str = math.abs(t) * 100; if t > 0 then return mx, my - str else return mx, my + str end end
        local c1x, c1y = GetCPs(-config.tens_attack, p_x, start_y, peak_x_vis, peak_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, p_x+10, start_y, c1x, c1y, c1x, c1y, peak_x_vis, peak_y, col_acc, 2, 20)
        local c2x, c2y = GetCPs(config.tens_release, peak_x_vis, peak_y, end_x, end_y)
        r.ImGui_DrawList_AddBezierCubic(draw_list, peak_x_vis, peak_y, c2x, c2y, c2x, c2y, end_x-10, end_y, col_acc, 2, 20)
    elseif settings.env_shape == 1 then
        local last_x, last_y = nil, nil
        for sample = 0, 128 do
            local pos = sample / 128
            local px = p_x + 10 + pos * (w - 20)
            local py = start_y - EvaluateRiseEnvelopeAt(pos, true) * (draw_h - 20)
            if last_x then r.ImGui_DrawList_AddLine(draw_list, last_x, last_y, px, py, col_acc, 2) end
            last_x, last_y = px, py
        end
        local range_start, range_end = GetDesignTimeRange()
        local rise_seconds = math.max(0, range_end - range_start) * Clamp(config.peak_pos or 0.97, 0.05, 1.0)
        local rise_text = rise_seconds < 1 and string.format("Rise: %.0f ms", rise_seconds * 1000) or string.format("Rise: %.2f s", rise_seconds)
        local text_w = r.ImGui_CalcTextSize(ctx, rise_text)
        r.ImGui_DrawList_AddRectFilled(draw_list, p_x + w - text_w - 18, p_y + 8, p_x + w - 8, p_y + 29, 0x181818D8, 5)
        r.ImGui_DrawList_AddText(draw_list, p_x + w - text_w - 13, p_y + 11, 0xE0E0E0FF, rise_text)
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
        if ResetSliderOnRightClick("tens_attack") then changed=true end
        r.ImGui_SetCursorScreenPos(ctx, p_x + w - slider_w - margin_side, y_pos); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv2, v2 = r.ImGui_SliderDouble(ctx, "##Rel", config.tens_release, -1, 1, "Rel: %.2f"); if rv2 then config.tens_release=v2; changed=true end
        if ResetSliderOnRightClick("tens_release") then changed=true end
        r.ImGui_PopStyleVar(ctx, 4); r.ImGui_PopStyleColor(ctx, 2)
    elseif settings.env_shape == 1 then
        local slider_w = math.min(112, (w - 100) / 3)
        local slider_y = p_y + draw_h - 35
        local gap = (w - slider_w * 3) * 0.25
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x444444FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), col_acc)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 1)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 16)
        r.ImGui_SetCursorScreenPos(ctx, p_x + gap, slider_y); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv_a, v_a = r.ImGui_SliderDouble(ctx, "##RiseAccelPreview", config.rise_accel or 0.65, 0, 1, "Accel %.2f")
        if rv_a then config.rise_accel=v_a; changed=true end
        if ResetSliderOnRightClick("rise_accel") then changed=true end
        r.ImGui_SetCursorScreenPos(ctx, p_x + gap * 2 + slider_w, slider_y); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv_d, v_d = r.ImGui_SliderDouble(ctx, "##RiseDipPreview", config.rise_dip or 0, 0, 1, "Dip %.2f")
        if rv_d then config.rise_dip=v_d; changed=true end
        if ResetSliderOnRightClick("rise_dip") then changed=true end
        r.ImGui_SetCursorScreenPos(ctx, p_x + gap * 3 + slider_w * 2, slider_y); r.ImGui_SetNextItemWidth(ctx, slider_w)
        local rv_r, v_r = r.ImGui_SliderDouble(ctx, "##RiseReleasePreview", config.rise_release or 0.15, 0, 1, "Release %.2f")
        if rv_r then config.rise_release=v_r; changed=true end
        if ResetSliderOnRightClick("rise_release") then changed=true end
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
    -- Extend the pad's input layer beyond its frame: endpoint handles can sit
    -- directly on an edge and should never leak a drag to the host window.
    local hit_margin = 12
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
        -- Use the exact rendered coordinates. `h` is a layout reservation,
        -- while draw_h is the visible pad height.
        local s_sc_x, s_sc_y = p_x + sx*w, p_y + (1-sy)*draw_h; local p_sc_x, p_sc_y = p_x + px*w, p_y + (1-py)*draw_h; local e_sc_x, e_sc_y = p_x + ex*w, p_y + (1-ey)*draw_h
        -- Comfortable handle pickup, while nearest-point selection below
        -- keeps closely spaced markers distinct.
        local hit_r = 12 * 12
        interaction.dragging_pad = p_idx
        local dist_s = (mx-s_sc_x)^2+(my-s_sc_y)^2; local dist_p = (mx-p_sc_x)^2+(my-p_sc_y)^2; local dist_e = (mx-e_sc_x)^2+(my-e_sc_y)^2
        local nearest_dist, nearest_point = dist_s, 1
        if dist_p < nearest_dist then nearest_dist, nearest_point = dist_p, 2 end
        if dist_e < nearest_dist then nearest_dist, nearest_point = dist_e, 3 end
        if nearest_dist <= hit_r then interaction.dragging_point = nearest_point
        else interaction.dragging_pad = nil; interaction.dragging_point = nil end
    end
    if not r.ImGui_IsMouseDown(ctx, 0) then interaction.dragging_pad = nil; interaction.dragging_point = nil end
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
            elseif p_idx==5 then config.spc_s_x,config.spc_s_y,config.spc_p_x,config.spc_p_y,config.spc_e_x,config.spc_e_y = sx,sy,px,py,ex,ey 
            elseif p_idx==6 then config.chop_s_x,config.chop_s_y,config.chop_p_x,config.chop_p_y,config.chop_e_x,config.chop_e_y = sx,sy,px,py,ex,ey
            elseif p_idx==7 then config.link_s_x,config.link_s_y,config.link_p_x,config.link_p_y,config.link_e_x,config.link_e_y = sx,sy,px,py,ex,ey end
        end
    end
    local s_x, s_y = p_x + sx*w, p_y + (1-sy)*draw_h; local p_x_d, p_y_d = p_x + px*w, p_y + (1-py)*draw_h; local e_x, e_y = p_x + ex*w, p_y + (1-ey)*draw_h
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
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.75, 0xFFFFFF15, 32, 1)
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.50, 0xFFFFFF20, 32, 1)
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, max_r * 0.35, 0xFFFFFF2A, 32, 1)
    end
    r.ImGui_DrawList_PopClipRect(draw_list)
    r.ImGui_DrawList_AddCircle(draw_list, s_x, s_y, 5, 0xAAAAAAFF, 12, 2); r.ImGui_DrawList_AddRectFilled(draw_list, p_x_d-4, p_y_d-4, p_x_d+4, p_y_d+4, 0xFFFFFFFF)
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
    local original_loop_start, original_loop_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local ts_start, ts_end = GetDesignTimeRange()
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
        if math.abs(item_pos - ts_start) < 0.01 and math.abs((item_pos + item_len) - (ts_end + tail_duration)) < 0.01 then
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
    local stem_channels = (settings.output_mode == 1) and 6 or 2
    local track_channels_required = stem_channels

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

    r.SetMediaTrackInfo_Value(stem_track, "I_NCHAN", stem_channels)

    local track_channels = r.GetMediaTrackInfo_Value(whoosh_track, "I_NCHAN")
    if track_channels ~= track_channels_required then r.SetMediaTrackInfo_Value(whoosh_track, "I_NCHAN", track_channels_required) end
    -- Re-write the Hit gate immediately before offline rendering.  Existing
    -- projects may still contain the legacy ultra-short trigger envelope.
    local fx = GetOrAddFX(whoosh_track, FX_NAME)
    local hit_range_end = has_ts and ts_end or math.max(render_start + 0.01, render_end - tail_duration)
    SyncEngineStaticParams(whoosh_track, fx, math.max(0.01, hit_range_end - render_start))
    WriteHitTriggerEnvelope(whoosh_track, fx, render_start, hit_range_end)
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
        r.GetSet_LoopTimeRange(true, false, original_loop_start, original_loop_end, false)
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
    r.GetSet_LoopTimeRange(true, false, original_loop_start, original_loop_end, false)
    r.PreventUIRefresh(-1); r.Undo_EndBlock("Bounce item to stem track", 0)
end

function GenerateWhoosh()
    if tail_preview.active then
        r.ShowMessageBox("Tail Preview is still active.\n\nTurn it off before creating a new Whoosh, then select the new timeline range.", "ReaWhoosh", 0)
        return
    end
    r.PreventUIRefresh(1)
    local source_start, source_end = GetDesignTimeRange()
    if source_start == source_end then r.ShowMessageBox("Select time!", "Error", 0); r.PreventUIRefresh(-1); return end
    local length = source_end - source_start
    local track = FindTrackByName(settings.track_name)
    if config.generate_mode == 2 then
        local base_name, suffix = settings.track_name:gsub(" %d+$", ""), 2
        local candidate = base_name .. " " .. suffix
        while FindTrackByName(candidate) do suffix = suffix + 1; candidate = base_name .. " " .. suffix end
        r.InsertTrackAtIndex(r.CountTracks(0), true)
        track = r.GetTrack(0, r.CountTracks(0)-1)
        r.GetSetMediaTrackInfo_String(track, "P_NAME", candidate, true)
        settings.track_name = candidate
    elseif not track then
        r.InsertTrackAtIndex(r.CountTracks(0), true)
        track = r.GetTrack(0, r.CountTracks(0)-1)
        r.GetSetMediaTrackInfo_String(track, "P_NAME", settings.track_name, true)
    end
    local start_time, end_time = source_start, source_end
    if config.generate_mode == 1 then
        local latest_end = source_end
        for i=0, r.CountTrackMediaItems(track)-1 do
            local old_item = r.GetTrackMediaItem(track, i)
            local _, tag = r.GetSetMediaItemInfo_String(old_item, "P_EXT:sbp_reawhoosh_generated", "", false)
            if tag == "1" then latest_end = math.max(latest_end, r.GetMediaItemInfo_Value(old_item, "D_POSITION") + r.GetMediaItemInfo_Value(old_item, "D_LENGTH")) end
        end
        start_time = latest_end + config.generate_gap; end_time = start_time + length
        tail_preview.active = false
        r.GetSet_LoopTimeRange(true, false, start_time, end_time, false)
    end
    r.SetMediaTrackInfo_Value(track, "I_NCHAN", settings.output_mode == 1 and 6 or 2)
    local fx = GetOrAddFX(track, FX_NAME)
    local item_count_before = r.CountTrackMediaItems(track)
    local item = r.CreateNewMIDIItemInProj(track, start_time, end_time, false)
    local function IsValidMediaItem(ptr)
        return type(ptr) == "userdata" and r.ValidatePtr2(0, ptr, "MediaItem*")
    end
    if not IsValidMediaItem(item) then
        -- Some REAPER builds/extensions can return a non-usable value even though
        -- the item was created. Resolve it from the destination track instead.
        local item_count_after = r.CountTrackMediaItems(track)
        if item_count_after > item_count_before then
            item = r.GetTrackMediaItem(track, item_count_after - 1)
        end
    end
    if not IsValidMediaItem(item) then
        r.ShowConsoleMsg("ReaWhoosh error: Could not resolve the newly created MIDI item.\n")
        r.PreventUIRefresh(-1)
        return
    end
    if config.generate_mode == 0 then
        -- A valid replacement exists now, so it is safe to delete only the
        -- overlapping items that were previously generated by ReaWhoosh.
        for i = r.CountTrackMediaItems(track) - 1, 0, -1 do
            local old_item = r.GetTrackMediaItem(track, i)
            if old_item ~= item then
                local _, tag = r.GetSetMediaItemInfo_String(old_item, "P_EXT:sbp_reawhoosh_generated", "", false)
                local pos = r.GetMediaItemInfo_Value(old_item, "D_POSITION")
                local len = r.GetMediaItemInfo_Value(old_item, "D_LENGTH")
                if tag == "1" and pos < end_time and (pos + len) > start_time then r.DeleteTrackMediaItem(track, old_item) end
            end
        end
    end
    r.SetMediaItemSelected(item, true)
    r.GetSetMediaItemInfo_String(item, "P_EXT:sbp_reawhoosh_generated", "1", true)
    local item_label = settings.env_shape == 1 and "ReaWhoosh • Rise" or settings.env_shape == 2 and "ReaWhoosh • Soft" or "ReaWhoosh • Whoosh"
    if config.hit_enable then item_label = item_label .. " + Hit" end
    r.GetSetMediaItemInfo_String(item, "P_NOTES", item_label, true)
    local take = r.GetActiveTake(item)
    if take then
        local note_end_time = end_time
        if settings.env_shape == 1 then
            note_end_time = start_time + (end_time - start_time) * Clamp(config.peak_pos or 0.97, 0.05, 1.0)
        end
        note_end_time = math.max(start_time + 0.001, math.min(end_time, note_end_time))
        local note_start_ppq = r.MIDI_GetPPQPosFromProjTime(take, start_time)
        local note_end_ppq = r.MIDI_GetPPQPosFromProjTime(take, note_end_time)
        r.MIDI_InsertNote(take, false, false, note_start_ppq, note_end_ppq, 0, 60, 100, false)
    end
    UpdateAutomationOnly("all", track, start_time, end_time)
    r.PreventUIRefresh(-1)
    ShowAllEnvelopes()
end

-- Compact right-side rack.  Generator detail lives here so new parameters no
-- longer force the main performance view to grow vertically.
local function DrawGeneratorRack()
    local changed, env_changed, hit_changed = false, false, false
    local function Slider(label, key, lo, hi, fmt)
        local row_x, row_y = r.ImGui_GetCursorPos(ctx)
        r.ImGui_TextDisabled(ctx, label)
        -- 105 + 170 px fits safely inside the 300 px Generator Rack.
        r.ImGui_SetCursorPos(ctx, row_x + 105, row_y)
        r.ImGui_SetNextItemWidth(ctx, 170)
        local rv, value = r.ImGui_SliderDouble(ctx, "##rack_"..key, config[key] or 0, lo, hi, fmt or "%.2f")
        if rv then config[key] = value; changed = true end
        if ResetSliderOnRightClick(key) then changed = true end
    end
    local function Toggle(label, key, inverted)
        local value = inverted and not config[key] or config[key]
        local rv, next_value = r.ImGui_Checkbox(ctx, label.."##"..key, value == true)
        if rv then config[key] = inverted and not next_value or next_value; changed = true end
    end
    -- ChildFlags_Border is unavailable in older ReaImGui builds.
    if r.ImGui_BeginChild(ctx, "GeneratorRack", 300, 0, 0) then
        local rack_green = 0x2D8C6DFF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), rack_green)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), LightenColor(rack_green, 1.12))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), DarkenColor(rack_green))
        r.ImGui_Text(ctx, "GENERATOR RACK")
        r.ImGui_TextDisabled(ctx, "Sound sources and impact design")
        r.ImGui_Separator(ctx)

        if r.ImGui_CollapsingHeader(ctx, "Noise##rack") then
            Toggle("Enabled", "mute_w", true)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local names = {"White", "Pink", "Crackle"}
            if r.ImGui_BeginCombo(ctx, "Type##noise", names[(config.noise_type or 0) + 1]) then
                for i, name in ipairs(names) do if r.ImGui_Selectable(ctx, name, config.noise_type == i-1) then config.noise_type=i-1; changed=true end end
                r.ImGui_EndCombo(ctx)
            end
            Slider("Color", "noise_tone", -1, 1)
            if config.noise_type == 2 then Slider("Crackle density", "noise_crackle_density", 0, 1) end
            r.ImGui_SetNextItemWidth(ctx, -1)
            local route = config.noise_routing == 1 and "Pitched" or "Clean"
            if r.ImGui_BeginCombo(ctx, "Routing##noise", route) then
                if r.ImGui_Selectable(ctx, "Clean", config.noise_routing==0) then config.noise_routing=0; changed=true end
                if r.ImGui_Selectable(ctx, "Pitched", config.noise_routing==1) then config.noise_routing=1; changed=true end
                r.ImGui_EndCombo(ctx)
            end
        end
        if r.ImGui_CollapsingHeader(ctx, "Oscillator##rack") then
            Toggle("Enabled", "mute_o", true)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local shapes = {"Sine", "Saw", "Square", "Triangle"}
            if r.ImGui_BeginCombo(ctx, "Shape##osc", shapes[(config.osc_shape_type or 0)+1]) then
                for i, name in ipairs(shapes) do if r.ImGui_Selectable(ctx, name, config.osc_shape_type==i-1) then config.osc_shape_type=i-1; changed=true end end
                r.ImGui_EndCombo(ctx)
            end
            Slider("Shift", "osc_octave", -24, 24, "%.1f st"); Slider("Color", "osc_tone", -1, 1)
            -- Sine has no PWM/shape stage; avoid showing controls that cannot
            -- affect the currently selected synthesis algorithm.
            if config.osc_shape_type ~= 0 then Slider("PWM / Shape", "osc_pwm", 0, 1) end
            Slider("Detune", "osc_detune", -50, 50, "%.1f ct"); Slider("Drive", "osc_drive", 0, 1)
            Slider("Unison mix", "osc_unison_mix", 0, 1); Slider("Voice 2 ratio", "osc_voice2_ratio", 0.5, 4.0, "%.2fx")
            Slider("Phase random", "osc_phase_random", 0, 1); Slider("Drift", "osc_drift", 0, 1)
            if config.osc_shape_type == 0 then
                Slider("FM amount", "osc_fm_amount", 0, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local fm_sources = {"OSC", "Sub", "Noise"}
                if r.ImGui_BeginCombo(ctx, "FM source##osc", fm_sources[(config.osc_fm_source or 0) + 1]) then
                    for i, name in ipairs(fm_sources) do if r.ImGui_Selectable(ctx, name, config.osc_fm_source == i-1) then config.osc_fm_source=i-1; changed=true end end
                    r.ImGui_EndCombo(ctx)
                end
                if config.osc_fm_source == 0 then
                    Slider("FM ratio", "osc_fm_ratio", 0.25, 8.0, "%.2fx")
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local fm_shapes = {"Sine", "Triangle", "Square"}
                    if r.ImGui_BeginCombo(ctx, "FM shape##osc", fm_shapes[(config.osc_fm_shape or 0) + 1]) then
                        for i, name in ipairs(fm_shapes) do if r.ImGui_Selectable(ctx, name, config.osc_fm_shape == i-1) then config.osc_fm_shape=i-1; changed=true end end
                        r.ImGui_EndCombo(ctx)
                    end
                end
            end
        end
        if r.ImGui_CollapsingHeader(ctx, "Chua / Chaos##rack") then
            Toggle("Enabled", "mute_c", true)
            Slider("Rate", "chua_rate", 0, 0.5); Slider("Shape", "chua_shape", 10, 45)
            Slider("Timbre", "chua_timbre", -20, 20); Slider("Alpha", "chua_alpha", 5, 20)
        end
        if r.ImGui_CollapsingHeader(ctx, "Sub##rack") then
            Toggle("Enabled", "sub_enable")
            local sub_x, sub_y = r.ImGui_GetCursorPos(ctx)
            r.ImGui_TextDisabled(ctx, "Base frequency")
            r.ImGui_SetCursorPos(ctx, sub_x + 105, sub_y); r.ImGui_SetNextItemWidth(ctx, 170)
            local rv, value = r.ImGui_SliderInt(ctx, "##sub_frequency", config.sub_freq or 55, 30, 120, "%d Hz")
            if rv then config.sub_freq=value; changed=true end
            if ResetSliderOnRightClick("sub_freq") then changed=true end
            Slider("Saturation", "sub_sat", 0, 1)
        end
        if r.ImGui_CollapsingHeader(ctx, "Hit / Impact##rack") then
            local hit_was_enabled = config.hit_enable
            Toggle("Enabled", "hit_enable")
            if hit_was_enabled ~= config.hit_enable then hit_changed = true end
            Slider("Body", "hit_body", 0, 1); Slider("Sub", "hit_sub", 0, 1); Slider("Crack", "hit_crack", 0, 1); Slider("Crash", "hit_crash", 0, 1)
            Slider("Decay", "hit_decay", 0.05, 2, "%.2f s"); Slider("Tone", "hit_tone", -1, 1)
            Slider("Drive", "hit_drive", 0, 1); Slider("Whoosh Duck", "hit_duck", 0, 1)
            Toggle("Bypass Chopper", "hit_chop_bypass"); r.ImGui_SameLine(ctx)
            Toggle("Bypass Panning", "hit_pan_bypass")
        end
        if r.ImGui_CollapsingHeader(ctx, "Pitch & Motion##rack") then
            r.ImGui_SetNextItemWidth(ctx, -1)
            local mode = ({"Pitch Shift", "Freq Shift", "Audio Pitch", "Physical Doppler"})[(config.pitch_mode or 0)+1]
            if r.ImGui_BeginCombo(ctx, "Doppler mode##rack", mode) then
                for i, name in ipairs({"Pitch Shift", "Freq Shift", "Audio Pitch", "Physical Doppler"}) do
                    if r.ImGui_Selectable(ctx, name, config.pitch_mode==i-1) then
                        if config.pitch_mode ~= i-1 and config.pitch_clear_on_mode_change then ResetPitchEnvelope() end
                        config.pitch_mode=i-1; changed=true
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            local clear_rv, clear_value = r.ImGui_Checkbox(ctx, "Clear old envelope on mode change##pitch", config.pitch_clear_on_mode_change == true)
            if clear_rv then config.pitch_clear_on_mode_change=clear_value; changed=true end
            local utility_c = 0x4A4A4AFF
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), utility_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(utility_c, 1.18))
            if r.ImGui_Button(ctx, "Reset pitch envelope##rack", -1) then ResetPitchEnvelope(); changed=true end
            r.ImGui_PopStyleColor(ctx, 2)
            if config.pitch_mode == 2 then
                r.ImGui_SetNextItemWidth(ctx, -1)
                local grain_name = ({"512 (Tiny)", "1024 (Short)", "2048 (Medium)", "4096 (Long)"})[(config.grain_size or 1)+1]
                if r.ImGui_BeginCombo(ctx, "Grain size##rack", grain_name) then
                    for i, name in ipairs({"512 (Tiny)", "1024 (Short)", "2048 (Medium)", "4096 (Long)"}) do if r.ImGui_Selectable(ctx, name, config.grain_size==i-1) then config.grain_size=i-1; changed=true end end
                    r.ImGui_EndCombo(ctx)
                end
            end
            if config.pitch_mode==3 then Slider("Air absorption", "doppler_air", 0, 1) end
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_EndChild(ctx)
    end
    return changed, env_changed, hit_changed
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
    -- 310 px generator rail + a fixed 1062 px performance workspace.
    r.ImGui_SetNextWindowSizeConstraints(ctx, 1402, 720, 1402, 720)
    
        local visible, open = r.ImGui_Begin(ctx, 'ReaWhoosh', true)
        -- Match REAPER's Space behavior: one press toggles transport, held key does not retrigger.
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space(), false) then
            if r.GetPlayState() ~= 0 then r.OnStopButton() else r.OnPlayButton() end
        end
        if visible then
        local changed_any = false; local changed_pads = false 
        
        r.ImGui_Text(ctx, "PRESETS:"); r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 200)
        if r.ImGui_BeginCombo(ctx, "##presets", config.current_preset) then
            if not USER_PRESETS then LoadUserPresets() end
            r.ImGui_TextDisabled(ctx, "-- Factory --")
            for _, name in ipairs(FACTORY_PRESET_ORDER) do if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any=true; changed_pads=true end end
            r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- User --")
            for name, _ in pairs(USER_PRESETS) do if r.ImGui_Selectable(ctx, name, config.current_preset == name) then ApplyPreset(name); changed_any=true end end
            r.ImGui_EndCombo(ctx) 
        end
        r.ImGui_SameLine(ctx); local add_c = 0x2D8C6DFF; r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), add_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(add_c))
        if r.ImGui_Button(ctx, "+", 24, 0) then SHOW_SAVE_MODAL = true; PRESET_INPUT_BUF = "My Preset"; DO_FOCUS_INPUT = true end
        r.ImGui_PopStyleColor(ctx, 2); r.ImGui_SameLine(ctx); local del_c = 0xCC4444FF; r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), del_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(del_c))
        if r.ImGui_Button(ctx, "-", 24, 0) then if USER_PRESETS[config.current_preset] then DeleteUserPreset(config.current_preset); changed_any = true end end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_SameLine(ctx); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4A4A4AFF); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(0x4A4A4AFF, 1.18))
        if r.ImGui_Button(ctx, "Variations", 82, 0) then r.ImGui_OpenPopup(ctx, "Variations") end
        r.ImGui_PopStyleColor(ctx, 2)
        if r.ImGui_BeginPopup(ctx, "Variations") then
            r.ImGui_TextDisabled(ctx, "A/B design snapshots — not saved after closing the script")
            local a_name = variation_slots.A and "A: captured" or "A: empty"
            local b_name = variation_slots.B and "B: captured" or "B: empty"
            r.ImGui_Text(ctx, a_name)
            if r.ImGui_Button(ctx, "Capture A", 90, 0) then CaptureVariation("A") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Recall A", 90, 0) then if RecallVariation("A") then changed_any=true end end
            r.ImGui_Text(ctx, b_name)
            if r.ImGui_Button(ctx, "Capture B", 90, 0) then CaptureVariation("B") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Recall B", 90, 0) then if RecallVariation("B") then changed_any=true end end
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, "Duplicate A -> B", 180, 0) then DuplicateVariation("A", "B") end
            if r.ImGui_Button(ctx, "Duplicate B -> A", 180, 0) then DuplicateVariation("B", "A") end
            r.ImGui_EndPopup(ctx)
        end
        
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
                    if ResetSliderOnRightClick("chop_shape") then changed_any=true end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Pad Live Preview --")
                    local preview_intervals = {0, 0.04, 0.08, 0.15, 0.25}
                    local preview_labels = {"Off (release only)", "Fast — 40 ms", "Balanced — 80 ms", "Smooth — 150 ms", "Light — 250 ms"}
                    local preview_idx = 3
                    local preview_value = settings.pad_preview_interval or 0.08
                    for i, value in ipairs(preview_intervals) do if math.abs(preview_value - value) < 0.001 then preview_idx=i; break end end
                    r.ImGui_SetNextItemWidth(ctx, 220)
                    if r.ImGui_BeginCombo(ctx, "Pad preview update", preview_labels[preview_idx]) then
                        for i, label in ipairs(preview_labels) do
                            if r.ImGui_Selectable(ctx, label, preview_idx == i) then settings.pad_preview_interval=preview_intervals[i]; SaveSettings() end
                        end
                        r.ImGui_EndCombo(ctx)
                    end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Reverb Routing --")
                    local reverb_positions = {"Post Envelope", "Pre Envelope / Diffuser", "Pre Filter"}
                    local reverb_position = math.floor(Clamp(config.reverb_position or 0, 0, 2) + 0.5)
                    r.ImGui_SetNextItemWidth(ctx, 220)
                    if r.ImGui_BeginCombo(ctx, "Reverb position", reverb_positions[reverb_position + 1]) then
                        for i, name in ipairs(reverb_positions) do if r.ImGui_Selectable(ctx, name, reverb_position == i-1) then config.reverb_position=i-1; changed_any=true end end
                        r.ImGui_EndCombo(ctx)
                    end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Randomization Targets --")
                    local _, b1 = r.ImGui_Checkbox(ctx, "Source Mix", settings.rand_src); if _ then settings.rand_src=b1 end
                    r.ImGui_SameLine(ctx); local _, bx = r.ImGui_Checkbox(ctx, "Exclude External sector", settings.rand_exclude_ext); if _ then settings.rand_exclude_ext=bx end
                    r.ImGui_SameLine(ctx); local _, b2 = r.ImGui_Checkbox(ctx, "Morph Filter", settings.rand_morph); if _ then settings.rand_morph=b2 end
                    r.ImGui_SameLine(ctx); local _, b3 = r.ImGui_Checkbox(ctx, "Cut/Res", settings.rand_filt); if _ then settings.rand_filt=b3 end
                    local _, b4 = r.ImGui_Checkbox(ctx, "Doppler", settings.rand_dop); if _ then settings.rand_dop=b4 end
                    r.ImGui_SameLine(ctx); local _, b5 = r.ImGui_Checkbox(ctx, "Space (FX)", settings.rand_space); if _ then settings.rand_space=b5 end
                    r.ImGui_SameLine(ctx); local _, b6 = r.ImGui_Checkbox(ctx, "Chopper", settings.rand_chop); if _ then settings.rand_chop=b6 end
                    local _, b7 = r.ImGui_Checkbox(ctx, "Volume Env", settings.rand_env); if _ then settings.rand_env=b7 end
                    r.ImGui_SameLine(ctx); local _, b8 = r.ImGui_Checkbox(ctx, "Surround Path", settings.rand_surround); if _ then settings.rand_surround=b8 end
                    r.ImGui_SameLine(ctx); local _, b9 = r.ImGui_Checkbox(ctx, "Link ext.", settings.rand_link); if _ then settings.rand_link=b9 end
                    r.ImGui_SameLine(ctx); local _, b10 = r.ImGui_Checkbox(ctx, "Lock Link targets", settings.rand_link_lock); if _ then settings.rand_link_lock=b10 end
                    local _, rg_noise = r.ImGui_Checkbox(ctx, "Noise generator", settings.rand_noise); if _ then settings.rand_noise=rg_noise end
                    r.ImGui_SameLine(ctx); local _, rg_osc = r.ImGui_Checkbox(ctx, "Osc generator", settings.rand_osc); if _ then settings.rand_osc=rg_osc end
                    r.ImGui_SameLine(ctx); local _, rg_chua = r.ImGui_Checkbox(ctx, "Chua generator", settings.rand_chua); if _ then settings.rand_chua=rg_chua end
                    r.ImGui_SameLine(ctx); local _, rg_sub = r.ImGui_Checkbox(ctx, "Sub generator", settings.rand_sub); if _ then settings.rand_sub=rg_sub end
                    r.ImGui_SameLine(ctx); local _, rg_hit = r.ImGui_Checkbox(ctx, "Hit / Impact", settings.rand_hit); if _ then settings.rand_hit=rg_hit end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Generation Settings --")
                    local rv_gap, v_gap = r.ImGui_SliderDouble(ctx, "Next timeline gap", config.generate_gap or 0.10, 0, 10, "%.2f s")
                    if rv_gap then config.generate_gap=v_gap; changed_any=true end
                    if ResetSliderOnRightClick("generate_gap") then changed_any=true end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Bounce Settings --")
                    local rv_tail, v_tail = r.ImGui_SliderDouble(ctx, "Bounce Tail (seconds)", config.bounce_tail or 0.5, 0.0, 3.0, "%.2f"); if rv_tail then config.bounce_tail = v_tail; changed_any = true end
                    if ResetSliderOnRightClick("bounce_tail") then changed_any=true end
                    r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx, "-- Preview Settings --")
                    local rv_preview, v_preview = r.ImGui_SliderDouble(ctx, "Tail Preview (seconds)", config.tail_preview_seconds or 2.0, 0.1, 10.0, "%.1f s")
                    if rv_preview then
                        config.tail_preview_seconds = v_preview
                        RefreshTailPreviewRange()
                    end
                    if ResetSliderOnRightClick("tail_preview_seconds") then changed_any=true; RefreshTailPreviewRange() end
                    if r.ImGui_Button(ctx, "Close") then SaveSettings(); r.ImGui_CloseCurrentPopup(ctx) end
                    r.ImGui_EndPopup(ctx)
                end

        local sur_changed, sur_path_changed = DrawSurroundWindow(ctx, r, settings, config, c_acc)
        if sur_changed then
            changed_any = true
            if sur_path_changed then surround_env_dirty = true end
        end

        r.ImGui_Separator(ctx)
        if r.ImGui_BeginTable(ctx, "WorkspaceShell", 2, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "GeneratorRail", r.ImGui_TableColumnFlags_WidthFixed(), 310)
            r.ImGui_TableSetupColumn(ctx, "Workspace", r.ImGui_TableColumnFlags_WidthFixed(), 1062)
            r.ImGui_TableNextColumn(ctx)
            local rack_changed, rack_env_changed, rack_hit_changed = DrawGeneratorRack()
            if rack_changed then changed_any = true end
            if rack_env_changed then changed_pads = true end
            if rack_hit_changed then changed_pads = true end
            r.ImGui_TableNextColumn(ctx)

        if r.ImGui_BeginTable(ctx, "MainTable", 2, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableSetupColumn(ctx, "PadGrid", r.ImGui_TableColumnFlags_WidthFixed(), PAD_SQUARE * 3 + 30)
            r.ImGui_TableSetupColumn(ctx, "EnvMix", r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
            r.ImGui_TableNextColumn(ctx); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 0, 0)
            if r.ImGui_BeginTable(ctx, "PadsGrid3x3", 3, r.ImGui_TableFlags_SizingStretchProp()) then
                local function PadCell(title, id, pad_idx, enable_key)
                    if enable_key then
                        local rv, value = r.ImGui_Checkbox(ctx, "##pad_enable_"..enable_key, config[enable_key] == true)
                        if rv then config[enable_key]=value; changed_any=true; changed_pads=true end
                        r.ImGui_SameLine(ctx, 0, 4); r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, title)
                    else
                        r.ImGui_Text(ctx, title)
                    end
                    if DrawVectorPad(id, pad_idx, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true; changed_pads=true end
                end
                r.ImGui_TableNextColumn(ctx); PadCell("Source Mix", "##src", 1); r.ImGui_TableNextColumn(ctx); PadCell("Morph Filter", "##morph", 2)
                r.ImGui_TableNextColumn(ctx); PadCell("Doppler Pad", "##doppler", 4, "doppler_enable"); r.ImGui_TableNextColumn(ctx); PadCell("Space Pad", "##space", 5, "space_enable")
                r.ImGui_TableNextColumn(ctx); PadCell("Cut / Res", "##cut", 3, "filter_enable"); r.ImGui_TableNextColumn(ctx); PadCell("Chopper", "##granular", 6, "chop_enable")
                r.ImGui_EndTable(ctx)
            end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_TableNextColumn(ctx); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0); local right_w = r.ImGui_GetContentRegionAvail(ctx)
            if r.ImGui_BeginChild(ctx, "EnvBlock", 0, PAD_SQUARE + 24, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_Text(ctx, " Volume Envelope")
                if DrawEnvelopePreview(right_w, PAD_SQUARE - 20, c_acc) then
                    changed_any=true
                    pads_dirty=true -- commit the heavier multi-envelope Rise update on mouse release
                end
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_Dummy(ctx, 0, 2); local mm_h = PAD_SQUARE + 24
            if r.ImGui_BeginChild(ctx, "MeterMixBlock", 0, mm_h, 0, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 0)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 0)
                if r.ImGui_BeginTable(ctx, "StereoMixerRow", 2, r.ImGui_TableFlags_SizingStretchProp()) then
                    r.ImGui_TableSetupColumn(ctx, "StereoCol", r.ImGui_TableColumnFlags_WidthStretch())
                    r.ImGui_TableSetupColumn(ctx, "MixerCol", r.ImGui_TableColumnFlags_WidthStretch())
                    r.ImGui_TableNextColumn(ctx)
                    local link_rv, link_value = r.ImGui_Checkbox(ctx, "##link_enable", config.link_enable ~= false)
                    if link_rv then config.link_enable = link_value; changed_any=true; changed_pads=true end
                    r.ImGui_SameLine(ctx, 0, 4); r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "Link ext. parameters")
                    r.ImGui_Dummy(ctx, 0, 2)
                    if DrawVectorPad("##link", 7, PAD_SQUARE, PAD_SQUARE, c_acc, c_bg) then changed_any=true; changed_pads=true end
                    
                    if r.ImGui_BeginPopupContextItem(ctx, "##link_ctx") then
                        r.ImGui_TextDisabled(ctx, "Link Configuration (Up to 4)"); r.ImGui_Separator(ctx)
                        local track = FindTrackByName(settings.track_name)
                        if track then
                            if not config.link_bindings then config.link_bindings = {} end
                            for i=1,4 do
                                if not config.link_bindings[i] then config.link_bindings[i] = {enabled=false, fx_name="", param_name="", axis=0, invert=false, min=0.0, max=1.0, auto_range=true} end
                                local bd = config.link_bindings[i]; if bd.min == nil then bd.min = 0.0 end; if bd.max == nil then bd.max = 1.0 end; if bd.auto_range == nil then bd.auto_range=true end
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
                                        -- Keep REAPER's real parameter indices, but present their names
                                        -- alphabetically so the binding menu remains easy to navigate.
                                        local params = {}
                                        for p=0, p_cnt-1 do
                                            local _, pnm = r.TrackFX_GetParamName(track, fx_idx, p)
                                            params[#params+1] = { index=p, name=pnm }
                                        end
                                        table.sort(params, function(a, b)
                                            return a.name:lower() < b.name:lower()
                                        end)
                                        for _, entry in ipairs(params) do
                                            local p, pnm = entry.index, entry.name
                                            if r.ImGui_Selectable(ctx, pnm, bd.param_name==pnm) then
                                                bd.param_name=pnm; bd.auto_range=true
                                                local _, pmin, pmax = r.TrackFX_GetParamEx(track, fx_idx, p)
                                                if pmin ~= nil and pmax ~= nil and pmax > pmin then bd.min=pmin; bd.max=pmax end
                                                changed_any=true
                                            end
                                        end
                                    else r.ImGui_TextDisabled(ctx, "FX not found") end
                                    r.ImGui_EndCombo(ctx)
                                end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 40)
                                if r.ImGui_BeginCombo(ctx, "##ax", bd.axis==0 and "X" or "Y") then
                                    if r.ImGui_Selectable(ctx, "X", bd.axis==0) then bd.axis=0; changed_any=true end; if r.ImGui_Selectable(ctx, "Y", bd.axis==1) then bd.axis=1; changed_any=true end; r.ImGui_EndCombo(ctx)
                                end
                                r.ImGui_SameLine(ctx); local _, inv = r.ImGui_Checkbox(ctx, "Inv", bd.invert); if _ then bd.invert=inv; changed_any=true end
                                r.ImGui_SameLine(ctx); local _, auto = r.ImGui_Checkbox(ctx, "Auto", bd.auto_range); if _ then bd.auto_range=auto; changed_any=true end
                                r.ImGui_SameLine(ctx); r.ImGui_TextDisabled(ctx, "|"); r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
                                local rv_min, v_min = r.ImGui_DragDouble(ctx, "##min", bd.min, 0.01, -100000, 100000, "Min=%.2f"); if rv_min then bd.min = v_min; bd.auto_range=false; if bd.min > bd.max then bd.min=bd.max end; changed_any=true end
                                r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
                                local rv_max, v_max = r.ImGui_DragDouble(ctx, "##max", bd.max, 0.01, -100000, 100000, "Max=%.2f"); if rv_max then bd.max = v_max; bd.auto_range=false; if bd.max < bd.min then bd.max=bd.min end; changed_any=true end
                                r.ImGui_PopID(ctx)
                            end
                        else r.ImGui_TextDisabled(ctx, "Track not found") end
                        r.ImGui_EndPopup(ctx)
                    end

                    r.ImGui_TableNextColumn(ctx)
                    local s_w, s_m, s_b = 16, 7, 24 
                    local function DrawStrip(lbl, val, state_bool, meter_idx, is_sub, max_value)
                        r.ImGui_BeginGroup(ctx)
                        local w = r.ImGui_CalcTextSize(ctx, lbl); local center_pos = r.ImGui_GetCursorPosX(ctx) + (s_b - w) / 2
                        r.ImGui_SetCursorPosX(ctx, center_pos); r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, lbl); r.ImGui_Dummy(ctx, 0, 2)
                        r.ImGui_PushID(ctx, lbl); r.ImGui_SetNextItemWidth(ctx, s_w)
                        local strip_max = max_value or 1.35
                        local rv, v = r.ImGui_VSliderDouble(ctx, "##v", s_w, MIX_H, val, 0, strip_max, "")
                        if rv then val=v; changed_any=true end
                        r.ImGui_PopID(ctx); r.ImGui_SameLine(ctx, 0, 2)
                        local m_val = tonumber(r.gmem_read(meter_idx)) or 0; local m_norm = math.min(m_val * 0.75, 1.0)
                        r.ImGui_Dummy(ctx, s_m, MIX_H); local p_min_x, p_min_y = r.ImGui_GetItemRectMin(ctx); local p_max_x, p_max_y = r.ImGui_GetItemRectMax(ctx); local dlm = r.ImGui_GetWindowDrawList(ctx)
                        r.ImGui_DrawList_AddRectFilled(dlm, p_min_x, p_min_y, p_max_x, p_max_y, 0x111111FF)
                        local fill_h = (p_max_y - p_min_y) * m_norm; local col = 0x2D8C6DFF; if m_norm > 0.75 then col = 0xCC4444FF end
                        r.ImGui_DrawList_AddRectFilled(dlm, p_min_x, p_max_y - fill_h, p_max_x, p_max_y, col)
                        local db0_norm = 1.0 / strip_max; local marker_y = p_max_y - (p_max_y - p_min_y) * db0_norm; r.ImGui_DrawList_AddLine(dlm, p_min_x, marker_y, p_max_x, marker_y, 0xFFFFFF60, 1)
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
                    -- External sources can arrive below generator level after
                    -- a safe stereo-to-mono fold-down. Give Ext dedicated
                    -- makeup headroom up to +12 dB (4.0 linear).
                    config.trim_e, config.mute_e = DrawStrip("Ext", config.trim_e, config.mute_e, 3, false, 4.0); r.ImGui_SameLine(ctx, 0, 4)
                    config.sub_vol, config.sub_enable = DrawStrip("Sub", config.sub_vol, config.sub_enable, 7, true)
                    r.ImGui_SameLine(ctx, 0, 4)
                    local old_hit_enabled = config.hit_enable
                    config.hit_level, config.hit_enable = DrawStrip("Hit", config.hit_level, config.hit_enable, 8, true, 2.0)
                    if old_hit_enabled ~= config.hit_enable then changed_pads = true end
                    r.ImGui_SameLine(ctx, 0, 8); r.ImGui_BeginGroup(ctx)
                    local mst_lbl = "Mst"; local s_w_mst, s_h_mst = 36, MIX_H + 24 
                    local w_m = r.ImGui_CalcTextSize(ctx, mst_lbl); local center_m = r.ImGui_GetCursorPosX(ctx) + (s_w_mst - w_m) / 2
                    r.ImGui_SetCursorPosX(ctx, center_m); r.ImGui_Text(ctx, mst_lbl)
                    r.ImGui_PushID(ctx, "Mst"); local is_surround = (settings.output_mode == 1); local ch_count = is_surround and 6 or 2
                    r.ImGui_InvisibleButton(ctx, "##mst_hit", s_w_mst, s_h_mst)
                    local hit_active = r.ImGui_IsItemActive(ctx); local hit_hover = r.ImGui_IsItemHovered(ctx)
                    local min_x, min_y = r.ImGui_GetItemRectMin(ctx); local max_x, max_y = r.ImGui_GetItemRectMax(ctx); local dlm = r.ImGui_GetWindowDrawList(ctx)
                    r.ImGui_DrawList_AddRectFilled(dlm, min_x, min_y, max_x, max_y, 0x111111FF, 4)
                    local h = max_y - min_y; local gap = 1; local bar_w = (s_w_mst - (ch_count + 1) * gap) / ch_count
                    local m_min_db, m_max_db = -60, 20
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
                    if hit_hover and r.ImGui_IsMouseClicked(ctx, 1) then settings.master_vol = -6.0; changed_any = true end
                    if hit_hover and r.ImGui_IsMouseReleased(ctx, 0) and not hit_active then local my = select(2, r.ImGui_GetMousePos(ctx)); local norm = Clamp((max_y - my) / h, 0, 1); local v = m_min_db + norm * (m_max_db - m_min_db); if v ~= settings.master_vol then settings.master_vol = v; changed_any = true end end
                    r.ImGui_PopID(ctx); r.ImGui_EndGroup(ctx)
                    r.ImGui_SameLine(ctx, 0, 20); r.ImGui_BeginGroup(ctx)
                    -- 170 px reaches the same right boundary as the envelope block.
                    r.ImGui_Text(ctx, "Scope"); r.ImGui_Dummy(ctx, 0, 2); local an_w, an_h = 170, 150; r.ImGui_Dummy(ctx, an_w, an_h)
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
                r.ImGui_EndTable(ctx); r.ImGui_PopStyleVar(ctx); r.ImGui_PopStyleVar(ctx); r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx, 1); r.ImGui_EndTable(ctx)
        end

        if r.ImGui_BeginTable(ctx, "BotGrid", 1, r.ImGui_TableFlags_SizingStretchProp()) then
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 3)
            if r.ImGui_BeginTable(ctx, "EffectsStrip", 3, r.ImGui_TableFlags_SizingStretchProp()) then
                r.ImGui_TableSetupColumn(ctx, "Character", r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
                r.ImGui_TableSetupColumn(ctx, "Space", r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
                r.ImGui_TableSetupColumn(ctx, "Actions", r.ImGui_TableColumnFlags_WidthFixed(), 205)
                local function FxSlider(label, key, lo, hi, fmt)
                    local row_x, row_y = r.ImGui_GetCursorPos(ctx)
                    r.ImGui_TextDisabled(ctx, label)
                    -- Fixed label and control columns make both effect banks read as one grid.
                    r.ImGui_SetCursorPos(ctx, row_x + 118, row_y)
                    r.ImGui_SetNextItemWidth(ctx, 300)
                    local rv, value = r.ImGui_SliderDouble(ctx, "##"..key, config[key] or 0, lo, hi, fmt or "%.2f")
                    if rv then config[key]=value; changed_any=true end
                    if ResetSliderOnRightClick(key) then changed_any=true end
                end
                r.ImGui_TableNextColumn(ctx); r.ImGui_TextDisabled(ctx, "COLOR / CHARACTER")
                FxSlider("Saturation drive", "sat_drive", 0, 1); FxSlider("Bitcrusher mix", "crush_mix", 0, 1)
                FxSlider("Bitcrusher rate", "crush_rate", 0.1, 1); FxSlider("Punch", "punch_amt", 0, 1); FxSlider("Ring metal", "ring_metal", 0, 1)
                FxSlider("Ring frequency", "ring_freq", 20, 4000, "%.0f Hz"); FxSlider("Ring shape", "ring_shape", 0, 1)
                r.ImGui_TableNextColumn(ctx); r.ImGui_TextDisabled(ctx, "SPACE / WIDTH")
                FxSlider("Flanger mix", "flange_wet", 0, 1); FxSlider("Flanger feedback", "flange_feed", 0, 1)
                FxSlider("Doubler spread", "dbl_wide", 0, 1)
                local delay_x, delay_y = r.ImGui_GetCursorPos(ctx)
                r.ImGui_TextDisabled(ctx, "Doubler delay"); r.ImGui_SetCursorPos(ctx, delay_x + 118, delay_y); r.ImGui_SetNextItemWidth(ctx, 300)
                local dbl_rv, dbl_value = r.ImGui_SliderInt(ctx, "##dbl_time", config.dbl_time or 30, 10, 60, "%d ms")
                if dbl_rv then config.dbl_time=dbl_value; changed_any=true end
                if ResetSliderOnRightClick("dbl_time") then changed_any=true end
                FxSlider("Reverb damp", "rev_damp", 0, 1); FxSlider("Reverb tail", "verb_tail", 0, 1); FxSlider("Reverb size", "verb_size", 0, 1)
                r.ImGui_TableNextColumn(ctx); r.ImGui_TextDisabled(ctx, "ACTIONS")
                r.ImGui_SetNextItemWidth(ctx, -1)
                local env_name = EngineTypeName()
                if r.ImGui_BeginCombo(ctx, "##envelope_shape_actions", env_name) then
                    if r.ImGui_Selectable(ctx, "Whoosh (Bezier)", settings.engine_type==0) then SetEngineType(0); changed_any=true; changed_pads=true end
                    if r.ImGui_Selectable(ctx, "Rise", settings.engine_type==1) then SetEngineType(1); config.peak_pos=math.max(config.peak_pos or 0.6, 0.85); changed_any=true; changed_pads=true end
                    if r.ImGui_Selectable(ctx, "Soft (slow)", settings.engine_type==2) then SetEngineType(2); changed_any=true; changed_pads=true end
                    if r.ImGui_Selectable(ctx, "Whoosh + Hit", settings.engine_type==3) then SetEngineType(3); changed_any=true; changed_pads=true end
                    if r.ImGui_Selectable(ctx, "Rise + Hit", settings.engine_type==4) then SetEngineType(4); config.peak_pos=math.max(config.peak_pos or 0.6, 0.85); changed_any=true; changed_pads=true end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_SetNextItemWidth(ctx, -1)
                local generate_name = config.generate_mode == 0 and "Replace current" or config.generate_mode == 1 and "Next timeline slot" or "New layer track"
                if r.ImGui_BeginCombo(ctx, "##generate_mode_actions", generate_name) then
                    if r.ImGui_Selectable(ctx, "Replace current", config.generate_mode == 0) then config.generate_mode=0; changed_any=true end
                    if r.ImGui_Selectable(ctx, "Next timeline slot", config.generate_mode == 1) then config.generate_mode=1; changed_any=true end
                    if r.ImGui_Selectable(ctx, "New layer track", config.generate_mode == 2) then config.generate_mode=2; changed_any=true end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_Separator(ctx)
                local rand_c = 0xD46A3FFF
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rand_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(rand_c))
                if r.ImGui_Button(ctx, "Randomize##actions", 96, 28) then RandomizeConfig(); changed_any=true end
                r.ImGui_PopStyleColor(ctx, 2); r.ImGui_SameLine(ctx)
                local utility_c = 0x4A4A4AFF
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), utility_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(utility_c, 1.18))
                if r.ImGui_Button(ctx, "Toggle Envs##actions", 101, 28) then ToggleEnvelopes() end
                r.ImGui_PopStyleColor(ctx, 2)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c_acc); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), DarkenColor(c_acc))
                if r.ImGui_Button(ctx, "GENERATE##actions", 205, 42) then GenerateWhoosh() end
                r.ImGui_PopStyleColor(ctx, 2)
                local preview_label = tail_preview.active and "TAIL PREVIEW: ON" or "TAIL PREVIEW"
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), utility_c); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(utility_c, 1.18))
                if r.ImGui_Button(ctx, preview_label.."##actions", 205, 25) then ToggleTailPreview() end
                r.ImGui_PopStyleColor(ctx, 2)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_MUTE_ACTIVE); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), LightenColor(C_MUTE_ACTIVE, 1.08))
                if r.ImGui_Button(ctx, "BOUNCE##actions", 205, 34) then BounceToNewTrack() end
                r.ImGui_PopStyleColor(ctx, 2)
                r.ImGui_EndTable(ctx)
                end
                r.ImGui_PopStyleVar(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_EndTable(ctx)
        end

        if changed_any then 
            local track = FindTrackByName(settings.track_name)
            if track then
                local fx = GetOrAddFX(track, FX_NAME)
                local sel_start, sel_end = GetDesignTimeRange()
                SyncEngineStaticParams(track, fx, sel_end > sel_start and (sel_end - sel_start) or 1.5)
            end
            
            if variation_recalled then
                variation_recalled = false
                changed_any = false
            elseif changed_pads then
                pads_dirty = true
                surround_env_dirty = false
                -- Moving a pad must remain a pure UI operation while stopped.
                -- Rewriting every FX envelope during drag causes visible stalls.
                -- During playback retain a sparse audition update only.
                local is_playing = (r.GetPlayState() & 1) == 1
                local now_t = r.time_precise()
                local preview_interval = settings.pad_preview_interval or 0.08
                if is_playing and preview_interval > 0 and now_t - (interaction.last_update_time or 0) > preview_interval then
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
r.atexit(function()
    if tail_preview.active then
        r.GetSet_LoopTimeRange(true, false, tail_preview.start_time, tail_preview.end_time, false)
    end
    SaveSettings()
end)
r.defer(Loop)
