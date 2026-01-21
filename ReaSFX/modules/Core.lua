-- ReaSFX Core Module
-- v2.0 - Модульная архитектура с полной реализацией SmartLoop
local Core = {}

-- Локальная ссылка на REAPER API
local r = reaper

-- =========================================================
-- DATA STRUCTURES
-- =========================================================
Core.Project = {
    keys = {},
    selected_note = 60,
    selected_set = 1,
    multi_sets = {},
    use_snap_align = false,
    placement_mode = 1,
    trigger_mode = 0,
    group_thresh = 0.5,

    -- Global randomization
    g_rnd_vol = 0.0, g_rnd_pitch = 0.0, g_rnd_pan = 0.0,
    g_rnd_pos = 0.0, g_rnd_offset = 0.0, g_rnd_fade = 0.0, g_rnd_len = 0.0
}

Core.LastLog = "Engine Ready."
Core.IsPreviewing = false
Core.PreviewID = nil
Core.KeyState = { held = false, start_pos = 0, pending_event = nil, pending_set = nil }
Core.Input = { was_down = false }

-- =========================================================
-- LOGGING
-- =========================================================
function Core.Log(msg)
    Core.LastLog = msg
end

-- =========================================================
-- KEY INITIALIZATION
-- =========================================================
function Core.InitKey(note)
    if not Core.Project.keys[note] then
        Core.Project.keys[note] = { sets = {} }
        for i=1, 16 do
            Core.Project.keys[note].sets[i] = {
                events = {},
                last_idx = -1,
                trigger_on = 0,
                rnd_vol = 0.0, rnd_pitch = 0.0, rnd_pan = 0.0,
                rnd_pos = 0.0, rnd_offset = 0.0, rnd_fade = 0.0, rnd_len = 0.0,
                xy_x = 0.5, xy_y = 0.5,
                seq_count = 4, seq_rate = 0.150,
                seq_len = 0.100, seq_fade = 0.020,
                seq_mode = 1, -- 0:First, 1:Random, 2:Stitch

                -- NEW: SmartLoop parameters
                loop_crossfade = 0.050,
                loop_sync_mode = 0, -- 0=free, 1=tempo, 2=grid
                release_length = 1.0,
                release_fade = 0.3
            }
        end
    end
    return Core.Project.keys[note]
end

-- Initialize default key
Core.InitKey(Core.Project.selected_note)

-- =========================================================
-- SMART MARKERS PARSING
-- =========================================================
function Core.ParseSmartMarkers(item)
    local take = r.GetActiveTake(item)
    if not take then return nil end
    local count = r.GetNumTakeMarkers(take)
    if count == 0 then return nil end

    local markers = { S=nil, L=nil, E=nil, R=nil }
    local found = false

    Core.Log(string.format("ParseSmartMarkers: found %d take markers", count))

    for i=0, count-1 do
        local retval, pos, name, color = r.GetTakeMarker(take, i)
        Core.Log(string.format("  Marker %d: name='%s', pos=%.3f", i, name or "nil", pos))

        if name and type(name) == 'string' then
            local n = name:upper():match("^%s*(.-)%s*$")  -- Trim whitespace
            Core.Log(string.format("  Trimmed name: '%s'", n))

            if n == "S" then markers.S = pos; found=true
            elseif n == "L" then markers.L = pos; found=true
            elseif n == "E" then markers.E = pos; found=true
            elseif n == "R" then markers.R = pos; found=true end
        end
    end

    if found then
        if not markers.S then markers.S = 0 end
        return markers
    else
        return nil
    end
end

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================
local function SortItemsByPos(a, b)
    return a.pos < b.pos
end

function Core.ClearSet(note, set_idx)
    local k = Core.Project.keys[note]
    if k and k.sets[set_idx] then
        k.sets[set_idx].events = {}
        Core.Log("Cleared Set " .. set_idx)
    end
end

-- =========================================================
-- CAPTURE EVENTS
-- =========================================================

-- ✨ NEW: Capture from Razor Edit areas
function Core.CaptureRazorEdit()
    local razor_events = {}
    local track_count = r.CountTracks(0)

    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local _, razor_str = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)

        if razor_str ~= "" then
            -- Parse razor edit format: "start end" pairs
            for area_start_str, area_end_str in razor_str:gmatch("([%d%.]+) ([%d%.]+)") do
                local area_start = tonumber(area_start_str)
                local area_end = tonumber(area_end_str)

                if area_start and area_end then
                    -- Find items in this razor area
                    local item_count = r.CountTrackMediaItems(track)
                    for j = 0, item_count - 1 do
                        local item = r.GetTrackMediaItem(track, j)
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_end = item_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")

                        -- Check if item overlaps with razor area
                        if item_pos < area_end and item_end > area_start then
                            local smart_data = Core.ParseSmartMarkers(item)
                            local chunk = select(2, r.GetItemStateChunk(item, "", false))

                            local evt = {
                                items = {{
                                    chunk = chunk,
                                    rel_pos = 0,
                                    rel_track = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"),
                                    rel_track_offset = 0,
                                    snap = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"),
                                    smart = smart_data,
                                    len = area_end - area_start
                                }},
                                is_smart = smart_data and true or false,
                                has_release = smart_data and smart_data.R and true or false
                            }

                            table.insert(razor_events, evt)
                        end
                    end
                end
            end
        end
    end

    return razor_events
end

function Core.CaptureToActiveSet()
    local note = Core.Project.selected_note
    local set_idx = Core.Project.selected_set
    local key_data = Core.InitKey(note)
    local target_set = key_data.sets[set_idx]

    -- ✨ Check for Razor Edit first
    local razor_events = Core.CaptureRazorEdit()
    if #razor_events > 0 then
        for _, evt in ipairs(razor_events) do
            evt.probability = 100
            evt.vol_offset = 0.0
            evt.muted = false
            table.insert(target_set.events, evt)
        end
        Core.Log(string.format("Captured %d events from Razor Edit", #razor_events))
        return
    end

    -- Fallback to selected items
    local num_sel = r.CountSelectedMediaItems(0)

    if num_sel == 0 then
        Core.Log("No items selected and no Razor Edit!")
        return
    end

    -- Collect all selected items
    local raw_items = {}

    for i = 0, num_sel - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local smart_data = Core.ParseSmartMarkers(item)

        table.insert(raw_items, {
            item = item,
            pos = pos,
            len = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
            snap = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"),
            track_idx = r.GetMediaTrackInfo_Value(r.GetMediaItem_Track(item), "IP_TRACKNUMBER"),
            chunk = select(2, r.GetItemStateChunk(item, "", false)),
            smart = smart_data
        })
    end

    table.sort(raw_items, SortItemsByPos)

    -- ✨ NEW: Process each item - split smart items into 3 events
    local new_events = {}

    for _, raw_item in ipairs(raw_items) do
        if raw_item.smart and raw_item.smart.L and raw_item.smart.E then
            -- Item has smart markers - split into 3 events: Start, Loop, Release
            local S = raw_item.smart.S or 0
            local L = raw_item.smart.L
            local E = raw_item.smart.E
            local R = raw_item.smart.R

            Core.Log(string.format("Smart item: S=%.3f L=%.3f E=%.3f R=%s",
                S, L, E, R and string.format("%.3f", R) or "nil"))

            -- Event 1: Start section (S → L)
            local start_len = L - S
            if start_len > 0.001 then
                table.insert(new_events, {
                    items = {{
                        chunk = raw_item.chunk,
                        rel_pos = 0,
                        rel_track = raw_item.track_idx,
                        rel_track_offset = 0,
                        snap = raw_item.snap,
                        smart = raw_item.smart,
                        len = start_len,
                        slice_offset = S,
                        slice_length = start_len
                    }},
                    is_smart = true,
                    has_release = R and true or false,
                    section_type = "START",
                    probability = 100,
                    vol_offset = 0.0,
                    muted = false
                })
            end

            -- Event 2: Loop section (L → E)
            local loop_len = E - L
            if loop_len > 0.001 then
                table.insert(new_events, {
                    items = {{
                        chunk = raw_item.chunk,
                        rel_pos = 0,
                        rel_track = raw_item.track_idx,
                        rel_track_offset = 0,
                        snap = raw_item.snap,
                        smart = raw_item.smart,
                        len = loop_len,
                        slice_offset = L,
                        slice_length = loop_len
                    }},
                    is_smart = true,
                    has_release = R and true or false,
                    section_type = "LOOP",
                    probability = 100,
                    vol_offset = 0.0,
                    muted = false
                })
            end

            -- Event 3: Release section (E → R)
            if R then
                local release_len = R - E
                if release_len > 0.001 then
                    table.insert(new_events, {
                        items = {{
                            chunk = raw_item.chunk,
                            rel_pos = 0,
                            rel_track = raw_item.track_idx,
                            rel_track_offset = 0,
                            snap = raw_item.snap,
                            smart = raw_item.smart,
                            len = release_len,
                            slice_offset = E,
                            slice_length = release_len
                        }},
                        is_smart = true,
                        has_release = true,
                        section_type = "RELEASE",
                        probability = 100,
                        vol_offset = 0.0,
                        muted = false
                    })
                end
            end
        else
            -- Regular item without smart markers
            table.insert(new_events, {
                items = {{
                    chunk = raw_item.chunk,
                    rel_pos = 0,
                    rel_track = raw_item.track_idx,
                    rel_track_offset = 0,
                    snap = raw_item.snap,
                    smart = raw_item.smart,
                    len = raw_item.len
                }},
                is_smart = false,
                has_release = false,
                probability = 100,
                vol_offset = 0.0,
                muted = false
            })
        end
    end

    -- Add all events to set
    for _, evt in ipairs(new_events) do
        table.insert(target_set.events, evt)
    end

    Core.Log(string.format("Captured %d events (%d smart splits)", #new_events, #new_events - #raw_items))
end

-- =========================================================
-- INSERT HELPERS
-- =========================================================
function Core.InsertSlice(chunk, track, pos, offset, length, set_params, total_vol_factor)
    local ni = r.AddMediaItemToTrack(track)
    r.SetItemStateChunk(ni, chunk, false)
    r.SetMediaItemInfo_Value(ni, "D_POSITION", pos)
    r.SetMediaItemInfo_Value(ni, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(ni, "D_FADEINLEN", 0.002)
    r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", 0.002)

    local take = r.GetActiveTake(ni)
    if take then
        local base_offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", base_offs + offset)
        local cur_vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", cur_vol * total_vol_factor)
    end

    r.SetMediaItemSelected(ni, true)
    return ni
end

function Core.InsertEventItems(event, play_pos, set_params, is_seq_item)
    local rnd = { vol=0, pitch=0, pan=0, pos=0, off=0, fade=0, len=0 }

    if set_params then
        local mt, md = set_params.xy_x * 2.0, set_params.xy_y * 2.0
        local function GR(r, m) return (math.random()*2-1)*r*m end

        rnd.vol = GR(set_params.rnd_vol + Core.Project.g_rnd_vol, md)
        rnd.pitch = GR(set_params.rnd_pitch + Core.Project.g_rnd_pitch, md)
        rnd.pan = GR((set_params.rnd_pan + Core.Project.g_rnd_pan)/100, mt)

        if not is_seq_item or set_params.seq_mode ~= 2 then
            rnd.pos = GR(set_params.rnd_pos + Core.Project.g_rnd_pos, mt)
        end

        rnd.off = math.abs(GR(set_params.rnd_offset + Core.Project.g_rnd_offset, mt))
        rnd.fade = math.abs(GR(set_params.rnd_fade + Core.Project.g_rnd_fade, 1.0))
        rnd.len = GR(set_params.rnd_len + Core.Project.g_rnd_len, 1.0)
    end

    local total_vol_factor = 10 ^ ((rnd.vol + (event.vol_offset or 0)) / 20)
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)

    if not base_track then
        r.InsertTrackAtIndex(0, true)
        base_track = r.GetTrack(0,0)
    end

    local mode = Core.Project.placement_mode
    if mode == 1 then
        r.SetMediaTrackInfo_Value(base_track, "I_FREEMODE", 1)
    elseif mode == 2 then
        r.SetMediaTrackInfo_Value(base_track, "I_FREEMODE", 2)
    end

    r.SelectAllMediaItems(0, false)
    local fipm_h = 1.0
    if mode == 1 and #event.items > 1 then
        fipm_h = 1.0 / #event.items
    end

    for i, it in ipairs(event.items) do
        local tr = base_track
        if mode == 0 then
            local idx = r.GetMediaTrackInfo_Value(base_track, "IP_TRACKNUMBER") + it.rel_track_offset
            tr = r.GetTrack(0, idx - 1)
            if not tr then
                r.InsertTrackAtIndex(idx-1, true)
                tr = r.GetTrack(0, idx-1)
            end
        end

        local ni = r.AddMediaItemToTrack(tr)
        r.SetItemStateChunk(ni, it.chunk, false)

        if mode == 1 then
            r.SetMediaItemInfo_Value(ni, "F_FREEMODE_Y", (i-1)*fipm_h)
            r.SetMediaItemInfo_Value(ni, "F_FREEMODE_H", fipm_h)
        elseif mode == 2 then
            r.SetMediaItemInfo_Value(ni, "I_FIXEDLANE", i-1)
        end

        local item_pos = play_pos + it.rel_pos + rnd.pos
        if Core.Project.use_snap_align and it.snap > 0 then
            item_pos = item_pos - it.snap
        end
        r.SetMediaItemInfo_Value(ni, "D_POSITION", item_pos)

        if is_seq_item then
            r.SetMediaItemInfo_Value(ni, "D_LENGTH", set_params.seq_len)
            r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", set_params.seq_fade)
        else
            r.SetMediaItemInfo_Value(ni, "D_LENGTH", math.max(0.1, r.GetMediaItemInfo_Value(ni, "D_LENGTH") + rnd.len))
            r.SetMediaItemInfo_Value(ni, "D_FADEINLEN", r.GetMediaItemInfo_Value(ni, "D_FADEINLEN") + rnd.fade)
            r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", r.GetMediaItemInfo_Value(ni, "D_FADEOUTLEN") + rnd.fade)
        end

        local take = r.GetActiveTake(ni)
        if take then
            r.SetMediaItemTakeInfo_Value(take, "D_PITCH", r.GetMediaItemTakeInfo_Value(take, "D_PITCH") + rnd.pitch)
            r.SetMediaItemTakeInfo_Value(take, "D_VOL", r.GetMediaItemTakeInfo_Value(take, "D_VOL") * total_vol_factor)
            local np = r.GetMediaItemTakeInfo_Value(take, "D_PAN") + rnd.pan
            if np > 1 then np = 1 elseif np < -1 then np = -1 end
            r.SetMediaItemTakeInfo_Value(take, "D_PAN", np)
            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + rnd.off)
        end

        if mode == 1 then r.UpdateItemInProject(ni) end
        r.SetMediaItemSelected(ni, true)
    end

    r.UpdateArrange()
end

-- =========================================================
-- SEQUENCER
-- =========================================================
function Core.PlaySequencer(pos, set)
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local use_sel = (ts_end - ts_start) > 0.001

    local count = set.seq_count
    local rate = math.max(0.01, set.seq_rate)

    local pool_normal, pool_release = {}, {}
    for i, e in ipairs(set.events) do
        if not e.muted then
            if e.has_release then
                table.insert(pool_release, e)
            else
                table.insert(pool_normal, e)
            end
        end
    end

    if #pool_release == 0 and #pool_normal == 0 then return end
    if #pool_normal == 0 then pool_normal = pool_release end

    local is_stitch = (set.seq_mode == 2)

    if use_sel then
        if is_stitch then
            count = 9999
            pos = ts_start
        else
            count = math.floor((ts_end - ts_start) / rate)
            if count<1 then count=1 end
            pos = ts_start
        end
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local current_pos = pos

    for i=0, count-1 do
        if use_sel and current_pos >= ts_end then break end

        local is_last = (i == count - 1)
        if use_sel and is_stitch then
            if (ts_end - current_pos) <= (set.seq_len * 1.1) then
                is_last = true
            end
        end

        local evt_to_play = nil
        if is_last and #pool_release > 0 then
            evt_to_play = pool_release[math.random(#pool_release)]
        else
            if set.seq_mode == 0 then
                evt_to_play = set.events[1]
            else
                evt_to_play = pool_normal[math.random(#pool_normal)]
            end
        end

        if evt_to_play then
            Core.InsertEventItems(evt_to_play, current_pos, set, true)
            if is_stitch then
                current_pos = current_pos + set.seq_len
            else
                current_pos = current_pos + rate
            end
        end

        if is_last and use_sel then break end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Sequencer", -1)
end

-- =========================================================
-- ✨ NEW: SMART LOOP IMPLEMENTATION ✨
-- =========================================================

-- NEW: Build Smart Loop from pre-split events (START, LOOP, RELEASE)
function Core.BuildSmartLoopFromEvents(start_evt, loop_evt, release_evt, fill_start, fill_end, set_params)
    if not loop_evt then
        Core.Log("BuildSmartLoopFromEvents: Missing LOOP event!")
        return
    end

    local duration = fill_end - fill_start
    if duration < 0.01 then
        Core.Log("BuildSmartLoopFromEvents: Time selection too short (< 0.01s)")
        return
    end

    local crossfade = set_params and set_params.loop_crossfade or 0.050
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    if not base_track then
        r.InsertTrackAtIndex(0, true)
        base_track = r.GetTrack(0, 0)
    end

    local current_pos = fill_start

    -- PHASE 1: Insert START section (if exists)
    if start_evt and start_evt.items and #start_evt.items > 0 then
        local start_item_data = start_evt.items[1]
        local start_len = start_item_data.slice_length or start_item_data.len
        local start_offset = start_item_data.slice_offset or 0

        Core.Log(string.format("Phase 1 START: len=%.3f, offset=%.3f", start_len, start_offset))

        for _, it in ipairs(start_evt.items) do
            local item_pos = current_pos + (it.rel_pos or 0)

            -- Align by snap offset
            if Core.Project.use_snap_align and it.snap and it.snap > 0 then
                item_pos = item_pos - it.snap
                Core.Log(string.format("Snap align: %.3f (snap=%.3f)", item_pos, it.snap))
            end

            Core.InsertSlice(it.chunk, base_track, item_pos,
                start_offset, start_len, set_params,
                10 ^ ((start_evt.vol_offset or 0) / 20))
        end

        current_pos = current_pos + start_len
    end

    -- PHASE 2: Insert LOOP section (repeated)
    local loop_item_data = loop_evt.items[1]
    local loop_len = loop_item_data.slice_length or loop_item_data.len
    local loop_offset = loop_item_data.slice_offset or 0
    local remaining = fill_end - current_pos
    local num_loops = 0

    Core.Log(string.format("Phase 2 LOOP: len=%.3f, offset=%.3f, remaining=%.3f",
        loop_len, loop_offset, remaining))

    while remaining > loop_len do
        for _, it in ipairs(loop_evt.items) do
            local item = Core.InsertSlice(it.chunk, base_track,
                current_pos + (it.rel_pos or 0), loop_offset, loop_len, set_params,
                10 ^ ((loop_evt.vol_offset or 0) / 20))

            -- Crossfade for smooth looping
            if crossfade > 0 then
                r.SetMediaItemInfo_Value(item, "D_FADEINLEN", math.min(crossfade, loop_len * 0.3))
                r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(crossfade, loop_len * 0.3))
            end
        end

        current_pos = current_pos + loop_len
        remaining = fill_end - current_pos
        num_loops = num_loops + 1
    end

    -- PHASE 3: Insert RELEASE section (if exists)
    if release_evt and release_evt.items and #release_evt.items > 0 then
        local release_item_data = release_evt.items[1]
        local release_len = release_item_data.slice_length or release_item_data.len
        local release_offset = release_item_data.slice_offset or 0

        Core.Log(string.format("Phase 3 RELEASE: len=%.3f, offset=%.3f", release_len, release_offset))

        for _, it in ipairs(release_evt.items) do
            local item = Core.InsertSlice(it.chunk, base_track,
                current_pos + (it.rel_pos or 0), release_offset, release_len, set_params,
                10 ^ ((release_evt.vol_offset or 0) / 20))

            -- Fadeout on release
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(0.1, release_len * 0.5))
        end
    end

    Core.Log(string.format("SmartLoop complete: %.2fs filled, %d loops", duration, num_loops))
end

-- OLD: Build Smart Loop from single event with markers (DEPRECATED - kept for compatibility)
function Core.BuildSmartLoop(event, start_pos, end_pos, set_params)
    Core.Log(string.format("BuildSmartLoop: filling %.2f to %.2f", start_pos, end_pos))

    if not event then
        Core.Log("BuildSmartLoop: Event is nil!")
        return
    end

    if not event.is_smart then
        Core.Log("BuildSmartLoop: Event has no smart markers")
        return
    end

    local duration = end_pos - start_pos
    if duration < 0.01 then
        Core.Log("BuildSmartLoop: Time selection too short")
        return
    end

    -- Find smart markers from first item
    local markers = nil
    for _, it in ipairs(event.items) do
        if it.smart then
            markers = it.smart
            break
        end
    end

    if not markers or not markers.L or not markers.E then
        Core.Log("BuildSmartLoop: Missing L or E markers")
        return
    end

    local S = markers.S or 0
    local L = markers.L
    local E = markers.E
    local R = markers.R

    Core.Log(string.format("Markers: S=%.3f, L=%.3f, E=%.3f, R=%s",
        S, L, E, R and string.format("%.3f", R) or "none"))

    local start_len = L - S  -- Intro/Start section length
    local loop_len = E - L   -- Loop body length
    local release_len = R and (R - E) or 0  -- Release tail length

    if loop_len <= 0 then
        Core.Log("BuildSmartLoop: Invalid loop length")
        return
    end

    local crossfade = set_params and set_params.loop_crossfade or 0.050

    -- Calculate positions
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    if not base_track then
        r.InsertTrackAtIndex(0, true)
        base_track = r.GetTrack(0, 0)
    end

    local current_pos = start_pos

    -- PHASE 1: Insert Start section (S -> L)
    -- Position accounting for snap offset
    for _, it in ipairs(event.items) do
        local item_pos = current_pos + it.rel_pos

        -- Align by snap offset
        if Core.Project.use_snap_align and it.snap > 0 then
            item_pos = item_pos - it.snap
        end

        Core.InsertSlice(it.chunk, base_track, item_pos, S, start_len, set_params,
            10 ^ ((event.vol_offset or 0) / 20))
    end

    current_pos = current_pos + start_len
    local remaining = end_pos - current_pos

    -- PHASE 2: Fill with Loop section (L -> E)
    -- Keep inserting loops until we reach near the end
    local num_loops = 0

    while remaining > loop_len do
        for _, it in ipairs(event.items) do
            local item = Core.InsertSlice(it.chunk, base_track,
                current_pos + it.rel_pos, L, loop_len, set_params,
                10 ^ ((event.vol_offset or 0) / 20))

            -- Crossfade for smooth looping
            if crossfade > 0 then
                r.SetMediaItemInfo_Value(item, "D_FADEINLEN", math.min(crossfade, loop_len * 0.3))
                r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(crossfade, loop_len * 0.3))
            end
        end

        current_pos = current_pos + loop_len
        remaining = end_pos - current_pos
        num_loops = num_loops + 1
    end

    -- PHASE 3: Insert Release tail (E -> R)
    -- Place release at the end, even if it extends past time selection
    if R and release_len > 0 then
        for _, it in ipairs(event.items) do
            local item = Core.InsertSlice(it.chunk, base_track,
                current_pos + it.rel_pos, E, release_len, set_params,
                10 ^ ((event.vol_offset or 0) / 20))

            -- Fadeout on release
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(0.1, release_len * 0.5))
        end
    end

    Core.Log(string.format("SmartLoop: filled %.2fs with %d loops", duration, num_loops))
end

-- =========================================================
-- TRIGGER & PREVIEW
-- =========================================================
function Core.GetTriggerEvent(note, set_idx)
    local k = Core.Project.keys[note]
    if not k then return nil, nil end
    local s = k.sets[set_idx]
    if not s or #s.events == 0 then return nil, nil end

    local pool = {}
    for i, evt in ipairs(s.events) do
        if evt.probability > 0 and not evt.muted then
            table.insert(pool, i)
        end
    end

    if #pool == 0 then return nil, nil end

    local c = -1
    if #pool==1 then
        c=pool[1]
    else
        local z=0
        repeat
            c=pool[math.random(1,#pool)]
            z=z+1
        until (c~=s.last_idx) or (z>20)
    end

    s.last_idx = c
    return s.events[c], s
end

function Core.StartPreview(event, id)
    if not event or #event.items == 0 then return end

    local has_sws = r.APIExists('Xen_StartSourcePreview')
    if has_sws and (not Core.IsPreviewing or Core.PreviewID ~= id) then
        r.Xen_StopSourcePreview(0)
        local fn = event.items[1].chunk:match('FILE "([^"]+)"') or event.items[1].chunk:match('FILE ([^\n]+)')
        if fn then
            local src = r.PCM_Source_CreateFromFile(fn)
            if src then
                r.Xen_StartSourcePreview(src, 10^((event.vol_offset or 0)/20), false)
                Core.IsPreviewing = true
                Core.PreviewID = id
            end
        end
    end
end

function Core.StopPreview()
    local has_sws = r.APIExists('Xen_StartSourcePreview')
    if has_sws and Core.IsPreviewing then
        r.Xen_StopSourcePreview(0)
        Core.IsPreviewing = false
        Core.PreviewID = nil
    end
end

function Core.ExecuteTrigger(note, set_idx, pos, edge_type)
    local k = Core.Project.keys[note]
    if not k then return end
    local set = k.sets[set_idx]
    if not set then return end

    if set.trigger_on == edge_type then
        local mode = Core.Project.trigger_mode
        if mode == 0 then -- One Shot
            local evt, _ = Core.GetTriggerEvent(note, set_idx)
            if evt then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                Core.InsertEventItems(evt, pos, set)
                r.PreventUIRefresh(-1)
                r.UpdateArrange()
                r.Undo_EndBlock("Trigger", -1)
            end
        elseif mode == 1 then -- Sequencer
            if edge_type == 0 then
                Core.PlaySequencer(pos, set)
            end
        elseif mode == 2 then -- Smart Loop
            if edge_type == 0 then
                local evt, _ = Core.GetTriggerEvent(note, set_idx)
                if evt then
                    Core.KeyState.pending_event = evt
                    Core.KeyState.pending_set = set
                    Core.Log("Smart Loop: Event captured, hold K and release for loop")
                end
            end
        end
    end
end

function Core.TriggerMulti(note, main_set_idx, pos, edge_type)
    Core.ExecuteTrigger(note, main_set_idx, pos, edge_type)
    for _, idx in ipairs(Core.Project.multi_sets) do
        if idx~=main_set_idx then
            Core.ExecuteTrigger(note, idx, pos, edge_type)
        end
    end
end

function Core.SmartLoopRelease(note, main_set_idx, start_pos, end_pos)
    if Core.Project.trigger_mode ~= 2 then
        return
    end

    -- Get current edit cursor position (for scrubbing support)
    local current_cursor = r.GetCursorPosition()

    -- Get time selection if exists
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local has_time_sel = (ts_end - ts_start) > 0.001

    -- Determine fill range (priority: Time Selection > Cursor Scrub > Key Hold)
    local fill_start, fill_end
    if has_time_sel then
        -- Priority 1: Time Selection
        fill_start = ts_start
        fill_end = ts_end
        Core.Log(string.format("Using time selection: %.2f to %.2f", ts_start, ts_end))
    elseif math.abs(current_cursor - start_pos) > 0.01 then
        -- Priority 2: Edit Cursor scrubbing (cursor moved during K hold)
        fill_start = math.min(start_pos, current_cursor)
        fill_end = math.max(start_pos, current_cursor)
        Core.Log(string.format("Using cursor scrub: %.2f to %.2f (scrubbed %.2fs)",
            fill_start, fill_end, fill_end - fill_start))
    else
        -- Priority 3: Key hold duration (fallback)
        fill_start = start_pos
        fill_end = end_pos
        Core.Log(string.format("Using key hold: %.2f to %.2f", start_pos, end_pos))
    end

    -- ✨ NEW: Find START, LOOP, RELEASE events in the set
    local k = Core.Project.keys[note]
    if not k then
        Core.Log("Smart Loop: No key data!")
        return
    end

    local set = k.sets[main_set_idx]
    if not set or #set.events == 0 then
        Core.Log("Smart Loop: No events in set!")
        return
    end

    local start_evt, loop_evt, release_evt = nil, nil, nil

    for _, evt in ipairs(set.events) do
        if evt.section_type == "START" then
            start_evt = evt
        elseif evt.section_type == "LOOP" then
            loop_evt = evt
        elseif evt.section_type == "RELEASE" then
            release_evt = evt
        end
    end

    if not loop_evt then
        Core.Log("Smart Loop: No LOOP event found! Capture smart item first.")
        return
    end

    -- Call BuildSmartLoop with separated events
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    Core.BuildSmartLoopFromEvents(start_evt, loop_evt, release_evt, fill_start, fill_end, set)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("SmartLoop", -1)

    Core.KeyState.pending_event = nil
    Core.KeyState.pending_set = nil
end

function Core.DeleteEvent(note, set_idx, evt_idx)
    local k = Core.Project.keys[note]
    if k and k.sets[set_idx] then
        table.remove(k.sets[set_idx].events, evt_idx)
    end
end

return Core
