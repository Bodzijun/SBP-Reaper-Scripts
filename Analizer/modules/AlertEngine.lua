local M = {}

function M.CreateAlertEngine(deps)
  local r = deps.r
  local state = deps.state
  local params = deps.params
  local Clamp = deps.Clamp
  local FindClosestPoint = deps.FindClosestPoint
  local GetAlertSourceOption = deps.GetAlertSourceOption
  local GetAlertModeOption = deps.GetAlertModeOption
  local ALERT_FIELD_OPTIONS = deps.ALERT_FIELD_OPTIONS
  local ToNativeColor = deps.ToNativeColor
  local LogError = deps.LogError

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

    if not params.alert_smart_naming then return prefix end

    if #entries == 1 then
      local e = entries[1]
      local base = string.format("%s %s", prefix, e.status)
      if params.alert_include_lufs and e.m then
        base = string.format("%s (%s %.1f LUFS)", base, e.meter or "M", e.m)
      end
      if params.alert_help then
        local hint = lift_hint(e.m, e.target)
        if hint ~= "" then base = string.format("%s [%s]", base, hint) end
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
      if h1 ~= "" and h2 ~= "" then base = string.format("%s [A %s | B %s]", base, h1, h2) end
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
      if delta > 0.1 then return string.format("raise +%.1f dB", delta) end
      if delta < -0.1 then return string.format("reduce %.1f dB", delta) end
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
      if hint ~= "" then base = string.format("%s [%s]", base, hint) end
    end
    return base
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
    if prev and (ts - prev) < cooldown then return false end
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
    if points and #points > 0 then pos = points[#points].t end
    if not pos then pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition() end
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
      if params.alert_include_lufs then txt = string.format("%s (LRA %.1f LU)", txt, lra_val) end
      if params.alert_help then txt = string.format("%s [reduce dynamics %.1f LU]", txt, exceed) end
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
    if points and #points > 0 then pos = points[#points].t end
    if not pos then pos = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition() end
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
      if params.alert_include_lufs then txt = string.format("%s (TP %.1f dBTP)", txt, tp_val) end
      if params.alert_help then txt = string.format("%s [reduce peak %.1f dB]", txt, exceed) end
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

      state.backend_note = string.format("Alerts: created %d items from %d critical segments + %d LRA events + %d TP events", created_total, seg_total, lra_total, tp_total)
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

  return {
    CreateDeviationAlerts = CreateDeviationAlerts,
    ClearDeviationAlertsByPrefix = ClearDeviationAlertsByPrefix,
    CreateAlertMarkerAtTime = CreateAlertMarkerAtTime,
    ClearGeneratedAlerts = ClearGeneratedAlerts,
    ClearAlertsByPrefix = ClearAlertsByPrefix
  }
end

return M
