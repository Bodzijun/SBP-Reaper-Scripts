local M = {}

function M.Reset(state, hold_ref)
  state.live_transport_phase = "STOPPED"
  state.live_was_playing = false
  state.live_last_play_pos = nil
  state.pending_rewrite_pos = nil
  state.live_rewrite_end = nil
  state.live_hold = true
  state.live_hold_ref = hold_ref
end

function M.Update(state, play_pos, is_playing)
  local event = {
    phase = state.live_transport_phase or "STOPPED",
    playback_started = false,
    should_record = false,
    rewrite_pos = nil,
    rewind_from = nil
  }

  local previous_pos = state.live_last_play_pos
  event.playback_started = is_playing and not state.live_was_playing
  state.live_was_playing = is_playing

  if not is_playing and previous_pos ~= nil and math.abs(play_pos - previous_pos) > 0.01 then
    state.pending_rewrite_pos = play_pos
  end

  if is_playing and state.pending_rewrite_pos ~= nil then
    event.rewrite_pos = state.pending_rewrite_pos
    state.pending_rewrite_pos = nil
  end

  if state.live_hold then
    if state.live_hold_ref == nil then
      state.live_hold_ref = play_pos
    end
    local moved = is_playing or math.abs(play_pos - (state.live_hold_ref or play_pos)) > 0.01
    if moved then
      state.live_hold = false
      state.live_hold_ref = nil
    else
      state.live_last_play_pos = play_pos
      state.live_transport_phase = "STOPPED"
      event.phase = state.live_transport_phase
      return event
    end
  end

  if not is_playing then
    state.live_last_play_pos = play_pos
    state.live_transport_phase = "STOPPED"
    event.phase = state.live_transport_phase
    return event
  end

  if previous_pos ~= nil and play_pos < (previous_pos - 0.002) then
    event.rewind_from = previous_pos
    state.live_transport_phase = "REWRITING"
  elseif event.playback_started then
    state.live_transport_phase = "STARTING"
  elseif state.live_rewrite_end ~= nil then
    state.live_transport_phase = "REWRITING"
  else
    state.live_transport_phase = "RECORDING"
  end

  state.live_last_play_pos = play_pos
  event.phase = state.live_transport_phase
  event.should_record = true
  return event
end

function M.FinishRewriteIfPassed(state, play_pos, margin_sec)
  if state.live_rewrite_end and play_pos > (state.live_rewrite_end + (margin_sec or 0.0)) then
    state.live_rewrite_end = nil
    state.live_transport_phase = "RECORDING"
    return true
  end
  return false
end

return M
