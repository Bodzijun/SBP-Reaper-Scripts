-- @description Voiceover Batch Processor (ReaImGui)
-- @version 2.0
-- @SBP & AI
-- @about
-- # Multi-function tool for processing voiceover items in REAPER (Sorting, spacing, fades, trimming, rate adjustment, and alignment).
-- @changelog
-- # v2.0 - Major overhaul with improved UI and functionality.

local r = reaper
local ctx = r.ImGui_CreateContext('VO Tool v2.9')

local params = {
    rate = 1.0,
    lock_pitch = true,
    
    spacing_val = 0.0, 
    spacing_max = 3.0,
    spacing_use_groups = false,
    spacing_max_gap = 1.0,
    
    fade_in = 0.010,
    fade_out = 0.010,
    
    trim_start = 0.0,
    trim_end = 0.0,
    
    auto_regions = false,
    region_gap_threshold = 3.0,
    region_pad_start = 0.250,
    region_pad_end = 0.250,
    
    region_reposition_gap = 1.0,

    heal_gap = 1.0,
    heal_enabled = true,
    align_create_region = true,
    align_mode = 0,
    align_group_gap = 1.0,
    align_center_mode = 1,
    align_destination_mode = 0,
    align_sort_stacks = true
}

local drag_state = {
    items_data = {} 
}

local COLOR_BG_DARK     = 0x1A1A1AFF
local COLOR_BG_LIGHTER  = 0x252525FF
local COLOR_ACCENT      = 0x2D8C6DFF
local COLOR_ACCENT_LITE = 0x2A7A5FFF
local COLOR_HEADER      = 0xFF8C6DFF
local COLOR_TEXT        = 0xE0E0E0FF
local COLOR_TEXT_DIM    = 0x808080FF

local header_font = nil

local function GetNonLinearSpacing(slider_val, max_sec)
    return (slider_val ^ 2) * max_sec
end

local function RecoverItemByGUID(guid_str)
    local count = r.CountMediaItems(0)
    for i = 0, count - 1 do
        local item = r.GetMediaItem(0, i)
        local retval, curr_guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
        if curr_guid == guid_str then return item end
    end
    return nil
end

local function ValidateOrRecover(data_row)
    if r.ValidatePtr(data_row.item, "MediaItem") then return data_row.item end
    local recovered = RecoverItemByGUID(data_row.guid)
    if recovered then
        data_row.item = recovered
        return recovered
    end
    return nil
end

local function SaveItemsState()
    drag_state.items_data = {}
    local count = r.CountSelectedMediaItems(0)
    if count == 0 then return end

    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        local retval, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
        
        local d = {
            item = item,
            guid = guid,
            has_take = (take ~= nil),
            pos = r.GetMediaItemInfo_Value(item, "D_POSITION"),
            len = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
            fadein = r.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
            fadeout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
        }
        if take then
            d.take_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            d.take_off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            d.take_vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
        else
            d.take_rate = 1.0; d.take_off = 0.0; d.take_vol = 1.0
        end
        drag_state.items_data[#drag_state.items_data + 1] = d
    end
end

local function ApplyRate()
    r.PreventUIRefresh(1)
    for _, data in ipairs(drag_state.items_data) do
        local item = ValidateOrRecover(data)
        if item and data.has_take then
            local take = r.GetActiveTake(item)
            if take then
                r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", params.rate)
                local new_len = data.len * (data.take_rate / params.rate)
                r.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", params.lock_pitch and 1 or 0)
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function ApplySpacing()
    local sorted = {}
    for i,v in ipairs(drag_state.items_data) do sorted[i] = v end
    table.sort(sorted, function(a,b) return a.pos < b.pos end)
    
    if #sorted == 0 then return end
    
    local gap = GetNonLinearSpacing(params.spacing_val, params.spacing_max)
    
    r.PreventUIRefresh(1)
    
    if params.spacing_use_groups then
        -- Group items by the maximum allowed distance
        local groups = {}
        local current_group = {sorted[1]}
        
        for i = 2, #sorted do
            local prev = sorted[i-1]
            local curr = sorted[i]
            local distance = curr.pos - (prev.pos + prev.len)
            
            if distance <= params.spacing_max_gap then
                table.insert(current_group, curr)
            else
                table.insert(groups, current_group)
                current_group = {curr}
            end
        end
        table.insert(groups, current_group)
        
        -- Process each group separately
        for _, group in ipairs(groups) do
            local cursor = group[1].pos + group[1].len
            for j = 2, #group do
                local data = group[j]
                local item = ValidateOrRecover(data)
                if item then
                    local new_start = cursor + gap
                    r.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
                    cursor = new_start + data.len
                end
            end
        end
    else
        -- Legacy mode: pack all items together without grouping
        local first = sorted[1]
        local current_cursor = first.pos + first.len 
        
        for i = 2, #sorted do
            local data = sorted[i]
            local item = ValidateOrRecover(data)
            if item then
                local new_start = current_cursor + gap
                r.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
                current_cursor = new_start + data.len
            end
        end
    end
    
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function ApplyFades()
    r.PreventUIRefresh(1)
    for _, data in ipairs(drag_state.items_data) do
        local item = ValidateOrRecover(data)
        if item then
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", params.fade_in)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", params.fade_out)
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function ApplyTrim()
    r.PreventUIRefresh(1)
    for _, data in ipairs(drag_state.items_data) do
        local item = ValidateOrRecover(data)
        if item and data.has_take then
            local take = r.GetActiveTake(item)
            if take then
                local total_trim = params.trim_start + params.trim_end
                if total_trim < data.len then
                    local new_pos = data.pos + params.trim_start
                    local new_len = data.len - total_trim
                    local new_off = data.take_off + (params.trim_start * params.rate)
                    
                    r.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                    r.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_off)
                end
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function HealSplits()
    while true do
        local count = r.CountSelectedMediaItems(0)
        if count < 2 then return end

        local items = {}
        local initial_guids = {}
        for i = 0, count - 1 do
            local item = r.GetSelectedMediaItem(0, i)
            if item then
                table.insert(items, item)
                local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
                initial_guids[#initial_guids + 1] = guid or ""
            end
        end

        if #items < 2 then return end

        table.sort(items, function(a, b)
            return r.GetMediaItemInfo_Value(a, "D_POSITION") < r.GetMediaItemInfo_Value(b, "D_POSITION")
        end)

        local healed = false
        for i = 1, #items - 1 do
            local item_a = items[i]
            local item_b = items[i + 1]
            local pos_a = r.GetMediaItemInfo_Value(item_a, "D_POSITION")
            local len_a = r.GetMediaItemInfo_Value(item_a, "D_LENGTH")
            local pos_b = r.GetMediaItemInfo_Value(item_b, "D_POSITION")
            local gap = pos_b - (pos_a + len_a)

            if gap > 0.0005 and gap <= params.heal_gap then
                r.Main_OnCommand(40289, 0)
                r.SetMediaItemSelected(item_a, true)
                r.SetMediaItemSelected(item_b, true)
                r.Main_OnCommand(40548, 0)
                healed = true

                -- Restore the selection of all originally selected items via GUID
                r.Main_OnCommand(40289, 0)
                for _, guid in ipairs(initial_guids) do
                    local item = RecoverItemByGUID(guid)
                    if item then
                        r.SetMediaItemSelected(item, true)
                    end
                end

                break
            end
        end

        if not healed then return end
    end
end

local function AlignItemsByCenter()
    local count = r.CountSelectedMediaItems(0)
    if count < 2 then return end
    
    local items = {}
    for i = 0, count - 1 do
        table.insert(items, r.GetSelectedMediaItem(0, i))
    end
    
    table.sort(items, function(a,b) 
        return r.GetMediaItemInfo_Value(a, "D_POSITION") < r.GetMediaItemInfo_Value(b, "D_POSITION")
    end)
    
    local first = items[1]
    local first_pos = r.GetMediaItemInfo_Value(first, "D_POSITION")
    local first_len = r.GetMediaItemInfo_Value(first, "D_LENGTH")
    local first_ref = first_pos + (params.align_center_mode == 1 and first_len / 2 or 0)
    local first_track = r.GetMediaItemTrack(first)
    local first_track_idx = math.floor(r.GetMediaTrackInfo_Value(first_track, "IP_TRACKNUMBER") + 0.5)
    
    local longest = first
    local longest_len = first_len
    local lane_mode = params.align_destination_mode == 1

    r.PreventUIRefresh(1)
    if lane_mode then
        r.SetMediaTrackInfo_Value(first_track, "I_FREEMODE", 2)
    end
    local rest = {}
    for i = 2, #items do
        rest[#rest+1] = items[i]
    end
    table.sort(rest, function(a,b)
        return r.GetMediaItemInfo_Value(a, "D_LENGTH") > r.GetMediaItemInfo_Value(b, "D_LENGTH")
    end)
    
    for i = 1, #rest do
        local item = rest[i]
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local ref_point = pos + (params.align_center_mode == 1 and len / 2 or 0)
        local new_pos = pos + (first_ref - ref_point)
        
        r.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
        
        local target_track = first_track
        if not lane_mode then
            local need_track_idx = first_track_idx + i
            while r.CountTracks(0) < need_track_idx do
                r.InsertTrackAtIndex(r.CountTracks(0), true)
            end
            target_track = r.GetTrack(0, need_track_idx - 1)
        end
        r.MoveMediaItemToTrack(item, target_track)
        if lane_mode then
            r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", i)
        end

        if len > longest_len then
            longest = item
            longest_len = len
        end
    end

    if lane_mode then
        r.SetMediaItemInfo_Value(first, "I_FIXEDLANE", 0)
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    if lane_mode then
        r.UpdateItemLanes(0)
    end

    local longest_start = r.GetMediaItemInfo_Value(longest, "D_POSITION")
    local longest_len = r.GetMediaItemInfo_Value(longest, "D_LENGTH")
    return {start = longest_start, finish = longest_start + longest_len}
end

local function AlignGroupedDuplicates()
    local count = r.CountSelectedMediaItems(0)
    if count < 2 then return nil end

    local items = {}
    for i = 0, count - 1 do
        table.insert(items, r.GetSelectedMediaItem(0, i))
    end

    table.sort(items, function(a, b)
        return r.GetMediaItemInfo_Value(a, "D_POSITION") < r.GetMediaItemInfo_Value(b, "D_POSITION")
    end)

    local groups = {}
    local current_group = {items[1]}

    for i = 2, #items do
        local prev = items[i - 1]
        local curr = items[i]
        local prev_pos = r.GetMediaItemInfo_Value(prev, "D_POSITION")
        local prev_len = r.GetMediaItemInfo_Value(prev, "D_LENGTH")
        local prev_end = prev_pos + prev_len
        local curr_pos = r.GetMediaItemInfo_Value(curr, "D_POSITION")
        local gap = curr_pos - prev_end

        if gap <= params.align_group_gap then
            current_group[#current_group + 1] = curr
        else
            groups[#groups + 1] = current_group
            current_group = {curr}
        end
    end
    groups[#groups + 1] = current_group

    if #groups < 2 then
        return AlignItemsByCenter()
    end

    local function compute_bounds(group)
        local min_pos = math.huge
        local max_pos = -math.huge
        for _, item in ipairs(group) do
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            if pos < min_pos then min_pos = pos end
            local end_pos = pos + len
            if end_pos > max_pos then max_pos = end_pos end
        end
        return min_pos, max_pos
    end

    local stacks = {}
    for _, grp in ipairs(groups) do
        local min_pos, max_pos = compute_bounds(grp)
        local length = max_pos - min_pos
        local center = params.align_center_mode == 1 and (min_pos + max_pos) / 2 or min_pos
        stacks[#stacks + 1] = {
            items = grp,
            center = center,
            length = length,
            start = min_pos,
            finish = max_pos
        }
    end

    local ordered = {}
    for _, entry in ipairs(stacks) do ordered[#ordered + 1] = entry end
    if params.align_sort_stacks then
        table.sort(ordered, function(a, b)
            return a.length > b.length
        end)
    end

    local reference_entry = ordered[1]
    local ref_first_item = reference_entry.items[1]
    local ref_track = r.GetMediaItemTrack(ref_first_item)
    if not ref_track then
        r.ShowConsoleMsg("[VO Tool] AlignGroupedDuplicates: missing base track\n")
        return nil
    end
    local first_track_idx = math.floor(r.GetMediaTrackInfo_Value(ref_track, "IP_TRACKNUMBER") + 0.5)
    local lane_mode = params.align_destination_mode == 1

    if lane_mode then
        r.SetMediaTrackInfo_Value(ref_track, "I_FREEMODE", 2)
        for _, item in ipairs(reference_entry.items) do
            if r.GetMediaItemTrack(item) ~= ref_track then
                r.MoveMediaItemToTrack(item, ref_track)
            end
            r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", 0)
        end
    end

    local overall_start = reference_entry.start
    local overall_finish = reference_entry.finish
    r.PreventUIRefresh(1)
    for idx = 2, #ordered do
        local grp = ordered[idx]
        local target_track = ref_track
        if not lane_mode then
            local target_track_idx = first_track_idx + idx - 1
            while r.CountTracks(0) < target_track_idx do
                r.InsertTrackAtIndex(r.CountTracks(0), true)
            end
            target_track = r.GetTrack(0, target_track_idx - 1)
        end
        local delta = reference_entry.center - grp.center
        for _, item in ipairs(grp.items) do
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            r.SetMediaItemInfo_Value(item, "D_POSITION", pos + delta)
            r.MoveMediaItemToTrack(item, target_track)
            if lane_mode then
                r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", idx - 1)
            end
        end
        local shifted_start = grp.start + delta
        local shifted_finish = grp.finish + delta
        if shifted_start < overall_start then overall_start = shifted_start end
        if shifted_finish > overall_finish then overall_finish = shifted_finish end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    if lane_mode then
        r.UpdateItemLanes(0)
    end

    return {start = overall_start, finish = overall_finish}
end

local function ApplyAlignDuplicates()
    if r.CountSelectedMediaItems(0) < 2 then return end
    r.Undo_BeginBlock()
    if params.align_mode == 0 and params.heal_enabled then
        HealSplits()
    end
    SaveItemsState()
    local reference_bounds = nil
    if params.align_mode == 0 then
        reference_bounds = AlignItemsByCenter()
    else
        reference_bounds = AlignGroupedDuplicates()
    end
    if params.align_create_region and reference_bounds then
        local region_pad = 0.150
        local start = reference_bounds.start - region_pad
        if start < 0 then start = 0 end
        local finish = reference_bounds.finish + region_pad
        r.AddProjectMarker2(0, true, start, finish, "Group Region", -1, 0)
        r.UpdateTimeline()
    end
    r.Undo_EndBlock("Align Duplicates", -1)
end

local function ResetManualVolume()
    r.PreventUIRefresh(1)
    for _, data in ipairs(drag_state.items_data) do
        local item = ValidateOrRecover(data)
        if item then
            r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
            local take = r.GetActiveTake(item)
            if take then
                r.SetMediaItemTakeInfo_Value(take, "D_VOL", 1.0)
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function UpdateRegions(force_update)
    if not params.auto_regions and not force_update then return end
    local count = r.CountSelectedMediaItems(0)
    if count == 0 then return end
    
    r.PreventUIRefresh(1)

    local items = {}
    local min_start = 9999999999
    local max_end = -9999999999
    
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_pos = pos + len
        if pos < min_start then min_start = pos end
        if end_pos > max_end then max_end = end_pos end
        items[#items+1] = {s = pos, e = end_pos}
    end
    
    table.sort(items, function(a,b) return a.s < b.s end)
    
    local search_start = min_start - 5.0
    local search_end = max_end + 5.0
    local num_markers, num_regions = r.CountProjectMarkers(0)
    for i = num_markers + num_regions - 1, 0, -1 do
        local retval, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers(i)
        if retval and isrgn then
            if (pos < search_end) and (rgnend > search_start) then
                r.DeleteProjectMarker(0, idx, true)
            end
        end
    end
    
    if #items > 0 then
        local cluster_start = items[1].s
        local cluster_end = items[1].e
        
        for k = 2, #items do
            local curr = items[k]
            local gap = curr.s - cluster_end
            if gap <= params.region_gap_threshold then
                cluster_end = curr.e
                if curr.e > cluster_end then cluster_end = curr.e end
            else
                r.AddProjectMarker(0, true, cluster_start - params.region_pad_start, cluster_end + params.region_pad_end, "", -1)
                cluster_start = curr.s
                cluster_end = curr.e
            end
        end
        r.AddProjectMarker(0, true, cluster_start - params.region_pad_start, cluster_end + params.region_pad_end, "", -1)
    end
    r.PreventUIRefresh(-1)
    r.UpdateTimeline()
end

local function ApplyRegionSpacing()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then return end
    
    local affected_regions = {}
    local region_map = {} 
    
    local ret, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = num_markers + num_regions
    
    local all_regions = {}
    for i = 0, total - 1 do
        local retval, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers(i)
        if retval and isrgn then
            all_regions[#all_regions+1] = {idx=idx, s=pos, e=rgnend}
        end
    end
    
    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local center = pos + (item_end - pos)/2
        
        for _, reg in ipairs(all_regions) do
            if center >= reg.s and center <= reg.e then
                if not region_map[reg.idx] then
                    region_map[reg.idx] = true
                    affected_regions[#affected_regions+1] = reg
                end
            end
        end
    end
    
    if #affected_regions < 2 then return end
    table.sort(affected_regions, function(a,b) return a.s < b.s end)
    
    r.PreventUIRefresh(1)
    
    local current_end_cursor = affected_regions[1].e
    
    for i = 2, #affected_regions do
        local reg = affected_regions[i]
        local target_start = current_end_cursor + params.region_reposition_gap
        local delta = target_start - reg.s
        
        if math.abs(delta) > 0.000001 then
            local new_start = reg.s + delta
            local new_end = reg.e + delta
            r.SetProjectMarker(reg.idx, true, new_start, new_end, "")
            
            for k = 0, sel_count - 1 do
                local item = r.GetSelectedMediaItem(0, k)
                local ipos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                local iend = ipos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
                local icenter = ipos + (iend - ipos)/2
                
                if icenter >= reg.s and icenter <= reg.e then
                    r.SetMediaItemInfo_Value(item, "D_POSITION", ipos + delta)
                end
            end
            reg.s = new_start
            reg.e = new_end
        end
        current_end_cursor = reg.e
    end
    
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.UpdateTimeline()
end

local function SetModernTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLOR_BG_DARK)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLOR_BG_DARK)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x353535FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_MenuBarBg(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), COLOR_BG_DARK)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGrip(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_TEXT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), COLOR_TEXT_DIM)

    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 16, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 10, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(), 6, 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.5, 0.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 0.0, 0.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupBorderSize(), 1)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
end

local function DrawSectionHeader(name)
    if header_font then r.ImGui_PushFont(ctx, header_font, 1.0) end
    r.ImGui_Selectable(ctx, "  " .. name, false, r.ImGui_SelectableFlags_SpanAllColumns())
    if header_font then r.ImGui_PopFont(ctx) end
    r.ImGui_Spacing(ctx)
end

local function DrawApplyBtn(id_suffix, func)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Apply##" .. id_suffix, 80, 0) then
        r.Undo_BeginBlock()
        SaveItemsState()
        func()
        if params.auto_regions then UpdateRegions(false) end
        r.Undo_EndBlock("Apply " .. id_suffix, -1)
    end
end

local function DrawGroupBorder()
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    if draw_list and x1 and y1 and x2 and y2 then
        local win_x = r.ImGui_GetWindowPos(ctx)
        local win_w = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_DrawList_AddLine(draw_list, win_x, y2 + 4, win_x + win_w, y2 + 4, 0x3A3A3AFF, 1)
    end
end

local function FinishSection()
    r.ImGui_Dummy(ctx, 0, 6)
    DrawGroupBorder()
    r.ImGui_Dummy(ctx, 0, 4)
    r.ImGui_Spacing(ctx)
end

local function Loop()
    SetModernTheme()
    
    r.ImGui_SetNextWindowSize(ctx, 450, 620, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'VO Tool v2.0', true)
    
    if visible then
        
        local sel_count = r.CountSelectedMediaItems(0)
        r.ImGui_Separator(ctx)
        if sel_count > 0 then
            r.ImGui_TextColored(ctx, 0x77DD77FF, "ACTIVE SELECTION: " .. sel_count .. " Items")
        else
            r.ImGui_TextColored(ctx, 0xEE6666FF, "NO SELECTION")
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        r.ImGui_BeginGroup(ctx)
            DrawSectionHeader("TIMING & PITCH")
            r.ImGui_Indent(ctx, 5)

            r.ImGui_SetNextItemWidth(ctx, 140)
            local r_changed, new_rate = r.ImGui_SliderDouble(ctx, "Rate", params.rate, 0.5, 2.0, "%.2fx")
            if r_changed then params.rate = new_rate end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Adjust playback rate of selected items") end

            local rate_active = r.ImGui_IsItemActive(ctx)
            local rate_activated = r.ImGui_IsItemActivated(ctx)
            local rate_deactivated = r.ImGui_IsItemDeactivated(ctx)

            DrawApplyBtn("Rate", ApplyRate)

            if rate_activated then r.Undo_BeginBlock(); SaveItemsState() end
            if rate_active then ApplyRate(); if params.auto_regions then UpdateRegions(false) end end
            if rate_deactivated then r.Undo_EndBlock("Rate Change", -1) end

            r.ImGui_SameLine(ctx)
            local p_changed, new_p = r.ImGui_Checkbox(ctx, "Pitch Lock", params.lock_pitch)
            if p_changed then params.lock_pitch = new_p; SaveItemsState(); ApplyRate() end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Lock pitch when changing rate") end
            r.ImGui_Unindent(ctx, 5)
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            DrawSectionHeader("ITEM SPACING")
            r.ImGui_Indent(ctx, 5)

            local real_gap = GetNonLinearSpacing(params.spacing_val, params.spacing_max)
            r.ImGui_Text(ctx, string.format("Item Gap: %.3f sec", real_gap))

            r.ImGui_SetNextItemWidth(ctx, 140)
            local s_changed, new_s = r.ImGui_SliderDouble(ctx, "##GapSlider", params.spacing_val, 0.0, 1.0, "")
            if s_changed then params.spacing_val = new_s end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Adjust spacing between items") end

            local space_active = r.ImGui_IsItemActive(ctx)
            local space_activated = r.ImGui_IsItemActivated(ctx)
            local space_deactivated = r.ImGui_IsItemDeactivated(ctx)

            DrawApplyBtn("Spacing", ApplySpacing)

            if space_activated then r.Undo_BeginBlock(); SaveItemsState() end
            if space_active then ApplySpacing(); if params.auto_regions then UpdateRegions(false) end end
            if space_deactivated then r.Undo_EndBlock("Spacing Change", -1) end

            local use_groups_ch, new_use_groups = r.ImGui_Checkbox(ctx, "Use Groups", params.spacing_use_groups)
            if use_groups_ch then params.spacing_use_groups = new_use_groups end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Group items by max gap distance") end

            if params.spacing_use_groups then
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 100)
                local mg_ch, new_mg = r.ImGui_SliderDouble(ctx, "##MaxGap", params.spacing_max_gap, 0.1, 5.0, "%.2fs")
                if mg_ch then params.spacing_max_gap = new_mg end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Only group items closer than this distance") end
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Max Gap")
            end

            r.ImGui_Unindent(ctx, 5)
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            DrawSectionHeader("TRIM & FADES")
            r.ImGui_Indent(ctx, 5)

            if r.ImGui_BeginTable(ctx, "EditTable", 2) then
                r.ImGui_TableSetupColumn(ctx, "C1", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, "C2", r.ImGui_TableColumnFlags_WidthStretch())

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ts_ch, new_ts = r.ImGui_SliderDouble(ctx, "Trim Start", params.trim_start, 0.0, 0.5, "%.3fs")
                if ts_ch then params.trim_start = new_ts end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Trim start of items") end
                if r.ImGui_IsItemActivated(ctx) then r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyTrim(); if params.auto_regions then UpdateRegions(false) end end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Trim Start", -1) end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local te_ch, new_te = r.ImGui_SliderDouble(ctx, "Trim End", params.trim_end, 0.0, 0.5, "%.3fs")
                if te_ch then params.trim_end = new_te end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Trim end of items") end
                if r.ImGui_IsItemActivated(ctx) then r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyTrim(); if params.auto_regions then UpdateRegions(false) end end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Trim End", -1) end

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local fi_ch, new_fi = r.ImGui_SliderDouble(ctx, "Fade In", params.fade_in, 0.0, 1.0, "%.3fs")
                if fi_ch then params.fade_in = new_fi end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Fade in length") end
                if r.ImGui_IsItemActivated(ctx) then r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyFades() end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Fade In", -1) end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local fo_ch, new_fo = r.ImGui_SliderDouble(ctx, "Fade Out", params.fade_out, 0.0, 1.0, "%.3fs")
                if fo_ch then params.fade_out = new_fo end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Fade out length") end
                if r.ImGui_IsItemActivated(ctx) then r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyFades() end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Fade Out", -1) end

                r.ImGui_EndTable(ctx)
            end
            r.ImGui_Unindent(ctx, 5)
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            DrawSectionHeader("REGIONS")
            r.ImGui_Indent(ctx, 5)

            r.ImGui_Text(ctx, "New Regions")
            r.ImGui_Spacing(ctx)

            local reg_on_ch, new_reg_on = r.ImGui_Checkbox(ctx, "Auto Live Update", params.auto_regions)
            if reg_on_ch then params.auto_regions = new_reg_on end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Automatically update regions when slider change") end

            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            local th_ch, new_th = r.ImGui_SliderDouble(ctx, "##MaxSil", params.region_gap_threshold, 0.1, 10.0, "%.1fs")
            if th_ch then params.region_gap_threshold = new_th; if params.auto_regions then r.Undo_BeginBlock(); UpdateRegions(false); r.Undo_EndBlock("Reg Threshold", -1) end end
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Max Silence")
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Maximum silence gap to merge regions") end

            r.ImGui_Spacing(ctx)

            if r.ImGui_BeginTable(ctx, "PadTable", 3) then
                r.ImGui_TableSetupColumn(ctx, "C1", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, "C2", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, "C3", r.ImGui_TableColumnFlags_WidthStretch())
                
                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_Text(ctx, "Pad Start")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_Text(ctx, "Pad End")
                
                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ps_ch, new_ps = r.ImGui_SliderDouble(ctx, "##PadL", params.region_pad_start, 0.0, 1.0, "%.2f")
                if ps_ch then params.region_pad_start = new_ps; if params.auto_regions then r.Undo_BeginBlock(); UpdateRegions(false); r.Undo_EndBlock("Reg Pad", -1) end end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local pe_ch, new_pe = r.ImGui_SliderDouble(ctx, "##PadR", params.region_pad_end, 0.0, 1.0, "%.2f")
                if pe_ch then params.region_pad_end = new_pe; if params.auto_regions then r.Undo_BeginBlock(); UpdateRegions(false); r.Undo_EndBlock("Reg Pad", -1) end end

                r.ImGui_TableSetColumnIndex(ctx, 2)
                if r.ImGui_Button(ctx, "Create##Now", -1, 0) then
                    r.Undo_BeginBlock(); UpdateRegions(true); r.Undo_EndBlock("Create Regions", -1)
                end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create regions from selected items") end
                r.ImGui_EndTable(ctx)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, "Region Reposition")
            r.ImGui_SetNextItemWidth(ctx, 100)
            local rr_ch, new_rr = r.ImGui_SliderDouble(ctx, "##RegGap", params.region_reposition_gap, 0.0, 5.0, "%.2fs")
            if rr_ch then params.region_reposition_gap = new_rr end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Gap between repositioned regions") end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Gap")
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Align", 60, 0) then
                r.Undo_BeginBlock(); ApplyRegionSpacing(); r.Undo_EndBlock("Align Regions", -1)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align selected regions with specified gap") end

            r.ImGui_Unindent(ctx, 5)
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            DrawSectionHeader("ALIGN DUPLICATES")
            r.ImGui_Indent(ctx, 5)

            local align_mode_labels = {"Per Item Stack", "Group Stack"}
            r.ImGui_Text(ctx, "Align Mode")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 170)
            local current_align_label = align_mode_labels[params.align_mode + 1]
            if r.ImGui_BeginCombo(ctx, "##AlignModeCombo", current_align_label) then
                for idx, label in ipairs(align_mode_labels) do
                    local is_selected = params.align_mode == idx - 1
                    if r.ImGui_Selectable(ctx, label, is_selected) then
                        params.align_mode = idx - 1
                    end
                    if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            r.ImGui_SameLine(ctx)
            local create_rgn_ch, new_create_rgn = r.ImGui_Checkbox(ctx, "Create Region", params.align_create_region)
            if create_rgn_ch then params.align_create_region = new_create_rgn end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create region around aligned items") end

            local center_labels = {"Left Edge", "Center"}
            r.ImGui_Text(ctx, "Centering")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##CenterCombo", center_labels[params.align_center_mode + 1]) then
                for idx, label in ipairs(center_labels) do
                    local is_sel = params.align_center_mode == idx - 1
                    if r.ImGui_Selectable(ctx, label, is_sel) then
                        params.align_center_mode = idx - 1
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align by center or left edge") end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Destination")
            r.ImGui_SameLine(ctx)
            local dest_labels = {"New Tracks", "Fixed Lanes"}
            r.ImGui_SetNextItemWidth(ctx, 150)
            if r.ImGui_BeginCombo(ctx, "##DestinationCombo", dest_labels[params.align_destination_mode + 1]) then
                for idx, label in ipairs(dest_labels) do
                    local is_sel = params.align_destination_mode == idx - 1
                    if r.ImGui_Selectable(ctx, label, is_sel) then
                        params.align_destination_mode = idx - 1
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create a new track or use fixed lanes") end

            local sort_ch, new_sort = r.ImGui_Checkbox(ctx, "Sort stacks by length", params.align_sort_stacks)
            if sort_ch then params.align_sort_stacks = new_sort end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Order groups by length or keep them in timeline order") end

            if params.align_mode == 0 then
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, "Pre-Alignment")
                r.ImGui_SameLine(ctx)
                local heal_ch, new_heal = r.ImGui_Checkbox(ctx, "Heal Splits", params.heal_enabled)
                if heal_ch then params.heal_enabled = new_heal end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Merge items closer than the maximum gap") end
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                local hg_ch, new_hg = r.ImGui_SliderDouble(ctx, "##HealGap", params.heal_gap, 0.1, 5.0, "%.2fs")
                if hg_ch then params.heal_gap = new_hg end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Maximum gap to heal") end
            else
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, "Group Gap")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                local gap_ch, new_gap = r.ImGui_SliderDouble(ctx, "##AlignGroupGap", params.align_group_gap, 0.1, 5.0, "%.2fs")
                if gap_ch then params.align_group_gap = new_gap end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Max gap to treat items as one duplicate group") end
            end

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, "Align##Duplicates", -1, 0) then
                ApplyAlignDuplicates()
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align items by center on separate tracks") end

            r.ImGui_Unindent(ctx, 5)
        r.ImGui_EndGroup(ctx)
        FinishSection()
        r.ImGui_End(ctx)
    end
    
    -- PopStyleVar and PopStyleColor
    r.ImGui_PopStyleVar(ctx, 15)
    r.ImGui_PopStyleColor(ctx, 32)
    
    if open then r.defer(Loop) end
end

r.defer(Loop)
