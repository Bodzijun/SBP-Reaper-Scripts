local M = {}

function M.Trim(points, now_t, history_sec)
  local min_t = now_t - history_sec
  local count = #points
  local first_keep = 1
  while first_keep <= count and (points[first_keep].t or 0.0) < min_t do
    first_keep = first_keep + 1
  end
  if first_keep <= 1 then return points end

  local write_at = 1
  for read_at = first_keep, count do
    points[write_at] = points[read_at]
    write_at = write_at + 1
  end
  for i = write_at, count do
    points[i] = nil
  end
  return points
end

function M.ClearAhead(points, cursor_t, ahead_sec)
  local out = {}
  local t0 = cursor_t or 0.0
  local t1 = t0 + math.max(0.0, ahead_sec or 0.0)
  for i = 1, #points do
    local point = points[i]
    local t = point.t or -1e9
    if t < t0 or t > t1 then
      out[#out + 1] = point
    end
  end
  return out
end

function M.InsertSorted(points, point)
  local insert_at = #points + 1
  for i = #points, 1, -1 do
    if (points[i].t or -1e9) <= (point.t or -1e9) then
      insert_at = i + 1
      break
    end
    insert_at = i
  end
  table.insert(points, insert_at, point)
end

function M.ResetSourceWrite(source_state)
  source_state.live_write_seg = nil
  source_state.last_live_write_t = nil
end

function M.BeginPass(state, start_t, integrated_settle_sec)
  state.live_segment_id = (state.live_segment_id or 0) + 1
  state.live_segments = state.live_segments or {}
  state.live_segments[#state.live_segments + 1] = {
    id = state.live_segment_id,
    start_t = start_t or 0.0
  }
  M.ResetSourceWrite(state.source_a)
  M.ResetSourceWrite(state.source_b)
  return state.live_segment_id
end

function M.PrepareWrite(source_state, active_seg, sample_t, cursor_t, erase_ahead_sec)
  local replacing = source_state.live_write_seg == active_seg and source_state.last_live_write_t ~= nil
  if not replacing then
    source_state.live_write_seg = active_seg
  end

  local replace_t0 = replacing and math.min(source_state.last_live_write_t, sample_t) or nil
  local replace_t1 = replacing and math.max(source_state.last_live_write_t, sample_t) or nil
  local erase_t0 = cursor_t or 0.0
  local erase_t1 = erase_t0 + math.max(0.0, erase_ahead_sec or 0.0)
  local points = source_state.points
  local out = {}

  -- One history pass handles both operations: old-pass replacement over the
  -- traversed interval and the empty erase strip strictly right of cursor.
  for i = 1, #points do
    local point = points[i]
    local t = point.t or -1e9
    local inside_erase = t >= erase_t0 and t <= erase_t1
    local old_in_replaced_range = replacing
      and t >= replace_t0 and t <= replace_t1
      and point.seg ~= active_seg
    if not inside_erase and not old_in_replaced_range then
      out[#out + 1] = point
    end
  end

  source_state.last_live_write_t = sample_t
  source_state.points = out
end

return M
