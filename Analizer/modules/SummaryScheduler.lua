local M = {}

function M.Reset(source_state)
  source_state.summary_last_update = nil
  source_state.summary_dirty = true
end

function M.MarkDirty(source_state)
  source_state.summary_dirty = true
end

function M.ShouldRefresh(source_state, now, interval_sec, force)
  local interval = math.max(0.0, interval_sec or 0.25)
  local last_update = source_state.summary_last_update
  local due = last_update == nil or ((now or 0.0) - last_update) >= interval
  if force or source_state.summary == nil or (source_state.summary_dirty and due) then
    source_state.summary_last_update = now or 0.0
    source_state.summary_dirty = false
    return true
  end
  return false
end

function M.Refresh(source_state, now, interval_sec, force, build_fn)
  if not M.ShouldRefresh(source_state, now, interval_sec, force) then
    return false
  end
  source_state.summary = build_fn()
  return true
end

return M
