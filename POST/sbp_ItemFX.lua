-- @description SBP ItemFX
-- @version 0.9 beta
-- @author SBP & AI
-- @about Batch item FX management for film post-production: clone FX chains (manual/linked/unlinked), item-level sends via channel routing, EQ and surround pan presets.
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   initial beta release


local r = reaper
local ctx = r.ImGui_CreateContext('SBP_ItemFX_v1')

-- =========================================================
-- DEPENDENCY CHECK
-- =========================================================
if not r.ImGui_CreateContext then
    r.ShowConsoleMsg("Error: ReaImGui is required for SBP ItemFX.\n")
    return
end

-- =========================================================
-- COLORS (matched to sbp_AmbientGen / ReaSFX style)
-- =========================================================
local C = {
    BG        = 0x252525FF,
    TITLE     = 0x202020FF,
    FRAME     = 0x1A1A1AFF,
    TEXT      = 0xDEDEDEFF,
    TEXT_DIM  = 0x707070FF,
    BTN       = 0x383838FF,
    BTN_HOV   = 0x454545FF,
    TEAL      = 0x226757FF,
    TEAL_HOV  = 0x29D0A9FF,
    ORANGE    = 0xD4753FFF,
    ORANGE_HOV= 0xB56230FF,
    RED       = 0xAA4A47FF,
    RED_HOV   = 0xC25E5BFF,
    BORDER    = 0x2A2A2AFF,
    ACTIVE    = 0x29D0A9FF,
    SEND_ON   = 0x226757CC,
    SEND_OFF  = 0x333333FF,
}

local EXTSTATE_SECTION = "SBP_ItemFX"

-- Linked clone source marking
local LINK_SRC_SUFFIX = " [SRC]"

-- =========================================================
-- DATA STRUCTURES
-- =========================================================

-- Captured source item
local captured_source = {
    item = nil,
    item_guid = "",
    take = nil,
    fx_count = 0,
    fx_names = {},
    fx_params = {},  -- [fx_idx][param_idx] = normalized_value
    track = nil,
    capture_time = 0,
}

-- Link table for linked clones: [target_guid] = {item, take, fx_map, active}
local link_table = {}
local link_engine_active = false
local link_sync_interval = 0.05  -- 50ms (20Hz)
local link_last_sync = 0

-- Send routing (per-item via JSFX)
local NUM_SENDS = 4
local send_config = {
    base_ch = 2,                       -- main output channels (2=stereo, 6=5.1, 8=7.1)
    names = {"", "", "", ""},          -- bus track names (user-editable)
    levels = {-60, -60, -60, -60},     -- per-send dB for JSFX sliders (-60 = off)
    enabled = {false, false, false, false}, -- per-send enable checkbox
}

-- EQ Presets
local EQ_PRESETS = {
    {name = "LC100",              builtin = true, bands = {{type="HP", freq=100, gain=0,    bw=1.80}}},
    {name = "LC150",              builtin = true, bands = {{type="HP", freq=150, gain=0,    bw=1.80}}},
    {name = "LC250",              builtin = true, bands = {{type="HP", freq=250, gain=0,    bw=1.80}}},
    {name = "LC100,HS-3.5",      builtin = true, bands = {{type="HP", freq=100, gain=0,    bw=1.80},
                                                           {type="HS", freq=8000,gain=-3.5, bw=1.0}}},
    {name = "HS+6",              builtin = true, bands = {{type="HS", freq=8000,gain=6,    bw=1.0}}},
    {name = "LC100,HS+6",        builtin = true, bands = {{type="HP", freq=100, gain=0,    bw=1.80},
                                                           {type="HS", freq=8000,gain=6,    bw=1.0}}},
    {name = "LS-4,HS+6",         builtin = true, bands = {{type="LS", freq=200, gain=-4,   bw=1.0},
                                                           {type="HS", freq=8000,gain=6,    bw=1.0}}},
    {name = "Lc100,Ls-4,Hs+6",   builtin = true, bands = {{type="HP", freq=100, gain=0,    bw=1.80},
                                                           {type="LS", freq=200, gain=-4,   bw=1.0},
                                                           {type="HS", freq=8000,gain=6,    bw=1.0}}},
    {name = "LS+4,HS-6",         builtin = true, bands = {{type="LS", freq=200, gain=4,    bw=1.0},
                                                           {type="HS", freq=8000,gain=-6,   bw=1.0}}},
}
local custom_eq_presets = {}

-- Surround Pan: Input channels + Output format
local SUR_OUTPUT_FORMATS = {
    {name = "LCR",     channels = 3},
    {name = "LfCRf",   channels = 3},
    {name = "4.0",     channels = 4},
    {name = "5.0",     channels = 5},
    {name = "5.1",     channels = 6},
    {name = "7.1",     channels = 8},
}
local sur_output_idx = 0        -- selected output format index (0 = none)
local custom_sur_presets = {}

-- Captured SurroundPan state templates: [format_name] = {state_b64, reaper_b64, channels}
local surpan_templates = {}

-- FX Priority (order in chain)
local fx_priority = {"EQ", "SurPan", "Send", "Default"}

-- UI State
local selected_eq_preset = 0
local show_tooltips = true
local log_msg = "Ready"

-- Tag system
local tag_track_name = "#Location"  -- name of track containing tag items
local tag_selected_idx = 0          -- currently selected tag in combo (0-based)

-- Clone to Tag confirmation state
local clone_to_tag_confirm_open = false
local clone_to_tag_sel_track_count = 0

-- Item Parameters capture system
local item_params_captured = {
    volume = 0,
    pan = 0,
    pitch = 0,
    playrate = 1.0,
    length = 0,
    fade_in_len = 0,
    fade_out_len = 0,
    fade_in_shape = 0,
    fade_out_shape = 0,
    pitch_mode = 0,
    item_phase = 0,
}

local item_params_enable = {
    volume = true,
    pan = true,
    pitch = true,
    pitch_mode = true,
    playrate = true,
    fade_in = true,
    fade_out = true,
    length = false,
    item_phase = false,
}

local item_params_current_vol = 0  -- Current volume slider for selected items (real-time)
local item_params_prev_sel_hash = ""  -- Track selection changes for readback

-- Custom preset name input buffer
local new_eq_name = ""
local new_sur_name = ""

-- =========================================================
-- SERIALIZE / UNSERIALIZE (from Scene Controller pattern)
-- =========================================================
local function Serialize(val)
    if type(val) == "table" then
        local tmp = {}
        for k, v in pairs(val) do
            local key = type(k) == "number" and "["..k.."]=" or "[\""..k.."\"]="
            table.insert(tmp, key .. Serialize(v))
        end
        return "{" .. table.concat(tmp, ",") .. "}"
    elseif type(val) == "string" then return string.format("%q", val)
    else return tostring(val) end
end

local function Unserialize(s)
    if not s or s == "" then return nil end
    local f = load("return " .. s)
    if not f then return nil end
    return f()
end

-- =========================================================
-- PERSISTENCE
-- =========================================================
local function SaveState()
    local data = {
        custom_eq = custom_eq_presets,
        custom_sur = custom_sur_presets,
        send_base_ch = send_config.base_ch,
        send_names = send_config.names,
        send_levels = send_config.levels,
        send_enabled = send_config.enabled,
        fx_priority = fx_priority,
        show_tooltips = show_tooltips,
        sur_output_idx = sur_output_idx,
        surpan_tpl = surpan_templates,
        tag_track = tag_track_name,
        item_params_captured = item_params_captured,
        item_params_enable = item_params_enable,
    }
    r.SetExtState(EXTSTATE_SECTION, "Config", Serialize(data), true)

    -- Save link table separately (item GUIDs only)
    local link_data = {}
    for guid, link in pairs(link_table) do
        if link.active then
            link_data[guid] = {fx_map = link.fx_map}
        end
    end
    r.SetExtState(EXTSTATE_SECTION, "LinkTable", Serialize(link_data), true)
end

local function LoadState()
    local cfg_str = r.GetExtState(EXTSTATE_SECTION, "Config")
    if cfg_str ~= "" then
        local data = Unserialize(cfg_str)
        if data then
            custom_eq_presets = data.custom_eq or {}
            custom_sur_presets = data.custom_sur or {}
            if data.send_base_ch then send_config.base_ch = data.send_base_ch end
            if data.send_names then send_config.names = data.send_names end
            if data.send_levels then send_config.levels = data.send_levels end
            if data.send_enabled then send_config.enabled = data.send_enabled end
            if data.fx_priority then fx_priority = data.fx_priority end
            if data.show_tooltips ~= nil then show_tooltips = data.show_tooltips end
            if data.sur_output_idx then sur_output_idx = data.sur_output_idx end
            if data.surpan_tpl then surpan_templates = data.surpan_tpl end
            if data.tag_track then tag_track_name = data.tag_track end
            if data.item_params_captured then item_params_captured = data.item_params_captured end
            if data.item_params_enable then item_params_enable = data.item_params_enable end
        end
    end
end

-- =========================================================
-- BASE64 HELPERS
-- =========================================================
local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_INV = {}
for i = 1, #B64 do B64_INV[B64:sub(i, i)] = i - 1 end

local function b64_decode(data)
    data = data:gsub('[^%w+/=]', '') -- strip whitespace/newlines
    local out = {}
    local bits = 0
    local val = 0
    for i = 1, #data do
        local c = data:sub(i, i)
        if c == '=' then break end
        val = val * 64 + (B64_INV[c] or 0)
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(val / (2 ^ bits)) % 256
            table.insert(out, string.char(byte))
            val = val % (2 ^ bits)
        end
    end
    return table.concat(out)
end

local function b64_encode(data)
    local out = {}
    local val = 0
    local bits = 0
    for i = 1, #data do
        val = val * 256 + data:byte(i)
        bits = bits + 8
        while bits >= 6 do
            bits = bits - 6
            local idx = math.floor(val / (2 ^ bits)) % 64
            table.insert(out, B64:sub(idx + 1, idx + 1))
            val = val % (2 ^ bits)
        end
    end
    if bits > 0 then
        val = val * (2 ^ (6 - bits))
        local idx = val % 64
        table.insert(out, B64:sub(idx + 1, idx + 1))
    end
    local result = table.concat(out)
    local pad = (3 - #data % 3) % 3
    return result .. string.rep('=', pad)
end

-- =========================================================
-- HELPERS
-- =========================================================

local function RecoverItemByGUID(guid)
    if not guid or guid == "" then return nil end
    for i = 0, r.CountMediaItems(0) - 1 do
        local item = r.GetMediaItem(0, i)
        local _, ig = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
        if ig == guid then return item end
    end
    return nil
end

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

local function GetSelectedItems()
    local items = {}
    local cnt = r.CountSelectedMediaItems(0)
    for i = 0, cnt - 1 do
        table.insert(items, r.GetSelectedMediaItem(0, i))
    end
    return items
end

local function GetItemName(item)
    local take = r.GetActiveTake(item)
    if take then
        local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        if name ~= "" then return name end
    end
    return string.format("Item %d", r.GetMediaItemInfo_Value(item, "IP_ITEMNUMBER"))
end

-- =========================================================
-- ITEM PARAMETERS
-- =========================================================

function CaptureItemParams()
    local items = GetSelectedItems()
    if #items == 0 then log_msg = "No items selected"; return end

    local item = items[1]
    item_params_captured.volume = r.GetMediaItemInfo_Value(item, "D_VOL")
    item_params_captured.pan = r.GetMediaItemInfo_Value(item, "D_PAN")
    item_params_captured.pitch = r.GetMediaItemInfo_Value(item, "D_PITCH")
    item_params_captured.playrate = r.GetMediaItemInfo_Value(item, "D_PLAYRATE")
    item_params_captured.length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    item_params_captured.fade_in_len = r.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    item_params_captured.fade_out_len = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
    item_params_captured.fade_in_shape = r.GetMediaItemInfo_Value(item, "D_FADEINSHAPE")
    item_params_captured.fade_out_shape = r.GetMediaItemInfo_Value(item, "D_FADEOUTSHAPE")
    item_params_captured.pitch_mode = r.GetMediaItemInfo_Value(item, "I_PITCHMODE")
    item_params_captured.item_phase = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")

    SaveState()
    log_msg = string.format("Captured item params from '%s'", GetItemName(item))
end

function CloneItemParams(target_items)
    if #target_items == 0 then log_msg = "No items selected"; return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local count = 0
    for _, item in ipairs(target_items) do
        if item_params_enable.volume then r.SetMediaItemInfo_Value(item, "D_VOL", item_params_captured.volume) end
        if item_params_enable.pan then r.SetMediaItemInfo_Value(item, "D_PAN", item_params_captured.pan) end
        if item_params_enable.pitch then r.SetMediaItemInfo_Value(item, "D_PITCH", item_params_captured.pitch) end
        if item_params_enable.pitch_mode then r.SetMediaItemInfo_Value(item, "I_PITCHMODE", item_params_captured.pitch_mode) end
        if item_params_enable.playrate then r.SetMediaItemInfo_Value(item, "D_PLAYRATE", item_params_captured.playrate) end
        if item_params_enable.fade_in then
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", item_params_captured.fade_in_len)
            r.SetMediaItemInfo_Value(item, "D_FADEINSHAPE", item_params_captured.fade_in_shape)
        end
        if item_params_enable.fade_out then
            r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", item_params_captured.fade_out_len)
            r.SetMediaItemInfo_Value(item, "D_FADEOUTSHAPE", item_params_captured.fade_out_shape)
        end
        if item_params_enable.length then r.SetMediaItemInfo_Value(item, "D_LENGTH", item_params_captured.length) end
        if item_params_enable.item_phase then r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", item_params_captured.item_phase) end
        count = count + 1
    end

    SaveState()
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Clone Item Parameters", -1)
    log_msg = string.format("Cloned params to %d items", count)
end

local clone_params_to_tag_pending = false
local clone_params_to_tag_items = {}
local clone_params_to_tag_count = 0
local clone_params_to_tag_sel_track_count = 0

function CloneItemParamsToTag(tag)
    if not tag then return end

    local items = GetItemsForTag(tag)
    if #items == 0 then
        log_msg = "No items found in tag range"
        return
    end

    clone_params_to_tag_pending = true
    clone_params_to_tag_items = items
    clone_params_to_tag_count = #items
    clone_params_to_tag_sel_track_count = r.CountSelectedTracks(0)
end

-- Get tag name from item (take name, then P_NOTES fallback)
local function GetTagName(item)
    local take = r.GetActiveTake(item)
    if take then
        local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        if name ~= "" then return name end
    end
    local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    if note ~= "" then return note end
    return nil
end

-- Scan the tag track and return list of {item, name, start, finish}
local function GetTagsFromTrack()
    local tags = {}
    if tag_track_name == "" then return tags end
    -- Find tag track by name
    local tag_tr = nil
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tn == tag_track_name then tag_tr = tr; break end
    end
    if not tag_tr then return tags end
    -- Collect all items on that track
    local count = r.CountTrackMediaItems(tag_tr)
    for i = 0, count - 1 do
        local item = r.GetTrackMediaItem(tag_tr, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local name = GetTagName(item) or string.format("Tag %d", i + 1)
        table.insert(tags, {item = item, name = name, start = pos, finish = pos + len})
    end
    return tags
end

-- Select all items (on other tracks) overlapping a specific tag's time range
function SelectItemsByTag(tag)
    if not tag then log_msg = "No tag selected"; return end

    -- Build set of selected tracks (if any are selected, limit to those)
    local sel_tracks = {}
    local has_sel_tracks = false
    for i = 0, r.CountSelectedTracks(0) - 1 do
        local tr = r.GetSelectedTrack(0, i)
        sel_tracks[tr] = true
        has_sel_tracks = true
    end

    r.Main_OnCommand(40289, 0)  -- Deselect all items
    local sel_cnt = 0
    local total = r.CountMediaItems(0)
    for i = 0, total - 1 do
        local item = r.GetMediaItem(0, i)
        local tr = r.GetMediaItem_Track(item)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        -- Skip items on the tag track itself
        if tn ~= tag_track_name then
            -- If tracks are selected, only match items on those tracks
            if not has_sel_tracks or sel_tracks[tr] then
                local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                if pos >= tag.start and pos < tag.finish then
                    r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
                    sel_cnt = sel_cnt + 1
                end
            end
        end
    end

    r.UpdateArrange()
    local scope = has_sel_tracks and "selected tracks" or "all tracks"
    log_msg = string.format("Tag '%s': %d items (%s)", tag.name, sel_cnt, scope)
end

local function ValidateSource()
    if not captured_source.item then return false end
    if not r.ValidatePtr(captured_source.item, "MediaItem*") then
        captured_source.item = RecoverItemByGUID(captured_source.item_guid)
        if not captured_source.item then
            captured_source.fx_count = 0
            captured_source.fx_names = {}
            captured_source.fx_params = {}
            log_msg = "Source item lost"
            return false
        end
    end
    return true
end

-- Find ReaEQ on a take (returns fx index or -1)
local function FindReaEQOnTake(take)
    for fx = 0, r.TakeFX_GetCount(take) - 1 do
        local _, name = r.TakeFX_GetFXName(take, fx)
        if name:lower():find("reaeq") then return fx end
    end
    return -1
end

-- Find surround panner on a take (returns fx index or -1)
local function FindSurroundPanOnTake(take)
    for fx = 0, r.TakeFX_GetCount(take) - 1 do
        local _, name = r.TakeFX_GetFXName(take, fx)
        if name:lower():find("surround") or name:lower():find("span") then return fx end
    end
    return -1
end

-- =========================================================
-- FX PRIORITY HELPERS
-- =========================================================

-- Classify an existing FX on a take by its type
local function ClassifyTakeFX(take, fx_idx)
    local _, name = r.TakeFX_GetFXName(take, fx_idx)
    name = name:lower()
    if name:find("reaeq") then return "EQ" end
    if name:find("surround") or name:find("span") then return "SurPan" end
    if name:find("sbp send router") then return "Send" end
    return "Default"
end

-- Get priority index for an FX type (1-based, lower = earlier in chain)
local function GetPriorityIndex(fx_type)
    for i, t in ipairs(fx_priority) do
        if t == fx_type then return i end
    end
    return #fx_priority
end

-- Calculate the insertion position for a new FX based on fx_priority
-- Returns the 0-indexed chain position where the FX should be inserted
local function GetFXInsertPosition(take, fx_type)
    local target_pri = GetPriorityIndex(fx_type)
    local insert_pos = 0
    local count = r.TakeFX_GetCount(take)
    for fx = 0, count - 1 do
        local existing_pri = GetPriorityIndex(ClassifyTakeFX(take, fx))
        if existing_pri <= target_pri then
            insert_pos = fx + 1
        end
    end
    return insert_pos
end

-- =========================================================
-- PHASE 1: FX CAPTURE & CLONE
-- =========================================================

function CaptureSourceItem()
    local cnt = r.CountSelectedMediaItems(0)
    if cnt == 0 then
        log_msg = "Select an item to capture"
        return
    end
    local item = r.GetSelectedMediaItem(0, 0)
    local take = r.GetActiveTake(item)
    if not take then
        log_msg = "Item has no active take"
        return
    end

    captured_source.item = item
    local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
    captured_source.item_guid = guid
    captured_source.take = take
    captured_source.track = r.GetMediaItem_Track(item)
    captured_source.capture_time = r.time_precise()

    -- Read FX chain info
    captured_source.fx_count = r.TakeFX_GetCount(take)
    captured_source.fx_names = {}
    captured_source.fx_params = {}

    for fx = 0, captured_source.fx_count - 1 do
        local _, name = r.TakeFX_GetFXName(take, fx)
        table.insert(captured_source.fx_names, name)

        -- Cache all parameters
        captured_source.fx_params[fx] = {}
        local param_count = r.TakeFX_GetNumParams(take, fx)
        for p = 0, param_count - 1 do
            captured_source.fx_params[fx][p] = r.TakeFX_GetParamNormalized(take, fx, p)
        end
    end

    local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    log_msg = string.format("Captured: %s (%d FX)", take_name ~= "" and take_name or "unnamed", captured_source.fx_count)
end

function CloneFXChain_Manual(target_items)
    if not ValidateSource() then return end
    local src_take = r.GetActiveTake(captured_source.item)
    if not src_take then log_msg = "Source has no active take"; return end
    local src_fx_count = r.TakeFX_GetCount(src_take)
    if src_fx_count == 0 then log_msg = "Source has no FX"; return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for _, item in ipairs(target_items) do
        local tgt_take = r.GetActiveTake(item)
        if tgt_take and tgt_take ~= src_take then
            -- Clear existing FX on target
            while r.TakeFX_GetCount(tgt_take) > 0 do
                r.TakeFX_Delete(tgt_take, 0)
            end
            -- Copy each FX from source
            for fx = 0, src_fx_count - 1 do
                r.TakeFX_CopyToTake(src_take, fx, tgt_take, fx, false)
            end
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Manual Clone", -1)
    log_msg = string.format("Cloned %d FX to %d items", src_fx_count, #target_items)
end

function CloneFXChain_Unlinked(target_items)
    CloneFXChain_Manual(target_items)
end

-- Delete all FX from target items
function DeleteEffectsFromItems(target_items)
    if #target_items == 0 then log_msg = "No items selected"; return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local total_deleted = 0
    for _, item in ipairs(target_items) do
        local take = r.GetActiveTake(item)
        if take then
            while r.TakeFX_GetCount(take) > 0 do
                r.TakeFX_Delete(take, 0)
                total_deleted = total_deleted + 1
            end
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Delete Effects", -1)
    log_msg = string.format("Deleted %d effects from %d items", total_deleted, #target_items)
end

-- Get items that overlap with a tag's time range (respecting selected tracks if any)
local function GetItemsForTag(tag)
    if not tag then return {} end

    -- Build set of selected tracks (if any are selected, limit to those)
    local sel_tracks = {}
    local has_sel_tracks = false
    for i = 0, r.CountSelectedTracks(0) - 1 do
        local tr = r.GetSelectedTrack(0, i)
        sel_tracks[tr] = true
        has_sel_tracks = true
    end

    local items = {}
    local total = r.CountMediaItems(0)
    for i = 0, total - 1 do
        local item = r.GetMediaItem(0, i)
        local tr = r.GetMediaItem_Track(item)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        -- Skip items on the tag track itself
        if tn ~= tag_track_name then
            -- If tracks are selected, only match items on those tracks
            if not has_sel_tracks or sel_tracks[tr] then
                local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                if pos >= tag.start and pos < tag.finish then
                    table.insert(items, item)
                end
            end
        end
    end
    return items
end

-- Clone FX to items in tag with confirmation dialog
local clone_to_tag_pending = false
local clone_to_tag_items = {}
local clone_to_tag_count = 0

function CloneFXToTagItems(tag)
    if not ValidateSource() then return end

    local items = GetItemsForTag(tag)
    if #items == 0 then
        log_msg = "No items found in tag range"
        return
    end

    -- Show confirmation dialog
    clone_to_tag_pending = true
    clone_to_tag_items = items
    clone_to_tag_count = #items
end

-- =========================================================
-- PHASE 2: LINKED CLONE ENGINE
-- =========================================================

local function MarkSourceItem(item, take)
    -- Add [SRC] suffix to take name
    local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if not take_name:find("%[SRC%]") then
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name .. LINK_SRC_SUFFIX, true)
    end
    -- Set item color to white
    r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", r.ColorToNative(255, 255, 255) | 0x01000000)
end

function CloneFXChain_Linked(target_items)
    if not ValidateSource() then return end
    local src_take = r.GetActiveTake(captured_source.item)
    if not src_take then return end
    local src_fx_count = r.TakeFX_GetCount(src_take)

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Mark source item
    MarkSourceItem(captured_source.item, src_take)

    for _, item in ipairs(target_items) do
        local tgt_take = r.GetActiveTake(item)
        if tgt_take and tgt_take ~= src_take then
            -- Clear and copy
            while r.TakeFX_GetCount(tgt_take) > 0 do
                r.TakeFX_Delete(tgt_take, 0)
            end
            for fx = 0, src_fx_count - 1 do
                r.TakeFX_CopyToTake(src_take, fx, tgt_take, fx, false)
            end

            -- Register in link table
            local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
            local fx_map = {}
            for fx = 0, src_fx_count - 1 do
                fx_map[fx] = fx
            end
            link_table[guid] = {
                item = item,
                take = tgt_take,
                fx_map = fx_map,
                active = true,
            }
        end
    end

    link_engine_active = true
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Linked Clone", -1)

    local link_count = 0
    for _ in pairs(link_table) do link_count = link_count + 1 end
    log_msg = string.format("Linked clone: %d FX to %d items (%d total links)", src_fx_count, #target_items, link_count)
    SaveState()
end

function UnlinkAll()
    link_table = {}
    link_engine_active = false
    log_msg = "All links removed"
    SaveState()
end

function SyncLinkedItems()
    if not link_engine_active then return end
    if not ValidateSource() then
        link_engine_active = false
        return
    end

    local now = r.time_precise()
    if (now - link_last_sync) < link_sync_interval then return end
    link_last_sync = now

    local src_take = r.GetActiveTake(captured_source.item)
    if not src_take then return end
    local src_fx_count = r.TakeFX_GetCount(src_take)

    -- Read current source params and compare with cache
    local changed_params = {}
    local any_changed = false
    for fx = 0, src_fx_count - 1 do
        local param_count = r.TakeFX_GetNumParams(src_take, fx)
        for p = 0, param_count - 1 do
            local val = r.TakeFX_GetParamNormalized(src_take, fx, p)
            local cached = captured_source.fx_params[fx] and captured_source.fx_params[fx][p]
            if not cached or math.abs(val - cached) > 0.0001 then
                if not changed_params[fx] then changed_params[fx] = {} end
                changed_params[fx][p] = val
                if not captured_source.fx_params[fx] then captured_source.fx_params[fx] = {} end
                captured_source.fx_params[fx][p] = val
                any_changed = true
            end
        end
    end

    if not any_changed then return end

    -- Apply changes to all linked targets
    for guid, link in pairs(link_table) do
        if not link.active then goto continue end

        if not r.ValidatePtr(link.item, "MediaItem*") then
            link.item = RecoverItemByGUID(guid)
            if not link.item then
                link.active = false
                goto continue
            end
            link.take = r.GetActiveTake(link.item)
        end

        local tgt_take = link.take or r.GetActiveTake(link.item)
        if not tgt_take then goto continue end

        for src_fx, params in pairs(changed_params) do
            local tgt_fx = link.fx_map[src_fx]
            if tgt_fx and tgt_fx < r.TakeFX_GetCount(tgt_take) then
                for p, val in pairs(params) do
                    r.TakeFX_SetParamNormalized(tgt_take, tgt_fx, p, val)
                end
            end
        end
        ::continue::
    end
end

-- =========================================================
-- PHASE 3: EQ PRESETS (ReaEQ)
-- =========================================================

-- Add or find existing ReaEQ on take (respects fx_priority order)
local function AddReaEQToTake(take)
    local existing = FindReaEQOnTake(take)
    if existing >= 0 then return existing end
    local pos = GetFXInsertPosition(take, "EQ")
    local names = {"ReaEQ", "VST: ReaEQ", "VST: ReaEQ (Cockos)", "Cockos/ReaEQ"}
    for _, name in ipairs(names) do
        local fx_idx = r.TakeFX_AddByName(take, name, -(1000 + pos))
        if fx_idx >= 0 then return fx_idx end
    end
    return -1
end

-- Parse ReaEQ param names to discover bands and their types.
local function DiscoverReaEQBands(take, fx_idx)
    local param_count = r.TakeFX_GetNumParams(take, fx_idx)
    local bands = {}
    local band_map = {}

    for p = 0, param_count - 1 do
        local _, pname = r.TakeFX_GetParamName(take, fx_idx, p)
        local param_type, band_name = pname:match("^(%w+)%-(.+)$")
        if param_type and band_name then
            if not band_map[band_name] then
                band_map[band_name] = {band_name = band_name}
                table.insert(bands, band_map[band_name])
            end
            local b = band_map[band_name]
            local pt = param_type:lower()
            if pt == "freq" then b.freq_idx = p
            elseif pt == "gain" then b.gain_idx = p
            elseif pt == "bw" then b.bw_idx = p
            end
        end
    end

    for _, band in ipairs(bands) do
        local nl = band.band_name:lower()
        if nl:find("high pass") then band.type = "HP"
        elseif nl:find("low pass") then band.type = "LP"
        elseif nl:find("high shelf") then band.type = "HS"
        elseif nl:find("low shelf") then band.type = "LS"
        elseif nl:find("notch") then band.type = "Notch"
        else band.type = "Band"
        end
    end

    return bands
end

-- Binary search: find the normalized 0-1 value that produces the desired display value.
local function FindNormForValue(take, fx_idx, param_idx, target, tolerance)
    tolerance = tolerance or 0.5
    local lo, hi = 0.0, 1.0
    local best_norm = 0.5
    local best_diff = math.huge

    for _ = 1, 32 do
        local mid = (lo + hi) / 2
        r.TakeFX_SetParamNormalized(take, fx_idx, param_idx, mid)
        local ok, formatted = r.TakeFX_GetFormattedParamValue(take, fx_idx, param_idx)
        if not ok or not formatted then return mid end

        local val = tonumber(formatted:match("([%-+]?[%d%.]+)"))
        if not val then return mid end

        local diff = math.abs(val - target)
        if diff < best_diff then
            best_diff = diff
            best_norm = mid
        end
        if diff <= tolerance then return mid end
        if val < target then lo = mid else hi = mid end
    end
    r.TakeFX_SetParamNormalized(take, fx_idx, param_idx, best_norm)
    return best_norm
end

-- ReaEQ band type numbers for TakeFX_SetNamedConfigParm("BANDTYPEn", value)
local REAEQ_TYPES = {
    LS = "0",       -- Low Shelf
    HS = "1",       -- High Shelf
    LP = "3",       -- Low Pass
    HP = "4",       -- High Pass
    AllPass = "5",  -- All Pass
    Notch = "6",    -- Notch
    BandPass = "7", -- Band Pass
    Band = "8",     -- Band (parametric)
}

-- Configure a full ReaEQ instance with the given band configurations.
local function ConfigureReaEQ(take, fx_idx, bands_config)
    local bands = DiscoverReaEQBands(take, fx_idx)
    if #bands == 0 then
        log_msg = "EQ: Could not discover ReaEQ bands"
        return false
    end

    -- Phase 1: Set band types and enable bands via named config params
    for i, cfg in ipairs(bands_config) do
        if i > #bands then break end
        local band_0idx = i - 1
        local type_val = REAEQ_TYPES[cfg.type] or REAEQ_TYPES.Band
        r.TakeFX_SetNamedConfigParm(take, fx_idx, "BANDTYPE" .. band_0idx, type_val)
        r.TakeFX_SetNamedConfigParm(take, fx_idx, "BANDENABLED" .. band_0idx, "1")
    end

    -- Re-discover bands (param names change after type change)
    bands = DiscoverReaEQBands(take, fx_idx)

    -- Phase 2: Set freq/gain/bw using binary search
    for i, cfg in ipairs(bands_config) do
        if i > #bands then break end
        local band = bands[i]

        if band.freq_idx and cfg.freq then
            FindNormForValue(take, fx_idx, band.freq_idx, cfg.freq, 1.0)
        end
        if band.gain_idx and cfg.gain then
            FindNormForValue(take, fx_idx, band.gain_idx, cfg.gain, 0.1)
        end
        if band.bw_idx and cfg.bw then
            FindNormForValue(take, fx_idx, band.bw_idx, cfg.bw, 0.02)
        end
    end

    -- Reset unused bands: disable and zero gain
    for i = #bands_config + 1, #bands do
        local band_0idx = i - 1
        r.TakeFX_SetNamedConfigParm(take, fx_idx, "BANDENABLED" .. band_0idx, "0")
        if bands[i] and bands[i].gain_idx then
            FindNormForValue(take, fx_idx, bands[i].gain_idx, 0.0, 0.1)
        end
    end

    return true
end

-- Check if an item's ReaEQ matches a preset (compare band frequencies)
local function ItemMatchesEQPreset(item, preset)
    if not preset or not preset.bands then return false end
    local take = r.GetActiveTake(item)
    if not take then return false end
    local fx_idx = FindReaEQOnTake(take)
    if fx_idx < 0 then return false end

    local bands = DiscoverReaEQBands(take, fx_idx)
    if #bands < #preset.bands then return false end

    for i, cfg in ipairs(preset.bands) do
        if i > #bands then return false end
        local band = bands[i]
        -- Check frequency match
        if band.freq_idx and cfg.freq then
            local ok, fmt = r.TakeFX_GetFormattedParamValue(take, fx_idx, band.freq_idx)
            if ok then
                local val = tonumber(fmt:match("([%-+]?[%d%.]+)"))
                if val and math.abs(val - cfg.freq) > 10 then return false end
            end
        end
        -- Check gain match (for non-HP/LP)
        if band.gain_idx and cfg.gain and cfg.type ~= "HP" and cfg.type ~= "LP" then
            local ok, fmt = r.TakeFX_GetFormattedParamValue(take, fx_idx, band.gain_idx)
            if ok then
                local val = tonumber(fmt:match("([%-+]?[%d%.]+)"))
                if val and math.abs(val - cfg.gain) > 1.0 then return false end
            end
        end
    end
    return true
end

-- Select all items in project that match the given EQ preset
local function SelectItemsWithEQPreset(preset)
    r.PreventUIRefresh(1)
    r.SelectAllMediaItems(0, false)
    local count = 0
    for i = 0, r.CountMediaItems(0) - 1 do
        local item = r.GetMediaItem(0, i)
        if ItemMatchesEQPreset(item, preset) then
            r.SetMediaItemSelected(item, true)
            count = count + 1
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    log_msg = string.format("Selected %d items with '%s'", count, preset.name)
end

-- Select all items that have surround panner FX
local function SelectItemsWithSurroundPan()
    r.PreventUIRefresh(1)
    r.SelectAllMediaItems(0, false)
    local count = 0
    for i = 0, r.CountMediaItems(0) - 1 do
        local item = r.GetMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take and FindSurroundPanOnTake(take) >= 0 then
            r.SetMediaItemSelected(item, true)
            count = count + 1
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    log_msg = string.format("Selected %d items with SurroundPan", count)
end

function ApplyEQPreset(preset, items, action)
    action = action or "INSERT"

    -- SEL ONLY: select matching items across project
    if action == "SEL_ONLY" then
        if preset then SelectItemsWithEQPreset(preset) end
        return
    end

    if #items == 0 then log_msg = "No items selected"; return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if not take then goto continue end

        if action == "INSERT" then
            if not preset or not preset.bands then goto continue end
            local fx_idx = AddReaEQToTake(take)
            if fx_idx >= 0 then
                ConfigureReaEQ(take, fx_idx, preset.bands)
            else
                log_msg = "ReaEQ plugin not found"
            end

        elseif action == "DEL" then
            for fx = r.TakeFX_GetCount(take) - 1, 0, -1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("reaeq") then
                    r.TakeFX_Delete(take, fx)
                end
            end

        elseif action == "ON" then
            for fx = 0, r.TakeFX_GetCount(take) - 1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("reaeq") then
                    r.TakeFX_SetEnabled(take, fx, true)
                end
            end

        elseif action == "OFF" then
            for fx = 0, r.TakeFX_GetCount(take) - 1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("reaeq") then
                    r.TakeFX_SetEnabled(take, fx, false)
                end
            end

        end
        ::continue::
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: EQ " .. action .. " - " .. (preset and preset.name or "all"), -1)
    log_msg = string.format("EQ %s: %s on %d items", action, preset and preset.name or "all", #items)
end

-- =========================================================
-- PHASE 4: SURROUND PAN PRESETS
-- =========================================================

-- Add or find existing surround panner on take (respects fx_priority order)
local function AddSurroundPanToTake(take)
    local existing = FindSurroundPanOnTake(take)
    if existing >= 0 then return existing end
    local pos = GetFXInsertPosition(take, "SurPan")
    local names = {
        "ReaSurroundPan", "VST: ReaSurroundPan", "VST: ReaSurroundPan (Cockos)",
        "Cockos/ReaSurroundPan", "SurroundPan"
    }
    for _, name in ipairs(names) do
        local fx_idx = r.TakeFX_AddByName(take, name, -(1000 + pos))
        if fx_idx >= 0 then return fx_idx end
    end
    return -1
end

-- Helper: extract VST block boundaries from item chunk
local function FindVSTBlock(chunk, plugin_name)
    local vst_start = chunk:find('<VST "VST: ' .. plugin_name)
                   or chunk:find('<VST "VST3: ' .. plugin_name)
    if not vst_start then return nil end
    local depth, vst_end = 0, vst_start
    for pos = vst_start, #chunk do
        local c = chunk:sub(pos, pos)
        if c == '<' then depth = depth + 1
        elseif c == '>' then
            depth = depth - 1
            if depth == 0 then vst_end = pos; break end
        end
    end
    return vst_start, vst_end
end

-- Helper: parse VST block into lines
local function ParseVSTBlock(chunk, vst_start, vst_end)
    local vst_block = chunk:sub(vst_start, vst_end)
    local lines = {}
    for line in vst_block:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- Helper: extract & decode the plugin state (second base64 block)
local function DecodePluginState(lines)
    local state_b64_parts = {}
    for i = 3, #lines - 1 do
        local trimmed = lines[i]:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(state_b64_parts, trimmed)
        end
    end
    if #state_b64_parts == 0 then return nil end
    return b64_decode(table.concat(state_b64_parts))
end

-- Helper: encode state binary, rebuild VST block, set chunk
local function SetPluginState(item, chunk, vst_start, vst_end, lines, state_bin)
    local new_b64 = b64_encode(state_bin)
    local b64_lines = {}
    for i = 1, #new_b64, 128 do
        table.insert(b64_lines, new_b64:sub(i, math.min(i + 127, #new_b64)))
    end
    local new_vst_lines = {lines[1], lines[2]}
    for _, bl in ipairs(b64_lines) do
        table.insert(new_vst_lines, bl)
    end
    table.insert(new_vst_lines, lines[#lines])
    local new_vst_block = table.concat(new_vst_lines, "\n")
    local new_chunk = chunk:sub(1, vst_start - 1) .. new_vst_block .. chunk:sub(vst_end + 1)
    return r.SetItemStateChunk(item, new_chunk, false)
end

-- Capture the current ReaSurroundPan state from selected item as a template
-- Stores under the currently selected output format name
local function CaptureSurroundTemplate()
    if sur_output_idx <= 0 then log_msg = "Select output format first"; return end
    local fmt = SUR_OUTPUT_FORMATS[sur_output_idx]
    if not fmt then return end

    local items = GetSelectedItems()
    if #items == 0 then log_msg = "Select item with SurroundPan"; return end
    local take = r.GetActiveTake(items[1])
    if not take then log_msg = "No active take"; return end
    local fx_idx = FindSurroundPanOnTake(take)
    if fx_idx < 0 then log_msg = "No SurroundPan on item"; return end

    local item = r.GetMediaItemTake_Item(take)
    local ok, chunk = r.GetItemStateChunk(item, "", false)
    if not ok then return end

    local vst_start, vst_end = FindVSTBlock(chunk, "ReaSurroundPan")
    if not vst_start then log_msg = "SurroundPan block not found"; return end

    local lines = ParseVSTBlock(chunk, vst_start, vst_end)
    if #lines < 4 then return end

    local state_bin = DecodePluginState(lines)
    if not state_bin or #state_bin < 60 then return end

    -- Store template keyed by format name
    surpan_templates[fmt.name] = {
        state = b64_encode(state_bin),
        reaper_line = lines[2],
        channels = fmt.channels,
    }
    SaveState()

    log_msg = string.format("Captured SurPan template: %s (%d bytes)", fmt.name, #state_bin)
end

-- Configure ReaSurroundPan using captured template (applied as-is)
local function ConfigureSurroundPan(take, _fx_idx, output_fmt)
    local fmt_name = output_fmt and output_fmt.name or "5.1"

    local item = r.GetMediaItemTake_Item(take)
    if not item then return end

    local template = surpan_templates[fmt_name]
    if not template then
        log_msg = string.format("No template for %s — capture first", fmt_name)
        return
    end

    local ok, chunk = r.GetItemStateChunk(item, "", false)
    if not ok then return end
    local vst_start, vst_end = FindVSTBlock(chunk, "ReaSurroundPan")
    if not vst_start then return end
    local lines = ParseVSTBlock(chunk, vst_start, vst_end)
    if #lines < 4 then return end

    -- Decode and apply template state directly
    local state_bin = b64_decode(template.state)
    if not state_bin or #state_bin < 60 then return end

    if template.reaper_line then
        lines[2] = template.reaper_line
    end

    SetPluginState(item, chunk, vst_start, vst_end, lines, state_bin)
end

function ApplySurroundPreset(items, action, output_fmt)
    action = action or "INSERT"

    if action == "SEL_ONLY" then
        SelectItemsWithSurroundPan()
        return
    end

    if #items == 0 then log_msg = "No items selected"; return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if not take then goto continue end

        if action == "INSERT" then
            if not output_fmt then goto continue end
            -- Delete existing surround pan first for clean state
            for fx = r.TakeFX_GetCount(take) - 1, 0, -1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("surround") or name:lower():find("span") then
                    r.TakeFX_Delete(take, fx)
                end
            end
            -- Add fresh + configure
            local fx_idx = AddSurroundPanToTake(take)
            if fx_idx >= 0 then
                ConfigureSurroundPan(take, fx_idx, output_fmt)
                log_msg = string.format("SurPan: %s applied", output_fmt.name)
            else
                log_msg = "SurroundPan plugin not found"
            end

        elseif action == "DEL" then
            for fx = r.TakeFX_GetCount(take) - 1, 0, -1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("surround") or name:lower():find("span") then
                    r.TakeFX_Delete(take, fx)
                end
            end

        elseif action == "ON" then
            for fx = 0, r.TakeFX_GetCount(take) - 1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("surround") or name:lower():find("span") then
                    r.TakeFX_SetEnabled(take, fx, true)
                end
            end

        elseif action == "OFF" then
            for fx = 0, r.TakeFX_GetCount(take) - 1 do
                local _, name = r.TakeFX_GetFXName(take, fx)
                if name:lower():find("surround") or name:lower():find("span") then
                    r.TakeFX_SetEnabled(take, fx, false)
                end
            end

        end
        ::continue::
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    local label = output_fmt and output_fmt.name or "all"
    r.Undo_EndBlock("ItemFX: SurPan " .. action .. " - " .. label, -1)
    log_msg = string.format("SurPan %s: %s on %d items", action, label, #items)
end

-- =========================================================
-- PHASE 5: SEND ROUTING (per-item via JSFX)
-- =========================================================

local SEND_ROUTER_NAME = "SBP Send Router"

-- Find SendRouter JSFX on a take (returns fx index or -1)
local function FindSendRouterOnTake(take)
    for fx = 0, r.TakeFX_GetCount(take) - 1 do
        local _, name = r.TakeFX_GetFXName(take, fx)
        if name:find(SEND_ROUTER_NAME) then return fx end
    end
    return -1
end

-- Add or find existing SendRouter JSFX on take (respects fx_priority order)
local function FindOrAddSendRouter(take)
    local existing = FindSendRouterOnTake(take)
    if existing >= 0 then return existing end
    local pos = GetFXInsertPosition(take, "Send")
    local fx_idx = r.TakeFX_AddByName(take, SEND_ROUTER_NAME, -(1000 + pos))
    return fx_idx
end

-- Configure pin mappings for Send Router JSFX based on base_ch
-- JSFX layout: pins 0-7 = main, 8-15 = send1, 16-23 = send2, 24-31 = send3, 32-39 = send4
-- Take layout: ch 0..base_ch-1 = main, then base_ch channels per send
local function SetSendRouterPinMappings(take, fx_idx)
    local base_ch = send_config.base_ch  -- 2, 6, or 8

    -- Clear all pin mappings (8 inputs + 40 outputs)
    for pin = 0, 7 do
        r.TakeFX_SetPinMappings(take, fx_idx, 0, pin, 0, 0)
    end
    for pin = 0, 39 do
        r.TakeFX_SetPinMappings(take, fx_idx, 1, pin, 0, 0)
    end

    -- Input pins: 0..base_ch-1 → take channels 0..base_ch-1
    for pin = 0, base_ch - 1 do
        r.TakeFX_SetPinMappings(take, fx_idx, 0, pin, 1 << pin, 0)
    end

    -- Main output pins: 0..base_ch-1 → take channels 0..base_ch-1
    for pin = 0, base_ch - 1 do
        r.TakeFX_SetPinMappings(take, fx_idx, 1, pin, 1 << pin, 0)
    end

    -- 4 send output blocks: each copies base_ch channels to its own range
    for s = 0, NUM_SENDS - 1 do
        for ch = 0, base_ch - 1 do
            local jsfx_pin = 8 + s * 8 + ch           -- JSFX output pin
            local take_ch = base_ch * (s + 1) + ch    -- take channel (0-indexed)
            if take_ch < 32 then
                r.TakeFX_SetPinMappings(take, fx_idx, 1, jsfx_pin, 1 << take_ch, 0)
            else
                r.TakeFX_SetPinMappings(take, fx_idx, 1, jsfx_pin, 0, 1 << (take_ch - 32))
            end
        end
    end
end

-- Set send level on a JSFX instance (send_slot 1-4, vol_db in dB or -60 for off)
-- Use TakeFX_SetParam to pass actual dB value directly (NOT SetParamNormalized)
local function SetItemSendLevel(take, fx_idx, send_slot, vol_db)
    local param_idx = send_slot - 1  -- slider1=param0, slider2=param1, etc.
    r.TakeFX_SetParam(take, fx_idx, param_idx, vol_db)
end

-- Find a track by name
local function FindTrackByName(name)
    if not name or name == "" then return nil end
    for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tn == name then return tr end
    end
    return nil
end

-- Find existing send from track to dest_track
local function FindExistingSend(track, dest_track)
    local num_sends = r.GetTrackNumSends(track, 0)
    for s = 0, num_sends - 1 do
        local dest = r.GetTrackSendInfo_Value(track, 0, s, "P_DESTTRACK")
        if dest == dest_track then return s end
    end
    return -1
end

-- Apply send routing: add JSFX to items + create track sends
-- Each send has its own JSFX slider and channel range for per-item per-bus control
function ApplySendRouting(items)
    if #items == 0 then log_msg = "No items selected"; return end

    -- Resolve enabled bus tracks by name
    local active_sends = {}
    for i = 1, NUM_SENDS do
        if send_config.enabled[i] then
            local name = send_config.names[i]
            if name and name ~= "" then
                local tr = FindTrackByName(name)
                if tr then
                    table.insert(active_sends, {slot = i, track = tr, name = name})
                end
            end
        end
    end

    if #active_sends == 0 then
        log_msg = "No enabled sends with valid bus tracks"
        return
    end

    local base_ch = send_config.base_ch
    local needed_ch = base_ch * (1 + NUM_SENDS)  -- main + 4 sends

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local tracks_done = {}

    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if not take then goto continue end

        -- Expand track channels FIRST (once per track) so pin mappings can target higher channels
        local tr = r.GetMediaItem_Track(item)
        local _, tr_guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
        if not tracks_done[tr_guid] then
            tracks_done[tr_guid] = true

            local current_ch = r.GetMediaTrackInfo_Value(tr, "I_NCHAN")
            if current_ch < needed_ch then
                r.SetMediaTrackInfo_Value(tr, "I_NCHAN", needed_ch)
            end

            -- Create sends: each from its own channel range
            for _, s in ipairs(active_sends) do
                local src_offset = base_ch * s.slot  -- 0-indexed: stereo→2,4,6,8; 5.1→6,12,18,24
                local send_idx = FindExistingSend(tr, s.track)
                if send_idx < 0 then
                    send_idx = r.CreateTrackSend(tr, s.track)
                end
                if send_idx >= 0 then
                    -- Encode multichannel source: first_ch | ((nch/2) << 10)
                    local src_chan = src_offset
                    if base_ch > 2 then
                        src_chan = src_offset + ((base_ch >> 1) << 10)
                    end
                    r.SetTrackSendInfo_Value(tr, 0, send_idx, "I_SRCCHAN", src_chan)
                    r.SetTrackSendInfo_Value(tr, 0, send_idx, "I_DSTCHAN", 0)
                    r.SetTrackSendInfo_Value(tr, 0, send_idx, "D_VOL", 1.0)
                    r.SetTrackSendInfo_Value(tr, 0, send_idx, "I_SENDMODE", 0)
                    r.SetTrackSendInfo_Value(tr, 0, send_idx, "I_MIDIFLAGS", 31)
                end
            end
        end

        -- Add JSFX, configure pin mappings, and set per-send levels
        local fx_idx = FindOrAddSendRouter(take)
        if fx_idx >= 0 then
            SetSendRouterPinMappings(take, fx_idx)
            for i = 1, NUM_SENDS do
                -- Disabled sends get -inf regardless of UI slider
                local vol = send_config.enabled[i] and send_config.levels[i] or -60
                SetItemSendLevel(take, fx_idx, i, vol)
            end
        end

        ::continue::
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Apply Send Routing", -1)
    log_msg = string.format("Send routing: %d sends (%dch) on %d items", #active_sends, base_ch, #items)
end

-- Remove send routing: delete JSFX from items + remove track sends
function RemoveSendRouting(items)
    if #items == 0 then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local tracks_done = {}
    for _, item in ipairs(items) do
        local take = r.GetActiveTake(item)
        if take then
            local fx_idx = FindSendRouterOnTake(take)
            if fx_idx >= 0 then
                r.TakeFX_Delete(take, fx_idx)
            end
        end

        -- Remove track sends to known bus tracks (iterate backwards to keep indices stable)
        local tr = r.GetMediaItem_Track(item)
        local _, tr_guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
        if not tracks_done[tr_guid] then
            tracks_done[tr_guid] = true
            for i = NUM_SENDS, 1, -1 do
                local name = send_config.names[i]
                if name and name ~= "" then
                    local bus_tr = FindTrackByName(name)
                    if bus_tr then
                        local si = FindExistingSend(tr, bus_tr)
                        if si >= 0 then r.RemoveTrackSend(tr, 0, si) end
                    end
                end
            end
            -- Restore track to base channel count
            r.SetMediaTrackInfo_Value(tr, "I_NCHAN", math.max(2, send_config.base_ch))
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("ItemFX: Remove Send Routing", -1)
    log_msg = "Send routing removed"
end

-- =========================================================
-- THEME
-- =========================================================
local function PushTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.BG)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.FRAME)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), C.BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), C.BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.TEXT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C.BTN)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), C.BTN_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), C.TEAL)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), C.TEAL)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), C.TEAL_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), C.BORDER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), C.BG)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 8)
end

local function PopTheme()
    r.ImGui_PopStyleColor(ctx, 16)
    r.ImGui_PopStyleVar(ctx, 4)
end

-- =========================================================
-- UI HELPERS
-- =========================================================

local function TealButton(label, w, h)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.TEAL)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.TEAL_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.TEAL_HOV)
    local pressed = r.ImGui_Button(ctx, label, w or 0, h or 0)
    r.ImGui_PopStyleColor(ctx, 3)
    return pressed
end

local function OrangeButton(label, w, h)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.ORANGE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.ORANGE_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.ORANGE_HOV)
    local pressed = r.ImGui_Button(ctx, label, w or 0, h or 0)
    r.ImGui_PopStyleColor(ctx, 3)
    return pressed
end

local function RedButton(label, w, h)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.RED)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.RED_HOV)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.RED_HOV)
    local pressed = r.ImGui_Button(ctx, label, w or 0, h or 0)
    r.ImGui_PopStyleColor(ctx, 3)
    return pressed
end

local function Tooltip(text)
    if show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, text)
    end
end

-- =========================================================
-- UI SECTIONS
-- =========================================================

local function DrawStatusBar()
    local sel_count = r.CountSelectedMediaItems(0)
    local src_name = "none"
    if captured_source.item and ValidateSource() then
        local take = r.GetActiveTake(captured_source.item)
        if take then
            local _, tn = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            src_name = tn ~= "" and tn or "unnamed"
        end
    end

    local link_count = 0
    for _, link in pairs(link_table) do
        if link.active then link_count = link_count + 1 end
    end

    r.ImGui_TextDisabled(ctx, string.format("Sel: %d  |  Source: %s (%d FX)  |  Links: %d  |  %s",
        sel_count, src_name, captured_source.fx_count, link_count, log_msg))
end

local function DrawCaptureButtons()
    -- Top row: Capture button + current source info
    if OrangeButton("CAPTURE FX", 80) then
        CaptureSourceItem()
    end
    Tooltip("Capture FX chain from first selected item (C)")
    r.ImGui_SameLine(ctx)

    if captured_source.fx_count > 0 then
        local fx_str = table.concat(captured_source.fx_names, ", ")
        r.ImGui_TextDisabled(ctx, fx_str)
    else
        r.ImGui_TextDisabled(ctx, "No source captured")
    end

    r.ImGui_Spacing(ctx)

    -- Clone operations
    if TealButton("Manual Clone", 100) then
        CloneFXChain_Manual(GetSelectedItems())
    end
    Tooltip("One-time copy of FX chain to selected items (M)")
    r.ImGui_SameLine(ctx)

    if TealButton("Linked Clone", 100) then
        CloneFXChain_Linked(GetSelectedItems())
    end
    Tooltip("Copy FX chain with real-time parameter sync (L)")
    r.ImGui_SameLine(ctx)

    if TealButton("Clone FX to Tag", 100) then
        local tags = GetTagsFromTrack()
        if #tags > 0 then
            local tag = tags[tag_selected_idx + 1]
            if tag then
                clone_to_tag_sel_track_count = r.CountSelectedTracks(0)
                CloneFXToTagItems(tag)
            else
                log_msg = "Select a tag first"
            end
        else
            log_msg = "No tags available"
        end
    end
    Tooltip("Clone FX to items in selected tag (applies to selected tracks only)")
    r.ImGui_SameLine(ctx)

    if RedButton("Delete FX", 75) then
        DeleteEffectsFromItems(GetSelectedItems())
    end
    Tooltip("Remove all effects from selected items")

    if link_engine_active then
        r.ImGui_SameLine(ctx)
        if RedButton("Unlink All", 70) then
            UnlinkAll()
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.ACTIVE)
        r.ImGui_Text(ctx, "SYNC ON")
        r.ImGui_PopStyleColor(ctx)
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
end

local function DrawCaptureSection()
    if not r.ImGui_CollapsingHeader(ctx, "SOURCE CAPTURE") then return end
    r.ImGui_TextDisabled(ctx, "Use buttons above to capture and clone FX chains")
end

local function DrawEQSection()
    if not r.ImGui_CollapsingHeader(ctx, "EQ PRESETS") then return end

    local w = r.ImGui_GetContentRegionAvail(ctx)
    local btn_w = math.max(70, (w - 12) / 5)

    -- Built-in presets grid
    r.ImGui_TextDisabled(ctx, "Built-in:")
    local col = 0
    for i, preset in ipairs(EQ_PRESETS) do
        if col > 0 then r.ImGui_SameLine(ctx) end
        local is_sel = (selected_eq_preset == i)
        if is_sel then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.TEAL)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.TEAL_HOV)
        end
        if r.ImGui_Button(ctx, preset.name .. "##eq" .. i, btn_w) then
            selected_eq_preset = i
        end
        if is_sel then r.ImGui_PopStyleColor(ctx, 2) end
        col = col + 1
        if col >= 5 then col = 0 end
    end

    -- Custom presets
    if #custom_eq_presets > 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_TextDisabled(ctx, "Custom:")
        col = 0
        for i, preset in ipairs(custom_eq_presets) do
            if col > 0 then r.ImGui_SameLine(ctx) end
            local global_idx = #EQ_PRESETS + i
            local is_sel = (selected_eq_preset == global_idx)
            if is_sel then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.ORANGE)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.ORANGE_HOV)
            end
            if r.ImGui_Button(ctx, preset.name .. "##ceq" .. i, btn_w) then
                selected_eq_preset = global_idx
            end
            if is_sel then r.ImGui_PopStyleColor(ctx, 2) end
            col = col + 1
            if col >= 5 then col = 0 end
        end
    end

    r.ImGui_Spacing(ctx)

    -- Resolve current preset (may be nil)
    local current = nil
    if selected_eq_preset > 0 and selected_eq_preset <= #EQ_PRESETS then
        current = EQ_PRESETS[selected_eq_preset]
    elseif selected_eq_preset > #EQ_PRESETS then
        current = custom_eq_presets[selected_eq_preset - #EQ_PRESETS]
    end

    -- Action row: always visible. INSERT/SEL ONLY need preset, DEL/ON/OFF work without.
    local btn_act_w = 55
    local sfx = "##act_EQ"

    -- INSERT (needs preset)
    if current then
        if TealButton("INSERT" .. sfx, btn_act_w) then
            ApplyEQPreset(current, GetSelectedItems(), "INSERT")
        end
    else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Button(ctx, "INSERT" .. sfx, btn_act_w)
        r.ImGui_EndDisabled(ctx)
    end
    r.ImGui_SameLine(ctx)

    -- DEL
    if RedButton("DEL" .. sfx, btn_act_w) then
        ApplyEQPreset(nil, GetSelectedItems(), "DEL")
    end
    r.ImGui_SameLine(ctx)

    -- SEL ONLY (needs preset)
    if current then
        if r.ImGui_Button(ctx, "SEL ONLY" .. sfx, btn_act_w) then
            ApplyEQPreset(current, {}, "SEL_ONLY")
        end
        Tooltip("Select all items matching this preset")
    else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Button(ctx, "SEL ONLY" .. sfx, btn_act_w)
        r.ImGui_EndDisabled(ctx)
    end
    r.ImGui_SameLine(ctx)

    -- ON
    if r.ImGui_Button(ctx, "ON" .. sfx, btn_act_w) then
        ApplyEQPreset(nil, GetSelectedItems(), "ON")
    end
    r.ImGui_SameLine(ctx)

    -- OFF
    if r.ImGui_Button(ctx, "OFF" .. sfx, btn_act_w) then
        ApplyEQPreset(nil, GetSelectedItems(), "OFF")
    end

    -- Save custom preset
    r.ImGui_Spacing(ctx)
    r.ImGui_SetNextItemWidth(ctx, 150)
    local changed, val = r.ImGui_InputText(ctx, "##new_eq_name", new_eq_name)
    if changed then new_eq_name = val end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save Custom EQ") and new_eq_name ~= "" then
        local items = GetSelectedItems()
        if #items > 0 then
            local take = r.GetActiveTake(items[1])
            if take then
                for fx = 0, r.TakeFX_GetCount(take) - 1 do
                    local _, name = r.TakeFX_GetFXName(take, fx)
                    if name:lower():find("reaeq") then
                        local discovered = DiscoverReaEQBands(take, fx)
                        local bands = {}
                        for _, b in ipairs(discovered) do
                            local freq_val = 1000
                            local gain_val = 0
                            local bw_val = 1.0
                            if b.freq_idx then
                                local ok, fmt = r.TakeFX_GetFormattedParamValue(take, fx, b.freq_idx)
                                if ok then freq_val = tonumber(fmt:match("([%-+]?[%d%.]+)")) or 1000 end
                            end
                            if b.gain_idx then
                                local ok, fmt = r.TakeFX_GetFormattedParamValue(take, fx, b.gain_idx)
                                if ok then gain_val = tonumber(fmt:match("([%-+]?[%d%.]+)")) or 0 end
                            end
                            if b.bw_idx then
                                local ok, fmt = r.TakeFX_GetFormattedParamValue(take, fx, b.bw_idx)
                                if ok then bw_val = tonumber(fmt:match("([%-+]?[%d%.]+)")) or 1.0 end
                            end
                            if gain_val ~= 0 or b.type == "HP" or b.type == "LP" then
                                table.insert(bands, {type = b.type, freq = freq_val, gain = gain_val, bw = bw_val})
                            end
                        end
                        table.insert(custom_eq_presets, {name = new_eq_name, builtin = false, bands = bands})
                        new_eq_name = ""
                        SaveState()
                        log_msg = "Custom EQ preset saved"
                        break
                    end
                end
            end
        end
    end
    Tooltip("Enter name and click to save current item's EQ as custom preset")
end

local function DrawSurroundSection()
    if not r.ImGui_CollapsingHeader(ctx, "SURROUND PAN") then return end

    -- Output format row (show * if template captured)
    local w = r.ImGui_GetContentRegionAvail(ctx)
    local out_btn_w = math.max(50, (w - 8) / #SUR_OUTPUT_FORMATS)
    for i, fmt in ipairs(SUR_OUTPUT_FORMATS) do
        if i > 1 then r.ImGui_SameLine(ctx) end
        local is_sel = (sur_output_idx == i)
        local has_tpl = surpan_templates[fmt.name] ~= nil
        if is_sel then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.ORANGE)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.ORANGE_HOV)
        elseif has_tpl then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.TEAL)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.TEAL_HOV)
        end
        local label = has_tpl and (fmt.name .. "*") or fmt.name
        if r.ImGui_Button(ctx, label .. "##sur_out_" .. i, out_btn_w) then
            sur_output_idx = i
            SaveState()
        end
        if is_sel or has_tpl then r.ImGui_PopStyleColor(ctx, 2) end
        if has_tpl then Tooltip("Template captured") end
    end

    r.ImGui_Spacing(ctx)

    -- Action row + capture
    local btn_act_w = 55
    local sfx = "##act_SurPan"
    local has_config = sur_output_idx > 0
    local out_fmt = has_config and SUR_OUTPUT_FORMATS[sur_output_idx] or nil

    -- INSERT (needs output selection)
    if has_config then
        if TealButton("INSERT" .. sfx, btn_act_w) then
            ApplySurroundPreset(GetSelectedItems(), "INSERT", out_fmt)
        end
    else
        r.ImGui_BeginDisabled(ctx)
        r.ImGui_Button(ctx, "INSERT" .. sfx, btn_act_w)
        r.ImGui_EndDisabled(ctx)
    end
    r.ImGui_SameLine(ctx)

    -- DEL
    if RedButton("DEL" .. sfx, btn_act_w) then
        ApplySurroundPreset(GetSelectedItems(), "DEL")
    end
    r.ImGui_SameLine(ctx)

    -- SEL ONLY
    if r.ImGui_Button(ctx, "SEL ONLY" .. sfx, btn_act_w) then
        ApplySurroundPreset({}, "SEL_ONLY")
    end
    Tooltip("Select all items with SurroundPan FX")
    r.ImGui_SameLine(ctx)

    -- ON
    if r.ImGui_Button(ctx, "ON" .. sfx, btn_act_w) then
        ApplySurroundPreset(GetSelectedItems(), "ON")
    end
    r.ImGui_SameLine(ctx)

    -- OFF
    if r.ImGui_Button(ctx, "OFF" .. sfx, btn_act_w) then
        ApplySurroundPreset(GetSelectedItems(), "OFF")
    end
    r.ImGui_SameLine(ctx)

    -- CAPTURE
    if OrangeButton("CAPTURE" .. sfx, 65) then
        CaptureSurroundTemplate()
    end
    Tooltip("Capture SurroundPan state from selected item as template")
end

local function DrawFXPriority()
    if not r.ImGui_CollapsingHeader(ctx, "FX PRIORITY") then return end

    r.ImGui_TextDisabled(ctx, "Chain order (first = earliest in chain):")
    local priority_options = {"EQ", "SurPan", "Send", "Default"}
    for i = 1, 4 do
        r.ImGui_SetNextItemWidth(ctx, 80)
        if r.ImGui_BeginCombo(ctx, "##prio" .. i, fx_priority[i] or "---") then
            for _, opt in ipairs(priority_options) do
                if r.ImGui_Selectable(ctx, opt, fx_priority[i] == opt) then
                    fx_priority[i] = opt
                    SaveState()
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if i < 4 then r.ImGui_SameLine(ctx) end
    end
end

-- Track selection for read-back (only sync UI ← JSFX when selection changes)
local send_prev_sel_hash = ""

local function DrawSendGrid()
    -- Count selected items with/without SendRouter for feedback
    local sel_items = GetSelectedItems()
    local items_with_send = 0
    local first_send_take = nil   -- first selected take that has SendRouter
    local first_send_fx = -1
    for _, item in ipairs(sel_items) do
        local take = r.GetActiveTake(item)
        if take then
            local fx_idx = FindSendRouterOnTake(take)
            if fx_idx >= 0 then
                items_with_send = items_with_send + 1
                if not first_send_take then
                    first_send_take = take
                    first_send_fx = fx_idx
                end
            end
        end
    end

    -- Header with feedback indicator
    local header_label = "ITEM SENDS"
    if #sel_items > 0 and items_with_send > 0 then
        header_label = string.format("ITEM SENDS  [%d/%d]", items_with_send, #sel_items)
    end
    if not r.ImGui_CollapsingHeader(ctx, header_label) then return end

    -- Build selection hash to detect when user selects different items
    local sel_hash = tostring(#sel_items)
    for _, item in ipairs(sel_items) do
        sel_hash = sel_hash .. tostring(r.GetMediaItemInfo_Value(item, "IP_ITEMNUMBER"))
    end

    -- Read back JSFX values only when selection changes (avoids snap-back on slider release)
    if first_send_take and sel_hash ~= send_prev_sel_hash then
        send_prev_sel_hash = sel_hash
        for i = 1, NUM_SENDS do
            local _, val = r.TakeFX_GetParam(first_send_take, first_send_fx, i - 1)
            send_config.levels[i] = val
        end
    end
    if not first_send_take then
        send_prev_sel_hash = sel_hash  -- update hash even when no sends, so readback fires on next valid selection
    end

    -- Base channel selector
    r.ImGui_TextDisabled(ctx, "Main:")
    r.ImGui_SameLine(ctx)
    local base_opts = {"Stereo", "4.0", "5.1", "7.1"}
    local base_vals = {2, 4, 6, 8}
    for bi, bv in ipairs(base_vals) do
        if bi > 1 then r.ImGui_SameLine(ctx) end
        local is_sel = (send_config.base_ch == bv)
        if is_sel then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.TEAL)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.TEAL_HOV)
        end
        if r.ImGui_Button(ctx, base_opts[bi] .. "##send_base_" .. bi, 50) then
            send_config.base_ch = bv
            SaveState()
        end
        if is_sel then r.ImGui_PopStyleColor(ctx, 2) end
    end

    r.ImGui_Spacing(ctx)

    -- Send rows: checkbox + name input + volume slider (per-item per-bus JSFX control)
    for i = 1, NUM_SENDS do
        -- Enable checkbox
        local en_changed, en_val = r.ImGui_Checkbox(ctx, "##send_en_" .. i, send_config.enabled[i])
        if en_changed then
            send_config.enabled[i] = en_val
            SaveState()
        end
        r.ImGui_SameLine(ctx)

        -- Gray out name + slider when disabled
        if not send_config.enabled[i] then r.ImGui_BeginDisabled(ctx) end

        r.ImGui_SetNextItemWidth(ctx, 90)
        local name_changed, new_name = r.ImGui_InputTextWithHint(ctx,
            "##send_name_" .. i, "track name", send_config.names[i])
        if name_changed then
            send_config.names[i] = new_name
            SaveState()
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local fmt = send_config.levels[i] <= -60 and "-inf dB" or "%.1f dB"
        local vol_changed, new_vol = r.ImGui_SliderDouble(ctx, "##send_vol_" .. i, send_config.levels[i], -60, 12, fmt)
        if vol_changed then
            send_config.levels[i] = new_vol
            -- Real-time: update JSFX slider on all selected items immediately
            for _, item in ipairs(sel_items) do
                local take = r.GetActiveTake(item)
                if take then
                    local fx_idx = FindSendRouterOnTake(take)
                    if fx_idx >= 0 then
                        SetItemSendLevel(take, fx_idx, i, new_vol)
                    end
                end
            end
        end

        if not send_config.enabled[i] then r.ImGui_EndDisabled(ctx) end
    end

    r.ImGui_Spacing(ctx)
    if TealButton("Apply to Selected", 120) then
        ApplySendRouting(GetSelectedItems())
    end
    Tooltip("Add SendRouter JSFX + create track sends")
    r.ImGui_SameLine(ctx)
    if RedButton("Remove from Selected", 140) then
        RemoveSendRouting(GetSelectedItems())
    end
    Tooltip("Remove SendRouter JSFX + track sends")

    -- Warning
    if items_with_send > 0 then
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xD4753FFF)
        r.ImGui_TextWrapped(ctx, "! Do not move items with sends to other tracks — routing will break.")
        r.ImGui_PopStyleColor(ctx)
    end
end

local function DrawTagSelect()
    if not r.ImGui_CollapsingHeader(ctx, "TAG SELECT") then return end

    -- Tag track name input
    r.ImGui_TextDisabled(ctx, "Tag Track:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local tt_changed, tt_val = r.ImGui_InputTextWithHint(ctx, "##tag_track", "#Location", tag_track_name)
    if tt_changed then
        tag_track_name = tt_val
        tag_selected_idx = 0
        SaveState()
    end

    -- Scan tag track for items
    local tags = GetTagsFromTrack()

    if #tags == 0 then
        r.ImGui_TextDisabled(ctx, tag_track_name ~= "" and "No items on tag track" or "Enter tag track name")
    else
        -- Tag combo selector
        r.ImGui_TextDisabled(ctx, "Tag:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        if tag_selected_idx >= #tags then tag_selected_idx = 0 end
        local preview = tags[tag_selected_idx + 1] and tags[tag_selected_idx + 1].name or "---"
        if r.ImGui_BeginCombo(ctx, "##tag_combo", preview) then
            for i, tag in ipairs(tags) do
                local is_sel = (tag_selected_idx == i - 1)
                if r.ImGui_Selectable(ctx, tag.name .. "##tag_" .. i, is_sel) then
                    tag_selected_idx = i - 1
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        r.ImGui_Spacing(ctx)
        if TealButton("Select Items in Tag Range", 180) then
            SelectItemsByTag(tags[tag_selected_idx + 1])
        end
        Tooltip("Select all items (on other tracks) overlapping the selected tag's time range")
    end
end

local function DrawCloneToTagConfirmDialog()
    if clone_to_tag_pending then
        clone_to_tag_pending = false
        clone_to_tag_confirm_open = true
        r.ImGui_OpenPopupEx(ctx, "##clone_to_tag_confirm", r.ImGui_PopupFlags_ConfirmPopup())
    end

    if r.ImGui_BeginPopupModal(ctx, "Clone to Tag - Confirmation##clone_to_tag_confirm") then
        r.ImGui_TextWrapped(ctx, string.format("Clone FX to %d items in time range", clone_to_tag_count))

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        if clone_to_tag_sel_track_count > 0 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFBB00FF)
            r.ImGui_TextWrapped(ctx, string.format("⚠ Cloning applies only to %d selected track%s",
                clone_to_tag_sel_track_count,
                clone_to_tag_sel_track_count == 1 and "" or "s"))
            r.ImGui_PopStyleColor(ctx)
        else
            r.ImGui_TextDisabled(ctx, "ℹ All tracks will be included (none currently selected)")
        end

        r.ImGui_Spacing(ctx)

        -- Buttons
        local w = r.ImGui_GetContentRegionAvail(ctx)
        local btn_w = w / 2 - 3

        if r.ImGui_Button(ctx, "Cancel", btn_w) then
            clone_to_tag_confirm_open = false
            r.ImGui_CloseCurrentPopup(ctx)
        end

        r.ImGui_SameLine(ctx)

        if r.ImGui_Button(ctx, "Confirm Clone", btn_w) then
            CloneFXChain_Manual(clone_to_tag_items)
            clone_to_tag_confirm_open = false
            r.ImGui_CloseCurrentPopup(ctx)
            clone_to_tag_items = {}
            clone_to_tag_count = 0
        end

        r.ImGui_EndPopup(ctx)
    end
end

local function DrawCloneParamsToTagConfirmDialog()
    if clone_params_to_tag_pending then
        clone_params_to_tag_pending = false
        r.ImGui_OpenPopupEx(ctx, "##clone_params_to_tag_confirm", r.ImGui_PopupFlags_ConfirmPopup())
    end

    if r.ImGui_BeginPopupModal(ctx, "Clone Parameters to Tag - Confirmation##clone_params_to_tag_confirm") then
        r.ImGui_TextWrapped(ctx, string.format("Clone parameters to %d items in time range", clone_params_to_tag_count))

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        if clone_params_to_tag_sel_track_count > 0 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFBB00FF)
            r.ImGui_TextWrapped(ctx, string.format("⚠ Cloning applies only to %d selected track%s",
                clone_params_to_tag_sel_track_count,
                clone_params_to_tag_sel_track_count == 1 and "" or "s"))
            r.ImGui_PopStyleColor(ctx)
        else
            r.ImGui_TextDisabled(ctx, "ℹ All tracks will be included (none currently selected)")
        end

        r.ImGui_Spacing(ctx)

        -- Buttons
        local w = r.ImGui_GetContentRegionAvail(ctx)
        local btn_w = w / 2 - 3

        if r.ImGui_Button(ctx, "Cancel", btn_w) then
            r.ImGui_CloseCurrentPopup(ctx)
            clone_params_to_tag_items = {}
            clone_params_to_tag_count = 0
        end

        r.ImGui_SameLine(ctx)

        if r.ImGui_Button(ctx, "Confirm Clone", btn_w) then
            CloneItemParams(clone_params_to_tag_items)
            r.ImGui_CloseCurrentPopup(ctx)
            clone_params_to_tag_items = {}
            clone_params_to_tag_count = 0
        end

        r.ImGui_EndPopup(ctx)
    end
end

local function DrawItemParametersSection()
    if not r.ImGui_CollapsingHeader(ctx, "ITEM PARAMETERS") then return end

    -- Volume slider for selected items (real-time)
    local sel_items = GetSelectedItems()

    -- Read volume from first selected item if selection changed
    local sel_hash = tostring(#sel_items)
    for _, item in ipairs(sel_items) do
        sel_hash = sel_hash .. tostring(r.GetMediaItemInfo_Value(item, "IP_ITEMNUMBER"))
    end

    if sel_hash ~= item_params_prev_sel_hash and #sel_items > 0 then
        item_params_prev_sel_hash = sel_hash
        item_params_current_vol = r.GetMediaItemInfo_Value(sel_items[1], "D_VOL")
    end

    -- Volume control for selected items (real-time)
    r.ImGui_TextDisabled(ctx, "Item Volume:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local vol_db = item_params_current_vol > 0 and (math.log(item_params_current_vol) / math.log(10)) * 20 or -60
    local vol_changed, new_vol_db = r.ImGui_SliderDouble(ctx, "##item_vol", vol_db, -60, 12, "%.1f dB")
    if vol_changed then
        item_params_current_vol = 10 ^ (new_vol_db / 20)
        for _, item in ipairs(sel_items) do
            r.SetMediaItemInfo_Value(item, "D_VOL", item_params_current_vol)
        end
        r.UpdateArrange()
    end

    -- Right-click to reset volume to 0 dB
    if r.ImGui_IsItemClicked(ctx, 1) then
        item_params_current_vol = 1.0
        for _, item in ipairs(sel_items) do
            r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
        end
        r.UpdateArrange()
    end

    r.ImGui_Spacing(ctx)

    -- Capture & Clone buttons
    if OrangeButton("CAPTURE PARAMS", 110) then
        CaptureItemParams()
    end
    Tooltip("Capture parameters from first selected item")
    r.ImGui_SameLine(ctx)

    if TealButton("Clone Params", 95) then
        CloneItemParams(GetSelectedItems())
    end
    Tooltip("Apply captured parameters to selected items")
    r.ImGui_SameLine(ctx)

    if TealButton("Clone Params to Tag", 140) then
        local tags = GetTagsFromTrack()
        if #tags > 0 then
            local tag = tags[tag_selected_idx + 1]
            if tag then
                CloneItemParamsToTag(tag)
            else
                log_msg = "Select a tag first"
            end
        else
            log_msg = "No tags available"
        end
    end
    Tooltip("Apply parameters to items in selected tag")

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Parameter enable checkboxes - organized in 2 columns logically
    r.ImGui_TextDisabled(ctx, "Parameters to clone:")
    r.ImGui_Spacing(ctx)

    local w = r.ImGui_GetContentRegionAvail(ctx)
    local col_w = w / 2 - 4
    local col2_x = col_w + 8

    -- **Row 1: Basic** (Volume, Pan)
    local vol_en, vol_val = r.ImGui_Checkbox(ctx, "Volume##param_vol", item_params_enable.volume)
    if vol_en then item_params_enable.volume = vol_val; SaveState() end
    r.ImGui_SameLine(ctx, col2_x)
    local pan_en, pan_val = r.ImGui_Checkbox(ctx, "Pan##param_pan", item_params_enable.pan)
    if pan_en then item_params_enable.pan = pan_val; SaveState() end

    -- **Row 2: Pitch & Mode** (Pitch, Pitch Mode)
    local pitch_en, pitch_val = r.ImGui_Checkbox(ctx, "Pitch##param_pitch", item_params_enable.pitch)
    if pitch_en then item_params_enable.pitch = pitch_val; SaveState() end
    r.ImGui_SameLine(ctx, col2_x)
    local pitchmode_en, pitchmode_val = r.ImGui_Checkbox(ctx, "Pitch Mode##param_pitchmode", item_params_enable.pitch_mode)
    if pitchmode_en then item_params_enable.pitch_mode = pitchmode_val; SaveState() end

    -- **Row 3: Playback & Length** (Playback Rate, Length)
    local playrate_en, playrate_val = r.ImGui_Checkbox(ctx, "Playback Rate##param_playrate", item_params_enable.playrate)
    if playrate_en then item_params_enable.playrate = playrate_val; SaveState() end
    r.ImGui_SameLine(ctx, col2_x)
    local length_en, length_val = r.ImGui_Checkbox(ctx, "Length##param_length", item_params_enable.length)
    if length_en then item_params_enable.length = length_val; SaveState() end

    -- **Row 4: Fades** (Fade In, Fade Out)
    local fadein_en, fadein_val = r.ImGui_Checkbox(ctx, "Fade In##param_fadein", item_params_enable.fade_in)
    if fadein_en then item_params_enable.fade_in = fadein_val; SaveState() end
    r.ImGui_SameLine(ctx, col2_x)
    local fadeout_en, fadeout_val = r.ImGui_Checkbox(ctx, "Fade Out##param_fadeout", item_params_enable.fade_out)
    if fadeout_en then item_params_enable.fade_out = fadeout_val; SaveState() end

    -- **Row 5: Sync** (Item Phase)
    local itemphase_en, itemphase_val = r.ImGui_Checkbox(ctx, "Item Phase##param_itemphase", item_params_enable.item_phase)
    if itemphase_en then item_params_enable.item_phase = itemphase_val; SaveState() end
end

-- =========================================================
-- KEYBOARD SHORTCUTS
-- =========================================================
local function HandleKeyboard()
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_C()) and not r.ImGui_IsAnyItemActive(ctx) then
        CaptureSourceItem()
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_M()) and not r.ImGui_IsAnyItemActive(ctx) then
        CloneFXChain_Manual(GetSelectedItems())
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_L()) and not r.ImGui_IsAnyItemActive(ctx) then
        CloneFXChain_Linked(GetSelectedItems())
    end
    for k = 1, 9 do
        local key = r.ImGui_Key_1() + (k - 1)
        if r.ImGui_IsKeyPressed(ctx, key) and not r.ImGui_IsAnyItemActive(ctx) then
            if not r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
                if k <= #EQ_PRESETS then
                    selected_eq_preset = k
                    ApplyEQPreset(EQ_PRESETS[k], GetSelectedItems(), "INSERT")
                end
            end
        end
    end
end

-- =========================================================
-- MAIN LOOP
-- =========================================================
function Loop()
    r.ImGui_SetNextWindowSize(ctx, 550, 750, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowBgAlpha(ctx, 1.0)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.TITLE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.TITLE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), C.TITLE)

    local visible, open = r.ImGui_Begin(ctx, 'SBP ItemFX v0.9', true)
    if visible then
        PushTheme()

        HandleKeyboard()

        DrawStatusBar()
        r.ImGui_Separator(ctx)

        -- Top-level capture buttons (always visible)
        DrawCaptureButtons()

        -- Tag select first
        DrawTagSelect()

        -- Other sections
        DrawEQSection()
        DrawSurroundSection()
        DrawFXPriority()
        DrawSendGrid()
        DrawItemParametersSection()

        DrawCloneToTagConfirmDialog()
        DrawCloneParamsToTagConfirmDialog()

        PopTheme()
        r.ImGui_End(ctx)
    end

    r.ImGui_PopStyleColor(ctx, 3)

    SyncLinkedItems()

    if open then r.defer(Loop) else SaveState() end
end

-- =========================================================
-- INIT
-- =========================================================
LoadState()
Loop()
