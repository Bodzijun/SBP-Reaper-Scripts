---@diagnostic disable: undefined-field, need-check-nil
-- Offline print: bounces the source track (with ReaSciFiEngine on it) to a
-- dedicated stem track, exactly like ReaWhoosh BounceToNewTrack.
-- Respects time selection when present; otherwise uses cursor + tail-derived duration.

local Printer = {}
local r = reaper

local STEM_STEREO   = 'ReaSciFi Renders'
local STEM_SURROUND = 'ReaSciFi Renders (Surround)'

local function formatBatchName(prefix, index)
  local safe_prefix = (prefix and prefix ~= '') and prefix or 'ReaSciFi'
  return string.format('%s_%03d', safe_prefix, index)
end

local function findTrackByName(name)
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    local _, tname = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    if tname == name then return track end
  end
  return nil
end

local function hasRangeCollision(track, ts_start, ts_end)
  if not track or ts_start == nil or ts_end == nil then
    return false
  end
  local item_count = r.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local it = r.GetTrackMediaItem(track, i)
    local ipos = r.GetMediaItemInfo_Value(it, 'D_POSITION')
    local ilen = r.GetMediaItemInfo_Value(it, 'D_LENGTH')
    if math.abs(ipos - ts_start) < 0.01 and math.abs((ipos + ilen) - ts_end) < 0.01 then
      return true
    end
  end
  return false
end

local function createUniqueStemTrack(stem_name)
  local suffix = 2
  while findTrackByName(stem_name .. '_' .. suffix) do suffix = suffix + 1 end
  local new_name = stem_name .. '_' .. suffix
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  local new_track = r.GetTrack(0, idx)
  r.GetSetMediaTrackInfo_String(new_track, 'P_NAME', new_name, true)
  return new_track
end

local function getRenderRange(state)
  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_end > ts_start then
    return ts_start, ts_end
  end

  local cursor = r.GetCursorPosition()
  local tail = state and state.synth and state.synth.tail or 0
  local mode = state and state.synth and state.synth.mode or 1

  if mode == 0 then
    -- One-shot fallback: short range close to note-sized trigger duration.
    local pre_roll = 0.01
    local one_shot_dur = math.max(0.12, math.min(1.0, 0.12 + tail * 0.55))
    local start_pos = math.max(0, cursor - pre_roll)
    local end_pos = start_pos + pre_roll + one_shot_dur
    return start_pos, end_pos
  end

  local dur = 2.0 + tail * 5.0
  return cursor, cursor + dur
end

local function hasTimeSelection()
  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return ts_end > ts_start
end

-- Finds a unique stem track name by appending _2, _3 etc. if one already has an
-- item at exactly the same time-selection range.
local function findOrCreateStemTrack(stem_name, ts_start, ts_end, opts)
  opts = opts or {}
  if opts.fixed_stem_track then
    return opts.fixed_stem_track
  end

  if opts.collision_policy == 'always-new-track' then
    return createUniqueStemTrack(stem_name)
  end

  local stem_track = findTrackByName(stem_name)
  local policy = opts.collision_policy or 'ask'

  -- Check if an existing bounce item already occupies this exact range.
  if stem_track and ts_start and ts_end then
    if hasRangeCollision(stem_track, ts_start, ts_end) then
      if policy == 'reuse' then
        return stem_track
      elseif policy == 'new-track' then
        return createUniqueStemTrack(stem_name)
      else
        local res = r.ShowMessageBox(
          'Bounce file already exists in this time selection.\n\nRender to a new track?\n\n(Yes = new track, No = cancel)',
          'Warning', 4)
        if res ~= 6 then return nil end
        return createUniqueStemTrack(stem_name)
      end
    end
    return stem_track
  end

  if stem_track then return stem_track end

  -- Create fresh stem track at bottom.
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  stem_track = r.GetTrack(0, idx)
  r.GetSetMediaTrackInfo_String(stem_track, 'P_NAME', stem_name, true)
  return stem_track
end

local function renameItemTake(item, name)
  if not item or not name or name == '' then return end
  local take = r.GetActiveTake(item)
  if take then
    r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', name, true)
  end
end

local function clampInt(v, lo, hi)
  v = math.floor(tonumber(v) or lo)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function clampNum(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function resolveMidiTrigger(cfg, rand_index)
  cfg = cfg or {}
  local rand_enabled = cfg.randomize_enabled == true

  local pitch = clampInt(cfg.pitch, 69, 127)
  local pmin = clampInt(cfg.pitch_min, 0, 127)
  local pmax = clampInt(cfg.pitch_max, 0, 127)
  if pmin > pmax then pmin, pmax = pmax, pmin end

  local velocity = clampInt(cfg.velocity, 1, 127)
  local vmin = clampInt(cfg.velocity_min, 1, 127)
  local vmax = clampInt(cfg.velocity_max, 1, 127)
  if vmin > vmax then vmin, vmax = vmax, vmin end

  local len_ms = clampInt(cfg.length_ms, 5, 300)
  local lmin = clampInt(cfg.length_min_ms, 5, 300)
  local lmax = clampInt(cfg.length_max_ms, 5, 300)
  if lmin > lmax then lmin, lmax = lmax, lmin end

  if rand_enabled then
    if cfg.pitch_randomize == true then
      pitch = math.random(pmin, pmax)
    end
    if cfg.velocity_randomize == true then
      velocity = math.random(vmin, vmax)
    end
    if cfg.length_randomize == true then
      len_ms = math.random(lmin, lmax)
    end
  end

  return {
    pitch = pitch,
    velocity = velocity,
    length_ms = len_ms,
    auto_fit_range = cfg.auto_fit_range == true,
    rand_index = rand_index
  }
end

local function computeOneShotAutoFitDurationSec(state, midi_trigger)
  local tail = state and state.synth and tonumber(state.synth.tail) or 0
  local note_len_sec = clampNum((tonumber((midi_trigger or {}).length_ms) or 30) / 1000.0, 0.005, 0.300)
  local pre_roll = 0.01
  local post_tail = 0.06 + tail * 0.45
  return clampNum(pre_roll + note_len_sec + post_tail, 0.08, 1.20)
end

local function createOneShotTriggerItem(track, render_start, render_end, midi_trigger)
  if not track then
    return nil, 'Missing source track for one-shot trigger.'
  end

  local item_end = math.min(render_end, render_start + 0.12)
  if item_end <= render_start then
    item_end = render_start + 0.01
  end

  local item = r.CreateNewMIDIItemInProj(track, render_start, item_end, false)
  if not item then
    return nil, 'Failed to create temporary MIDI trigger item.'
  end

  local take = r.GetActiveTake(item)
  if not take then
    r.DeleteTrackMediaItem(track, item)
    return nil, 'Failed to access MIDI take for one-shot trigger.'
  end

  local note_start = r.MIDI_GetPPQPosFromProjTime(take, render_start)
  local trig = midi_trigger or {}
  local note_len_sec = clampNum((tonumber(trig.length_ms) or 30) / 1000.0, 0.005, 0.300)
  local note_end_time = math.min(item_end, render_start + note_len_sec)
  local note_end = r.MIDI_GetPPQPosFromProjTime(take, note_end_time)
  if note_end <= note_start then
    note_end = note_start + 1
  end

  local midi_pitch = clampInt(trig.pitch, 0, 127)
  local midi_vel = clampInt(trig.velocity, 1, 127)
  local inserted = r.MIDI_InsertNote(take, false, false, note_start, note_end, 0, midi_pitch, midi_vel, false)
  if not inserted then
    r.DeleteTrackMediaItem(track, item)
    return nil, 'Failed to insert one-shot trigger note.'
  end

  r.MIDI_Sort(take)
  return item
end

-- Main print function. Returns ok (bool), message (string).
function Printer.Print(state, opts)
  opts = opts or {}
  if r.CountTracks(0) == 0 then
    return false, 'Project has no tracks.'
  end

  -- Resolve source track.
  local source_track
  if state.setup.follow_selected_track then
    source_track = r.GetSelectedTrack(0, 0)
  end
  if not source_track and state.setup.target_track_name ~= '' then
    source_track = findTrackByName(state.setup.target_track_name)
  end
  if not source_track then
    return false, 'No source track. Select a track or set Target Track Name.'
  end

  local render_start = tonumber(opts.render_start)
  local render_end = tonumber(opts.render_end)
  if not render_start or not render_end or render_end <= render_start then
    render_start, render_end = getRenderRange(state)
  end

  local midi_trigger = nil
  if state.synth.mode == 0 then
    midi_trigger = opts.midi_trigger or resolveMidiTrigger(opts.midi_trigger_cfg, opts.midi_trigger_randomize_index)
    if midi_trigger.auto_fit_range and not hasTimeSelection() then
      local dur = computeOneShotAutoFitDurationSec(state, midi_trigger)
      render_end = render_start + dur
    end
  end

  local is_surround = state.synth.output_mode == 1
  local stem_name   = is_surround and STEM_SURROUND or STEM_STEREO
  local desired_ch  = is_surround and 6 or 2

  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()

  local stem_track = findOrCreateStemTrack(stem_name, render_start, render_end, opts)
  if not stem_track then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock('ReaSciFi Print cancelled', -1)
    return false, 'Print cancelled.'
  end

  r.SetMediaTrackInfo_Value(stem_track,   'I_NCHAN', desired_ch)
  r.SetMediaTrackInfo_Value(source_track, 'I_NCHAN', desired_ch)

  r.GetSet_LoopTimeRange(true, false, render_start, render_end, false)
  r.SetOnlyTrackSelected(source_track)
  r.UpdateArrange()

  local one_shot_trigger_item = nil
  if state.synth.mode == 0 then
    local trig_err
    one_shot_trigger_item, trig_err = createOneShotTriggerItem(source_track, render_start, render_end, midi_trigger)
    if not one_shot_trigger_item then
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock('ReaSciFi Print cancelled', -1)
      return false, trig_err or 'Failed to create one-shot render trigger.'
    end
  end

  -- Snapshot track list before render so we can capture the new render track.
  local pre_tracks = {}
  for i = 0, r.CountTracks(0) - 1 do
    pre_tracks[r.GetTrack(0, i)] = true
  end

  local render_cmd = is_surround and 41720 or 41719  -- stems: multichannel / stereo
  r.Main_OnCommand(render_cmd, 0)

  -- Move items from newly-created render track(s) into our stem track.
  local new_tracks = {}
  local moved_items = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if not pre_tracks[tr] and tr ~= stem_track then
      table.insert(new_tracks, tr)
    end
  end

  for _, tr in ipairs(new_tracks) do
    for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(tr, i)
      r.MoveMediaItemToTrack(item, stem_track)
      moved_items[#moved_items + 1] = item
    end
  end
  for i = #new_tracks, 1, -1 do
    r.DeleteTrack(new_tracks[i])
  end

  if one_shot_trigger_item then
    r.DeleteTrackMediaItem(source_track, one_shot_trigger_item)
  end

  -- Keep source selected so follow-selected auto-sync does not attach JSFX to stem tracks.
  r.SetOnlyTrackSelected(source_track)

  if opts.item_name and opts.item_name ~= '' then
    for i = 1, #moved_items do
      renameItemTake(moved_items[i], opts.item_name)
    end
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock('ReaSciFi Print to stem track', 0)

  local msg = 'Printed  ' .. (is_surround and '5.1' or 'Stereo') .. '  →  ' .. stem_name
  if opts.item_name and opts.item_name ~= '' then
    msg = msg .. ' [' .. opts.item_name .. ']'
  end
  return true, msg, #moved_items
end

function Printer.PrintBatch(state, opts)
  opts = opts or {}
  local count = math.floor(tonumber(opts.count) or 1)
  if count < 1 then count = 1 end
  if count > 128 then count = 128 end
  local sequential_gap_sec = math.max(0, tonumber(opts.sequential_gap_sec) or 0.02)

  local prefix = opts.prefix or 'ReaSciFi'
  local randomize_each = opts.randomize_each == true
  local randomize_fn = opts.randomize_fn
  local sync_fn = opts.sync_fn

  local rendered = 0
  local failed = 0

  local is_surround = state.synth.output_mode == 1
  local stem_name = is_surround and STEM_SURROUND or STEM_STEREO
  local base_start, base_end = getRenderRange(state)
  local render_len = math.max(0.01, (base_end or 0) - (base_start or 0))
  local has_ts = hasTimeSelection()

  local res = r.ShowMessageBox(
    'Batch render mode:\n\nYes = each render to a NEW track\nNo = all renders sequentially to ONE track\nCancel = abort',
    'Batch Render Mode', 3)
  if res == 2 then
    return false, 'Batch render cancelled.'
  end

  local collision_policy = (res == 6) and 'always-new-track' or 'reuse'
  local fixed_stem_track = nil
  if collision_policy == 'reuse' then
    fixed_stem_track = findOrCreateStemTrack(stem_name, base_start, base_end, { collision_policy = 'reuse' })
    if not fixed_stem_track then
      return false, 'Batch render cancelled.'
    end
  end

  local sequence_cursor = base_start

  for i = 1, count do
    if randomize_each and type(randomize_fn) == 'function' then
      randomize_fn(i)
      if type(sync_fn) == 'function' then
        sync_fn()
      end
    end

    local item_name = formatBatchName(prefix, i)
    local midi_trigger = nil
    if state.synth.mode == 0 then
      midi_trigger = resolveMidiTrigger(opts.midi_trigger_cfg, i)
    end
    local item_start = base_start
    local item_end = base_end
    local item_len = render_len
    if midi_trigger and midi_trigger.auto_fit_range and not has_ts then
      item_len = computeOneShotAutoFitDurationSec(state, midi_trigger)
    end
    if collision_policy == 'reuse' then
      item_start = sequence_cursor
      item_end = item_start + item_len
      sequence_cursor = item_end + sequential_gap_sec
    else
      item_end = item_start + item_len
    end

    local ok = Printer.Print(state, {
      item_name = item_name,
      collision_policy = collision_policy,
      fixed_stem_track = fixed_stem_track,
      midi_trigger_cfg = opts.midi_trigger_cfg,
      midi_trigger = midi_trigger,
      midi_trigger_randomize_index = i,
      render_start = item_start,
      render_end = item_end
    })
    if ok then
      rendered = rendered + 1
    else
      failed = failed + 1
    end
  end

  if failed > 0 then
    return false, string.format('Batch render done: %d ok, %d failed.', rendered, failed)
  end
  return true, string.format('Batch render done: %d items (%s_###).', rendered, prefix)
end

return Printer
