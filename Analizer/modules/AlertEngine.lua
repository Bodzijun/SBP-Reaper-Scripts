local M = {}

function M.CreateAlertEngine(deps)
  local r = deps.r
  local state = deps.state
  local params = deps.params
  local Clamp = deps.Clamp
  local FindClosestPoint = deps.FindClosestPoint
  local GetAlertSourceOption = deps.GetAlertSourceOption
  local GetAlertModeOption = deps.GetAlertModeOption
  local GetAlertThresholdOption = deps.GetAlertThresholdOption
  local ALERT_FIELD_OPTIONS = deps.ALERT_FIELD_OPTIONS
  local ToNativeColor = deps.ToNativeColor
  local LogError = deps.LogError

  local function ClearGeneratedAlerts()
    if not state.alert_ids then
      state.alert_ids = {}
      state.alert_cooldown_last = {}
      return
    end
    for i = #state.alert_ids, 1, -1 do
      local item = state.alert_ids[i]
      if item and item.id then
        pcall(r.DeleteProjectMarker, 0, item.id, item.isrgn and true or false)
      end
    end
    state.alert_ids = {}
    state.alert_cooldown_last = {}
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
    state.alert_cooldown_last = {}
    return deleted
  end

  local function ResolveAlertLaneIndex(output_kind)
    local is_region = tostring(output_kind or "marker") == "region"
    local use_key = is_region and "alert_region_use_lane" or "alert_marker_use_lane"
    local name_key = is_region and "alert_region_lane_name" or "alert_marker_lane_name"
    local index_key = is_region and "alert_region_lane_index" or "alert_marker_lane_index"
    local use_lane = params[use_key]
    if use_lane == nil then use_lane = params.alert_use_lane end
    if not use_lane then return -1 end
    if not (r.APIExists and r.APIExists("GetSetProjectInfo")) then return -1 end

    local fallback_name = is_region and "Loudness Regions" or "True Peak Alerts"
    local lane_name = tostring(params[name_key] or params.alert_lane_name or fallback_name)
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

    local legacy_index = (not is_region) and params.alert_lane_index or -1
    local manual_value = params[index_key]
    if manual_value == nil or (manual_value < 0 and legacy_index and legacy_index >= 0) then
      manual_value = legacy_index
    end
    local manual = math.floor((manual_value or -1) + 0.5)
    if manual >= 0 and manual < lane_count then
      if r.GetSetProjectInfo_String then
        local desc = "RULER_LANE_NAME:" .. tostring(manual)
        pcall(r.GetSetProjectInfo_String, 0, desc, lane_name, true)
      end
      params[index_key] = manual
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
      params[index_key] = found
      return found
    end

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
      params[index_key] = created_idx
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

  local function GetOutputNameFlags(output_kind)
    local prefix = (tostring(output_kind or "marker") == "region") and "alert_region_" or "alert_marker_"
    return {
      source = params[prefix .. "include_source"] ~= false,
      status = params[prefix .. "include_status"] ~= false,
      metric = params[prefix .. "include_metric"] ~= false,
      value = params[prefix .. "include_value"] == true,
      duration = params[prefix .. "include_duration"] == true,
      hint = params[prefix .. "include_hint"] == true
    }
  end

  local function BuildOutputName(output_kind, prefix, source_label, status, metric, value_text, duration_text, hint_text)
    local flags = GetOutputNameFlags(output_kind)
    local parts = {}
    local pfx = tostring(prefix or "Loudness Alert")
    if pfx ~= "" then parts[#parts + 1] = pfx end
    if flags.source and source_label and tostring(source_label) ~= "" then parts[#parts + 1] = tostring(source_label) end
    if flags.status and status and tostring(status) ~= "" then parts[#parts + 1] = tostring(status) end
    if flags.metric and metric and tostring(metric) ~= "" then parts[#parts + 1] = tostring(metric) end
    if flags.value and value_text and tostring(value_text) ~= "" then parts[#parts + 1] = tostring(value_text) end
    if flags.duration and duration_text and tostring(duration_text) ~= "" then parts[#parts + 1] = tostring(duration_text) end
    if flags.hint and hint_text and tostring(hint_text) ~= "" then parts[#parts + 1] = "[" .. tostring(hint_text) .. "]" end
    if #parts == 0 then return "Loudness Alert" end
    return table.concat(parts, " ")
  end

  local function GetOutputAlertConfig(output_kind)
    local kind = tostring(output_kind or "marker") == "region" and "region" or "marker"
    local prefix = "alert_" .. kind .. "_"
    local enabled = params[prefix .. "enabled"]
    if enabled == nil then
      local legacy_mode = tonumber(params.alert_mode_idx) or 1
      enabled = (kind == "marker" and (legacy_mode == 2 or legacy_mode == 3)) or (kind == "region" and (legacy_mode == 1 or legacy_mode == 3))
    end
    local threshold_idx = params[prefix .. "threshold_idx"]
    local threshold_opt = GetAlertThresholdOption and GetAlertThresholdOption(threshold_idx) or { key = "critical" }
    local lra_enabled = params[prefix .. "lra_enabled"]
    local tp_enabled = params[prefix .. "tp_enabled"]
    if lra_enabled == nil then lra_enabled = params.alert_lra_enabled == true end
    if tp_enabled == nil then tp_enabled = params.alert_tp_enabled == true end
    return {
      kind = kind,
      enabled = enabled == true,
      threshold = threshold_opt,
      lra_enabled = lra_enabled == true,
      tp_enabled = tp_enabled == true
    }
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

  local function BuildSmartAlertLabelAtTime(pos, output_kind)
    local source_mode = GetAlertSourceOption().key
    local prefix = tostring(params.alert_prefix or "Loudness Alert")
    if prefix == "" then prefix = "Loudness Alert" end

    local entries = {}
    local function lift_hint(current_lufs, target_lufs)
      local cur = tonumber(current_lufs)
      local tgt = tonumber(target_lufs)
      if not cur or not tgt then return "" end
      local delta = tgt - cur
      if delta > 0.1 then return string.format("raise +%.1f dB", delta) end
      if delta < -0.1 then return string.format("reduce %.1f dB", delta) end
      return "on target"
    end

    local function add_entry(src_key)
      local p, target, tol, cup, cdn, src_label, field_key = GetSourcePointAtTime(src_key, pos)
      local meter = (field_key == "st") and "S" or "M"
      local m_val = p and p[field_key] or nil
      local status, rank = BuildLoudnessStatus(m_val, target, tol, cup, cdn)
      entries[#entries + 1] = { source = src_label, status = status, rank = rank, m = m_val, target = target, meter = meter }
    end

    if source_mode == "a" then add_entry("a")
    elseif source_mode == "b" then add_entry("b")
    else add_entry("a"); add_entry("b") end

    if #entries == 1 then
      local e = entries[1]
      local hint = lift_hint(e.m, e.target)
      return BuildOutputName(output_kind or "marker", prefix, e.source, e.status, e.meter or "M", e.m and string.format("%.1f LUFS", e.m) or nil, nil, hint)
    end

    local e1 = entries[1]
    local e2 = entries[2]
    local h1 = lift_hint(e1.m, e1.target)
    local h2 = lift_hint(e2.m, e2.target)
    local value_text = (e1.m and e2.m) and string.format("A %.1f / B %.1f LUFS", e1.m, e2.m) or nil
    local hint = (h1 ~= "" and h2 ~= "") and string.format("A %s | B %s", h1, h2) or nil
    return BuildOutputName(output_kind or "marker", prefix, "A/B", e1.status .. " | " .. e2.status, (e1.meter or "M") .. "/" .. (e2.meter or "M"), value_text, nil, hint)
  end

  local function BuildSegmentAlertLabel(prefix, source_label, seg, meter_label, output_kind)
    local pfx = tostring(prefix or "Loudness Alert")
    if pfx == "" then pfx = "Loudness Alert" end
    local seg_status = ((seg and seg.polarity) == "LOW") and "too quiet" or "too loud"
    local function lift_hint(current_lufs, target_lufs)
      local cur = tonumber(current_lufs)
      local tgt = tonumber(target_lufs)
      if not cur or not tgt then return "" end
      local delta = tgt - cur
      if delta > 0.1 then return string.format("raise +%.1f dB", delta) end
      if delta < -0.1 then return string.format("reduce %.1f dB", delta) end
      return "on target"
    end

    local target = (tostring(source_label or "A") == "B") and (params.source_b_target_lufs or -23.0) or (params.source_a_target_lufs or -23.0)

    local dur = math.max(0.0, ((seg and seg.t1) or (seg and seg.t0) or 0.0) - ((seg and seg.t0) or 0.0))
    local value_text = seg and seg.v_peak and string.format("%.1f LUFS", seg.v_peak) or nil
    local duration_text = string.format("%.2fs", dur)
    local hint = lift_hint(seg and seg.v_peak or nil, target)
    return BuildOutputName(output_kind, pfx, source_label or "A", seg_status, meter_label or "M", value_text, duration_text, hint)
  end

  local function CollectCriticalSegments(points, field_key, target_lufs, tol_lu, crit_up_lu, crit_down_lu, threshold_key, min_dur_sec, merge_gap_sec)
    local out = {}
    if not points or #points == 0 then return out end

    local min_dur = math.max(0.01, min_dur_sec or 0.6)
    local merge_gap = math.max(0.0, merge_gap_sec or 0.25)
    local target = tonumber(target_lufs) or -23.0
    local tolerance = math.max(0.05, tonumber(tol_lu) or 1.0)
    local critical_up = math.max(0.1, tonumber(crit_up_lu) or 8.0)
    local critical_down = math.max(0.1, tonumber(crit_down_lu) or 8.0)
    local use_tolerance = tostring(threshold_key or "critical") == "tolerance"
    local up_lim = target + (use_tolerance and tolerance or critical_up)
    local dn_lim = target - (use_tolerance and tolerance or critical_down)

    local seg = nil
    for i = 1, #points do
      local p = points[i]
      local t = tonumber(p and p.t)
      local v = tonumber(p and p[field_key])
      -- Cockos' meter can briefly expose the floor value (-120 LUFS) while
      -- its peak output already contains real audio. Do not turn that stale
      -- floor read into a long false silence region; a genuine digital
      -- silence normally carries the same floor on its peak value as well.
      local peak = tonumber(p and p.peak)
      if v and v <= -119.5 and peak and peak > -119.0 then
        v = nil
      end
      if not t or not v then
        if seg and (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
        seg = nil
      else
        if seg and (t - seg.t1) > merge_gap then
          if (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
          seg = nil
        end
        local over = v - up_lim
        local under = dn_lim - v
        local bad = (over > 0.0) or (under > 0.0)
        local polarity = (over > 0.0) and "HIGH" or "LOW"
        local excess = math.max(over, under, 0.0)

        if bad then
          if not seg then
            seg = { t0 = t, t1 = t, polarity = polarity, max_excess = excess, v_peak = v }
          elseif polarity ~= seg.polarity then
            if (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
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
        end
      end
    end

    if seg and (seg.t1 - seg.t0) >= min_dur then out[#out + 1] = seg end
    return out
  end

  local function PassesAlertCooldown(source_key, alert_kind, t)
    local cooldown = math.max(0.0, tonumber(params.alert_cooldown_sec) or 0.0)
    if cooldown <= 0.0 then return true end
    if not state.alert_cooldown_last then state.alert_cooldown_last = {} end

    local ts = math.max(0.0, tonumber(t) or 0.0)
    local key = tostring(source_key or "?") .. "|" .. tostring(alert_kind or "generic")
    local prev = tonumber(state.alert_cooldown_last[key])
    if prev and ts < prev then
      -- Timeline moved backwards: start a fresh cooldown epoch.
      prev = nil
      state.alert_cooldown_last[key] = nil
    end
    if prev and (ts - prev) < cooldown then return false end
    state.alert_cooldown_last[key] = ts
    return true
  end

  local function CreateAlertsForSource(source_key, label, points, target_lufs, crit_up_lu, crit_down_lu)
    local created = 0
    local field_key = GetAlertFieldKeyForSource(source_key)
    local meter_label = (field_key == "st") and "S" or "M"
    local tolerance = (source_key == "a") and params.source_a_tolerance_lu or params.source_b_tolerance_lu
    local prefix = tostring(params.alert_prefix or "Loudness Alert")
    if prefix == "" then prefix = "Loudness Alert" end
    local region_cfg = GetOutputAlertConfig("region")
    local region_lane_idx = region_cfg.enabled and ResolveAlertLaneIndex("region") or -1

    local total_segments = 0
    local function create_output(output_kind, cfg)
      if not cfg.enabled then return end
      local segs = CollectCriticalSegments(points, field_key, target_lufs, tolerance, crit_up_lu, crit_down_lu, cfg.threshold.key, params.alert_min_duration_sec, params.alert_merge_gap_sec)
      total_segments = total_segments + #segs
      for i = 1, #segs do
        local s = segs[i]
        if PassesAlertCooldown(source_key, "deviation|" .. output_kind, s.t0) then
          local alert_color = ((s.polarity or "") == "LOW") and ToNativeColor(params.alert_color_low) or ToNativeColor(params.alert_color_high)
          local txt = BuildSegmentAlertLabel(prefix, label, s, meter_label, output_kind)
          local rgn_end = math.max((s.t1 or s.t0) + 0.001, s.t0 + 0.001)
          local id = r.AddProjectMarker2(0, true, s.t0, rgn_end, txt, -1, alert_color)
          if id and id >= 0 then
            state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = true }
            PlaceRegionOrMarkerLaneByIndex(id, true, region_lane_idx)
            created = created + 1
          end
        end
      end
    end

    -- M/S tolerance and critical deviations describe a time span, so they
    -- always use regions. Markers are reserved for instantaneous TP peaks.
    create_output("region", region_cfg)
    return created, total_segments
  end

  local function FindPeakPointTime(points, field_key)
    local best_t = nil
    local best_v = -math.huge
    for i = 1, #(points or {}) do
      local point = points[i]
      local value = tonumber(point and point[field_key])
      local t = tonumber(point and point.t)
      if value and t and value > best_v then
        best_v = value
        best_t = t
      end
    end
    return best_t, best_v
  end

  local function FindLraAnchor(points, summary)
    if not points or #points == 0 then return nil, nil end
    local integrated = tonumber(summary and (summary.integrated_meter or summary.integrated))
    if not integrated or integrated <= -119.0 then return nil, nil end

    local gate = integrated - 20.0
    local values = {}
    for i = 1, #points do
      local value = tonumber(points[i] and points[i].st)
      if value and value >= gate then values[#values + 1] = { value = value, t = tonumber(points[i].t) } end
    end
    if #values < 5 then return nil, nil end

    table.sort(values, function(a, b) return a.value < b.value end)
    local function percentile(q)
      local index = 1 + (q * (#values - 1))
      local lo = math.floor(index)
      local hi = math.ceil(index)
      if lo == hi then return values[lo].value end
      local frac = index - lo
      return values[lo].value + (values[hi].value - values[lo].value) * frac
    end
    local p10 = percentile(0.10)
    local p95 = percentile(0.95)
    local t10, t95 = nil, nil
    local d10, d95 = math.huge, math.huge
    for i = 1, #values do
      local item = values[i]
      if item.t then
        local e10 = math.abs(item.value - p10)
        local e95 = math.abs(item.value - p95)
        if e10 < d10 then d10, t10 = e10, item.t end
        if e95 < d95 then d95, t95 = e95, item.t end
      end
    end
    if not t10 or not t95 then return nil, nil end
    return math.min(t10, t95), math.max(t10, t95)
  end

  local function CreateLRAAlertForSource(source_key, label, points, summary, limit_lu)
    local region_cfg = GetOutputAlertConfig("region")
    if not region_cfg.enabled or not region_cfg.lra_enabled then return 0, 0 end
    if not summary or summary.lra == nil then return 0, 0 end

    local lra_val = tonumber(summary.lra) or 0.0
    local lra_lim = math.max(0.5, tonumber(limit_lu) or 8.0)
    if lra_val <= lra_lim then return 0, 0 end

    local range_start, range_end = FindLraAnchor(points, summary)
    local region_start = tonumber(range_start)
    local pos = range_start and ((range_start + range_end) * 0.5) or nil
    if not pos then pos = points and #points > 0 and points[#points].t or nil end
    if not pos then pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition() end
    pos = math.max(0.0, tonumber(pos) or 0.0)
    region_start = math.max(0.0, region_start or pos)
    range_end = math.max(pos + 0.001, tonumber(range_end) or pos + 0.001)
    local region_pass = PassesAlertCooldown(source_key, "lra|region", pos)
    if not region_pass then return 0, 0 end

    local prefix = tostring(params.alert_lra_prefix or "")
    if prefix == "" then prefix = tostring(params.alert_prefix or "Loudness Alert") end
    if prefix == "" then prefix = "Loudness Alert" end
    local region_lane_idx = ResolveAlertLaneIndex("region")
    local exceed = lra_val - lra_lim

    local alert_color = ToNativeColor(params.alert_color_high)
    local created = 0
    if region_pass then
      local txt = BuildOutputName("region", prefix, label or "A", "LRA high", "LRA", string.format("%.1f LU", lra_val), string.format("%.2fs", math.max(0.0, range_end - region_start)), string.format("reduce dynamics %.1f LU", exceed))
      local id = r.AddProjectMarker2(0, true, region_start, math.max(region_start + 0.001, range_end), txt, -1, alert_color)
      if id and id >= 0 then
        state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = true }
        PlaceRegionOrMarkerLaneByIndex(id, true, region_lane_idx)
        created = created + 1
      end
    end

    return created, 1
  end

  local function CreateTPAlertForSource(source_key, label, points, summary, limit_dbtp)
    local marker_cfg = GetOutputAlertConfig("marker")
    if not marker_cfg.enabled then return 0, 0 end
    if not points or #points == 0 then return 0, 0 end

    -- Resolve the value and its position from the same point.  The summary
    -- is refreshed on a scheduler and can briefly lag behind a rewritten live
    -- history, which previously allowed a valid TP value to be paired with a
    -- marker time from a different pass.
    local pos, point_peak = FindPeakPointTime(points, "peak")
    local tp_val = tonumber(point_peak)
    -- Never fall back to a stale summary when the point history is empty or
    -- has not yet caught up with the transport; that would place a phantom
    -- marker at the cursor rather than at a real peak.
    if not tp_val then return 0, 0 end
    local tp_lim = tonumber(limit_dbtp) or -1.0
    if tp_val <= tp_lim then return 0, 0 end

    if not pos then pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition() end
    pos = math.max(0.0, tonumber(pos) or 0.0)
    local marker_pass = PassesAlertCooldown(source_key, "tp|marker", pos)
    if not marker_pass then return 0, 0 end

    local prefix = tostring(params.alert_tp_prefix or "")
    if prefix == "" then prefix = "True Peak Alert" end
    local marker_lane_idx = ResolveAlertLaneIndex("marker")
    local exceed = tp_val - tp_lim

    local alert_color = ToNativeColor(params.alert_color_high)
    local created = 0
    if marker_pass then
      local txt = BuildOutputName("marker", prefix, label or "A", "high", nil, string.format("%.1f dBTP", tp_val), nil, string.format("reduce peak %.1f dB", exceed))
      local id = r.AddProjectMarker2(0, false, pos, 0.0, txt, -1, alert_color)
      if id and id >= 0 then
        state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = false }
        PlaceRegionOrMarkerLaneByIndex(id, false, marker_lane_idx)
        created = created + 1
      end
    end

    return created, 1
  end

  local function CreateDeviationAlerts()
    local ok, err = pcall(function()
      if params.alert_clear_prev then ClearGeneratedAlerts() end

      local source_key = GetAlertSourceOption().key
      local created_total, seg_total, lra_total, tp_total = 0, 0, 0, 0

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

      state.backend_note = string.format("Alerts: created %d items from %d deviation segments + %d LRA events + %d TP events", created_total, seg_total, lra_total, tp_total)
    end)

    if not ok then LogError("Create alerts failed: " .. tostring(err)) end
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
    if not ok then LogError("Clear alerts by prefix failed: " .. tostring(err)) end
  end

  local function CreateAlertMarkerAtTime(t)
    local pos = math.max(0.0, tonumber(t) or 0.0)
    local txt = BuildSmartAlertLabelAtTime(pos, "marker")
    local marker_color = ToNativeColor(params.alert_color_high)
    local lane_idx = ResolveAlertLaneIndex("marker")
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
      state.alert_ids[#state.alert_ids + 1] = { id = id, isrgn = false }
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

  return {
    CreateDeviationAlerts = CreateDeviationAlerts,
    ClearDeviationAlertsByPrefix = ClearDeviationAlertsByPrefix,
    CreateAlertMarkerAtTime = CreateAlertMarkerAtTime,
    ClearGeneratedAlerts = ClearGeneratedAlerts,
    ClearAlertsByPrefix = ClearAlertsByPrefix
  }
end

return M
