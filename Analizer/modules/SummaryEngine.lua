local M = {}

function M.CreateSummaryEngine(deps)
  local ComputePercentile = deps.ComputePercentile
  local EnergyToLufs = deps.EnergyToLufs
  local LufsToEnergy = deps.LufsToEnergy

  local function BuildSummary(points, gate_db, dialogue_cfg)
    if #points == 0 then
      return {
        integrated = -120.0,
        peak = -120.0,
        lra = 0.0,
        short_max = -120.0,
        gated_ratio = 0.0
      }
    end

    local function ComputeSpeechGatedDialogue(points_in, base_gate_db)
      if not points_in or #points_in < 8 then return nil, nil, nil, 0, 0 end

      local st_vals = {}
      for i = 1, #points_in do
        local stv = tonumber(points_in[i] and points_in[i].st)
        if stv and stv > -120.0 then
          st_vals[#st_vals + 1] = stv
        end
      end
      if #st_vals < 8 then return nil, nil, nil, 0, 0 end

      local noise_floor = ComputePercentile(st_vals, 0.20)
      local gate_offset = tonumber(dialogue_cfg and dialogue_cfg.gate_offset_lu) or 6.0
      local gate_min = tonumber(dialogue_cfg and dialogue_cfg.gate_min_st_lufs) or -55.0
      local speech_gate = math.max((tonumber(base_gate_db) or -70.0) + 10.0, noise_floor + gate_offset, gate_min)

      local dt_sum = 0.0
      local dt_n = 0
      for i = 2, #points_in do
        local t0 = tonumber(points_in[i - 1] and points_in[i - 1].t)
        local t1 = tonumber(points_in[i] and points_in[i].t)
        if t0 and t1 and t1 > t0 then
          dt_sum = dt_sum + (t1 - t0)
          dt_n = dt_n + 1
        end
      end
      local dt = (dt_n > 0) and (dt_sum / dt_n) or 0.1

      local hysteresis = tonumber(dialogue_cfg and dialogue_cfg.gate_hysteresis_lu) or 1.5
      local hangover_sec = tonumber(dialogue_cfg and dialogue_cfg.gate_hangover_sec) or 0.30
      local min_seg_sec = tonumber(dialogue_cfg and dialogue_cfg.min_segment_sec) or 0.35
      local merge_gap_sec = tonumber(dialogue_cfg and dialogue_cfg.merge_gap_sec) or 0.20

      local gate_open = speech_gate + (hysteresis * 0.5)
      local gate_close = speech_gate - (hysteresis * 0.5)
      local hang_pts = math.max(0, math.floor(hangover_sec / math.max(0.001, dt) + 0.5))
      local min_seg_pts = math.max(1, math.floor(min_seg_sec / math.max(0.001, dt) + 0.5))
      local merge_gap_pts = math.max(0, math.floor(merge_gap_sec / math.max(0.001, dt) + 0.5))

      local segments = {}
      local active = false
      local seg_start = 0
      local seg_end = 0
      local hang_left = 0

      for i = 1, #points_in do
        local stv = tonumber(points_in[i] and points_in[i].st)
        local mv = tonumber(points_in[i] and points_in[i].m)
        local open_hit = stv and mv and stv >= gate_open and mv >= (speech_gate - 3.0)
        local keep_hit = stv and mv and stv >= gate_close and mv >= (speech_gate - 3.0)

        if not active then
          if open_hit then
            active = true
            seg_start = i
            seg_end = i
            hang_left = hang_pts
          end
        else
          if keep_hit then
            seg_end = i
            hang_left = hang_pts
          elseif hang_left > 0 then
            seg_end = i
            hang_left = hang_left - 1
          else
            segments[#segments + 1] = { s = seg_start, e = seg_end }
            active = false
            if open_hit then
              active = true
              seg_start = i
              seg_end = i
              hang_left = hang_pts
            end
          end
        end
      end
      if active and seg_end >= seg_start then
        segments[#segments + 1] = { s = seg_start, e = seg_end }
      end

      local filtered = {}
      for i = 1, #segments do
        local seg = segments[i]
        if (seg.e - seg.s + 1) >= min_seg_pts then
          filtered[#filtered + 1] = seg
        end
      end
      if #filtered == 0 then return nil, nil, speech_gate, 0, 0 end

      local merged = { filtered[1] }
      for i = 2, #filtered do
        local prev = merged[#merged]
        local cur = filtered[i]
        local gap_pts = cur.s - prev.e - 1
        if gap_pts <= merge_gap_pts then
          prev.e = math.max(prev.e, cur.e)
        else
          merged[#merged + 1] = cur
        end
      end

      local sum_e = 0.0
      local count_e = 0
      for i = 1, #merged do
        local seg = merged[i]
        for j = seg.s, seg.e do
          local e = tonumber(points_in[j] and points_in[j].m_energy)
          if e and e > 0.0 then
            sum_e = sum_e + e
            count_e = count_e + 1
          end
        end
      end

      if count_e < 3 then return nil, nil, speech_gate, count_e, #merged end
      local dlufs = EnergyToLufs(sum_e / count_e)
      local dratio = 100.0 * (1.0 - (count_e / math.max(1, #points_in)))
      return dlufs, dratio, speech_gate, count_e, #merged
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

    local integrated_meter = integrated
    if i_src_latest ~= nil then
      integrated_meter = i_src_latest
    end

    local dlg_lufs, dlg_ratio, dlg_gate, dlg_count, dlg_segments = ComputeSpeechGatedDialogue(points, gate_db)
    local use_dialogue = ((dialogue_cfg and dialogue_cfg.method_key) == "speech_gate") and (dlg_lufs ~= nil)
    integrated = use_dialogue and dlg_lufs or integrated_meter

    return {
      integrated = integrated,
      integrated_meter = integrated_meter,
      peak = peak,
      lra = lra,
      short_max = short_max,
      short_current = last_point and (last_point.st or -120.0) or -120.0,
      side_current = last_point and (last_point.s or -120.0) or -120.0,
      side_max = side_max,
      momentary_current = last_point and (last_point.m or -120.0) or -120.0,
      momentary_max = momentary_max,
      gated_ratio = gated_ratio,
      gate_reference = gate_db,
      dialogue_lufs = dlg_lufs,
      dialogue_gated_ratio = dlg_ratio,
      dialogue_gate_lufs = dlg_gate,
      dialogue_count = dlg_count,
      dialogue_segments = dlg_segments,
      dialogue_mode_used = use_dialogue
    }
  end

  return {
    BuildSummary = BuildSummary
  }
end

return M
