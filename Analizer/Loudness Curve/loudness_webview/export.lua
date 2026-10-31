local M = {}

function M.parse(value)
  local start_text, length_text, raw = value:match("^([%d%.]+)|([%d%.]+)|(.+)$")
  local start, length = tonumber(start_text), tonumber(length_text)
  if not start or not length or start < 0 or length <= 0 or length > 86400 then
    return nil, "Invalid render start or duration"
  end
  local points, previous = {}, -1
  for pair in raw:gmatch("[^;]+") do
    local t, gain = pair:match("^([%d%.]+),([%d%.%-]+)$")
    t, gain = tonumber(t), tonumber(gain)
    if not t or not gain or t <= previous or t < 0 or t > length + 0.01 or gain ~= gain or math.abs(gain) == math.huge then
      return nil, "Invalid or unordered correction point"
    end
    points[#points + 1] = {time = t, gain = gain}
    previous = t
    if #points > 200002 then return nil, "Too many correction points" end
  end
  if #points < 2 or points[1].time > 0.01 or points[#points].time < length - 0.01 then
    return nil, "Correction must cover the complete render range"
  end
  return {start = start, length = length, points = points}
end

local function find_printmaster(r, profile)
  if profile.destination_guid then
    for index = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, index)
      if r.GetTrackGUID(track) == profile.destination_guid then return track end
    end
    return nil, 'The destination track no longer exists. Refresh tracks and choose it again.'
  end
  local base = (profile.bus_printmaster or "PRINTMASTER"):match("^%s*(.-)%s*$")
  local suffix = (profile.bus_suffix or ""):match("^%s*(.-)%s*$")
  local expected = suffix ~= "" and (base .. " " .. suffix):lower() or base:lower()
  local fallback, exact, fallback_duplicate
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local _, name = r.GetTrackName(track)
    local normalized = (name or ""):match("^%s*(.-)%s*$"):lower()
    if normalized == expected then
      if exact then return nil, "Multiple PRINTMASTER tracks have the same name" end
      exact = track
    elseif normalized == base:lower() then
      if fallback then fallback_duplicate = true end
      fallback = track
    end
  end
  if exact then return exact end
  if fallback_duplicate then return nil, "Multiple PRINTMASTER tracks have the same name" end
  if fallback then return fallback end
  return nil, "PRINTMASTER track was not found"
end

-- The export range has no underlying points. Use one reference level for
-- the whole correction, rather than turning a constant gain into a ramp
-- toward a guard point left just outside the automation item.
local function reference_base(r, envelope, mode, start, finish)
  local _, value = r.Envelope_Evaluate(envelope, start, 48000, 256)
  local base = value or 1
  if mode ~= 0 then base = r.ScaleFromEnvelopeMode(mode, base) end
  assert(base > 0 and base < math.huge, "Cannot export over a muted or nonfinite reference envelope")
  local before, after = false, false
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time = r.GetEnvelopePoint(envelope, index)
    if ok then before = before or time < start; after = after or time > finish end
  end
  if before and after then
    local _, last = r.Envelope_Evaluate(envelope, finish, 48000, 256)
    if last and mode ~= 0 then last = r.ScaleFromEnvelopeMode(mode, last) end
    assert(last and math.abs(last - base) <= math.max(1, base) * .0000001,
      "Underlying PRINTMASTER points outside the range create a ramp. Use a flat original export range.")
  end
  return base
end

local function existing_item(r, envelope, correction, replace)
  local found, base
  for index = 0, r.CountAutomationItems(envelope) - 1 do
    local start = r.GetSetAutomationItemInfo(envelope, index, 'D_POSITION', 0, false)
    local length = r.GetSetAutomationItemInfo(envelope, index, 'D_LENGTH', 0, false)
    if start < correction.start + correction.length and start + length > correction.start then
      local _, name = r.GetSetAutomationItemInfo_String(envelope, index, 'P_POOL_NAME', '', false)
      local stored = tonumber((name or ''):match('^SBP_LoudnessCurve:([%d%.eE+%-]+)'))
      local source_i = tonumber((name or ''):match('|i=([%d%.eE+%-]+)'))
      local source_name = (name or ''):match('|source=([^|]*)')
      local source_key = (name or ''):match('|key=([^|]*)')
      assert(not source_key or source_key == correction.source_key,
        'Previous export uses a different source file. Its automation is protected.')
      assert(not source_i or not correction.source_i or (math.abs(source_i-correction.source_i)<.01 and source_name==correction.source_name),
        'Previous export uses a different original report. Load its original audio and report before replacing or measuring.')
      assert(not stored or stored > 0 and stored < math.huge, 'Invalid stored reference level')
      assert(not found and math.abs(start - correction.start) < .001 and math.abs(length - correction.length) < .001,
        'Existing automation must match the complete export range; partial or multiple overlaps are protected')
      assert(replace or stored, 'PRINTMASTER already has an automation item in this range. Enable Replace existing curve to overwrite it.')
      assert(stored or name == '', 'This automation item belongs to another tool; remove it manually before exporting')
      local pool = r.GetSetAutomationItemInfo(envelope, index, 'D_POOL_ID', 0, false)
      for other = 0, r.CountAutomationItems(envelope) - 1 do
        assert(other == index or r.GetSetAutomationItemInfo(envelope, other, 'D_POOL_ID', 0, false) ~= pool,
          'This curve shares a pool with another item. Unpool it before replacing.')
      end
      found, base = index, stored
    end
  end
  return found, base
end

-- Reduce in the actual REAPER envelope coordinate, not in dB: linear dB
-- ramps are not necessarily linear after fader scaling. Preview and export
-- must use this same point set. Check original knots and quarter-segments.
function M.reduce(r, mode, base, points, tolerance)
  tolerance = tolerance or .005
  local values = {}
  for index, point in ipairs(points) do
    local linear = base * 10 ^ (point.gain / 20)
    assert(linear > 0 and linear < math.huge, "Correction exceeds numeric envelope range")
    values[index] = mode ~= 0 and r.ScaleToEnvelopeMode(mode, linear) or linear
  end
  local function linear(value)
    return mode ~= 0 and r.ScaleFromEnvelopeMode(mode, value) or value
  end
  local keep = {[1]=true, [#points]=true}
  -- Paired millisecond anchors encode hard/step boundaries in the payload.
  for i=2,#points do
    if points[i].time-points[i-1].time<=.002001 then keep[i-1]=true;keep[i]=true end
  end
  local anchors={};for i=1,#points do if keep[i] then anchors[#anchors+1]=i end end
  local stack={};for i=2,#anchors do stack[#stack+1]={anchors[i-1],anchors[i]} end
  while #stack>0 do
    local span=table.remove(stack);local a,b=span[1],span[2]
    if b>a+1 then
      local worst, split=0,a+1
      for i=a,b-1 do
        for sample=0,3 do
          local f=sample/4
          local time=points[i].time+(points[i+1].time-points[i].time)*f
          local actual=linear(values[i]+(values[i+1]-values[i])*f)
          local fraction=(time-points[a].time)/(points[b].time-points[a].time)
          local predicted=linear(values[a]+(values[b]-values[a])*fraction)
          local error=actual>0 and predicted>0 and math.abs(20*math.log(predicted/actual)/math.log(10)) or math.huge
          if error>worst then worst=error;split=math.max(a+1,math.min(b-1,i+(sample>0 and 1 or 0))) end
        end
      end
      if worst>tolerance then
        -- Avoid quadratic scans when the worst error repeatedly hugs an end.
        if split-a<(b-a)/8 or b-split<(b-a)/8 then split=math.floor((a+b)/2) end
        keep[split]=true;stack[#stack+1]={a,split};stack[#stack+1]={split,b}
      end
    end
  end
  local reduced, scaled={},{}
  for i,point in ipairs(points) do if keep[i] then reduced[#reduced+1]=point;scaled[#scaled+1]=values[i] end end
  return reduced,scaled
end

-- Project the same reduced, scaled, linear-segment envelope that apply() inserts.
-- Divide by the fixed reference level already baked into the original render.
local function project_gain(r, correction, mode, base)
  local reduced, scaled = M.reduce(r, mode, base, correction.points)
  assert(correction.length <= 21600, "Audio preview supports render ranges up to six hours")
  local flat=true;for _,point in ipairs(correction.points) do if point.gain~=correction.points[1].gain then flat=false;break end end
  if flat then
    local value=mode~=0 and r.ScaleFromEnvelopeMode(mode,scaled[1]) or scaled[1]
    assert(value>0 and value/base<math.huge,'Cannot project a muted or nonfinite envelope')
    return {{time=0,linear=value/base},{time=correction.length,linear=value/base}}
  end
  local points, cursor = {}, 2
  local times = {}; for _, point in ipairs(reduced) do times[#times + 1] = point.time end
  for index = 0, math.floor(correction.length * 100) do times[#times + 1] = index / 100 end
  times[#times + 1] = correction.length
  table.sort(times)
  local previous = -1
  for _, time in ipairs(times) do
    if time > previous + .0000001 then
      while cursor < #reduced and reduced[cursor].time < time do cursor = cursor + 1 end
      local a, b = reduced[cursor - 1], reduced[cursor]
      local f = math.max(0, math.min(1, (time - a.time) / (b.time - a.time)))
      local value = scaled[cursor - 1] + (scaled[cursor] - scaled[cursor - 1]) * f
      if mode ~= 0 then value = r.ScaleFromEnvelopeMode(mode, value) end
      assert(base > 0 and value > 0 and value / base < math.huge, "Cannot project a muted or nonfinite envelope")
      points[#points + 1] = {time = time, linear = value / base}
      previous = time
    end
  end
  return points
end

function M.project(r, profile, correction)
  local track, err = find_printmaster(r, profile)
  assert(track, err)
  local envelope = r.GetTrackEnvelopeByChunkName(track, "<VOLENV2") or r.GetTrackEnvelopeByChunkName(track, "<VOLENV")
  assert(envelope, "Enable the destination track Volume envelope before measuring")
  local existing, stored_base = existing_item(r, envelope, correction, false)
  assert(not existing or stored_base, 'Remove the old untagged export before measuring its replacement')
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time = r.GetEnvelopePoint(envelope, index)
    assert(not ok or time < correction.start or time > correction.start + correction.length,
      "Existing PRINTMASTER points overlap this range")
  end
  local mode = r.GetEnvelopeScalingMode(envelope)
  local base = stored_base or reference_base(r, envelope, mode, correction.start, correction.start + correction.length)
  return project_gain(r, correction, mode, base)
end

-- File-only gain preview. Destination automation is already baked into the WAV;
-- it neither blocks this read-only model nor gets applied a second time.
-- Reuse scaling/reference when available to retain export interpolation fidelity.
function M.project_file(r, profile, correction)
  local mode, base = 0, 1
  local track = find_printmaster(r, profile)
  local envelope = track and (r.GetTrackEnvelopeByChunkName(track, "<VOLENV2") or r.GetTrackEnvelopeByChunkName(track, "<VOLENV"))
  if envelope then
    mode = r.GetEnvelopeScalingMode(envelope)
    local ok, _, stored_base = pcall(existing_item, r, envelope, correction, false)
    if ok and stored_base then base = stored_base
    else
      local _, value = r.Envelope_Evaluate(envelope, correction.start, 48000, 256)
      if value and mode ~= 0 then value = r.ScaleFromEnvelopeMode(mode, value) end
      if value and value > 0 and value < math.huge then base = value end
    end
  end
  return project_gain(r, correction, mode, base)
end

function M.apply(r, project, profile, correction, replace)
  local track, track_error = find_printmaster(r, profile)
  if not track then return nil, track_error end
  local envelope = r.GetTrackEnvelopeByChunkName and r.GetTrackEnvelopeByChunkName(track, "<VOLENV2")
    or r.GetTrackEnvelopeByChunkName and r.GetTrackEnvelopeByChunkName(track, "<VOLENV")
    or r.GetTrackEnvelopeByName(track, "Volume")
  if not envelope then return nil, "Enable the destination track Volume envelope before exporting" end
  local begin_time, finish_time = correction.start, correction.start + correction.length
  local item_ok, item_index, stored_base = pcall(existing_item, r, envelope, correction, replace)
  if not item_ok then return nil, item_index end
  if item_index and not replace then return nil, 'Enable Replace existing curve to overwrite the previous export' end
  local replacing = item_index ~= nil
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, position = r.GetEnvelopePoint(envelope, index)
    if ok and position >= begin_time and position <= finish_time then
      return nil, "PRINTMASTER already has volume points in this range"
    end
  end
  local mode = r.GetEnvelopeScalingMode(envelope)
  local chunk_ok, original_chunk = r.GetEnvelopeStateChunk(envelope, "", false)
  if not chunk_ok then return nil, "Cannot read PRINTMASTER envelope visibility" end
  local base_ok, base = true, stored_base
  if item_index and not stored_base then
    -- Legacy exports have no reference tag. Mute only this item briefly to
    -- evaluate its underlying level, and immediately restore its mute state.
    local muted = r.GetSetAutomationItemInfo(envelope, item_index, 'D_MUTE', 0, false)
    r.GetSetAutomationItemInfo(envelope, item_index, 'D_MUTE', 1, true)
    base_ok, base = pcall(reference_base, r, envelope, mode, begin_time, finish_time)
    r.GetSetAutomationItemInfo(envelope, item_index, 'D_MUTE', muted, true)
  elseif not base then base_ok, base = pcall(reference_base, r, envelope, mode, begin_time, finish_time) end
  if not base_ok then return nil, base end
  local reduced_ok, reduced, values = pcall(M.reduce, r, mode, base, correction.points)
  if not reduced_ok then return nil, reduced end
  local visible_chunk, changed = original_chunk:gsub("(\nVIS[ \t]+)[%-%d]+[ \t]+[%-%d]+", function(prefix) return prefix .. "1 1" end, 1)
  if changed == 0 then return nil, "PRINTMASTER envelope visibility field was not found" end
  local active_changed
  visible_chunk, active_changed = visible_chunk:gsub("(\nACT[ \t]+)[%-%d]+", function(prefix) return prefix .. "1" end, 1)
  if active_changed == 0 then
    visible_chunk = visible_chunk:gsub("(\nVIS[ \t]+)", "\nACT 1 -1%1", 1)
  end
  r.Undo_BeginBlock()
  if visible_chunk ~= original_chunk and not r.SetEnvelopeStateChunk(envelope, visible_chunk, false) then
    r.Undo_EndBlock("SBP Loudness Curve: export failed", -1)
    return nil, "Cannot activate and show PRINTMASTER Volume envelope"
  end
  item_index = item_index or r.InsertAutomationItem(envelope, -1, begin_time, correction.length)
  if item_index < 0 then
    if visible_chunk ~= original_chunk then r.SetEnvelopeStateChunk(envelope, original_chunk, false) end
    r.Undo_EndBlock("SBP Loudness Curve: export failed", -1)
    return nil, "Cannot create PRINTMASTER automation item"
  end
  r.GetSetAutomationItemInfo(envelope, item_index, "D_LOOPSRC", 0, true)
  r.GetSetAutomationItemInfo(envelope, item_index, "D_STARTOFFS", 0, true)
  r.GetSetAutomationItemInfo(envelope, item_index, "D_PLAYRATE", 1, true)
  r.GetSetAutomationItemInfo(envelope, item_index, "D_BASELINE", .5, true)
  r.GetSetAutomationItemInfo(envelope, item_index, "D_AMPLITUDE", 1, true)
  r.GetSetAutomationItemInfo(envelope, item_index, 'D_MUTE', 0, true)
  if r.GetSetAutomationItemInfo_String then
    local tag = 'SBP_LoudnessCurve:' .. string.format('%.17g', base):gsub(',', '.')
    if correction.source_i and correction.source_name then
      tag = tag .. '|i=' .. string.format('%.17g', correction.source_i):gsub(',', '.') .. '|source=' .. correction.source_name:gsub('|', '_')
    end
    if correction.source_key then tag = tag .. '|key=' .. correction.source_key:gsub('|', '_') end
    r.GetSetAutomationItemInfo_String(envelope, item_index, 'P_POOL_NAME', tag, true)
  end
  if not r.DeleteEnvelopePointRangeEx(envelope, item_index, begin_time - 1, finish_time + 1) then
    local restored = r.SetEnvelopeStateChunk(envelope, original_chunk, false)
    r.Undo_EndBlock('SBP Loudness Curve: export failed', -1)
    return nil, restored and 'Cannot clear old correction points; original envelope restored' or 'Cannot clear points; restore the envelope with REAPER Undo'
  end
  for index, point in ipairs(reduced) do
    local inserted = r.InsertEnvelopePointEx(envelope, item_index, begin_time + point.time,
      values[index], 0, 0, false, true)
    if not inserted then
      local restored = r.SetEnvelopeStateChunk(envelope, original_chunk, false)
      r.Undo_EndBlock("SBP Loudness Curve: export failed", -1)
      return nil, restored and "Cannot insert correction point; original envelope restored" or "Point insertion failed; restore the envelope with REAPER Undo"
    end
  end
  r.Envelope_SortPointsEx(envelope, item_index)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  local _, track_name = r.GetTrackName(track)
  r.Undo_EndBlock("SBP Loudness Curve: export to " .. (track_name or 'destination track'), -1)
  return {track = track_name or profile.bus_printmaster, points = #reduced, original_points = #correction.points, replaced = replacing}
end

return M
