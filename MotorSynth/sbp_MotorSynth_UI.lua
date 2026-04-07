-- @description SBP MotorSynth UI
-- @author      SBP & AI
-- @version     1.24.3
-- @about
--   # SBP MotorSynth UI
--   Automotive cockpit controller for SBP MotorSynth JSFX.
--   Dual-gauge cockpit (tachometer + speedometer), vertical gear strip,
--   interactive pedals, and tabbed parameter panels.
-- @link https://github.com/Bodzijun/SBP-Reaper-Scripts
-- @donation https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=bodzik@gmail.com&item_name=SBP+Reaper+Scripts+Support&currency_code=USD
--
-- @changelog
--   v1.24.3 (2026-04-07)
--     + Moved Phase 8 engine bonus controls from Interior/Cabin to Engine tab
--     + Idle Micro-Popping now in Engine Tuning; Fuel Pump and Knock/Ping moved to left Engine column under XY Pad
--   v1.24.2 (2026-04-07)
--     + ReaPack release prep: refreshed help section with Electro/Hybrid mechanics overview
--     + Smoothed Turn Influence behavior in DSP to avoid abrupt onset when turn signal is enabled
--   v1.24.1 (2026-04-07)
--     + Replaced Regen-to-Gearbox routing slider with Regen Timbre control
--     + Updated EV help to describe Mech-only regen routing and timbre shaping
--   v1.24.0 (2026-04-07)
--     + Updated factory presets for Phase 8 controls and Siren/Horn era parameter set
--     + Added new factory presets: Electric Urban EV, Hybrid Commute, Police Interceptor, Mountain Descent

---@diagnostic disable: undefined-field, need-check-nil, lowercase-global, param-type-mismatch

local r = reaper
local GMEM_NAME = 'SBP_MotorSynth_UI'
local GMEM_OK = false

-- ReaImGui shim
local shim = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
if r.file_exists(shim) then dofile(shim) end
if not r.ImGui_CreateContext then
  r.ShowConsoleMsg('[MotorSynth UI] ReaImGui not installed. Install via ReaPack.\n')
  return
end

if r.gmem_attach and r.gmem_read then
  local ok = pcall(r.gmem_attach, GMEM_NAME)
  GMEM_OK = ok and true or false
end

-- ===================================================================
-- CONSTANTS
-- ===================================================================
local FX_MATCH = 'MotorSynth'
local WIN_W, WIN_H = 1000, 710

-- Color palette  (0xRRGGBBAA)
local C = {
  BG        = 0x0C0D0EFF,
  PANEL     = 0x131618FF,
  FRAME     = 0x1B1F23FF,
  BORDER    = 0x26303AFF,
  TEXT      = 0xCDD4DCFF,
  TEXT_DIM  = 0x55626EFF,
  AMBER     = 0xE8730AFF,
  AMBER_MED = 0x9A4B07FF,
  AMBER_DIM = 0x3A1C05FF,
  GOLD      = 0xD4A218FF,
  RED       = 0xCC2A18FF,
  RED_MED   = 0x7A190FFF,
  RED_DIM   = 0x2E0D09FF,
  TEAL      = 0x29C09AFF,
  TEAL_DIM  = 0x124E40FF,
  GREEN     = 0x38C43EFF,
  YELLOW    = 0xE8C428FF,
  WHITE     = 0xFFFFFFFF,
  GRID      = 0xFFFFFF0C,
  NONE      = 0x00000000,
}

-- Param indices (0-based = sliderN - 1)
local P = {
  ignition=0,   throttle=1,   brake=2,      mode=3,       trans_mode=4,
  shift_intent=5, gear=6,     speed_ovr=7,  cabin_ext=8,
  rpm_tgt=9,    rev_lim=10,   cylinders=11, eng_size=12,
  character=13, roughness=14, cold_start=15,
  mech_noise=16,trans_whine=17,shift_jolt=18,shift_scrape=19,
  exh_type=20,  muffler=21,   turbo=22,     intake=23,    crackle=24, als=25,
  brk_squeal=26,brk_overtone=27,brk_trim=28,
  road_noise=29,road_surface=30,drift_aggr=31,chorus_color=32,wind_noise=33,
  handbrake=67, hb_ratchet=68, hb_release=69, hb_hold=70,
  gb_mesh=71, gb_diff=72, shift_peak=73,
  sci_mode=74, sci_ev=75, sci_inv=76, sci_regen=77, sci_bias=78,
  siren_on=79, siren_type=80, siren_level=81,
  horn_on=82, horn_level=83, out_siren_horn=84,
  idle_pop=85, fuel_pump=86, knock_ping=87, regen_timbre=88,
  brk_pad=52,  brk_pitch=53, bf_body=54, bf_res=55,
  valve_train=56, belt_pulley=57, chain_rattle=58,
  rev_beep_pitch=59, rev_beep_level=60, out_interior=61,
  ind_mode=62, ind_level=63, cabin_amb=64, ind_type=65, turn_infl=66,
  drive=34,     high_cut=35,  stereo_width=36, master_vol=37,
  out_exhaust=38,out_engine=39,out_mech=40, out_gearbox=41,
  out_air=42,   out_bov=43,   out_road=44,  out_chassis=45,
  out_brakes=46,out_bangs=47, out_wind=48,
  rpm_live=49,  speed_live=50, temp_live=51,
}

-- { min, max, default }
local PDEF = {
  [0]={0,1,0},        [1]={0,100,5},      [2]={0,100,0},
  [3]={0,1,1},        [4]={0,2,0},        [5]={0,4,0},
  [6]={0,8,0},        [7]={0,280,0},      [8]={0,100,50},
  [9]={500,9000,3200},[10]={4000,9000,6500},[11]={0,5,3},
  [12]={0,100,65},    [13]={-100,100,0},  [14]={0,100,45},
  [15]={0,100,20},    [16]={0,100,20},    [17]={0,100,48},
  [18]={0,100,70},    [19]={0,100,20},    [20]={0,2,2},
  [21]={0,100,45},    [22]={0,100,60},    [23]={0,100,50},
  [24]={0,100,65},    [25]={0,100,20},    [26]={0,100,82},
  [27]={0,100,68},    [28]={-12,6,-2},    [29]={0,100,55},
  [30]={0,3,1},       [31]={0,100,62},    [32]={0,100,55},
  [33]={0,100,5},     [34]={0,100,20},    [35]={0,100,30},
  [36]={0,100,50},    [37]={-60,0,-9},
  [38]={0,12,0}, [39]={0,12,0}, [40]={0,12,0}, [41]={0,12,0},
  [42]={0,12,0}, [43]={0,12,0}, [44]={0,12,0}, [45]={0,12,0},
  [46]={0,12,0}, [47]={0,12,0}, [48]={0,12,0},
  [49]={0,9000,800}, [50]={0,280,0}, [51]={0,100,0},
  [52]={0,100,45}, [53]={0,100,35},
  [54]={0,100,62}, [55]={0,100,48},
  [56]={0,100,55}, [57]={0,100,50}, [58]={0,100,52},
  [59]={700,1500,1080}, [60]={0,100,45}, [61]={0,12,0},
  [62]={0,3,0}, [63]={0,100,55}, [64]={0,100,8}, [65]={0,2,1}, [66]={0,100,0},
  [67]={0,100,0}, [68]={0,100,65}, [69]={0,100,60}, [70]={0,100,55},
  [71]={0,100,58}, [72]={0,100,52}, [73]={0,100,100},
  [74]={0,2,0}, [75]={0,100,55}, [76]={0,100,48}, [77]={0,100,42}, [78]={0,100,50},
  [79]={0,1,0}, [80]={0,2,0}, [81]={0,100,55},
  [82]={0,1,0}, [83]={0,100,55}, [84]={0,12,12},
  [85]={0,100,35}, [86]={0,100,45}, [87]={0,100,30}, [88]={0,100,58},
}

-- Tachometer arc geometry  (screen Y is down, 0=right, CW)
-- 7-o'clock (bottom-left) = 120 deg in screen = 2π*(120/360)
local TACHO_START = math.pi * (2.0 / 3.0)
local TACHO_SPAN  = math.pi * (5.0 / 3.0)   -- 300 deg sweep

-- ===================================================================
-- STATE
-- ===================================================================
local state = {
  params    = {},       -- physical param mirrors
  track     = nil,
  fx_idx    = -1,
  linked    = false,
  active_tab = 0,
  preset_idx = 0,
  car_name = 'Phantom',
  help_open = false,
  help_lang = 0,        -- 0=EN, 1=UKR
  -- animations
  disp_rpm  = 800.0,    -- smooth RPM for needle
  disp_spd  = 0.0,      -- smooth Speed for speedo needle
  disp_thr  = 0.0,      -- smooth throttle for bar glow
  disp_brk  = 0.0,      -- smooth brake for bar glow
  -- pedal drag state
  ped_was_active  = {},
  ped_drag_start  = {},
  -- link cache
  _link_check_t   = 0,
}

local function clearLinkState()
  state.track = nil
  state.fx_idx = -1
  state.linked = false
end

local function hasValidLinkedFX()
  if not state.track or state.fx_idx < 0 then return false end
  if not r.ValidatePtr2(0, state.track, 'MediaTrack*') then return false end
  return state.fx_idx < r.TrackFX_GetCount(state.track)
end

local PARAM_HELP = {
  [P.ignition] = 'Engine power state. OFF keeps synthesis in shutdown/coast behavior.',
  [P.throttle] = 'Driver throttle input (%). Key thresholds: auto N->1 engage >8%; Auto-intent kickdown trigger needs throttle >55% + fast pedal rise.',
  [P.brake] = 'Brake pressure input (%). Drives brake layers and speed decay/stop-hold behavior.',
  [P.mode] = 'Direct: pedal drives RPM directly. Physics: engine/load/gear model with inertia and shift logic.',
  [P.trans_mode] = 'D: earlier upshifts (RPM gate -60), calmer behavior. S: later upshifts (RPM gate +80), more aggressive. M: disables auto scheduling.',
  [P.shift_intent] = 'Auto adaptive, Cruise bias upshift, Neutral no bias, Downshift bias lower gear, Kickdown strongest downshift strategy.',
  [P.gear] = 'Manual gear selector (includes Neutral and Park/N slot).',
  [P.speed_ovr] = '0 = auto speed from drivetrain. >0 forces vehicle-speed domain for road/slip/wind behaviors.',
  [P.cabin_ext] = '0 = cabin perspective, 100 = exterior perspective (bus re-balance).',
  [P.rpm_tgt] = 'Target operating RPM band. In Physics mode this steers up/down shift decisions.',
  [P.rev_lim] = 'Hard limiter/cut region. Above limit, firing can be cut and ALS/bang behavior appears.',
  [P.cylinders] = 'Cylinder/firing-order topology. Changes pulse density, tone and engine feel.',
  [P.eng_size] = 'Virtual engine size/inertia weight. Bigger = heavier body, slower reactions, deeper feel. In Physics mode: larger engine has more flywheel inertia — builds RPM more slowly, upshifts happen later.',
  [P.character] = 'Core pulse skew. Left = thump/rounder; right = rasp/sharper.',
  [P.roughness] = 'Idle instability/randomness at low load.',
  [P.cold_start] = 'Cold-start duration/flare influence at ignition-on.',
  [P.mech_noise] = 'Mechanical master level for Valve Train + Belt/Pulley + Chain Rattle layers.',
  [P.valve_train] = 'Valve Train layer: metallic RPM-synced clicks in upper-mid range.',
  [P.belt_pulley] = 'Belt/Pulley layer: continuous mid-frequency whirr tied to RPM.',
  [P.chain_rattle] = 'Chain Rattle layer: low-mid roughness, stronger near idle.',
  [P.trans_whine] = 'Gearbox whine level.',
  [P.shift_jolt] = 'Low-mid impact component during gear engagement.',
  [P.shift_scrape] = 'Metallic scrape/ratchet tail during shifts.',
  [P.gb_mesh] = 'Phase 5: continuous gear-mesh texture plus synchro whine intensity during shift-in.',
  [P.gb_diff] = 'Phase 5: differential hum driven by vehicle speed (not RPM).',
  [P.shift_peak] = 'Synchro shift-in peak level ("pik"). 0% fully disables this peak.',
  [P.sci_mode] = 'Phase 7 drive source switch: Combustion = normal engine, Hybrid = automatic EV/combustion blend, Electric = EV-style drive layers only.',
  [P.sci_ev] = 'EV drive whine intensity. Main traction-motor tonal layer.',
  [P.sci_inv] = 'Inverter tone intensity. High-frequency electric switching/drive layer.',
  [P.sci_regen] = 'Regen braking tonal behavior while coasting/braking in Hybrid or Electric mode.',
  [P.sci_bias] = 'Hybrid EV bias. Higher values keep Hybrid mode in EV behavior longer at low load.',
  [P.siren_on] = 'Bonus siren switch (quick cockpit button). Routed to dedicated Siren/Horn bus.',
  [P.siren_type] = 'Siren type selection: Police, Medical, Fire.',
  [P.siren_level] = 'Siren loudness routed to dedicated Siren/Horn bus.',
  [P.horn_on] = 'Cockpit hold-to-sound horn trigger. Active only while the HORN button is held.',
  [P.horn_level] = 'Horn loudness routed to dedicated Siren/Horn bus.',
  [P.idle_pop] = 'Phase 8: subtle idle micro-popping texture at low RPM and low throttle.',
  [P.fuel_pump] = 'Phase 8: ignition-on fuel pump priming buzz intensity and duration.',
  [P.knock_ping] = 'Phase 8: combustion knock/ping intensity under high-load high-RPM stress.',
  [P.regen_timbre] = 'Regen timbre shaping. Lower = darker/noisier electric brake texture, higher = brighter/more tonal regen character.',
  [P.exh_type] = 'Exhaust topology preset (Stock/Sport/Straight Pipe).',
  [P.muffler] = 'Muffling amount. Higher = darker/smoother exhaust.',
  [P.turbo] = 'Turbo spool/whine system intensity.',
  [P.intake] = 'Intake air/noise contribution.',
  [P.crackle] = 'Backfire/crackle probability and intensity.',
  [P.als] = 'Anti-lag/limiter bangs contribution.',
  [P.brk_squeal] = 'Brake squeal tonal layer amount.',
  [P.brk_overtone] = 'Brake overtone harmonics/brightness.',
  [P.brk_pitch] = 'Brake pad squeak pitch. Controls only the disc-friction oscillator (metal-on-metal tone). 0% = low ~2200 Hz, 100% = high ~5600 Hz. Pitch is road-surface independent; overall level still follows surface conditions.',  
  [P.brk_trim] = 'Brake bus output trim in dB.',
  [P.brk_pad] = 'Pad squeak volume — a quieter metallic pad-bite layer. It starts entering at about 12% brake pressure, rises through roughly 12-36%, and then stays present across the rest of the brake travel with a softer level.',
  [P.handbrake] = 'Handbrake input (%). Controls lock intensity and handbrake behavior in motion.',
  [P.hb_ratchet] = 'Ratchet click level while pulling the handbrake lever.',
  [P.hb_release] = 'Release-level trigger amount for shared handbrake ratchet body on lever return.',
  [P.hb_hold] = 'Hold friction/rumble level while moving with handbrake engaged.',
  [P.road_noise] = 'Road/tire broadband and texture layers.',
  [P.road_surface] = 'Surface profile (Asphalt/Concrete/Gravel/Wet) for road/brake/slip coloration.',
  [P.drift_aggr] = 'Slip/traction aggressiveness and burst behavior.',
  [P.chorus_color] = 'Color amount for multi-wheel/chorus-like drift and brake tones.',
  [P.wind_noise] = 'Speed-dependent wind layer amount.',
  [P.rev_beep_pitch] = 'Frequency of Reverse Beep tone in Hz. Fixed single-frequency (no modulation). Typical range 700-1500 Hz.',
  [P.rev_beep_level] = 'Reverse Beep output level (0-100%). Routed to Interior/Cabin output.',
  [P.out_interior] = 'Interior/Cabin bus output routing (Reverse Beep, Indicators, Cabin Ambiance).',
  [P.out_siren_horn] = 'Dedicated Siren/Horn bus output routing.',
  [P.ind_mode] = 'Indicator state control from Cockpit tab buttons < and > (OFF/LEFT/RIGHT). Hazard remains automation/manual mode.',
  [P.ind_level] = 'Indicator relay click level (0-100%). Level of L/R/Hazard indicators regardless of mode selection.',
  [P.cabin_amb] = 'Cabin ambiance level (0-100%). Subtle filtered low-frequency background texture for interior perspective.',
  [P.ind_type] = 'Indicator click character: Relay (mechanical), Soft (damped), Sharp (bright and snappy).',
  [P.turn_infl] = 'Optional motion-linked sound influence while turn FX is active. 0 = fully off. Higher values add subtle road/chassis/engine movement cues.',
  [P.drive] = 'Master drive/saturation amount.',
  [P.high_cut] = 'Global top-end attenuation/tone darkening.',
  [P.stereo_width] = 'Stereo width processing amount.',
  [P.master_vol] = 'Master output level (dB).',
  [P.rpm_live] = 'Telemetry: live RPM from engine core.',
  [P.speed_live] = 'Telemetry: live speed (km/h).',
  [P.temp_live] = 'Telemetry: live thermal state (%).',
}

-- Initialise params from defaults
for idx, def in pairs(PDEF) do state.params[idx] = def[3] end

-- ===================================================================
-- UTILITY
-- ===================================================================
local function clamp(v, lo, hi)  return v < lo and lo or (v > hi and hi or v) end
local function lerp(a, b, t)     return a + (b - a) * t end
local function lerpf(cur, tgt, spd)  return cur + (tgt - cur) * clamp(spd, 0, 1) end

local function alphamix(col, a)
  return (col & 0xFFFFFF00) | clamp(math.floor((col & 0xFF) * a), 0, 255)
end

local function showTip(ctx, txt)
  if txt and txt ~= '' and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, txt)
  end
end

local function tr(en, uk)
  return state.help_lang == 1 and uk or en
end

-- Draw arc as line segments  (dl, cx, cy, r, a_start, a_end, col, thick, segs)
local function arc(dl, cx, cy, rad, a0, a1, col, thick, segs)
  segs = segs or 36
  local da = (a1 - a0) / segs
  local lx = cx + math.cos(a0) * rad
  local ly = cy + math.sin(a0) * rad
  for i = 1, segs do
    local a  = a0 + da * i
    local nx = cx + math.cos(a) * rad
    local ny = cy + math.sin(a) * rad
    r.ImGui_DrawList_AddLine(dl, lx, ly, nx, ny, col, thick)
    lx = nx;  ly = ny
  end
end

-- Draw filled band arc (the thick colored zone behind the gauge)
local function arcBand(dl, cx, cy, r_in, r_out, a0, a1, col, segs)
  segs = segs or 32
  local thick = r_out - r_in
  local rad   = (r_in + r_out) * 0.5
  arc(dl, cx, cy, rad, a0, a1, col, thick, segs)
end

-- ===================================================================
-- TRACK / FX
-- ===================================================================
local function findFX(track)
  for i = 0, r.TrackFX_GetCount(track) - 1 do
    local _, nm = r.TrackFX_GetFXName(track, i)
    if nm and nm:find(FX_MATCH, 1, true) then return i end
  end
  return -1
end

local function findTrackWithFX()
  for pass = 1, 2 do
    local cnt = pass == 1 and r.CountSelectedTracks(0) or r.CountTracks(0)
    for i = 0, cnt - 1 do
      local tr = pass == 1 and r.GetSelectedTrack(0, i) or r.GetTrack(0, i)
      local fx = findFX(tr)
      if fx >= 0 then return tr, fx end
    end
  end
  return nil, -1
end

local readAllParams

local function ensureMotorSynthOnSelectedTrack()
  if r.CountSelectedTracks(0) < 1 then
    r.ShowConsoleMsg('[MotorSynth UI] Select a track first, then click CORE.\n')
    return false
  end
  local tr = r.GetSelectedTrack(0, 0)
  if not tr then
    r.ShowConsoleMsg('[MotorSynth UI] Failed to get selected track.\n')
    return false
  end

  local candidates = {
    'JS: sbp_MotorSynth',
    'JS: sbp_MotorSynth.jsfx',
    'JS: MotorSynth',
    'MotorSynth',
  }

  local fx = -1
  for _, fx_name in ipairs(candidates) do
    fx = r.TrackFX_AddByName(tr, fx_name, false, 1)
    if fx >= 0 then break end
  end

  if fx < 0 then
    r.ShowConsoleMsg('[MotorSynth UI] Could not add/find MotorSynth JSFX on selected track.\n')
    return false
  end

  state.track = tr
  state.fx_idx = fx
  state.linked = true
  state._link_check_t = 0
  readAllParams()
  return true
end

readAllParams = function()
  if not hasValidLinkedFX() then
    clearLinkState()
    return
  end
  for idx, _ in pairs(PDEF) do
    if type(idx) == 'number' then
      local val = r.TrackFX_GetParamEx(state.track, state.fx_idx, idx)
      state.params[idx] = val
    end
  end
end

local function setParam(idx, val)
  if not hasValidLinkedFX() then
    clearLinkState()
    return
  end
  local def = PDEF[idx]; if not def then return end
  val = clamp(val, def[1], def[2])
  state.params[idx] = val
  r.TrackFX_SetParam(state.track, state.fx_idx, idx, val)
end

local function updateLink()
  if state.track and not hasValidLinkedFX() then
    clearLinkState()
  end
  local now = r.time_precise()
  if now - state._link_check_t < 0.4 then return end
  state._link_check_t = now
  local tr, fx = findTrackWithFX()
  if tr and fx >= 0 then
    if tr ~= state.track or fx ~= state.fx_idx then
      state.track   = tr
      state.fx_idx  = fx
      readAllParams()
    end
    state.linked = true
  else
    clearLinkState()
  end
end

-- Items string helper: null-separated combo list.
-- Avoids Lua's \0N decimal-escape bug (\01 = chr(1), not chr(0)+'1')
local function items(...) return table.concat({...}, '\0') .. '\0' end

-- ===================================================================
-- THEME
-- ===================================================================
local N_COL, N_VAR = 21, 5

local function pushTheme(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),          C.BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),           C.PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),           C.FRAME)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),    0x222830FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),     0x2C3640FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),              C.TEXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),      C.TEXT_DIM)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),            0x1C3020FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),     0x224030FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),      0x2A5840FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),         C.AMBER)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),        C.AMBER)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(),  C.GOLD)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),            0x281E08FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(),     0x3A2C0EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),      0x4E3C14FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(),           0x080A0CFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(),     0x0C0F12FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(),         C.BORDER)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),            C.BORDER)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(),           0x14181EFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(),  10, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),  3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),   3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),    6, 3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_TabRounding(),    3)
end

local function popTheme(ctx)
  r.ImGui_PopStyleColor(ctx, N_COL)
  r.ImGui_PopStyleVar(ctx, N_VAR)
end

-- Per-frame refresh of animated params (tachometer, pedals, gear, speed)
local function refreshCritical()
  if not hasValidLinkedFX() then
    clearLinkState()
    return
  end
  local function rd(i) return r.TrackFX_GetParamEx(state.track, state.fx_idx, i) end
  state.params[P.rpm_tgt]    = rd(P.rpm_tgt)
  state.params[P.rpm_live]   = rd(P.rpm_live)
  state.params[P.throttle]   = rd(P.throttle)
  state.params[P.brake]      = rd(P.brake)
  state.params[P.gear]       = rd(P.gear)
  state.params[P.speed_ovr]  = rd(P.speed_ovr)
  state.params[P.speed_live] = rd(P.speed_live)
  state.params[P.temp_live]  = rd(P.temp_live)
  state.params[P.cold_start] = rd(P.cold_start)
  state.params[P.eng_size]   = rd(P.eng_size)
  state.params[P.character]  = rd(P.character)

  -- Fallback live telemetry channel via gmem (more robust than slider sync on some hosts)
  if GMEM_OK then
    local rpm = r.gmem_read(0)
    local spd = r.gmem_read(1)
    local tmp = r.gmem_read(2)
    if rpm and spd and tmp then
      rpm = clamp(rpm, 0, 9000)
      spd = clamp(spd, 0, 280)
      tmp = clamp(tmp, 0, 100)
      state.params[P.rpm_live] = rpm
      state.params[P.speed_live] = spd
      state.params[P.temp_live] = tmp
    end
  end
end

-- ===================================================================
-- WIDGET HELPERS
-- ===================================================================
local function secHdr(ctx, lbl, col)
  col = col or C.AMBER
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_Text(ctx, lbl)
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_Separator(ctx)
end

local function sliderD(ctx, lbl, idx, w)
  local def = PDEF[idx]; if not def then return false end
  local cur = state.params[idx] or def[3]
  r.ImGui_SetNextItemWidth(ctx, w or -1)
  local ch, v = r.ImGui_SliderDouble(ctx, lbl, cur, def[1], def[2])
  if ch and state.linked then setParam(idx, v) end
  return ch
end

local function sliderI(ctx, lbl, idx, w)
  local def = PDEF[idx]; if not def then return false end
  local cur = math.floor(state.params[idx] or def[3])
  r.ImGui_SetNextItemWidth(ctx, w or -1)
  local ch, v = r.ImGui_SliderInt(ctx, lbl, cur, def[1], def[2])
  if ch and state.linked then setParam(idx, math.floor(v)) end
  return ch
end

local function cmb(ctx, lbl, idx, items, w)
  local def = PDEF[idx]; if not def then return false end
  local cur = math.floor(state.params[idx] or 0)
  r.ImGui_SetNextItemWidth(ctx, w or -1)
  local ch, v = r.ImGui_Combo(ctx, lbl, cur, items)
  if ch and state.linked then setParam(idx, v) end
  return ch
end

local function labelSlider(ctx, label, idx, w)
  r.ImGui_Text(ctx, label)
  showTip(ctx, PARAM_HELP[idx])
  sliderD(ctx, '##' .. idx, idx, w)
  showTip(ctx, PARAM_HELP[idx])
end

local function labelSliderI(ctx, label, idx, w)
  r.ImGui_Text(ctx, label)
  showTip(ctx, PARAM_HELP[idx])
  sliderI(ctx, '##i' .. idx, idx, w)
  showTip(ctx, PARAM_HELP[idx])
end

-- XY Pad for Engine Size (Y) and Character (X)
local xy_pad_state = {
  dragging = false,
  char_norm = 0.5,
  size_norm = 0.5,
  char_tgt = 0.5,
  size_tgt = 0.5,
  last_push_t = 0,
}

-- XY Pad for Drift automation: Speed Override (X) and Drift Aggression (Y)
local drift_xy_state = { dragging = false, speed_norm = 0.0, aggr_norm = 0.5 }

local function drawXYPad(ctx, pad_w, pad_h)
  r.ImGui_Dummy(ctx, pad_w, pad_h)
  local p_x, p_y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  
  -- Background
  r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + pad_w, p_y + pad_h, 0x000000A0, 4)
  r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + pad_w, p_y + pad_h, 0xFFFFFF30, 4)
  
  -- Grid lines
  r.ImGui_DrawList_AddLine(draw_list, p_x + pad_w*0.5, p_y, p_x + pad_w*0.5, p_y + pad_h, 0xFFFFFF15, 1)
  r.ImGui_DrawList_AddLine(draw_list, p_x, p_y + pad_h*0.5, p_x + pad_w, p_y + pad_h*0.5, 0xFFFFFF15, 1)
  
  -- Axis labels centered inside pad
  local lbl_col = 0xFFFFFF80
  local function drawAxisText(text, x, y)
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    local tx = x - tw * 0.5
    local ty = y - th * 0.5
    r.ImGui_DrawList_AddText(draw_list, tx, ty, lbl_col, text)
  end

  local top_y = p_y + 8
  local bottom_y = p_y + pad_h - 8
  local left_x = p_x + 8
  local right_x = p_x + pad_w - 8
  local mid_x = p_x + pad_w * 0.5
  local mid_y = p_y + pad_h * 0.5

  drawAxisText('Large',  mid_x, top_y)
  drawAxisText('Small',  mid_x, bottom_y)
  drawAxisText('Raspy',  left_x + 14, mid_y)
  drawAxisText('Thumpy', right_x - 18, mid_y)
  
  -- Invisible button for interaction
  local hit_margin = 6
  r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
  r.ImGui_InvisibleButton(ctx, '##xy_pad_engine', pad_w + hit_margin*2, pad_h + hit_margin*2)
  
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx)
  local is_active = r.ImGui_IsItemActive(ctx)
  
  -- When clicked, sync from JSFX to get external preset changes
  if is_clicked and state.track and state.fx_idx >= 0 then
    xy_pad_state.char_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.character), 0, 1)
    xy_pad_state.size_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.eng_size), 0, 1)
    xy_pad_state.char_tgt = xy_pad_state.char_norm
    xy_pad_state.size_tgt = xy_pad_state.size_norm
    xy_pad_state.last_push_t = r.time_precise()
    xy_pad_state.dragging = true
  end
  
  -- End dragging
  if not r.ImGui_IsMouseDown(ctx, 0) then
    xy_pad_state.dragging = false
  end
  
  -- Handle active dragging with mouse position
  if xy_pad_state.dragging and is_active and state.track and state.fx_idx >= 0 then
    local mx, my = r.ImGui_GetMousePos(ctx)
    
    -- Calculate position relative to pad area
    local rel_x = mx - p_x
    local rel_y = my - p_y
    
    -- Clamp to pad bounds and normalize
    local nx = clamp(rel_x / pad_w, 0, 1)      -- X = Character
    local ny = clamp(1 - (rel_y / pad_h), 0, 1)  -- Y = Size (inverted: top=1, bottom=0)
    
    -- Set drag targets; actual writes are smoothed below to avoid zipper noise.
    xy_pad_state.char_tgt = nx
    xy_pad_state.size_tgt = ny
  end

  if xy_pad_state.dragging and state.track and state.fx_idx >= 0 then
    local slew = 0.22
    xy_pad_state.char_norm = lerpf(xy_pad_state.char_norm, xy_pad_state.char_tgt, slew)
    xy_pad_state.size_norm = lerpf(xy_pad_state.size_norm, xy_pad_state.size_tgt, slew)

    local dch = math.abs(xy_pad_state.char_norm - xy_pad_state.char_tgt)
    local dsz = math.abs(xy_pad_state.size_norm - xy_pad_state.size_tgt)
    local now = r.time_precise()
    if dch > 0.0005 or dsz > 0.0005 or (now - xy_pad_state.last_push_t) > 0.030 then
      setParam(P.character, xy_pad_state.char_norm * 200.0 - 100.0)
      setParam(P.eng_size, xy_pad_state.size_norm * 100.0)
      xy_pad_state.last_push_t = now
    end
  end
  
  -- Draw current position handle (always use stored state)
  local handle_x = p_x + xy_pad_state.char_norm * pad_w
  local handle_y = p_y + (1 - xy_pad_state.size_norm) * pad_h
  r.ImGui_DrawList_AddCircleFilled(draw_list, handle_x, handle_y, 6, 0x2D8C6DFF)
  r.ImGui_DrawList_AddCircle(draw_list, handle_x, handle_y, 6, 0xFFFFFF80, 0, 2)
end

-- XY Pad for Drift: Speed Override (X-axis: 0-280 km/h) ↔ Drift Aggression (Y-axis: 0-100%)
local function drawDriftXYPad(ctx, pad_w, pad_h)
  local p_x, p_y = r.ImGui_GetCursorScreenPos(ctx)
  
  -- Sync from JSFX when not dragging (to catch preset changes)
  if not drift_xy_state.dragging and state.track and state.fx_idx >= 0 then
    drift_xy_state.speed_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.speed_ovr) / 280, 0, 1)
    drift_xy_state.aggr_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.drift_aggr) / 100, 0, 1)
  end
  
  -- Visual background (same as Engine XY Pad)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, p_x, p_y, p_x + pad_w, p_y + pad_h, 0x000000A0, 4)
  r.ImGui_DrawList_AddRect(draw_list, p_x, p_y, p_x + pad_w, p_y + pad_h, 0xFFFFFF30, 4)
  
  -- Grid lines
  r.ImGui_DrawList_AddLine(draw_list, p_x + pad_w*0.5, p_y, p_x + pad_w*0.5, p_y + pad_h, 0xFFFFFF15, 1)
  r.ImGui_DrawList_AddLine(draw_list, p_x, p_y + pad_h*0.5, p_x + pad_w, p_y + pad_h*0.5, 0xFFFFFF15, 1)
  
  -- Invisible button for interaction
  local hit_margin = 6
  r.ImGui_SetCursorScreenPos(ctx, p_x - hit_margin, p_y - hit_margin)
  r.ImGui_InvisibleButton(ctx, '##xy_pad_drift', pad_w + hit_margin*2, pad_h + hit_margin*2)
  
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  local is_clicked = r.ImGui_IsItemClicked(ctx)
  local is_active = r.ImGui_IsItemActive(ctx)
  
  -- On click: sync from JSFX live values
  if is_clicked and state.track and state.fx_idx >= 0 then
    drift_xy_state.speed_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.speed_ovr) / 280, 0, 1)
    drift_xy_state.aggr_norm = clamp(r.TrackFX_GetParamEx(state.track, state.fx_idx, P.drift_aggr) / 100, 0, 1)
    drift_xy_state.dragging = true
  end
  
  -- Release: stop dragging
  if not r.ImGui_IsMouseDown(ctx, 0) then
    drift_xy_state.dragging = false
  end
  
  -- While dragging: update parameters
  if drift_xy_state.dragging and is_active and state.track and state.fx_idx >= 0 then
    local mx, my = r.ImGui_GetMousePos(ctx)
    
    local rel_x = mx - p_x
    local rel_y = my - p_y
    
    local nx = clamp(rel_x / pad_w, 0, 1)            -- X = Speed Override (0-280 km/h)
    local ny = clamp(1 - (rel_y / pad_h), 0, 1)  -- Y = Drift Aggression (inverted: top=1)
    
    r.TrackFX_SetParamNormalized(state.track, state.fx_idx, P.speed_ovr, nx)
    r.TrackFX_SetParamNormalized(state.track, state.fx_idx, P.drift_aggr, ny)
    
    drift_xy_state.speed_norm = nx
    drift_xy_state.aggr_norm = ny
  end
  
  -- Draw axis labels in top corners (inside pad)
  r.ImGui_DrawList_AddText(draw_list, p_x + 6, p_y + 4, 0xFFFFFF80, '0')
  r.ImGui_DrawList_AddText(draw_list, p_x + pad_w - 32, p_y + 4, 0xFFFFFF80, '280 km/h')
  
  -- Draw handle (gold color for drift)
  local handle_x = p_x + drift_xy_state.speed_norm * pad_w
  local handle_y = p_y + (1 - drift_xy_state.aggr_norm) * pad_h
  r.ImGui_DrawList_AddCircleFilled(draw_list, handle_x, handle_y, 5, 0xFFD700FF)
  r.ImGui_DrawList_AddCircle(draw_list, handle_x, handle_y, 5, 0xFFFFFFBF, 0, 1.5)
  
  -- Display current values
  local spd_km = math.floor(drift_xy_state.speed_norm * 280 + 0.5)
  local aggr_pct = math.floor(drift_xy_state.aggr_norm * 100 + 0.5)
  r.ImGui_DrawList_AddText(draw_list, handle_x + 8, handle_y - 8, 0xFFFFFFFF, 
    spd_km .. ' km/h | ' .. aggr_pct .. '%')
end

local function labelCombo(ctx, label, idx, items, w)
  r.ImGui_Text(ctx, label)
  showTip(ctx, PARAM_HELP[idx])
  cmb(ctx, '##c' .. idx, idx, items, w)
  showTip(ctx, PARAM_HELP[idx])
end

local function drawHelpWindow(ctx)
  if not state.help_open then return end
  r.ImGui_SetNextWindowSize(ctx, 860, 680, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, tr('MotorSynth Help', 'Довідка MotorSynth'), true)
  state.help_open = open
  if visible then
    r.ImGui_SetNextItemWidth(ctx, 170)
    local ch_lang, v_lang = r.ImGui_Combo(ctx, 'Language##help_lang', state.help_lang, items('English', 'Українська'))
    if ch_lang then state.help_lang = v_lang end

    r.ImGui_TextWrapped(ctx, tr(
      'This help describes behavior mechanics and thresholds in plain language. Hover controls for short tips.',
      'Ця довідка описує механіки та пороги простою мовою. Наводь курсор на контроли для коротких підказок.'))
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, tr('Electro / Hybrid Engine Mechanics', 'Механіка Electro / Hybrid двигуна'))
    r.ImGui_TextWrapped(ctx, tr(
      'Drive Source controls behavior domains: Combustion keeps classic engine stack; Hybrid crossfades EV and combustion by throttle/load with Hybrid Bias; Electric forces EV-focused layers. EV Whine is traction-motor body, Inverter adds high switching texture, Regen Tone adds braking generation layer.\n\nRouting model: inverter and regen are under-hood only (Mech context), with no Interior feed, so electric layers remain mechanical rather than cabin FX.\n\nRegen Timbre (%) shapes spectral balance: lower values are darker/noisier friction-like electric braking, higher values are brighter/more tonal regeneration. Regen is strongest when throttle is released and/or brake rises, and is motion-gated to avoid idle artifacts.',
      'Drive Source керує доменами поведінки: Combustion залишає класичний стек ДВЗ; Hybrid кросфейдить EV і combustion за газом/навантаженням з Hybrid Bias; Electric примусово вмикає EV-орієнтовані шари. EV Whine формує тягове тіло мотора, Inverter додає високочастотну комутаційну текстуру, Regen Tone додає шар рекуперативного гальмування.\n\nМодель маршрутизації: inverter і regen йдуть тільки під капот (контекст Mech), без подачі в Interior, щоб електро-шари лишалися механічними, а не кабінним FX.\n\nRegen Timbre (%) формує спектральний баланс: нижчі значення дають темніше/шумніше електрогальмування, вищі значення дають яскравіший/тональніший характер регени. Регенерація найсильніша при відпущеному газі та/або зростанні гальма і має motion-gate, щоб уникати артефактів на місці.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Core Modes', 'Основні режими'))
    r.ImGui_TextWrapped(ctx, tr(
      'Direct mode: pedal controls RPM directly for quick sound design. Physics mode: full load, inertia and gearbox behavior.',
      'Режим Direct: педаль напряму керує RPM для швидкого саунд-дизайну. Режим Physics: повна логіка навантаження, інерції та коробки.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Transmission styles: D shifts earlier and calmer, S shifts later and more aggressive, M disables automatic scheduling.',
      'Стилі трансмісії: D перемикає раніше і спокійніше, S пізніше та агресивніше, M вимикає автоперемикання.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Shift Intent and Triggers', 'Shift Intent і тригери'))
    r.ImGui_TextWrapped(ctx, tr(
      'Auto intent can trigger kickdown when pedal rises sharply and throttle is high. Cruise prefers calmer upshifts. Downshift and Kickdown keep lower gears longer.',
      'У режимі Auto може запускатися kickdown, коли педаль різко зростає і газ високий. Cruise надає перевагу спокійним апшифтам. Downshift і Kickdown довше тримають нижчі передачі.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Fast throttle release can trigger BOV and crackle events. A practical trigger point is about a 15% drop from high load.',
      'Швидкий відпуск газу може запускати BOV і crackle-події. Практичний поріг: близько 15% падіння при високому навантаженні.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Upshift / Downshift Timing', 'Таймінги апшифт/дауншифт'))
    r.ImGui_TextWrapped(ctx, tr(
      'Typical upshift duration is about 0.25 s. Typical downshift duration is about 0.30 s.',
      'Типова тривалість апшифту близько 0.25 с. Типова тривалість дауншифту близько 0.30 с.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Auto N->1 engage starts when throttle goes above about 8% and Park/N lock is not active.',
      'Автовключення N->1 починається, коли газ перевищує приблизно 8% і не активовано Park/N lock.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Engine Braking', 'Гальмування двигуном'))
    r.ImGui_TextWrapped(ctx, tr(
      'Engine braking grows as throttle closes. It is strongest in lower gears and at higher RPM.',
      'Гальмування двигуном зростає при закритті газу. Воно найсильніше на нижчих передачах і вищих RPM.'))
    r.ImGui_TextWrapped(ctx, tr(
      'This behavior is blended into RPM deceleration and into chassis pulse, so decel is both heard and felt.',
      'Ця поведінка вбудована в уповільнення RPM і в імпульс шасі, тому сповільнення і чути, і відчувається.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Near stop, brake and low throttle can activate stop-lock for stable zero-speed hold.',
      'Біля нуля швидкості комбінація гальма і низького газу може ввімкнути stop-lock для стабільного утримання на місці.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Brakes, Surface Types, and Brake Lag', 'Гальма, типи поверхні та brake lag'))
    r.ImGui_TextWrapped(ctx, tr(
      'Brake system uses multiple layers: squeal tone, friction body, crunch texture, and optional wet hiss.',
      'Система гальм має кілька шарів: squeal-тон, фрикційне тіло, crunch-текстуру та, за потреби, wet-hiss.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Surface profiles change brake tone and texture: Asphalt balanced, Concrete brighter and cleaner, Gravel noisier and choppier, Wet softer with more spray/hiss.',
      'Профілі поверхні змінюють тон і текстуру гальм: Asphalt збалансований, Concrete яскравіший і чистіший, Gravel шумніший і рваніший, Wet м’якший із більшим spray/hiss.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Brake lag behavior is intentional: short micro-delays and interruptions imitate stick-slip and pad/disc grip-release cycles.',
      'Brake lag зроблено навмисно: короткі мікрозатримки й переривання імітують stick-slip та цикли grip-release колодки/диска.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Thermal System', 'Тепловая система'))
    r.ImGui_TextWrapped(ctx, tr(
      'The engine has two thermal states: cold (blue, on startup) and warm (orange/red, running). Cold engines exhibit: extended cranking duration, elevated idle RPM, increased mechanical friction, and coarser exhaust sound.',
      'Двигун має два теплові стани: холодний (синій, при запуску) і гарячий (оранжевий/червоний, при роботі). На холодному двигуні: подовжене запалювання, підвищена холостих обороти, збільшений механічний фрикціон та грубіший оклад.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Warm-up occurs automatically over about 45 seconds while the engine runs. Cool-down takes about 90 seconds after the engine stops.',
      'Прогрів відбувається автоматично протягом близько 45 секунд при роботі двигуна. Охолодження займає близько 90 секунд після зупинки.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Cold Start slider (1-100) controls cranking severity and duration. Higher values mean longer, rougher cold starts.',
      'Повзунок Cold Start (1-100) керує суворістю і тривалістю запуску. Вищі значення означають довшу й грубішу холодну стартування.'))
    r.ImGui_TextWrapped(ctx, tr(
      'As temperature rises, backfire and crackle activity increases, and idle RPM gradually stabilizes to the hot baseline.',
      'З підвищенням температури активність бекпейрів і крекління зростає, а холостий хід поступово стабілізується до гарячої лінії.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Engine Size and Character', 'Розмір двигуна та характер'))
    r.ImGui_TextWrapped(ctx, tr(
      'Engine Size scales the physical presence: larger engines have deeper startup revs, louder core tone, longer mechanical rattle, and more dramatic shifts. Smaller engines sound tighter and snappier.',
      'Розмір двигуна масштабує фізичну присутність: більш великі мають глибший запуск, більш гучний оклад, довший mechanical rattle і більш драматичні піки. Менші звучать щільніше й живіше.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Gear shift speed: In Physics mode, Engine Size controls flywheel inertia. Larger engines build RPM more slowly → upshifts happen later and feel heavier. Smaller engines rev freely → faster shifts.',
      'Швидкість перемикань: у режимі Physics розмір двигуна керує інерцією маховика. Більший двигун набирає оберти повільніше → перемикання пізніші й важчі. Менший двигун крутить вільно → зміни передач швидші.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Character ranges from Thump (negative, deep and smooth) to Rasp (positive, bright and edgy). Adjust character to match real engine personality.',
      'Характер від Thump (мінус, глибокий й гладкий) до Rasp (плюс, яскравий й гострий). Налаштуйте для розпізнаваності реального двигуна.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Speed Domain and Telemetry', 'Швидкісний домен і телеметрія'))
    r.ImGui_TextWrapped(ctx, tr(
      'Speed Override at 0 uses automatic drivetrain speed estimate (rpm/gear-based). Non-zero (1-280 km/h) forces a fixed speed domain for road, wind, tire and drift/slip logic.',
      'Speed Override = 0 використовує автоматичну оцінку швидкості від трансмісії (RPM/gear). Ненульове (1-280 км/год) форсує фіксований домен швидкості для road, wind, tire й drift/slip логіки.'))
    r.ImGui_TextWrapped(ctx, tr(
      'For drifting, Speed Override is ideal: set it to match vehicle speed while wheels slip independently. This decouples sound engine from drivetrain and lets tire slip, road texture, and wind freely modulate.',
      'Для дрифту Speed Override ідеальний: встановіть значення відповідно до швидкості авто, поки колеса буксують незалежно. Це розділяє звук від трансмісії й дозволяє tire slip, road і wind вільно модулювати.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Gauges read live telemetry: RPM, speed and temperature.',
      'Прилади читають live-телеметрію: RPM, швидкість і температуру.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Mechanical Noise Split (Phase 1)', 'Розділення механічного шуму (Фаза 1)'))
    r.ImGui_TextWrapped(ctx, tr(
      'The mechanical layer is now split into three independent and organic-sounding components:',
      'Механічний шар тепер розділений на три незалежні й органічні компоненти:'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Valve Train: FM-synthesized metallic clicks (frequency-modulated at 2.75× ratio) with gated transients. Sharpest and most RPM-reactive component.',
      '• Valve Train: FM-синтезовані металічні клацання (модульовані на 2.75× коефіцієнт) із затвореними імпульсами. Найгостріший і найбільш реактивний на RPM компонент.'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Belt/Pulley: Harmonic stack (3 weighted sinusoids) with amplitude wobble (7-20 Hz). Smooth continuous whirr, like a belt spinning.',
      '• Belt/Pulley: Гармонічний стек (3 зважених синусоїди) з амплітудним вібраціоном (7-20 Гц). Гладкий безперервний звук, як ремінь, що крутиться.'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Chain Rattle: Ring modulation + RBJ bandpass resonator. Fat metallic rattle with defined Q factor, Engine Size influences center frequency.',
      '• Chain Rattle: Ring modulation + RBJ bandpass резонатор. Товстий металічний грюкіт з визначеним Q фактором, розмір двигуна впливає на центральну частоту.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Each layer has its own slider control in the Engine tab. Mix them to balance the mechanical character: high Valve for aggressive, high Belt for smooth, high Chain for industrial tone.',
      'Кожен шар має власний повзунок керування на вкладці Engine. Мішайте їх для балансування механіки: висока Valve для агресивного, висока Belt для гладкого, висока Chain для індустріального тону.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Reverse Gear (Phase 3)', 'Задня передача (Фаза 3)'))
    r.ImGui_TextWrapped(ctx, tr(
      'Reverse is now a full transmission state with dedicated physics, audio and cabin perspective:',
      'Задня передача тепер повний стан трансмісії з виділеною фізикою, аудіо та кабінною перспективою:'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Reverse State: Gear slot 7 (Yellow highlight in selector). Physical gear ratio = 3.05 (similar to 1st gear but with reverse flow).',
      '• Reverse State: Слот передачі 7 (Жовтий виділ у селекторі). Фізичний передавальний коефіцієнт = 3.05 (подібний до 1-ї передачі, але зі зворотним потоком).'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Reverse Speed Physics: Vehicle speed is capped at ~13% of max forward speed. This prevents unrealistic reverse acceleration.',
      '• Reverse Speed Physics: Швидкість авто обмежена ~13% максимальної передової швидкості. Це запобігає нереалістичному розгону назад.'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Reverse Whine: Dual-tone transmission whine (base 230 Hz + 0.2×RPM, with 2.03× harmonic at 30% amplitude). Subtle and distinct from forward whine.',
      '• Reverse Whine: Двотоновий звук трансмісії (базова 230 Hz + 0.2×RPM, із 2.03× гармонікою на 30% амплітуді). Тонкий і відмінний від передового звуку.'))
    r.ImGui_TextWrapped(ctx, tr(
      '• Cabin-Aware Reverse Beep: Impulsive tone (1080-1200 Hz band) cycling on 170ms / off 480ms. In cabin mode, beep is loud (1.25×). In exterior mode, it is nearly silent (0.10×). Reflects real vehicle backup warning behavior.',
      '• Cabin-Aware Reverse Beep: Імпульсивний тон (1080-1200 Hz смуга) циклюючи ввімкнено 170мс / вимкнено 480мс. В режимі кабіни бип гучний (1.25×). В режимі зовні майже беззвучний (0.10×). Відображає реальну поведінку попередження про задню передачу.'  ))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Routing and Outputs', 'Роутинг і виходи'))
    r.ImGui_TextWrapped(ctx, tr(
      'Master tab can auto-build a routing folder with one child track per output bus and clean it safely.',
      'У Master можна автозібрати роутинг-папку з дочірнім треком для кожної шини й безпечно її очистити.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Car Name controls folder naming as Car "Name".',
      'Car Name задає назву папки у форматі Car "Name".'))
    r.ImGui_Dummy(ctx, 0, 4)
    r.ImGui_TextWrapped(ctx, tr(
      'Post-processing tips: Place Engine Core and Exhaust in short room reverbs (pre-delay 0-5ms, RT60 50-150ms) to give acoustic body. Apply narrow EQ cuts at 200-400 Hz on Mech/Whine to clean up box resonance. Use Chorus + light Overdrive on Brakes for gritty texture. Pan outputs to match vehicle position in frame.',
      'Підказки пост-обробки: Помістіть Engine Core та Exhaust у короткі кімнатні реверберації (pre-delay 0-5ms, RT60 50-150ms) для акустичного тіла. Застосуйте вузькі EQ-порізи на 200-400 Гц у Mech/Whine для очищення резонансів. Використовуйте Chorus + легкий Overdrive на Brakes для текстури. Панорамуйте виходи відповідно до позиції авто в кадрі.'))
    r.ImGui_Separator(ctx)

    -- KILLER FEATURE box
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x1A3A1AFF)
    if r.ImGui_BeginChild(ctx, '##killer_feat', 0, 130, 0, r.ImGui_WindowFlags_NoScrollbar()) then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x55FF55FF)
      r.ImGui_Text(ctx, tr('  >> KILLER FEATURE: Hidden Modulation Sources <<', '  >> KILLER FEATURE: Приховані джерела модуляції <<'))
      r.ImGui_PopStyleColor(ctx)
      r.ImGui_TextWrapped(ctx, tr(
        'slider50 (Live RPM), slider51 (Live Speed km/h), slider52 (Live Temperature %) are updated live by the JSFX. They are hidden from UI but accessible as REAPER parameter modulation targets.',
        'slider50 (Live RPM), slider51 (Live Speed km/h), slider52 (Live Temperature %) оновлюються двигуном у реальному часі. Приховані від UI, але доступні як цілі Parameter Modulation у REAPER.'))
      r.ImGui_TextWrapped(ctx, tr(
        'Open any FX > Parameter Modulation > Link from FX param > pick MotorSynth > slider50/51/52. Examples: Live RPM -> reverb size (room grows with revs). Live Speed -> wind filter cutoff. Live Temperature -> Drive/Saturation for hot engine character.',
        'Відкрийте будь-який FX → Parameter Modulation → Link from FX param → оберіть MotorSynth → slider50/51/52. Приклади: Live RPM → розмір реверберації. Live Speed → зріз фільтра вітру. Live Temperature → Drive/Saturation для гарячого двигуна.'))
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('RPM Target and Rev Limiter', 'RPM Target і Rev Limiter'))
    r.ImGui_TextWrapped(ctx, tr(
      'RPM Target sets the ceiling of throttle response — the RPM the engine tries to reach when pedal is fully open.',
      'RPM Target задає стелю реакції газу — оберти, яких двигун намагається досягти при повному натисненні педалі.'))
    r.ImGui_TextWrapped(ctx, tr(
      'In Direct mode: pedal linearly sweeps RPM from idle up to RPM Target. The gauge arc always spans from idle to RPM Target.',
      'У режимі Direct: педаль лінійно пересуває RPM від холостого ходу до RPM Target. Дуга тахометра завжди від idle до RPM Target.'))
    r.ImGui_TextWrapped(ctx, tr(
      'In Physics mode: RPM Target acts as the desired power band ceiling. Gearbox auto-shifts to stay below it in D, and rides it hard in S. In M (manual), it only limits the scheduler — user controls gears.',
      'У режимі Physics: RPM Target є бажаною межею потужнісної смуги. Коробка (D) перемикається, щоб залишатись нижче неї; в S — тримається впритул. У M RPM Target лише обмежує планувальник — перемикання ручне.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Rev Limiter is the absolute engine ceiling. When RPM reaches this value, fuel cuts and the engine sounds choppier. Set it 500-1000 RPM above RPM Target for a natural limiter bounce. For race cars, set both close together for aggressive limiter hits.',
      'Rev Limiter — абсолютна межа двигуна. Коли RPM досягає цього значення, паливо відрізається і двигун звучить рвано. Встановіть його на 500-1000 RPM вище RPM Target для природнього відскоку. Для гоночних авто — тримайте обидва близько для агресивних відсічок.'))
    r.ImGui_Separator(ctx)

    r.ImGui_Text(ctx, tr('Exhaust System and Control', 'Система вихлопу та управління'))
    r.ImGui_TextWrapped(ctx, tr(
      'The exhaust is a physically modeled waveguide delay line. Each combustion pulse travels down a virtual pipe, reflects, and returns — creating resonant exhaust tone layered over the raw engine note.',
      'Вихлоп — це фізично змодельована хвилеводна лінія затримки. Кожен імпульс горіння проходить по віртуальній трубі, відбивається та повертається — створюючи резонансний тон поверх сирого звуку двигуна.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Exhaust Type controls pipe length and feedback: Stock — long pipe with soft feedback (rounded, muffled). Sport — medium pipe, brighter tone, more overtone content. Straight Pipe — short tight waveguide, sharp metallic blast with maximum rasp.',
      'Exhaust Type керує довжиною труби та зворотнім зв\'язком: Stock — довга труба, м\'який feedback (округлий, приглушений). Sport — середня труба, яскравіший тон. Straight Pipe — коротка пружна хвилевід, різкий металевий удар з максимальним rasp.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Muffler (0-100) is a low-pass filter on the waveguide output. At 0 the exhaust is fully open — bright, raw and loud. At 100 it is heavily muffled — dark and suppressed. Mid values (40-65) give a natural road car character.',
      'Muffler (0-100) — фільтр нижніх частот на виході хвилеводу. При 0 вихлоп повністю відкритий — яскравий, сирий і гучний. При 100 — сильно заглушений і темний. Середні значення (40-65) дають характер звичайного дорожнього авто.'))
    r.ImGui_TextWrapped(ctx, tr(
      'Crackle/Backfire generates combustion pops on overrun. Anti-Lag (ALS) Bangs adds shotgun-style explosions routed to a dedicated output (Out: Exhaust Explosions). Both are triggered by fast throttle release above 30% load.',
      'Crackle/Backfire генерує хлопки горіння при скиданні газу. Anti-Lag (ALS) Bangs додає дробовикові вибухи, виведені на окремий вихід (Out: Exhaust Explosions). Обидва активуються швидким відпуском газу при навантаженні >30%.'))
    r.ImGui_Separator(ctx)
  end
  r.ImGui_End(ctx)
end

-- ===================================================================
-- PRESETS
-- ===================================================================
local PRESET_LIST = {
  {
    name = 'Stock Balanced',
    vals = {
      [P.mode]=1, [P.trans_mode]=0, [P.shift_intent]=0,
      [P.rpm_tgt]=3200, [P.rev_lim]=6500,
      [P.cylinders]=3, [P.eng_size]=65, [P.character]=0, [P.roughness]=45, [P.cold_start]=20,
      [P.mech_noise]=20, [P.trans_whine]=48, [P.shift_jolt]=70, [P.shift_scrape]=20,
      [P.valve_train]=52, [P.belt_pulley]=46, [P.chain_rattle]=56,
      [P.exh_type]=2, [P.muffler]=45, [P.turbo]=60, [P.intake]=50, [P.crackle]=65, [P.als]=20,
      [P.bf_body]=62, [P.bf_res]=48,
      [P.brk_squeal]=82, [P.brk_overtone]=68, [P.brk_pitch]=35, [P.brk_trim]=-2, [P.brk_pad]=45,
      [P.road_noise]=55, [P.road_surface]=1, [P.drift_aggr]=62, [P.chorus_color]=55, [P.wind_noise]=5,
      [P.drive]=20, [P.high_cut]=30, [P.stereo_width]=50,
      [P.sci_mode]=0, [P.sci_ev]=22, [P.sci_inv]=18, [P.sci_regen]=24, [P.sci_bias]=46,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=50, [P.horn_on]=0, [P.horn_level]=56,
      [P.idle_pop]=36, [P.fuel_pump]=46, [P.knock_ping]=34, [P.regen_timbre]=58,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'GT Sport',
    vals = {
      [P.mode]=1, [P.trans_mode]=1, [P.shift_intent]=4,
      [P.rpm_tgt]=5200, [P.rev_lim]=7800,
      [P.cylinders]=5, [P.eng_size]=82, [P.character]=22, [P.roughness]=32, [P.cold_start]=8,
      [P.mech_noise]=30, [P.trans_whine]=56, [P.shift_jolt]=74, [P.shift_scrape]=24,
      [P.valve_train]=58, [P.belt_pulley]=62, [P.chain_rattle]=44,
      [P.exh_type]=1, [P.muffler]=30, [P.turbo]=72, [P.intake]=62, [P.crackle]=58, [P.als]=18,
      [P.bf_body]=68, [P.bf_res]=54,
      [P.brk_squeal]=70, [P.brk_overtone]=62, [P.brk_pitch]=33, [P.brk_trim]=-1, [P.brk_pad]=38,
      [P.road_noise]=45, [P.road_surface]=0, [P.drift_aggr]=35, [P.chorus_color]=28, [P.wind_noise]=14,
      [P.drive]=34, [P.high_cut]=44, [P.stereo_width]=62,
      [P.sci_mode]=0, [P.sci_ev]=18, [P.sci_inv]=16, [P.sci_regen]=20, [P.sci_bias]=42,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=52, [P.horn_on]=0, [P.horn_level]=58,
      [P.idle_pop]=32, [P.fuel_pump]=42, [P.knock_ping]=40, [P.regen_timbre]=58,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Drift Beast',
    vals = {
      [P.mode]=1, [P.trans_mode]=2, [P.shift_intent]=3,
      [P.rpm_tgt]=5900, [P.rev_lim]=7600,
      [P.cylinders]=3, [P.eng_size]=78, [P.character]=40, [P.roughness]=54, [P.cold_start]=6,
      [P.mech_noise]=36, [P.trans_whine]=60, [P.shift_jolt]=82, [P.shift_scrape]=42,
      [P.valve_train]=72, [P.belt_pulley]=55, [P.chain_rattle]=68,
      [P.exh_type]=2, [P.muffler]=18, [P.turbo]=68, [P.intake]=64, [P.crackle]=84, [P.als]=42,
      [P.bf_body]=86, [P.bf_res]=76,
      [P.brk_squeal]=88, [P.brk_overtone]=76, [P.brk_pitch]=40, [P.brk_trim]=1, [P.brk_pad]=60,
      [P.road_noise]=70, [P.road_surface]=1, [P.drift_aggr]=92, [P.chorus_color]=78, [P.wind_noise]=22,
      [P.drive]=42, [P.high_cut]=40, [P.stereo_width]=70,
      [P.sci_mode]=1, [P.sci_ev]=34, [P.sci_inv]=28, [P.sci_regen]=36, [P.sci_bias]=54,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=58, [P.horn_on]=0, [P.horn_level]=66,
      [P.idle_pop]=48, [P.fuel_pump]=42, [P.knock_ping]=52, [P.regen_timbre]=64,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Rally Gravel',
    vals = {
      [P.mode]=1, [P.trans_mode]=1, [P.shift_intent]=3,
      [P.rpm_tgt]=4700, [P.rev_lim]=7200,
      [P.cylinders]=3, [P.eng_size]=72, [P.character]=18, [P.roughness]=50, [P.cold_start]=10,
      [P.mech_noise]=28, [P.trans_whine]=46, [P.shift_jolt]=66, [P.shift_scrape]=28,
      [P.valve_train]=62, [P.belt_pulley]=50, [P.chain_rattle]=64,
      [P.exh_type]=1, [P.muffler]=40, [P.turbo]=64, [P.intake]=58, [P.crackle]=48, [P.als]=16,
      [P.bf_body]=58, [P.bf_res]=52,
      [P.brk_squeal]=74, [P.brk_overtone]=61, [P.brk_pitch]=31, [P.brk_trim]=-1, [P.brk_pad]=42,
      [P.road_noise]=80, [P.road_surface]=2, [P.drift_aggr]=68, [P.chorus_color]=56, [P.wind_noise]=18,
      [P.drive]=26, [P.high_cut]=36, [P.stereo_width]=54,
      [P.sci_mode]=0, [P.sci_ev]=24, [P.sci_inv]=20, [P.sci_regen]=28, [P.sci_bias]=44,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=46, [P.horn_on]=0, [P.horn_level]=54,
      [P.idle_pop]=40, [P.fuel_pump]=48, [P.knock_ping]=38, [P.regen_timbre]=62,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Hyper Track',
    vals = {
      [P.mode]=1, [P.trans_mode]=1, [P.shift_intent]=4,
      [P.rpm_tgt]=6800, [P.rev_lim]=8600,
      [P.cylinders]=5, [P.eng_size]=90, [P.character]=30, [P.roughness]=22, [P.cold_start]=4,
      [P.mech_noise]=24, [P.trans_whine]=54, [P.shift_jolt]=72, [P.shift_scrape]=18,
      [P.valve_train]=52, [P.belt_pulley]=70, [P.chain_rattle]=40,
      [P.exh_type]=2, [P.muffler]=14, [P.turbo]=76, [P.intake]=68, [P.crackle]=52, [P.als]=14,
      [P.bf_body]=74, [P.bf_res]=64,
      [P.brk_squeal]=62, [P.brk_overtone]=58, [P.brk_pitch]=29, [P.brk_trim]=-2, [P.brk_pad]=30,
      [P.road_noise]=38, [P.road_surface]=0, [P.drift_aggr]=24, [P.chorus_color]=20, [P.wind_noise]=26,
      [P.drive]=38, [P.high_cut]=52, [P.stereo_width]=58,
      [P.sci_mode]=0, [P.sci_ev]=20, [P.sci_inv]=18, [P.sci_regen]=22, [P.sci_bias]=40,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=50, [P.horn_on]=0, [P.horn_level]=60,
      [P.idle_pop]=28, [P.fuel_pump]=36, [P.knock_ping]=46, [P.regen_timbre]=56,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Electric Urban EV',
    vals = {
      [P.mode]=1, [P.trans_mode]=0, [P.shift_intent]=1,
      [P.rpm_tgt]=3600, [P.rev_lim]=6200,
      [P.cylinders]=3, [P.eng_size]=55, [P.character]=-8, [P.roughness]=8, [P.cold_start]=6,
      [P.mech_noise]=10, [P.trans_whine]=26, [P.shift_jolt]=34, [P.shift_scrape]=12,
      [P.valve_train]=14, [P.belt_pulley]=22, [P.chain_rattle]=18,
      [P.exh_type]=0, [P.muffler]=80, [P.turbo]=0, [P.intake]=8, [P.crackle]=8, [P.als]=0,
      [P.bf_body]=10, [P.bf_res]=10,
      [P.brk_squeal]=58, [P.brk_overtone]=44, [P.brk_pitch]=30, [P.brk_trim]=-3, [P.brk_pad]=26,
      [P.road_noise]=42, [P.road_surface]=0, [P.drift_aggr]=20, [P.chorus_color]=18, [P.wind_noise]=20,
      [P.drive]=14, [P.high_cut]=40, [P.stereo_width]=56,
      [P.sci_mode]=2, [P.sci_ev]=86, [P.sci_inv]=72, [P.sci_regen]=70, [P.sci_bias]=84,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=52, [P.horn_on]=0, [P.horn_level]=62,
      [P.idle_pop]=6, [P.fuel_pump]=28, [P.knock_ping]=4, [P.regen_timbre]=72,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Hybrid Commute',
    vals = {
      [P.mode]=1, [P.trans_mode]=0, [P.shift_intent]=1,
      [P.rpm_tgt]=4300, [P.rev_lim]=6800,
      [P.cylinders]=3, [P.eng_size]=62, [P.character]=-4, [P.roughness]=24, [P.cold_start]=12,
      [P.mech_noise]=18, [P.trans_whine]=38, [P.shift_jolt]=48, [P.shift_scrape]=16,
      [P.valve_train]=28, [P.belt_pulley]=34, [P.chain_rattle]=30,
      [P.exh_type]=0, [P.muffler]=62, [P.turbo]=18, [P.intake]=20, [P.crackle]=18, [P.als]=4,
      [P.bf_body]=20, [P.bf_res]=18,
      [P.brk_squeal]=60, [P.brk_overtone]=48, [P.brk_pitch]=31, [P.brk_trim]=-2, [P.brk_pad]=30,
      [P.road_noise]=44, [P.road_surface]=0, [P.drift_aggr]=24, [P.chorus_color]=24, [P.wind_noise]=16,
      [P.drive]=18, [P.high_cut]=38, [P.stereo_width]=54,
      [P.sci_mode]=1, [P.sci_ev]=62, [P.sci_inv]=52, [P.sci_regen]=60, [P.sci_bias]=72,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=52, [P.horn_on]=0, [P.horn_level]=58,
      [P.idle_pop]=20, [P.fuel_pump]=34, [P.knock_ping]=16, [P.regen_timbre]=62,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Police Interceptor',
    vals = {
      [P.mode]=1, [P.trans_mode]=1, [P.shift_intent]=4,
      [P.rpm_tgt]=5600, [P.rev_lim]=7600,
      [P.cylinders]=4, [P.eng_size]=80, [P.character]=18, [P.roughness]=28, [P.cold_start]=10,
      [P.mech_noise]=30, [P.trans_whine]=58, [P.shift_jolt]=76, [P.shift_scrape]=26,
      [P.valve_train]=54, [P.belt_pulley]=56, [P.chain_rattle]=46,
      [P.exh_type]=1, [P.muffler]=30, [P.turbo]=56, [P.intake]=48, [P.crackle]=40, [P.als]=12,
      [P.bf_body]=48, [P.bf_res]=40,
      [P.brk_squeal]=78, [P.brk_overtone]=66, [P.brk_pitch]=34, [P.brk_trim]=-1, [P.brk_pad]=42,
      [P.road_noise]=54, [P.road_surface]=1, [P.drift_aggr]=44, [P.chorus_color]=34, [P.wind_noise]=18,
      [P.drive]=30, [P.high_cut]=42, [P.stereo_width]=60,
      [P.sci_mode]=0, [P.sci_ev]=24, [P.sci_inv]=22, [P.sci_regen]=28, [P.sci_bias]=42,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=82, [P.horn_on]=0, [P.horn_level]=84,
      [P.idle_pop]=30, [P.fuel_pump]=40, [P.knock_ping]=44, [P.regen_timbre]=68,
      [P.speed_ovr]=0,
    }
  },
  {
    name = 'Mountain Descent',
    vals = {
      [P.mode]=1, [P.trans_mode]=0, [P.shift_intent]=3,
      [P.rpm_tgt]=4200, [P.rev_lim]=6700,
      [P.cylinders]=3, [P.eng_size]=70, [P.character]=-6, [P.roughness]=40, [P.cold_start]=14,
      [P.mech_noise]=26, [P.trans_whine]=52, [P.shift_jolt]=62, [P.shift_scrape]=24,
      [P.valve_train]=46, [P.belt_pulley]=52, [P.chain_rattle]=56,
      [P.exh_type]=0, [P.muffler]=54, [P.turbo]=28, [P.intake]=26, [P.crackle]=24, [P.als]=6,
      [P.bf_body]=30, [P.bf_res]=24,
      [P.brk_squeal]=86, [P.brk_overtone]=76, [P.brk_pitch]=36, [P.brk_trim]=0, [P.brk_pad]=58,
      [P.road_noise]=62, [P.road_surface]=1, [P.drift_aggr]=38, [P.chorus_color]=46, [P.wind_noise]=12,
      [P.drive]=24, [P.high_cut]=34, [P.stereo_width]=52,
      [P.sci_mode]=0, [P.sci_ev]=20, [P.sci_inv]=18, [P.sci_regen]=26, [P.sci_bias]=38,
      [P.siren_on]=0, [P.siren_type]=0, [P.siren_level]=48, [P.horn_on]=0, [P.horn_level]=54,
      [P.idle_pop]=38, [P.fuel_pump]=52, [P.knock_ping]=28, [P.regen_timbre]=76,
      [P.speed_ovr]=0,
    }
  },
}

local PRESET_SEC = 'SBP_MotorSynth_UI_Presets'
local PRESET_ITEMS = ''

local function collectCurrentPresetVals()
  local vals = {}
  for idx, def in pairs(PDEF) do
    if type(idx) == 'number' and def then
      vals[idx] = state.params[idx] or def[3]
    end
  end
  return vals
end

local function serializePresetVals(vals)
  local keys = {}
  for idx, _ in pairs(vals) do keys[#keys + 1] = idx end
  table.sort(keys)
  local parts = {}
  for _, idx in ipairs(keys) do
    parts[#parts + 1] = string.format('%d=%.10f', idx, vals[idx])
  end
  return table.concat(parts, '|')
end

local function deserializePresetVals(data)
  local vals = {}
  for token in string.gmatch(data or '', '([^|]+)') do
    local k, v = token:match('^(%-?%d+)=([%+%-%.%deE]+)$')
    if k and v then vals[tonumber(k)] = tonumber(v) end
  end
  return vals
end

local function rebuildPresetItems()
  local names = {}
  for i, p in ipairs(PRESET_LIST) do
    names[i] = p.name
  end
  PRESET_ITEMS = table.concat(names, '\0') .. '\0'
end

local function saveUserPresetsToExtState()
  local old_count = tonumber(r.GetExtState(PRESET_SEC, 'count')) or 0
  local users = {}
  for _, p in ipairs(PRESET_LIST) do
    if p.is_user then users[#users + 1] = p end
  end

  r.SetExtState(PRESET_SEC, 'count', tostring(#users), true)
  for i, p in ipairs(users) do
    r.SetExtState(PRESET_SEC, 'name_' .. i, p.raw_name or p.name, true)
    r.SetExtState(PRESET_SEC, 'data_' .. i, serializePresetVals(p.vals or {}), true)
  end
  for i = #users + 1, old_count do
    if r.DeleteExtState then
      r.DeleteExtState(PRESET_SEC, 'name_' .. i, true)
      r.DeleteExtState(PRESET_SEC, 'data_' .. i, true)
    else
      r.SetExtState(PRESET_SEC, 'name_' .. i, '', true)
      r.SetExtState(PRESET_SEC, 'data_' .. i, '', true)
    end
  end
end

local function loadUserPresetsFromExtState()
  local count = tonumber(r.GetExtState(PRESET_SEC, 'count')) or 0
  for i = 1, count do
    local raw_name = r.GetExtState(PRESET_SEC, 'name_' .. i)
    local data = r.GetExtState(PRESET_SEC, 'data_' .. i)
    local vals = deserializePresetVals(data)
    if raw_name ~= '' and next(vals) then
      PRESET_LIST[#PRESET_LIST + 1] = {
        name = 'User: ' .. raw_name,
        raw_name = raw_name,
        vals = vals,
        is_user = true,
      }
    end
  end
end

local function saveCurrentAsUserPreset(raw_name)
  local name = (raw_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if name == '' then
    r.ShowConsoleMsg('[MotorSynth UI] Preset name is empty.\n')
    return
  end

  local vals = collectCurrentPresetVals()
  local found_idx = nil
  for i, p in ipairs(PRESET_LIST) do
    if p.is_user and p.raw_name == name then
      found_idx = i
      break
    end
  end

  if found_idx then
    PRESET_LIST[found_idx].vals = vals
    state.preset_idx = found_idx - 1
  else
    PRESET_LIST[#PRESET_LIST + 1] = {
      name = 'User: ' .. name,
      raw_name = name,
      vals = vals,
      is_user = true,
    }
    state.preset_idx = #PRESET_LIST - 1
  end

  rebuildPresetItems()
  saveUserPresetsToExtState()
end

loadUserPresetsFromExtState()
rebuildPresetItems()

local function applyPreset(preset_idx)
  if not state.linked then return end
  local p = PRESET_LIST[preset_idx]
  if not p or not p.vals then return end
  for idx, val in pairs(p.vals) do
    setParam(idx, val)
  end
end

-- ===================================================================
-- ANIMATED TACHOMETER
-- ===================================================================
local function drawTacho(ctx, cx, cy, rad)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local rpm_live   = state.params[P.rpm_live] or (state.params[P.rpm_tgt] or 3200)
  local rpm_target = state.params[P.rpm_tgt] or 3200
  local lim_rpm    = state.params[P.rev_lim] or 6500
  local max_rpm = 9000.0

  -- Smooth needle follow
  state.disp_rpm = lerpf(state.disp_rpm, rpm_live, 0.09)

  local norm_live = clamp((state.disp_rpm) / max_rpm, 0, 1)
  local norm_tgt  = clamp(rpm_target / max_rpm, 0, 1)
  local lim_norm  = clamp(lim_rpm / max_rpm, 0, 1)

  -- Zone angles
  local a_lim    = TACHO_START + lim_norm  * TACHO_SPAN
  local a_yellow = TACHO_START + 0.70      * TACHO_SPAN
  local a_end    = TACHO_START +            TACHO_SPAN
  local a_target = TACHO_START + norm_tgt   * TACHO_SPAN
  local a_needle = TACHO_START + norm_live  * TACHO_SPAN

  -- Background ring
  arc(dl, cx, cy, rad + 4,  TACHO_START, a_end, 0x18202800, 10, 2)
  arc(dl, cx, cy, rad + 4,  TACHO_START, a_end, C.BORDER,    1, 48)

  -- Colored zones (thick band arcs, semi-transparent background)
  arcBand(dl, cx, cy, rad - 7, rad + 2, TACHO_START, a_yellow, 0x1E4A1C60, 40)
  arcBand(dl, cx, cy, rad - 7, rad + 2, a_yellow, a_lim,   0x4A3C0C60, 24)
  arcBand(dl, cx, cy, rad - 7, rad + 2, a_lim,    a_end,   0x4A100A60, 16)

  -- Tick marks with RPM labels
  for i = 0, 9 do
    local tn = i / 9.0
    local ta = TACHO_START + tn * TACHO_SPAN
    local is_major = (i % 3 == 0)
    local tk_len   = is_major and 11 or 5
    local tk_w     = is_major and 2.0 or 1.0
    local tk_col   = C.TEXT_DIM
    if tn > lim_norm       then tk_col = 0x7A1A0EFF
    elseif tn > 0.70       then tk_col = 0x7A6218FF
    end
    r.ImGui_DrawList_AddLine(dl,
      cx + math.cos(ta) * (rad - tk_len), cy + math.sin(ta) * (rad - tk_len),
      cx + math.cos(ta) *  rad,           cy + math.sin(ta) *  rad,
      tk_col, tk_w)
    if is_major then
      local rpm_lbl = math.floor(i * max_rpm / 9 / 1000 + 0.5) .. 'k'
      local lx = cx + math.cos(ta) * (rad - 22) - (i == 0 and 3 or 7)
      local ly = cy + math.sin(ta) * (rad - 22) - 7
      r.ImGui_DrawList_AddText(dl, lx, ly, C.TEXT_DIM, rpm_lbl)
    end
  end

  -- Rev limiter red mark
  r.ImGui_DrawList_AddLine(dl,
    cx + math.cos(a_lim) * (rad - 4), cy + math.sin(a_lim) * (rad - 4),
    cx + math.cos(a_lim) * (rad + 8), cy + math.sin(a_lim) * (rad + 8),
    C.RED, 2.5)

  -- Target sweep arc: controlled only by RPM Target slider
  if norm_tgt > 0.01 then
    arc(dl, cx, cy, rad - 10, TACHO_START, a_target, alphamix(C.GREEN, 0.5),  3, 44)
    arc(dl, cx, cy, rad - 11, TACHO_START, a_target, alphamix(C.GREEN, 0.18), 7, 44)
  end

  -- Needle
  local n_cos, n_sin = math.cos(a_needle), math.sin(a_needle)
  local nx = cx + n_cos * (rad - 16)
  local ny = cy + n_sin * (rad - 16)
  local tx = cx - n_cos * 12
  local ty = cy - n_sin * 12
  r.ImGui_DrawList_AddLine(dl, tx, ty, nx, ny, C.AMBER, 2.5)

  -- Center hub
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 8, 0x0A0C0EFF)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 5, C.AMBER)

  -- RPM digital readout
  local rpm_str = string.format('%d', math.floor(state.disp_rpm + 0.5))
  r.ImGui_DrawList_AddText(dl, cx - #rpm_str * 3.5, cy + 14, C.AMBER, rpm_str)
  r.ImGui_DrawList_AddText(dl, cx - 9, cy + 26, C.TEXT_DIM, 'RPM')
end

-- ===================================================================
-- GEAR BADGE
-- ===================================================================
local GEAR_LBL = {'N','1','2','3','4','5','6','R','P'}

local function drawGearBadge(ctx, cx, cy, sz)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local g  = math.floor(state.params[P.gear] or 0)
  local lbl = GEAR_LBL[g + 1] or 'N'
  local col  = lbl == 'N' and C.TEXT_DIM
            or lbl == 'P' and C.RED
            or lbl == 'R' and C.YELLOW
            or C.AMBER
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, sz, C.FRAME)
  r.ImGui_DrawList_AddCircle      (dl, cx, cy, sz, col, 0, 1.5)
  r.ImGui_DrawList_AddCircle      (dl, cx, cy, sz - 3, alphamix(col, 0.14), 0, 5)
  r.ImGui_DrawList_AddText(dl, cx - 6,  cy - 10, col, lbl)
end

-- ===================================================================
-- IGNITION BUTTON
-- ===================================================================
local function drawIgnButton(ctx)
  local dl    = r.ImGui_GetWindowDrawList(ctx)
  local ign   = math.floor(state.params[P.ignition] or 0)
  local t     = r.ImGui_GetTime(ctx)
  local pulse = ign == 1 and (0.65 + 0.35 * math.sin(t * 3.8)) or 0.0

  local bw, bh = 112, 36
  local px, py = r.ImGui_GetCursorScreenPos(ctx)

  r.ImGui_InvisibleButton(ctx, '##ignbtn', bw, bh)
  local hov     = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)

  if clicked and state.linked then
    setParam(P.ignition, ign == 1 and 0 or 1)
    ign = math.floor(state.params[P.ignition])
    pulse = ign == 1 and 1.0 or 0.0
  end

  -- Outer glow when on
  if ign == 1 then
    r.ImGui_DrawList_AddRectFilled(dl, px-4, py-4, px+bw+4, py+bh+4,
      alphamix(C.AMBER, pulse * 0.22), 10)
  end
  -- Body
  local bg = ign == 1 and math.floor(lerp(0x4A1A03FF, 0x7A2E08FF, pulse))
                       or (hov and 0x232A32FF or 0x181D22FF)
  r.ImGui_DrawList_AddRectFilled(dl, px, py, px+bw, py+bh, bg, 6)
  r.ImGui_DrawList_AddRect      (dl, px, py, px+bw, py+bh,
    ign == 1 and alphamix(C.AMBER, 0.55 + pulse * 0.45) or C.BORDER, 6, 0, 1)

  -- LED indicator
  local led_col = ign == 1 and alphamix(C.AMBER, 0.7 + pulse * 0.3) or C.TEXT_DIM
  r.ImGui_DrawList_AddCircleFilled(dl, px + 13, py + bh * 0.5, 5, led_col)

  -- Label
  local lbl_col = ign == 1 and alphamix(C.AMBER, 0.8 + pulse * 0.2) or C.TEXT_DIM
  local lbl_txt = ign == 1 and 'IGNITION ON' or 'IGNITION OFF'
  r.ImGui_DrawList_AddText(dl, px + 23, py + bh * 0.5 - 6, lbl_col, lbl_txt)
end

-- ===================================================================
-- PEDAL WIDGET  (vertical interactive bar, drag-up = increase)
-- ===================================================================
local function drawPedal(ctx, lbl, idx, fill_col, bg_col, pw, ph)
  local dl  = r.ImGui_GetWindowDrawList(ctx)
  local def = PDEF[idx]
  local cur = state.params[idx] or def[3]
  local LABEL_H = 18
  local px, py = r.ImGui_GetCursorScreenPos(ctx)

  -- Single button covers bar + label so SameLine works correctly
  r.ImGui_InvisibleButton(ctx, '##ped' .. idx, pw, ph + LABEL_H)
  local hov    = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local key    = 'p' .. idx

  -- Drag tracking
  if active and state.linked then
    if not state.ped_was_active[key] then
      state.ped_drag_start[key] = cur
    end
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
    local delta_n = -dy / ph
    local new_v   = (state.ped_drag_start[key] or cur) + delta_n * (def[2] - def[1])
    setParam(idx, new_v)
    cur = state.params[idx]
  end
  state.ped_was_active[key] = active

  local norm    = clamp((cur - def[1]) / (def[2] - def[1]), 0, 1)
  local fill_h  = math.max(norm * ph, 1)
  local alpha   = (active or hov) and 1.0 or 0.72
  local border  = hov and C.AMBER or (active and C.GOLD or C.BORDER)

  -- Background
  r.ImGui_DrawList_AddRectFilled(dl, px, py, px+pw, py+ph, bg_col, 4)

  -- Graduation lines (every 10%)
  for step = 1, 9 do
    local gy = py + ph - step * ph * 0.1
    r.ImGui_DrawList_AddLine(dl, px+2, gy, px+pw-2, gy, C.GRID, 1)
  end

  -- Fill bar
  r.ImGui_DrawList_AddRectFilled(dl,
    px, py + ph - fill_h, px+pw, py+ph,
    alphamix(fill_col, alpha), 4)

  -- Shine on top of fill
  if fill_h > 4 then
    r.ImGui_DrawList_AddLine(dl,
      px+3, py+ph-fill_h+2, px+pw-3, py+ph-fill_h+2,
      alphamix(0xFFFFFFFF, 0.10 + norm * 0.12), 1.5)
  end

  -- Border
  r.ImGui_DrawList_AddRect(dl, px, py, px+pw, py+ph, border, 4, 0, 1.2)
  if active then
    r.ImGui_DrawList_AddRect(dl, px-2, py-2, px+pw+2, py+ph+2,
      alphamix(fill_col, 0.30), 6, 0, 1)
  end

  -- Value text
  local val_str = string.format('%d', math.floor(cur + 0.5))
  local tx = px + pw * 0.5 - #val_str * 4
  local ty = py + ph * 0.5 - 7
  r.ImGui_DrawList_AddText(dl, tx, ty, alphamix(0xFFFFFFFF, 0.55 + norm * 0.45), val_str)

  -- Label in label area (within button bounds, below bar)
  local lx = px + pw * 0.5 - #lbl * 3.5
  r.ImGui_DrawList_AddText(dl, lx, py + ph + 4, C.TEXT_DIM, lbl)
end

-- ===================================================================
-- TAB: COCKPIT
-- ===================================================================
-- ===================================================================
-- GEAR STRIP  (vertical P / R / N / 1–6 selector)
-- ===================================================================
local GEAR_STOPS = {
  {val=8, lbl='P', ac=C.RED},
  {val=7, lbl='R', ac=C.YELLOW},
  {val=0, lbl='N', ac=C.TEAL},
  {val=1, lbl='1', ac=C.AMBER},
  {val=2, lbl='2', ac=C.AMBER},
  {val=3, lbl='3', ac=C.AMBER},
  {val=4, lbl='4', ac=C.AMBER},
  {val=5, lbl='5', ac=C.AMBER},
  {val=6, lbl='6', ac=C.AMBER},
}

local function drawGearStrip(ctx, sw, sh)
  local dl     = r.ImGui_GetWindowDrawList(ctx)
  local px, py = r.ImGui_GetCursorScreenPos(ctx)
  local cur_g  = math.floor(state.params[P.gear] or 0)
  local cell_h = sh / #GEAR_STOPS

  r.ImGui_InvisibleButton(ctx, '##gstrip', sw, sh)
  local strip_hov = r.ImGui_IsItemHovered(ctx)
  local strip_clk = r.ImGui_IsItemClicked(ctx, 0)
  local mx, my = r.ImGui_GetMousePos(ctx)

  r.ImGui_DrawList_AddRectFilled(dl, px, py, px+sw, py+sh, C.FRAME, 4)
  r.ImGui_DrawList_AddRect      (dl, px, py, px+sw, py+sh, C.BORDER, 4, 0, 1)

  for i, stop in ipairs(GEAR_STOPS) do
    local cy   = py + (i-1) * cell_h
    local act  = (cur_g == stop.val)
    local chov = strip_hov and my >= cy and my < cy + cell_h
    if act then
      r.ImGui_DrawList_AddRectFilled(dl, px+1, cy+1, px+sw-1, cy+cell_h-1,
        alphamix(stop.ac, 0.18), 3)
      r.ImGui_DrawList_AddRectFilled(dl, px+sw-4, cy+2, px+sw-1, cy+cell_h-2, stop.ac, 2)
    elseif chov then
      r.ImGui_DrawList_AddRectFilled(dl, px+1, cy+1, px+sw-1, cy+cell_h-1, 0x1E2830FF, 3)
    end
    if i > 1 then
      r.ImGui_DrawList_AddLine(dl, px+3, cy, px+sw-3, cy, C.BORDER, 1)
    end
    local lbl_col = act  and stop.ac
                  or chov and alphamix(C.TEXT, 0.6)
                  or C.TEXT_DIM
    r.ImGui_DrawList_AddText(dl,
      math.floor(px + sw*0.5 - #stop.lbl*4),
      math.floor(cy + cell_h*0.5 - 7),
      lbl_col, stop.lbl)
    if strip_clk and chov and state.linked then
      setParam(P.gear, stop.val)
    end
  end
end

-- ===================================================================
-- SPEEDOMETER
-- ===================================================================
local function drawSpeedo(ctx, cx, cy, rad)
  local dl  = r.ImGui_GetWindowDrawList(ctx)
  local spd = state.params[P.speed_live] or 0
  local temp_n = clamp((state.params[P.temp_live] or 0) / 100.0, 0, 1)
  state.disp_spd = lerpf(state.disp_spd, spd, 0.09)
  local MAX_SPD  = 280.0
  local norm_spd = clamp(state.disp_spd / MAX_SPD, 0, 1)
  local a_end    = TACHO_START + TACHO_SPAN
  local a_needle = TACHO_START + norm_spd * TACHO_SPAN

  arc(dl, cx, cy, rad+4, TACHO_START, a_end, C.BORDER, 1, 48)
  arcBand(dl, cx, cy, rad-7, rad+2, TACHO_START, TACHO_START+0.57*TACHO_SPAN, 0x1C3D5060, 40)
  arcBand(dl, cx, cy, rad-7, rad+2, TACHO_START+0.57*TACHO_SPAN, a_end,       0x2E2A0C60, 16)

  for i = 0, 11 do
    local spd_v = i * 25
    local ta    = TACHO_START + (spd_v / MAX_SPD) * TACHO_SPAN
    local major = (i % 2 == 0)
    r.ImGui_DrawList_AddLine(dl,
      cx + math.cos(ta)*(rad-(major and 11 or 5)),
      cy + math.sin(ta)*(rad-(major and 11 or 5)),
      cx + math.cos(ta)*rad, cy + math.sin(ta)*rad,
      C.TEXT_DIM, major and 2.0 or 1.0)
    if major and spd_v <= 250 then
      local lbl = tostring(spd_v)
      r.ImGui_DrawList_AddText(dl,
        cx + math.cos(ta)*(rad-24) - #lbl*3.5,
        cy + math.sin(ta)*(rad-24) - 7,
        C.TEXT_DIM, lbl)
    end
  end

  if norm_spd > 0.01 then
    arc(dl, cx, cy, rad-10, TACHO_START, a_needle, alphamix(C.TEAL, 0.55), 3, 44)
    arc(dl, cx, cy, rad-11, TACHO_START, a_needle, alphamix(C.TEAL, 0.18), 7, 44)
  end
  local nc, ns = math.cos(a_needle), math.sin(a_needle)
  r.ImGui_DrawList_AddLine(dl, cx-nc*12, cy-ns*12, cx+nc*(rad-16), cy+ns*(rad-16), C.TEAL, 2.5)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 8, 0x0A0C0EFF)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 5, C.TEAL)

  local spd_str = string.format('%d', math.floor(state.disp_spd + 0.5))
  r.ImGui_DrawList_AddText(dl, cx - #spd_str*3.5, cy+14, C.TEAL, spd_str)
  r.ImGui_DrawList_AddText(dl, cx - 9,            cy+26, C.TEXT_DIM, 'km/h')

  -- Vertical temperature sensor on the side to avoid overlap with km/h
  local tcol = temp_n < 0.45 and C.TEAL or (temp_n < 0.75 and C.YELLOW or C.RED)
  local tube_w = 8
  local tube_x1 = cx + rad + 16
  local tube_x2 = tube_x1 + tube_w
  local tube_y1 = cy - 30
  local tube_y2 = cy + 22
  local fill_h = (tube_y2 - tube_y1) * temp_n
  local bulb_cx = tube_x1 + tube_w * 0.5
  local bulb_cy = tube_y2 + 6
  local bulb_r = 7.0

  r.ImGui_DrawList_AddRectFilled(dl, tube_x1, tube_y1, tube_x2, tube_y2, 0x1A2026FF, 3)
  if fill_h > 0.5 then
    r.ImGui_DrawList_AddRectFilled(dl, tube_x1 + 1, tube_y2 - fill_h, tube_x2 - 1, tube_y2, alphamix(tcol, 0.92), 2)
  end
  -- Small neck to visually connect tube and bulb
  r.ImGui_DrawList_AddRectFilled(dl, tube_x1 + 1, tube_y2 - 1, tube_x2 - 1, bulb_cy, alphamix(tcol, 0.88), 2)
  r.ImGui_DrawList_AddRect(dl, tube_x1, tube_y1, tube_x2, tube_y2, C.BORDER, 3, 0, 1)
  r.ImGui_DrawList_AddCircleFilled(dl, bulb_cx, bulb_cy, bulb_r, alphamix(tcol, 0.95))
  r.ImGui_DrawList_AddCircle(dl, bulb_cx, bulb_cy, bulb_r, C.BORDER, 0, 1)
  local t_lbl = 'TEMP'
  r.ImGui_DrawList_AddText(dl, bulb_cx - #t_lbl * 3.5, bulb_cy + bulb_r + 3, C.TEXT_DIM, t_lbl)
end

-- ===================================================================
-- TAB: COCKPIT
-- ===================================================================
local function tabCockpit(ctx)
  local GRAD = 84
  local GW   = GRAD * 2 + 16
  local SW   = 42
  local GAP  = 8

  local tfl = r.ImGui_TableFlags_SizingStretchProp()
  if not r.ImGui_BeginTable(ctx, 'cpk_tbl', 3, tfl) then return end
  r.ImGui_TableSetupColumn(ctx, 'cp1', r.ImGui_TableColumnFlags_WidthStretch(), 0.22)
  r.ImGui_TableSetupColumn(ctx, 'cp2', r.ImGui_TableColumnFlags_WidthStretch(), 0.56)
  r.ImGui_TableSetupColumn(ctx, 'cp3', r.ImGui_TableColumnFlags_WidthStretch(), 0.22)

  r.ImGui_TableNextColumn(ctx)
  secHdr(ctx, tr('PEDALS', 'ПЕДАЛІ'), C.AMBER)
  r.ImGui_Dummy(ctx, 0, 6)
  local avail_l = r.ImGui_GetContentRegionAvail(ctx)
  local PEDAL_W, PEDAL_H = 58, 150
  r.ImGui_SetCursorPosX(ctx,
    r.ImGui_GetCursorPosX(ctx) + math.max(0, (avail_l - PEDAL_W*2 - 10) * 0.5))
  drawPedal(ctx, 'THR', P.throttle, C.AMBER, 0x1A1208FF, PEDAL_W, PEDAL_H)
  r.ImGui_SameLine(ctx, 0, 10)
  drawPedal(ctx, 'BRK', P.brake, C.RED, 0x1A0908FF, PEDAL_W, PEDAL_H)
  r.ImGui_Dummy(ctx, 0, 10)
  secHdr(ctx, tr('IGNITION', 'ЗАПАЛЕННЯ'), C.AMBER)
  local ign_w = 112
  local ign_av = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetCursorPosX(ctx,
    r.ImGui_GetCursorPosX(ctx) + math.max(0, (ign_av - ign_w) * 0.5))
  drawIgnButton(ctx)

  r.ImGui_Dummy(ctx, 0, 10)
  secHdr(ctx, tr('HANDBRAKE', 'РУЧНИК'), C.RED)
  local hb_val = state.params[P.handbrake] or 0
  local hb_w = 138
  local hb_av = r.ImGui_GetContentRegionAvail(ctx)
  local hb_x = r.ImGui_GetCursorPosX(ctx) + math.max(0, (hb_av - hb_w) * 0.5)
  r.ImGui_SetCursorPosX(ctx, hb_x)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x240B09FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3A1410FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x4D1A14FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0xC53A2AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xE54B37FF)
  sliderI(ctx, '##cockpit_handbrake_main', P.handbrake, hb_w)
  r.ImGui_PopStyleColor(ctx, 5)
  r.ImGui_SetCursorPosX(ctx, hb_x)
  r.ImGui_Text(ctx, string.format(tr('Lever %d%%', 'Важіль %d%%'), math.floor(hb_val + 0.5)))
  showTip(ctx, tr('Main handbrake lever. 0% released, 100% fully pulled.', 'Основний важіль ручника. 0% відпущено, 100% повністю затягнуто.'))

  r.ImGui_TableNextColumn(ctx)
  secHdr(ctx, tr('INSTRUMENTS', 'ПРИЛАДИ'), C.AMBER)
  r.ImGui_Dummy(ctx, 0, 4)
  local mid_w   = r.ImGui_GetContentRegionAvail(ctx)
  local total_w = GW + GAP + SW + GAP + GW
  local inst_base_x = r.ImGui_GetCursorPosX(ctx) + math.max(0, (mid_w - total_w) * 0.5)
  r.ImGui_SetCursorPosX(ctx, inst_base_x)

  local tsx, tsy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, '##tacho_area', GW, GW)
  r.ImGui_SameLine(ctx, 0, GAP)
  drawGearStrip(ctx, SW, GW)
  r.ImGui_SameLine(ctx, 0, GAP)
  local ssx, ssy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, '##speedo_area', GW, GW)

  local dl = r.ImGui_GetWindowDrawList(ctx)
  drawTacho(ctx, math.floor(tsx + GW * 0.5), math.floor(tsy + GW * 0.5), GRAD)
  drawSpeedo(ctx, math.floor(ssx + GW * 0.5), math.floor(ssy + GW * 0.5), GRAD)
  r.ImGui_DrawList_AddText(dl, tsx + GW * 0.5 - 18, tsy + 4, C.TEXT_DIM, 'TACHO')
  r.ImGui_DrawList_AddText(dl, ssx + GW * 0.5 - 18, ssy + 4, C.TEXT_DIM, 'SPEED')

  r.ImGui_Dummy(ctx, 0, 6)
  local turn_btn_w = 28
  local turn_gap = 6
  local turn_total_w = turn_btn_w * 2 + turn_gap
  local gear_center_x = inst_base_x + GW + GAP + SW * 0.5
  r.ImGui_SetCursorPosX(ctx, gear_center_x - turn_total_w * 0.5)
  local ind_mode = math.floor(state.params[P.ind_mode] or 0)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), ind_mode == 1 and 0x8A5F14FF or 0x2B2418FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), ind_mode == 1 and 0xA87418FF or 0x3A2E1EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), ind_mode == 1 and 0xC3871FFF or 0x4A3A24FF)
  if r.ImGui_Button(ctx, '<##turn_left_cockpit', turn_btn_w, 18) then
    setParam(P.ind_mode, ind_mode == 1 and 0 or 1)
  end
  r.ImGui_PopStyleColor(ctx, 3)
  r.ImGui_SameLine(ctx, 0, turn_gap)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), ind_mode == 2 and 0x8A5F14FF or 0x2B2418FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), ind_mode == 2 and 0xA87418FF or 0x3A2E1EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), ind_mode == 2 and 0xC3871FFF or 0x4A3A24FF)
  if r.ImGui_Button(ctx, '>##turn_right_cockpit', turn_btn_w, 18) then
    setParam(P.ind_mode, ind_mode == 2 and 0 or 2)
  end
  r.ImGui_PopStyleColor(ctx, 3)
  showTip(ctx, tr('Turn signal direction trigger (< left, > right). Press active button again to switch OFF.', 'Тригер напрямку повороту (< ліво, > право). Натисни активну кнопку ще раз, щоб вимкнути.'))

  r.ImGui_Dummy(ctx, 0, 6)
  labelSliderI(ctx, tr('RPM Target', 'RPM Target'), P.rpm_tgt)
  labelSliderI(ctx, tr('Rev Limiter', 'Лімітер обертів'), P.rev_lim)

  r.ImGui_TableNextColumn(ctx)
  secHdr(ctx, tr('CONTROL', 'КОНТРОЛЬ'), C.AMBER)
  labelCombo(ctx, tr('Mode', 'Режим'),         P.mode,         items(tr('Direct', 'Direct'), tr('Physics', 'Physics')))
  labelCombo(ctx, tr('Transmission', 'Трансмісія'), P.trans_mode,   items(tr('D - Drive', 'D - Drive'), tr('S - Sport', 'S - Sport'), tr('M - Manual', 'M - Manual')))
  labelCombo(ctx, tr('Drive Source', 'Джерело приводу'), P.sci_mode,     items(tr('Combustion', 'Згоряння'), tr('Hybrid', 'Гібрид'), tr('Electric', 'Електро')))
  labelCombo(ctx, tr('Shift Intent', 'Намір перемикання'), P.shift_intent, items(tr('Auto', 'Авто'), tr('Cruise', 'Круїз'), tr('Neutral', 'Нейтральний'), tr('Downshift', 'Дауншифт'), tr('Kickdown', 'Кікдаун')))
  r.ImGui_Dummy(ctx, 0, 4)
  labelSliderI(ctx, tr('Speed Override (km/h)', 'Speed Override (км/год)'), P.speed_ovr)
  r.ImGui_Dummy(ctx, 0, 4)
  labelSlider(ctx, tr('Cabin / Exterior', 'Салон / Зовні'), P.cabin_ext)
  r.ImGui_Dummy(ctx, 0, 8)
  secHdr(ctx, tr('BONUS', 'БОНУС'), C.TEAL)
  local siren_on = math.floor(state.params[P.siren_on] or 0)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), siren_on == 1 and 0x1B4E7AFF or 0x1A2128FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), siren_on == 1 and 0x23649CFF or 0x24303AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), siren_on == 1 and 0x2C79BDFF or 0x32414EFF)
  if r.ImGui_Button(ctx, 'SIREN##cockpit_siren_btn', 86, 18) then
    setParam(P.siren_on, siren_on == 1 and 0 or 1)
  end
  r.ImGui_PopStyleColor(ctx, 3)
  showTip(ctx, tr('Police siren quick toggle. Detailed type/level controls are in Interior/Cabin tab.', 'Швидкий тумблер сирени. Детальні налаштування типу/гучності у вкладці Interior/Cabin.'))
  r.ImGui_SameLine(ctx, 0, 8)
  local horn_on = math.floor(state.params[P.horn_on] or 0)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), horn_on == 1 and 0x9F5B10FF or 0x2A2117FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), horn_on == 1 and 0xBC6D12FF or 0x3A2A1CFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), horn_on == 1 and 0xD78218FF or 0x4A3523FF)
  r.ImGui_Button(ctx, 'HORN##cockpit_horn_btn', 86, 18)
  local horn_hold = r.ImGui_IsItemActive(ctx) and 1 or 0
  if horn_hold ~= horn_on then
    setParam(P.horn_on, horn_hold)
  end
  r.ImGui_PopStyleColor(ctx, 3)
  showTip(ctx, tr('Hold to sound the horn.', 'Утримуйте, щоб сигналив клаксон.'))
  r.ImGui_Dummy(ctx, 0, 4)

  r.ImGui_EndTable(ctx)
end

-- ===================================================================
-- TAB: ENGINE
-- ===================================================================
local function tabEngine(ctx)
  local tfl = r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_SizingStretchSame()
  if r.ImGui_BeginTable(ctx, 'eng_tbl', 2, tfl) then
    r.ImGui_TableSetupColumn(ctx, 'en1', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)
    r.ImGui_TableSetupColumn(ctx, 'en2', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('ENGINE CORE', 'ЯДРО ДВИГУНА'), C.GOLD)
    labelCombo(ctx, tr('Cylinders', 'Циліндри'), P.cylinders, items('1 Cyl', '2 Cyl', '3 Cyl', '4 Cyl', '6 Cyl', '8 Cyl'))
    r.ImGui_Dummy(ctx, 0, 4)
    -- XY Pad for Engine Size and Character - centered
    r.ImGui_Text(ctx, tr('Engine Size ↔ Character (XY Pad)', 'Розмір двигуна ↔ Характер (XY Pad)'))
    r.ImGui_Dummy(ctx, 0, 2)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local pad_size = 146
    local offset = (avail_w - pad_size) * 0.5
    if offset > 0 then r.ImGui_Dummy(ctx, offset, 0); r.ImGui_SameLine(ctx) end
    drawXYPad(ctx, pad_size, pad_size)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('ENGINE BONUS', 'БОНУС ДВИГУНА'), C.TEAL)
    labelSlider(ctx, tr('Fuel Pump Priming (%)', 'Праймінг бензонасоса (%)'), P.fuel_pump)
    labelSlider(ctx, tr('Engine Knock / Ping (%)', 'Детонація / Пінг (%)'), P.knock_ping)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('GEARBOX', 'КОРОБКА'), C.GOLD)
    labelSlider(ctx, tr('Trans Whine', 'Трансмісійний свист'), P.trans_whine)
    labelSlider(ctx, tr('Shift Jolt', 'Поштовх перемикання'), P.shift_jolt)
    labelSlider(ctx, tr('Shift Scrape', 'Скрегіт перемикання'), P.shift_scrape)
    labelSlider(ctx, tr('Gear Mesh', 'Сітка шестерень'), P.gb_mesh)
    labelSlider(ctx, tr('Diff Hum', 'Гул диференціала'), P.gb_diff)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('ENGINE TUNING', 'ТЮНІНГ ДВИГУНА'), C.GOLD)
    labelSlider(ctx, tr('Idle Roughness', 'Нерівність холостого'), P.roughness)
    labelSlider(ctx, tr('Idle Micro-Popping (%)', 'Мікро-попи на холостих (%)'), P.idle_pop)
    labelSlider(ctx, tr('Cold Start', 'Холодний старт'), P.cold_start)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('SCI-FI / EV', 'SCI-FI / EV'), C.TEAL)
    labelSlider(ctx, tr('EV Whine', 'EV-тин'), P.sci_ev)
    labelSlider(ctx, tr('Inverter Tone', 'Тон інвертора'), P.sci_inv)
    labelSlider(ctx, tr('Regen Tone', 'Тон рекуперації'), P.sci_regen)
    labelSlider(ctx, tr('Hybrid EV Bias', 'Зсув Hybrid EV'), P.sci_bias)
    labelSlider(ctx, tr('Regen Timbre', 'Тембр рекуперації'), P.regen_timbre)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('MECHANICAL', 'МЕХАНІКА'), C.GOLD)
    labelSlider(ctx, tr('Mech Noise', 'Мех. шум'), P.mech_noise)
    labelSlider(ctx, tr('Valve Train', 'Клапанний механізм'), P.valve_train)
    labelSlider(ctx, tr('Belt / Pulley', 'Ремінь / Шків'), P.belt_pulley)
    labelSlider(ctx, tr('Chain Rattle', 'Брязкіт ланцюга'), P.chain_rattle)

    r.ImGui_EndTable(ctx)
  end
end

-- ===================================================================
-- TAB: EXHAUST + AIR
-- ===================================================================
local function tabExhaust(ctx)
  local tfl = r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_SizingStretchSame()
  if r.ImGui_BeginTable(ctx, 'exh_tbl', 2, tfl) then
    r.ImGui_TableSetupColumn(ctx, 'xa', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)
    r.ImGui_TableSetupColumn(ctx, 'xb', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('EXHAUST', 'ВИХЛОП'), 0xFF6633FF)
    labelCombo(ctx, tr('Exhaust Type', 'Тип вихлопу'), P.exh_type, items(tr('Stock', 'Stock'), tr('Sport', 'Sport'), tr('Straight Pipe', 'Straight Pipe')))
    labelSlider(ctx, tr('Muffler', 'Глушник'), P.muffler)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('COMBUSTION', 'ЗГОРЯННЯ'), 0xFF6633FF)
    labelSlider(ctx, tr('Crackle / Backfire', 'Крекл / Бекфаєр'), P.crackle)
    labelSlider(ctx, tr('Anti-Lag / ALS', 'Антилaг / ALS'), P.als)
    labelSlider(ctx, tr('Backfire Body', 'Тіло бекфаєру'), P.bf_body)
    labelSlider(ctx, tr('Backfire Resonance', 'Резонанс бекфаєру'), P.bf_res)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('TURBO + INTAKE', 'ТУРБО + ВПУСК'), 0x44AADDFF)
    labelSlider(ctx, tr('Turbo Amount', 'Рівень турбо'), P.turbo)
    labelSlider(ctx, tr('Intake Noise', 'Шум впуску'), P.intake)

    r.ImGui_EndTable(ctx)
  end
end

-- ===================================================================
-- TAB: CHASSIS + ROAD
-- ===================================================================
local function tabChassis(ctx)
  local tfl = r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_SizingStretchSame()
  if r.ImGui_BeginTable(ctx, 'chs_tbl', 2, tfl) then
    r.ImGui_TableSetupColumn(ctx, 'ca', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)
    r.ImGui_TableSetupColumn(ctx, 'cb', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('BRAKES', 'ГАЛЬМА'), C.RED)
    labelSlider(ctx, tr('Brake Squeal Level', 'Рівень скрипу гальм'), P.brk_squeal)
    labelSlider(ctx, tr('Brake Overtone Drive', 'Овертон-драйв гальм'), P.brk_overtone)
    labelSlider(ctx, tr('Brake Squeal Pitch', 'Висота скрипу гальм'), P.brk_pitch)
    labelSlider(ctx, tr('Pad Squeak Volume', 'Гучність скрипу колодки'), P.brk_pad)
    labelSlider(ctx, tr('Brake Trim (dB)', 'Trim гальм (dB)'), P.brk_trim)
    labelSlider(ctx, tr('Chorus Color', 'Колір chorus'), P.chorus_color)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('HANDBRAKE TUNING', 'ТЮНІНГ РУЧНИКА'), C.RED)
    labelSlider(ctx, tr('HB Ratchet', 'HB Тріскачка'), P.hb_ratchet)
    labelSlider(ctx, tr('HB Release Level', 'HB Рівень відпуску'), P.hb_release)
    labelSlider(ctx, tr('HB Hold Rumble', 'HB Румбл утримання'), P.hb_hold)
    
    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('DRIFT XY PAD', 'DRIFT XY PAD'), C.GOLD)
    r.ImGui_TextWrapped(ctx, tr(
      'Interactive 2D pad: X-axis = Speed Override (0-280 km/h), Y-axis = Drift Aggression (0-100%). Drag to automate both simultaneously for drift recordings.',
      'Інтерактивний 2D пэд: X = SpeedOverride (0-280 км/год), Y = ДрифтАгресія (0-100%). Перетягуйте для автоматизації обох одночасно для записів дрифту.'))
    local pad_w = r.ImGui_GetContentRegionAvail(ctx)
    drawDriftXYPad(ctx, pad_w - 4, 120)
    labelSlider(ctx, tr('Drift Aggression', 'Агресія дрифту'), P.drift_aggr)

    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('ROAD + WIND', 'ДОРОГА + ВІТЕР'), C.TEAL)
    labelCombo(ctx, tr('Road Surface', 'Покриття дороги'), P.road_surface, items(tr('Asphalt', 'Асфальт'), tr('Concrete', 'Бетон'), tr('Gravel', 'Гравій'), tr('Wet', 'Мокро')))
    labelSlider(ctx, tr('Road / Tire Noise', 'Шум дороги / шин'), P.road_noise)
    labelSlider(ctx, tr('Wind Noise', 'Шум вітру'), P.wind_noise)

    r.ImGui_EndTable(ctx)
  end
end

-- ===================================================================
-- TAB: MASTER + OUTPUTS
-- ===================================================================
local OUT_LABELS = {
  'Exhaust', 'Engine Core', 'Mech / Whine / Starter',
  'Gearbox / Shift', 'Intake / Turbo Whine', 'Turbo BOV',
  'Road / Tire', 'Chassis Sub', 'Brakes', 'Explosions', 'Wind', 'Interior / Cabin', 'Siren / Horn',
}
local OUT_HELP = {
  'Tailpipe/exhaust radiation bus.',
  'Direct engine core/body bus.',
  'Mechanical texture, whine and starter bus.',
  'Shift-only gearbox impact/scrape bus.',
  'Intake and turbo whine bus.',
  'BOV transient bus.',
  'Road and tire noise bus.',
  'Low chassis/sub rumble bus.',
  'Brake synthesis and slip-to-brake bus.',
  'Backfire/ALS explosions bus.',
  'Wind layer bus.',
  'Interior/Cabin bus: Reverse Beep, Indicator Relays, Cabin Ambiance.',
  'Dedicated Siren/Horn bus.',
}
local OUT_PIDX = {
  P.out_exhaust, P.out_engine, P.out_mech, P.out_gearbox,
  P.out_air, P.out_bov, P.out_road, P.out_chassis,
  P.out_brakes, P.out_bangs, P.out_wind, P.out_interior, P.out_siren_horn,
}
local CH_STR = items('1/2', '3/4', '5/6', '7/8', '9/10', '11/12', '13/14', '15/16', '17/18', '19/20', '21/22', '23/24', '25/26')
local ROUTE_EXT_SEC = 'SBP_MotorSynth_UI_Routing'

local function outPairLabel(sel)
  local s = clamp(math.floor(sel or 0), 0, 12)
  local a = s * 2 + 1
  return tostring(a) .. '/' .. tostring(a + 1)
end

local function routeGroupTrackName(grp)
  local labels = grp and grp.labels or {}
  local body = 'Out ' .. outPairLabel(grp and grp.out_sel or 0)
  if #labels == 1 then
    body = labels[1]
  elseif #labels > 1 and #labels <= 4 then
    body = table.concat(labels, ' + ')
  elseif #labels > 4 then
    body = labels[1] .. ' + ' .. labels[2] .. ' +' .. tostring(#labels - 2)
  end
  return body
end

local function routeAllOutputsTo12()
  if not state.linked or not state.track or state.fx_idx < 0 then
    r.ShowConsoleMsg('[MotorSynth UI] Link to MotorSynth first, then run All Out to 1/2.\n')
    return
  end
  r.Undo_BeginBlock()
  for _, pidx in ipairs(OUT_PIDX) do
    setParam(pidx, 0)
  end
  r.Undo_EndBlock('MotorSynth: Route all outputs to 1/2', -1)
end

local function routeAllOutputsSeparate()
  if not state.linked or not state.track or state.fx_idx < 0 then
    r.ShowConsoleMsg('[MotorSynth UI] Link to MotorSynth first, then run Separate All Out.\n')
    return
  end
  r.Undo_BeginBlock()
  for i, pidx in ipairs(OUT_PIDX) do
    local def = PDEF[pidx]
    local max_sel = def and def[2] or 10
    setParam(pidx, clamp(i - 1, 0, max_sel))
  end
  r.Undo_EndBlock('MotorSynth: Separate all outputs', -1)
end

local function sanitizeCarName(name)
  local s = tostring(name or '')
  s = s:gsub('[^%w%s%-_]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then s = 'Phantom' end
  return s
end

local function routingFolderName()
  local nm = sanitizeCarName(state.car_name)
  return 'Car "' .. nm .. '"'
end

local function loadRoutingName()
  local saved = r.GetExtState(ROUTE_EXT_SEC, 'car_name')
  if saved and saved ~= '' then
    state.car_name = sanitizeCarName(saved)
  end
end

local function saveRoutingName()
  r.SetExtState(ROUTE_EXT_SEC, 'car_name', sanitizeCarName(state.car_name), true)
end

local function getFolderSpan(folder_idx)
  local n = r.CountTracks(0)
  if folder_idx < 0 or folder_idx >= n then return folder_idx, folder_idx end
  local depth = math.floor(r.GetMediaTrackInfo_Value(r.GetTrack(0, folder_idx), 'I_FOLDERDEPTH') or 0)
  if depth <= 0 then return folder_idx, folder_idx end

  local acc = depth
  local last = folder_idx
  for i = folder_idx + 1, n - 1 do
    local tr = r.GetTrack(0, i)
    if not tr then break end
    acc = acc + math.floor(r.GetMediaTrackInfo_Value(tr, 'I_FOLDERDEPTH') or 0)
    last = i
    if acc <= 0 then break end
  end
  return folder_idx, last
end

local function findExistingRoutingFolderForSource(src, folder_name)
  if not src then return nil end
  local src_num = math.floor(r.GetMediaTrackInfo_Value(src, 'IP_TRACKNUMBER') or 0)
  if src_num < 1 then return nil end
  local fidx = src_num
  local ftr = r.GetTrack(0, fidx)
  if not ftr then return nil end
  local _, nm = r.GetSetMediaTrackInfo_String(ftr, 'P_NAME', '', false)
  if nm ~= folder_name then return nil end
  local sidx, eidx = getFolderSpan(fidx)
  return { track = ftr, start_idx = sidx, end_idx = eidx }
end

local function cleanupRoutingForSource(src)
  if not src then return false end
  local folder_name = routingFolderName()
  local found = findExistingRoutingFolderForSource(src, folder_name)
  if not found then return false end

  for i = found.end_idx, found.start_idx, -1 do
    local tr = r.GetTrack(0, i)
    if tr and r.DeleteTrack then
      r.DeleteTrack(tr)
    end
  end
  return true
end

local function buildAutoRoutingFromLinkedTrack()
  if not state.linked or not state.track then
    r.ShowConsoleMsg('[MotorSynth UI] Link to MotorSynth first, then run Auto Routing.\n')
    return
  end

  local src = state.track
  local folder_name = routingFolderName()
  local src_num = math.floor(r.GetMediaTrackInfo_Value(src, 'IP_TRACKNUMBER'))
  if src_num < 1 then
    r.ShowConsoleMsg('[MotorSynth UI] Failed to resolve source track index for routing.\n')
    return
  end

  local existing = findExistingRoutingFolderForSource(src, folder_name)
  if existing then
    r.ShowConsoleMsg('[MotorSynth UI] Routing folder already exists for this track. Use Cleanup Routing first.\n')
    return
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local ok = true
  local src_idx = src_num - 1
  local req_nchan = 26
  local cur_nchan = math.floor(r.GetMediaTrackInfo_Value(src, 'I_NCHAN') or 2)
  if cur_nchan < req_nchan then
    r.SetMediaTrackInfo_Value(src, 'I_NCHAN', req_nchan)
  end

  local insert_idx = src_idx + 1
  r.InsertTrackAtIndex(insert_idx, true)
  local folder = r.GetTrack(0, insert_idx)
  if not folder then
    ok = false
  else
    r.GetSetMediaTrackInfo_String(folder, 'P_NAME', folder_name, true)
    r.SetMediaTrackInfo_Value(folder, 'I_FOLDERDEPTH', 1)
  end

  local route_groups = {}
  local route_group_order = {}
  for i = 1, #OUT_LABELS do
    local out_sel = math.floor(state.params[OUT_PIDX[i]] or 0)
    out_sel = clamp(out_sel, 0, 12)
    local key = tostring(out_sel)
    local grp = route_groups[key]
    if not grp then
      grp = { out_sel = out_sel, labels = {} }
      route_groups[key] = grp
      route_group_order[#route_group_order + 1] = grp
    end
    grp.labels[#grp.labels + 1] = OUT_LABELS[i]
  end

  local created_children = {}
  if ok then
    for i = 1, #route_group_order do
      local grp = route_group_order[i]
      local child_idx = insert_idx + i
      r.InsertTrackAtIndex(child_idx, true)
      local tr = r.GetTrack(0, child_idx)
      if not tr then
        ok = false
        break
      end
      created_children[#created_children + 1] = tr

      local tr_name = routeGroupTrackName(grp)
      r.GetSetMediaTrackInfo_String(tr, 'P_NAME', tr_name, true)

      local send_idx = r.CreateTrackSend(src, tr)
      if send_idx < 0 then
        ok = false
        break
      end

      local src_chan = grp.out_sel * 2
      r.SetTrackSendInfo_Value(src, 0, send_idx, 'I_SRCCHAN', src_chan)
      r.SetTrackSendInfo_Value(src, 0, send_idx, 'I_DSTCHAN', 0)
      r.SetTrackSendInfo_Value(src, 0, send_idx, 'D_VOL', 1.0)
      r.SetTrackSendInfo_Value(src, 0, send_idx, 'I_SENDMODE', 0)
    end
  end

  if #created_children > 0 then
    local last = created_children[#created_children]
    r.SetMediaTrackInfo_Value(last, 'I_FOLDERDEPTH', -1)
  end

  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)
  if ok then
    r.Undo_EndBlock('MotorSynth: Build output routing folder', -1)
    r.ShowConsoleMsg('[MotorSynth UI] Auto routing created in folder: ' .. folder_name .. '\n')
  else
    r.Undo_EndBlock('MotorSynth: Build output routing folder (partial)', -1)
    r.ShowConsoleMsg('[MotorSynth UI] Auto routing finished with errors. Please verify created tracks/sends.\n')
  end
end

local function cleanupAutoRoutingFromLinkedTrack()
  if not state.linked or not state.track then
    r.ShowConsoleMsg('[MotorSynth UI] Link to MotorSynth first, then run Cleanup Routing.\n')
    return
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok = cleanupRoutingForSource(state.track)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.PreventUIRefresh(-1)

  if ok then
    r.Undo_EndBlock('MotorSynth: Cleanup output routing folder', -1)
    r.ShowConsoleMsg('[MotorSynth UI] Routing folder cleaned up.\n')
  else
    r.Undo_EndBlock('MotorSynth: Cleanup output routing folder (no-op)', -1)
    r.ShowConsoleMsg('[MotorSynth UI] No matching routing folder found for cleanup.\n')
  end
end

local function tabInterior(ctx)
  local tfl = r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_SizingStretchProp()
  if r.ImGui_BeginTable(ctx, 'int_cbl', 2, tfl) then
    r.ImGui_TableSetupColumn(ctx, 'int_a', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)
    r.ImGui_TableSetupColumn(ctx, 'int_b', r.ImGui_TableColumnFlags_WidthStretch(), 0.5)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('REVERSE BEEP', 'РЕВЕРС БІП'), C.TEAL)
    labelSlider(ctx, tr('Pitch (Hz)', 'Висота (Гц)'), P.rev_beep_pitch)
    labelSlider(ctx, tr('Level (%)', 'Рівень (%)'), P.rev_beep_level)
    labelSlider(ctx, tr('Shift Peak (%)', 'Пік перемикання (%)'), P.shift_peak)
    r.ImGui_Dummy(ctx, 0, 5)
    secHdr(ctx, tr('SIREN (BONUS)', 'СИРЕНА (БОНУС)'), C.TEAL)
    r.ImGui_Text(ctx, tr('Type', 'Тип'))
    showTip(ctx, PARAM_HELP[P.siren_type])
    cmb(ctx, 'Siren Type##siren_type', P.siren_type, items('Police', 'Medical', 'Fire'))
    showTip(ctx, PARAM_HELP[P.siren_type])
    labelSlider(ctx, tr('Siren Level (%)', 'Гучність сирени (%)'), P.siren_level)
    labelSlider(ctx, tr('Horn Level (%)', 'Гучність клаксону (%)'), P.horn_level)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('INDICATOR TUNING', 'НАЛАШТУВАННЯ ПОВОРОТНИКІВ'), C.TEAL)
    r.ImGui_Text(ctx, tr('Click Type', 'Тип клацання'))
    showTip(ctx, PARAM_HELP[P.ind_type])
    cmb(ctx, 'Click Type##ind_type', P.ind_type, items('Relay', 'Soft', 'Sharp'))
    showTip(ctx, PARAM_HELP[P.ind_type])
    labelSlider(ctx, tr('Level (%)', 'Рівень (%)'), P.ind_level)
    labelSlider(ctx, tr('Cabin Ambiance (%)', 'Атмосфера салону (%)'), P.cabin_amb)
    labelSlider(ctx, tr('Turn Influence (%)', 'Вплив повороту (%)'), P.turn_infl)

    r.ImGui_EndTable(ctx)
  end
end

local function tabMaster(ctx)
  local tfl = r.ImGui_TableFlags_BordersInnerV() | r.ImGui_TableFlags_SizingStretchProp()
  if r.ImGui_BeginTable(ctx, 'mst_tbl', 2, tfl) then
    r.ImGui_TableSetupColumn(ctx, 'ma', r.ImGui_TableColumnFlags_WidthStretch(), 0.42)
    r.ImGui_TableSetupColumn(ctx, 'mb', r.ImGui_TableColumnFlags_WidthStretch(), 0.58)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('TONE / FX', 'ТОН / FX'), C.TEAL)
    labelSlider(ctx, tr('Drive / Saturation', 'Драйв / Сатурація'), P.drive)
    labelSlider(ctx, tr('High Cut / Tone', 'ВЧ зріз / Тон'), P.high_cut)
    labelSlider(ctx, tr('Stereo Width', 'Ширина стерео'), P.stereo_width)
    r.ImGui_Dummy(ctx, 0, 8)
    secHdr(ctx, tr('MASTER', 'МАЙСТЕР'), C.TEAL)
    labelSlider(ctx, tr('Master Volume (dB)', 'Майстер гучність (dB)'), P.master_vol)

    r.ImGui_TableNextColumn(ctx)
    secHdr(ctx, tr('OUTPUT ROUTING', 'РОУТИНГ ВИХОДІВ'), C.TEXT_DIM)

    r.ImGui_Text(ctx, tr('Car Name', 'Назва авто'))
    r.ImGui_SetNextItemWidth(ctx, 190)
    local ch_name, car_name = r.ImGui_InputText(ctx, '##ms_car_name', state.car_name)
    if ch_name then
      state.car_name = sanitizeCarName(car_name)
      saveRoutingName()
    end
    r.ImGui_Dummy(ctx, 0, 4)

    local btn_h = 36
    local btn_gap = 4
    local btn_avail = r.ImGui_GetContentRegionAvail(ctx)
    local btn_w = math.max(92, math.floor((btn_avail - btn_gap * 3) / 4))

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 3, 2)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x6A5818FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x8A7420FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xA18826FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFF2C8FF)
    if r.ImGui_Button(ctx, tr('All Out to 1/2', 'Всі виходи в 1/2') .. '##ms_out_all_to_12', btn_w, btn_h) then
      routeAllOutputsTo12()
    end
    r.ImGui_SameLine(ctx, 0, btn_gap)
    if r.ImGui_Button(ctx, tr('Separate All Out', 'Рознести всі виходи') .. '##ms_out_all_separate', btn_w, btn_h) then
      routeAllOutputsSeparate()
    end
    r.ImGui_PopStyleColor(ctx, 4)
    r.ImGui_SameLine(ctx, 0, btn_gap)
    if r.ImGui_Button(ctx, tr('Auto Build Routing', 'Автозбірка роутингу') .. '##ms_auto_build_routing', btn_w, btn_h) then
      buildAutoRoutingFromLinkedTrack()
    end
    r.ImGui_SameLine(ctx, 0, btn_gap)
    if r.ImGui_Button(ctx, tr('Cleanup Routing', 'Очистити роутинг') .. '##ms_cleanup_routing', btn_w, btn_h) then
      cleanupAutoRoutingFromLinkedTrack()
    end
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_Dummy(ctx, 0, 4)

    local rtfl = r.ImGui_TableFlags_BordersOuter() |
                 r.ImGui_TableFlags_RowBg() |
                 r.ImGui_TableFlags_SizingStretchProp()
    if r.ImGui_BeginTable(ctx, 'rt_tbl', 2, rtfl) then
      r.ImGui_TableSetupColumn(ctx, 'rt_nm', r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableSetupColumn(ctx, 'rt_ch', r.ImGui_TableColumnFlags_WidthFixed(), 74)
      r.ImGui_TableHeadersRow(ctx)
      for i, pidx in ipairs(OUT_PIDX) do
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.TEXT_DIM)
        r.ImGui_Text(ctx, OUT_LABELS[i])
        r.ImGui_PopStyleColor(ctx)
        showTip(ctx, OUT_HELP[i])
        r.ImGui_TableNextColumn(ctx)
        cmb(ctx, '##rt' .. i, pidx, CH_STR, 72)
        showTip(ctx, OUT_HELP[i])
      end
      r.ImGui_EndTable(ctx)
    end

    r.ImGui_EndTable(ctx)
  end
end

loadRoutingName()
-- ===================================================================
-- STATUS BAR
-- ===================================================================
local function drawStatusBar(ctx)
  local tf = r.ImGui_TableFlags_SizingStretchProp()
  if not r.ImGui_BeginTable(ctx, 'status_bar_top_tbl', 2, tf) then return end
  r.ImGui_TableSetupColumn(ctx, 'left', r.ImGui_TableColumnFlags_WidthStretch(), 1.0)
  r.ImGui_TableSetupColumn(ctx, 'right', r.ImGui_TableColumnFlags_WidthFixed(), 360)
  r.ImGui_TableNextRow(ctx)

  -- Left controls
  r.ImGui_TableSetColumnIndex(ctx, 0)

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x13212CFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x1B2C3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x264055FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.TEAL)
  if r.ImGui_Button(ctx, 'CORE##core_insert_fx', 52, 36) then
    ensureMotorSynthOnSelectedTrack()
  end
  showTip(ctx, 'Find/add MotorSynth on selected track and link UI to it.')
  r.ImGui_PopStyleColor(ctx, 4)

  r.ImGui_SameLine(ctx, 0, 14)
  drawIgnButton(ctx)

  r.ImGui_SameLine(ctx, 0, 10)
  r.ImGui_SetNextItemWidth(ctx, 100)
  sliderD(ctx, 'Vol##sv', P.master_vol, 100)
  showTip(ctx, PARAM_HELP[P.master_vol])

  r.ImGui_SameLine(ctx, 0, 12)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local mx, my = r.ImGui_GetCursorScreenPos(ctx)
  local mw, mh = 14, 36
  local thr_n = clamp((state.params[P.throttle] or 0) / 100.0, 0, 1)
  r.ImGui_DrawList_AddRectFilled(dl, mx, my, mx + mw, my + mh, C.FRAME, 2)
  if thr_n > 0.01 then
    r.ImGui_DrawList_AddRectFilled(dl, mx, my + mh * (1 - thr_n), mx + mw, my + mh,
      alphamix(C.AMBER, 0.8), 2)
  end
  r.ImGui_DrawList_AddRect(dl, mx, my, mx + mw, my + mh, C.BORDER, 2, 0, 1)

  local brk_n = clamp((state.params[P.brake] or 0) / 100.0, 0, 1)
  r.ImGui_DrawList_AddRectFilled(dl, mx + mw + 4, my, mx + mw * 2 + 4, my + mh, C.FRAME, 2)
  if brk_n > 0.01 then
    r.ImGui_DrawList_AddRectFilled(dl, mx + mw + 4, my + mh * (1 - brk_n), mx + mw * 2 + 4, my + mh,
      alphamix(C.RED, 0.8), 2)
  end
  r.ImGui_DrawList_AddRect(dl, mx + mw + 4, my, mx + mw * 2 + 4, my + mh, C.BORDER, 2, 0, 1)
  r.ImGui_Dummy(ctx, mw * 2 + 8, mh)

  r.ImGui_SameLine(ctx, 0, 10)
  local gx, gy = r.ImGui_GetCursorScreenPos(ctx)
  drawGearBadge(ctx, gx + 20, gy + 16, 18)
  r.ImGui_Dummy(ctx, 42, 36)

  r.ImGui_SameLine(ctx, 0, 8)
  if r.ImGui_Button(ctx, 'Help##open_help_top', 60, 36) then
    state.help_open = true
  end
  showTip(ctx, 'Open full MotorSynth mechanics help window.')

  -- Right: presets
  r.ImGui_TableSetColumnIndex(ctx, 1)
  local combo_w, btn_w = 190, 74
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  local ch, idx = r.ImGui_Combo(ctx, '##preset_combo_top', state.preset_idx, PRESET_ITEMS)
  if ch then state.preset_idx = idx end
  showTip(ctx, 'Preset list: built-in + saved user presets.')

  r.ImGui_SameLine(ctx, 0, 6)
  if r.ImGui_Button(ctx, 'Apply##preset_apply_top', btn_w, 0) and state.linked then
    applyPreset(state.preset_idx + 1)
    readAllParams()
  end
  showTip(ctx, 'Apply selected preset to linked MotorSynth track.')

  r.ImGui_SameLine(ctx, 0, 6)
  if r.ImGui_Button(ctx, 'Save##preset_save_top', btn_w, 0) and state.linked then
    local ok, name = r.GetUserInputs('Save MotorSynth Preset', 1, 'Preset name:,extrawidth=120', '')
    if ok then
      saveCurrentAsUserPreset(name)
    end
  end
  showTip(ctx, 'Save current parameter state as a user preset (persistent).')

  r.ImGui_EndTable(ctx)
end

-- ===================================================================
-- RESPONSIVE TAB ROW
-- ===================================================================
local TAB_ITEMS = {
  {label='Cockpit', label_uk='Кокпіт', fn=tabCockpit},
  {label='Engine', label_uk='Двигун', fn=tabEngine},
  {label='Exhaust + Air', label_uk='Вихлоп + Повітря', fn=tabExhaust},
  {label='Chassis + Road', label_uk='Шасі + Дорога', fn=tabChassis},
  {label='Interior/Cabin', label_uk='Інтер\'єр/Салон', fn=tabInterior},
  {label='Master + Outputs', label_uk='Майстер + Виходи', fn=tabMaster},
}

local function drawResponsiveTabs(ctx)
  local tfl = r.ImGui_TableFlags_SizingStretchSame()
  if r.ImGui_BeginTable(ctx, 'tabs_row', #TAB_ITEMS, tfl) then
    for i, t in ipairs(TAB_ITEMS) do
      r.ImGui_TableNextColumn(ctx)
      local is_active = state.active_tab == (i - 1)
      local b_col = is_active and 0x5A2B08FF or 0x241A10FF
      local h_col = is_active and 0x6A340AFF or 0x352212FF
      local a_col = is_active and 0x7A3D0CFF or 0x4A2A13FF
      local txt_c = is_active and C.AMBER or 0xC9A27BFF
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), b_col)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), h_col)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), a_col)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), txt_c)
      r.ImGui_SetNextItemWidth(ctx, -1)
      if r.ImGui_Button(ctx, tr(t.label, t.label_uk) .. '##ms_tab_' .. i, -1, 28) then
        state.active_tab = i - 1
      end
      r.ImGui_PopStyleColor(ctx, 4)
    end
    r.ImGui_EndTable(ctx)
  end
end

local function drawQuickConstants(ctx)
  r.ImGui_Dummy(ctx, 0, 6)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Text(tr('Quick Constants Table', 'Швидка таблиця констант'))

  local rows = nil
  if state.active_tab == 0 then
    rows = {
      {tr('Auto N->1 engage', 'Авто N->1 engage'), tr('Throttle above ~8%', 'Газ вище ~8%')},
      {tr('Kickdown detect (Auto intent)', 'Kickdown detect (Auto intent)'), tr('Fast pedal rise + throttle >55%', 'Різкий ріст газу + газ >55%')},
      {tr('Throttle-drop trigger', 'Throttle-drop trigger'), tr('About 15% fast release at high load', 'Близько 15% швидкого скидання при високому навантаженні')},
      {tr('Stop-lock entry', 'Stop-lock вхід'), tr('Brake >12% and near-zero speed', 'Гальмо >12% і майже нульова швидкість')},
    }
  elseif state.active_tab == 1 then
    rows = {
      {tr('Upshift duration', 'Тривалість апшифту'), tr('~0.25 s', '~0.25 с')},
      {tr('Downshift duration', 'Тривалість дауншифту'), tr('~0.30 s', '~0.30 с')},
      {tr('Base upshift speed gates', 'Базові speed-gates апшифту'), tr('24 / 40 / 62 / 88 / 112 km/h', '24 / 40 / 62 / 88 / 112 км/год')},
      {tr('Auto upshift force fallback', 'Форс-апшифт fallback'), tr('When RPM goes clearly above target', 'Коли RPM помітно вище target')},
      {tr('Warm-up duration (cold→hot)', 'Тривалість прогріву (холодний→гарячий)'), tr('~45 seconds', '~45 секунд')},
      {tr('Cool-down duration (hot→cold)', 'Тривалість охолодження (гарячий→холодний)'), tr('~90 seconds', '~90 секунд')},
      {tr('Cold-start effect on idle', 'Вплив холодного запуску на холостий'), tr('Extends cranking, raises idle RPM', 'Подовжує запуск, піднімає холостий хід')},
      {tr('Higher temperature effect', 'Вплив вищої температури'), tr('Increases backfire/crackle activity', 'Збільшує активність бекпейрів/крекління')},
      {tr('Engine Size scales', 'Розмір двигуна масштабує'), tr('Startup revs, tone depth, shift drama, mech rattle', 'Запуск, глибину окладу, драму піків, rattle')},
      {tr('Character Thump ↔ Rasp', 'Характер Thump ↔ Rasp'), tr('Negative = deep/smooth, Positive = bright/edgy', 'Мінус = глибокий/гладкий, Плюс = яскравий/гострий')},
    }
  elseif state.active_tab == 2 then
    rows = {
      {tr('BOV transient trigger', 'BOV transient trigger'), tr('Fast throttle release from load', 'Швидке скидання газу під навантаженням')},
      {tr('ALS impact zone', 'ALS impact zone'), tr('Most audible near limiter', 'Найчутніше біля лімітера')},
      {tr('Turbo spool behavior', 'Turbo spool behavior'), tr('Slower at low RPM, faster at high RPM', 'Повільніше на низьких RPM, швидше на високих')},
      {tr('Intake motion coupling', 'Intake motion coupling'), tr('Depends on throttle and vehicle motion', 'Залежить від газу та руху авто')},
    }
  elseif state.active_tab == 3 then
    rows = {
      {tr('Brake-to-speed decouple', 'Brake-to-speed decouple'), tr('Brake above ~10% with low launch intent', 'Гальмо вище ~10% при низькому launch intent')},
      {tr('Surface type impact', 'Вплив типу поверхні'), tr('Asphalt/Concrete/Gravel/Wet change brake+road tone', 'Asphalt/Concrete/Gravel/Wet змінюють тон гальм і дороги')},
      {tr('Brake lag character', 'Brake lag характер'), tr('Short micro-delays imitate stick-slip', 'Короткі мікролаги імітують stick-slip')},
      {tr('Stop-lock hold', 'Stop-lock hold'), tr('Stabilizes full stop and prevents crawl', 'Стабілізує повну зупинку і прибирає crawl')},
    }
  else
    rows = {
      {tr('Routing folder format', 'Формат routing-папки'), tr('Car "Name"', 'Car "Name"')},
      {tr('Auto Build result', 'Результат Auto Build'), tr('1 folder + 13 bus tracks', '1 папка + 13 bus-треків')},
      {tr('Source channel requirement', 'Вимога до каналів source'), tr('Track channels expanded up to 26 if needed', 'Канали source розширюються до 26 за потреби')},
      {tr('Cleanup behavior', 'Поведінка Cleanup'), tr('Removes generated folder for linked source', 'Видаляє згенеровану папку для linked source')},
      {tr('Speed Override at 0', 'Speed Override = 0'), tr('Auto drivetrain speed estimate (RPM/gear-based)', 'Автооцінка швидкості від трансмісії (RPM/gear)')},
      {tr('Speed Override > 0', 'Speed Override > 0'), tr('Fixed speed (1-280 km/h) for drift simulation and live wheel slip', 'Фіксована швидкість для симуляції дрифту та буксування')},
      {tr('Ideal for drifting', 'Ідеально для дрифту'), tr('Set Speed Override = your car speed, let tire slip independently', 'Встановіть = швидкість авто, колеса буксують незалежно')},
    }
  end

  local tf = r.ImGui_TableFlags_BordersOuter() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_SizingStretchProp()
  if r.ImGui_BeginTable(ctx, 'quick_constants_tbl##bottom', 2, tf) then
    r.ImGui_TableSetupColumn(ctx, 'key##qc', r.ImGui_TableColumnFlags_WidthStretch(), 0.42)
    r.ImGui_TableSetupColumn(ctx, 'value##qc', r.ImGui_TableColumnFlags_WidthStretch(), 0.58)
    r.ImGui_TableHeadersRow(ctx)
    for i, row in ipairs(rows) do
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableSetColumnIndex(ctx, 0)
      r.ImGui_Text(ctx, row[1])
      r.ImGui_TableSetColumnIndex(ctx, 1)
      r.ImGui_TextWrapped(ctx, row[2])
    end
    r.ImGui_EndTable(ctx)
  end
end

-- ===================================================================
-- MAIN LOOP
-- ===================================================================
local ctx = r.ImGui_CreateContext('SBP MotorSynth UI')

local function loop()
  updateLink()
  refreshCritical()

  r.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, r.ImGui_Cond_FirstUseEver())
  pushTheme(ctx)

  local visible, open = r.ImGui_Begin(ctx, 'SBP MotorSynth', true,
    r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse())

  if visible then
    drawStatusBar(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Dummy(ctx, 0, 2)
    drawResponsiveTabs(ctx)
    r.ImGui_Dummy(ctx, 0, 2)
    TAB_ITEMS[state.active_tab + 1].fn(ctx)
  end

  r.ImGui_End(ctx)
  popTheme(ctx)

  if open then
    drawHelpWindow(ctx)
    r.defer(loop)
  else
    if r.ImGui_DestroyContext then
      r.ImGui_DestroyContext(ctx)
    else
      r.ShowConsoleMsg('[MotorSynth UI] ImGui_DestroyContext not available in this ReaImGui build.\n')
    end
  end
end

loop()
