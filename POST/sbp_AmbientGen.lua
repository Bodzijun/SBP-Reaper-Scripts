-- @description SBP AmbientGenerator
-- @version 0.9 beta
-- @author SBP & AI
-- @about Acceleration tool for automatically filling the environment for all scenes in a movie using a prepared location design.
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   initial beta release


local r = reaper
local ctx = r.ImGui_CreateContext('AmbientGen_v82')
math.randomseed(os.time())

-- =========================================================
-- COLORS
-- =========================================================
local C_BG       = 0x252525FF
local C_TITLE    = 0x202020FF
local C_FRAME    = 0x1A1A1AFF
local C_TEXT     = 0xDEDEDEFF
local C_BTN      = 0x383838FF
local C_BTN_HOVR = 0x454545FF

local C_TAG_RED  = 0xAA4A47FF
local C_TAG_HOVR = 0xC25E5BFF
local C_GEN_TEAL = 0x226757FF
local C_GEN_HOVR = 0x29D0A9FF
local C_AUTO_ORG = 0xD4753FFF
local C_AUTO_HOV = 0xB56230FF

local EXTSTATE_SECTION = "SBP_AmbientGen"
local SOURCE_ROOT_NAME = "#LOC_PRESET"
local DEST_ROOT_NAME   = "#AMB_BUS"

-- Magic number constants
local BLOCK_MERGE_TOLERANCE = 0.5      -- seconds tolerance for merging adjacent blocks
local SOURCE_MATCH_TOLERANCE = 0.1     -- seconds tolerance for matching source positions
local REAPER_COLOR_FLAG = 0x1000000    -- flag to mark color as custom in REAPER

local params = {
    -- BEDS
    bed_overlap = 2.0, bed_fade = 2.0, bed_vol_db = -6.0, bed_trim = 0.5,
    bed_randomize = 0.0, bed_min_slice = 8.0, bed_grain_overlap = 0.5,  -- grain_overlap = crossfade between random slices
    -- SPOTS
    spot_density_sec = 10.0,
    spot_min_gap = 3.0,
    spot_intensity = 1.0,
    spot_edge_bias = true,
    spot_dist_sim  = 0.5,
    seed_lock = false,
    -- HUMANIZE
    spot_vol_var = 3.0, spot_pitch_var = 2.0, spot_pan_var = 0.5,
    -- GLOBAL
    create_regions = false,
    target_mode = 0,  -- 0=New (create structure), 1=Selected (use selected tracks), 2=ByName (find by spot/bed)
    color_items = true,           -- Color generated items with preset color
    group_items = false,          -- Group generated items by location
    -- Hidden
    spot_fade = 0.2
}

local presets = {}
local selected_preset_index = 0
local log_msg = "Ready v8.2"
local show_tooltips = true
local HAS_SWS = false  -- will be set at startup
local delete_confirm_idx = -1  -- index of preset pending delete confirmation

-- =========================================================
-- HELPERS
-- =========================================================

function CheckSWS()
    -- Check if SWS extension is available
    return r.NamedCommandLookup("_XENAKIOS_SISFTRANDIF") ~= 0
end

function GetTrackByName(name)
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tr_name == name then return tr end
    end
    return nil
end

function GetRandomReaperColor()
    local red = math.random(60, 200)
    local green = math.random(60, 200)
    local blue = math.random(60, 200)
    return r.ColorToNative(red, green, blue) | REAPER_COLOR_FLAG
end

function FindLocationFolderInRoot(root_track, loc_name)
    local root_depth = r.GetTrackDepth(root_track)
    local idx = r.GetMediaTrackInfo_Value(root_track, "IP_TRACKNUMBER") 
    local count = r.CountTracks(0)
    local k = idx 
    while k < count do
        local tr = r.GetTrack(0, k)
        if r.GetTrackDepth(tr) <= root_depth then break end
        local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if name == loc_name then return tr end
        k = k + 1
    end
    return nil
end

function GetOrCreateLocationFolder(bus_tr, name)
    local bus_idx = r.GetMediaTrackInfo_Value(bus_tr, "IP_TRACKNUMBER")
    local bus_depth = r.GetTrackDepth(bus_tr)
    local count = r.CountTracks(0)
    local k = bus_idx
    local insert_idx = bus_idx
    while k < count do
        local tr = r.GetTrack(0, k)
        if r.GetTrackDepth(tr) <= bus_depth then insert_idx = k break end
        local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tr_name == name then return tr end
        insert_idx = k + 1 
        k = k + 1
    end
    r.InsertTrackAtIndex(insert_idx, true)
    local new_tr = r.GetTrack(0, insert_idx)
    r.GetSetMediaTrackInfo_String(new_tr, "P_NAME", name, true)
    r.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", 1)
    local col = r.GetMediaTrackInfo_Value(bus_tr, "I_CUSTOMCOLOR")
    r.SetMediaTrackInfo_Value(new_tr, "I_CUSTOMCOLOR", col)
    return new_tr
end

-- Find tracks by type name (spot/bed), excluding source folder
function FindTracksByType(type_pattern)
    local tracks = {}
    local inside_source = false
    local source_depth = -1

    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local tr_depth = r.GetTrackDepth(tr)
        local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

        -- Check if entering or leaving source folder
        if tr_name == SOURCE_ROOT_NAME then
            inside_source = true
            source_depth = tr_depth
        elseif inside_source and tr_depth <= source_depth then
            inside_source = false
        end

        -- Skip if inside source folder
        if inside_source then goto continue end

        -- Match pattern
        if tr_name:lower():find(type_pattern:lower()) then
            table.insert(tracks, tr)
        end
        ::continue::
    end
    return tracks
end

function ApplyFadeToSelection(type_filter, fade_val)
    local cnt = r.CountSelectedMediaItems(0)
    if cnt == 0 then return end
    r.Undo_BeginBlock()
    for i=0, cnt-1 do
        local item = r.GetSelectedMediaItem(0, i)
        local tr = r.GetMediaItem_Track(item)
        local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local is_spot = tr_name:match("^SPOT_")
        local apply = false
        if type_filter == "BED" and not is_spot then apply = true end
        if type_filter == "SPOT" and is_spot then apply = true end
        if apply then
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_val)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_val)
        end
    end
    r.Undo_EndBlock("Adjust Fades", -1)
    r.UpdateArrange()
end

function ApplyVolToSelection(vol_db)
    local ok, err = pcall(function()
        local cnt = r.CountSelectedMediaItems(0)
        if cnt == 0 then return end
        local vol = 10^(vol_db/20)
        for i = 0, cnt - 1 do
            local item = r.GetSelectedMediaItem(0, i)
            if item then
                r.SetMediaItemInfo_Value(item, "D_VOL", vol)
            end
        end
        r.UpdateArrange()
    end)
    if not ok then
        r.ShowConsoleMsg("ApplyVolToSelection error: " .. tostring(err) .. "\n")
    end
end

-- =========================================================
-- PERSISTENCE (ExtState)
-- =========================================================

function SaveParams()
    -- Save all params
    for key, val in pairs(params) do
        local str_val = tostring(val)
        if type(val) == "boolean" then str_val = val and "1" or "0" end
        r.SetExtState(EXTSTATE_SECTION, "param_" .. key, str_val, true)
    end
    -- Save other settings
    r.SetExtState(EXTSTATE_SECTION, "SOURCE_ROOT_NAME", SOURCE_ROOT_NAME, true)
    r.SetExtState(EXTSTATE_SECTION, "show_tooltips", show_tooltips and "1" or "0", true)
    r.SetExtState(EXTSTATE_SECTION, "selected_preset_index", tostring(selected_preset_index), true)
end

-- Save preset colors by name
function SavePresetColors()
    local colors_str = ""
    for _, p in ipairs(presets) do
        if p.name and p.color then
            colors_str = colors_str .. p.name .. "=" .. string.format("%08X", p.color) .. ";"
        end
    end
    r.SetExtState(EXTSTATE_SECTION, "preset_colors", colors_str, true)
end

-- Load preset colors and apply to existing presets
function LoadPresetColors()
    local colors_str = r.GetExtState(EXTSTATE_SECTION, "preset_colors")
    if colors_str == "" then return end

    local saved_colors = {}
    for name, color_hex in string.gmatch(colors_str, "([^=]+)=(%x+);") do
        saved_colors[name] = tonumber(color_hex, 16)
    end

    -- Apply saved colors to presets
    for _, p in ipairs(presets) do
        if saved_colors[p.name] then
            p.color = saved_colors[p.name]
        end
    end
end

function LoadParams()
    -- Load params
    for key, default_val in pairs(params) do
        local stored = r.GetExtState(EXTSTATE_SECTION, "param_" .. key)
        if stored ~= "" then
            if type(default_val) == "boolean" then
                params[key] = (stored == "1")
            elseif type(default_val) == "number" then
                params[key] = tonumber(stored) or default_val
            end
        end
    end
    -- Load other settings
    local src_name = r.GetExtState(EXTSTATE_SECTION, "SOURCE_ROOT_NAME")
    if src_name ~= "" then SOURCE_ROOT_NAME = src_name end

    local tips = r.GetExtState(EXTSTATE_SECTION, "show_tooltips")
    if tips ~= "" then show_tooltips = (tips == "1") end

    local preset_idx = r.GetExtState(EXTSTATE_SECTION, "selected_preset_index")
    if preset_idx ~= "" then selected_preset_index = tonumber(preset_idx) or 0 end
end

-- =========================================================
-- PRESET LOGIC
-- =========================================================

function ReaperColorToImGui(reaper_color)
    if reaper_color == 0 then return C_TAG_RED end
    local r_val, g_val, b_val = r.ColorFromNative(reaper_color & 0xFFFFFF)
    return (r_val << 24) | (g_val << 16) | (b_val << 8) | 0xFF
end

function ImGuiColorToReaper(imgui_color)
    local r_val = (imgui_color >> 24) & 0xFF
    local g_val = (imgui_color >> 16) & 0xFF
    local b_val = (imgui_color >> 8) & 0xFF
    return r.ColorToNative(r_val, g_val, b_val) | REAPER_COLOR_FLAG
end

function ScanPresets()
    presets = {}
    local root = GetTrackByName(SOURCE_ROOT_NAME)
    if not root then log_msg = "Track '"..SOURCE_ROOT_NAME.."' not found. Create it first." return end
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
        local tr = r.GetTrack(0, i)
        local parent = r.GetParentTrack(tr)
        if parent == root then
            local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            local track_color = r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
            local preset_color = ReaperColorToImGui(track_color)
            local layers = {}
            local j = i + 1
            while j < count do
                local child = r.GetTrack(0, j)
                local child_parent = r.GetParentTrack(child)
                if child_parent == tr then
                    if r.CountTrackMediaItems(child) > 0 then
                        local _, l_name = r.GetSetMediaTrackInfo_String(child, "P_NAME", "", false)
                        local l_type = "BED"
                        if l_name:match("^SPOT_") then l_type = "SPOT" end
                        table.insert(layers, {track = child, name = l_name, type = l_type})
                    end
                elseif r.GetTrackDepth(child) <= r.GetTrackDepth(tr) then break end
                j = j + 1
            end
            table.insert(presets, {name = name, layers = layers, color = preset_color})
        end
    end
    log_msg = "Scanned " .. #presets .. " presets."
end

-- Helper: Check if item is empty (no active take or empty take)
local function IsEmptyItem(item)
    local take = r.GetActiveTake(item)
    if not take then return true end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return true end
    return false
end

-- Helper: Merge empty items by extending first and deleting others
local function MergeEmptyItems()
    local count = r.CountSelectedMediaItems(0)
    if count < 2 then return false end

    -- Check if ALL selected items are empty
    local all_empty = true
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item and not IsEmptyItem(item) then
            all_empty = false
            break
        end
    end

    if not all_empty then return false end

    -- Calculate total range
    local min_start, max_end = math.huge, -math.huge
    local first_item = nil
    local items_to_delete = {}

    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            if pos < min_start then
                min_start = pos
                first_item = item
            end
            if pos + len > max_end then
                max_end = pos + len
            end
        end
    end

    -- Collect items to delete (all except first)
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item and item ~= first_item then
            table.insert(items_to_delete, item)
        end
    end

    -- Extend first item to cover entire range
    if first_item then
        r.SetMediaItemInfo_Value(first_item, "D_POSITION", min_start)
        r.SetMediaItemInfo_Value(first_item, "D_LENGTH", max_end - min_start)

        -- Delete other items
        for _, item in ipairs(items_to_delete) do
            local track = r.GetMediaItem_Track(item)
            if track then
                r.DeleteTrackMediaItem(track, item)
            end
        end

        -- Re-select the first item
        r.SetMediaItemSelected(first_item, true)
    end

    return true
end

function AssignPreset(glue_first)
    if #presets == 0 or selected_preset_index < 0 or selected_preset_index >= #presets then return end
    local p = presets[selected_preset_index + 1]
    r.Undo_BeginBlock()

    -- If glue_first is true, glue selected items into one before tagging
    if glue_first then
        local count = r.CountSelectedMediaItems(0)
        if count > 1 then
            -- Try to merge empty items first (without rendering to WAV)
            if MergeEmptyItems() then
                log_msg = "Merged Empty Items & Tagged: " .. p.name
            else
                -- Regular items - use standard glue
                r.Main_OnCommand(40362, 0) -- Glue items
                log_msg = "Glued & Tagged: " .. p.name
            end
        end
    end

    local count = r.CountSelectedMediaItems(0)
    local item_color = ImGuiColorToReaper(p.color)
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            r.GetSetMediaItemInfo_String(item, "P_NOTES", "PRESET:" .. p.name, true)
            r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", item_color)
            r.UpdateItemInProject(item)
        end
    end
    r.UpdateArrange()
    r.Undo_EndBlock("Assign Preset: " .. p.name, -1)
end

-- Check if region/marker with specific name already exists at position
function MarkerExistsAtPosition(is_region, name, start_pos, end_pos)
    local num_markers, num_regions = r.CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local _, isrgn, pos, rgnend, rgnname, _ = r.EnumProjectMarkers(i)
        if isrgn == is_region and rgnname == name then
            -- Check if positions match (within tolerance)
            if math.abs(pos - start_pos) < 0.01 then
                if not is_region or math.abs(rgnend - end_pos) < 0.01 then
                    return true
                end
            end
        end
    end
    return false
end

function CreateManualMarker(is_region)
    r.Undo_BeginBlock()

    -- Collect all tagged items in project grouped by preset name
    local locations = {}  -- {name = {min_start, max_end}}

    -- If a preset is selected, only process items with that preset name
    local filter_name = nil
    if selected_preset_index >= 0 and selected_preset_index < #presets then
        filter_name = presets[selected_preset_index + 1].name
    end

    -- Scan all items in project for tagged items
    local total_items = r.CountMediaItems(0)
    for i = 0, total_items - 1 do
        local item = r.GetMediaItem(0, i)
        if item then
            local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            if note:match("^PRESET:") then
                local p_name = note:match("^PRESET:(.*)")
                -- Apply filter if preset is selected
                if not filter_name or p_name == filter_name then
                    local s = r.GetMediaItemInfo_Value(item, "D_POSITION")
                    local e = s + r.GetMediaItemInfo_Value(item, "D_LENGTH")

                    if not locations[p_name] then
                        locations[p_name] = {min_start = s, max_end = e}
                    else
                        if s < locations[p_name].min_start then locations[p_name].min_start = s end
                        if e > locations[p_name].max_end then locations[p_name].max_end = e end
                    end
                end
            end
        end
    end

    -- Create markers/regions for each location (skip if already exists)
    local created = 0
    local skipped = 0
    for name, loc in pairs(locations) do
        if MarkerExistsAtPosition(is_region, name, loc.min_start, loc.max_end) then
            skipped = skipped + 1
        else
            r.AddProjectMarker(0, is_region, loc.min_start, loc.max_end, name, -1)
            created = created + 1
        end
    end

    local type_name = is_region and "regions" or "markers"
    if created > 0 or skipped > 0 then
        log_msg = string.format("Created %d %s, skipped %d (already exist)", created, type_name, skipped)
    else
        log_msg = "No tagged items found"
    end

    r.Undo_EndBlock("Create " .. (is_region and "Regions" or "Markers"), -1)
    r.UpdateArrange()
end

-- =========================================================
-- AUDIO GENERATION (ReaEQ)
-- =========================================================

function AddReaEQToTake(take)
    local names = {"ReaEQ", "VST: ReaEQ", "VST: ReaEQ (Cockos)", "Cockos/ReaEQ"}
    local fx_idx = -1
    for _, name in ipairs(names) do
        fx_idx = r.TakeFX_AddByName(take, name, 1)
        if fx_idx >= 0 then break end
    end
    return fx_idx
end

function Generate()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then log_msg = "Select tagged scenes first (use TAG button)" return end

    -- Prepare tracks based on target mode
    local selected_tracks = {}
    local byname_spot_tracks = {}
    local byname_bed_tracks = {}

    if params.target_mode == 1 then
        -- Selected mode: use selected tracks in order
        local sel_tr_count = r.CountSelectedTracks(0)
        if sel_tr_count == 0 then
            log_msg = "Select destination tracks first (Selected mode)"
            return
        end
        for i = 0, sel_tr_count - 1 do
            table.insert(selected_tracks, r.GetSelectedTrack(0, i))
        end
    elseif params.target_mode == 2 then
        -- ByName mode: find tracks with spot/bed in name
        byname_spot_tracks = FindTracksByType("spot")
        byname_bed_tracks = FindTracksByType("bed")
        if #byname_spot_tracks == 0 and #byname_bed_tracks == 0 then
            log_msg = "No tracks with 'spot' or 'bed' in name found (excluding source folder)"
            return
        end
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Counters for feedback
    local bed_count, spot_count = 0, 0

    if not params.seed_lock then math.randomseed(os.time()) end

    local amb_bus = nil
    if params.target_mode == 0 then
        -- New mode: create track structure
        amb_bus = GetTrackByName(DEST_ROOT_NAME)
        if not amb_bus then
            r.InsertTrackAtIndex(r.CountTracks(0), true)
            amb_bus = r.GetTrack(0, r.CountTracks(0)-1)
            r.GetSetMediaTrackInfo_String(amb_bus, "P_NAME", DEST_ROOT_NAME, true)
            r.SetMediaTrackInfo_Value(amb_bus, "I_FOLDERDEPTH", 1)
        end
    end
    
    local items_data = {}
    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note:match("^PRESET:") then
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            table.insert(items_data, {item=item, pos=pos, end_pos=pos+len, p_name=note:match("^PRESET:(.*)")})
        end
    end
    table.sort(items_data, function(a,b) return a.pos < b.pos end)

    local blocks = {}
    if #items_data > 0 then
        local current_block = {p_name=items_data[1].p_name, start_pos=items_data[1].pos, end_pos=items_data[1].end_pos, original_items={items_data[1].item}}
        for i = 2, #items_data do
            local next_item = items_data[i]
            if next_item.p_name == current_block.p_name and next_item.pos <= (current_block.end_pos + BLOCK_MERGE_TOLERANCE) then
                if next_item.end_pos > current_block.end_pos then current_block.end_pos = next_item.end_pos end
                table.insert(current_block.original_items, next_item.item)
            else
                table.insert(blocks, current_block)
                current_block = {p_name=next_item.p_name, start_pos=next_item.pos, end_pos=next_item.end_pos, original_items={next_item.item}}
            end
        end
        table.insert(blocks, current_block)
    end

    local location_counts = {}  -- track how many times each location appears

    for _, block in ipairs(blocks) do
        if params.seed_lock then
            local name_sum = 0
            for i=1, #block.p_name do name_sum = name_sum + string.byte(block.p_name, i) end
            math.randomseed(math.floor(block.start_pos) + name_sum)
        end

        local p_data = nil
        for _, p in ipairs(presets) do if p.name == block.p_name then p_data = p break end end
        if p_data then
            if params.create_regions then r.AddProjectMarker(0, true, block.start_pos, block.end_pos, block.p_name, -1) end

            -- Get location folder ONCE before layer loop (for New mode)
            local loc_folder = nil
            if params.target_mode == 0 then
                loc_folder = GetOrCreateLocationFolder(amb_bus, block.p_name)
            end

            -- For ByName mode: count layers and validate
            if params.target_mode == 2 then
                local preset_spots, preset_beds = 0, 0
                for _, l in ipairs(p_data.layers) do
                    if l.type == "SPOT" then preset_spots = preset_spots + 1
                    elseif l.type == "BED" then preset_beds = preset_beds + 1 end
                end
                if preset_spots > #byname_spot_tracks or preset_beds > #byname_bed_tracks then
                    log_msg = string.format("Preset '%s' has %d spots and %d beds, but you have %d spot tracks and %d bed tracks",
                        block.p_name, preset_spots, preset_beds, #byname_spot_tracks, #byname_bed_tracks)
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("Generate Ambients (failed)", -1)
                    return
                end
            end

            local block_dur = block.end_pos - block.start_pos
            local layer_track_idx = 0  -- counter for selected tracks mode
            local byname_spot_idx = 0  -- counter for ByName spot tracks
            local byname_bed_idx = 0   -- counter for ByName bed tracks
            local generated_items = {}  -- track all generated items for this block

            for _, layer in ipairs(p_data.layers) do
                local dest_tr = nil

                if params.target_mode == 1 then
                    -- Selected mode: use selected tracks in order
                    layer_track_idx = layer_track_idx + 1
                    if layer_track_idx <= #selected_tracks then
                        dest_tr = selected_tracks[layer_track_idx]
                    else
                        dest_tr = selected_tracks[#selected_tracks]
                    end
                elseif params.target_mode == 2 then
                    -- ByName mode: match by layer type
                    if layer.type == "SPOT" then
                        byname_spot_idx = byname_spot_idx + 1
                        dest_tr = byname_spot_tracks[byname_spot_idx] or byname_spot_tracks[#byname_spot_tracks]
                    elseif layer.type == "BED" then
                        byname_bed_idx = byname_bed_idx + 1
                        dest_tr = byname_bed_tracks[byname_bed_idx] or byname_bed_tracks[#byname_bed_tracks]
                    end
                else
                    -- New mode: find or create track in location folder
                    local loc_idx = r.GetMediaTrackInfo_Value(loc_folder, "IP_TRACKNUMBER")
                    local loc_depth = r.GetTrackDepth(loc_folder)
                    local k = loc_idx
                    while k < r.CountTracks(0) do
                        local t = r.GetTrack(0, k)
                        if r.GetTrackDepth(t) <= loc_depth then break end
                        local _, t_name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
                        if t_name == layer.name then dest_tr = t break end
                        k = k + 1
                    end
                    if not dest_tr then
                        r.InsertTrackAtIndex(loc_idx, true)
                        dest_tr = r.GetTrack(0, loc_idx)
                        r.GetSetMediaTrackInfo_String(dest_tr, "P_NAME", layer.name, true)
                        local col = r.GetMediaTrackInfo_Value(layer.track, "I_CUSTOMCOLOR")
                        r.SetMediaTrackInfo_Value(dest_tr, "I_CUSTOMCOLOR", col)
                    end
                end
                
                local src_cnt = r.CountTrackMediaItems(layer.track)
                if src_cnt > 0 then
                    if layer.type == "BED" then
                        local src_item = r.GetTrackMediaItem(layer.track, 0)
                        local _, chunk = r.GetItemStateChunk(src_item, "", false)

                        -- Get source info
                        local src_take = r.GetActiveTake(src_item)
                        local src_source = src_take and r.GetMediaItemTake_Source(src_take)
                        local src_len = src_source and r.GetMediaSourceLength(src_source) or 60
                        local trim = params.bed_trim or 0.5
                        local safe_len = math.max(src_len - (trim * 2), 1)  -- usable length after trimming edges

                        -- Calculate target parameters
                        -- Overlap slider = total crossfade zone between locations
                        -- Each side extends by half, so adjacent locations overlap by exactly the slider value
                        local half_overlap = params.bed_overlap / 2
                        -- Clamp start position to 0 (can't place items before timeline start)
                        local f_st = math.max(0, block.start_pos - half_overlap)
                        -- scene_end always extends into next location by half_overlap
                        local scene_end = block.end_pos + half_overlap
                        local total_len = scene_end - f_st
                        -- Fade = FULL overlap for proper X-crossfade (both fades span entire overlap zone)
                        local actual_fade = params.bed_overlap > 0 and params.bed_overlap or params.bed_fade

                        -- Smart fades for edge locations (no crossfade partner = shorter fade)
                        local is_at_start = (f_st < 0.01)  -- location at timeline start
                        local first_fade = is_at_start and half_overlap or actual_fade

                        -- Helper function to create a BED slice
                        -- Returns actual length created (may be less than requested if capped by safe_len)
                        local function CreateBedSlice(pos, len, fade_in, fade_out)
                            -- CRITICAL: Cap length to safe_len to avoid extending beyond audio
                            local actual_len = math.min(len, safe_len)
                            -- CRITICAL: Don't extend past scene_end (strict location boundary)
                            actual_len = math.min(actual_len, scene_end - pos)
                            if actual_len <= 0 then return nil, 0 end

                            -- Ensure fades fit within the actual length
                            local max_fade = actual_len * 0.45  -- Leave at least 10% unfaded in middle
                            fade_in = math.min(fade_in, max_fade)
                            fade_out = math.min(fade_out, max_fade)

                            local new_item = r.AddMediaItemToTrack(dest_tr)
                            r.SetItemStateChunk(new_item, chunk, false)
                            r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
                            r.SetMediaItemInfo_Value(new_item, "D_POSITION", pos)
                            r.SetMediaItemInfo_Value(new_item, "D_LENGTH", actual_len)
                            r.SetMediaItemInfo_Value(new_item, "D_VOL", 10^(params.bed_vol_db/20))
                            r.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fade_in)
                            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fade_out)

                            -- Random start offset within safe zone
                            local take = r.GetActiveTake(new_item)
                            if take then
                                local available = src_len - trim - actual_len
                                if available > 0 then
                                    local rand_offset = trim + (math.random() * available)
                                    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", rand_offset)
                                else
                                    -- Not enough room for random offset, use trim
                                    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", trim)
                                end
                            end

                            if params.color_items and p_data.color then
                                r.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", ImGuiColorToReaper(p_data.color))
                            end
                            table.insert(generated_items, new_item)
                            return new_item, actual_len  -- Return actual length for caller to know if it was capped
                        end

                        local min_slice = params.bed_min_slice or 8

                        -- Two types of fades:
                        -- location_fade = full overlap for X-crossfade between locations (HEAD/TAIL)
                        -- grain_overlap = crossfade between random slices (user-controllable)
                        local location_fade = actual_fade
                        local grain_overlap = params.bed_grain_overlap or 0.5  -- overlap between grains

                        -- Edge zone covers the location crossfade area
                        local edge_zone = math.max(location_fade, min_slice)
                        local body_start = f_st + edge_zone
                        local body_end = scene_end - edge_zone
                        local body_len = body_end - body_start

                        if params.bed_randomize <= 0.01 or total_len <= min_slice * 2 or body_len <= min_slice then
                            -- === SIMPLE MODE: covers entire scene ===
                            if total_len <= safe_len then
                                -- Source is long enough - single item (use first_fade if at timeline start)
                                CreateBedSlice(f_st, total_len, first_fade, location_fade)
                                bed_count = bed_count + 1
                            else
                                -- Source too short - need multiple overlapping items
                                local simple_overlap = math.min(location_fade, safe_len * 0.3)
                                local simple_pos = f_st
                                local simple_count = 0
                                local max_simple = 50  -- Safety limit

                                while simple_pos < scene_end and simple_count < max_simple do
                                    local remaining = scene_end - simple_pos
                                    -- CRITICAL: Don't extend past scene_end (strict boundary)
                                    local this_len = math.min(safe_len, remaining)

                                    -- Determine fades for this slice (use first_fade for start if at timeline beginning)
                                    local this_fade_in = (simple_count == 0) and first_fade or simple_overlap
                                    local this_fade_out = (simple_pos + this_len >= scene_end) and location_fade or simple_overlap

                                    CreateBedSlice(simple_pos, this_len, this_fade_in, this_fade_out)
                                    simple_count = simple_count + 1

                                    -- Advance (with overlap for X-crossfade)
                                    local advance = this_len - simple_overlap
                                    if advance < 0.5 then advance = this_len * 0.5 end
                                    simple_pos = simple_pos + advance

                                    -- Exit if we've covered the scene
                                    if simple_pos + simple_overlap >= scene_end then break end
                                end
                                bed_count = bed_count + simple_count
                            end
                        else
                            -- === GRANULAR MODE: overlapping grains with random sizes ===
                            -- Based on granular synthesis: continuous coverage with varying grain sizes

                            local slice_count = 0
                            local max_slices = 500  -- Safety limit to prevent infinite loops

                            -- HEAD: covers fade-in zone + extends into body for overlap
                            -- HEAD extends by half grain_overlap (symmetric overlap like location crossfade)
                            local half_grain = grain_overlap / 2
                            local head_len = edge_zone + half_grain
                            head_len = math.min(head_len, safe_len)
                            -- HEAD fades: first_fade in (shorter if at timeline start), grain_overlap out (for MIDDLE X-crossfade)
                            CreateBedSlice(f_st, head_len, first_fade, grain_overlap)
                            slice_count = slice_count + 1

                            -- Track where HEAD ends (for continuous coverage)
                            local head_end = f_st + head_len
                            local coverage_pos = head_end - grain_overlap  -- start next slice with overlap

                            -- MIDDLE: granular slices with random size variation (±30%)
                            local base_slice = min_slice + (1 - params.bed_randomize) * min_slice
                            local tail_zone_start = scene_end - edge_zone - grain_overlap

                            -- Minimum advance to prevent infinite loops (at least 0.5s or half of grain_overlap)
                            local min_advance = math.max(0.5, grain_overlap * 0.5, min_slice * 0.25)

                            while coverage_pos < tail_zone_start and slice_count < max_slices do
                                -- Random slice length: base ± 30%
                                local size_variation = 0.7 + (math.random() * 0.6)  -- 0.7 to 1.3
                                local this_slice_len = math.min(base_slice * size_variation, safe_len)
                                this_slice_len = math.max(this_slice_len, min_slice * 0.5)  -- min half of min_slice

                                -- Ensure we don't go past tail zone
                                if coverage_pos + this_slice_len > tail_zone_start + grain_overlap then
                                    this_slice_len = tail_zone_start + grain_overlap - coverage_pos
                                end

                                if this_slice_len > grain_overlap * 2 then
                                    CreateBedSlice(coverage_pos, this_slice_len, grain_overlap, grain_overlap)
                                    slice_count = slice_count + 1

                                    -- Next position: advance by slice minus overlap (with minimum to prevent infinite loop)
                                    local advance = math.max(this_slice_len - grain_overlap, min_advance)
                                    coverage_pos = coverage_pos + advance
                                else
                                    break
                                end
                            end

                            -- TAIL: covers fade-out zone, overlaps with last slice by exactly grain_overlap
                            -- coverage_pos is grain_overlap before last slice ends, so TAIL MUST start at coverage_pos for X-crossfade
                            -- (don't use max with edge_zone - that breaks the overlap!)
                            local tail_start = coverage_pos
                            local tail_len = scene_end - tail_start
                            -- Ensure TAIL is long enough for both grain fade-in and location fade-out
                            if tail_len > math.max(grain_overlap, location_fade) then
                                CreateBedSlice(tail_start, tail_len, grain_overlap, location_fade)
                                slice_count = slice_count + 1
                            elseif tail_len > 0.1 then
                                -- Short TAIL: use proportional fades
                                local short_fade = tail_len * 0.4
                                CreateBedSlice(tail_start, tail_len, short_fade, short_fade)
                                slice_count = slice_count + 1
                            end

                            bed_count = bed_count + slice_count
                        end
                    elseif layer.type == "SPOT" then
                        if params.spot_intensity > 0.01 then 
                            local effective_density = params.spot_density_sec / params.spot_intensity
                            local raw_count = math.floor(block_dur / effective_density)
                            if math.random() < ((block_dur / effective_density) - raw_count) then raw_count = raw_count + 1 end
                            if raw_count < 1 and block_dur > 5 then raw_count = 1 end
                            
                            local candidates = {}
                            for n = 1, raw_count do
                                local rel = math.random()
                                if params.spot_edge_bias and math.random() < 0.3 then
                                    if math.random() < 0.5 then rel = math.random() * 0.15 else rel = 0.85 + (math.random() * 0.15) end
                                end
                                table.insert(candidates, block.start_pos + (rel * block_dur))
                            end
                            table.sort(candidates)
                            
                            local last_end_pos = -9999
                            for _, ideal_pos in ipairs(candidates) do
                                local rnd_idx = math.random(1, src_cnt) - 1
                                local src_item = r.GetTrackMediaItem(layer.track, rnd_idx)
                                local src_len = r.GetMediaItemInfo_Value(src_item, "D_LENGTH")
                                
                                local valid_start = last_end_pos + params.spot_min_gap
                                local actual_pos = ideal_pos
                                if actual_pos < valid_start then actual_pos = valid_start end
                                
                                if (actual_pos + src_len) <= (block.end_pos + params.bed_overlap / 2) then
                                    local _, chunk = r.GetItemStateChunk(src_item, "", false)
                                    local new_item = r.AddMediaItemToTrack(dest_tr)
                                    r.SetItemStateChunk(new_item, chunk, false)
                                    r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
                                    r.SetMediaItemInfo_Value(new_item, "D_POSITION", actual_pos)
                                    
                                    if params.spot_vol_var > 0 then
                                        local c_vol = r.GetMediaItemInfo_Value(new_item, "D_VOL")
                                        local ch = (math.random() * 2 - 1) * params.spot_vol_var
                                        r.SetMediaItemInfo_Value(new_item, "D_VOL", c_vol * (10 ^ (ch / 20)))
                                    end
                                    if params.spot_pitch_var > 0 then
                                        local pch = (math.random() * 2 - 1) * params.spot_pitch_var
                                        r.SetMediaItemTakeInfo_Value(r.GetActiveTake(new_item), "D_PITCH", pch)
                                    end
                                    if params.spot_pan_var > 0 then
                                        local pan = (math.random() * 2 - 1) * params.spot_pan_var
                                        r.SetMediaItemTakeInfo_Value(r.GetActiveTake(new_item), "D_PAN", pan)
                                    end
                                    r.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", params.spot_fade)
                                    r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", params.spot_fade)
                                    
                                    if params.spot_dist_sim > 0.0 then
                                        local dist_rnd = math.random() 
                                        local impact = dist_rnd * params.spot_dist_sim 
                                        if impact > 0.05 then
                                            local att_db = -12.0 * impact
                                            local v = r.GetMediaItemInfo_Value(new_item, "D_VOL")
                                            r.SetMediaItemInfo_Value(new_item, "D_VOL", v * (10 ^ (att_db / 20)))
                                            
                                            local take = r.GetActiveTake(new_item)
                                            local fx_idx = AddReaEQToTake(take)
                                            if fx_idx >= 0 then
                                                local jitter = (math.random() * 0.1) - 0.05
                                                local freq_norm = 1.0 - (impact * 0.7) + jitter
                                                if freq_norm > 1.0 then freq_norm = 1.0 end
                                                r.TakeFX_SetParamNormalized(take, fx_idx, 12, 0.25)
                                                r.TakeFX_SetParamNormalized(take, fx_idx, 10, 0.2 + jitter)
                                                r.TakeFX_SetParamNormalized(take, fx_idx, 9, freq_norm)
                                            end
                                        end
                                    end
                                    if params.color_items and p_data.color then
                                        r.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", ImGuiColorToReaper(p_data.color))
                                    end
                                    table.insert(generated_items, new_item)
                                    last_end_pos = actual_pos + src_len
                                    spot_count = spot_count + 1
                                end
                            end
                        end
                    end
                end
            end

            -- Rename and optionally group items
            if #generated_items > 0 then
                -- Track location occurrence count
                location_counts[block.p_name] = (location_counts[block.p_name] or 0) + 1
                local loc_num = location_counts[block.p_name]

                -- Generate group ID if grouping is enabled
                local group_id = nil
                if params.group_items then
                    group_id = math.floor((r.time_precise() * 10000) + (block.start_pos * 100)) % 100000000
                    if group_id == 0 then group_id = 1 end
                end

                -- Rename original empty items (LocationName_N) and optionally group
                local empty_item_name = block.p_name .. "_" .. loc_num
                for _, orig_item in ipairs(block.original_items) do
                    -- Set or clear group ID
                    r.SetMediaItemInfo_Value(orig_item, "I_GROUPID", group_id or 0)
                    -- Rename empty item: LocationName_N
                    local take = r.GetActiveTake(orig_item)
                    if not take then
                        take = r.AddTakeToMediaItem(orig_item)
                    end
                    if take then
                        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", empty_item_name, true)
                    end
                end
                -- Rename generated items (OriginalName_LocationName) and optionally group
                for _, gen_item in ipairs(generated_items) do
                    -- Set or clear group ID (clear inherited group from source item chunk)
                    r.SetMediaItemInfo_Value(gen_item, "I_GROUPID", group_id or 0)
                    -- Add location name as suffix (OriginalName_LocationName)
                    local take = r.GetActiveTake(gen_item)
                    if take then
                        local _, orig_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                        if orig_name and orig_name ~= "" then
                            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", orig_name .. "_" .. block.p_name, true)
                        else
                            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "item_" .. block.p_name, true)
                        end
                    end
                end
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Generate Ambients v8.2", -1)
    log_msg = string.format("Generated: %d beds, %d spots in %d blocks", bed_count, spot_count, #blocks)
end

-- =========================================================
-- PROPAGATE SELECTED AI (CLEAN MANUAL MODE)
-- =========================================================

function FindAllSelectedAutomationItems()
    local selected_ais = {}
    local tr_cnt = r.CountTracks(0)
    for i=0, tr_cnt-1 do
        local tr = r.GetTrack(0, i)
        local env_cnt = r.CountTrackEnvelopes(tr)
        for j=0, env_cnt-1 do
            local env = r.GetTrackEnvelope(tr, j)
            local ai_cnt = r.CountAutomationItems(env)
            for k=0, ai_cnt-1 do
                if r.GetSetAutomationItemInfo(env, k, "D_UISEL", 0, false) > 0 then
                    local pool_id = r.GetSetAutomationItemInfo(env, k, "D_POOL_ID", 0, false)
                    local pos = r.GetSetAutomationItemInfo(env, k, "D_POSITION", 0, false)
                    table.insert(selected_ais, {env=env, pool_id=pool_id, src_pos=pos, ai_idx=k})
                end
            end
        end
    end
    return selected_ais
end

function PropagateSelectedAI()
    if #presets == 0 then return end
    local p_name = presets[selected_preset_index + 1].name
    
    r.Undo_BeginBlock()
    
    -- 1. FIND SELECTED AI (MANUAL ONLY)
    local source_ais = FindAllSelectedAutomationItems()
    
    if #source_ais == 0 then
        log_msg = "No automation items selected. Select AI in envelope first."
        r.Undo_EndBlock("Propagate Fail", -1); return
    end
    
    -- 2. AUTO-RENAME SOURCE ITEMS
    for _, src in ipairs(source_ais) do
        local retval, env_name = r.GetEnvelopeName(src.env, "")
        if retval then
            local clean_name = env_name:match("Send Volume: (.*)")
            if not clean_name then clean_name = env_name end
            local new_pool_name = clean_name .. " " .. p_name
            r.GetSetAutomationItemInfo_String(src.env, src.ai_idx, "P_POOL_NAME", new_pool_name, true)
        end
    end
    
    -- 3. FIND TARGET SCENES
    local ranges = {}
    local count = r.CountMediaItems(0)
    for i = 0, count - 1 do
        local item = r.GetMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note == "PRESET:" .. p_name then
            local s = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local e = s + r.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- Don't copy on top of source
            local is_source = false
            for _, src in ipairs(source_ais) do
                 if math.abs(s - src.src_pos) < SOURCE_MATCH_TOLERANCE then is_source = true end
            end
            
            if not is_source then
                local merged = false
                for _, rng in ipairs(ranges) do
                    if s <= (rng.e + BLOCK_MERGE_TOLERANCE) and e > rng.s then
                        if s < rng.s then rng.s = s end
                        if e > rng.e then rng.e = e end
                        merged = true; break
                    end
                end
                if not merged then table.insert(ranges, {s=s, e=e}) end
            end
        end
    end
    
    -- 4. DUPLICATE POOLED
    local items_created = 0
    for _, rng in ipairs(ranges) do
        local len = rng.e - rng.s
        for _, ai_src in ipairs(source_ais) do
            r.InsertAutomationItem(ai_src.env, ai_src.pool_id, rng.s, len)
            items_created = items_created + 1
        end
    end
    
    r.UpdateArrange(); r.Undo_EndBlock("Propagate Selected AI", -1)
    log_msg = "Propagated " .. items_created .. " named clips."
end

-- =========================================================
-- SELECTION & TOOLS
-- =========================================================

-- Select ALL generated items in project for the preset selected in UI
-- Finds items whose names end with _PresetName
function SelectAllGenerated()
    if #presets == 0 or selected_preset_index < 0 then
        log_msg = "Select a preset first"
        return
    end
    local p_name = presets[selected_preset_index + 1].name
    local suffix = "_" .. p_name

    r.Main_OnCommand(40289, 0)  -- Deselect all
    local total_count = r.CountMediaItems(0)
    local sel_cnt = 0

    for i = 0, total_count - 1 do
        local item = r.GetMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take then
            local _, item_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            -- Check if item name ends with _PresetName
            if item_name ~= "" and item_name:sub(-#suffix) == suffix then
                r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
                sel_cnt = sel_cnt + 1
            end
        end
    end

    r.UpdateArrange()
    log_msg = "Selected " .. sel_cnt .. " generated items for '" .. p_name .. "'"
end

-- Select tagged scene items (empty items with PRESET: note) for preset selected in UI
function SelectTagItems()
    if #presets == 0 or selected_preset_index < 0 then
        log_msg = "Select a preset first"
        return
    end
    local p_name = presets[selected_preset_index + 1].name
    r.Main_OnCommand(40289, 0)  -- Deselect all
    local count = r.CountMediaItems(0)
    local sel_cnt = 0
    for i = 0, count - 1 do
        local item = r.GetMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note == "PRESET:" .. p_name then
            r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
            sel_cnt = sel_cnt + 1
        end
    end
    r.UpdateArrange()
    log_msg = "Selected " .. sel_cnt .. " tagged scenes for '" .. p_name .. "'"
end

-- Select generated items (beds/spots) for the tag-item currently selected on timeline
-- Works by finding items whose names end with _PresetName matching the selected tag item
function SelectGeneratedForSelection()
    -- Find selected tagged item
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        log_msg = "Select a tagged scene item first"
        return
    end

    -- Find preset name from selected items
    local preset_name = nil
    local tag_item_pos = nil
    local tag_item_end = nil

    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note:match("^PRESET:") then
            preset_name = note:match("^PRESET:(.*)")
            tag_item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            tag_item_end = tag_item_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
            break
        end
    end

    if not preset_name then
        log_msg = "No tagged scene item selected"
        return
    end

    -- Find all generated items with _PresetName suffix that overlap with the tag item
    r.Main_OnCommand(40289, 0)  -- Deselect all
    local total_count = r.CountMediaItems(0)
    local sel_cnt = 0
    local suffix = "_" .. preset_name

    for i = 0, total_count - 1 do
        local item = r.GetMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take then
            local _, item_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            -- Check if item name ends with _PresetName
            if item_name:sub(-#suffix) == suffix then
                -- Check if item overlaps with tag item time range
                local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
                -- Overlap check with some tolerance for the location overlap zones
                local tolerance = params.bed_overlap or 2
                if item_pos < tag_item_end + tolerance and item_end > tag_item_pos - tolerance then
                    r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
                    sel_cnt = sel_cnt + 1
                end
            end
        end
    end

    r.UpdateArrange()
    log_msg = "Selected " .. sel_cnt .. " generated items for '" .. preset_name .. "'"
end

function SwapSourceSWS(mode)
    if not HAS_SWS then
        log_msg = "SWS Extension required for swap functions"
        return
    end
    local cmd = (mode==1) and "_XENAKIOS_SISFTNEXTIF" or ((mode==-1) and "_XENAKIOS_SISFTPREVIF" or "_XENAKIOS_SISFTRANDIF")
    r.Undo_BeginBlock(); r.Main_OnCommand(r.NamedCommandLookup(cmd), 0); r.Undo_EndBlock("Swap", -1); r.UpdateArrange()
end
function ColorRandom()
    local cnt = r.CountSelectedMediaItems(0); if cnt==0 then return end
    r.Undo_BeginBlock(); local c=GetRandomReaperColor(); for i=0,cnt-1 do r.SetMediaItemInfo_Value(r.GetSelectedMediaItem(0,i),"I_CUSTOMCOLOR",c) end
    r.Undo_EndBlock("Rnd Col",-1); r.UpdateArrange()
end

-- Apply preset color to all generated and tag items for selected preset
function ApplyPresetColor()
    if #presets == 0 or selected_preset_index < 0 then
        log_msg = "Select a preset first"
        return
    end
    local p = presets[selected_preset_index + 1]
    local suffix = "_" .. p.name
    local item_color = ImGuiColorToReaper(p.color)
    
    r.Undo_BeginBlock()
    local count = 0
    local total_items = r.CountMediaItems(0)
    
    for i = 0, total_items - 1 do
        local item = r.GetMediaItem(0, i)
        local apply_color = false
        
        -- Check if it's a tag item
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note == "PRESET:" .. p.name then
            apply_color = true
        else
            -- Check if it's a generated item (name ends with _PresetName)
            local take = r.GetActiveTake(item)
            if take then
                local _, item_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                if item_name:sub(-#suffix) == suffix then
                    apply_color = true
                end
            end
        end
        
        if apply_color then
            r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", item_color)
            count = count + 1
        end
    end
    
    r.Undo_EndBlock("Apply Preset Color", -1)
    r.UpdateArrange()
    log_msg = "Applied color to " .. count .. " items for '" .. p.name .. "'"
end

-- Group tag items with their generated items for selected preset
-- If all_presets is true, groups all locations in project (ignores UI selection)
function GroupByLocation(all_presets)
    local filter_name = nil
    if not all_presets then
        if #presets == 0 or selected_preset_index < 0 then
            log_msg = "Select a preset first"
            return
        end
        filter_name = presets[selected_preset_index + 1].name
    end
    
    r.Undo_BeginBlock()
    
    -- Find all tag items (optionally filtered by preset)
    local tag_items = {}
    local total_items = r.CountMediaItems(0)
    for i = 0, total_items - 1 do
        local item = r.GetMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        local p_name = note:match("^PRESET:(.*)")
        if p_name and (not filter_name or p_name == filter_name) then
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            table.insert(tag_items, {item = item, pos = pos, end_pos = pos + len, p_name = p_name})
        end
    end
    
    if #tag_items == 0 then
        if filter_name then
            log_msg = "No tagged scenes found for '" .. filter_name .. "'"
        else
            log_msg = "No tagged scenes found"
        end
        r.Undo_EndBlock("Group by Location (no tags)", -1)
        return
    end
    
    local groups_created = 0
    local tolerance = params.bed_overlap or 2
    
    -- For each tag item, create a group with overlapping generated items
    for _, tag_data in ipairs(tag_items) do
        -- Generate unique group ID
        local group_id = math.floor((r.time_precise() * 10000) + (tag_data.pos * 100)) % 100000000
        if group_id == 0 then group_id = 1 end
        
        -- Apply group to tag item
        r.SetMediaItemInfo_Value(tag_data.item, "I_GROUPID", group_id)
        local grouped_count = 1
        
        -- Find and group all generated items that overlap with this tag
        local suffix = "_" .. tag_data.p_name
        for i = 0, total_items - 1 do
            local item = r.GetMediaItem(0, i)
            if item ~= tag_data.item then
                local take = r.GetActiveTake(item)
                if take then
                    local _, item_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                    -- Check if it's a generated item for this preset
                    if item_name:sub(-#suffix) == suffix then
                        -- Check if it overlaps with tag item
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_end = item_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
                        
                        if item_pos < tag_data.end_pos + tolerance and item_end > tag_data.pos - tolerance then
                            r.SetMediaItemInfo_Value(item, "I_GROUPID", group_id)
                            grouped_count = grouped_count + 1
                        end
                    end
                end
            end
        end
        
        if grouped_count > 1 then
            groups_created = groups_created + 1
        end
    end
    
    r.Undo_EndBlock("Group by Location", -1)
    r.UpdateArrange()
    if filter_name then
        log_msg = "Created " .. groups_created .. " groups for '" .. filter_name .. "'"
    else
        log_msg = "Created " .. groups_created .. " groups across all presets"
    end
end

-- UI
function PushTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C_BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C_FRAME)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), C_BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), C_BTN_HOVR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_BTN_HOVR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_BTN_HOVR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C_TEXT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C_BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C_BTN_HOVR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), C_BTN_HOVR)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), C_GEN_TEAL)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), C_GEN_TEAL)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), C_GEN_HOVR)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 6)
end
function PopTheme() r.ImGui_PopStyleColor(ctx, 14); r.ImGui_PopStyleVar(ctx, 3) end

function Loop()
    -- Set default width to 500
    r.ImGui_SetNextWindowSize(ctx, 500, 600, r.ImGui_Cond_FirstUseEver())
    
    -- Set window opacity to 100%
    r.ImGui_SetNextWindowBgAlpha(ctx, 1.0)

    -- Push title bar colors BEFORE ImGui_Begin
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C_TITLE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C_TITLE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), C_TITLE)

    local visible, open = r.ImGui_Begin(ctx, 'Ambient Generator', true)
    if visible then
        PushTheme()
        local w = r.ImGui_GetWindowWidth(ctx) - 16
        
        r.ImGui_TextDisabled(ctx, "SETUP")
        r.ImGui_Text(ctx, "Source Track:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, w * 0.4)
        local changed_src, new_src = r.ImGui_InputText(ctx, "##src_track", SOURCE_ROOT_NAME)
        if changed_src then SOURCE_ROOT_NAME = new_src; SaveParams() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Track name containing location presets")
        end
        r.ImGui_SameLine(ctx, w - 30)
        local tips_changed, tips = r.ImGui_Checkbox(ctx, "?", show_tooltips)
        if tips_changed then show_tooltips = tips; SaveParams() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Show/hide tooltips")
        end
        if r.ImGui_Button(ctx, "Scan Presets", -1) then ScanPresets(); LoadPresetColors() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Scan tracks for location presets")
        end
        r.ImGui_Text(ctx, log_msg)
        r.ImGui_Separator(ctx)
        
        if r.ImGui_BeginListBox(ctx, "##list", -1, 120) then
            for i, p in ipairs(presets) do
                local is_sel = (selected_preset_index == i - 1)
                r.ImGui_PushID(ctx, i)

                -- Color button
                local col_rgb = (p.color >> 8) & 0xFFFFFF  -- Convert RGBA to RGB
                local flags = r.ImGui_ColorEditFlags_NoAlpha() | r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel()
                local changed, new_col = r.ImGui_ColorEdit3(ctx, "##col", col_rgb, flags)
                if changed then
                    p.color = (new_col << 8) | 0xFF  -- Convert RGB back to RGBA
                    SavePresetColors()  -- Save color changes
                end
                if show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Click to change location color")
                end

                r.ImGui_SameLine(ctx)

                -- Selectable (use remaining width minus delete button) - click again to deselect
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                if is_sel then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C_GEN_TEAL); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C_GEN_HOVR) end
                if r.ImGui_Selectable(ctx, p.name .. " (" .. #p.layers .. ")", is_sel, 0, avail_w - 25, 0) then
                    if is_sel then
                        selected_preset_index = -1  -- Deselect if already selected
                    else
                        selected_preset_index = i - 1  -- Select
                    end
                    SaveParams()
                end
                if is_sel then r.ImGui_PopStyleColor(ctx, 2) end

                -- Delete button
                r.ImGui_SameLine(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x55353588)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_TAG_RED)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_TAG_HOVR)
                if r.ImGui_SmallButton(ctx, "X") then
                    delete_confirm_idx = i - 1
                end
                r.ImGui_PopStyleColor(ctx, 3)
                if show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Remove preset from list")
                end

                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndListBox(ctx)

            -- Handle delete after loop to avoid modifying list during iteration
            if delete_confirm_idx >= 0 then
                table.remove(presets, delete_confirm_idx + 1)
                if selected_preset_index >= #presets then
                    selected_preset_index = math.max(0, #presets - 1)
                end
                log_msg = "Preset removed from list"
                delete_confirm_idx = -1
                SaveParams()
            end
        end
        
        r.ImGui_TextDisabled(ctx, "ACTIONS")
        -- TAG button (just tag, no merge)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_TAG_RED); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_TAG_HOVR); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_TAG_HOVR)
        if r.ImGui_Button(ctx, "TAG", w * 0.24) then
            AssignPreset(false)
        end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Tag selected items with preset name")
        end
        r.ImGui_PopStyleColor(ctx, 3); r.ImGui_SameLine(ctx)
        -- MERGE+TAG button (merge items then tag)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_TAG_RED); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_TAG_HOVR); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_TAG_HOVR)
        if r.ImGui_Button(ctx, "+TAG", w * 0.24) then
            AssignPreset(true)
        end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Merge items into one, then tag\n(Empty items stay empty, audio items are glued)")
        end
        r.ImGui_PopStyleColor(ctx, 3); r.ImGui_SameLine(ctx)
        -- GENERATE button
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_GEN_TEAL); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_GEN_HOVR); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_GEN_HOVR)
        if r.ImGui_Button(ctx, "GENERATE", -1) then Generate() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Generate ambient audio for tagged scenes")
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        local rv, params_changed = false, false
        if r.ImGui_Button(ctx, "Region", w*0.18) then CreateManualMarker(true) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Create regions for locations\n• Selected preset: only that location\n• No selection: ALL locations\n• Skips if already exists")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Marker", w*0.18) then CreateManualMarker(false) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Create markers for locations\n• Selected preset: only that location\n• No selection: ALL locations\n• Skips if already exists")
        end
        r.ImGui_SameLine(ctx)
        rv, params.create_regions = r.ImGui_Checkbox(ctx, "Auto Rgn", params.create_regions); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Automatically create regions during generation")
        end
        r.ImGui_SameLine(ctx)
        rv, params.color_items = r.ImGui_Checkbox(ctx, "Color", params.color_items); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Color generated items with preset color")
        end
        r.ImGui_SameLine(ctx)
        rv, params.group_items = r.ImGui_Checkbox(ctx, "Group", params.group_items); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Group generated items by location\n(allows moving entire location as a block)")
        end
        -- Target at right edge with padding
        r.ImGui_SameLine(ctx)
        local target_btn_w = 65
        local target_total_w = 50 + target_btn_w  -- "Target:" label + button + spacing
        local avail = r.ImGui_GetContentRegionAvail(ctx)
        if avail > target_total_w then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + avail - target_total_w)
        end
        r.ImGui_TextDisabled(ctx, "Target:")
        r.ImGui_SameLine(ctx)
        local target_labels = {"New", "Selected", "ByName"}
        local target_label = target_labels[params.target_mode + 1] or "New"
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_BTN)
        if r.ImGui_Button(ctx, target_label, target_btn_w) then
            params.target_mode = (params.target_mode + 1) % 3
            params_changed = true
        end
        r.ImGui_PopStyleColor(ctx, 1)
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            local tooltips = {
                "New: Create new folder structure under " .. DEST_ROOT_NAME,
                "Selected: Insert on selected tracks in order",
                "ByName: Insert on tracks with 'spot'/'bed' in name\n(ignores source folder " .. SOURCE_ROOT_NAME .. ")"
            }
            r.ImGui_SetTooltip(ctx, tooltips[params.target_mode + 1] or tooltips[1])
        end

        -- === AUTOMATION SECTION ===
        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, "AUTOMATION (Propagate Selected AI)")
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_AUTO_ORG)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_AUTO_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_AUTO_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x202020FF)
        if r.ImGui_Button(ctx, "PROPAGATE SELECTED AI", -1) then PropagateSelectedAI() end
        r.ImGui_PopStyleColor(ctx, 4)
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Copy selected automation items to all scenes with the same preset")
        end
        -- ===========================

        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, "SELECTION")

        if r.ImGui_Button(ctx, "Gen by Preset", w*0.32) then SelectAllGenerated() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select ALL generated items for preset selected in UI\n(across entire project)")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Tag Items", w*0.32) then SelectTagItems() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select tagged scene items for preset selected in UI")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Gen by Tag", -1) then SelectGeneratedForSelection() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select generated items for tag-item selected on timeline")
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, "TOOLS")
        local spacing_x = select(1, r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()))
        local swap_group_w = w * 0.49
        local arrow_w = 32
        local reroll_w = swap_group_w - (arrow_w * 2) - (spacing_x * 2)
        if reroll_w < 40 then reroll_w = 40 end

        r.ImGui_BeginGroup(ctx)
        -- Grey out swap buttons if SWS not available
        if not HAS_SWS then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "<", arrow_w) then SwapSourceSWS(-1) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Previous source file (SWS)" or "SWS Extension required")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Re-Roll", reroll_w) then SwapSourceSWS(0) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Random source file (SWS)" or "SWS Extension required")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, ">", arrow_w) then SwapSourceSWS(1) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Next source file (SWS)" or "SWS Extension required")
        end
        if not HAS_SWS then r.ImGui_EndDisabled(ctx) end
        r.ImGui_EndGroup(ctx)

        r.ImGui_SameLine(ctx)

        -- Group Locations (teal) - on same line
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_GEN_TEAL)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_GEN_HOVR)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_GEN_HOVR)
        if r.ImGui_Button(ctx, "Group Locations", -1) then
            local all_presets = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
            GroupByLocation(all_presets)
        end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Group each tag item with its generated items\nClick: selected preset\nShift-click: ALL presets")
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        -- Color tools (orange) - Color Rnd and Color Preset on one line
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_AUTO_ORG)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_AUTO_HOV)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_AUTO_HOV)
        if r.ImGui_Button(ctx, "Color Rnd", w*0.49) then ColorRandom() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Apply random color to selected items/scenes")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Color Preset", -1) then ApplyPresetColor() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Apply preset color to all generated and tag items\n(for preset selected in UI)")
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_Separator(ctx)
        
        r.ImGui_TextDisabled(ctx, "LOCATIONS SETTINGS")
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
        rv, params.bed_overlap = r.ImGui_SliderDouble(ctx, "Overlap##b", params.bed_overlap, 0.0, 10.0, "%.2f s"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "X-crossfade zone between adjacent locations")
        end
        rv, params.bed_fade = r.ImGui_SliderDouble(ctx, "Int. Fade##b", params.bed_fade, 0.0, 5.0, "%.2f s"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Internal fade for slice transitions\n(used when Shuffle > 0)")
        end
        if r.ImGui_IsItemEdited(ctx) then ApplyFadeToSelection("BED", params.bed_fade) end
        rv, params.bed_vol_db = r.ImGui_SliderDouble(ctx, "Vol (dB)##b", params.bed_vol_db, -60.0, 0.0, "%.1f"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Realtime volume for selected items")
        end
        if r.ImGui_IsItemEdited(ctx) then ApplyVolToSelection(params.bed_vol_db) end

        r.ImGui_TextDisabled(ctx, "BEDS SETTINGS")
        rv, params.bed_randomize = r.ImGui_SliderDouble(ctx, "Shuffle##b", params.bed_randomize, 0.0, 1.0, "%.2f"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Granular mode:\n0 = single continuous item\n1 = many random slices\nSlice sizes vary ±30% for natural sound")
        end
        rv, params.bed_min_slice = r.ImGui_SliderDouble(ctx, "Base Slice##b", params.bed_min_slice, 2.0, 30.0, "%.1f s"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Base slice length (actual size varies ±30%)")
        end
        rv, params.bed_grain_overlap = r.ImGui_SliderDouble(ctx, "Grain Overlap##b", params.bed_grain_overlap, 0.1, 3.0, "%.2f s"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Crossfade between random slices\n(prevents clicks at slice boundaries)")
        end
        rv, params.bed_trim = r.ImGui_SliderDouble(ctx, "Edge Trim##b", params.bed_trim, 0.0, 5.0, "%.2f s"); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Trim from source edges\n(avoids physical fades in audio files)")
        end

        r.ImGui_Spacing(ctx)

        r.ImGui_TextDisabled(ctx, "SPOTS SETTINGS")
        rv, params.spot_intensity = r.ImGui_SliderDouble(ctx, "Intensity", params.spot_intensity, 0.0, 5.0, "%.1fx"); if rv then params_changed = true end
        rv, params.spot_min_gap = r.ImGui_SliderDouble(ctx, "Min Gap", params.spot_min_gap, 0.0, 10.0, "%.1f s"); if rv then params_changed = true end
        rv, params.spot_fade = r.ImGui_SliderDouble(ctx, "Fade##s", params.spot_fade, 0.0, 2.0, "%.1f s"); if rv then params_changed = true end
        if r.ImGui_IsItemEdited(ctx) then ApplyFadeToSelection("SPOT", params.spot_fade) end

        r.ImGui_PopStyleVar(ctx)

        rv, params.spot_edge_bias = r.ImGui_Checkbox(ctx, "Edge Bias", params.spot_edge_bias); if rv then params_changed = true end; r.ImGui_SameLine(ctx)
        rv, params.seed_lock = r.ImGui_Checkbox(ctx, "Lock Seed", params.seed_lock); if rv then params_changed = true end

        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 2)
        rv, params.spot_dist_sim = r.ImGui_SliderDouble(ctx, "Distance (Sim)", params.spot_dist_sim, 0.0, 1.0, "%.2f"); if rv then params_changed = true end

        r.ImGui_TextDisabled(ctx, "HUMANIZE")
        rv, params.spot_vol_var = r.ImGui_SliderDouble(ctx, "Vol Var", params.spot_vol_var, 0.0, 12.0, "%.1f dB"); if rv then params_changed = true end
        rv, params.spot_pitch_var = r.ImGui_SliderDouble(ctx, "Pitch Var", params.spot_pitch_var, 0.0, 12.0, "%.1f st"); if rv then params_changed = true end
        rv, params.spot_pan_var = r.ImGui_SliderDouble(ctx, "Pan Var", params.spot_pan_var, 0.0, 1.0, "%.2f"); if rv then params_changed = true end

        r.ImGui_PopStyleVar(ctx)

        -- Save params if any changed this frame
        if params_changed then SaveParams() end

        PopTheme()
        r.ImGui_End(ctx)
    end
    -- Pop title bar colors (pushed before ImGui_Begin)
    r.ImGui_PopStyleColor(ctx, 3)
    if open then r.defer(Loop) end
end

LoadParams()
HAS_SWS = CheckSWS()
if not HAS_SWS then log_msg = "Ready v8.2 (SWS not found - swap disabled)" end
ScanPresets()
LoadPresetColors()
r.defer(Loop)
