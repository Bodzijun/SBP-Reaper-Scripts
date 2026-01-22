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
    placement_mode = 0,  -- default to Track(s)
    trigger_mode = 0,
    group_thresh = 0.5,

    -- Global randomization
    g_rnd_vol = 0.0, g_rnd_pitch = 0.0, g_rnd_pan = 0.0,
    g_rnd_pos = 0.0, g_rnd_offset = 0.0, g_rnd_fade = 0.0, g_rnd_len = 0.0,

    -- MIDI Control
    midi_enabled = false,
    midi_channel = 0,  -- 0 = any channel
    midi_trigger_note = 60,  -- which MIDI note triggers insertion (default C3)
    midi_learn_active = false,  -- MIDI learn mode for trigger note
    selected_sets = {},  -- array of selected sets for velocity layering {1, 3, 5}
    velocity_ranges = {}, -- {[set_idx] = {min=0, max=127}, ...}

    -- Corner Mixer (Krotos-style XY morphing)
    xy_corners = {
        top_left = nil,      -- set_idx or nil
        top_right = nil,
        bottom_left = nil,
        bottom_right = nil
    },
    xy_mixer_mode = 0,       -- 0=Post-FX Balance, 1=Real-time Insert, 2=Vector Recording
    xy_mixer_enabled = false -- Corner mixer active
}

Core.LastLog = "Engine Ready."
Core.IsPreviewing = false
Core.PreviewID = nil
Core.KeyState = { held = false, start_pos = 0, pending_event = nil, pending_set = nil }
Core.Input = { was_down = false }
Core.FollowMouseCursor = false

-- =========================================================
-- LOGGING
-- =========================================================
-- Log history
Core.LogHistory = Core.LogHistory or {}
Core.MaxLogLines = 50

function Core.Log(msg)
    Core.LastLog = msg
    table.insert(Core.LogHistory, msg)
    -- Keep only last N lines
    if #Core.LogHistory > Core.MaxLogLines then
        table.remove(Core.LogHistory, 1)
    end
end

-- =========================================================
-- EDIT CURSOR FOLLOWS MOUSE
-- =========================================================
function Core.UpdateMouseCursor()
    if not Core.FollowMouseCursor then return end
    local window, segment, details = r.BR_GetMouseCursorContext()
    if window == "arrange" then
        local mouse_pos = r.BR_GetMouseCursorContext_Position()
        local edit_cur = r.GetCursorPosition()
        if mouse_pos >= 0 and mouse_pos ~= edit_cur then
            r.SetEditCurPos2(0, mouse_pos, false, false)
        end
    end
end

-- =========================================================
-- REAL-TIME PARAM UPDATE ON SELECTED ITEMS
-- =========================================================
Core.LastSeqParams = {}

function Core.UpdateSelectedItemsRealtime(s)
    if not s then return end
    -- Only for Repeat First and Random Pool modes
    if s.seq_mode == 2 then return end

    -- Apply to selected items
    local item_count = r.CountSelectedMediaItems(0)
    if item_count == 0 then return end

    r.PreventUIRefresh(1)

    -- Collect items and sort by position
    local items = {}
    for i = 0, item_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            table.insert(items, {
                item = item,
                pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            })
        end
    end
    table.sort(items, function(a, b) return a.pos < b.pos end)

    -- Get first item position as base
    local base_pos = items[1].pos

    for i, data in ipairs(items) do
        local item = data.item
        -- Update position based on rate (spacing from first item)
        local new_pos = base_pos + (i - 1) * s.seq_rate
        r.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
        -- Update length and fades
        r.SetMediaItemInfo_Value(item, "D_LENGTH", s.seq_len)
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN", s.seq_fade)
        r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", s.seq_fade)
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
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
                xy_mode = 0,    -- 0=Intens/Spread, 1=Vol/Pitch, 2=Pan/Pos
                xy_snap = false, -- snap to center on release
                xy_midi_x_cc = -1,  -- -1 = disabled, 0-127 = CC number
                xy_midi_y_cc = -1,
                xy_midi_channel = 0, -- 0 = any
                seq_count = 4, seq_rate = 0.150,
                seq_len = 0.100, seq_fade = 0.020,
                seq_mode = 1, -- 0:First, 1:Random, 2:Stitch

                -- One Shot mode settings
                oneshot_mode = 1, -- 0:Sequential (round-robin), 1:Random
                oneshot_idx = 0,  -- current index for sequential mode

                -- NEW: SmartLoop parameters
                loop_crossfade = 0.050,
                loop_sync_mode = 0, -- 0=free, 1=tempo, 2=grid
                release_length = 1.0,
                release_fade = 0.3,

                -- FX Chain
                fx_chunk = "",  -- FX chain chunk from take

                -- Per-set MIDI settings
                midi_enabled = false,   -- MIDI trigger enabled for this set
                velocity_min = 0,       -- min velocity (0-127)
                velocity_max = 127,     -- max velocity (0-127)
                velocity_invert = false -- invert velocity slider display
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
    if not take then
        Core.Log("ParseSmartMarkers: No active take")
        return nil
    end

    local count = r.GetNumTakeMarkers(take)
    Core.Log(string.format("ParseSmartMarkers: found %d take markers", count))

    if count == 0 then return nil end

    local markers = { S=nil, L=nil, E=nil, R=nil }

    for i=0, count-1 do
        -- ✨ FIX: GetTakeMarker returns position as FIRST value, name as SECOND!
        -- API: position, name, color_index = GetTakeMarker(take, index)
        local marker_pos, marker_name = r.GetTakeMarker(take, i)

        Core.Log(string.format("  Marker %d: pos=%.3f, name='%s'", i, marker_pos or 0, tostring(marker_name)))

        if marker_pos and marker_name and type(marker_name) == 'string' and marker_name ~= "" then
            local n = marker_name:upper():match("^%s*(.-)%s*$")  -- Trim whitespace
            Core.Log(string.format("  → Recognized: '%s' at %.3f", n, marker_pos))

            if n == "S" then
                markers.S = marker_pos
                Core.Log("    → START marker")
            elseif n == "L" then
                markers.L = marker_pos
                Core.Log("    → LOOP START marker")
            elseif n == "E" then
                markers.E = marker_pos
                Core.Log("    → LOOP END marker")
            elseif n == "R" then
                markers.R = marker_pos
                Core.Log("    → RELEASE marker")
            else
                Core.Log(string.format("    → Unknown marker: '%s'", n))
            end
        end
    end

    -- Smart: требуется L и R (E опционален)
    if markers.L and markers.R then
        if not markers.S then markers.S = 0 end
        if not markers.E then markers.E = markers.R end  -- E=R если E нет
        Core.Log(string.format("Smart: S=%.3f, L=%.3f, E=%.3f, R=%.3f",
            markers.S, markers.L, markers.E, markers.R))

        -- Add item end position
        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local take_offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        markers.ITEM_END = take_offset + item_len

        return markers
    else
        Core.Log("Not smart (need L + R)")
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

            -- Event 2: Loop section (L → E, или L→R если E нет)
            local loop_end = E or R
            local loop_len = loop_end - L
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

            -- Event 3: Release section (R → ITEM_END)
            if R then
                local ITEM_END = raw_item.smart.ITEM_END
                local release_len = ITEM_END - R
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
                            slice_offset = R,
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
            -- Regular item without smart markers - will be grouped below
            table.insert(new_events, {
                raw = raw_item,  -- temporary, for grouping
                is_smart = false
            })
        end
    end

    -- ✨ GROUP regular items by position (within gap threshold)
    local grouped_events = {}
    local regular_items = {}

    for _, evt in ipairs(new_events) do
        if evt.raw then
            -- Regular item - collect for grouping
            table.insert(regular_items, evt.raw)
        else
            -- Smart item - add directly
            table.insert(grouped_events, evt)
        end
    end

    -- Sort regular items by position
    table.sort(regular_items, function(a, b) return a.pos < b.pos end)

    -- Group items within gap threshold
    local gap = Core.Project.group_thresh
    local current_group = nil
    local group_base_pos = nil
    local group_base_track = nil

    for _, raw_item in ipairs(regular_items) do
        if not current_group or (raw_item.pos - group_base_pos) > gap then
            -- Start new group
            if current_group then
                table.insert(grouped_events, current_group)
            end
            group_base_pos = raw_item.pos
            group_base_track = raw_item.track_idx
            current_group = {
                items = {},
                is_smart = false,
                has_release = false,
                probability = 100,
                vol_offset = 0.0,
                muted = false
            }
        end

        -- Add item to current group
        table.insert(current_group.items, {
            chunk = raw_item.chunk,
            rel_pos = raw_item.pos - group_base_pos,
            rel_track = raw_item.track_idx,
            rel_track_offset = raw_item.track_idx - group_base_track,
            snap = raw_item.snap,
            smart = raw_item.smart,
            len = raw_item.len
        })
    end

    -- Add last group
    if current_group then
        table.insert(grouped_events, current_group)
    end

    -- Add all events to set
    for _, evt in ipairs(grouped_events) do
        table.insert(target_set.events, evt)
    end

    local layer_count = 0
    for _, evt in ipairs(grouped_events) do
        if evt.items then layer_count = layer_count + #evt.items end
    end
    Core.Log(string.format("Captured %d events (%d layers total)", #grouped_events, layer_count))
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

    -- Apply FX from source take
    if set_params and set_params.fx_source_item and take then
        Core.ApplyFXToTake(take, set_params)
    end

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

    local fipm_h = 1.0
    if mode == 1 and #event.items > 1 then
        fipm_h = 1.0 / #event.items
    end

    for i, it in ipairs(event.items) do
        local tr = base_track
        if mode == 0 and #event.items > 1 then
            -- Track(s) mode: place layers on consecutive tracks starting from selected
            -- Layer 1 → base track, Layer 2 → base+1, etc.
            local base_idx = math.floor(r.GetMediaTrackInfo_Value(base_track, "IP_TRACKNUMBER"))
            local idx = base_idx + (i - 1)  -- Sequential: layer index determines track

            tr = r.GetTrack(0, idx - 1)  -- GetTrack is 0-based
            if not tr then
                r.InsertTrackAtIndex(idx - 1, true)
                tr = r.GetTrack(0, idx - 1)
            end

            Core.Log(string.format("Layer %d -> Track %d", i, idx))
        end

        if not tr then
            Core.Log("ERROR: Could not get/create track for layer " .. i)
            tr = base_track  -- Fallback to base track
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

    -- Deselect all items before inserting
    r.SelectAllMediaItems(0, false)

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

    -- Get crossfade from set params
    local micro_overlap = set_params and set_params.loop_crossfade or 0.003

    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    if not base_track then
        r.InsertTrackAtIndex(0, true)
        base_track = r.GetTrack(0, 0)
    end

    -- Deselect all items before inserting
    r.SelectAllMediaItems(0, false)

    -- ✨ PHASE 1: Insert START section with snap alignment
    local current_pos = fill_start
    local snap_shift = 0

    if start_evt and start_evt.items and #start_evt.items > 0 then
        local start_item_data = start_evt.items[1]
        local start_len = start_item_data.slice_length or start_item_data.len
        local start_offset = start_item_data.slice_offset or 0

        -- Calculate snap offset: START begins BEFORE Time Selection
        if Core.Project.use_snap_align and start_item_data.snap and start_item_data.snap > 0 then
            snap_shift = start_item_data.snap
            Core.Log(string.format("Phase 1 START: snap=%.3f, starts %.3f before TS",
                snap_shift, snap_shift))
        end

        Core.Log(string.format("Phase 1 START: len=%.3f, offset=%.3f", start_len, start_offset))

        for _, it in ipairs(start_evt.items) do
            -- Position: Time Selection start - snap offset
            local item_pos = fill_start - snap_shift + (it.rel_pos or 0)

            local item = Core.InsertSlice(it.chunk, base_track, item_pos,
                start_offset, start_len, set_params,
                10 ^ ((start_evt.vol_offset or 0) / 20))

            -- NO internal fades - only micro fade at end for crossfade
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0.001)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", micro_overlap)

            -- Apply randomization (generate per-item)
            local item_take = r.GetActiveTake(item)
            if item_take and set_params then
                local rnd_vol = (set_params.rnd_vol or 0) * (math.random() * 2 - 1)
                local rnd_pitch = (set_params.rnd_pitch or 0) * (math.random() * 2 - 1)
                local rnd_pan = (set_params.rnd_pan or 0) * (math.random() * 2 - 1)

                local cur_vol = r.GetMediaItemTakeInfo_Value(item_take, "D_VOL")
                r.SetMediaItemTakeInfo_Value(item_take, "D_VOL", cur_vol * 10^(rnd_vol/20))
                r.SetMediaItemTakeInfo_Value(item_take, "D_PITCH", rnd_pitch)
                r.SetMediaItemTakeInfo_Value(item_take, "D_PAN", rnd_pan / 100)
            end
        end

        -- Next position: after START with slight overlap
        current_pos = fill_start + start_len - micro_overlap
    end

    -- ✨ PHASE 2: Insert LOOP section (repeated with micro-overlaps)
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

            -- Micro-crossfade: overlap at edges for seamless looping
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", micro_overlap)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", micro_overlap)

            -- Apply randomization
            local item_take = r.GetActiveTake(item)
            if item_take then
                local cur_vol = r.GetMediaItemTakeInfo_Value(item_take, "D_VOL")
                r.SetMediaItemTakeInfo_Value(item_take, "D_VOL", cur_vol * 10^(rnd.vol/20))
                r.SetMediaItemTakeInfo_Value(item_take, "D_PITCH", rnd.pitch)
                r.SetMediaItemTakeInfo_Value(item_take, "D_PAN", rnd.pan / 100)
            end
        end

        current_pos = current_pos + loop_len - micro_overlap  -- Overlap next
        remaining = fill_end - current_pos
        num_loops = num_loops + 1
    end

    -- ✨ PHASE 3: Insert RELEASE section (E→R, not E only!)
    if release_evt and release_evt.items and #release_evt.items > 0 then
        local release_item_data = release_evt.items[1]
        local release_len = release_item_data.slice_length or release_item_data.len
        local release_offset = release_item_data.slice_offset or 0

        Core.Log(string.format("Phase 3 RELEASE: len=%.3f, offset=%.3f (E→R section)",
            release_len, release_offset))

        for _, it in ipairs(release_evt.items) do
            local item = Core.InsertSlice(it.chunk, base_track,
                current_pos + (it.rel_pos or 0), release_offset, release_len, set_params,
                10 ^ ((release_evt.vol_offset or 0) / 20))

            -- Micro fadein for crossfade, natural fadeout at end
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", micro_overlap)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(0.05, release_len * 0.3))

            -- Apply randomization
            local item_take = r.GetActiveTake(item)
            if item_take then
                local cur_vol = r.GetMediaItemTakeInfo_Value(item_take, "D_VOL")
                r.SetMediaItemTakeInfo_Value(item_take, "D_VOL", cur_vol * 10^(rnd.vol/20))
                r.SetMediaItemTakeInfo_Value(item_take, "D_PITCH", rnd.pitch)
                r.SetMediaItemTakeInfo_Value(item_take, "D_PAN", rnd.pan / 100)
            end
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

    -- Build pool of available events (not muted, probability > 0)
    local pool = {}
    for i, evt in ipairs(s.events) do
        if evt.probability > 0 and not evt.muted then
            table.insert(pool, i)
        end
    end

    if #pool == 0 then return nil, nil end

    local c = -1
    local oneshot_mode = s.oneshot_mode or 1  -- default to Random

    if #pool == 1 then
        c = pool[1]
    elseif oneshot_mode == 0 then
        -- Sequential (Round-Robin): cycle through events in order
        s.oneshot_idx = (s.oneshot_idx or 0) + 1
        if s.oneshot_idx > #pool then
            s.oneshot_idx = 1
        end
        c = pool[s.oneshot_idx]
    else
        -- Random: pick random event, avoid repeating last
        local z = 0
        repeat
            c = pool[math.random(1, #pool)]
            z = z + 1
        until (c ~= s.last_idx) or (z > 20)
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

-- Store source take for FX copying
Core.FXSourceTake = nil

-- Copy FX from selected item to set (stores source take reference)
function Core.CopyFXToSet()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then
        Core.Log("No item selected to copy FX from")
        return
    end

    local take = r.GetActiveTake(item)
    if not take then
        Core.Log("Selected item has no take")
        return
    end

    local fx_count = r.TakeFX_GetCount(take)
    Core.Log(string.format("Take has %d FX", fx_count))

    if fx_count == 0 then
        Core.Log("No FX on selected item take")
        return
    end

    -- Store source take and mark set as having FX
    local note = Core.Project.selected_note
    local set_idx = Core.Project.selected_set
    local k = Core.Project.keys[note]
    if k and k.sets[set_idx] then
        k.sets[set_idx].fx_source_item = item
        k.sets[set_idx].fx_count = fx_count
        Core.Log(string.format("FX source saved for Set %d (%d FX)", set_idx, fx_count))
    end
end

-- Apply FX from source take to target take
function Core.ApplyFXToTake(target_take, set_params)
    if not target_take or not set_params then return end
    if not set_params.fx_source_item then return end

    local source_item = set_params.fx_source_item
    if not r.ValidatePtr(source_item, "MediaItem*") then
        Core.Log("FX source item no longer valid")
        return
    end

    local source_take = r.GetActiveTake(source_item)
    if not source_take then return end

    local fx_count = r.TakeFX_GetCount(source_take)
    for i = 0, fx_count - 1 do
        r.TakeFX_CopyToTake(source_take, i, target_take, -1, false)
    end
end

-- =========================================================
-- MIDI CONTROL
-- =========================================================
Core.MIDI = {
    learn_mode = nil,  -- nil, "x", or "y" for XY pad learning
    last_cc = -1,
    last_cc_value = 0
}

-- Toggle set selection for velocity layering (Shift+Click)
function Core.ToggleSetSelection(set_idx)
    local sets = Core.Project.selected_sets
    local found = false
    for i, idx in ipairs(sets) do
        if idx == set_idx then
            table.remove(sets, i)
            found = true
            break
        end
    end
    if not found then
        table.insert(sets, set_idx)
        -- Initialize velocity range if not exists
        if not Core.Project.velocity_ranges[set_idx] then
            Core.Project.velocity_ranges[set_idx] = { min = 0, max = 127 }
        end
    end
    Core.Log(string.format("Selected sets: %d", #sets))
end

-- Check if set is selected for layering
function Core.IsSetSelected(set_idx)
    for _, idx in ipairs(Core.Project.selected_sets) do
        if idx == set_idx then return true end
    end
    return false
end

-- Auto-distribute velocity ranges evenly across selected sets
function Core.AutoDistributeVelocity()
    local sets = Core.Project.selected_sets
    local count = #sets
    if count == 0 then return end

    local range_size = math.floor(127 / count)
    for i, set_idx in ipairs(sets) do
        local min_vel = (i - 1) * range_size
        local max_vel = (i == count) and 127 or (i * range_size - 1)
        Core.Project.velocity_ranges[set_idx] = { min = min_vel, max = max_vel }
    end
    Core.Log(string.format("Velocity distributed across %d sets", count))
end

-- Handle incoming MIDI Note (per-set MIDI settings)
-- midi_note: incoming MIDI note number (corresponds to GUI key)
-- velocity: 0-127
-- is_note_on: true for Note On, false for Note Off
function Core.HandleMIDINote(midi_note, velocity, is_note_on)
    if not Core.Project.midi_enabled then return end

    -- Ignore zero velocity (phantom signals / Note Off as vel=0)
    if is_note_on and velocity == 0 then
        return
    end

    -- MIDI note directly corresponds to GUI key (60-89 range)
    -- Check if this key exists and has MIDI-enabled sets
    local k = Core.Project.keys[midi_note]
    if not k then return end  -- Key not initialized, ignore

    local cursor = r.GetPlayState() ~= 0 and r.GetPlayPosition() or r.GetCursorPosition()

    -- Collect sets that match velocity
    local matching_sets = {}
    for i = 1, 16 do
        local s = k.sets[i]
        if s and s.midi_enabled and #s.events > 0 then
            -- Check velocity range (handle inverted)
            local vel_min = s.velocity_min or 0
            local vel_max = s.velocity_max or 127
            if s.velocity_invert then
                vel_min, vel_max = 127 - vel_max, 127 - vel_min
            end
            if velocity >= vel_min and velocity <= vel_max then
                table.insert(matching_sets, i)
            end
        end
    end

    if #matching_sets == 0 then return end

    Core.Log(string.format("MIDI: note=%d vel=%d -> %d sets match", midi_note, velocity, #matching_sets))

    -- Check if multiple sets match (layering mode)
    local is_layered = #matching_sets > 1

    -- Get base track
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    if not base_track then
        r.InsertTrackAtIndex(0, true)
        base_track = r.GetTrack(0, 0)
    end
    local base_track_idx = math.floor(r.GetMediaTrackInfo_Value(base_track, "IP_TRACKNUMBER"))

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for layer_idx, set_idx in ipairs(matching_sets) do
        if is_note_on then
            -- For layered mode: each set goes to different track
            if is_layered and Core.Project.placement_mode == 0 then
                -- Calculate target track: base track + (layer_idx - 1)
                local target_track_idx = base_track_idx + layer_idx - 2  -- -2 because IP_TRACKNUMBER is 1-based
                if target_track_idx < 0 then target_track_idx = 0 end

                local target_track = r.GetTrack(0, target_track_idx)
                if not target_track then
                    r.InsertTrackAtIndex(target_track_idx, true)
                    target_track = r.GetTrack(0, target_track_idx)
                end

                if target_track then
                    -- Select only this track for insertion
                    r.SetOnlyTrackSelected(target_track)
                    Core.Log(string.format("Layer %d -> Track %d", layer_idx, target_track_idx + 1))
                end
            end

            -- Execute trigger for this set (midi_note = key number)
            Core.ExecuteTrigger(midi_note, set_idx, cursor, 0)
        else
            -- Note Off
            Core.ExecuteTrigger(midi_note, set_idx, cursor, 1)
            Core.SmartLoopRelease(midi_note, set_idx, Core.KeyState.start_pos, cursor)
        end
    end

    -- Restore original track selection
    if is_layered and base_track then
        r.SetOnlyTrackSelected(base_track)
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("MIDI Trigger", -1)
end

-- Handle incoming MIDI CC for XY Pad
function Core.HandleMIDICC(cc, value, channel)
    -- MIDI Learn mode
    if Core.MIDI.learn_mode then
        Core.MIDI.last_cc = cc
        Core.MIDI.last_cc_value = value
        return
    end

    -- Apply CC to current set's XY pad
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return end
    local s = k.sets[Core.Project.selected_set]
    if not s then return end

    -- Check channel (0 = any)
    if s.xy_midi_channel ~= 0 and channel ~= s.xy_midi_channel then return end

    -- Apply to X or Y axis
    if s.xy_midi_x_cc == cc then
        s.xy_x = value / 127
    end
    if s.xy_midi_y_cc == cc then
        s.xy_y = value / 127
    end
end

-- Poll MIDI input via gmem (shared memory from JSFX bridge)
-- gmem[0] = note, gmem[1] = velocity, gmem[2] = on/off
-- gmem[3] = cc, gmem[4] = cc_value, gmem[5] = channel
-- gmem[6] = event counter (increments on each new event)
Core.MIDI.gmem_attached = false
Core.MIDI.last_event_id = -1

function Core.PollMIDI()
    if not Core.Project.midi_enabled then return end

    -- Attach to gmem once
    if not Core.MIDI.gmem_attached then
        r.gmem_attach("ReaSFX_MIDI")
        Core.MIDI.gmem_attached = true
    end

    -- Check event counter to see if there's a new event
    local event_id = r.gmem_read(6)
    if event_id == Core.MIDI.last_event_id then return end
    Core.MIDI.last_event_id = event_id

    -- Check for Note messages
    local note = r.gmem_read(0)
    local vel = r.gmem_read(1)
    local note_on = r.gmem_read(2)
    local channel = r.gmem_read(5)

    if note >= 0 then
        Core.HandleMIDINote(math.floor(note), math.floor(vel), note_on > 0.5)
    end

    -- Check for CC messages
    local cc = r.gmem_read(3)
    local cc_val = r.gmem_read(4)

    if cc >= 0 then
        Core.HandleMIDICC(math.floor(cc), math.floor(cc_val), math.floor(channel))
    end
end

-- Generate JSFX code for MIDI bridge (uses gmem shared memory)
-- gmem[0] = note number (-1 = none)
-- gmem[1] = velocity
-- gmem[2] = note on/off (1=on, 0=off)
-- gmem[3] = CC number (-1 = none)
-- gmem[4] = CC value
-- gmem[5] = channel
-- gmem[6] = event counter (increments on each new event)
function Core.GetMIDIBridgeJSFX()
    return [[
desc:ReaSFX MIDI Bridge
// Install this JSFX on a track to receive MIDI for ReaSFX
// Uses shared memory (gmem) to communicate with Lua script

options:gmem=ReaSFX_MIDI

@init
gmem[0] = -1;
gmem[3] = -1;
gmem[6] = 0;

@block
while (midirecv(offset, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;
  channel = (msg1 & 0x0F) + 1;

  // Note On
  status == 0x90 && msg3 > 0 ? (
    gmem[0] = msg2;
    gmem[1] = msg3;
    gmem[2] = 1;
    gmem[5] = channel;
    gmem[6] += 1;
  );

  // Note Off
  (status == 0x80 || (status == 0x90 && msg3 == 0)) ? (
    gmem[0] = msg2;
    gmem[1] = 0;
    gmem[2] = 0;
    gmem[5] = channel;
    gmem[6] += 1;
  );

  // CC
  status == 0xB0 ? (
    gmem[3] = msg2;
    gmem[4] = msg3;
    gmem[5] = channel;
    gmem[6] += 1;
  );

  midisend(offset, msg1, msg2, msg3);
);
]]
end

-- =========================================================
-- CORNER MIXER (Krotos-style XY morphing)
-- =========================================================

-- Calculate corner weights based on XY position
-- Returns weights for each corner (0-1), sum = 1
function Core.CalculateCornerWeights(x, y)
    return {
        top_left = (1 - x) * y,
        top_right = x * y,
        bottom_left = (1 - x) * (1 - y),
        bottom_right = x * (1 - y)
    }
end

-- Apply corner mix to selected items (POST-FX BALANCE mode)
function Core.ApplyCornerMixToSelection(x, y)
    local weights = Core.CalculateCornerWeights(x, y)

    -- Get selected items
    local num_sel = r.CountSelectedMediaItems(0)
    if num_sel == 0 then
        Core.Log("Corner Mix: No items selected")
        return
    end

    -- Group items by track for layer assignment
    local items_by_track = {}
    for i = 0, num_sel - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local track = r.GetMediaItem_Track(item)
        local track_idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
        if not items_by_track[track_idx] then
            items_by_track[track_idx] = {}
        end
        table.insert(items_by_track[track_idx], item)
    end

    -- Sort track indices
    local track_indices = {}
    for idx in pairs(items_by_track) do
        table.insert(track_indices, idx)
    end
    table.sort(track_indices)

    -- Map tracks to corners (1st=TL, 2nd=TR, 3rd=BL, 4th=BR)
    local corner_order = {"top_left", "top_right", "bottom_left", "bottom_right"}
    for i, track_idx in ipairs(track_indices) do
        local corner = corner_order[i]
        if corner and weights[corner] then
            local vol = weights[corner]
            for _, item in ipairs(items_by_track[track_idx]) do
                local take = r.GetActiveTake(item)
                if take then
                    r.SetMediaItemTakeInfo_Value(take, "D_VOL", vol)
                end
            end
        end
    end

    r.UpdateArrange()
    Core.Log(string.format("Corner Mix applied: TL=%.0f%% TR=%.0f%% BL=%.0f%% BR=%.0f%%",
        weights.top_left*100, weights.top_right*100, weights.bottom_left*100, weights.bottom_right*100))
end

-- Insert with corner mix (REAL-TIME INSERT mode)
function Core.InsertWithCornerMix(pos)
    if not Core.Project.xy_mixer_enabled then return false end

    local corners = Core.Project.xy_corners
    local k = Core.Project.keys[Core.Project.selected_note]
    if not k then return false end

    -- Get current XY from active set
    local s = k.sets[Core.Project.selected_set]
    if not s then return false end

    local weights = Core.CalculateCornerWeights(s.xy_x, s.xy_y)
    local threshold = 0.1  -- Minimum weight to insert

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local inserted = 0
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    local base_track_idx = base_track and math.floor(r.GetMediaTrackInfo_Value(base_track, "IP_TRACKNUMBER")) or 1

    local corner_order = {"top_left", "top_right", "bottom_left", "bottom_right"}
    for i, corner in ipairs(corner_order) do
        local set_idx = corners[corner]
        local weight = weights[corner]

        if set_idx and weight >= threshold then
            local corner_set = k.sets[set_idx]
            if corner_set and #corner_set.events > 0 then
                -- Select target track (offset from base)
                local target_track_idx = base_track_idx + i - 2
                if target_track_idx < 0 then target_track_idx = 0 end

                local target_track = r.GetTrack(0, target_track_idx)
                if not target_track then
                    r.InsertTrackAtIndex(target_track_idx, true)
                    target_track = r.GetTrack(0, target_track_idx)
                end

                if target_track then
                    r.SetOnlyTrackSelected(target_track)
                end

                -- Get event and insert with volume = weight
                local evt = Core.GetTriggerEvent(Core.Project.selected_note, set_idx)
                if evt then
                    -- Temporarily modify vol_offset based on weight
                    local orig_vol = evt.vol_offset or 0
                    evt.vol_offset = orig_vol + 20 * math.log(weight, 10)  -- Convert to dB

                    Core.InsertEventItems(evt, pos, corner_set)

                    evt.vol_offset = orig_vol  -- Restore
                    inserted = inserted + 1
                end
            end
        end
    end

    -- Restore track selection
    if base_track then
        r.SetOnlyTrackSelected(base_track)
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Corner Mix Insert", -1)

    Core.Log(string.format("Corner Mix: Inserted %d layers", inserted))
    return inserted > 0
end

-- Vector Recording state
Core.VectorRecording = {
    active = false,
    points = {},  -- {pos=, x=, y=}
    last_marker_idx = 0,
    last_play_pos = 0
}

-- Start vector recording
function Core.StartVectorRecording()
    Core.VectorRecording.active = true
    Core.VectorRecording.points = {}
    Core.VectorRecording.last_marker_idx = 0
    Core.VectorRecording.last_play_pos = 0
    Core.Log("Vector Recording: Started")
end

-- Stop vector recording and process
function Core.StopVectorRecording()
    Core.VectorRecording.active = false
    local points = Core.VectorRecording.points

    if #points == 0 then
        Core.Log("Vector Recording: No points captured")
        return
    end

    Core.Log(string.format("Vector Recording: Processing %d points", #points))

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Insert events at each point with interpolated mix
    for i, pt in ipairs(points) do
        -- Calculate interpolation weight (gradual change between points)
        local next_pt = points[i + 1]
        local interp_x = pt.x
        local interp_y = pt.y

        -- Linear interpolation toward next point (optional, for future enhancement)
        -- For now just use the point value directly
        _ = next_pt  -- Suppress unused warning

        -- Save current XY
        local k = Core.Project.keys[Core.Project.selected_note]
        local s = k and k.sets[Core.Project.selected_set]
        if s then
            local orig_x, orig_y = s.xy_x, s.xy_y
            s.xy_x = interp_x
            s.xy_y = interp_y

            Core.InsertWithCornerMix(pt.pos)

            s.xy_x = orig_x
            s.xy_y = orig_y
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Vector Recording", -1)

    Core.Log(string.format("Vector Recording: Completed with %d events", #points))
end

-- Poll for vector recording (called from main loop during playback)
function Core.PollVectorRecording()
    if not Core.VectorRecording.active then return end
    if r.GetPlayState() == 0 then return end  -- Not playing

    local play_pos = r.GetPlayPosition()
    if play_pos <= Core.VectorRecording.last_play_pos then return end

    -- Check for markers between last_pos and play_pos
    local num_markers = r.CountProjectMarkers(0)
    for i = 0, num_markers - 1 do
        local _, is_rgn, marker_pos = r.EnumProjectMarkers(i)
        if not is_rgn and marker_pos > Core.VectorRecording.last_play_pos and marker_pos <= play_pos then
            -- Found a marker - capture current XY position
            local k = Core.Project.keys[Core.Project.selected_note]
            local s = k and k.sets[Core.Project.selected_set]
            if s then
                table.insert(Core.VectorRecording.points, {
                    pos = marker_pos,
                    x = s.xy_x,
                    y = s.xy_y
                })
                Core.Log(string.format("Vector: Captured point at %.2f (XY: %.0f%%, %.0f%%)",
                    marker_pos, s.xy_x*100, s.xy_y*100))
            end
        end
    end

    Core.VectorRecording.last_play_pos = play_pos
end

return Core
