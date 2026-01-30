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
    bed_overlap = 2.0, bed_fade = 2.0, bed_vol_db = -6.0,
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
    sel_scope = 1, 
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

function AssignPreset(glue_first)
    if #presets == 0 or selected_preset_index < 0 or selected_preset_index >= #presets then return end
    local p = presets[selected_preset_index + 1]
    r.Undo_BeginBlock()

    -- If glue_first is true, glue selected items into one before tagging
    if glue_first then
        local count = r.CountSelectedMediaItems(0)
        if count > 1 then
            r.Main_OnCommand(40362, 0) -- Glue items
            log_msg = "Glued & Tagged: " .. p.name
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
    r.Undo_EndBlock("Assign Preset: " .. p.name, -1)
end

function CreateManualMarker(is_region)
    local cnt = r.CountSelectedMediaItems(0)
    if cnt == 0 then return end
    local min_start, max_end = math.huge, -math.huge
    for i=0, cnt-1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            local s = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local e = s + r.GetMediaItemInfo_Value(item, "D_LENGTH")
            if s < min_start then min_start = s end
            if e > max_end then max_end = e end
        end
    end
    local name = "Scene"
    local item0 = r.GetSelectedMediaItem(0, 0)
    if item0 then
        local _, note = r.GetSetMediaItemInfo_String(item0, "P_NOTES", "", false)
        if note:match("^PRESET:") then name = note:match("^PRESET:(.*)") end
    end
    r.Undo_BeginBlock()
    r.AddProjectMarker(0, is_region, min_start, max_end, name, -1)
    r.Undo_EndBlock("Create Marker/Region", -1)
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
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Counters for feedback
    local bed_count, spot_count = 0, 0

    if not params.seed_lock then math.randomseed(os.time()) end
    
    local amb_bus = GetTrackByName(DEST_ROOT_NAME)
    if not amb_bus then
        r.InsertTrackAtIndex(r.CountTracks(0), true)
        amb_bus = r.GetTrack(0, r.CountTracks(0)-1)
        r.GetSetMediaTrackInfo_String(amb_bus, "P_NAME", DEST_ROOT_NAME, true)
        r.SetMediaTrackInfo_Value(amb_bus, "I_FOLDERDEPTH", 1) 
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
        local current_block = {p_name=items_data[1].p_name, start_pos=items_data[1].pos, end_pos=items_data[1].end_pos}
        for i = 2, #items_data do
            local next_item = items_data[i]
            if next_item.p_name == current_block.p_name and next_item.pos <= (current_block.end_pos + BLOCK_MERGE_TOLERANCE) then
                if next_item.end_pos > current_block.end_pos then current_block.end_pos = next_item.end_pos end
            else
                table.insert(blocks, current_block)
                current_block = {p_name=next_item.p_name, start_pos=next_item.pos, end_pos=next_item.end_pos}
            end
        end
        table.insert(blocks, current_block)
    end

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
            local loc_folder = GetOrCreateLocationFolder(amb_bus, block.p_name)
            local block_dur = block.end_pos - block.start_pos
            for _, layer in ipairs(p_data.layers) do
                local dest_tr = nil
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
                
                local src_cnt = r.CountTrackMediaItems(layer.track)
                if src_cnt > 0 then
                    if layer.type == "BED" then
                        local src_item = r.GetTrackMediaItem(layer.track, 0)
                        local _, chunk = r.GetItemStateChunk(src_item, "", false)
                        local new_item = r.AddMediaItemToTrack(dest_tr)
                        r.SetItemStateChunk(new_item, chunk, false)
                        local f_st = block.start_pos - params.bed_overlap
                        local f_ln = block_dur + (params.bed_overlap * 2)
                        r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 1)
                        r.SetMediaItemInfo_Value(new_item, "D_POSITION", f_st)
                        r.SetMediaItemInfo_Value(new_item, "D_LENGTH", f_ln)
                        r.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", params.bed_fade)
                        r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", params.bed_fade)
                        r.SetMediaItemInfo_Value(new_item, "D_VOL", 10^(params.bed_vol_db/20))
                        bed_count = bed_count + 1
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
                                
                                if (actual_pos + src_len) <= (block.end_pos + params.bed_overlap) then
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
                                    last_end_pos = actual_pos + src_len
                                    spot_count = spot_count + 1
                                end
                            end
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

function SelectScenes()
    if #presets == 0 then return end
    local p_name = presets[selected_preset_index + 1].name
    r.Main_OnCommand(40289, 0)
    local count = r.CountMediaItems(0)
    local m = 0
    for i = 0, count - 1 do
        local item = r.GetMediaItem(0, i)
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        if note == "PRESET:" .. p_name then
            r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
            m=m+1
        end
    end
    r.UpdateArrange()
    log_msg = "Selected " .. m .. " scenes."
end

function SelectAudioGeneric(filter_type)
    if #presets == 0 then return end
    local p_name = presets[selected_preset_index + 1].name
    local root_name = (params.sel_scope == 0) and SOURCE_ROOT_NAME or DEST_ROOT_NAME
    local root_track = GetTrackByName(root_name)
    if not root_track then log_msg = "Track '"..root_name.."' not found. Scan presets first." return end
    local loc_folder = FindLocationFolderInRoot(root_track, p_name)
    if not loc_folder then log_msg = "Location '"..p_name.."' not in "..root_name..". Generate first." return end
    r.Main_OnCommand(40289, 0)
    local idx = r.GetMediaTrackInfo_Value(loc_folder, "IP_TRACKNUMBER")
    local count = r.CountTracks(0)
    local k = idx
    local sel_cnt = 0
    while k < count do
        local tr = r.GetTrack(0, k)
        local parent = r.GetParentTrack(tr)
        if parent ~= loc_folder then break end
        local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local is_spot = tr_name:match("^SPOT_")
        local is_bed = not is_spot
        local select_me = false
        if filter_type == "ALL" then select_me = true end
        if filter_type == "BED" and is_bed then select_me = true end
        if filter_type == "SPOT" and is_spot then select_me = true end
        if select_me then
            local it_cnt = r.CountTrackMediaItems(tr)
            for m=0, it_cnt-1 do
                r.SetMediaItemInfo_Value(r.GetTrackMediaItem(tr, m), "B_UISEL", 1)
                sel_cnt = sel_cnt + 1
            end
        end
        k = k + 1
    end
    r.UpdateArrange()
    local scope_str = (params.sel_scope == 0) and "SRC" or "BUS"
    log_msg = "Sel " .. filter_type .. " (" .. scope_str .. "): " .. sel_cnt
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
        if r.ImGui_Button(ctx, "Scan Presets", -1) then ScanPresets() end
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
                end
                if show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Click to change location color")
                end

                r.ImGui_SameLine(ctx)

                -- Selectable (use remaining width minus delete button)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                if is_sel then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C_GEN_TEAL); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C_GEN_HOVR) end
                if r.ImGui_Selectable(ctx, p.name .. " (" .. #p.layers .. ")", is_sel, 0, avail_w - 25, 0) then selected_preset_index = i - 1; SaveParams() end
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
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_TAG_RED); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_TAG_HOVR); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_TAG_HOVR)
        if r.ImGui_Button(ctx, "TAG", w * 0.49) then
            local shift_held = r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift() ~= 0
            AssignPreset(shift_held)
        end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Click: Tag selected items with preset name\nShift+Click: Glue items into one, then tag")
        end
        r.ImGui_PopStyleColor(ctx, 3); r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_GEN_TEAL); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_GEN_HOVR); r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_GEN_HOVR)
        if r.ImGui_Button(ctx, "GENERATE", -1) then Generate() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Generate ambient audio for tagged scenes")
        end
        r.ImGui_PopStyleColor(ctx, 3)
        
        if r.ImGui_Button(ctx, "Region", w*0.32) then CreateManualMarker(true) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Create region from selected items")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Marker", w*0.32) then CreateManualMarker(false) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Create marker at selection start")
        end
        r.ImGui_SameLine(ctx)
        local rv, params_changed = false, false
        rv, params.create_regions = r.ImGui_Checkbox(ctx, "Auto Region", params.create_regions); if rv then params_changed = true end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Automatically create regions during generation")
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
        r.ImGui_TextDisabled(ctx, "SELECTION SCOPE")
        if r.ImGui_RadioButton(ctx, "SOURCE (Preset)", params.sel_scope == 0) then params.sel_scope = 0; params_changed = true end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "BUS (Generated)", params.sel_scope == 1) then params.sel_scope = 1; params_changed = true end
        
        if r.ImGui_Button(ctx, "SEL Scenes", w*0.24) then SelectScenes() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select all items tagged with current preset")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "SEL ALL", w*0.24) then SelectAudioGeneric("ALL") end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select all generated audio for current preset")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "SEL BEDS", w*0.24) then SelectAudioGeneric("BED") end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select only BED layers")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "SEL SPOTS", -1) then SelectAudioGeneric("SPOT") end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Select only SPOT layers")
        end
        
        r.ImGui_Separator(ctx)
        
        r.ImGui_TextDisabled(ctx, "BEDS SETTINGS")
        rv, params.bed_overlap = r.ImGui_SliderDouble(ctx, "Overlap##b", params.bed_overlap, 0.0, 10.0, "%.1f s"); if rv then params_changed = true end
        rv, params.bed_fade = r.ImGui_SliderDouble(ctx, "Fade##b", params.bed_fade, 0.0, 5.0, "%.1f s"); if rv then params_changed = true end
        if r.ImGui_IsItemEdited(ctx) then ApplyFadeToSelection("BED", params.bed_fade) end
        rv, params.bed_vol_db = r.ImGui_SliderDouble(ctx, "Vol (dB)##b", params.bed_vol_db, -60.0, 0.0, "%.1f"); if rv then params_changed = true end

        r.ImGui_Spacing(ctx)

        r.ImGui_TextDisabled(ctx, "SPOTS SETTINGS")
        rv, params.spot_intensity = r.ImGui_SliderDouble(ctx, "Intensity", params.spot_intensity, 0.0, 5.0, "%.1fx"); if rv then params_changed = true end
        rv, params.spot_min_gap = r.ImGui_SliderDouble(ctx, "Min Gap", params.spot_min_gap, 0.0, 10.0, "%.1f s"); if rv then params_changed = true end
        rv, params.spot_fade = r.ImGui_SliderDouble(ctx, "Fade##s", params.spot_fade, 0.0, 2.0, "%.1f s"); if rv then params_changed = true end
        if r.ImGui_IsItemEdited(ctx) then ApplyFadeToSelection("SPOT", params.spot_fade) end

        rv, params.spot_edge_bias = r.ImGui_Checkbox(ctx, "Edge Bias", params.spot_edge_bias); if rv then params_changed = true end; r.ImGui_SameLine(ctx)
        rv, params.seed_lock = r.ImGui_Checkbox(ctx, "Lock Seed", params.seed_lock); if rv then params_changed = true end

        rv, params.spot_dist_sim = r.ImGui_SliderDouble(ctx, "Distance (Sim)", params.spot_dist_sim, 0.0, 1.0, "%.2f"); if rv then params_changed = true end

        r.ImGui_TextDisabled(ctx, "HUMANIZE")
        rv, params.spot_vol_var = r.ImGui_SliderDouble(ctx, "Vol Var", params.spot_vol_var, 0.0, 12.0, "%.1f dB"); if rv then params_changed = true end
        rv, params.spot_pitch_var = r.ImGui_SliderDouble(ctx, "Pitch Var", params.spot_pitch_var, 0.0, 12.0, "%.1f st"); if rv then params_changed = true end
        rv, params.spot_pan_var = r.ImGui_SliderDouble(ctx, "Pan Var", params.spot_pan_var, 0.0, 1.0, "%.2f"); if rv then params_changed = true end

        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, "TOOLS")
        -- Grey out swap buttons if SWS not available
        if not HAS_SWS then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "<", 40) then SwapSourceSWS(-1) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Previous source file (SWS)" or "SWS Extension required")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Re-Roll", w*0.4) then SwapSourceSWS(0) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Random source file (SWS)" or "SWS Extension required")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, ">", 40) then SwapSourceSWS(1) end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, HAS_SWS and "Next source file (SWS)" or "SWS Extension required")
        end
        if not HAS_SWS then r.ImGui_EndDisabled(ctx) end
        r.ImGui_SameLine(ctx)

        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C_TAG_RED)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C_TAG_HOVR)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C_TAG_HOVR)
        if r.ImGui_Button(ctx, "Color Rnd", -1) then ColorRandom() end
        if show_tooltips and r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Apply random color to selected items/scenes")
        end
        r.ImGui_PopStyleColor(ctx, 3)

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
r.defer(Loop)
