-- @description SBP Cine Loudness Analyzer
-- @author SBP & AI
-- @version 0.72
-- @about Standalone loudness analyzer for post-production in REAPER. Horizontal timeline UI with M/S/I curves, target line, heatmap, grid, and source comparison (Dialog/Master).
-- @link https://forum.cockos.com/showthread.php?t=301263
-- @changelog
--   0.72 Release: final publication build for forum/ReaPack (A/B standards workflow, dialogue/cinema presets, UI polish, and release documentation).

local r = reaper
local SCRIPT_ID = "SBP_CINE_LOUDNESS_ANALYZER"
local SCRIPT_TITLE = "SBP Cine Loudness Analyzer v0.72"
local ctx = r.ImGui_CreateContext(SCRIPT_TITLE)

local PROFILE_OPTIONS = {
  { label = "EBU R128 Broadcast (-23 LUFS)", target = -23.0, tol = 0.5, lra_max = 20.0, tp_max = -1.0, ref = "EBU R128", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "ATSC A/85 TV (-24 LKFS)", target = -24.0, tol = 2.0, lra_max = 20.0, tp_max = -2.0, ref = "ATSC A/85", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "Netflix Dialog (-27 LKFS)", target = -27.0, tol = 2.0, lra_max = 18.0, tp_max = -2.0, ref = "Netflix dialog mix", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "st" },
  { label = "Dialogue LKFS Focus (-24, S=3s)", target = -24.0, tol = 2.0, lra_max = 18.0, tp_max = -2.0, ref = "Dialogue editorial", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "st" },
  { label = "Dialogue LKFS Focus (-24, S=10s)", target = -24.0, tol = 2.0, lra_max = 18.0, tp_max = -2.0, ref = "Dialogue editorial", m_win = 0.4, s_win = 10.0, hop = 0.1, alert_field = "st" },
  { label = "Spotify Normal (-14 LUFS)", target = -14.0, tol = 1.5, lra_max = 12.0, tp_max = -1.0, ref = "Spotify normalization", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "YouTube Music (-14 LUFS)", target = -14.0, tol = 2.0, lra_max = 12.0, tp_max = -1.0, ref = "YouTube playback target", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "Apple Music Sound Check (-16 LUFS)", target = -16.0, tol = 1.5, lra_max = 12.0, tp_max = -1.0, ref = "Sound Check practice", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "Vertical Mobile Cinema (-18 LUFS)", target = -18.0, tol = 1.5, lra_max = 10.0, tp_max = -2.0, ref = "Mobile short-form", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" },
  { label = "Podcast Stereo (-16 LUFS)", target = -16.0, tol = 1.0, lra_max = 10.0, tp_max = -1.0, ref = "Podcast delivery", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "st" },
  { label = "Cinema Dialog+Program EU (EBU R128 v4)", target = -23.0, tol = 0.5, lra_max = 20.0, tp_max = -1.0, ref = "EU theatrical workflow", m_win = 0.4, s_win = 10.0, hop = 0.1, alert_field = "st" },
  { label = "Cinema Dialog+Program US (theatrical style)", target = -27.0, tol = 2.0, lra_max = 22.0, tp_max = -3.0, ref = "US theatrical workflow", m_win = 0.4, s_win = 10.0, hop = 0.1, alert_field = "st" },
  { label = "Custom", target = -23.0, tol = 1.0, lra_max = 8.0, tp_max = -1.0, ref = "Custom", m_win = 0.4, s_win = 3.0, hop = 0.1, alert_field = "m" }
}

local BIND_OPTIONS = {
  { label = "Master", key = "master" },
  { label = "Track Name", key = "track_name" },
  { label = "Selected Tracks", key = "selected" }
}

local VIEW_OPTIONS = {
  { label = "Overlay", key = "overlay" },
  { label = "Split Lanes", key = "split" },
  { label = "Delta (A-B)", key = "delta" }
}

local MODE_OPTIONS = {
  { label = "Live", key = "live" },
  { label = "Offline", key = "offline" }
}

local TIME_AXIS_OPTIONS = {
  { label = "Cumulative", key = "cumulative" },
  { label = "Timeline Synced", key = "timeline" },
  { label = "Centered Cursor", key = "cursor_center" }
}

local QUICK_PRESET_OPTIONS = {
  { label = "Film Dialog (Netflix style)", key = "film_dialog" },
  { label = "Broadcast EBU R128", key = "broadcast_ebu" },
  { label = "Streaming General", key = "streaming_general" },
  { label = "Music Platforms", key = "music_platforms" },
  { label = "Vertical Mobile", key = "vertical_mobile" },
  { label = "Podcast Speech", key = "podcast" },
  { label = "Dialogue LKFS Focus (S=10s)", key = "dialog_lkfs_focus" },
  { label = "Cinema Dialog+Program EU", key = "cinema_dialog_program_eu" },
  { label = "Cinema Dialog+Program US", key = "cinema_dialog_program_us" }
}

local OFFLINE_RANGE_OPTIONS = {
  { label = "Time Selection", key = "time_selection" },
  { label = "Markers =START/=END", key = "markers_start_end" },
  { label = "Whole Project", key = "whole_project" }
}

local OFFLINE_PROGRAM_CHANNEL_OPTIONS = {
  { label = "Auto (recommended)", channels = 0 },
  { label = "Stereo (2)", channels = 2 },
  { label = "Surround 5.1 (6)", channels = 6 },
  { label = "Surround 7.1 (8)", channels = 8 }
}

local ALERT_MODE_OPTIONS = {
  { label = "Regions", key = "regions" },
  { label = "Markers", key = "markers" },
  { label = "Markers + Regions", key = "both" }
}

local ALERT_SOURCE_OPTIONS = {
  { label = "A", key = "a" },
  { label = "B", key = "b" },
  { label = "A + B", key = "both" }
}

local MARKER_FLAG_FILTER_OPTIONS = {
  { label = "All", key = "all" },
  { label = "Lane name contains", key = "lane_contains" },
  { label = "Exact lane name", key = "lane_exact" }
}

local CACHE_MODE_OPTIONS = {
  { label = "All", key = "all" },
  { label = "Selected", key = "selected" }
}

local RIBBON_FIELD_OPTIONS = {
  { label = "Momentary (M)", key = "m" },
  { label = "Short (S)", key = "st" },
  { label = "Integrated (I)", key = "i" }
}

local ALERT_FIELD_OPTIONS = {
  { label = "Momentary (M)", key = "m" },
  { label = "Short (S)", key = "st" }
}

local params = {
  enabled = true,
  measurement_locked = false,
  mode_idx = 1,
  quick_preset_idx = 1,
  time_axis_idx = 1,
  view_idx = 1,

  source_a_enabled = true,
  source_a_bind_idx = 3,
  source_a_name = "",
  source_a_profile_idx = 3,

  source_b_enabled = true,
  source_b_bind_idx = 1,
  source_b_name = "",
  source_b_profile_idx = 1,

  show_grid = true,
  show_marker_flags = false,
  show_marker_flag_text = false,
  marker_flags_filter_mode_idx = 1,
  marker_flags_name_filter = "Loudness Alert",
  cache_mode_idx = 1,
  cache_markers = true,
  cache_marker_lanes = true,
  cache_curve_gap = true,
  cache_hover_readout = true,
  cache_refresh_ms = 150,
  render_early_skip = false,
  show_heatmap = false,
  show_target = true,
  y_top_zero = false,
  show_mid = true,
  show_side = true,
  show_integrated = true,
  overlay_b_fill = true,
  overlay_fill_source_idx = 2,
  overlay_fill_field_idx = 1,
  ribbon_field_idx = 1,
  overlay_fill_alpha = 0.35,
  critical_lu = 8.0,
  critical_upper_lu = 8.0,
  critical_lower_lu = 8.0,
  source_a_critical_upper_lu = 8.0,
  source_a_critical_lower_lu = 8.0,
  source_b_critical_upper_lu = 8.0,
  source_b_critical_lower_lu = 8.0,
  alert_mode_idx = 1,
  alert_source_idx = 3,
  alert_min_duration_sec = 0.60,
  alert_merge_gap_sec = 0.25,
  alert_cooldown_sec = 0.0,
  alert_lra_enabled = false,
  alert_tp_enabled = false,
  alert_clear_prev = true,
  alert_prefix = "Loudness Alert",
  alert_lra_prefix = "LRA Alert",
  alert_tp_prefix = "TP Alert",
  alert_smart_naming = true,
  alert_include_lufs = false,
  alert_help = true,
  alert_use_lane = true,
  alert_lane_name = "Loudness Alert",
  alert_lane_index = -1,
  alert_color_low = 0x4F8CB8,
  alert_color_high = 0xD26A5B,
  show_critical_lines = true,
  y_zoom = 1.0,
  x_zoom = 1.0,
  source_a_show_heatmap = true,
  source_b_show_heatmap = true,
  source_a_show_critical = true,
  source_b_show_critical = true,
  source_a_show_tolerance = true,
  source_b_show_tolerance = true,

  source_a_show_mid = true,
  source_a_show_side = true,
  source_a_show_integrated = true,
  source_a_target_enabled = true,
  source_a_target_lufs = -27.0,
  source_a_tolerance_lu = 2.0,
  source_a_lra_limit_lu = 18.0,
  source_a_tp_limit_dbtp = -2.0,
  source_a_alert_field_idx = 2,
  source_a_momentary_window_sec = 0.4,
  source_a_short_window_sec = 3.0,
  source_a_hop_sec = 0.1,

  source_b_show_mid = true,
  source_b_show_side = true,
  source_b_show_integrated = true,
  source_b_target_enabled = true,
  source_b_target_lufs = -23.0,
  source_b_tolerance_lu = 5.0,
  source_b_lra_limit_lu = 20.0,
  source_b_tp_limit_dbtp = -1.0,
  source_b_alert_field_idx = 1,
  source_b_momentary_window_sec = 0.4,
  source_b_short_window_sec = 3.0,
  source_b_hop_sec = 0.1,

  theme_preset = 1,
  col_bg = 0x1A1A1AFF,
  col_panel = 0x252525FF,
  col_grid = 0x2F3742FF,
  col_mid_a = 0x55D6BEFF,
  col_side_a = 0xA6A7FFFF,
  col_int_a = 0x4AA96CFF,
  col_mid_b = 0xFFB454FF,
  col_side_b = 0xFF7A90FF,
  col_int_b = 0xFF8C3BFF,
  col_fill_b = 0xFFB45455,
  col_target_a = 0x7BE49599,
  col_target_b = 0xFFB45499,

  sample_rate = 48000,
  gate_db = -70.0,
  history_sec = 300.0,
  panel_ratio = 0.25,
  panel_hidden = false,

  range_start = 0.0,
  range_end = 0.0,
  offline_status = "Idle",
  offline_program_channels_idx = 1,
  offline_debug_enabled = false
}

local PARAMS_KEY_ORDER = {
  "enabled", "measurement_locked", "mode_idx", "quick_preset_idx", "time_axis_idx", "view_idx",
  "source_a_enabled", "source_a_bind_idx", "source_a_name", "source_a_profile_idx",
  "source_b_enabled", "source_b_bind_idx", "source_b_name", "source_b_profile_idx",
  "show_grid", "show_marker_flags", "show_marker_flag_text", "marker_flags_filter_mode_idx", "marker_flags_name_filter", "cache_mode_idx", "cache_markers", "cache_marker_lanes", "cache_curve_gap", "cache_hover_readout", "cache_refresh_ms", "render_early_skip", "show_heatmap", "show_target", "y_top_zero", "show_mid", "show_side", "show_integrated",
  "overlay_b_fill", "overlay_fill_source_idx", "overlay_fill_field_idx", "ribbon_field_idx", "overlay_fill_alpha", "critical_lu", "critical_upper_lu", "critical_lower_lu", "source_a_critical_upper_lu", "source_a_critical_lower_lu", "source_b_critical_upper_lu", "source_b_critical_lower_lu", "alert_mode_idx", "alert_source_idx", "alert_min_duration_sec", "alert_merge_gap_sec", "alert_cooldown_sec", "alert_lra_enabled", "alert_tp_enabled", "alert_clear_prev", "alert_prefix", "alert_lra_prefix", "alert_tp_prefix", "alert_smart_naming", "alert_include_lufs", "alert_help", "alert_use_lane", "alert_lane_name", "alert_lane_index", "alert_color_low", "alert_color_high", "show_critical_lines", "y_zoom", "x_zoom",
  "source_a_show_heatmap", "source_b_show_heatmap", "source_a_show_critical", "source_b_show_critical", "source_a_show_tolerance", "source_b_show_tolerance",
  "source_a_show_mid", "source_a_show_side", "source_a_show_integrated", "source_a_target_enabled", "source_a_target_lufs", "source_a_tolerance_lu", "source_a_lra_limit_lu", "source_a_tp_limit_dbtp", "source_a_alert_field_idx", "source_a_momentary_window_sec", "source_a_short_window_sec", "source_a_hop_sec",
  "source_b_show_mid", "source_b_show_side", "source_b_show_integrated", "source_b_target_enabled", "source_b_target_lufs", "source_b_tolerance_lu", "source_b_lra_limit_lu", "source_b_tp_limit_dbtp", "source_b_alert_field_idx", "source_b_momentary_window_sec", "source_b_short_window_sec", "source_b_hop_sec",
  "theme_preset", "col_bg", "col_panel", "col_grid", "col_mid_a", "col_side_a", "col_int_a", "col_mid_b", "col_side_b", "col_int_b", "col_fill_b", "col_target_a", "col_target_b",
  "sample_rate", "gate_db", "history_sec", "panel_ratio", "panel_hidden",
  "range_start", "range_end", "offline_program_channels_idx", "offline_debug_enabled"
}

local EXT_KEY = "params_v010"
local last_saved_blob = ""
local last_live_update = 0.0
local last_live_play_pos = nil

local state = {
  source_a = { tracks = {}, points = {}, summary = nil, label = "A" },
  source_b = { tracks = {}, points = {}, summary = nil, label = "B" },
  last_error = "",
  backend_note = "",
  offline_last_run = 0.0,
  live_hold = true,
  live_hold_ref = nil,
  pending_rewrite_pos = nil,
  alert_ids = {},
  marker_flags_cache = nil,
  marker_lane_map_cache = nil,
  marker_lane_name_cache = {},
  gap_dt_cache = {},
  hover_readout_cache = nil,
  alert_cooldown_last = {},
  offline_job = nil,
  offline_dry_plan = nil,
  offline_dry_run_a = true,
  offline_dry_run_b = true,
  offline_dry_range_idx = 1,
  offline_dry_marker_start = "=START",
  offline_dry_marker_end = "=END",
  offline_dry_popup_request = false,
  offline_progress_popup_request = false,
  offline_progress_popup_open = false,
  offline_debug_last = ""
}

local COCKOS_LM_JSFX_NAME = "JS:Loudness Meter Peak/RMS/LUFS (Cockos)"
local COCKOS_LM_FILE_NAME = "JS:realoudness"

local COCKOS_CFG_LUFS_M = 3
local COCKOS_CFG_LUFS_S = 4
local COCKOS_CFG_LUFS_I = 6
local COCKOS_CFG_REINIT = 10
local COCKOS_OUT_PEAK = 15
local COCKOS_OUT_LUFS_M = 18
local COCKOS_OUT_LUFS_S = 19
local COCKOS_OUT_LUFS_I = 20

local COLOR_BG = params.col_bg
local COLOR_PANEL = params.col_panel
local COLOR_TEXT = 0xDDE1E9FF
local COLOR_DIM = 0x8A94A3FF
local COLOR_GRID = params.col_grid
local COLOR_TARGET_A = params.col_target_a
local COLOR_TARGET_B = params.col_target_b
local COLOR_MID_A = params.col_mid_a
local COLOR_SIDE_A = params.col_side_a
local COLOR_INT_A = params.col_int_a
local COLOR_MID_B = params.col_mid_b
local COLOR_SIDE_B = params.col_side_b
local COLOR_INT_B = params.col_int_b
local COLOR_FILL_B = params.col_fill_b
local COLOR_DELTA = 0x7AD3FFFF

local CreateAlertMarkerAtTime
local GetCachedValue
local FindClosestPoint
local UpdateSourceBindings

local function LogError(msg)
  state.last_error = tostring(msg or "unknown")
  r.ShowConsoleMsg("[SBP Cine Loudness Analyzer] ERROR: " .. state.last_error .. "\n")
end

local function OfflineDebug(msg)
  state.offline_debug_last = tostring(msg or "")
  if not params.offline_debug_enabled then return end
  r.ShowConsoleMsg("[SBP CLA OFFLINE] " .. state.offline_debug_last .. "\n")
end

local function EstimateGapDt(points, field, t_span, cache_tag, compute_fn)
  local key = string.format("%s|%s|%d|%.3f|%.3f|%.3f", cache_tag or "gap", tostring(field or "?"), #points, (points[1] and points[1].t or 0.0), (points[#points] and points[#points].t or 0.0), t_span or 0.0)
  return GetCachedValue("gap_dt_cache", key, "cache_curve_gap", compute_fn)
end

local function PrecacheGapDt(points, field, t_start, t_end, cache_tag)
  if not points or #points < 2 then return end
  local t_span = math.max(0.001, (t_end or 0.0) - (t_start or 0.0))
  local function compute_gap()
    local dts = {}
    local prev_t = nil
    local prev_has = false
    for i = 1, #points do
      local p = points[i]
      local has_v = p[field] ~= nil
      if has_v and prev_has and prev_t then
        local dt = (p.t or 0.0) - prev_t
        if dt > 0 then
          dts[#dts + 1] = dt
          if #dts >= 96 then break end
        end
      end
      prev_t = p.t or prev_t
      prev_has = has_v
    end
    if #dts == 0 then
      return math.min(0.75, math.max(0.12, t_span / math.max(1, #points - 1)))
    end
    table.sort(dts)
    local median = dts[math.floor((#dts + 1) * 0.5)] or dts[#dts]
    return math.min(0.75, math.max(0.12, median * 1.6))
  end
  EstimateGapDt(points, field, t_span, cache_tag or "curve", compute_gap)
end

local function MaybePrepareGapLayer(points, field, t_start, t_end, cache_tag)
  if params.render_early_skip then return end
  PrecacheGapDt(points, field, t_start, t_end, cache_tag)
end

local function DestroyContextSafe()
  if r.ImGui_DestroyContext then
    r.ImGui_DestroyContext(ctx)
  end
end

local function IsCtrlDown()
  if r.ImGui_GetKeyMods and r.ImGui_Mod_Ctrl then
    local ok_mods, mods = pcall(r.ImGui_GetKeyMods, ctx)
    local ok_mask, ctrl_mask = pcall(r.ImGui_Mod_Ctrl)
    if ok_mods and ok_mask and type(mods) == "number" and type(ctrl_mask) == "number" then
      if (mods & ctrl_mask) ~= 0 then
        return true
      end
    end
  end
  if r.JS_Mouse_GetState then
    local ok_state, state = pcall(r.JS_Mouse_GetState, 4)
    if ok_state and type(state) == "number" then
      return (state & 4) ~= 0
    end
  end
  return false
end

local function IsXZoomModifierDown()
  local os_name = ""
  if r.GetOS then
    local ok_os, os_val = pcall(r.GetOS)
    if ok_os and type(os_val) == "string" then
      os_name = os_val
    end
  end
  local is_mac = os_name:find("OSX", 1, true) ~= nil or os_name:find("mac", 1, true) ~= nil

  if r.ImGui_GetKeyMods then
    local ok_mods, mods = pcall(r.ImGui_GetKeyMods, ctx)
    if ok_mods and type(mods) == "number" then
      if r.ImGui_Mod_Ctrl then
        local ok_ctrl, ctrl_mask = pcall(r.ImGui_Mod_Ctrl)
        if ok_ctrl and type(ctrl_mask) == "number" and (mods & ctrl_mask) ~= 0 then
          return true
        end
      end
      if is_mac and r.ImGui_Mod_Super then
        local ok_super, super_mask = pcall(r.ImGui_Mod_Super)
        if ok_super and type(super_mask) == "number" and (mods & super_mask) ~= 0 then
          return true
        end
      end
    end
  end

  if IsCtrlDown() then
    return true
  end

  return false
end

local function IsGraphDoubleClick(plot_x, plot_y, plot_w, plot_h)
  local mx, my = r.GetMousePosition()
  if mx < plot_x or mx > (plot_x + plot_w) or my < plot_y or my > (plot_y + plot_h) then
    return false, mx, my
  end

  if r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    return true, mx, my
  end

  if r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
    local now = (r.time_precise and r.time_precise()) or 0.0
    local prev_t = state.graph_click_t or -999.0
    local prev_x = state.graph_click_x or mx
    local prev_y = state.graph_click_y or my
    local dt = now - prev_t
    local dx = math.abs(mx - prev_x)
    local dy = math.abs(my - prev_y)

    state.graph_click_t = now
    state.graph_click_x = mx
    state.graph_click_y = my

    if dt > 0.0 and dt <= 0.45 and dx <= 12 and dy <= 12 then
      return true, mx, my
    end
  end

  return false, mx, my
end

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function NormalizeColorU32(color, fallback)
  local c = tonumber(color)
  if c == nil then c = tonumber(fallback) or 0xFFFFFFFF end
  c = math.floor(c) % 4294967296
  if c < 0 then c = c + 4294967296 end
  return c
end

local function EnsureOpaqueColor(color, fallback)
  local c = NormalizeColorU32(color, fallback)
  local rgb = math.floor(c / 256) % 16777216
  return rgb * 256 + 0xFF
end

local function ToNativeColor(rgb)
  local c = tonumber(rgb or 0) or 0
  c = math.floor(c)
  local rr = math.floor(c / 65536) % 256
  local gg = math.floor(c / 256) % 256
  local bb = c % 256
  return (r.ColorToNative(rr, gg, bb) or 0) + 0x1000000
end

local function DbToAmp(db)
  return 10 ^ ((db or 0.0) / 20.0)
end

local function AmpToDb(amp)
  if not amp or amp <= 0 then return -120.0 end
  return 20.0 * (math.log(amp) / math.log(10))
end

local function SafeTrackName(track)
  if not track then return "" end
  local ok, _, name = pcall(r.GetTrackName, track)
  if ok then return tostring(name or "") end
  return ""
end

local function SerializeParams()
  local chunks = {}
  for _, key in ipairs(PARAMS_KEY_ORDER) do
    local value = params[key]
    local kind = type(value)
    if kind == "boolean" then
      chunks[#chunks + 1] = key .. "=b:" .. (value and "1" or "0")
    elseif kind == "number" then
      chunks[#chunks + 1] = key .. "=n:" .. string.format("%.10f", value)
    else
      chunks[#chunks + 1] = key .. "=s:" .. tostring(value or "")
    end
  end
  return table.concat(chunks, "|")
end

local function DeserializeParams(blob)
  if not blob or blob == "" then return end
  for token in string.gmatch(blob, "[^|]+") do
    local key, packed = token:match("^([^=]+)=([bns]:.*)$")
    if key and packed and params[key] ~= nil then
      local kind = packed:sub(1, 1)
      local raw = packed:sub(3)
      if kind == "b" then
        params[key] = (raw == "1")
      elseif kind == "n" then
        local n = tonumber(raw)
        if n ~= nil then params[key] = n end
      else
        params[key] = raw
      end
    end
  end
end

local function LoadParams()
  local blob = r.GetExtState(SCRIPT_ID, EXT_KEY)
  if blob and blob ~= "" then
    DeserializeParams(blob)
  end
  last_saved_blob = SerializeParams()
end

local function SaveParamsIfChanged(force)
  local blob = SerializeParams()
  if force or blob ~= last_saved_blob then
    r.SetExtState(SCRIPT_ID, EXT_KEY, blob, true)
    last_saved_blob = blob
  end
end

local function GetBindOption(idx)
  local i = math.floor((idx or 1) + 0.5)
  i = Clamp(i, 1, #BIND_OPTIONS)
  params.source_a_bind_idx = Clamp(params.source_a_bind_idx, 1, #BIND_OPTIONS)
  params.source_b_bind_idx = Clamp(params.source_b_bind_idx, 1, #BIND_OPTIONS)
  return BIND_OPTIONS[i], i
end

local function GetViewOption()
  params.view_idx = Clamp(math.floor((params.view_idx or 1) + 0.5), 1, #VIEW_OPTIONS)
  return VIEW_OPTIONS[params.view_idx]
end

local function GetModeOption()
  params.mode_idx = Clamp(math.floor((params.mode_idx or 1) + 0.5), 1, #MODE_OPTIONS)
  return MODE_OPTIONS[params.mode_idx]
end

local function GetTimeAxisOption()
  params.time_axis_idx = Clamp(math.floor((params.time_axis_idx or 1) + 0.5), 1, #TIME_AXIS_OPTIONS)
  return TIME_AXIS_OPTIONS[params.time_axis_idx]
end

local function GetQuickPresetOption()
  params.quick_preset_idx = Clamp(math.floor((params.quick_preset_idx or 1) + 0.5), 1, #QUICK_PRESET_OPTIONS)
  return QUICK_PRESET_OPTIONS[params.quick_preset_idx]
end

local function GetOfflineRangeOption()
  state.offline_dry_range_idx = Clamp(math.floor((state.offline_dry_range_idx or 1) + 0.5), 1, #OFFLINE_RANGE_OPTIONS)
  return OFFLINE_RANGE_OPTIONS[state.offline_dry_range_idx]
end

local function GetOfflineProgramChannelOption()
  params.offline_program_channels_idx = Clamp(math.floor((params.offline_program_channels_idx or 1) + 0.5), 1, #OFFLINE_PROGRAM_CHANNEL_OPTIONS)
  return OFFLINE_PROGRAM_CHANNEL_OPTIONS[params.offline_program_channels_idx]
end

local function GetAlertModeOption()
  params.alert_mode_idx = Clamp(math.floor((params.alert_mode_idx or 1) + 0.5), 1, #ALERT_MODE_OPTIONS)
  return ALERT_MODE_OPTIONS[params.alert_mode_idx]
end

local function GetAlertSourceOption()
  params.alert_source_idx = Clamp(math.floor((params.alert_source_idx or 1) + 0.5), 1, #ALERT_SOURCE_OPTIONS)
  return ALERT_SOURCE_OPTIONS[params.alert_source_idx]
end

local function GetMarkerFlagFilterOption()
  params.marker_flags_filter_mode_idx = Clamp(math.floor((params.marker_flags_filter_mode_idx or 1) + 0.5), 1, #MARKER_FLAG_FILTER_OPTIONS)
  return MARKER_FLAG_FILTER_OPTIONS[params.marker_flags_filter_mode_idx]
end

local function GetCacheModeOption()
  params.cache_mode_idx = Clamp(math.floor((params.cache_mode_idx or 1) + 0.5), 1, #CACHE_MODE_OPTIONS)
  return CACHE_MODE_OPTIONS[params.cache_mode_idx]
end

local function CacheRefreshSeconds()
  params.cache_refresh_ms = Clamp(math.floor((params.cache_refresh_ms or 150) + 0.5), 50, 2000)
  return (params.cache_refresh_ms or 150) / 1000.0
end

local function UseCache(flag_key)
  if GetCacheModeOption().key == "all" then
    return true
  end
  return params[flag_key] and true or false
end

GetCachedValue = function(bucket_name, item_key, flag_key, compute_fn)
  if not UseCache(flag_key) then
    return compute_fn()
  end

  local bucket = state[bucket_name]
  if type(bucket) ~= "table" then
    bucket = {}
    state[bucket_name] = bucket
  end

  local now = (r.time_precise and r.time_precise()) or 0.0
  local ttl = CacheRefreshSeconds()
  local hit = bucket[item_key]
  if hit and (now - (hit.ts or 0.0)) <= ttl then
    return hit.val
  end

  local val = compute_fn()
  bucket[item_key] = { ts = now, val = val }
  return val
end

local function GetRibbonFieldOption()
  params.ribbon_field_idx = Clamp(math.floor((params.ribbon_field_idx or 1) + 0.5), 1, #RIBBON_FIELD_OPTIONS)
  return RIBBON_FIELD_OPTIONS[params.ribbon_field_idx]
end

local function GetProfileOptionByIndex(profile_idx)
  local idx = Clamp(math.floor((profile_idx or 1) + 0.5), 1, #PROFILE_OPTIONS)
  return PROFILE_OPTIONS[idx], idx
end

local function GetAlertFieldOptionByIndex(field_idx)
  local idx = Clamp(math.floor((field_idx or 1) + 0.5), 1, #ALERT_FIELD_OPTIONS)
  return ALERT_FIELD_OPTIONS[idx], idx
end

local function GetSourcePrefix(source_key)
  return (source_key == "B") and "source_b_" or "source_a_"
end

local function ApplyProfileToSource(source_key, profile_idx)
  local pref = GetSourcePrefix(source_key)
  local profile, idx = GetProfileOptionByIndex(profile_idx)
  params[pref .. "profile_idx"] = idx
  if not profile then return end

  if profile.label ~= "Custom" then
    params[pref .. "target_lufs"] = tonumber(profile.target) or params[pref .. "target_lufs"]
    params[pref .. "tolerance_lu"] = tonumber(profile.tol) or params[pref .. "tolerance_lu"]
    params[pref .. "lra_limit_lu"] = tonumber(profile.lra_max) or params[pref .. "lra_limit_lu"]
    params[pref .. "tp_limit_dbtp"] = tonumber(profile.tp_max) or params[pref .. "tp_limit_dbtp"]
  end

  params[pref .. "momentary_window_sec"] = Clamp(tonumber(profile.m_win) or params[pref .. "momentary_window_sec"] or 0.4, 0.2, 6.0)
  params[pref .. "short_window_sec"] = Clamp(tonumber(profile.s_win) or params[pref .. "short_window_sec"] or 3.0, 1.0, 30.0)
  params[pref .. "hop_sec"] = Clamp(tonumber(profile.hop) or params[pref .. "hop_sec"] or 0.1, 0.02, 0.5)

  local desired_field = tostring(profile.alert_field or "m")
  local desired_idx = 1
  for i = 1, #ALERT_FIELD_OPTIONS do
    if ALERT_FIELD_OPTIONS[i].key == desired_field then
      desired_idx = i
      break
    end
  end
  params[pref .. "alert_field_idx"] = desired_idx
end

local function ApplyQuickPreset(idx)
  params.quick_preset_idx = Clamp(math.floor((idx or 1) + 0.5), 1, #QUICK_PRESET_OPTIONS)
  local p = GetQuickPresetOption()
  if not p then return end

  params.source_a_enabled = true
  params.source_b_enabled = true
  params.view_idx = 1
  params.overlay_b_fill = true
  params.overlay_fill_alpha = 0.35
  params.alert_source_idx = 3

  if p.key == "film_dialog" then
    ApplyProfileToSource("A", 3)
    ApplyProfileToSource("B", 1)
    params.source_a_bind_idx = 1
    params.source_a_name = ""
    params.source_b_bind_idx = 3
    params.source_b_name = ""
    params.source_a_show_mid = false
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = true
    params.source_b_show_side = false
    params.source_b_show_integrated = false
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 3
    params.ribbon_field_idx = 1
  elseif p.key == "dialog_lkfs_focus" then
    ApplyProfileToSource("A", 5)
    ApplyProfileToSource("B", 2)
    params.source_a_bind_idx = 1
    params.source_a_name = ""
    params.source_b_bind_idx = 3
    params.source_b_name = ""
    params.source_a_show_mid = false
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = true
    params.source_b_show_side = false
    params.source_b_show_integrated = true
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 2
    params.ribbon_field_idx = 2
  elseif p.key == "broadcast_ebu" then
    ApplyProfileToSource("A", 1)
    ApplyProfileToSource("B", 1)
    params.source_a_bind_idx = 1
    params.source_b_bind_idx = 3
    params.source_a_show_mid = false
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = true
    params.source_b_show_side = false
    params.source_b_show_integrated = true
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 3
    params.ribbon_field_idx = 3
  elseif p.key == "streaming_general" then
    ApplyProfileToSource("A", 8)
    ApplyProfileToSource("B", 8)
    params.source_a_bind_idx = 1
    params.source_b_bind_idx = 3
    params.source_a_show_mid = true
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = true
    params.source_b_show_side = false
    params.source_b_show_integrated = false
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 1
    params.ribbon_field_idx = 1
  elseif p.key == "music_platforms" then
    ApplyProfileToSource("A", 6)
    ApplyProfileToSource("B", 6)
    params.source_a_bind_idx = 3
    params.source_a_name = ""
    params.source_b_bind_idx = 1
    params.source_b_name = ""
    params.source_a_show_mid = true
    params.source_a_show_side = true
    params.source_a_show_integrated = true
    params.source_b_show_mid = false
    params.source_b_show_side = false
    params.source_b_show_integrated = true
    params.overlay_fill_source_idx = 2
    params.overlay_fill_field_idx = 3
    params.ribbon_field_idx = 2
  elseif p.key == "vertical_mobile" then
    ApplyProfileToSource("A", 9)
    ApplyProfileToSource("B", 9)
    params.source_a_bind_idx = 1
    params.source_b_bind_idx = 3
    params.source_a_show_mid = true
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = true
    params.source_b_show_side = false
    params.source_b_show_integrated = false
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 1
    params.ribbon_field_idx = 1
  elseif p.key == "podcast" then
    ApplyProfileToSource("A", 10)
    ApplyProfileToSource("B", 10)
    params.source_a_bind_idx = 1
    params.source_b_bind_idx = 3
    params.source_a_show_mid = false
    params.source_a_show_side = true
    params.source_a_show_integrated = true
    params.source_b_show_mid = false
    params.source_b_show_side = true
    params.source_b_show_integrated = false
    params.overlay_fill_source_idx = 1
    params.overlay_fill_field_idx = 2
    params.ribbon_field_idx = 2
  elseif p.key == "cinema_dialog_program_eu" then
    ApplyProfileToSource("A", 11)
    ApplyProfileToSource("B", 11)
    params.source_a_bind_idx = 3
    params.source_a_name = ""
    params.source_b_bind_idx = 1
    params.source_b_name = ""
    params.source_a_show_mid = true
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = false
    params.source_b_show_side = false
    params.source_b_show_integrated = true
    params.overlay_fill_source_idx = 2
    params.overlay_fill_field_idx = 2
    params.ribbon_field_idx = 2
  elseif p.key == "cinema_dialog_program_us" then
    ApplyProfileToSource("A", 12)
    ApplyProfileToSource("B", 12)
    params.source_a_bind_idx = 3
    params.source_a_name = ""
    params.source_b_bind_idx = 1
    params.source_b_name = ""
    params.source_a_show_mid = true
    params.source_a_show_side = false
    params.source_a_show_integrated = true
    params.source_b_show_mid = false
    params.source_b_show_side = false
    params.source_b_show_integrated = true
    params.overlay_fill_source_idx = 2
    params.overlay_fill_field_idx = 2
    params.ribbon_field_idx = 2
  end

  UpdateSourceBindings()
  state.backend_note = "Quick Preset applied: " .. tostring(p.label)
end

local function BuildProfileSignature(profile)
  if not profile then return "" end
  return string.format("Target %.1f LUFS | Tol +/- %.1f LU | TP <= %.1f dBTP", tonumber(profile.target) or -23.0, tonumber(profile.tol) or 1.0, tonumber(profile.tp_max) or -1.0)
end

local function BuildProfileTooltip(profile)
  if not profile then return "" end
  local metric = tostring(profile.alert_field or "m"):upper()
  return string.format(
    "Target %.1f LUFS | Tol +/- %.1f LU | TP <= %.1f dBTP\nLRA <= %.1f LU | M %.1fs | S %.1fs | Analysis metric: %s (fixed by preset to keep the A/B rows aligned)",
    tonumber(profile.target) or -23.0,
    tonumber(profile.tol) or 1.0,
    tonumber(profile.tp_max) or -1.0,
    tonumber(profile.lra_max) or 8.0,
    tonumber(profile.m_win) or 0.4,
    tonumber(profile.s_win) or 3.0,
    metric
  )
end

local function ApplyThemePreset(idx)
  params.theme_preset = Clamp(math.floor((idx or 1) + 0.5), 1, 7)
  if params.theme_preset == 1 then
    -- ReaWhoosh-like classic dark teal palette.
    params.col_bg = 0x1A1A1AFF
    params.col_panel = 0x252525FF
    params.col_grid = 0x2F3742FF
    params.col_mid_a = 0x55D6BEFF
    params.col_side_a = 0xA6A7FFFF
    params.col_int_a = 0x4AA96CFF
    params.col_mid_b = 0xFFB454FF
    params.col_side_b = 0xFF7A90FF
    params.col_int_b = 0xFF8C3BFF
    params.col_fill_b = 0xFFB45455
    params.col_target_a = 0x7BE49599
    params.col_target_b = 0xFFB45499
  elseif params.theme_preset == 2 then
    params.col_bg = 0x0F1116FF
    params.col_panel = 0x1A202CFF
    params.col_grid = 0x394556FF
    params.col_mid_a = 0x69F5D2FF
    params.col_side_a = 0xAAB8FFFF
    params.col_int_a = 0x62D27CFF
    params.col_mid_b = 0xFFC56EFF
    params.col_side_b = 0xFF92A8FF
    params.col_int_b = 0xFFAC4BFF
    params.col_fill_b = 0xFFC56E66
    params.col_target_a = 0x69F5D299
    params.col_target_b = 0xFFC56E99
  elseif params.theme_preset == 3 then
    params.col_bg = 0x181413FF
    params.col_panel = 0x26201DFF
    params.col_grid = 0x4A3A33FF
    params.col_mid_a = 0x6EE7C8FF
    params.col_side_a = 0xB7C2FFFF
    params.col_int_a = 0x6BCF8CFF
    params.col_mid_b = 0xFF9E66FF
    params.col_side_b = 0xFF8FA0FF
    params.col_int_b = 0xFF7E63FF
    params.col_fill_b = 0xFF9E6655
    params.col_target_a = 0x6EE7C899
    params.col_target_b = 0xFF9E6699
  elseif params.theme_preset == 4 then
    params.col_bg = 0x0D1418FF
    params.col_panel = 0x142127FF
    params.col_grid = 0x2B3F48FF
    params.col_mid_a = 0x58E1C1FF
    params.col_side_a = 0x90B7FFFF
    params.col_int_a = 0x5CD08CFF
    params.col_mid_b = 0xFFD57BFF
    params.col_side_b = 0xFF98B9FF
    params.col_int_b = 0xFF9E5AFF
    params.col_fill_b = 0xFFD57B50
    params.col_target_a = 0x58E1C199
    params.col_target_b = 0xFFD57B99
  elseif params.theme_preset == 5 then
    params.col_bg = 0x17191CFF
    params.col_panel = 0x23272BFF
    params.col_grid = 0x3A434BFF
    params.col_mid_a = 0x6EF3D8FF
    params.col_side_a = 0xC6D2E6FF
    params.col_int_a = 0x78DA9CFF
    params.col_mid_b = 0xFFBE78FF
    params.col_side_b = 0xF29FB7FF
    params.col_int_b = 0xD18BFFFF
    params.col_fill_b = 0xFFBE7850
    params.col_target_a = 0x6EF3D899
    params.col_target_b = 0xFFBE7899
  elseif params.theme_preset == 6 then
    params.col_bg = 0x10161EFF
    params.col_panel = 0x1C2632FF
    params.col_grid = 0x364A62FF
    params.col_mid_a = 0x4EE0FFFF
    params.col_side_a = 0x95A8FFFF
    params.col_int_a = 0x60C875FF
    params.col_mid_b = 0xFFB04AFF
    params.col_side_b = 0xFF86BAFF
    params.col_int_b = 0xFF7F5CFF
    params.col_fill_b = 0xFFB04A55
    params.col_target_a = 0x4EE0FF99
    params.col_target_b = 0xFFB04A99
  else
    params.col_bg = 0x141112FF
    params.col_panel = 0x261F24FF
    params.col_grid = 0x453343FF
    params.col_mid_a = 0x74F0CEFF
    params.col_side_a = 0xB7BBFFFF
    params.col_int_a = 0x74CD8EFF
    params.col_mid_b = 0xFFC07AFF
    params.col_side_b = 0xFF8DA8FF
    params.col_int_b = 0xFF77A8FF
    params.col_fill_b = 0xFFC07A50
    params.col_target_a = 0x74F0CE99
    params.col_target_b = 0xFFC07A99
  end
end

local function RefreshColorsFromParams()
  -- Keep curve colors opaque; fill transparency is controlled only by overlay_fill_alpha.
  params.col_mid_a = EnsureOpaqueColor(params.col_mid_a, 0x55D6BEFF)
  params.col_side_a = EnsureOpaqueColor(params.col_side_a, 0xA6A7FFFF)
  params.col_int_a = EnsureOpaqueColor(params.col_int_a, 0x4AA96CFF)
  params.col_mid_b = EnsureOpaqueColor(params.col_mid_b, 0xFFB454FF)
  params.col_side_b = EnsureOpaqueColor(params.col_side_b, 0xFF7A90FF)
  params.col_int_b = EnsureOpaqueColor(params.col_int_b, 0xFF8C3BFF)

  COLOR_BG = params.col_bg
  COLOR_PANEL = params.col_panel
  COLOR_GRID = params.col_grid
  COLOR_MID_A = params.col_mid_a
  COLOR_SIDE_A = params.col_side_a
  COLOR_INT_A = params.col_int_a
  COLOR_MID_B = params.col_mid_b
  COLOR_SIDE_B = params.col_side_b
  COLOR_INT_B = params.col_int_b
  COLOR_FILL_B = params.col_fill_b
  COLOR_TARGET_A = params.col_target_a
  COLOR_TARGET_B = params.col_target_b
end

local function FindTracksByName(name)
  local out = {}
  local key = (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if key == "" then return out end
  local track_count = r.CountTracks(0)
  for i = 0, track_count - 1 do
    local tr = r.GetTrack(0, i)
    local tr_name = SafeTrackName(tr):lower()
    if tr_name == key then
      out[#out + 1] = tr
    end
  end
  if #out > 0 then return out end
  for i = 0, track_count - 1 do
    local tr = r.GetTrack(0, i)
    local tr_name = SafeTrackName(tr):lower()
    if tr_name:find(key, 1, true) then
      out[#out + 1] = tr
    end
  end
  return out
end

local function FindFolderTracksByName(name)
  local out = {}
  local roots = FindTracksByName(name)
  for _, root in ipairs(roots) do
    local depth = r.GetMediaTrackInfo_Value(root, "I_FOLDERDEPTH") or 0
    if depth > 0 then
      out[#out + 1] = root
      local idx = math.floor((r.GetMediaTrackInfo_Value(root, "IP_TRACKNUMBER") or 1) - 1)
      local remain = depth
      local total = r.CountTracks(0)
      for i = idx + 1, total - 1 do
        local tr = r.GetTrack(0, i)
        if not tr then break end
        out[#out + 1] = tr
        local d = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
        remain = remain + d
        if remain <= 0 then break end
      end
      return out
    end
  end
  return out
end

local function GetSelectedTracksList()
  local out = {}
  local count = r.CountSelectedTracks(0)
  for i = 0, count - 1 do
    local tr = r.GetSelectedTrack(0, i)
    if tr then out[#out + 1] = tr end
  end
  return out
end

local function GetAllTracksList()
  local out = {}
  local total = r.CountTracks(0)
  for i = 0, total - 1 do
    local tr = r.GetTrack(0, i)
    if tr then out[#out + 1] = tr end
  end
  return out
end

local function ResolveSourceTracks(bind_idx, source_name)
  local bind = GetBindOption(bind_idx)
  local key = bind.key

  if key == "master" then
    local master = r.GetMasterTrack(0)
    if master then return { master }, "MASTER" end
    return {}, "MASTER"
  end

  if key == "track_name" then
    local found = FindTracksByName(source_name)
    if #found > 0 then
      return found, source_name ~= "" and source_name or "Track Name"
    end
    return {}, source_name ~= "" and source_name or "Track Name"
  end

  if key == "folder_name" then
    local found = FindFolderTracksByName(source_name)
    if #found > 0 then
      return found, source_name ~= "" and (source_name .. " (Folder)") or "Folder"
    end
    local selected_fallback = GetSelectedTracksList()
    if #selected_fallback > 0 then
      return selected_fallback, "Selected (fallback)"
    end
    return {}, source_name ~= "" and (source_name .. " (Folder)") or "Folder"
  end

  if key == "selected" then
    local selected = GetSelectedTracksList()
    if #selected > 0 then return selected, "Selected Tracks" end
    return {}, "Selected Tracks"
  end

  return {}, "Unknown"
end

local function ComputePercentile(values, p)
  if #values == 0 then return -120.0 end
  table.sort(values)
  local idx = math.floor((#values - 1) * p + 1)
  idx = Clamp(idx, 1, #values)
  return values[idx]
end

local function EnergyToLufs(energy)
  if not energy or energy <= 0.0 then return -120.0 end
  return -0.691 + 10.0 * (math.log(energy) / math.log(10))
end

local function LufsToEnergy(lufs)
  return 10 ^ (((lufs or -120.0) + 0.691) / 10.0)
end

local K_SHELF = {
  b0 = 1.53512485958697,
  b1 = -2.69169618940638,
  b2 = 1.19839281085285,
  a1 = -1.69065929318241,
  a2 = 0.73248077421585
}

local K_HIGHPASS = {
  b0 = 1.0,
  b1 = -2.0,
  b2 = 1.0,
  a1 = -1.99004745483398,
  a2 = 0.99007225036621
}

local function NewBiquadState()
  return { z1 = 0.0, z2 = 0.0 }
end

local function BiquadProcess(st, c, x)
  local y = c.b0 * x + st.z1
  st.z1 = c.b1 * x - c.a1 * y + st.z2
  st.z2 = c.b2 * x - c.a2 * y
  return y
end

local function NewKWeightState()
  return {
    shelf = NewBiquadState(),
    hpf = NewBiquadState()
  }
end

local function KWeightSample(st, x)
  local y = BiquadProcess(st.shelf, K_SHELF, x)
  return BiquadProcess(st.hpf, K_HIGHPASS, y)
end

local function CreateTrackAccessors(tracks)
  local out = {}
  for _, tr in ipairs(tracks) do
    local acc = r.CreateTrackAudioAccessor(tr)
    if acc then
      local trim_vol = r.GetMediaTrackInfo_Value(tr, "D_VOL") or 1.0
      out[#out + 1] = {
        acc = acc,
        start_t = r.GetAudioAccessorStartTime(acc),
        end_t = r.GetAudioAccessorEndTime(acc),
        channels = Clamp(math.floor(r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2), 1, 64),
        trim_vol = trim_vol,
        buffer = nil,
        buffer_n = 0
      }
    end
  end
  return out
end

local function DenormFrom01(v, lo, hi)
  local n = Clamp(tonumber(v) or 0.0, 0.0, 1.0)
  return lo + (hi - lo) * n
end

local function ReadTrackFxPhysicalParam(track, fx_idx, param_idx, lo, hi)
  if r.TrackFX_GetParam then
    local ok, value = pcall(r.TrackFX_GetParam, track, fx_idx, param_idx)
    if ok and type(value) == "number" then
      return value
    end
  end
  local norm = r.TrackFX_GetParamNormalized(track, fx_idx, param_idx)
  return DenormFrom01(norm, lo, hi)
end

local function TryGetFxName(track, fx_idx)
  local ok, retval, name = pcall(r.TrackFX_GetFXName, track, fx_idx, "")
  if not ok then return "" end
  if type(retval) == "string" then return retval end
  if type(name) == "string" then return name end
  return ""
end

local function FindFxByNameContains(track, needle)
  local n = r.TrackFX_GetCount(track) or 0
  local key = (needle or ""):lower()
  for i = 0, n - 1 do
    local fx_name = TryGetFxName(track, i):lower()
    if fx_name ~= "" and fx_name:find(key, 1, true) then
      return i
    end
  end
  return -1
end

local function EnsureCockosMeterConfigured(track, fx_idx)
  r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_M, 2)
  r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_S, 1)
  r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_LUFS_I, 1)
  r.TrackFX_SetParam(track, fx_idx, COCKOS_CFG_REINIT, 0)
end

local function EnsureCockosMeterFx(track, allow_insert)
  if not track then return -1, "Track is nil" end

  local cockos_idx = FindFxByNameContains(track, "loudness meter peak/rms/lufs")
  if cockos_idx < 0 and allow_insert ~= false then
    cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_JSFX_NAME, false, 0)
  end
  if cockos_idx < 0 and allow_insert ~= false then
    cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_FILE_NAME, false, 0)
  end
  if cockos_idx < 0 and allow_insert ~= false then
    cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_JSFX_NAME, false, 1)
  end
  if cockos_idx < 0 and allow_insert ~= false then
    cockos_idx = r.TrackFX_AddByName(track, COCKOS_LM_FILE_NAME, false, 1)
  end
  if cockos_idx >= 0 then
    local n_params = r.TrackFX_GetNumParams(track, cockos_idx) or 0
    if n_params > COCKOS_OUT_LUFS_I then
      EnsureCockosMeterConfigured(track, cockos_idx)
      return cockos_idx, nil
    end
  end

  return -1, "Cockos Loudness Meter not found/loaded"
end

local function ReadBridgePoint(track, allow_insert)
  local fx_idx, err = EnsureCockosMeterFx(track, allow_insert)
  if fx_idx < 0 then return nil, err end

  local m_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_M, -100.0, 0.0)
  local st_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_S, -100.0, 0.0)
  local i_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_LUFS_I, -100.0, 0.0)
  local peak_db = ReadTrackFxPhysicalParam(track, fx_idx, COCKOS_OUT_PEAK, -150.0, 20.0)
  if m_db <= -99.0 and st_db <= -99.0 then
    -- Keep timeline continuity on very quiet passages: write a floor point instead of dropping sample.
    m_db = -120.0
    st_db = -120.0
    if i_db <= -99.0 then i_db = -120.0 end
    if peak_db <= -149.0 then peak_db = -150.0 end
  end
  state.backend_note = "JSFX source: Cockos Loudness Meter"

  return {
    m = m_db,
    st = st_db,
    i = i_db,
    s = st_db,
    peak = peak_db,
    gated = (m_db < -70.0),
    lin_energy = LufsToEnergy(m_db),
    m_energy = LufsToEnergy(m_db),
    i_src = i_db
  }, nil
end

local function DestroyTrackAccessors(accessors)
  for i = 1, #accessors do
    local a = accessors[i]
    if a and a.acc then r.DestroyAudioAccessor(a.acc) end
  end
end

local function BuildSummary(points, gate_db)
  if #points == 0 then
    return {
      integrated = -120.0,
      peak = -120.0,
      lra = 0.0,
      short_max = -120.0,
      gated_ratio = 0.0
    }
  end

  local peak = -120.0
  local short_max = -120.0
  local momentary_max = -120.0
  local side_max = -120.0
  local momentary_energies_abs = {}
  local short_for_lra = {}
  local i_src_latest = nil
  local gate_abs = LufsToEnergy(-70.0)
  local last_point = points[#points]

  for _, p in ipairs(points) do
    if (p.peak or -120.0) > peak then peak = p.peak end
    if (p.m or -120.0) > momentary_max then momentary_max = p.m end
    if (p.st or -120.0) > short_max then short_max = p.st end
    if (p.s or -120.0) > side_max then side_max = p.s end

    local e = p.m_energy
    if e and e > gate_abs then
      momentary_energies_abs[#momentary_energies_abs + 1] = e
    end
    if p.st then
      short_for_lra[#short_for_lra + 1] = p.st
    end
    if p.i_src then
      i_src_latest = p.i_src
    end
  end

  local integrated = -120.0
  local gated_ratio = 100.0
  if #momentary_energies_abs > 0 then
    local sum_abs = 0.0
    for i = 1, #momentary_energies_abs do
      sum_abs = sum_abs + momentary_energies_abs[i]
    end
    local ungated_lufs = EnergyToLufs(sum_abs / #momentary_energies_abs)
    local rel_gate_lufs = ungated_lufs - 10.0
    local final_gate = LufsToEnergy(math.max(-70.0, rel_gate_lufs))

    local sum_final = 0.0
    local count_final = 0
    for i = 1, #momentary_energies_abs do
      local e = momentary_energies_abs[i]
      if e >= final_gate then
        sum_final = sum_final + e
        count_final = count_final + 1
      end
    end
    if count_final > 0 then
      integrated = EnergyToLufs(sum_final / count_final)
      gated_ratio = 100.0 * (1.0 - (count_final / #points))
    end
  end

  local lra = 0.0
  if integrated > -120.0 and #short_for_lra >= 5 then
    local lra_gate = integrated - 20.0
    local lra_pool = {}
    for i = 1, #short_for_lra do
      local v = short_for_lra[i]
      if v >= lra_gate then lra_pool[#lra_pool + 1] = v end
    end
    if #lra_pool >= 5 then
      local p10 = ComputePercentile(lra_pool, 0.10)
      local p95 = ComputePercentile(lra_pool, 0.95)
      lra = p95 - p10
    end
  end

  if i_src_latest ~= nil then
    integrated = i_src_latest
  end

  return {
    integrated = integrated,
    peak = peak,
    lra = lra,
    short_max = short_max,
    short_current = last_point and (last_point.st or -120.0) or -120.0,
    side_current = last_point and (last_point.s or -120.0) or -120.0,
    side_max = side_max,
    momentary_current = last_point and (last_point.m or -120.0) or -120.0,
    momentary_max = momentary_max,
    gated_ratio = gated_ratio,
    gate_reference = gate_db
  }
end

local function DownmixAccessorFrameToLR(buf, idx, channels, gain)
  local total_ch = math.max(1, math.floor(channels or 1))
  local forced = tonumber(GetOfflineProgramChannelOption().channels) or 0
  local ch = total_ch
  if forced > 0 then
    ch = math.min(total_ch, forced)
  else
    if total_ch >= 8 then
      ch = 8
    elseif total_ch >= 6 then
      ch = 6
    else
      ch = math.min(total_ch, 2)
    end
  end

  local g = gain or 1.0
  local function sample_at(ch_idx)
    return (buf[idx + ch_idx - 1] or 0.0) * g
  end

  local l = sample_at(1)
  local rch = (ch >= 2) and sample_at(2) or l

  if ch >= 3 then
    local c = sample_at(3)
    l = l + 0.7071 * c
    rch = rch + 0.7071 * c
  end
  if ch >= 4 then
    local lfe = sample_at(4)
    l = l + 0.5 * lfe
    rch = rch + 0.5 * lfe
  end
  if ch >= 5 then
    l = l + 0.7071 * sample_at(5)
  end
  if ch >= 6 then
    rch = rch + 0.7071 * sample_at(6)
  end

  if ch >= 7 then
    l = l + 0.5 * sample_at(7)
  end
  if ch >= 8 then
    rch = rch + 0.5 * sample_at(8)
  end

  return l, rch
end

local function AnalyzeWindowAtTime(tracks, end_t, sample_rate)
  if #tracks == 0 then return nil end

  local sr = 48000
  local short_sec = 3.0
  local momentary_sec = 0.4
  local t_end = math.max(0.0, end_t or 0.0)
  local t_start = math.max(0.0, t_end - short_sec)
  local samples = math.max(1, math.floor((t_end - t_start) * sr + 0.5))
  if samples < 8 then return nil end

  local accessors = CreateTrackAccessors(tracks)
  if #accessors == 0 then return nil end

  local mix_l = {}
  local mix_r = {}
  for i = 1, samples do
    mix_l[i] = 0.0
    mix_r[i] = 0.0
  end

  for i = 1, #accessors do
    local a = accessors[i]
    if t_start <= a.end_t and t_end >= a.start_t then
      if (not a.buffer) or a.buffer_n < samples then
        a.buffer = r.new_array(samples * a.channels)
        a.buffer_n = samples
      end
      local rc = r.GetAudioAccessorSamples(a.acc, sr, a.channels, t_start, samples, a.buffer)
      if rc == 1 then
        local idx = 1
        local gain = a.trim_vol or 1.0
        for s = 1, samples do
          local l, rv = DownmixAccessorFrameToLR(a.buffer, idx, a.channels, gain)
          idx = idx + a.channels
          mix_l[s] = mix_l[s] + l
          mix_r[s] = mix_r[s] + rv
        end
      end
    end
  end

  DestroyTrackAccessors(accessors)

  local st_l = NewKWeightState()
  local st_r = NewKWeightState()
  local short_sq = 0.0
  local momentary_sq = 0.0
  local side_sq = 0.0
  local peak_lin = 0.0
  local m_samples = math.max(1, math.floor(momentary_sec * sr + 0.5))
  local m_start = math.max(1, samples - m_samples + 1)

  for i = 1, samples do
    local l = mix_l[i]
    local rv = mix_r[i]
    local kl = KWeightSample(st_l, l)
    local kr = KWeightSample(st_r, rv)
    local e = kl * kl + kr * kr
    short_sq = short_sq + e
    if i >= m_start then
      momentary_sq = momentary_sq + e
      local side = 0.5 * (l - rv)
      side_sq = side_sq + side * side
      local abs_l = math.abs(l)
      local abs_r = math.abs(rv)
      if abs_l > peak_lin then peak_lin = abs_l end
      if abs_r > peak_lin then peak_lin = abs_r end
    end
  end

  local short_e = short_sq / math.max(1, samples)
  local mom_e = momentary_sq / math.max(1, samples - m_start + 1)
  local side_e = side_sq / math.max(1, samples - m_start + 1)
  local m_db = EnergyToLufs(mom_e)
  local st_db = EnergyToLufs(short_e)
  local s_db = AmpToDb(math.sqrt(math.max(0.0, side_e)))

  return {
    m = m_db,
    s = s_db,
    st = st_db,
    peak = AmpToDb(peak_lin),
    gated = (m_db < -70.0),
    lin_energy = mom_e,
    m_energy = mom_e
  }
end

local function AnalyzeHopAtTime(tracks, start_t, duration_sec, sample_rate)
  if #tracks == 0 then return nil end

  local sr = 48000
  local t0 = math.max(0.0, start_t or 0.0)
  local dur = math.max(0.001, duration_sec or 0.1)
  local samples = math.max(1, math.floor(dur * sr + 0.5))

  local accessors = CreateTrackAccessors(tracks)
  if #accessors == 0 then return nil end

  local mix_l = {}
  local mix_r = {}
  for i = 1, samples do
    mix_l[i] = 0.0
    mix_r[i] = 0.0
  end

  for i = 1, #accessors do
    local a = accessors[i]
    if t0 <= a.end_t and (t0 + dur) >= a.start_t then
      if (not a.buffer) or a.buffer_n < samples then
        a.buffer = r.new_array(samples * a.channels)
        a.buffer_n = samples
      end
      local rc = r.GetAudioAccessorSamples(a.acc, sr, a.channels, t0, samples, a.buffer)
      if rc == 1 then
        local idx = 1
        local gain = a.trim_vol or 1.0
        for s = 1, samples do
          local l, rv = DownmixAccessorFrameToLR(a.buffer, idx, a.channels, gain)
          idx = idx + a.channels
          mix_l[s] = mix_l[s] + l
          mix_r[s] = mix_r[s] + rv
        end
      end
    end
  end

  DestroyTrackAccessors(accessors)

  local k_l = NewKWeightState()
  local k_r = NewKWeightState()
  local hop_sq = 0.0
  local hop_side_sq = 0.0
  local hop_peak = 0.0
  for s = 1, samples do
    local l = mix_l[s]
    local rv = mix_r[s]
    local kl = KWeightSample(k_l, l)
    local kr = KWeightSample(k_r, rv)
    hop_sq = hop_sq + (kl * kl + kr * kr)
    local side = 0.5 * (l - rv)
    hop_side_sq = hop_side_sq + side * side
    local abs_l = math.abs(l)
    local abs_r = math.abs(rv)
    if abs_l > hop_peak then hop_peak = abs_l end
    if abs_r > hop_peak then hop_peak = abs_r end
  end

  return {
    hop_energy = hop_sq / math.max(1, samples),
    hop_side_energy = hop_side_sq / math.max(1, samples),
    hop_peak = hop_peak
  }
end

local function AnalyzeRange(tracks, range_start, range_end)
  local points = {}
  if #tracks == 0 then return points end

  local sr = 48000
  local hop_sec = 0.1
  local hop_samples = math.max(1, math.floor(sr * hop_sec + 0.5))
  local mom_hops = 4
  local short_hops = 30

  local accessors = CreateTrackAccessors(tracks)
  if #accessors == 0 then return points end

  local k_l = NewKWeightState()
  local k_r = NewKWeightState()

  local mom_q, short_q, side_q, peak_q = {}, {}, {}, {}
  local mom_sum = 0.0
  local short_sum = 0.0
  local side_sum = 0.0

  local abs_gate = LufsToEnergy(-70.0)
  local abs_sum = 0.0
  local abs_count = 0

  local t = math.max(0.0, range_start)
  local t_stop = math.max(t, range_end)

  r.PreventUIRefresh(1)
  while t < t_stop do
    local remain = t_stop - t
    local chunk_samples = math.max(1, math.min(hop_samples, math.floor(remain * sr + 0.5)))
    local chunk_sec = chunk_samples / sr
    if chunk_samples <= 0 or chunk_sec <= 0 then break end

    local mix_l = {}
    local mix_r = {}
    for i = 1, chunk_samples do
      mix_l[i] = 0.0
      mix_r[i] = 0.0
    end

    for i = 1, #accessors do
      local a = accessors[i]
      if t <= a.end_t and (t + chunk_sec) >= a.start_t then
        if (not a.buffer) or a.buffer_n < chunk_samples then
          a.buffer = r.new_array(chunk_samples * a.channels)
          a.buffer_n = chunk_samples
        end
        local rc = r.GetAudioAccessorSamples(a.acc, sr, a.channels, t, chunk_samples, a.buffer)
        if rc == 1 then
          local idx = 1
          local gain = a.trim_vol or 1.0
          for s = 1, chunk_samples do
            local l, rv = DownmixAccessorFrameToLR(a.buffer, idx, a.channels, gain)
            idx = idx + a.channels
            mix_l[s] = mix_l[s] + l
            mix_r[s] = mix_r[s] + rv
          end
        end
      end
    end

    local hop_sq = 0.0
    local hop_side_sq = 0.0
    local hop_peak = 0.0
    for s = 1, chunk_samples do
      local l = mix_l[s]
      local rv = mix_r[s]
      local kl = KWeightSample(k_l, l)
      local kr = KWeightSample(k_r, rv)
      hop_sq = hop_sq + (kl * kl + kr * kr)
      local side = 0.5 * (l - rv)
      hop_side_sq = hop_side_sq + side * side
      local abs_l = math.abs(l)
      local abs_r = math.abs(rv)
      if abs_l > hop_peak then hop_peak = abs_l end
      if abs_r > hop_peak then hop_peak = abs_r end
    end

    local hop_energy = hop_sq / math.max(1, chunk_samples)
    local hop_side = AmpToDb(math.sqrt(hop_side_sq / math.max(1, chunk_samples)))

    mom_q[#mom_q + 1] = hop_energy
    mom_sum = mom_sum + hop_energy
    if #mom_q > mom_hops then
      mom_sum = mom_sum - table.remove(mom_q, 1)
    end

    short_q[#short_q + 1] = hop_energy
    short_sum = short_sum + hop_energy
    if #short_q > short_hops then
      short_sum = short_sum - table.remove(short_q, 1)
    end

    side_q[#side_q + 1] = hop_side
    side_sum = side_sum + hop_side
    if #side_q > mom_hops then
      side_sum = side_sum - table.remove(side_q, 1)
    end

    peak_q[#peak_q + 1] = hop_peak
    if #peak_q > mom_hops then table.remove(peak_q, 1) end

    if #mom_q >= mom_hops then
      local m_energy = mom_sum / mom_hops
      local st_energy = short_sum / math.max(1, #short_q)
      local m_db = EnergyToLufs(m_energy)
      local st_db = EnergyToLufs(st_energy)
      local side_db = side_sum / math.max(1, #side_q)

      local peak_lin = 0.0
      for i = 1, #peak_q do
        if peak_q[i] > peak_lin then peak_lin = peak_q[i] end
      end

      if m_energy >= abs_gate then
        abs_sum = abs_sum + m_energy
        abs_count = abs_count + 1
      end
      local i_db = (abs_count > 0) and EnergyToLufs(abs_sum / abs_count) or -120.0

      points[#points + 1] = {
        t = t + chunk_sec,
        m = m_db,
        s = side_db,
        st = st_db,
        i = i_db,
        peak = AmpToDb(peak_lin),
        gated = (m_db < -70.0),
        lin_energy = m_energy,
        m_energy = m_energy
      }
    end

    t = t + chunk_sec
  end
  r.PreventUIRefresh(-1)
  DestroyTrackAccessors(accessors)

  return points
end

local function TrimLivePoints(points, now_t, history_sec)
  local out = {}
  local min_t = now_t - history_sec
  for i = 1, #points do
    if (points[i].t or 0.0) >= min_t then
      out[#out + 1] = points[i]
    end
  end
  return out
end

local function TrimPointsPreCursorBuffer(points, pivot_t, pre_sec)
  local out = {}
  local t0 = (pivot_t or 0.0) - math.max(0.0, pre_sec or 1.0)
  local t1 = (pivot_t or 0.0)
  for i = 1, #points do
    local pt = points[i]
    local t = pt.t or -1e9
    if t < t0 or t > t1 then
      out[#out + 1] = pt
    end
  end
  return out
end

local function ReplacePointsNearTime(points, center_t, half_window)
  local out = {}
  local hw = math.max(0.001, half_window or 0.05)
  local t0 = (center_t or 0.0) - hw
  local t1 = (center_t or 0.0) + hw
  for i = 1, #points do
    local pt = points[i]
    local t = pt.t or -1e9
    if t < t0 or t > t1 then
      out[#out + 1] = pt
    end
  end
  return out
end

local function ClearGraphHistory(hold_ref)
  state.source_a.points = {}
  state.source_a.summary = nil
  state.source_b.points = {}
  state.source_b.summary = nil
  params.range_start = 0.0
  params.range_end = 0.0
  last_live_update = 0.0
  last_live_play_pos = nil
  state.live_hold = true
  state.live_hold_ref = hold_ref
  state.backend_note = ""
end

local function BlendColor(cold, hot, t)
  t = Clamp(t, 0.0, 1.0)
  local function ch(c, shift)
    return math.floor(c / (2 ^ shift)) % 256
  end
  local r1, g1, b1, a1 = ch(cold, 24), ch(cold, 16), ch(cold, 8), ch(cold, 0)
  local r2, g2, b2, a2 = ch(hot, 24), ch(hot, 16), ch(hot, 8), ch(hot, 0)
  local rr = math.floor(r1 + (r2 - r1) * t)
  local gg = math.floor(g1 + (g2 - g1) * t)
  local bb = math.floor(b1 + (b2 - b1) * t)
  local aa = math.floor(a1 + (a2 - a1) * t)
  return rr * 16777216 + gg * 65536 + bb * 256 + aa
end

local function SetAlpha(color, alpha_01)
  local c = NormalizeColorU32(color, 0xFFFFFFFF)
  local a = Clamp(math.floor((alpha_01 or 0.0) * 255 + 0.5), 0, 255)
  local rgb = math.floor(c / 256) % 16777216
  return rgb * 256 + a
end

local function DrawSummaryCard(label, summary, color)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), color)
  r.ImGui_Text(ctx, label)
  r.ImGui_PopStyleColor(ctx)
  if not summary then
    r.ImGui_TextColored(ctx, COLOR_DIM, "No data")
    return
  end
  r.ImGui_Text(ctx, string.format("I: %.1f LUFS | TP: %.1f dBFS", summary.integrated, summary.peak))
  r.ImGui_Text(ctx, string.format("LRA: %.1f LU | Short Max: %.1f", summary.lra, summary.short_max))
  r.ImGui_Text(ctx, string.format("Gated: %.1f%%", summary.gated_ratio))
end

local function BuildHeatmap(points, x_min, y_min, width, height, t_start, t_end, db_min, db_max)
  if #points == 0 then return end
  if height < 150 then return end

  local bins_x = math.max(140, math.floor(width / 2))
  local bins_y = 18
  local matrix = {}
  local max_count = 0

  for x = 1, bins_x do
    matrix[x] = {}
    for y = 1, bins_y do matrix[x][y] = 0 end
  end

  local t_span = math.max(0.001, t_end - t_start)
  for _, p in ipairs(points) do
    local tx = (p.t - t_start) / t_span
    local ty = ((p.m or db_min) - db_min) / math.max(0.001, (db_max - db_min))
    local bx = Clamp(math.floor(tx * bins_x) + 1, 1, bins_x)
    local by = Clamp(math.floor((1.0 - ty) * bins_y) + 1, 1, bins_y)
    matrix[bx][by] = matrix[bx][by] + 1
    if matrix[bx][by] > max_count then max_count = matrix[bx][by] end
  end

  if max_count <= 0 then return end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local step_x = width / bins_x
  local step_y = height / bins_y

  for bx = 1, bins_x do
    for by = 1, bins_y do
      local c = matrix[bx][by]
      if c > 0 then
        local k = c / max_count
        if k >= 0.08 then
          local color = BlendColor(0x2E74D93A, 0xFF8A3D5A, k)
          local x1 = x_min + (bx - 1) * step_x
          local y1 = y_min + (by - 1) * step_y
          r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + step_x, y1 + step_y, color, 0.0)
        end
      end
    end
  end
end

local function DrawStatusRibbon(points, field, target, tol, critical_up_lu, critical_down_lu, x_min, y_min, width, height, t_start, t_end, band_idx, band_count)
  if #points < 2 then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local t_span = math.max(0.001, t_end - t_start)
  local axis_mode = GetTimeAxisOption().key
  local function estimate_gap_dt()
    local dts = {}
    local prev_t = nil
    local prev_has = false
    for i = 1, #points do
      local p = points[i]
      local has_v = p[field] ~= nil
      if has_v and prev_has and prev_t then
        local dt = (p.t or 0.0) - prev_t
        if dt > 0 then
          dts[#dts + 1] = dt
          if #dts >= 96 then break end
        end
      end
      prev_t = p.t or prev_t
      prev_has = has_v
    end
    if #dts == 0 then
      return math.min(0.75, math.max(0.12, t_span / math.max(1, #points - 1)))
    end
    table.sort(dts)
    local median = dts[math.floor((#dts + 1) * 0.5)] or dts[#dts]
    return math.min(0.75, math.max(0.12, median * 1.6))
  end
  local gap_dt = ((axis_mode == "timeline") or (axis_mode == "cursor_center")) and EstimateGapDt(points, field, t_span, "ribbon", estimate_gap_dt) or nil
  local crit_up = math.max(0.1, critical_up_lu or 5.0)
  local crit_down = math.max(0.1, critical_down_lu or 5.0)
  band_count = math.max(1, math.floor(band_count or 1))
  band_idx = Clamp(math.floor(band_idx or 1), 1, band_count)
  local total_h = 9
  local band_h = math.max(3, math.floor(total_h / band_count))
  local y2 = y_min + height - 1 - (band_count - band_idx) * band_h
  local y1 = y2 - band_h + 1

  local prev_x = nil
  local prev_v = nil
  local prev_t = nil
  for i = 1, #points do
    local p = points[i]
    local x = x_min + ((p.t - t_start) / t_span) * width
    local v = p[field]
    local dt_ok = (not gap_dt) or (prev_t and (p.t - prev_t) <= gap_dt)
    if v and prev_x and prev_v and x >= prev_x and dt_ok then
      local color = 0x3BB273DD
      if v > (target + tol) or v < (target - tol) then color = 0xD9A23BDD end
      if v > (target + crit_up) or v < (target - crit_down) then color = 0xD44A4ADD end
      r.ImGui_DrawList_AddRectFilled(dl, prev_x, y1, x, y2, color, 0.0)
    end
    if v then
      prev_x, prev_v = x, v
      prev_t = p.t
    else
      prev_x, prev_v, prev_t = nil, nil, nil
    end
  end
end

local function DrawLaneTag(x, y, text, color)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddText(dl, x, y, color, text)
end

local function DrawGrid(x_min, y_min, width, height)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local v_lines = 12
  local h_lines = 8
  for i = 0, v_lines do
    local x = x_min + (width * i / v_lines)
    r.ImGui_DrawList_AddLine(dl, x, y_min, x, y_min + height, COLOR_GRID, 1.0)
  end
  for i = 0, h_lines do
    local y = y_min + (height * i / h_lines)
    r.ImGui_DrawList_AddLine(dl, x_min, y, x_min + width, y, COLOR_GRID, 1.0)
  end
end

local function DrawCurve(points, field, color, x_min, y_min, width, height, t_start, t_end, db_min, db_max, line_width)
  if #points < 2 then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local t_span = math.max(0.001, t_end - t_start)
  local d_span = math.max(0.001, db_max - db_min)
  local axis_mode = GetTimeAxisOption().key
  local function estimate_gap_dt()
    local dts = {}
    local prev_t = nil
    local prev_has = false
    for i = 1, #points do
      local p = points[i]
      local has_v = p[field] ~= nil
      if has_v and prev_has and prev_t then
        local dt = (p.t or 0.0) - prev_t
        if dt > 0 then
          dts[#dts + 1] = dt
          if #dts >= 96 then break end
        end
      end
      prev_t = p.t or prev_t
      prev_has = has_v
    end
    if #dts == 0 then
      return math.min(0.75, math.max(0.12, t_span / math.max(1, #points - 1)))
    end
    table.sort(dts)
    local median = dts[math.floor((#dts + 1) * 0.5)] or dts[#dts]
    return math.min(0.75, math.max(0.12, median * 1.6))
  end
  local gap_dt = ((axis_mode == "timeline") or (axis_mode == "cursor_center")) and EstimateGapDt(points, field, t_span, "curve", estimate_gap_dt) or nil
  local max_dx = math.max(8, width * 0.22)
  local stroke = line_width or 2.0

  local prev_x = nil
  local prev_y = nil
  local prev_t = nil
  local smooth_val = nil
  for i = 1, #points do
    local p = points[i]
    local x = x_min + ((p.t - t_start) / t_span) * width
    local raw_val = p[field]
    if raw_val then
      if not smooth_val then
        smooth_val = raw_val
      else
        smooth_val = smooth_val * 0.78 + raw_val * 0.22
      end
      local val = Clamp(smooth_val, db_min, db_max)
      local y = y_min + (1.0 - ((val - db_min) / d_span)) * height
      local dt_ok = (not gap_dt) or (prev_t and (p.t - prev_t) <= gap_dt)
      local can_join = prev_x and prev_y and x >= prev_x and (x - prev_x) <= max_dx and dt_ok
      if can_join then
        r.ImGui_DrawList_AddLine(dl, prev_x, prev_y, x, y, color, stroke)
      end
      prev_x, prev_y = x, y
      prev_t = p.t
    else
      -- Gap in source data: break line to avoid accidental closure artifacts.
      prev_x, prev_y, prev_t = nil, nil, nil
      smooth_val = nil
    end
  end
end

local function DrawFilledCurve(points, field, color, x_min, y_min, width, height, t_start, t_end, db_min, db_max)
  if #points < 2 then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local t_span = math.max(0.001, t_end - t_start)
  local d_span = math.max(0.001, db_max - db_min)
  local axis_mode = GetTimeAxisOption().key
  local function estimate_gap_dt()
    local dts = {}
    local prev_t = nil
    local prev_has = false
    for i = 1, #points do
      local p = points[i]
      local has_v = p[field] ~= nil
      if has_v and prev_has and prev_t then
        local dt = (p.t or 0.0) - prev_t
        if dt > 0 then
          dts[#dts + 1] = dt
          if #dts >= 96 then break end
        end
      end
      prev_t = p.t or prev_t
      prev_has = has_v
    end
    if #dts == 0 then
      return math.min(0.75, math.max(0.12, t_span / math.max(1, #points - 1)))
    end
    table.sort(dts)
    local median = dts[math.floor((#dts + 1) * 0.5)] or dts[#dts]
    return math.min(0.75, math.max(0.12, median * 1.6))
  end
  local gap_dt = ((axis_mode == "timeline") or (axis_mode == "cursor_center")) and EstimateGapDt(points, field, t_span, "fill", estimate_gap_dt) or nil
  local base_y = y_min + height
  local max_dx = math.max(8, width * 0.22)
  local prev_x = nil
  local prev_y = nil
  local prev_t = nil
  local smooth_val = nil

  for i = 1, #points do
    local p = points[i]
    local x = x_min + ((p.t - t_start) / t_span) * width
    local raw_val = p[field]
    if raw_val then
      if not smooth_val then
        smooth_val = raw_val
      else
        smooth_val = smooth_val * 0.78 + raw_val * 0.22
      end
      local y = y_min + (1.0 - ((Clamp(smooth_val, db_min, db_max) - db_min) / d_span)) * height
      local dt_ok = (not gap_dt) or (prev_t and (p.t - prev_t) <= gap_dt)
      local can_join = prev_x and prev_y and x >= prev_x and (x - prev_x) <= max_dx and dt_ok
      if can_join then
        local x1 = math.min(prev_x, x)
        local x2 = math.max(prev_x, x)
        local top = math.min(prev_y, y)
        if (x2 - x1) < 0.05 then x2 = x1 + 0.05 end
        r.ImGui_DrawList_AddRectFilled(dl, x1, top, x2, base_y, color, 0.0)
      end
      prev_x, prev_y = x, y
      prev_t = p.t
    else
      prev_x, prev_y, prev_t = nil, nil, nil
      smooth_val = nil
    end
  end
end

local function DrawTargetLine(x_min, y_min, width, height, target_lufs, tolerance_lu, color_line, db_min, db_max, show_tolerance)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local d_span = math.max(0.001, db_max - db_min)
  local cl = NormalizeColorU32(color_line, 0xFFFFFFFF)
  local target_val = Clamp(target_lufs, db_min, db_max)
  local y = y_min + (1.0 - ((target_val - db_min) / d_span)) * height
  r.ImGui_DrawList_AddLine(dl, x_min, y, x_min + width, y, cl, 1.0)

  if not show_tolerance then
    return
  end

  local top_tol = Clamp(target_lufs + tolerance_lu, db_min, db_max)
  local bot_tol = Clamp(target_lufs - tolerance_lu, db_min, db_max)
  local y1 = y_min + (1.0 - ((top_tol - db_min) / d_span)) * height
  local y2 = y_min + (1.0 - ((bot_tol - db_min) / d_span)) * height
  local rr = math.floor(cl / 16777216) % 256
  local gg = math.floor(cl / 65536) % 256
  local bb = math.floor(cl / 256) % 256
  local fill_color = rr * 16777216 + gg * 65536 + bb * 256 + 0x20
  local tol_line = rr * 16777216 + gg * 65536 + bb * 256 + 0x88
  r.ImGui_DrawList_AddRectFilled(dl, x_min, y1, x_min + width, y2, fill_color)
  r.ImGui_DrawList_AddLine(dl, x_min, y1, x_min + width, y1, tol_line, 1.0)
  r.ImGui_DrawList_AddLine(dl, x_min, y2, x_min + width, y2, tol_line, 1.0)
end

local function DrawCriticalLines(x_min, y_min, width, height, target_lufs, tolerance_lu, critical_up_lu, critical_down_lu, db_min, db_max)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local d_span = math.max(0.001, db_max - db_min)
  local up = Clamp(target_lufs + math.max(0.1, critical_up_lu or 8.0), db_min, db_max)
  local dn = Clamp(target_lufs - math.max(0.1, critical_down_lu or 8.0), db_min, db_max)
  local y_up = y_min + (1.0 - ((up - db_min) / d_span)) * height
  local y_dn = y_min + (1.0 - ((dn - db_min) / d_span)) * height
  local col = 0xD44A4A66
  r.ImGui_DrawList_AddLine(dl, x_min, y_up, x_min + width, y_up, col, 1.0)
  r.ImGui_DrawList_AddLine(dl, x_min, y_dn, x_min + width, y_dn, col, 1.0)
end

local function FormatTimeMMSS(sec)
  local s = tonumber(sec) or 0.0
  local sign = ""
  if s < 0 then
    sign = "-"
    s = -s
  end
  local total = math.floor(s + 0.5)
  local mm = math.floor(total / 60)
  local ss = total % 60
  return string.format("%s%02d:%02d", sign, mm, ss)
end

local function DrawAxisLabels(area_x, area_y, plot_x, plot_y, plot_w, plot_h, t_start, t_end, db_min, db_max, show_time, skip_first_tick, skip_last_tick)
  if show_time == nil then show_time = true end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ticks = 6
  local d_span = math.max(0.001, db_max - db_min)
  for i = 0, ticks do
    if (not (skip_first_tick and i == 0)) and (not (skip_last_tick and i == ticks)) then
    local d = db_max - (d_span * i / ticks)
    local y = plot_y + (plot_h * i / ticks)
    r.ImGui_DrawList_AddText(dl, area_x + 4, y - 10, COLOR_DIM, string.format("%.0f", d))
    end
  end

  if show_time then
    local axis_mode = GetTimeAxisOption().key
    local t_span = math.max(0.001, t_end - t_start)
    for i = 0, 10 do
      local x = plot_x + plot_w * (i / 10)
      local tv = t_start + t_span * (i / 10)
      local label = ((axis_mode == "timeline") or (axis_mode == "cursor_center")) and FormatTimeMMSS(tv) or FormatTimeMMSS(tv - t_start)
      r.ImGui_DrawList_AddText(dl, x - 16, area_y + plot_h + 2, COLOR_DIM, label)
    end
  end
end

local function DrawTimeAxisLabels(area_y, plot_x, plot_w, plot_h, t_start, t_end)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local axis_mode = GetTimeAxisOption().key
  local t_span = math.max(0.001, t_end - t_start)
  for i = 0, 10 do
    local x = plot_x + plot_w * (i / 10)
    local tv = t_start + t_span * (i / 10)
    local label = ((axis_mode == "timeline") or (axis_mode == "cursor_center")) and FormatTimeMMSS(tv) or FormatTimeMMSS(tv - t_start)
    r.ImGui_DrawList_AddText(dl, x - 16, area_y + plot_h + 2, COLOR_DIM, label)
  end
end

local function BuildMarkerLaneMap()
  return GetCachedValue("marker_lane_map_cache", "lane_map", "cache_marker_lanes", function()
    local map = {}
    if not (r.APIExists and r.APIExists("GetNumRegionsOrMarkers") and r.APIExists("GetRegionOrMarker") and r.APIExists("GetRegionOrMarkerInfo_Value")) then
      return map
    end

    local total = math.floor((r.GetNumRegionsOrMarkers(0) or 0) + 0.5)
    for i = 0, math.max(0, total - 1) do
      local ok_obj, obj = pcall(r.GetRegionOrMarker, 0, i, "")
      if ok_obj and obj then
        local isrgn = (r.GetRegionOrMarkerInfo_Value(0, obj, "B_ISREGION") or 0) >= 0.5
        if not isrgn then
          local idnum = math.floor((r.GetRegionOrMarkerInfo_Value(0, obj, "I_NUMBER") or -999999) + 0.5)
          local lane_idx = math.floor((r.GetRegionOrMarkerInfo_Value(0, obj, "I_LANENUMBER") or -1) + 0.5)
          map[idnum] = lane_idx
        end
      end
    end
    return map
  end)
end

local function GetLaneNameByIndex(lane_idx, cache)
  if lane_idx == nil or lane_idx < 0 then return "" end
  if cache[lane_idx] ~= nil then
    return cache[lane_idx]
  end

  local name = ""
  if r.GetSetProjectInfo_String then
    local desc = "RULER_LANE_NAME:" .. tostring(lane_idx)
    local ok_nm, _, nm = pcall(r.GetSetProjectInfo_String, 0, desc, "", false)
    if ok_nm then
      name = tostring(nm or "")
    end
  end
  cache[lane_idx] = name
  return name
end

local function CollectVisibleMarkers(t_start, t_end, max_count)
  local filter_opt = GetMarkerFlagFilterOption()
  local filter_text = tostring(params.marker_flags_name_filter or "")
  local filter_text_lc = string.lower(filter_text)
  local key = string.format("%.3f|%.3f|%d|%s|%s", t_start or 0.0, t_end or 0.0, math.floor(max_count or 96), filter_opt.key or "all", filter_text_lc)

  return GetCachedValue("marker_flags_cache", key, "cache_markers", function()
    local out = {}
    if not (r.CountProjectMarkers and r.EnumProjectMarkers2) then
      return out
    end

    local use_lane_contains = (filter_opt.key == "lane_contains") and (filter_text ~= "")
    local use_lane_exact = (filter_opt.key == "lane_exact") and (filter_text ~= "")
    local lane_map = BuildMarkerLaneMap()
    local lane_name_cache = UseCache("cache_marker_lanes") and (state.marker_lane_name_cache or {}) or {}
    if UseCache("cache_marker_lanes") then
      state.marker_lane_name_cache = lane_name_cache
    end

    local total = math.floor((r.CountProjectMarkers(0) or 0) + 0.5)
    if total < 1 then
      return out
    end

    for i = 0, total - 1 do
      local ok, retval, isrgn, pos, _, name, id = pcall(r.EnumProjectMarkers2, 0, i)
      if ok and retval and retval > 0 and (not isrgn) and pos and pos >= t_start and pos <= t_end then
        local nm = tostring(name or "")
        local lane_idx = lane_map[id or -999999] or -1
        local lane_name = GetLaneNameByIndex(lane_idx, lane_name_cache)
        local lane_lc = string.lower(lane_name)
        local pass = true
        if use_lane_contains then
          pass = string.find(lane_lc, filter_text_lc, 1, true) ~= nil
        elseif use_lane_exact then
          pass = lane_lc == filter_text_lc
        end
        if pass then
          out[#out + 1] = { t = pos, name = nm, id = id or -1, lane_idx = lane_idx, lane_name = lane_name }
        end
      end
    end

    local keep = math.max(8, math.floor(max_count or 96))
    if #out <= keep then
      return out
    end

    local trimmed = {}
    local step = #out / keep
    for j = 0, keep - 1 do
      local idx = math.floor(j * step) + 1
      if idx > #out then idx = #out end
      trimmed[#trimmed + 1] = out[idx]
    end
    return trimmed
  end)
end

local function DrawMarkerFlags(plot_x, plot_y, plot_w, t_start, t_end)
  if not params.show_marker_flags then return end

  local items = CollectVisibleMarkers(t_start, t_end, 96)
  if #items == 0 then return end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local span_t = math.max(0.001, t_end - t_start)
  local pole_col = 0xC9B27FFF
  local flag_col = 0xE3C98BFF
  local text_col = 0xDCE6F2FF

  local mx, my = r.GetMousePosition()
  local hovered = nil
  local last_label_x = -1000000

  for i = 1, #items do
    local m = items[i]
    local x = plot_x + ((m.t - t_start) / span_t) * plot_w
    if x >= plot_x and x <= (plot_x + plot_w) then
      local y0 = plot_y + 2
      local y1 = plot_y + 11
      r.ImGui_DrawList_AddLine(dl, x, y0, x, y1, pole_col, 1.0)
      r.ImGui_DrawList_AddTriangleFilled(dl, x + 1, y0 + 1, x + 8, y0 + 4, x + 1, y0 + 7, flag_col)

      if params.show_marker_flag_text and m.name and m.name ~= "" and (x - last_label_x) >= 26 then
        local txt = m.name
        if #txt > 18 then
          txt = string.sub(txt, 1, 18) .. "..."
        end
        r.ImGui_DrawList_AddText(dl, x + 10, y0 - 1, text_col, txt)
        last_label_x = x
      end

      if math.abs(mx - x) <= 5 and my >= plot_y and my <= (plot_y + 14) then
        hovered = m
      end
    end
  end

  if hovered then
    local nm = hovered.name
    if nm == "" then
      nm = "Marker #" .. tostring(hovered.id or "?")
    end
    local lane_info = (hovered.lane_name and hovered.lane_name ~= "") and (" | Lane: " .. hovered.lane_name) or ""
    local txt = string.format("%s @ %s%s", nm, FormatTimeMMSS(hovered.t), lane_info)
    r.ImGui_DrawList_AddText(dl, plot_x + 8, plot_y + 13, 0xE7ECF2FF, txt)
  end
end

local function ComputeVisibleRange(points_a, points_b)
  local min_v, max_v =  999.0, -999.0
  local function probe(points)
    for i = 1, #points do
      local p = points[i]
      if p.m then
        if p.m < min_v then min_v = p.m end
        if p.m > max_v then max_v = p.m end
      end
      if p.st then
        if p.st < min_v then min_v = p.st end
        if p.st > max_v then max_v = p.st end
      end
      if p.i then
        if p.i < min_v then min_v = p.i end
        if p.i > max_v then max_v = p.i end
      end
    end
  end

  probe(points_a)
  probe(points_b)

  if min_v > max_v then
    return -72.0, 0.0
  end

  local pad = 3.0
  local lo = math.max(-72.0, min_v - pad)
  local hi = math.min(6.0, max_v + pad)
  if (hi - lo) < 18.0 then
    local mid = 0.5 * (hi + lo)
    lo = math.max(-72.0, mid - 9.0)
    hi = math.min(6.0, mid + 9.0)
  end
  return lo, hi
end

local function ComputeVisibleRangeForSource(points, show_mid, show_side, show_i)
  local min_v, max_v =  999.0, -999.0
  for i = 1, #points do
    local p = points[i]
    if show_mid and p.m then
      if p.m < min_v then min_v = p.m end
      if p.m > max_v then max_v = p.m end
    end
    if show_side and p.st then
      if p.st < min_v then min_v = p.st end
      if p.st > max_v then max_v = p.st end
    end
    if show_i and p.i then
      if p.i < min_v then min_v = p.i end
      if p.i > max_v then max_v = p.i end
    end
  end

  if min_v > max_v then
    return -72.0, 0.0
  end

  local pad = 3.0
  local lo = math.max(-72.0, min_v - pad)
  local hi = params.y_top_zero and 0.0 or math.min(6.0, max_v + pad)
  if hi < lo then hi = lo + 1.0 end
  if (hi - lo) < 18.0 then
    if params.y_top_zero then
      lo = math.max(-72.0, hi - 18.0)
    else
      local mid = 0.5 * (hi + lo)
      lo = math.max(-72.0, mid - 9.0)
      hi = math.min(6.0, mid + 9.0)
    end
  end
  return lo, hi
end

local function ApplyYZoom(lo, hi, anchor_lufs)
  local z = Clamp(params.y_zoom or 1.0, 0.5, 3.0)
  local span = math.max(1.0, hi - lo)
  local new_span = span / z
  if params.y_top_zero then
    local n_hi = 0.0
    local n_lo = math.max(-72.0, n_hi - new_span)
    if (n_hi - n_lo) < 6.0 then n_lo = n_hi - 6.0 end
    return n_lo, n_hi
  end
  local mid = anchor_lufs or (0.5 * (hi + lo))
  local n_lo = math.max(-72.0, mid - new_span * 0.5)
  local n_hi = math.min(6.0, mid + new_span * 0.5)
  if (n_hi - n_lo) < 6.0 then
    n_lo = math.max(-72.0, n_hi - 6.0)
  end
  return n_lo, n_hi
end

local function ComputeGraphTimeWindow(mode_key, axis_mode)
  local is_playing = (r.GetPlayState() % 2) == 1
  local now_t = ((mode_key == "live") or (mode_key == "offline" and is_playing)) and r.GetPlayPosition() or params.range_end
  local start_t = (mode_key == "live") and (now_t - params.history_sec) or params.range_start
  local end_t = (mode_key == "live") and now_t or params.range_end
  local x_zoom = Clamp(params.x_zoom or 1.0, 0.25, 8.0)
  local span = math.max(1.0, end_t - start_t) / x_zoom
  local center_t = nil

  if axis_mode == "cursor_center" then
    local is_playing = (r.GetPlayState() % 2) == 1
    if mode_key == "live" and is_playing then
      center_t = r.GetPlayPosition()
    else
      center_t = r.GetCursorPositionEx and r.GetCursorPositionEx(0) or r.GetCursorPosition()
    end
    start_t = center_t - span * 0.5
    end_t = center_t + span * 0.5
  elseif mode_key == "live" then
    end_t = now_t
    start_t = end_t - span
  elseif mode_key == "offline" and is_playing then
    end_t = now_t
    start_t = end_t - span
  else
    local mid = 0.5 * (start_t + end_t)
    start_t = mid - span * 0.5
    end_t = mid + span * 0.5
  end

  if end_t <= start_t then end_t = start_t + 1.0 end
  return start_t, end_t, center_t
end

local function DrawCenterCursorMarker(area_y, plot_x, plot_y, plot_w, plot_h, t_start, t_end, center_t)
  if not center_t then return end
  local t_span = math.max(0.001, t_end - t_start)
  local x = plot_x + ((center_t - t_start) / t_span) * plot_w
  if x < plot_x or x > (plot_x + plot_w) then return end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  local line_col = 0x9AA8B8DD
  local tri_col = 0xD6E2F1EE
  local tri_y = area_y + 2
  local tri_w = 6
  local tri_h = 6

  r.ImGui_DrawList_AddLine(dl, x, plot_y, x, plot_y + plot_h, line_col, 1.0)
  r.ImGui_DrawList_AddTriangleFilled(dl, x, tri_y + tri_h, x - tri_w, tri_y, x + tri_w, tri_y, tri_col)
end

local function DrawGraph(points_a, points_b, graph_h)
  local avail_w, _ = r.ImGui_GetContentRegionAvail(ctx)
  local x_min, y_min = r.ImGui_GetCursorScreenPos(ctx)
  local width = math.max(320, avail_w)
  local height = math.max(90, graph_h or 120)

  local margin_left = 46
  local margin_right = 8
  local margin_top = 6
  local margin_bottom = 20
  local plot_x = x_min + margin_left
  local plot_y = y_min + margin_top
  local plot_w = math.max(40, width - margin_left - margin_right)
  local plot_h = math.max(30, height - margin_top - margin_bottom)

  r.ImGui_InvisibleButton(ctx, "GraphCanvas##main_canvas", width, height)
  if r.ImGui_IsItemHovered(ctx) then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel and math.abs(wheel) > 0.0001 then
      local zoom_mul = (wheel > 0) and 1.08 or 0.925
      if IsXZoomModifierDown() then
        params.x_zoom = Clamp((params.x_zoom or 1.0) * zoom_mul, 0.25, 8.0)
      else
        params.y_zoom = Clamp((params.y_zoom or 1.0) * zoom_mul, 0.5, 3.0)
      end
    end
  end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x_min, y_min, x_min + width, y_min + height, COLOR_PANEL, 4.0)

  if params.measurement_locked then
    r.ImGui_DrawList_AddText(dl, x_min + 16, y_min + 18, 0xE6C27AFF, "Measurement locked: new data paused")
  end

  local mode = GetModeOption()
  local axis_mode = GetTimeAxisOption().key
  local start_t, end_t, center_t = ComputeGraphTimeWindow(mode.key, axis_mode)

  local dbl, mx, my = IsGraphDoubleClick(plot_x, plot_y, plot_w, plot_h)
  if dbl and mx >= plot_x and mx <= (plot_x + plot_w) and my >= plot_y and my <= (plot_y + plot_h) then
    local span_t = math.max(0.001, end_t - start_t)
    local click_t = start_t + ((mx - plot_x) / math.max(1, plot_w)) * span_t
    click_t = Clamp(click_t, start_t, end_t)
    local ok_click, created = pcall(CreateAlertMarkerAtTime, click_t)
    if not ok_click then
      LogError("Graph marker double-click handler failed: " .. tostring(created))
    elseif not created then
      state.backend_note = "Double-click detected, marker creation failed"
    end
  end

  local db_min, db_max = ComputeVisibleRange(points_a, points_b)
  if params.y_top_zero then
    db_max = 0.0
    if (db_max - db_min) < 18.0 then
      db_min = math.max(-72.0, db_max - 18.0)
    end
  end
  local zoom_anchor = nil
  if params.show_target then
    local target_sum = 0.0
    local target_count = 0
    if params.source_a_target_enabled then
      target_sum = target_sum + params.source_a_target_lufs
      target_count = target_count + 1
    end
    if params.source_b_target_enabled then
      target_sum = target_sum + params.source_b_target_lufs
      target_count = target_count + 1
    end
    if target_count > 0 then
      zoom_anchor = target_sum / target_count
    end
  end
  db_min, db_max = ApplyYZoom(db_min, db_max, zoom_anchor)

  r.ImGui_DrawList_PushClipRect(dl, plot_x, plot_y, plot_x + plot_w, plot_y + plot_h, true)

  if params.show_grid then
    DrawGrid(plot_x, plot_y, plot_w, plot_h)
  end

  local view = GetViewOption()
  local ribbon_field = GetRibbonFieldOption().key
  if view.key == "overlay" then
    if params.show_target and params.source_a_target_enabled then
      DrawTargetLine(plot_x, plot_y, plot_w, plot_h, params.source_a_target_lufs, params.source_a_tolerance_lu, COLOR_TARGET_A, db_min, db_max, params.source_a_show_tolerance)
      if params.source_a_show_critical then
        DrawCriticalLines(plot_x, plot_y, plot_w, plot_h, params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, db_min, db_max)
      end
    end
    if params.show_target and params.source_b_target_enabled then
      DrawTargetLine(plot_x, plot_y, plot_w, plot_h, params.source_b_target_lufs, params.source_b_tolerance_lu, COLOR_TARGET_B, db_min, db_max, params.source_b_show_tolerance)
      if params.source_b_show_critical then
        DrawCriticalLines(plot_x, plot_y, plot_w, plot_h, params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, db_min, db_max)
      end
    end

    if params.overlay_b_fill then
      local fill_source = (params.overlay_fill_source_idx == 1) and points_a or points_b
      local fill_field = (params.overlay_fill_field_idx == 1) and "m" or ((params.overlay_fill_field_idx == 2) and "st" or "i")
      local fill_col_base = nil
      if params.overlay_fill_source_idx == 1 then
        fill_col_base = (fill_field == "m") and COLOR_MID_A or ((fill_field == "st") and COLOR_SIDE_A or COLOR_INT_A)
      else
        fill_col_base = (fill_field == "m") and COLOR_MID_B or ((fill_field == "st") and COLOR_SIDE_B or COLOR_INT_B)
      end
      local fill_col = SetAlpha(fill_col_base, params.overlay_fill_alpha)
      DrawFilledCurve(fill_source, fill_field, fill_col, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max)
    end

    if params.source_a_show_mid then DrawCurve(points_a, "m", COLOR_MID_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_a, "m", start_t, end_t, "curve") end
    if params.source_b_show_mid then DrawCurve(points_b, "m", COLOR_MID_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_b, "m", start_t, end_t, "curve") end
    if params.source_a_show_side then DrawCurve(points_a, "st", COLOR_SIDE_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max, 2.8) else MaybePrepareGapLayer(points_a, "st", start_t, end_t, "curve") end
    if params.source_b_show_side then DrawCurve(points_b, "st", COLOR_SIDE_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max, 2.8) else MaybePrepareGapLayer(points_b, "st", start_t, end_t, "curve") end
    if params.source_a_show_integrated then DrawCurve(points_a, "i", COLOR_INT_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_a, "i", start_t, end_t, "curve") end
    if params.source_b_show_integrated then DrawCurve(points_b, "i", COLOR_INT_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_b, "i", start_t, end_t, "curve") end
  elseif view.key == "split" then
    local lane_gap = 2
    local top_h = math.max(24, math.floor((plot_h - lane_gap) * 0.5))
    local gap = top_h + lane_gap
    local lane_a_y = plot_y
    local lane_b_y = plot_y + gap
    local db_min_a, db_max_a = ComputeVisibleRangeForSource(points_a, params.source_a_show_mid, params.source_a_show_side, params.source_a_show_integrated)
    local db_min_b, db_max_b = ComputeVisibleRangeForSource(points_b, params.source_b_show_mid, params.source_b_show_side, params.source_b_show_integrated)
    local anchor_a = params.source_a_target_enabled and params.source_a_target_lufs or nil
    local anchor_b = params.source_b_target_enabled and params.source_b_target_lufs or nil
    db_min_a, db_max_a = ApplyYZoom(db_min_a, db_max_a, anchor_a)
    db_min_b, db_max_b = ApplyYZoom(db_min_b, db_max_b, anchor_b)

    r.ImGui_DrawList_PushClipRect(dl, plot_x, lane_a_y, plot_x + plot_w, lane_a_y + top_h, true)
    if params.show_target and params.source_a_target_enabled then
      DrawTargetLine(plot_x, lane_a_y, plot_w, top_h, params.source_a_target_lufs, params.source_a_tolerance_lu, COLOR_TARGET_A, db_min_a, db_max_a, params.source_a_show_tolerance)
      if params.source_a_show_critical then
        DrawCriticalLines(plot_x, lane_a_y, plot_w, top_h, params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, db_min_a, db_max_a)
      end
    end
    if params.overlay_b_fill and params.overlay_fill_source_idx == 1 then
      local fill_field_a = (params.overlay_fill_field_idx == 1) and "m" or ((params.overlay_fill_field_idx == 2) and "st" or "i")
      local fill_base_a = (fill_field_a == "m") and COLOR_MID_A or ((fill_field_a == "st") and COLOR_SIDE_A or COLOR_INT_A)
      local fill_col_a = SetAlpha(fill_base_a, params.overlay_fill_alpha)
      DrawFilledCurve(points_a, fill_field_a, fill_col_a, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, db_min_a, db_max_a)
    end
    if params.source_a_show_mid then DrawCurve(points_a, "m", COLOR_MID_A, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, db_min_a, db_max_a) else MaybePrepareGapLayer(points_a, "m", start_t, end_t, "curve") end
    if params.source_a_show_side then DrawCurve(points_a, "st", COLOR_SIDE_A, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, db_min_a, db_max_a, 2.8) else MaybePrepareGapLayer(points_a, "st", start_t, end_t, "curve") end
    if params.source_a_show_integrated then DrawCurve(points_a, "i", COLOR_INT_A, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, db_min_a, db_max_a) else MaybePrepareGapLayer(points_a, "i", start_t, end_t, "curve") end
    if params.source_a_show_heatmap then
      DrawStatusRibbon(points_a, ribbon_field, params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, 1, 1)
    else
      MaybePrepareGapLayer(points_a, ribbon_field, start_t, end_t, "ribbon")
    end
    r.ImGui_DrawList_PopClipRect(dl)

    r.ImGui_DrawList_PushClipRect(dl, plot_x, lane_b_y, plot_x + plot_w, lane_b_y + top_h, true)
    if params.show_target and params.source_b_target_enabled then
      DrawTargetLine(plot_x, lane_b_y, plot_w, top_h, params.source_b_target_lufs, params.source_b_tolerance_lu, COLOR_TARGET_B, db_min_b, db_max_b, params.source_b_show_tolerance)
      if params.source_b_show_critical then
        DrawCriticalLines(plot_x, lane_b_y, plot_w, top_h, params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, db_min_b, db_max_b)
      end
    end
    if params.overlay_b_fill and params.overlay_fill_source_idx == 2 then
      local fill_field_b = (params.overlay_fill_field_idx == 1) and "m" or ((params.overlay_fill_field_idx == 2) and "st" or "i")
      local fill_base_b = (fill_field_b == "m") and COLOR_MID_B or ((fill_field_b == "st") and COLOR_SIDE_B or COLOR_INT_B)
      local fill_col_b = SetAlpha(fill_base_b, params.overlay_fill_alpha)
      DrawFilledCurve(points_b, fill_field_b, fill_col_b, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, db_min_b, db_max_b)
    end
    if params.source_b_show_mid then DrawCurve(points_b, "m", COLOR_MID_B, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, db_min_b, db_max_b) else MaybePrepareGapLayer(points_b, "m", start_t, end_t, "curve") end
    if params.source_b_show_side then DrawCurve(points_b, "st", COLOR_SIDE_B, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, db_min_b, db_max_b, 2.8) else MaybePrepareGapLayer(points_b, "st", start_t, end_t, "curve") end
    if params.source_b_show_integrated then DrawCurve(points_b, "i", COLOR_INT_B, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, db_min_b, db_max_b) else MaybePrepareGapLayer(points_b, "i", start_t, end_t, "curve") end
    if params.source_b_show_heatmap then
      DrawStatusRibbon(points_b, ribbon_field, params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, 1, 1)
    else
      MaybePrepareGapLayer(points_b, ribbon_field, start_t, end_t, "ribbon")
    end
    r.ImGui_DrawList_PopClipRect(dl)

    r.ImGui_DrawList_AddLine(dl, plot_x, lane_b_y - 1, plot_x + plot_w, lane_b_y - 1, COLOR_GRID, 1.0)
    if axis_mode == "cursor_center" then
      DrawCenterCursorMarker(y_min, plot_x, plot_y, plot_w, plot_h, start_t, end_t, center_t)
    end
    if params.show_marker_flags then
      DrawMarkerFlags(plot_x, plot_y, plot_w, start_t, end_t)
    elseif not params.render_early_skip then
      CollectVisibleMarkers(start_t, end_t, 96)
    end
    DrawLaneTag(plot_x + 6, lane_a_y + 6, "A", COLOR_MID_A)
    DrawLaneTag(plot_x + 6, lane_b_y + 6, "B", COLOR_MID_B)
    r.ImGui_DrawList_PopClipRect(dl)

    DrawAxisLabels(x_min, lane_a_y, plot_x, lane_a_y, plot_w, top_h, start_t, end_t, db_min_a, db_max_a, false, false, true)
    DrawAxisLabels(x_min, lane_b_y, plot_x, lane_b_y, plot_w, top_h, start_t, end_t, db_min_b, db_max_b, false, false, false)
    DrawTimeAxisLabels(y_min, plot_x, plot_w, plot_h, start_t, end_t)

    if #points_a == 0 and #points_b == 0 then
      r.ImGui_DrawList_AddText(dl, x_min + 16, y_min + 18, 0xFFD37AFF, "No measurement data. Select source tracks or run Analyze Offline.")
    end
    return
  else
    if params.show_target and params.source_a_target_enabled then
      DrawTargetLine(plot_x, plot_y, plot_w, plot_h, params.source_a_target_lufs, params.source_a_tolerance_lu, COLOR_TARGET_A, db_min, db_max, params.source_a_show_tolerance)
      if params.source_a_show_critical then
        DrawCriticalLines(plot_x, plot_y, plot_w, plot_h, params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, db_min, db_max)
      end
    end
    if params.show_target and params.source_b_target_enabled then
      DrawTargetLine(plot_x, plot_y, plot_w, plot_h, params.source_b_target_lufs, params.source_b_tolerance_lu, COLOR_TARGET_B, db_min, db_max, params.source_b_show_tolerance)
      if params.source_b_show_critical then
        DrawCriticalLines(plot_x, plot_y, plot_w, plot_h, params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, db_min, db_max)
      end
    end

    if params.source_a_show_mid then DrawCurve(points_a, "m", COLOR_MID_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_a, "m", start_t, end_t, "curve") end
    if params.source_b_show_mid then DrawCurve(points_b, "m", COLOR_MID_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_b, "m", start_t, end_t, "curve") end
    if params.source_a_show_side then DrawCurve(points_a, "st", COLOR_SIDE_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max, 2.8) else MaybePrepareGapLayer(points_a, "st", start_t, end_t, "curve") end
    if params.source_b_show_side then DrawCurve(points_b, "st", COLOR_SIDE_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max, 2.8) else MaybePrepareGapLayer(points_b, "st", start_t, end_t, "curve") end
    if params.source_a_show_integrated then DrawCurve(points_a, "i", COLOR_INT_A, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_a, "i", start_t, end_t, "curve") end
    if params.source_b_show_integrated then DrawCurve(points_b, "i", COLOR_INT_B, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max) else MaybePrepareGapLayer(points_b, "i", start_t, end_t, "curve") end

    if params.source_a_show_mid and params.source_b_show_mid then
      local delta = {}
      local n = math.min(#points_a, #points_b)
      for i = 1, n do
        delta[#delta + 1] = { t = points_a[i].t, m = (points_a[i].m or -120.0) - (points_b[i].m or -120.0) }
      end
      DrawCurve(delta, "m", COLOR_DELTA, plot_x, plot_y, plot_w, plot_h, start_t, end_t, -24.0, 24.0)
    end
  end

  if params.source_a_show_heatmap then
    DrawStatusRibbon(points_a, ribbon_field, params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, plot_x, plot_y, plot_w, plot_h, start_t, end_t, 1, 2)
  else
    MaybePrepareGapLayer(points_a, ribbon_field, start_t, end_t, "ribbon")
  end
  if params.source_b_show_heatmap then
    DrawStatusRibbon(points_b, ribbon_field, params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, plot_x, plot_y, plot_w, plot_h, start_t, end_t, 2, 2)
  else
    MaybePrepareGapLayer(points_b, ribbon_field, start_t, end_t, "ribbon")
  end

  r.ImGui_DrawList_PopClipRect(dl)

  if axis_mode == "cursor_center" then
    DrawCenterCursorMarker(y_min, plot_x, plot_y, plot_w, plot_h, start_t, end_t, center_t)
  end

  if params.show_marker_flags then
    DrawMarkerFlags(plot_x, plot_y, plot_w, start_t, end_t)
  elseif not params.render_early_skip then
    CollectVisibleMarkers(start_t, end_t, 96)
  end

  DrawAxisLabels(x_min, y_min, plot_x, plot_y, plot_w, plot_h, start_t, end_t, db_min, db_max, true)

  if #points_a == 0 and #points_b == 0 then
    r.ImGui_DrawList_AddText(dl, x_min + 16, y_min + 18, 0xFFD37AFF, "No measurement data. Select source tracks or run Analyze Offline.")
  end
end

local function GetReferenceTime()
  local playing = (r.GetPlayState() % 2) == 1
  if playing then
    return r.GetPlayPosition(), true
  end
  if r.GetCursorPositionEx then
    return r.GetCursorPositionEx(0), false
  end
  return r.GetCursorPosition(), false
end

UpdateSourceBindings = function()
  local tracks_a, label_a = ResolveSourceTracks(params.source_a_bind_idx, params.source_a_name)
  local tracks_b, label_b = ResolveSourceTracks(params.source_b_bind_idx, params.source_b_name)
  state.source_a.tracks = tracks_a
  state.source_b.tracks = tracks_b
  state.source_a.label = label_a
  state.source_b.label = label_b
end

local function FormatEtaTime(sec)
  local s = tonumber(sec)
  if not s or s <= 0.0 then return "--:--" end
  local total = math.floor(s + 0.5)
  local mm = math.floor(total / 60)
  local ss = total % 60
  return string.format("%02d:%02d", mm, ss)
end

local function FindMarkerPosByNameExact(name)
  local needle = tostring(name or "")
  if needle == "" then return nil end
  local total = r.CountProjectMarkers(0)
  for i = 0, total - 1 do
    local ok, retval, isrgn, pos, rgnend, nm = pcall(r.EnumProjectMarkers2, 0, i)
    if ok and retval and retval > 0 and (not isrgn) then
      if tostring(nm or "") == needle then
        return tonumber(pos)
      end
    end
  end
  return nil
end

local function ResolveOfflineRange()
  local mode = GetOfflineRangeOption().key
  local range_start = params.range_start
  local range_end = params.range_end
  local source_label = "Whole Project"
  local note = ""

  if mode == "time_selection" then
    local ts_ok, ts_start, ts_end = pcall(function()
      return r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    end)
    if ts_ok and ts_start and ts_end and ts_end > ts_start then
      range_start = ts_start
      range_end = ts_end
      source_label = "Time Selection"
    else
      range_start = 0.0
      range_end = math.max(1.0, r.GetProjectLength(0) or 1.0)
      source_label = "Whole Project"
      note = "Time selection empty -> fallback to whole project"
    end
  elseif mode == "markers_start_end" then
    local m_start = FindMarkerPosByNameExact(state.offline_dry_marker_start)
    local m_end = FindMarkerPosByNameExact(state.offline_dry_marker_end)
    if m_start and m_end and m_end > m_start then
      range_start = m_start
      range_end = m_end
      source_label = "Markers"
    else
      range_start = 0.0
      range_end = math.max(1.0, r.GetProjectLength(0) or 1.0)
      source_label = "Whole Project"
      note = "Markers not found/invalid -> fallback to whole project"
    end
  else
    range_start = 0.0
    range_end = math.max(1.0, r.GetProjectLength(0) or 1.0)
    source_label = "Whole Project"
  end

  range_start = math.max(0.0, tonumber(range_start) or 0.0)
  range_end = math.max(range_start + 0.001, tonumber(range_end) or range_start + 0.001)
  return range_start, range_end, source_label, note
end

local function ResolveOfflineTracksForSource(source_key, resolved_tracks)
  local src_key = tostring(source_key or "A")
  local bind_idx = (src_key == "B") and params.source_b_bind_idx or params.source_a_bind_idx
  local bind = GetBindOption(bind_idx)
  local tracks = resolved_tracks or {}
  local note = ""

  local function expand_folder_children(src_tracks)
    local total = r.CountTracks(0)
    if total <= 0 then return src_tracks, 0 end

    local out = {}
    local seen = {}
    local added = 0

    for i = 1, #src_tracks do
      local tr = src_tracks[i]
      if tr and (not seen[tr]) then
        out[#out + 1] = tr
        seen[tr] = true
      end
    end

    for i = 1, #src_tracks do
      local root = src_tracks[i]
      if root then
        local depth = tonumber(r.GetMediaTrackInfo_Value(root, "I_FOLDERDEPTH")) or 0
        if depth > 0 then
          local idx = math.floor((tonumber(r.GetMediaTrackInfo_Value(root, "IP_TRACKNUMBER")) or 1) - 1)
          local remain = depth
          for t_idx = idx + 1, total - 1 do
            local tr = r.GetTrack(0, t_idx)
            if not tr then break end
            if not seen[tr] then
              out[#out + 1] = tr
              seen[tr] = true
              added = added + 1
            end
            local d = tonumber(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")) or 0
            remain = remain + d
            if remain <= 0 then break end
          end
        end
      end
    end

    return out, added
  end

  if bind and bind.key == "master" then
    local mix_tracks = GetAllTracksList()
    if #mix_tracks > 0 then
      tracks = mix_tracks
      note = "master binding offline -> project mix (all tracks)"
    end
  else
    local expanded, added = expand_folder_children(tracks)
    tracks = expanded
    if added > 0 then
      note = string.format("offline folder expansion: +%d child tracks", added)
    end
  end

  return tracks, note
end

local function MaxFieldValue(points, field)
  if not points or #points == 0 then return -120.0 end
  local mx = -120.0
  for i = 1, #points do
    local v = tonumber(points[i][field])
    if v and v > mx then mx = v end
  end
  return mx
end

local function GetSourceAnalysisSettings(source_label)
  local is_b = tostring(source_label or "A") == "B"
  local pref = is_b and "source_b_" or "source_a_"

  local hop = Clamp(tonumber(params[pref .. "hop_sec"]) or 0.1, 0.02, 0.5)
  local mom = Clamp(tonumber(params[pref .. "momentary_window_sec"]) or 0.4, 0.2, 6.0)
  local short = Clamp(tonumber(params[pref .. "short_window_sec"]) or 3.0, 1.0, 30.0)
  if short < mom then short = mom end

  return {
    hop_sec = hop,
    momentary_sec = mom,
    short_sec = short
  }
end

local function BuildOfflineDryRunPlan()
  UpdateSourceBindings()
  local range_start, range_end, range_source, range_note = ResolveOfflineRange()
  local duration = math.max(0.001, range_end - range_start)
  local cfg_a = GetSourceAnalysisSettings("A")
  local cfg_b = GetSourceAnalysisSettings("B")
  local hop_sec = math.min(cfg_a.hop_sec, cfg_b.hop_sec)

  local tracks_a_base = state.source_a.tracks or {}
  local tracks_b_base = state.source_b.tracks or {}
  local tracks_a, note_a = ResolveOfflineTracksForSource("A", tracks_a_base)
  local tracks_b, note_b = ResolveOfflineTracksForSource("B", tracks_b_base)
  local can_a = (#tracks_a > 0)
  local can_b = (#tracks_b > 0)
  local run_a_default = params.source_a_enabled and can_a
  local run_b_default = params.source_b_enabled and can_b

  local hops = math.max(1, math.ceil(duration / hop_sec))
  local load = 0
  if run_a_default then load = load + math.max(1, #tracks_a) end
  if run_b_default then load = load + math.max(1, #tracks_b) end
  local est_sec = math.max(1.0, duration * math.max(0.04, load * 0.025))

  OfflineDebug(string.format("DryRun: range %.2f..%.2f (%s) | A tracks=%d (%s) | B tracks=%d (%s)", range_start, range_end, tostring(range_source or "n/a"), #tracks_a, tostring(state.source_a.label or "A"), #tracks_b, tostring(state.source_b.label or "B")))
  if note_a ~= "" then OfflineDebug("DryRun A note: " .. note_a) end
  if note_b ~= "" then OfflineDebug("DryRun B note: " .. note_b) end
  if tostring(range_note or "") ~= "" then
    OfflineDebug("DryRun note: " .. tostring(range_note))
  end

  return {
    range_start = range_start,
    range_end = range_end,
    duration = duration,
    hop_sec = hop_sec,
    hops = hops,
    tracks_a = #tracks_a,
    tracks_b = #tracks_b,
    label_a = tostring(state.source_a.label or "A"),
    label_b = tostring(state.source_b.label or "B"),
    note_a = note_a,
    note_b = note_b,
    offline_tracks_a = tracks_a,
    offline_tracks_b = tracks_b,
    can_a = can_a,
    can_b = can_b,
    run_a_default = run_a_default,
    run_b_default = run_b_default,
    range_source = range_source,
    range_note = range_note,
    est_sec = est_sec
  }
end

local function InitOfflineSourceJob(source_label, tracks, range_start, range_end)
  local cfg = GetSourceAnalysisSettings(source_label)
  local hop_sec = cfg.hop_sec
  local mom_hops = math.max(1, math.floor((cfg.momentary_sec / hop_sec) + 0.5))
  local short_hops = math.max(mom_hops, math.floor((cfg.short_sec / hop_sec) + 0.5))

  local src = {
    label = source_label,
    tracks = tracks or {},
    range_start = range_start,
    range_end = range_end,
    t = math.max(0.0, range_start),
    t_stop = math.max(math.max(0.0, range_start), range_end),
    sr = 48000,
    hop_sec = hop_sec,
    hop_samples = math.max(1, math.floor(48000 * hop_sec + 0.5)),
    mom_hops = mom_hops,
    short_hops = short_hops,
    points = {},
    done = false,
    failed = false,
    reason = ""
  }

  if #src.tracks == 0 then
    src.done = true
    src.reason = "No tracks"
    OfflineDebug(string.format("Init %s: no tracks", source_label))
    return src
  end

  src.accessors = CreateTrackAccessors(src.tracks)
  if not src.accessors or #src.accessors == 0 then
    src.done = true
    src.failed = true
    src.reason = "No audio accessors"
    OfflineDebug(string.format("Init %s: no accessors for %d tracks", source_label, #src.tracks))
    return src
  end
  local max_ch = 0
  for i = 1, #src.accessors do
    max_ch = math.max(max_ch, tonumber(src.accessors[i].channels) or 0)
  end
  OfflineDebug(string.format("Init %s: tracks=%d accessors=%d max_ch=%d range %.2f..%.2f | hop=%.2fs M=%.2fs S=%.2fs", source_label, #src.tracks, #src.accessors, max_ch, src.range_start or 0.0, src.range_end or 0.0, src.hop_sec or 0.1, (src.mom_hops or 1) * (src.hop_sec or 0.1), (src.short_hops or 1) * (src.hop_sec or 0.1)))

  src.k_l = NewKWeightState()
  src.k_r = NewKWeightState()
  src.mom_q, src.short_q, src.side_q, src.peak_q = {}, {}, {}, {}
  src.mom_sum = 0.0
  src.short_sum = 0.0
  src.side_sum = 0.0
  src.abs_gate = LufsToEnergy(-70.0)
  src.abs_sum = 0.0
  src.abs_count = 0
  return src
end

local function DestroyOfflineSourceJob(src)
  if not src then return end
  if src.accessors then
    DestroyTrackAccessors(src.accessors)
    src.accessors = nil
  end
end

local function ProcessOfflineSourceChunk(src)
  if not src or src.done then return end
  if src.t >= src.t_stop then
    src.done = true
    DestroyOfflineSourceJob(src)
    return
  end

  local remain = src.t_stop - src.t
  local chunk_samples = math.max(1, math.min(src.hop_samples, math.floor(remain * src.sr + 0.5)))
  local chunk_sec = chunk_samples / src.sr
  if chunk_samples <= 0 or chunk_sec <= 0 then
    src.done = true
    DestroyOfflineSourceJob(src)
    return
  end

  local mix_l = {}
  local mix_r = {}
  for i = 1, chunk_samples do
    mix_l[i] = 0.0
    mix_r[i] = 0.0
  end

  for i = 1, #src.accessors do
    local a = src.accessors[i]
    if src.t <= a.end_t and (src.t + chunk_sec) >= a.start_t then
      if (not a.buffer) or a.buffer_n < chunk_samples then
        a.buffer = r.new_array(chunk_samples * a.channels)
        a.buffer_n = chunk_samples
      end
      local rc = r.GetAudioAccessorSamples(a.acc, src.sr, a.channels, src.t, chunk_samples, a.buffer)
      if rc == 1 then
        local idx = 1
        local gain = a.trim_vol or 1.0
        for s = 1, chunk_samples do
          local l, rv = DownmixAccessorFrameToLR(a.buffer, idx, a.channels, gain)
          idx = idx + a.channels
          mix_l[s] = mix_l[s] + l
          mix_r[s] = mix_r[s] + rv
        end
      end
    end
  end

  local hop_sq = 0.0
  local hop_side_sq = 0.0
  local hop_peak = 0.0
  for s = 1, chunk_samples do
    local l = mix_l[s]
    local rv = mix_r[s]
    local kl = KWeightSample(src.k_l, l)
    local kr = KWeightSample(src.k_r, rv)
    hop_sq = hop_sq + (kl * kl + kr * kr)
    local side = 0.5 * (l - rv)
    hop_side_sq = hop_side_sq + side * side
    local abs_l = math.abs(l)
    local abs_r = math.abs(rv)
    if abs_l > hop_peak then hop_peak = abs_l end
    if abs_r > hop_peak then hop_peak = abs_r end
  end

  local hop_energy = hop_sq / math.max(1, chunk_samples)
  local hop_side = AmpToDb(math.sqrt(hop_side_sq / math.max(1, chunk_samples)))

  src.mom_q[#src.mom_q + 1] = hop_energy
  src.mom_sum = src.mom_sum + hop_energy
  if #src.mom_q > src.mom_hops then
    src.mom_sum = src.mom_sum - table.remove(src.mom_q, 1)
  end

  src.short_q[#src.short_q + 1] = hop_energy
  src.short_sum = src.short_sum + hop_energy
  if #src.short_q > src.short_hops then
    src.short_sum = src.short_sum - table.remove(src.short_q, 1)
  end

  src.side_q[#src.side_q + 1] = hop_side
  src.side_sum = src.side_sum + hop_side
  if #src.side_q > src.mom_hops then
    src.side_sum = src.side_sum - table.remove(src.side_q, 1)
  end

  src.peak_q[#src.peak_q + 1] = hop_peak
  if #src.peak_q > src.mom_hops then table.remove(src.peak_q, 1) end

  if #src.mom_q >= src.mom_hops then
    local m_energy = src.mom_sum / src.mom_hops
    local st_energy = src.short_sum / math.max(1, #src.short_q)
    local m_db = EnergyToLufs(m_energy)
    local st_db = EnergyToLufs(st_energy)
    local side_db = src.side_sum / math.max(1, #src.side_q)

    local peak_lin = 0.0
    for i = 1, #src.peak_q do
      if src.peak_q[i] > peak_lin then peak_lin = src.peak_q[i] end
    end

    if m_energy >= src.abs_gate then
      src.abs_sum = src.abs_sum + m_energy
      src.abs_count = src.abs_count + 1
    end
    local i_db = (src.abs_count > 0) and EnergyToLufs(src.abs_sum / src.abs_count) or -120.0

    src.points[#src.points + 1] = {
      t = src.t + chunk_sec,
      m = m_db,
      s = side_db,
      st = st_db,
      i = i_db,
      peak = AmpToDb(peak_lin),
      gated = (m_db < -70.0),
      lin_energy = m_energy,
      m_energy = m_energy
    }
  end

  src.t = src.t + chunk_sec
  src.steps = (src.steps or 0) + 1
  if src.t >= src.t_stop then
    src.done = true
    OfflineDebug(string.format("Done %s: steps=%d points=%d", tostring(src.label or "?"), tonumber(src.steps or 0), #src.points))
    DestroyOfflineSourceJob(src)
  end
end

local function ComputeOfflineProgress(job)
  local dur = math.max(0.001, (job.range_end or 0.0) - (job.range_start or 0.0))
  local total = 0.0
  local done = 0.0

  local function add_source(enabled, src)
    if not enabled then return end
    total = total + dur
    if not src then
      done = done + dur
      return
    end
    if src.done then
      done = done + dur
      return
    end
    local cur = math.max(job.range_start or 0.0, math.min(src.t or (job.range_start or 0.0), job.range_end or 0.0))
    done = done + math.max(0.0, cur - (job.range_start or 0.0))
  end

  add_source(job.run_a, job.a)
  add_source(job.run_b, job.b)
  if total <= 0.0 then return 1.0 end
  return Clamp(done / total, 0.0, 1.0)
end

local function FinalizeOfflineJob(job)
  if not job then return end
  DestroyOfflineSourceJob(job.a)
  DestroyOfflineSourceJob(job.b)

  if job.run_a then
    state.source_a.points = job.a and (job.a.points or {}) or {}
    state.source_a.summary = BuildSummary(state.source_a.points, params.gate_db)
  end
  if job.run_b then
    state.source_b.points = job.b and (job.b.points or {}) or {}
    state.source_b.summary = BuildSummary(state.source_b.points, params.gate_db)
  end

  params.range_start = job.range_start
  params.range_end = job.range_end
  params.mode_idx = 2
  state.offline_last_run = r.time_precise()
  params.offline_status = "Ready"

  local a_pts = job.run_a and #(state.source_a.points or {}) or #(state.source_a.points or {})
  local b_pts = job.run_b and #(state.source_b.points or {}) or #(state.source_b.points or {})
  state.backend_note = string.format("Offline complete: A %d pts | B %d pts", a_pts, b_pts)
  OfflineDebug(string.format("Finalize: A=%d pts B=%d pts", a_pts, b_pts))
  local a_max_m = MaxFieldValue(state.source_a.points, "m")
  local b_max_m = MaxFieldValue(state.source_b.points, "m")
  OfflineDebug(string.format("Finalize signal: A max M=%.1f LUFS | B max M=%.1f LUFS", a_max_m, b_max_m))
  if (job.run_a and a_max_m <= -119.9) or (job.run_b and b_max_m <= -119.9) then
    state.backend_note = state.backend_note .. " | Warning: no audible signal in selected offline range"
  end
  if (job.run_a and a_pts <= 0) or (job.run_b and b_pts <= 0) then
    OfflineDebug("Finalize warning: zero-point result on one or more enabled sources (check bindings/range/audio accessors)")
  end

  state.offline_job = nil
end

local function CancelOfflineJob()
  local job = state.offline_job
  if not job then return end
  DestroyOfflineSourceJob(job.a)
  DestroyOfflineSourceJob(job.b)
  state.offline_job = nil
  params.offline_status = "Cancelled"
  state.backend_note = "Offline analysis cancelled"
  OfflineDebug("Job cancelled")
end

local function StartOfflineAnalysisJob(run_a, run_b)
  if state.offline_job then
    params.offline_status = "Offline already running..."
    return
  end

  local plan = state.offline_dry_plan or BuildOfflineDryRunPlan()
  local do_a = (run_a == true) and plan.can_a
  local do_b = (run_b == true) and plan.can_b

  if (not do_a) and (not do_b) then
    params.offline_status = "Dry Run: choose A/B source with valid tracks"
    OfflineDebug("Start denied: neither source is valid")
    return
  end

  local job = {
    started_at = r.time_precise(),
    range_start = plan.range_start,
    range_end = plan.range_end,
    run_a = do_a,
    run_b = do_b,
    a = do_a and InitOfflineSourceJob("A", plan.offline_tracks_a or state.source_a.tracks, plan.range_start, plan.range_end) or nil,
    b = do_b and InitOfflineSourceJob("B", plan.offline_tracks_b or state.source_b.tracks, plan.range_start, plan.range_end) or nil,
    cancel_requested = false
  }

  state.offline_job = job
  state.offline_progress_popup_request = true
  state.offline_progress_popup_open = true
  params.offline_status = "Starting offline analysis..."
  state.backend_note = "Offline analysis running (Audio Accessor, no FX insert)"
  OfflineDebug(string.format("Start: runA=%s runB=%s range %.2f..%.2f | path=AudioAccessor(no FX insert)", tostring(do_a), tostring(do_b), plan.range_start or 0.0, plan.range_end or 0.0))
end

local function ProcessOfflineJobTick()
  local job = state.offline_job
  if not job then return end

  if job.cancel_requested then
    CancelOfflineJob()
    return
  end

  local t_end = r.time_precise() + 0.010
  while r.time_precise() < t_end do
    local advanced = false

    if job.run_a and job.a and not job.a.done then
      ProcessOfflineSourceChunk(job.a)
      advanced = true
    elseif job.run_b and job.b and not job.b.done then
      ProcessOfflineSourceChunk(job.b)
      advanced = true
    end

    if (not advanced) then
      break
    end
  end

  local pct = ComputeOfflineProgress(job)
  local elapsed = math.max(0.0, r.time_precise() - (job.started_at or r.time_precise()))
  local eta = (pct > 0.001) and (elapsed * (1.0 - pct) / pct) or -1
  params.offline_status = string.format("Analyzing... %d%% | ETA %s", math.floor(pct * 100 + 0.5), FormatEtaTime(eta))
  if params.offline_debug_enabled then
    local now = r.time_precise()
    if (not job.last_log_t) or (now - job.last_log_t) >= 1.0 then
      job.last_log_t = now
      OfflineDebug(string.format("Tick: %d%% A=%d B=%d", math.floor(pct * 100 + 0.5), job.a and #(job.a.points or {}) or 0, job.b and #(job.b.points or {}) or 0))
    end
  end

  local done_a = (not job.run_a) or (job.a and job.a.done)
  local done_b = (not job.run_b) or (job.b and job.b.done)
  if done_a and done_b then
    FinalizeOfflineJob(job)
  end
end

local function RunOfflineAnalysis()
  if state.offline_job then
    params.offline_status = "Offline already running..."
    return
  end

  local ok, err = pcall(function()
    local plan = BuildOfflineDryRunPlan()
    state.offline_dry_plan = plan
    state.offline_dry_run_a = plan.run_a_default
    state.offline_dry_run_b = plan.run_b_default
    state.offline_dry_popup_request = true
    OfflineDebug("DryRun popup opened")
  end)

  if not ok then
    params.offline_status = "Error"
    LogError("Offline dry run failed: " .. tostring(err))
  end
end

local function ClearGeneratedAlerts()
  if not state.alert_ids then
    state.alert_ids = {}
    return
  end
  for i = #state.alert_ids, 1, -1 do
    local item = state.alert_ids[i]
    if item and item.id then
      pcall(r.DeleteProjectMarker, 0, item.id, item.isrgn and true or false)
    end
  end
  state.alert_ids = {}
end

local function ClearAlertsByPrefix(prefix)
  local pfx = tostring(prefix or "")
  if pfx == "" then return 0 end

  local deleted = 0
  local total = r.CountProjectMarkers(0)
  for i = total - 1, 0, -1 do
    local ok, retval, isrgn, pos, rgnend, name, id = pcall(r.EnumProjectMarkers2, 0, i)
    if ok and retval and retval > 0 then
      local txt = tostring(name or "")
      if txt:sub(1, #pfx) == pfx then
        if r.DeleteProjectMarker(0, id, isrgn and true or false) then
          deleted = deleted + 1
        end
      end
    end
  end
  state.alert_ids = {}
  return deleted
end

local function ResolveAlertLaneIndex()
  if not params.alert_use_lane then return -1 end
  if not (r.APIExists and r.APIExists("GetSetProjectInfo")) then return -1 end

  local lane_name = tostring(params.alert_lane_name or "Loudness Alert")
  if lane_name == "" then lane_name = "Loudness Alert" end

  local lane_count = math.floor((r.GetSetProjectInfo(0, "RULER_LANE_COUNT", 0, false) or 0) + 0.5)
  if lane_count < 1 then
    local ok_make, new_count = pcall(r.GetSetProjectInfo, 0, "RULER_LANE_COUNT", 1, true)
    if ok_make then
      lane_count = math.floor((new_count or 1) + 0.5)
      if lane_count < 1 then lane_count = 1 end
    end
  end
  if lane_count < 1 then return -1 end

  local manual = math.floor((params.alert_lane_index or -1) + 0.5)
  if manual >= 0 and manual < lane_count then
    if r.GetSetProjectInfo_String then
      local desc = "RULER_LANE_NAME:" .. tostring(manual)
      pcall(r.GetSetProjectInfo_String, 0, desc, lane_name, true)
    end
    params.alert_lane_index = manual
    return manual
  end

  local found = -1
  if r.GetSetProjectInfo_String then
    for i = 0, lane_count - 1 do
      local desc = "RULER_LANE_NAME:" .. tostring(i)
      local ok, _, nm = pcall(r.GetSetProjectInfo_String, 0, desc, "", false)
      if ok and tostring(nm or "") == lane_name then
        found = i
        break
      end
    end
  end

  if found >= 0 then
    params.alert_lane_index = found
    return found
  end

  -- Create a new lane at the end and name it, without renaming existing lanes.
  local ok_grow, new_count = pcall(r.GetSetProjectInfo, 0, "RULER_LANE_COUNT", lane_count + 1, true)
  if ok_grow then
    local created_idx = lane_count
    local normalized_count = math.floor((new_count or (lane_count + 1)) + 0.5)
    if normalized_count > 0 then
      created_idx = math.max(0, math.min(created_idx, normalized_count - 1))
    end
    if r.GetSetProjectInfo_String then
      local desc = "RULER_LANE_NAME:" .. tostring(created_idx)
      pcall(r.GetSetProjectInfo_String, 0, desc, lane_name, true)
    end
    params.alert_lane_index = created_idx
    return created_idx
  end

  return -1
end

local function PlaceRegionOrMarkerLaneByIndex(mark_idx, is_region, lane_idx)
  if lane_idx < 0 then return false end
  if not (r.APIExists and r.APIExists("SetRegionOrMarkerInfo_Value") and r.APIExists("GetRegionOrMarker")) then
    return false
  end

  local marker_obj = nil
  if r.APIExists("GetNumRegionsOrMarkers") and r.APIExists("GetRegionOrMarkerInfo_Value") then
    local total = math.floor((r.GetNumRegionsOrMarkers(0) or 0) + 0.5)
    for i = 0, math.max(0, total - 1) do
      local ok_obj, obj = pcall(r.GetRegionOrMarker, 0, i, "")
      if ok_obj and obj then
        local idnum = math.floor((r.GetRegionOrMarkerInfo_Value(0, obj, "I_NUMBER") or -999999) + 0.5)
        local isrgn = (r.GetRegionOrMarkerInfo_Value(0, obj, "B_ISREGION") or 0) >= 0.5
        if idnum == mark_idx and isrgn == (is_region and true or false) then
          marker_obj = obj
          break
        end
      end
    end
  end

  if not marker_obj then return false end
  local ok_set = pcall(r.SetRegionOrMarkerInfo_Value, 0, marker_obj, "I_LANENUMBER", lane_idx)
  return ok_set and true or false
end

local function BuildLoudnessStatus(m_val, target_lufs, tol_lu, crit_up_lu, crit_down_lu)
  local v = tonumber(m_val)
  if not v then return "normal", 0 end

  local target = tonumber(target_lufs) or -23.0
  local tol = math.max(0.05, tonumber(tol_lu) or 1.0)
  local crit_up = math.max(0.1, tonumber(crit_up_lu) or 8.0)
  local crit_dn = math.max(0.1, tonumber(crit_down_lu) or 8.0)

  if v < (target - crit_dn) then return "too quiet", 2 end
  if v > (target + crit_up) then return "too loud", 2 end
  if v < (target - tol) then return "quiet", 1 end
  if v > (target + tol) then return "loud", 1 end
  return "normal", 0
end

local function GetAlertFieldKeyForSource(source_key)
  local idx = 1
  if source_key == "a" or source_key == "A" then
    idx = Clamp(math.floor((params.source_a_alert_field_idx or 1) + 0.5), 1, #ALERT_FIELD_OPTIONS)
  else
    idx = Clamp(math.floor((params.source_b_alert_field_idx or 1) + 0.5), 1, #ALERT_FIELD_OPTIONS)
  end
  return ALERT_FIELD_OPTIONS[idx].key
end

local function GetSourcePointAtTime(source_key, t)
  if source_key == "a" then
    return FindClosestPoint(state.source_a.points or {}, t), params.source_a_target_lufs, params.source_a_tolerance_lu, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, "A", GetAlertFieldKeyForSource("a")
  end
  return FindClosestPoint(state.source_b.points or {}, t), params.source_b_target_lufs, params.source_b_tolerance_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu, "B", GetAlertFieldKeyForSource("b")
end

local function BuildSmartAlertLabelAtTime(pos)
  local source_mode = GetAlertSourceOption().key
  local prefix = tostring(params.alert_prefix or "Loudness Alert")
  if prefix == "" then prefix = "Loudness Alert" end

  local entries = {}
  local function lift_hint(current_lufs, target_lufs)
    local cur = tonumber(current_lufs)
    local tgt = tonumber(target_lufs)
    if not cur or not tgt then return "" end
    local delta = tgt - cur
    if delta > 0.1 then
      return string.format("raise +%.1f dB", delta)
    end
    if delta < -0.1 then
      return string.format("reduce %.1f dB", delta)
    end
    return "on target"
  end

  local function add_entry(src_key)
    local p, target, tol, cup, cdn, src_label, field_key = GetSourcePointAtTime(src_key, pos)
    local meter = (field_key == "st") and "S" or "M"
    local m_val = p and p[field_key] or nil
    local status, rank = BuildLoudnessStatus(m_val, target, tol, cup, cdn)
    entries[#entries + 1] = { source = src_label, status = status, rank = rank, m = m_val, target = target, meter = meter }
  end

  if source_mode == "a" then
    add_entry("a")
  elseif source_mode == "b" then
    add_entry("b")
  else
    add_entry("a")
    add_entry("b")
  end

  if not params.alert_smart_naming then
    return prefix
  end

  if #entries == 1 then
    local e = entries[1]
    local base = string.format("%s %s", prefix, e.status)
    if params.alert_include_lufs and e.m then
      base = string.format("%s (%s %.1f LUFS)", base, e.meter or "M", e.m)
    end
    if params.alert_help then
      local hint = lift_hint(e.m, e.target)
      if hint ~= "" then
        base = string.format("%s [%s]", base, hint)
      end
    end
    return base
  end

  local e1 = entries[1]
  local e2 = entries[2]
  local base = string.format("%s A:%s | B:%s", prefix, e1.status, e2.status)
  if params.alert_include_lufs and e1.m and e2.m then
    base = string.format("%s (A %s %.1f | B %s %.1f LUFS)", base, e1.meter or "M", e1.m, e2.meter or "M", e2.m)
  end
  if params.alert_help then
    local h1 = lift_hint(e1.m, e1.target)
    local h2 = lift_hint(e2.m, e2.target)
    if h1 ~= "" and h2 ~= "" then
      base = string.format("%s [A %s | B %s]", base, h1, h2)
    end
  end
  return base
end

local function BuildSegmentAlertLabel(prefix, source_label, seg, meter_label)
  local pfx = tostring(prefix or "Loudness Alert")
  if pfx == "" then pfx = "Loudness Alert" end
  local seg_status = ((seg and seg.polarity) == "LOW") and "too quiet" or "too loud"
  local function lift_hint(current_lufs, target_lufs)
    local cur = tonumber(current_lufs)
    local tgt = tonumber(target_lufs)
    if not cur or not tgt then return "" end
    local delta = tgt - cur
    if delta > 0.1 then
      return string.format("raise +%.1f dB", delta)
    end
    if delta < -0.1 then
      return string.format("reduce %.1f dB", delta)
    end
    return "on target"
  end

  local target = (tostring(source_label or "A") == "B") and (params.source_b_target_lufs or -23.0) or (params.source_a_target_lufs or -23.0)

  if not params.alert_smart_naming then
    local dur = math.max(0.0, ((seg and seg.t1) or (seg and seg.t0) or 0.0) - ((seg and seg.t0) or 0.0))
    return string.format("%s %s %s(%s) +%.1fLU (%.2fs)", pfx, source_label or "A", tostring((seg and seg.polarity) or "OUT"), tostring(meter_label or "M"), tonumber((seg and seg.max_excess) or 0.0), dur)
  end

  local base = string.format("%s %s %s", pfx, source_label or "A", seg_status)
  if params.alert_include_lufs and seg and seg.v_peak then
    base = string.format("%s (%s %.1f LUFS)", base, meter_label or "M", seg.v_peak)
  end
  if params.alert_help then
    local hint = lift_hint(seg and seg.v_peak or nil, target)
    if hint ~= "" then
      base = string.format("%s [%s]", base, hint)
    end
  end
  return base
end

CreateAlertMarkerAtTime = function(t)
  local pos = math.max(0.0, tonumber(t) or 0.0)
  local txt = BuildSmartAlertLabelAtTime(pos)
  local marker_color = ToNativeColor(params.alert_color_high)
  local lane_idx = ResolveAlertLaneIndex()
  local id = -1
  local last_err = nil
  if r.AddProjectMarker2 then
    local ok2a, id2a = pcall(r.AddProjectMarker2, nil, false, pos, 0.0, txt, -1, marker_color)
    if ok2a and id2a and id2a >= 0 then
      id = id2a
    else
      local ok2b, id2b = pcall(r.AddProjectMarker2, 0, false, pos, 0.0, txt, -1, marker_color)
      if ok2b and id2b and id2b >= 0 then
        id = id2b
      else
        if not ok2a then last_err = id2a end
        if not ok2b then last_err = id2b end
      end
    end
  end
  if (not id or id < 0) and r.AddProjectMarker then
    local ok1a, id1a = pcall(r.AddProjectMarker, nil, false, pos, 0.0, txt, -1)
    if ok1a and id1a and id1a >= 0 then
      id = id1a
    else
      local ok1b, id1b = pcall(r.AddProjectMarker, 0, false, pos, 0.0, txt, -1)
      if ok1b and id1b and id1b >= 0 then
        id = id1b
      else
        if not ok1a then last_err = id1a end
        if not ok1b then last_err = id1b end
      end
    end
  end
  if id and id >= 0 then
    PlaceRegionOrMarkerLaneByIndex(id, false, lane_idx)
    if r.UpdateArrange then r.UpdateArrange() end
    local mm = math.floor(pos / 60)
    local ss = math.floor(pos % 60)
    state.backend_note = string.format("Alert marker created at %02d:%02d", mm, ss)
    return true
  end
  state.backend_note = "Alert marker create failed"
  if last_err then
    LogError("Alert marker create failed: " .. tostring(last_err))
  else
    LogError("Alert marker create failed: API returned invalid marker id")
  end
  return false
end

local function CollectCriticalSegments(points, field_key, target_lufs, crit_up_lu, crit_down_lu, min_dur_sec, merge_gap_sec)
  local out = {}
  if not points or #points == 0 then return out end

  local min_dur = math.max(0.01, min_dur_sec or 0.6)
  local merge_gap = math.max(0.0, merge_gap_sec or 0.25)
  local up_lim = target_lufs + math.max(0.1, crit_up_lu or 8.0)
  local dn_lim = target_lufs - math.max(0.1, crit_down_lu or 8.0)

  local seg = nil
  for i = 1, #points do
    local p = points[i]
    local t = p.t
    local v = p[field_key]
    if t and v then
      local over = v - up_lim
      local under = dn_lim - v
      local bad = (over > 0.0) or (under > 0.0)
      local polarity = (over > 0.0) and "HIGH" or "LOW"
      local excess = math.max(over, under, 0.0)

      if bad then
        if not seg then
          seg = { t0 = t, t1 = t, polarity = polarity, max_excess = excess, v_peak = v }
        elseif (t - seg.t1) <= merge_gap then
          seg.t1 = t
          if excess > seg.max_excess then
            seg.max_excess = excess
            seg.v_peak = v
          end
        else
          if (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
          seg = { t0 = t, t1 = t, polarity = polarity, max_excess = excess, v_peak = v }
        end
      elseif seg and (t - seg.t1) > merge_gap then
        if (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
        seg = nil
      end
    end
  end

  if seg and (seg.t1 - seg.t0) >= min_dur then
    out[#out + 1] = seg
  end

  return out
end

local function PassesAlertCooldown(source_key, alert_kind, t)
  local cooldown = math.max(0.0, tonumber(params.alert_cooldown_sec) or 0.0)
  if cooldown <= 0.0 then return true end
  if not state.alert_cooldown_last then state.alert_cooldown_last = {} end

  local ts = math.max(0.0, tonumber(t) or 0.0)
  local key = tostring(source_key or "?") .. "|" .. tostring(alert_kind or "generic")
  local prev = tonumber(state.alert_cooldown_last[key])
  if prev and (ts - prev) < cooldown then
    return false
  end
  state.alert_cooldown_last[key] = ts
  return true
end

local function CreateAlertsForSource(source_key, label, points, target_lufs, crit_up_lu, crit_down_lu)
  local created = 0
  local field_key = GetAlertFieldKeyForSource(source_key)
  local meter_label = (field_key == "st") and "S" or "M"
  local segs = CollectCriticalSegments(points, field_key, target_lufs, crit_up_lu, crit_down_lu, params.alert_min_duration_sec, params.alert_merge_gap_sec)
  local mode_key = GetAlertModeOption().key
  local prefix = tostring(params.alert_prefix or "Loudness Alert")
  if prefix == "" then prefix = "Loudness Alert" end
  local lane_idx = ResolveAlertLaneIndex()

  for i = 1, #segs do
    local s = segs[i]
    if PassesAlertCooldown(source_key, "critical", s.t0) then
      local txt = BuildSegmentAlertLabel(prefix, label, s, meter_label)
      local alert_color = ((s.polarity or "") == "LOW") and ToNativeColor(params.alert_color_low) or ToNativeColor(params.alert_color_high)

      if mode_key == "markers" or mode_key == "both" then
        local id = r.AddProjectMarker2(0, false, s.t0, 0.0, txt, -1, alert_color)
        if id and id >= 0 then
          state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = false }
          PlaceRegionOrMarkerLaneByIndex(id, false, lane_idx)
          created = created + 1
        end
      end

      if mode_key == "regions" or mode_key == "both" then
        local rgn_end = math.max((s.t1 or s.t0) + 0.001, s.t0 + 0.001)
        local id = r.AddProjectMarker2(0, true, s.t0, rgn_end, txt, -1, alert_color)
        if id and id >= 0 then
          state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = true }
          PlaceRegionOrMarkerLaneByIndex(id, true, lane_idx)
          created = created + 1
        end
      end
    end
  end

  return created, #segs
end

local function CreateLRAAlertForSource(source_key, label, points, summary, limit_lu)
  if not params.alert_lra_enabled then return 0, 0 end
  if not summary or summary.lra == nil then return 0, 0 end

  local lra_val = tonumber(summary.lra) or 0.0
  local lra_lim = math.max(0.5, tonumber(limit_lu) or 8.0)
  if lra_val <= lra_lim then return 0, 0 end

  local pos = nil
  if points and #points > 0 then
    pos = points[#points].t
  end
  if not pos then
    pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition()
  end
  pos = math.max(0.0, tonumber(pos) or 0.0)
  if not PassesAlertCooldown(source_key, "lra", pos) then return 0, 0 end

  local mode_key = GetAlertModeOption().key
  local prefix = tostring(params.alert_lra_prefix or "")
  if prefix == "" then prefix = tostring(params.alert_prefix or "Loudness Alert") end
  if prefix == "" then prefix = "Loudness Alert" end
  local lane_idx = ResolveAlertLaneIndex()
  local exceed = lra_val - lra_lim

  local txt = string.format("%s %s LRA high", prefix, tostring(label or "A"))
  if not params.alert_smart_naming then
    txt = string.format("%s %s LRA HIGH +%.1fLU", prefix, tostring(label or "A"), exceed)
  else
    if params.alert_include_lufs then
      txt = string.format("%s (LRA %.1f LU)", txt, lra_val)
    end
    if params.alert_help then
      txt = string.format("%s [reduce dynamics %.1f LU]", txt, exceed)
    end
  end

  local alert_color = ToNativeColor(params.alert_color_high)
  local created = 0
  if mode_key == "markers" or mode_key == "both" then
    local id = r.AddProjectMarker2(0, false, pos, 0.0, txt, -1, alert_color)
    if id and id >= 0 then
      state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = false }
      PlaceRegionOrMarkerLaneByIndex(id, false, lane_idx)
      created = created + 1
    end
  end

  if mode_key == "regions" or mode_key == "both" then
    local rgn_end = pos + 0.001
    local id = r.AddProjectMarker2(0, true, pos, rgn_end, txt, -1, alert_color)
    if id and id >= 0 then
      state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = true }
      PlaceRegionOrMarkerLaneByIndex(id, true, lane_idx)
      created = created + 1
    end
  end

  return created, 1
end

local function CreateTPAlertForSource(source_key, label, points, summary, limit_dbtp)
  if not params.alert_tp_enabled then return 0, 0 end
  if not summary or summary.peak == nil then return 0, 0 end

  local tp_val = tonumber(summary.peak) or -120.0
  local tp_lim = tonumber(limit_dbtp) or -1.0
  if tp_val <= tp_lim then return 0, 0 end

  local pos = nil
  if points and #points > 0 then
    pos = points[#points].t
  end
  if not pos then
    pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition()
  end
  pos = math.max(0.0, tonumber(pos) or 0.0)
  if not PassesAlertCooldown(source_key, "tp", pos) then return 0, 0 end

  local mode_key = GetAlertModeOption().key
  local prefix = tostring(params.alert_tp_prefix or "")
  if prefix == "" then prefix = tostring(params.alert_prefix or "Loudness Alert") end
  if prefix == "" then prefix = "Loudness Alert" end
  local lane_idx = ResolveAlertLaneIndex()
  local exceed = tp_val - tp_lim

  local txt = string.format("%s %s TP high", prefix, tostring(label or "A"))
  if not params.alert_smart_naming then
    txt = string.format("%s %s TP HIGH +%.1f dBTP", prefix, tostring(label or "A"), exceed)
  else
    if params.alert_include_lufs then
      txt = string.format("%s (TP %.1f dBTP)", txt, tp_val)
    end
    if params.alert_help then
      txt = string.format("%s [reduce peak %.1f dB]", txt, exceed)
    end
  end

  local alert_color = ToNativeColor(params.alert_color_high)
  local created = 0
  if mode_key == "markers" or mode_key == "both" then
    local id = r.AddProjectMarker2(0, false, pos, 0.0, txt, -1, alert_color)
    if id and id >= 0 then
      state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = false }
      PlaceRegionOrMarkerLaneByIndex(id, false, lane_idx)
      created = created + 1
    end
  end

  if mode_key == "regions" or mode_key == "both" then
    local rgn_end = pos + 0.001
    local id = r.AddProjectMarker2(0, true, pos, rgn_end, txt, -1, alert_color)
    if id and id >= 0 then
      state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = true }
      PlaceRegionOrMarkerLaneByIndex(id, true, lane_idx)
      created = created + 1
    end
  end

  return created, 1
end

local function CreateDeviationAlerts()
  local ok, err = pcall(function()
    if params.alert_clear_prev then
      ClearGeneratedAlerts()
    end

    local source_key = GetAlertSourceOption().key
    local created_total = 0
    local seg_total = 0
    local lra_total = 0
    local tp_total = 0

    if source_key == "a" or source_key == "both" then
      local c, s = CreateAlertsForSource("a", "A", state.source_a.points, params.source_a_target_lufs, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu)
      created_total = created_total + c
      seg_total = seg_total + s
      local lc, ls = CreateLRAAlertForSource("a", "A", state.source_a.points, state.source_a.summary, params.source_a_lra_limit_lu)
      created_total = created_total + lc
      lra_total = lra_total + ls
      local tc, ts = CreateTPAlertForSource("a", "A", state.source_a.points, state.source_a.summary, params.source_a_tp_limit_dbtp)
      created_total = created_total + tc
      tp_total = tp_total + ts
    end
    if source_key == "b" or source_key == "both" then
      local c, s = CreateAlertsForSource("b", "B", state.source_b.points, params.source_b_target_lufs, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu)
      created_total = created_total + c
      seg_total = seg_total + s
      local lc, ls = CreateLRAAlertForSource("b", "B", state.source_b.points, state.source_b.summary, params.source_b_lra_limit_lu)
      created_total = created_total + lc
      lra_total = lra_total + ls
      local tc, ts = CreateTPAlertForSource("b", "B", state.source_b.points, state.source_b.summary, params.source_b_tp_limit_dbtp)
      created_total = created_total + tc
      tp_total = tp_total + ts
    end

    state.backend_note = string.format("Alerts: created %d items from %d critical segments + %d LRA events + %d TP events", created_total, seg_total, lra_total, tp_total)
  end)

  if not ok then
    LogError("Create alerts failed: " .. tostring(err))
  end
end

local function ClearDeviationAlertsByPrefix()
  local ok, err = pcall(function()
    local prefix = tostring(params.alert_prefix or "")
    local lra_prefix = tostring(params.alert_lra_prefix or "")
    local tp_prefix = tostring(params.alert_tp_prefix or "")
    if prefix == "" and lra_prefix == "" and tp_prefix == "" then
      state.backend_note = "Alerts: prefix is empty, nothing to clear"
      return
    end

    local deleted = 0
    local seen = {}
    local function clear_once(p)
      local key = tostring(p or "")
      if key == "" or seen[key] then return end
      seen[key] = true
      deleted = deleted + ClearAlertsByPrefix(key)
    end

    clear_once(prefix)
    clear_once(lra_prefix)
    clear_once(tp_prefix)

    if deleted > 0 then
      state.backend_note = string.format("Alerts: cleared %d items by configured prefixes", deleted)
    else
      state.backend_note = "Alerts: no items found for configured prefixes"
    end
  end)
  if not ok then
    LogError("Clear alerts by prefix failed: " .. tostring(err))
  end
end

local function RunLiveTick()
  local ok, err = pcall(function()
    if not params.enabled then return end
    if params.measurement_locked then return end

    local now = r.time_precise()
    local hop_sec = 0.1
    if (now - last_live_update) < hop_sec then return end
    last_live_update = now

    local play_pos, is_playing = GetReferenceTime()

    if not is_playing and last_live_play_pos ~= nil and math.abs(play_pos - last_live_play_pos) > 0.01 then
      state.pending_rewrite_pos = play_pos
    end

    if is_playing and state.pending_rewrite_pos ~= nil then
      local rewrite_pos = state.pending_rewrite_pos
      state.pending_rewrite_pos = nil
      state.source_a.points = TrimPointsPreCursorBuffer(state.source_a.points, rewrite_pos, 0.0)
      state.source_b.points = TrimPointsPreCursorBuffer(state.source_b.points, rewrite_pos, 0.0)
      state.source_a.summary = BuildSummary(state.source_a.points, params.gate_db)
      state.source_b.summary = BuildSummary(state.source_b.points, params.gate_db)
    end

    if state.live_hold then
      if state.live_hold_ref == nil then
        state.live_hold_ref = play_pos
      end
      local moved = false
      if is_playing then
        moved = true
      elseif math.abs(play_pos - (state.live_hold_ref or play_pos)) > 0.01 then
        moved = true
      end
      if moved then
        state.live_hold = false
        state.live_hold_ref = nil
      else
        last_live_play_pos = play_pos
        return
      end
    end

    if (not is_playing) and last_live_play_pos ~= nil and math.abs(play_pos - last_live_play_pos) < 0.0005 then
      return
    end

    UpdateSourceBindings()

    if is_playing and last_live_play_pos ~= nil and play_pos < (last_live_play_pos - 0.01) then
      -- On backward seek, keep only stable history and drop rewrite zone.
      state.source_a.points = TrimPointsPreCursorBuffer(state.source_a.points, play_pos, 0.0)
      state.source_b.points = TrimPointsPreCursorBuffer(state.source_b.points, play_pos, 0.0)
      state.source_a.summary = BuildSummary(state.source_a.points, params.gate_db)
      state.source_b.summary = BuildSummary(state.source_b.points, params.gate_db)
    end
    last_live_play_pos = play_pos
    state.backend_note = ""

    local function append_live(source_state, enabled, source_label)
      if (not enabled) or #source_state.tracks == 0 then
        source_state.points = {}
        source_state.summary = nil
        return
      end

      local track = source_state.tracks[1]
      if #source_state.tracks > 1 then
        state.backend_note = "Live meter: for " .. source_label .. " selected first track only"
      end

      local bind_idx = (source_label == "A") and params.source_a_bind_idx or params.source_b_bind_idx
      local bind_key = GetBindOption(bind_idx).key
      local source_name = (source_label == "A") and tostring(params.source_a_name or "") or tostring(params.source_b_name or "")
      local allow_autoinsert = (bind_key ~= "track_name") or (source_name:gsub("^%s+", ""):gsub("%s+$", "") ~= "")
      local point, p_err = ReadBridgePoint(track, allow_autoinsert)
      if not point then
        if p_err and p_err ~= "" then
          state.backend_note = source_label .. ": " .. p_err
        end
        return
      end

      if is_playing then
        source_state.points = ReplacePointsNearTime(source_state.points, play_pos, hop_sec * 0.6)
      end
      source_state.points[#source_state.points + 1] = {
        t = play_pos,
        m = point.m,
        s = point.s,
        st = point.st,
        i = point.i,
        i_src = point.i_src,
        peak = point.peak,
        gated = point.gated,
        lin_energy = point.lin_energy,
        m_energy = point.m_energy
      }

      if is_playing then
        source_state.points = TrimLivePoints(source_state.points, play_pos, params.history_sec)
      end
      source_state.summary = BuildSummary(source_state.points, params.gate_db)
    end

    append_live(state.source_a, params.source_a_enabled, "A")
    append_live(state.source_b, params.source_b_enabled, "B")

    params.range_start = math.max(0.0, play_pos - params.history_sec)
    params.range_end = play_pos
  end)

  if not ok then
    LogError("Live tick failed: " .. tostring(err))
  end
end

local function PushTheme()
  local btn = 0x2F3339FF
  local btn_h = 0x3B414AFF
  local btn_a = 0x4A525DFF
  local fr = 0x202020FF
  local fr_h = 0x232323FF
  local fr_a = 0x262626FF
  local grab = 0x55D6BEFF
  local grab_a = 0x70E7D0FF
  if params.theme_preset == 1 then
    fr = 0x202020FF
    fr_h = 0x232323FF
    fr_a = 0x262626FF
    btn = 0x2C6D57FF
    btn_h = 0x38886CFF
    btn_a = 0x45A181FF
    grab = 0x52D6A9FF
    grab_a = 0x72E5BFFF
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLOR_BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLOR_PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_TEXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_h)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_a)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), fr)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), fr_h)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), fr_a)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), grab)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), grab_a)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLOR_MID_A)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
end

local function PopTheme()
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, 12)
end

local function DrawSourceControls(source_key, enabled_key, bind_key, name_key)
  local source_name = (source_key == "A") and "Source A" or "Source B"
  local source_state = (source_key == "A") and state.source_a or state.source_b

  r.ImGui_PushID(ctx, "src_" .. source_key)
  local enabled_changed, enabled_new = r.ImGui_Checkbox(ctx, "Enable##enable", params[enabled_key])
  if enabled_changed then params[enabled_key] = enabled_new end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, source_name .. ": " .. tostring(source_state.label or "N/A"))

  local bind_opt, bind_idx = GetBindOption(params[bind_key])
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "Binding##binding", bind_opt.label) then
    for i, entry in ipairs(BIND_OPTIONS) do
      local is_sel = (bind_idx == i)
      if r.ImGui_Selectable(ctx, entry.label .. "##bind_item_" .. tostring(i), is_sel) then
        params[bind_key] = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SetNextItemWidth(ctx, -1)
  local name_changed, name_new = r.ImGui_InputText(ctx, "Name##name", params[name_key] or "")
  if name_changed then params[name_key] = name_new end

  r.ImGui_PopID(ctx)
end

local function DrawSourceViewConfig(prefix)
  local is_a = prefix == "A"
  local profile_key = is_a and "source_a_profile_idx" or "source_b_profile_idx"
  local show_mid_key = is_a and "source_a_show_mid" or "source_b_show_mid"
  local show_side_key = is_a and "source_a_show_side" or "source_b_show_side"
  local show_i_key = is_a and "source_a_show_integrated" or "source_b_show_integrated"
  local target_en_key = is_a and "source_a_target_enabled" or "source_b_target_enabled"
  local target_key = is_a and "source_a_target_lufs" or "source_b_target_lufs"
  local tol_key = is_a and "source_a_tolerance_lu" or "source_b_tolerance_lu"
  local lra_lim_key = is_a and "source_a_lra_limit_lu" or "source_b_lra_limit_lu"
  local tp_lim_key = is_a and "source_a_tp_limit_dbtp" or "source_b_tp_limit_dbtp"
  local alert_field_key = is_a and "source_a_alert_field_idx" or "source_b_alert_field_idx"
  local mom_win_key = is_a and "source_a_momentary_window_sec" or "source_b_momentary_window_sec"
  local short_win_key = is_a and "source_a_short_window_sec" or "source_b_short_window_sec"
  local hop_key = is_a and "source_a_hop_sec" or "source_b_hop_sec"
  local heat_key = is_a and "source_a_show_heatmap" or "source_b_show_heatmap"
  local crit_key = is_a and "source_a_show_critical" or "source_b_show_critical"
  local tol_vis_key = is_a and "source_a_show_tolerance" or "source_b_show_tolerance"
  local crit_up_key = is_a and "source_a_critical_upper_lu" or "source_b_critical_upper_lu"
  local crit_dn_key = is_a and "source_a_critical_lower_lu" or "source_b_critical_lower_lu"
  local profile, profile_idx = GetProfileOptionByIndex(params[profile_key])
  params[profile_key] = profile_idx
  local alert_field_opt, alert_field_idx = GetAlertFieldOptionByIndex(params[alert_field_key])
  params[alert_field_key] = alert_field_idx

  if params.render_early_skip then
    params[show_mid_key] = false
    params[show_side_key] = false
    params[show_i_key] = false
  end

  local lock_layers = params.render_early_skip == true and r.ImGui_BeginDisabled ~= nil

  r.ImGui_TextColored(ctx, COLOR_DIM, "Graph " .. prefix .. " View")
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "Standard##src_profile_" .. prefix, profile and profile.label or "Custom") then
    for i, entry in ipairs(PROFILE_OPTIONS) do
      local is_sel = (params[profile_key] == i)
      if r.ImGui_Selectable(ctx, entry.label .. "##src_profile_item_" .. prefix .. "_" .. tostring(i), is_sel) then
        ApplyProfileToSource(prefix, i)
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_TextColored(ctx, COLOR_DIM, BuildProfileSignature(profile))
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, BuildProfileTooltip(profile))
  end

  if lock_layers then r.ImGui_BeginDisabled(ctx, true) end
  local c1, v1 = r.ImGui_Checkbox(ctx, "M##src_mid_" .. prefix, params[show_mid_key])
  if c1 then params[show_mid_key] = v1 end
  r.ImGui_SameLine(ctx)
  local c2, v2 = r.ImGui_Checkbox(ctx, "S##src_side_" .. prefix, params[show_side_key])
  if c2 then params[show_side_key] = v2 end
  r.ImGui_SameLine(ctx)
  local c3, v3 = r.ImGui_Checkbox(ctx, "I##src_i_" .. prefix, params[show_i_key])
  if c3 then params[show_i_key] = v3 end
  if params.render_early_skip then
    params[show_mid_key] = false
    params[show_side_key] = false
    params[show_i_key] = false
  end
  if lock_layers then r.ImGui_EndDisabled(ctx) end
  if params.render_early_skip then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, COLOR_DIM, "(M/S/I locked by Render Early Skip)")
  end

  local c4, v4 = r.ImGui_Checkbox(ctx, "Target##src_target_" .. prefix, params[target_en_key])
  if c4 then params[target_en_key] = v4 end
  r.ImGui_SameLine(ctx)
  local c5, v5 = r.ImGui_Checkbox(ctx, "Ribbon##src_heat_" .. prefix, params[heat_key])
  if c5 then params[heat_key] = v5 end
  r.ImGui_SameLine(ctx)
  local c6, v6 = r.ImGui_Checkbox(ctx, "Critical##src_crit_" .. prefix, params[crit_key])
  if c6 then params[crit_key] = v6 end
  r.ImGui_SameLine(ctx)
  local c7, v7 = r.ImGui_Checkbox(ctx, "Tol##src_tol_vis_" .. prefix, params[tol_vis_key])
  if c7 then params[tol_vis_key] = v7 end

  local t_ch, t_new = r.ImGui_SliderDouble(ctx, "Target LUFS##src_target_lufs_" .. prefix, params[target_key], -40.0, -6.0, "%.1f")
  if t_ch then params[target_key] = t_new end
  local tol_ch, tol_new = r.ImGui_SliderDouble(ctx, "Tolerance##src_target_tol_" .. prefix, params[tol_key], 0.2, 5.0, "%.1f LU")
  if tol_ch then params[tol_key] = tol_new end

  local cup_ch, cup_new = r.ImGui_SliderDouble(ctx, "Critical Up +LU##src_crit_up_" .. prefix, params[crit_up_key], 1.0, 20.0, "%.1f")
  if cup_ch then params[crit_up_key] = cup_new end
  local cdn_ch, cdn_new = r.ImGui_SliderDouble(ctx, "Critical Down +LU##src_crit_dn_" .. prefix, params[crit_dn_key], 1.0, 20.0, "%.1f")
  if cdn_ch then params[crit_dn_key] = cdn_new end

  local crit_up_abs = params[target_key] + params[crit_up_key]
  local crit_dn_abs = params[target_key] - params[crit_dn_key]
  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Critical LUFS: up %.1f | down %.1f", crit_up_abs, crit_dn_abs))

  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "Alert Field##src_alert_field_" .. prefix, alert_field_opt.label) then
    for i, entry in ipairs(ALERT_FIELD_OPTIONS) do
      local is_sel = (params[alert_field_key] == i)
      if r.ImGui_Selectable(ctx, entry.label .. "##src_alert_field_item_" .. prefix .. "_" .. tostring(i), is_sel) then
        params[alert_field_key] = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Deviation segments are built from the selected metric for this source.\nM = momentary (~0.4s): catches fast peaks/dips.\nS = short window (3s or 10s): smoother, better for dialogue/broadcast style criteria.\nChoose according to your delivery standard specification.")
  end

  local lra_ch, lra_new = r.ImGui_SliderDouble(ctx, "LRA max##src_lra_max_" .. prefix, params[lra_lim_key], 1.0, 24.0, "%.1f LU")
  if lra_ch then params[lra_lim_key] = lra_new end
  local tp_ch, tp_new = r.ImGui_SliderDouble(ctx, "TP max##src_tp_max_" .. prefix, params[tp_lim_key], -6.0, 0.0, "%.1f dBTP")
  if tp_ch then params[tp_lim_key] = tp_new end

  params[mom_win_key] = Clamp(tonumber(params[mom_win_key]) or 0.4, 0.2, 6.0)
  params[short_win_key] = Clamp(tonumber(params[short_win_key]) or 3.0, 1.0, 30.0)
  params[hop_key] = Clamp(tonumber(params[hop_key]) or 0.1, 0.02, 0.5)

  local mw_ch, mw_new = r.ImGui_SliderDouble(ctx, "Momentary Window##src_m_win_" .. prefix, params[mom_win_key], 0.2, 6.0, "%.2f s")
  if mw_ch then
    params[mom_win_key] = Clamp(mw_new, 0.2, 6.0)
    if params[short_win_key] < params[mom_win_key] then
      params[short_win_key] = params[mom_win_key]
    end
  end
  local sw_ch, sw_new = r.ImGui_SliderDouble(ctx, "Short Window##src_s_win_" .. prefix, params[short_win_key], 1.0, 30.0, "%.1f s")
  if sw_ch then
    params[short_win_key] = Clamp(sw_new, params[mom_win_key], 30.0)
  end
  local hp_ch, hp_new = r.ImGui_SliderDouble(ctx, "Hop##src_hop_sec_" .. prefix, params[hop_key], 0.02, 0.5, "%.2f s")
  if hp_ch then params[hop_key] = Clamp(hp_new, 0.02, 0.5) end

  r.ImGui_TextColored(ctx, COLOR_DIM, "Curve Colors " .. prefix)
  if is_a then
    local ch_m_a, col_m_a = r.ImGui_ColorEdit4(ctx, "M##src_col_mid_" .. prefix, params.col_mid_a)
    if ch_m_a then params.col_mid_a = EnsureOpaqueColor(col_m_a, params.col_mid_a) end
    local ch_s_a, col_s_a = r.ImGui_ColorEdit4(ctx, "S##src_col_side_" .. prefix, params.col_side_a)
    if ch_s_a then params.col_side_a = EnsureOpaqueColor(col_s_a, params.col_side_a) end
    local ch_i_a, col_i_a = r.ImGui_ColorEdit4(ctx, "I##src_col_int_" .. prefix, params.col_int_a)
    if ch_i_a then params.col_int_a = EnsureOpaqueColor(col_i_a, params.col_int_a) end
  else
    local ch_m_b, col_m_b = r.ImGui_ColorEdit4(ctx, "M##src_col_mid_" .. prefix, params.col_mid_b)
    if ch_m_b then params.col_mid_b = EnsureOpaqueColor(col_m_b, params.col_mid_b) end
    local ch_s_b, col_s_b = r.ImGui_ColorEdit4(ctx, "S##src_col_side_" .. prefix, params.col_side_b)
    if ch_s_b then params.col_side_b = EnsureOpaqueColor(col_s_b, params.col_side_b) end
    local ch_i_b, col_i_b = r.ImGui_ColorEdit4(ctx, "I##src_col_int_" .. prefix, params.col_int_b)
    if ch_i_b then params.col_int_b = EnsureOpaqueColor(col_i_b, params.col_int_b) end
  end
end

FindClosestPoint = function(points, target_t)
  if #points == 0 then return nil end
  local nearest = points[1]
  local best_dt = math.abs((nearest.t or target_t) - target_t)
  for i = 2, #points do
    local point = points[i]
    local dt = math.abs((point.t or target_t) - target_t)
    if dt < best_dt then
      nearest = point
      best_dt = dt
    end
  end
  return nearest
end

local function DrawControlPanel()
  local function BeginInlineCombo(label, id, preview, total_w)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    r.ImGui_SameLine(ctx)
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local combo_w = math.max(84, (total_w or 160) - label_w - 10)
    r.ImGui_SetNextItemWidth(ctx, combo_w)
    return r.ImGui_BeginCombo(ctx, "##" .. id, preview)
  end

  local function BeginInlineInputText(label, id, value, total_w)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    r.ImGui_SameLine(ctx)
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local input_w = math.max(84, (total_w or 160) - label_w - 10)
    r.ImGui_SetNextItemWidth(ctx, input_w)
    return r.ImGui_InputText(ctx, "##" .. id, value)
  end

  local function InlineSliderDouble(label, id, value, lo, hi, fmt, total_w)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    r.ImGui_SameLine(ctx)
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local slider_w = math.max(84, (total_w or 160) - label_w - 10)
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    return r.ImGui_SliderDouble(ctx, "##" .. id, value, lo, hi, fmt)
  end

  local function InlineInputInt(label, id, value, total_w)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    r.ImGui_SameLine(ctx)
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local input_w = math.max(84, (total_w or 160) - label_w - 10)
    r.ImGui_SetNextItemWidth(ctx, input_w)
    return r.ImGui_InputInt(ctx, "##" .. id, value)
  end

  local function Tip(text)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, text)
    end
  end

  local mode_opt = GetModeOption()
  local quick_preset_opt = GetQuickPresetOption()
  local alert_mode_opt = GetAlertModeOption()
  local alert_source_opt = GetAlertSourceOption()
  local ribbon_field_opt = GetRibbonFieldOption()
  local time_axis_opt = GetTimeAxisOption()
  local view_opt = GetViewOption()

  r.ImGui_TextColored(ctx, COLOR_TEXT, "Controls")

  local panel_w = r.ImGui_GetContentRegionAvail(ctx)
  local pair_w = math.max(120, (panel_w - 8) * 0.5)

  if BeginInlineCombo("Mode", "mode_main", mode_opt.label, pair_w) then
    for i, entry in ipairs(MODE_OPTIONS) do
      local is_sel = params.mode_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##mode_item_" .. tostring(i), is_sel) then
        params.mode_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx)
  if BeginInlineCombo("Quick Preset", "quick_preset_main", quick_preset_opt.label, pair_w) then
    for i, entry in ipairs(QUICK_PRESET_OPTIONS) do
      local is_sel = params.quick_preset_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##quick_preset_item_" .. tostring(i), is_sel) then
        ApplyQuickPreset(i)
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  if BeginInlineCombo("View", "view_main", view_opt.label, pair_w) then
    for i, entry in ipairs(VIEW_OPTIONS) do
      local is_sel = params.view_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##view_item_" .. tostring(i), is_sel) then
        params.view_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx)
  if BeginInlineCombo("Time Scale", "time_scale_main", time_axis_opt.label, pair_w) then
    for i, entry in ipairs(TIME_AXIS_OPTIONS) do
      local is_sel = params.time_axis_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##time_scale_item_" .. tostring(i), is_sel) then
        params.time_axis_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  local theme_labels = {
    "Studio",
    "High Contrast",
    "Warm",
    "Ocean Glass",
    "Slate Mint",
    "Blue Scope",
    "Rose Night"
  }
  if BeginInlineCombo("Theme", "theme_preset_combo", theme_labels[params.theme_preset] or "Studio", pair_w) then
    for i = 1, #theme_labels do
      local sel = (params.theme_preset == i)
      if r.ImGui_Selectable(ctx, theme_labels[i] .. "##theme_item_" .. i, sel) then
        ApplyThemePreset(i)
      end
      if sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  local row_w = r.ImGui_GetContentRegionAvail(ctx)
  local button_w = math.max(68, (row_w - 12) / 3)
  local offline_running = (state.offline_job ~= nil)
  if offline_running and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Analyze Offline##run_offline", button_w, 0) then
    RunOfflineAnalysis()
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear Graph##clear_graph", button_w, 0) then
    local ref_pos = GetReferenceTime()
    ClearGraphHistory(ref_pos)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Rebind##rebind", button_w, 0) then
    UpdateSourceBindings()
  end
  if offline_running and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

  if state.offline_dry_popup_request then
    r.ImGui_OpenPopup(ctx, "Offline Dry Run##offline_dry_modal")
    state.offline_dry_popup_request = false
  end

  if r.ImGui_BeginPopupModal(ctx, "Offline Dry Run##offline_dry_modal") then
    local plan = state.offline_dry_plan
    if not plan then
      r.ImGui_TextColored(ctx, COLOR_DIM, "Dry run data unavailable.")
    else
      local recalc_plan = false
      local range_opt = GetOfflineRangeOption()
      local prog_opt = GetOfflineProgramChannelOption()

      r.ImGui_TextColored(ctx, COLOR_TEXT, "Offline analysis pre-check")
      if BeginInlineCombo("Range", "offline_range_src", range_opt.label, pair_w) then
        for i, entry in ipairs(OFFLINE_RANGE_OPTIONS) do
          local is_sel = state.offline_dry_range_idx == i
          if r.ImGui_Selectable(ctx, entry.label .. "##offline_range_item_" .. tostring(i), is_sel) then
            state.offline_dry_range_idx = i
            recalc_plan = true
          end
          if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end

      if range_opt.key == "markers_start_end" then
        local ms_ch, ms_new = BeginInlineInputText("Start Marker", "offline_marker_start", tostring(state.offline_dry_marker_start or "=START"), pair_w)
        if ms_ch then
          state.offline_dry_marker_start = tostring(ms_new or "")
          recalc_plan = true
        end
        r.ImGui_SameLine(ctx)
        local me_ch, me_new = BeginInlineInputText("End Marker", "offline_marker_end", tostring(state.offline_dry_marker_end or "=END"), pair_w)
        if me_ch then
          state.offline_dry_marker_end = tostring(me_new or "")
          recalc_plan = true
        end
      end

      if BeginInlineCombo("Program Channels", "offline_program_channels", prog_opt.label, pair_w) then
        for i, entry in ipairs(OFFLINE_PROGRAM_CHANNEL_OPTIONS) do
          local is_sel = params.offline_program_channels_idx == i
          if r.ImGui_Selectable(ctx, entry.label .. "##offline_progch_item_" .. tostring(i), is_sel) then
            params.offline_program_channels_idx = i
            recalc_plan = true
          end
          if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end

      if recalc_plan then
        plan = BuildOfflineDryRunPlan()
        state.offline_dry_plan = plan
      end

      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Range: %s - %s (%.1fs)", FormatTimeMMSS(plan.range_start), FormatTimeMMSS(plan.range_end), plan.duration))
      r.ImGui_TextColored(ctx, COLOR_DIM, "Range source: " .. tostring(plan.range_source or "n/a"))
      if tostring(plan.range_note or "") ~= "" then
        r.ImGui_TextColored(ctx, 0xFFD6A368, tostring(plan.range_note))
      end
      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Expected hops: %d | ETA ~ %s", plan.hops, FormatEtaTime(plan.est_sec)))
      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("A: %s | B: %s", tostring(plan.label_a or "A"), tostring(plan.label_b or "B")))
      r.ImGui_TextColored(ctx, COLOR_DIM, "Program channels mode: " .. tostring(GetOfflineProgramChannelOption().label))
      if tostring(plan.note_a or "") ~= "" then
        r.ImGui_TextColored(ctx, COLOR_DIM, "A note: " .. tostring(plan.note_a))
      end
      if tostring(plan.note_b or "") ~= "" then
        r.ImGui_TextColored(ctx, COLOR_DIM, "B note: " .. tostring(plan.note_b))
      end
      r.ImGui_TextColored(ctx, COLOR_DIM, "Offline path: Audio Accessor (analyzer FX is not inserted on tracks)")

      local a_lbl = string.format("Run Source A (%d tracks)##offline_dry_a", plan.tracks_a)
      local b_lbl = string.format("Run Source B (%d tracks)##offline_dry_b", plan.tracks_b)

      if (not plan.can_a) and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
      local dra_ch, dra_new = r.ImGui_Checkbox(ctx, a_lbl, state.offline_dry_run_a)
      if dra_ch then state.offline_dry_run_a = dra_new end
      if (not plan.can_a) and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

      if (not plan.can_b) and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
      local drb_ch, drb_new = r.ImGui_Checkbox(ctx, b_lbl, state.offline_dry_run_b)
      if drb_ch then state.offline_dry_run_b = drb_new end
      if (not plan.can_b) and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

      if not plan.can_a and not plan.can_b then
        r.ImGui_TextColored(ctx, 0xFF7777FF, "No valid tracks resolved for A/B. Rebind source first.")
      end

      local odb_ch, odb_new = r.ImGui_Checkbox(ctx, "Offline Debug (console)##offline_debug_enabled", params.offline_debug_enabled)
      if odb_ch then params.offline_debug_enabled = odb_new end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Print dry-run, init, tick and finalize details to ReaScript console")
      end

      local can_start = (state.offline_dry_run_a and plan.can_a) or (state.offline_dry_run_b and plan.can_b)
      if (not can_start) and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
      if r.ImGui_Button(ctx, "Start Offline##offline_dry_start", 160, 0) then
        StartOfflineAnalysisJob(state.offline_dry_run_a, state.offline_dry_run_b)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      if (not can_start) and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel##offline_dry_cancel", 120, 0) then
        params.offline_status = "Idle"
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  if state.offline_progress_popup_request then
    r.ImGui_OpenPopup(ctx, "Offline Render Status##offline_progress_modal")
    state.offline_progress_popup_request = false
  end

  if state.offline_progress_popup_open and r.ImGui_BeginPopupModal(ctx, "Offline Render Status##offline_progress_modal") then
    local job = state.offline_job
    if job then
      local pct = ComputeOfflineProgress(job)
      local elapsed = math.max(0.0, r.time_precise() - (job.started_at or r.time_precise()))
      local eta = (pct > 0.001) and (elapsed * (1.0 - pct) / pct) or -1
      local dur = math.max(0.001, (job.range_end or 0.0) - (job.range_start or 0.0))
      local active = "Done"
      if job.run_a and job.a and not job.a.done then
        active = "Source A"
      elseif job.run_b and job.b and not job.b.done then
        active = "Source B"
      end

      r.ImGui_TextColored(ctx, COLOR_TEXT, string.format("Progress: %d%%", math.floor(pct * 100 + 0.5)))
      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Range: %s - %s (%.1fs)", FormatTimeMMSS(job.range_start), FormatTimeMMSS(job.range_end), dur))
      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Active: %s | ETA %s", active, FormatEtaTime(eta)))
      r.ImGui_TextColored(ctx, COLOR_DIM, string.format("A points: %d | B points: %d", job.a and #(job.a.points or {}) or 0, job.b and #(job.b.points or {}) or 0))

      if r.ImGui_Button(ctx, "Cancel Render##offline_progress_cancel", 160, 0) then
        job.cancel_requested = true
      end
    else
      r.ImGui_TextColored(ctx, COLOR_DIM, "Offline job is not running.")
      if r.ImGui_Button(ctx, "Close##offline_progress_close", 120, 0) then
        state.offline_progress_popup_open = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  local lock_label = params.measurement_locked and "Unlock Measure##toggle_measure_lock" or "Lock Measure##toggle_measure_lock"
  if r.ImGui_Button(ctx, lock_label, -1, 0) then
    params.measurement_locked = not params.measurement_locked
    state.backend_note = params.measurement_locked and "Measurement locked: new data acquisition paused" or "Measurement unlocked"
  end

  r.ImGui_Separator(ctx)

  if r.ImGui_BeginTable(ctx, "SrcCompactTable##src_tbl", 2, r.ImGui_TableFlags_SizingStretchSame(), -1, 0) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableSetColumnIndex(ctx, 0)
    DrawSourceControls("A", "source_a_enabled", "source_a_bind_idx", "source_a_name")
    r.ImGui_TableSetColumnIndex(ctx, 1)
    DrawSourceControls("B", "source_b_enabled", "source_b_bind_idx", "source_b_name")
    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Separator(ctx)

  if r.ImGui_BeginTable(ctx, "SrcViewTable##src_view_tbl", 2, r.ImGui_TableFlags_SizingStretchSame(), -1, 0) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableSetColumnIndex(ctx, 0)
    DrawSourceViewConfig("A")
    r.ImGui_TableSetColumnIndex(ctx, 1)
    DrawSourceViewConfig("B")
    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, "Fill Settings")
  local obf_ch, obf_new = r.ImGui_Checkbox(ctx, "B Fill Overlay##overlay_b_fill", params.overlay_b_fill)
  if obf_ch then params.overlay_b_fill = obf_new end
  if params.overlay_b_fill then
    local alpha_label_w = r.ImGui_CalcTextSize(ctx, "Alpha")
    local alpha_slider_w = math.max(84, math.min(128, pair_w - alpha_label_w - 16))
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "Alpha")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, alpha_slider_w)
    local fa_ch, fa_new = r.ImGui_SliderDouble(ctx, "##fill_alpha_inline", params.overlay_fill_alpha, 0.05, 0.85, "%.2f")
    if fa_ch then params.overlay_fill_alpha = fa_new end
  end

  if params.overlay_b_fill then
    local fill_source_labels = { "A", "B" }
    if BeginInlineCombo("Fill Source", "fill_source", fill_source_labels[Clamp(params.overlay_fill_source_idx, 1, 2)] or "B", pair_w) then
      for i = 1, #fill_source_labels do
        local sel = (params.overlay_fill_source_idx == i)
        if r.ImGui_Selectable(ctx, fill_source_labels[i] .. "##fill_source_item_" .. i, sel) then
          params.overlay_fill_source_idx = i
        end
        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end

    local fill_curve_labels = { "Momentary", "Short", "Integrated" }
    r.ImGui_SameLine(ctx)
    if BeginInlineCombo("Fill Curve", "fill_curve", fill_curve_labels[Clamp(params.overlay_fill_field_idx, 1, 3)] or "Momentary", pair_w) then
      for i = 1, #fill_curve_labels do
        local sel = (params.overlay_fill_field_idx == i)
        if r.ImGui_Selectable(ctx, fill_curve_labels[i] .. "##fill_curve_item_" .. i, sel) then
          params.overlay_fill_field_idx = i
        end
        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
  end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, "Ribbon Settings")
  if BeginInlineCombo("Ribbon Field", "ribbon_field", ribbon_field_opt.label, pair_w) then
    for i, entry in ipairs(RIBBON_FIELD_OPTIONS) do
      local is_sel = params.ribbon_field_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##ribbon_field_item_" .. tostring(i), is_sel) then
        params.ribbon_field_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, "Global Graph Controls")
  local sg_ch, sg_new = r.ImGui_Checkbox(ctx, "Grid##show_grid", params.show_grid)
  if sg_ch then params.show_grid = sg_new end
  Tip("Show/hide background grid lines")
  r.ImGui_SameLine(ctx)
  local st_ch, st_new = r.ImGui_Checkbox(ctx, "Target##show_target", params.show_target)
  if st_ch then params.show_target = st_new end
  Tip("Show/hide target and tolerance guides")
  r.ImGui_SameLine(ctx)
  local yz_ch, yz_new = r.ImGui_Checkbox(ctx, "Top=0 LUFS##y_top_zero", params.y_top_zero)
  if yz_ch then params.y_top_zero = yz_new end
  Tip("Clamp graph top at 0 LUFS")
  r.ImGui_SameLine(ctx)
  local smf_ch, smf_new = r.ImGui_Checkbox(ctx, "Markers##show_marker_flags", params.show_marker_flags)
  if smf_ch then params.show_marker_flags = smf_new end
  Tip("Show marker flags at top of graph")
  if params.show_marker_flags then
    r.ImGui_SameLine(ctx)
    local smt_ch, smt_new = r.ImGui_Checkbox(ctx, "Marker Text##show_marker_flag_text", params.show_marker_flag_text)
    if smt_ch then params.show_marker_flag_text = smt_new end
    Tip("Show marker text labels next to flags")

    local marker_filter_opt = GetMarkerFlagFilterOption()
    if BeginInlineCombo("Marker Filter", "marker_filter_mode", marker_filter_opt.label, pair_w) then
      for i, entry in ipairs(MARKER_FLAG_FILTER_OPTIONS) do
        local is_sel = params.marker_flags_filter_mode_idx == i
        if r.ImGui_Selectable(ctx, entry.label .. "##marker_filter_item_" .. tostring(i), is_sel) then
          params.marker_flags_filter_mode_idx = i
        end
        if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    Tip("Filter marker flags by lane name")

    local mf_key = GetMarkerFlagFilterOption().key
    if mf_key == "lane_contains" or mf_key == "lane_exact" then
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, pair_w)
      local mf_ch, mf_new = r.ImGui_InputText(ctx, "Lane Name##marker_flags_name_filter", tostring(params.marker_flags_name_filter or ""))
      if mf_ch then params.marker_flags_name_filter = tostring(mf_new or "") end
      Tip("Lane name filter text")
    end
  end

  local cache_mode_opt = GetCacheModeOption()
  if BeginInlineCombo("Caching", "cache_mode", cache_mode_opt.label, pair_w) then
    for i, entry in ipairs(CACHE_MODE_OPTIONS) do
      local is_sel = params.cache_mode_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##cache_mode_item_" .. tostring(i), is_sel) then
        params.cache_mode_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  Tip("All: cache every supported block. Selected: only checked blocks")
  r.ImGui_SameLine(ctx)
  local crm_ch, crm_new = InlineInputInt("Cache ms", "cache_refresh_ms", math.floor((params.cache_refresh_ms or 150) + 0.5), pair_w)
  if crm_ch then
    params.cache_refresh_ms = Clamp(crm_new, 50, 2000)
  end
  Tip("Cache refresh interval in milliseconds")

  if GetCacheModeOption().key == "selected" then
    local c1_ch, c1_new = r.ImGui_Checkbox(ctx, "Cache Markers##cache_markers", params.cache_markers)
    if c1_ch then params.cache_markers = c1_new end
    Tip("Cache filtered marker list for flags")
    r.ImGui_SameLine(ctx)
    local c2_ch, c2_new = r.ImGui_Checkbox(ctx, "Cache Marker Lanes##cache_marker_lanes", params.cache_marker_lanes)
    if c2_ch then params.cache_marker_lanes = c2_new end
    Tip("Cache marker->lane map and lane names")
    r.ImGui_SameLine(ctx)
    local c3_ch, c3_new = r.ImGui_Checkbox(ctx, "Cache Gap##cache_curve_gap", params.cache_curve_gap)
    if c3_ch then params.cache_curve_gap = c3_new end
    Tip("Cache gap estimation for continuity logic")
    r.ImGui_SameLine(ctx)
    local c4_ch, c4_new = r.ImGui_Checkbox(ctx, "Cache Hover##cache_hover_readout", params.cache_hover_readout)
    if c4_ch then params.cache_hover_readout = c4_new end
    Tip("Cache mouse hover readout text")
  end

  local ers_ch, ers_new = r.ImGui_Checkbox(ctx, "Render Early Skip##render_early_skip", params.render_early_skip)
  if ers_ch then params.render_early_skip = ers_new end
  Tip("On: hidden layers are skipped fully. Off: hidden layers may precompute cache")

  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Mouse wheel: Y Zoom | Ctrl+Wheel: X Zoom (%.2fx)", params.x_zoom or 1.0))

  if r.ImGui_BeginTable(ctx, "EngineCompactTable##eng_tbl", 2, r.ImGui_TableFlags_SizingStretchSame(), -1, 0) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableSetColumnIndex(ctx, 0)
    local hs_changed, hs_new = r.ImGui_SliderDouble(ctx, "History (X)##history_sec", params.history_sec, 10.0, 900.0, "%.0f s")
    if hs_changed then params.history_sec = hs_new end
    r.ImGui_TableSetColumnIndex(ctx, 1)
    local yz_changed, yz_new = r.ImGui_SliderDouble(ctx, "Y Zoom##y_zoom", params.y_zoom, 0.5, 3.0, "%.2fx")
    if yz_changed then params.y_zoom = yz_new end
    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, "Deviation Alerts")
  if BeginInlineCombo("Alert Mode", "alert_mode", alert_mode_opt.label, pair_w) then
    for i, entry in ipairs(ALERT_MODE_OPTIONS) do
      local is_sel = params.alert_mode_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##alert_mode_item_" .. tostring(i), is_sel) then
        params.alert_mode_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SameLine(ctx)
  if BeginInlineCombo("Alert Source", "alert_source", alert_source_opt.label, pair_w) then
    for i, entry in ipairs(ALERT_SOURCE_OPTIONS) do
      local is_sel = params.alert_source_idx == i
      if r.ImGui_Selectable(ctx, entry.label .. "##alert_source_item_" .. tostring(i), is_sel) then
        params.alert_source_idx = i
      end
      if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end

  local md_ch, md_new = InlineSliderDouble("Min Duration", "alert_min_duration", params.alert_min_duration_sec, 0.05, 10.0, "%.2f s", pair_w)
  if md_ch then params.alert_min_duration_sec = md_new end
  r.ImGui_SameLine(ctx)
  local mg_ch, mg_new = InlineSliderDouble("Merge Gap", "alert_merge_gap", params.alert_merge_gap_sec, 0.00, 2.0, "%.2f s", pair_w)
  if mg_ch then params.alert_merge_gap_sec = mg_new end

  local cd_ch, cd_new = InlineSliderDouble("Cooldown", "alert_cooldown_sec", params.alert_cooldown_sec, 0.0, 60.0, "%.1f s", pair_w)
  if cd_ch then params.alert_cooldown_sec = cd_new end
  Tip("Minimum time between same alert type events per source")

  local alra_ch, alra_new = r.ImGui_Checkbox(ctx, "LRA criterion##alert_lra_enabled", params.alert_lra_enabled)
  if alra_ch then params.alert_lra_enabled = alra_new end
  Tip("Create extra alerts when source LRA exceeds the max of source A/B standard")

  r.ImGui_SameLine(ctx)
  local atp_ch, atp_new = r.ImGui_Checkbox(ctx, "TP criterion##alert_tp_enabled", params.alert_tp_enabled)
  if atp_ch then params.alert_tp_enabled = atp_new end
  Tip("Create extra alerts when True Peak exceeds the max of source A/B standard")

  local cp_ch, cp_new = r.ImGui_Checkbox(ctx, "Clear previous generated##alert_clear_prev", params.alert_clear_prev)
  if cp_ch then params.alert_clear_prev = cp_new end
  r.ImGui_SameLine(ctx)
  local al_ch, al_new = r.ImGui_Checkbox(ctx, "Use dedicated lane##alert_use_lane", params.alert_use_lane)
  if al_ch then params.alert_use_lane = al_new end
  r.ImGui_SameLine(ctx)
  local asn_ch, asn_new = r.ImGui_Checkbox(ctx, "Smart naming##alert_smart_naming", params.alert_smart_naming)
  if asn_ch then params.alert_smart_naming = asn_new end
  Tip("Use status words in marker/region names: too quiet, quiet, normal, loud, too loud")
  r.ImGui_SameLine(ctx)
  local ail_ch, ail_new = r.ImGui_Checkbox(ctx, "LUFS in name##alert_include_lufs", params.alert_include_lufs)
  if ail_ch then params.alert_include_lufs = ail_new end
  Tip("Append momentary loudness value (LUFS) to generated marker/region name")
  r.ImGui_SameLine(ctx)
  local ah_ch, ah_new = r.ImGui_Checkbox(ctx, "Help##alert_help", params.alert_help)
  if ah_ch then params.alert_help = ah_new end
  Tip("Append recommended gain adjustment to target directly in marker/region names")

  local prefix_row_w = r.ImGui_GetContentRegionAvail(ctx)
  local prefix_w = math.max(96, (prefix_row_w - 16) / 3)

  local ap_ch, ap_new = BeginInlineInputText("Prefix", "alert_prefix", tostring(params.alert_prefix or ""), prefix_w)
  if ap_ch then params.alert_prefix = ap_new end
  r.ImGui_SameLine(ctx)
  local alp_ch, alp_new = BeginInlineInputText("LRA Prefix", "alert_lra_prefix", tostring(params.alert_lra_prefix or ""), prefix_w)
  if alp_ch then params.alert_lra_prefix = alp_new end
  r.ImGui_SameLine(ctx)
  local atpp_ch, atpp_new = BeginInlineInputText("TP Prefix", "alert_tp_prefix", tostring(params.alert_tp_prefix or ""), prefix_w)
  if atpp_ch then params.alert_tp_prefix = atpp_new end

  local aln_ch, aln_new = BeginInlineInputText("Lane Name", "alert_lane_name", tostring(params.alert_lane_name or ""), pair_w)
  if aln_ch then params.alert_lane_name = aln_new end
  r.ImGui_SameLine(ctx)
  local ali_ch, ali_new = InlineInputInt("Lane Index", "alert_lane_index", math.floor((params.alert_lane_index or -1) + 0.5), pair_w)
  if ali_ch then params.alert_lane_index = ali_new end
  r.ImGui_TextColored(ctx, COLOR_DIM, "Alert colors: LOW = blue, HIGH = red")

  local alerts_row_w = r.ImGui_GetContentRegionAvail(ctx)
  local alert_btn_w = math.max(64, (alerts_row_w - 12) / 3)
  if r.ImGui_Button(ctx, "Create Alerts##create_alerts", alert_btn_w, 0) then
    CreateDeviationAlerts()
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear Session##clear_alerts_session", alert_btn_w, 0) then
    ClearGeneratedAlerts()
    state.backend_note = "Alerts: cleared generated items from current session"
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear Prefix##clear_alerts_prefix", alert_btn_w, 0) then
    ClearDeviationAlertsByPrefix()
  end

  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("A tracks: %d | B tracks: %d", #state.source_a.tracks, #state.source_b.tracks))
  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("A pts: %d | B pts: %d", #state.source_a.points, #state.source_b.points))
  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("A src: %s | B src: %s", tostring(state.source_a.label or "A"), tostring(state.source_b.label or "B")))
  r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Offline status: %s | Range %.2f - %.2f", params.offline_status, params.range_start, params.range_end))
  if params.offline_debug_enabled then
    r.ImGui_TextColored(ctx, COLOR_DIM, "Offline debug: ON")
    if tostring(state.offline_debug_last or "") ~= "" then
      r.ImGui_TextColored(ctx, COLOR_DIM, "DBG: " .. tostring(state.offline_debug_last))
    end
  end
  if state.backend_note ~= "" then
    r.ImGui_TextColored(ctx, COLOR_DIM, state.backend_note)
  end
  if state.last_error ~= "" then
    r.ImGui_TextColored(ctx, 0xFF7777FF, "Last error: " .. state.last_error)
  end
end

local function FormatSummaryInline(prefix, summary)
  if not summary then
    return prefix .. " I:-inf TP:-inf LRA:0.0"
  end
  return string.format("%s I:%.1f TP:%.1f LRA:%.1f G:%.0f%%", prefix, summary.integrated, summary.peak, summary.lra, summary.gated_ratio)
end

local function ShortLabel(s, max_len)
  local txt = tostring(s or "")
  if #txt <= max_len then return txt end
  return txt:sub(1, max_len - 1) .. "~"
end

local function DrawSummaryLine()
  r.ImGui_Separator(ctx)
  local a_lbl = ShortLabel(state.source_a.label, 12)
  local b_lbl = ShortLabel(state.source_b.label, 12)
  local a_txt = state.source_a.summary
    and string.format("A[%s] I %.1f TP %.1f LRA %.1f G %.0f%%", a_lbl, state.source_a.summary.integrated, state.source_a.summary.peak, state.source_a.summary.lra, state.source_a.summary.gated_ratio)
    or string.format("A[%s] no data", a_lbl)
  local b_txt = state.source_b.summary
    and string.format("B[%s] I %.1f TP %.1f LRA %.1f G %.0f%%", b_lbl, state.source_b.summary.integrated, state.source_b.summary.peak, state.source_b.summary.lra, state.source_b.summary.gated_ratio)
    or string.format("B[%s] no data", b_lbl)
  local sep = "  |  "
  local aw = r.ImGui_CalcTextSize(ctx, a_txt)
  local sw = r.ImGui_CalcTextSize(ctx, sep)
  local bw = r.ImGui_CalcTextSize(ctx, b_txt)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local cur_x, _ = r.ImGui_GetCursorPos(ctx)
  local start_x = cur_x + math.max(0.0, avail - (aw + sw + bw))
  r.ImGui_SetCursorPosX(ctx, start_x)
  r.ImGui_TextColored(ctx, COLOR_MID_A, a_txt)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, COLOR_DIM, sep)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, COLOR_MID_B, b_txt)
end

local function DrawMouseReadoutLine(points_a, points_b, start_t, end_t, graph_x, graph_w)
  local mouse_x = select(1, r.GetMousePosition())
  local mouse_t = start_t + ((mouse_x - graph_x) / math.max(1, graph_w)) * (end_t - start_t)
  mouse_t = Clamp(mouse_t, start_t, end_t)

  local time_bucket = math.floor((mouse_t or 0.0) * 20 + 0.5)
  local key = string.format("%d|%d|%d|%d|%d", time_bucket, #points_a, #points_b, math.floor((start_t or 0.0) * 10), math.floor((end_t or 0.0) * 10))
  local text = GetCachedValue("hover_readout_cache", key, "cache_hover_readout", function()
    local a_point = FindClosestPoint(points_a, mouse_t)
    local b_point = FindClosestPoint(points_b, mouse_t)
    local t = string.format("Mouse %s", FormatTimeMMSS(mouse_t))
    if a_point or b_point then
      t = t .. string.format(" | A M:%.1f S:%.1f I:%.1f TP:%.1f", a_point and (a_point.m or -120.0) or -120.0, a_point and (a_point.s or -120.0) or -120.0, a_point and (a_point.i or -120.0) or -120.0, a_point and (a_point.peak or -120.0) or -120.0)
      t = t .. string.format(" | B M:%.1f S:%.1f I:%.1f TP:%.1f", b_point and (b_point.m or -120.0) or -120.0, b_point and (b_point.s or -120.0) or -120.0, b_point and (b_point.i or -120.0) or -120.0, b_point and (b_point.peak or -120.0) or -120.0)
    else
      t = t .. " | Move over graph for values"
    end
    return t
  end)

  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local cur_x, _ = r.ImGui_GetCursorPos(ctx)
  r.ImGui_SetCursorPosX(ctx, cur_x + 2)
  r.ImGui_TextColored(ctx, COLOR_DIM, text)
end

local function DrawDetailMetricsBlock(panel_w, panel_h)
  local function draw_summary(prefix, label, summary, color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), color)
    r.ImGui_Text(ctx, prefix .. " " .. label)
    r.ImGui_PopStyleColor(ctx)
    if not summary then
      r.ImGui_TextColored(ctx, COLOR_DIM, "No data")
      return
    end

    r.ImGui_PushFont(ctx, nil, 18.0)
    r.ImGui_TextColored(ctx, COLOR_TEXT, string.format("I: %.1f LUFS", summary.integrated))
    r.ImGui_PopFont(ctx)
    r.ImGui_TextColored(ctx, COLOR_TEXT, string.format("TP: %.1f dBFS | LRA: %.1f LU | G: %.0f%%", summary.peak, summary.lra, summary.gated_ratio))
    r.ImGui_TextColored(ctx, COLOR_TEXT, string.format("S(cur/max): %.1f / %.1f", summary.short_current or -120.0, summary.short_max or -120.0))
    r.ImGui_TextColored(ctx, COLOR_TEXT, string.format("M(cur/max): %.1f / %.1f", summary.momentary_current or -120.0, summary.momentary_max or -120.0))
  end

  panel_w = math.max(1, math.floor(panel_w or r.ImGui_GetContentRegionAvail(ctx)))
  panel_h = math.max(1, math.floor(panel_h or 0))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 2)
  if r.ImGui_BeginChild(ctx, "LoudnessDetails##details", panel_w, panel_h, 1) then
    draw_summary("A", ShortLabel(state.source_a.label, 12), state.source_a.summary, COLOR_MID_A)
    r.ImGui_Separator(ctx)
    draw_summary("B", ShortLabel(state.source_b.label, 12), state.source_b.summary, COLOR_MID_B)
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Range: %.2f..%.2f", params.range_start, params.range_end))
    r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Offline windows A M/S/H: %.2fs/%.1fs/%.2fs | B M/S/H: %.2fs/%.1fs/%.2fs", params.source_a_momentary_window_sec or 0.4, params.source_a_short_window_sec or 3.0, params.source_a_hop_sec or 0.1, params.source_b_momentary_window_sec or 0.4, params.source_b_short_window_sec or 3.0, params.source_b_hop_sec or 0.1))
    r.ImGui_TextColored(ctx, COLOR_DIM, string.format("Zoom: %.2fx | A Crit +/-: %.1f/%.1f | B Crit +/-: %.1f/%.1f LU", params.y_zoom, params.source_a_critical_upper_lu, params.source_a_critical_lower_lu, params.source_b_critical_upper_lu, params.source_b_critical_lower_lu))
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopStyleVar(ctx, 1)
end

local function MainLoop()
  PushTheme()

  RefreshColorsFromParams()

  params.sample_rate = Clamp(math.floor(params.sample_rate or 48000), 8000, 192000)
  params.source_a_momentary_window_sec = Clamp(tonumber(params.source_a_momentary_window_sec) or 0.4, 0.2, 6.0)
  params.source_a_short_window_sec = Clamp(tonumber(params.source_a_short_window_sec) or 3.0, params.source_a_momentary_window_sec, 30.0)
  params.source_a_hop_sec = Clamp(tonumber(params.source_a_hop_sec) or 0.1, 0.02, 0.5)
  params.source_b_momentary_window_sec = Clamp(tonumber(params.source_b_momentary_window_sec) or 0.4, 0.2, 6.0)
  params.source_b_short_window_sec = Clamp(tonumber(params.source_b_short_window_sec) or 3.0, params.source_b_momentary_window_sec, 30.0)
  params.source_b_hop_sec = Clamp(tonumber(params.source_b_hop_sec) or 0.1, 0.02, 0.5)
  params.history_sec = Clamp(params.history_sec, 10.0, 1800.0)
  params.y_zoom = Clamp(params.y_zoom or 1.0, 0.5, 3.0)
  params.x_zoom = Clamp(params.x_zoom or 1.0, 0.25, 8.0)

  if r.CountTracks(0) <= 0 then
    r.ImGui_SetNextWindowSize(ctx, 620, 220, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, SCRIPT_TITLE, true)
    if visible then
      r.ImGui_TextColored(ctx, 0xFFBB66FF, "No tracks found in project.")
      r.ImGui_Text(ctx, "Create/import tracks and reopen analyzer.")
      if r.ImGui_Button(ctx, "Close##close_no_tracks", 120, 0) then
        open = false
      end
      r.ImGui_End(ctx)
    end
    PopTheme()
    if open then
      r.defer(MainLoop)
    else
      DestroyContextSafe()
    end
    return
  end

  if GetModeOption().key == "live" then
    RunLiveTick()
  end

  ProcessOfflineJobTick()

  params.panel_ratio = Clamp(params.panel_ratio or 0.25, 0.15, 0.45)

  r.ImGui_SetNextWindowSize(ctx, 1460, 260, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_TITLE, true)

  if visible then
    local points_a = params.source_a_enabled and state.source_a.points or {}
    local points_b = params.source_b_enabled and state.source_b.points or {}

    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local splitter_w = params.panel_hidden and 12 or 6
    local right_w = params.panel_hidden and 0 or math.max(300, math.floor(avail_w * params.panel_ratio))
    local left_w = math.max(320, avail_w - right_w - splitter_w - 6)

    if r.ImGui_BeginChild(ctx, "GraphArea##left", left_w, avail_h, 0) then
      local graph_x, graph_y = r.ImGui_GetCursorScreenPos(ctx)
      local graph_w_ctx = r.ImGui_GetContentRegionAvail(ctx)
      local mode_key = GetModeOption().key
      local axis_mode = GetTimeAxisOption().key
      local readout_start_t, readout_end_t = ComputeGraphTimeWindow(mode_key, axis_mode)
      local content_h = math.max(90, avail_h - 2)
      local details_w = (avail_h >= 150 and graph_w_ctx >= 620) and math.max(250, math.min(300, math.floor(graph_w_ctx * 0.28))) or 0
      local graph_col_w = math.max(320, graph_w_ctx - details_w - (details_w > 0 and 8 or 0))
      local mouse_line_h = 20
      local graph_h = math.max(90, content_h - mouse_line_h - 8)

      if details_w > 0 then
        if r.ImGui_BeginChild(ctx, "GraphPane##left_graph", graph_col_w, content_h, 0) then
          DrawGraph(points_a, points_b, graph_h)
          DrawMouseReadoutLine(points_a, points_b, readout_start_t, readout_end_t, graph_x, graph_col_w)
          r.ImGui_EndChild(ctx)
        end

        r.ImGui_SameLine(ctx)
        DrawDetailMetricsBlock(details_w, content_h)
      else
        DrawGraph(points_a, points_b, graph_h)
        DrawMouseReadoutLine(points_a, points_b, readout_start_t, readout_end_t, graph_x, graph_w_ctx)
        DrawDetailMetricsBlock(graph_w_ctx, math.max(1, content_h - graph_h - 8))
      end

      r.ImGui_EndChild(ctx)
    end

    r.ImGui_SameLine(ctx)
    local splitter_x, splitter_y = r.ImGui_GetCursorScreenPos(ctx)
    local split_h = math.max(2, avail_h)
    if splitter_w > 0 and split_h > 0 then
      r.ImGui_InvisibleButton(ctx, "PanelSplitter##split", splitter_w, split_h)
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local split_col = r.ImGui_IsItemHovered(ctx) and 0x7A8798FF or 0x46505FFF
      r.ImGui_DrawList_AddLine(dl, splitter_x + splitter_w * 0.5, splitter_y, splitter_x + splitter_w * 0.5, splitter_y + split_h, split_col, 2.0)
      local arrow = params.panel_hidden and ">" or "<"
      r.ImGui_DrawList_AddText(dl, splitter_x + 1, splitter_y + 8, 0xA8B4C5FF, arrow)

      if params.panel_hidden and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 0) then
        params.panel_hidden = false
      elseif r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        params.panel_hidden = not params.panel_hidden
      elseif r.ImGui_IsItemActive(ctx) and (not params.panel_hidden) then
        local dx = r.ImGui_GetMouseDelta(ctx)
        params.panel_ratio = Clamp(params.panel_ratio - (dx / math.max(1, avail_w)), 0.02, 0.45)
        if params.panel_ratio <= 0.03 then
          params.panel_hidden = true
        end
      end
    end

    if not params.panel_hidden and right_w > 0 then
      r.ImGui_SameLine(ctx)
      if r.ImGui_BeginChild(ctx, "ControlArea##right", right_w, avail_h, 0) then
        DrawControlPanel()
        r.ImGui_EndChild(ctx)
      end
    end

    r.ImGui_End(ctx)
  end

  PopTheme()
  SaveParamsIfChanged(false)

  if open then
    r.defer(MainLoop)
  else
    SaveParamsIfChanged(true)
    DestroyContextSafe()
  end
end

LoadParams()
UpdateSourceBindings()
ClearGraphHistory(nil)
r.defer(MainLoop)
