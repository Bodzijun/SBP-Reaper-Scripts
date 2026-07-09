-- @description VO-tool
-- @author SBP & AI
-- @version 2.77
-- @about Multi-function tool for processing voiceover items in REAPER (Sorting, spacing, time control, fades, trimming, rate adjustment, and alignment). 
-- @link https://forum.cockos.com/showthread.php?t=301263
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   2.77 Major VO Tool update: consolidated workflow improvements across timeline/region handling, PRE-PROD chain processing, normalization accuracy, Restore Original recovery, and Auto-Level (Rider) development. Includes a redesigned and calibrated Rider engine with RMS/LUFS-style detection, robust gating, correct envelope-domain mapping (Track/Trim/Pre-FX/Take), multi-item reliability, and stable target lock behavior for consistent results (for example, -23 LUFS workflows) without cumulative gain drift.

local r = reaper
local ctx = r.ImGui_CreateContext('VO Tool v2.77')

local params = {
    rate = 1.0,
    lock_pitch = true,
    
    spacing_val = 0.0, 
    spacing_max = 3.0,
    spacing_use_groups = false,
    spacing_max_gap = 1.0,
    
    fade_in = 0.010,
    fade_out = 0.010,
    fade_in_shape = 0,
    fade_out_shape = 0,
    
    trim_start = 0.0,
    trim_end = 0.0,
    
    auto_regions = false,
    region_gap_threshold = 3.0,
    region_pad_start = 0.250,
    region_pad_end = 0.250,
    region_timeline_follow = false,
    
    region_reposition_gap = 1.0,

    autolevel_enabled = false,
    autolevel_target_db = -20.0,
    autolevel_detector_mode = 1,
    autolevel_window_ms = 350.0,
    autolevel_point_step_ms = 70.0,
    autolevel_tolerance_db = 1.5,
    autolevel_silence_db = -48.0,
    autolevel_lookahead_ms = 40.0,
    autolevel_attack_ms = 35.0,
    autolevel_release_ms = 220.0,
    autolevel_hold_ms = 100.0,
    autolevel_range_db = 8.0,
    autolevel_max_up_db = 6.0,
    autolevel_slew_dbps = 18.0,
    autolevel_gate_view = false,
    autolevel_gate_mark_db = 4.0,
    autolevel_gate_hold_ms = 180.0,
    autolevel_gate_close_ms = 140.0,
    autolevel_target_env = 1,
    autolevel_preset = 1,

    autosplit_enabled = false,
    autosplit_mode = 1,
    autosplit_threshold_db = -42.0,
    autosplit_min_silence_ms = 90.0,
    autosplit_min_cut_ms = 55.0,
    autosplit_min_keep_ms = 95.0,
    autosplit_pre_pad_ms = 35.0,
    autosplit_post_pad_ms = 35.0,
    autosplit_breath_policy = 1,
    autosplit_breath_aggr = 0.65,
    autosplit_window_ms = 40.0,
    autosplit_hop_ms = 10.0,

    preprod_chain_enabled = true,
    preprod_chain_preset = "",
    preprod_normalize_enabled = true,
    preprod_normalize_unit = 1,
    preprod_normalize_target = -3.0,
    preprod_normalize_mode = 1,
    preprod_wait_before_apply = 0.60,
    preprod_wait_before_bounce = 0.00,

    heal_gap = 1.0,
    heal_enabled = true,
    align_create_region = true,
    align_mode = 0,
    align_group_gap = 1.0,
    align_center_mode = 1,
    align_destination_mode = 0,
    align_sort_stacks = true
}

local PARAMS_KEY_ORDER = {
    "rate", "lock_pitch",
    "spacing_val", "spacing_max", "spacing_use_groups", "spacing_max_gap",
    "fade_in", "fade_out", "fade_in_shape", "fade_out_shape",
    "trim_start", "trim_end",
    "auto_regions", "region_gap_threshold", "region_pad_start", "region_pad_end", "region_timeline_follow",
    "region_reposition_gap",
    "autolevel_enabled", "autolevel_target_db", "autolevel_detector_mode", "autolevel_window_ms", "autolevel_point_step_ms", "autolevel_tolerance_db", "autolevel_silence_db",
    "autolevel_lookahead_ms", "autolevel_attack_ms", "autolevel_release_ms", "autolevel_hold_ms", "autolevel_range_db", "autolevel_max_up_db", "autolevel_slew_dbps", "autolevel_gate_view", "autolevel_gate_mark_db", "autolevel_gate_hold_ms", "autolevel_gate_close_ms", "autolevel_target_env", "autolevel_preset",
    "autosplit_enabled", "autosplit_mode", "autosplit_threshold_db", "autosplit_min_silence_ms",
    "autosplit_min_cut_ms", "autosplit_min_keep_ms", "autosplit_pre_pad_ms", "autosplit_post_pad_ms", "autosplit_breath_policy", "autosplit_breath_aggr", "autosplit_window_ms", "autosplit_hop_ms",
    "preprod_chain_enabled", "preprod_chain_preset", "preprod_normalize_enabled", "preprod_normalize_unit",
    "preprod_normalize_target", "preprod_normalize_mode", "preprod_wait_before_apply", "preprod_wait_before_bounce",
    "heal_gap", "heal_enabled",
    "align_create_region", "align_mode", "align_group_gap", "align_center_mode", "align_destination_mode", "align_sort_stacks"
}

local default_params = {}
for _, key in ipairs(PARAMS_KEY_ORDER) do
    default_params[key] = params[key]
end

local drag_state = {
    items_data = {},
    trim_start_base = 0.0,
    trim_end_base = 0.0
}

local EXT_SECTION = "SBP_VO_TOOL"
local EXT_PARAMS_KEY = "params_v210"
local last_saved_blob = ""
local last_region_jump_to = -1
local slider_prev_values = {}

local COLOR_BG_DARK     = 0x1A1A1AFF
local COLOR_BG_LIGHTER  = 0x252525FF
local COLOR_ACCENT      = 0x2D8C6DFF
local COLOR_ACCENT_LITE = 0x2A7A5FFF
local COLOR_HEADER      = 0xFF8C6DFF
local COLOR_TEXT        = 0xE0E0E0FF
local COLOR_TEXT_DIM    = 0x808080FF

local header_font = nil
local UpdateRegions
local SaveItemsState
local RecoverItemByGUID
local last_hotkey_down = false
local last_play_pos = -1
local last_region_enum_idx = nil
local last_region_jump_at = 0.0
local REGION_JUMP_EPS = 0.10
local REGION_JUMP_COOLDOWN = 0.20
local PREPROD_CHAIN_SUBFOLDER = "VO"
local PREPROD_GLUE_CMD_ID = 41588
local preprod_chain_cache = {}
local preprod_job = nil
local preprod_restore_popup = nil
local autosplit_preview_regions = {}
local autosplit_preview_segments = {}
local autosplit_last_stats = { items = 0, segments = 0, breaths_filtered = 0, fricative_filtered = 0, keep_merged = 0 }
local AUTOSPLIT_PREVIEW_PREFIX = "[VO Split Preview]"

local NORMALIZE_UNIT_OPTIONS = {
    { label = "Peak", api_value = 2 },
    { label = "RMS-I", api_value = 1 },
    { label = "LUFS-I", api_value = 0 }
}

local NORMALIZE_MODE_OPTIONS = {
    { label = "All items", key = "all" },
    { label = "Only quiet", key = "quiet_only" },
    { label = "Only loud", key = "loud_only" },
    { label = "Match selected avg", key = "average_selected" }
}

local AUTOSPLIT_MODE_OPTIONS = {
    { label = "Preview only", key = "preview" },
    { label = "Split only", key = "split_only" },
    { label = "Split + delete silence", key = "split_delete" }
}

local AUTOSPLIT_BREATH_POLICY_OPTIONS = {
    { label = "Treat breaths as silence/noise", key = "remove_breaths" },
    { label = "Balanced", key = "balanced" },
    { label = "Keep natural breaths", key = "keep_breaths" }
}

local AUTOLEVEL_DETECTOR_OPTIONS = {
    { label = "RMS", key = "rms" },
    { label = "LUFS-style", key = "lufs_style" }
}

local AUTOLEVEL_TARGET_OPTIONS = {
    { label = "Track Volume", key = "track_vol" },
    { label = "Trim Volume", key = "trim_vol" },
    { label = "Pre-FX Volume", key = "prefx_vol" },
    { label = "Take Volume", key = "take_vol" }
}

local AUTOLEVEL_PRESET_OPTIONS = {
    { label = "Manual", key = "manual" },
    { label = "Smooth Voice", key = "smooth" },
    { label = "Gentle Longform", key = "longform" }
}

local function SerializeParams()
    local chunks = {}
    for _, key in ipairs(PARAMS_KEY_ORDER) do
        local value = params[key]
        local kind = type(value)
        if kind == "boolean" then
            chunks[#chunks + 1] = key .. "=b:" .. (value and "1" or "0")
        elseif kind == "number" then
            chunks[#chunks + 1] = key .. "=n:" .. string.format("%.10f", value)
        else
            chunks[#chunks + 1] = key .. "=s:" .. tostring(value)
        end
    end
    return table.concat(chunks, "|")
end

local function DeserializeParams(blob)
    if not blob or blob == "" then return end
    for token in string.gmatch(blob, "[^|]+") do
        local key, packed = token:match("^([^=]+)=([bns]:.*)$")
        if key and packed and params[key] ~= nil then
            local kind = packed:sub(1, 1)
            local raw = packed:sub(3)
            if kind == "b" then
                params[key] = (raw == "1")
            elseif kind == "n" then
                local n = tonumber(raw)
                if n ~= nil then params[key] = n end
            else
                params[key] = raw
            end
        end
    end
end

local function LoadParams()
    local blob = r.GetExtState(EXT_SECTION, EXT_PARAMS_KEY)
    if blob and blob ~= "" then
        DeserializeParams(blob)
    end
    last_saved_blob = SerializeParams()
end

local function SaveParamsIfChanged(force)
    local blob = SerializeParams()
    if force or blob ~= last_saved_blob then
        r.SetExtState(EXT_SECTION, EXT_PARAMS_KEY, blob, true)
        last_saved_blob = blob
    end
end

local function RememberSliderPrevValue(param_key)
    if param_key and params[param_key] ~= nil then
        slider_prev_values[param_key] = params[param_key]
    end
end

local function ApplySliderRightClickReset(param_key, apply_func, undo_name, should_update_regions, use_prev_value)
    if not r.ImGui_IsItemHovered(ctx) then return false end
    if not r.ImGui_IsMouseClicked(ctx, 1) then return false end

    local default_value = default_params[param_key]
    if default_value == nil then return false end

    local reset_value = default_value
    if use_prev_value and slider_prev_values[param_key] ~= nil then
        reset_value = slider_prev_values[param_key]
    end

    if params[param_key] == reset_value then return false end

    if apply_func then
        r.Undo_BeginBlock()
        SaveItemsState()
        params[param_key] = reset_value
        apply_func()
        if should_update_regions and params.auto_regions then
            UpdateRegions(false)
        end
        r.Undo_EndBlock(undo_name or ("Reset " .. param_key), -1)
    else
        params[param_key] = reset_value
    end
    return true
end

local function GetAllRegions()
    local regions = {}
    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = (num_markers or 0) + (num_regions or 0)

    for enum_idx = 0, total - 1 do
        local retval, isrgn, pos, rgnend, name, idx, color
        if r.EnumProjectMarkers3 then
            retval, isrgn, pos, rgnend, name, idx, color = r.EnumProjectMarkers3(0, enum_idx)
        else
            retval, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers(enum_idx)
            color = 0
        end

        if retval and isrgn then
            regions[#regions + 1] = {
                enum_idx = enum_idx,
                idx = idx,
                s = pos,
                e = rgnend,
                name = name or "",
                color = color or 0
            }
        end
    end

    return regions
end

local function FindCurrentAndNextRegionAtTime(time_pos)
    local regions = GetAllRegions()
    if #regions == 0 then return nil, nil end

    table.sort(regions, function(a, b) return a.s < b.s end)

    local current, next_region = nil, nil
    for i = 1, #regions do
        local rg = regions[i]
        if time_pos >= rg.s and time_pos < rg.e then
            current = rg
            next_region = regions[i + 1]
            break
        end
    end
    return current, next_region
end

local function HandleRegionTimelinePlayback()
    if not params.region_timeline_follow then
        last_region_jump_to = -1
        return
    end

    if (r.GetPlayState() & 1) == 0 then
        last_region_jump_to = -1
        return
    end

    local play_pos = r.GetPlayPosition()
    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = (num_markers or 0) + (num_regions or 0)
    if total <= 0 then return end

    local current_rgn_end = nil
    local next_rgn_start = nil

    for i = 0, total - 1 do
        local retval, isrgn, pos, rgnend
        if r.EnumProjectMarkers3 then
            retval, isrgn, pos, rgnend = r.EnumProjectMarkers3(0, i)
        else
            retval, isrgn, pos, rgnend = r.EnumProjectMarkers(i)
        end

        if retval and isrgn and play_pos >= pos and play_pos < rgnend then
            current_rgn_end = rgnend

            for j = i + 1, total - 1 do
                local retval2, isrgn2, pos2
                if r.EnumProjectMarkers3 then
                    retval2, isrgn2, pos2 = r.EnumProjectMarkers3(0, j)
                else
                    retval2, isrgn2, pos2 = r.EnumProjectMarkers(j)
                end
                if retval2 and isrgn2 then
                    next_rgn_start = pos2
                    break
                end
            end
            break
        end
    end

    if not current_rgn_end or not next_rgn_start then return end
    if play_pos < (current_rgn_end - REGION_JUMP_EPS) then return end

    local now = r.time_precise and r.time_precise() or 0
    if math.abs(next_rgn_start - last_region_jump_to) < 0.0001 and (now - last_region_jump_at) < REGION_JUMP_COOLDOWN then
        return
    end

    r.SetEditCurPos2(0, next_rgn_start, true, true)
    last_region_jump_to = next_rgn_start
    last_region_jump_at = now
end

local function IsShiftQPressed()
    local pressed = false

    if r.ImGui_IsWindowFocused(ctx) and r.ImGui_Shortcut and r.ImGui_Key_Q and r.ImGui_Mod_Shift then
        pressed = r.ImGui_Shortcut(ctx, r.ImGui_Mod_Shift() | r.ImGui_Key_Q())
    elseif r.ImGui_IsWindowFocused(ctx) and r.ImGui_IsKeyPressed and r.ImGui_Key_Q and r.ImGui_GetKeyMods and r.ImGui_Mod_Shift then
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Q(), false) then
            local mods = r.ImGui_GetKeyMods(ctx)
            pressed = (mods & r.ImGui_Mod_Shift()) ~= 0
        end
    elseif r.ImGui_IsWindowFocused(ctx) and r.ImGui_IsKeyDown and r.ImGui_Key_Q and r.ImGui_GetKeyMods and r.ImGui_Mod_Shift then
        local mods = r.ImGui_GetKeyMods(ctx)
        local shift_down = (mods & r.ImGui_Mod_Shift()) ~= 0
        local q_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_Q())
        local now_down = shift_down and q_down
        pressed = now_down and not last_hotkey_down
        last_hotkey_down = now_down
        return pressed
    elseif r.JS_VKeys_GetState then
        local state = r.JS_VKeys_GetState(0)
        if state and #state >= 81 then
            local shift_down = state:byte(16) ~= 0
            local q_down = state:byte(81) ~= 0
            local now_down = shift_down and q_down
            pressed = now_down and not last_hotkey_down
            last_hotkey_down = now_down
            return pressed
        end
    end

    if not pressed then
        last_hotkey_down = false
        return false
    end

    last_hotkey_down = true
    return true
end

local function GetNonLinearSpacing(slider_val, max_sec)
    return (slider_val ^ 2) * max_sec
end

local function BuildVoChainFolderPath()
    local base = r.GetResourcePath() or ""
    if base == "" then return "" end
    return base .. "/FXChains/" .. PREPROD_CHAIN_SUBFOLDER
end

local function NormalizeSlashes(s)
    if not s then return "" end
    return (tostring(s):gsub("\\", "/"))
end

local function EnumerateVoChainFilesRecursive(root, rel_prefix)
    local files = {}
    local rel = rel_prefix or ""

    if r.EnumerateFiles then
        r.EnumerateFiles(root, -1)
        local fi = 0
        while true do
            local fname = r.EnumerateFiles(root, fi)
            if not fname then break end
            if fname:lower():sub(-9) == ".rfxchain" then
                local rel_file = rel .. fname
                files[#files + 1] = rel_file
            end
            fi = fi + 1
        end
    end

    if r.EnumerateSubdirectories then
        r.EnumerateSubdirectories(root, -1)
        local si = 0
        while true do
            local sub = r.EnumerateSubdirectories(root, si)
            if not sub then break end
            local sub_root = root .. "/" .. sub
            local sub_rel = rel .. sub .. "/"
            local nested = EnumerateVoChainFilesRecursive(sub_root, sub_rel)
            for _, rel_file in ipairs(nested) do
                files[#files + 1] = rel_file
            end
            si = si + 1
        end
    end

    return files
end

local function RefreshPreProdChainCache()
    local folder = BuildVoChainFolderPath()
    preprod_chain_cache = {}
    if folder == "" then return preprod_chain_cache end

    local rel_files = EnumerateVoChainFilesRecursive(folder, "")
    for _, rel_file_raw in ipairs(rel_files) do
        local rel_file = NormalizeSlashes(rel_file_raw)
        local rel_no_ext = rel_file:sub(1, -10)
        preprod_chain_cache[#preprod_chain_cache + 1] = {
            name = rel_no_ext,
            rel_file = rel_file,
            rel_no_ext = rel_no_ext,
            file = rel_file,
            path = folder .. "/" .. rel_file
        }
    end

    table.sort(preprod_chain_cache, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    return preprod_chain_cache
end

local function EnsurePreProdChainSelection()
    if #preprod_chain_cache == 0 then
        params.preprod_chain_preset = ""
        return
    end

    if params.preprod_chain_preset and params.preprod_chain_preset ~= "" then
        for _, entry in ipairs(preprod_chain_cache) do
            if entry.name == params.preprod_chain_preset then
                return
            end
        end
    end

    params.preprod_chain_preset = preprod_chain_cache[1].name
end

local function GetSelectedPreProdChain()
    for _, entry in ipairs(preprod_chain_cache) do
        if entry.name == params.preprod_chain_preset then
            return entry
        end
    end
    return nil
end

local function ClampOptionIndex(value, options)
    local idx = math.floor((value or 1) + 0.5)
    if idx < 1 then idx = 1 end
    if idx > #options then idx = #options end
    return idx
end

local function GetSelectedNormalizeUnit()
    local idx = ClampOptionIndex(params.preprod_normalize_unit, NORMALIZE_UNIT_OPTIONS)
    params.preprod_normalize_unit = idx
    return NORMALIZE_UNIT_OPTIONS[idx], idx
end

local function GetSelectedNormalizeMode()
    local idx = ClampOptionIndex(params.preprod_normalize_mode, NORMALIZE_MODE_OPTIONS)
    params.preprod_normalize_mode = idx
    return NORMALIZE_MODE_OPTIONS[idx], idx
end

local function GetSelectedAutoSplitMode()
    local idx = ClampOptionIndex(params.autosplit_mode, AUTOSPLIT_MODE_OPTIONS)
    params.autosplit_mode = idx
    return AUTOSPLIT_MODE_OPTIONS[idx], idx
end

local function GetSelectedAutoSplitBreathPolicy()
    local idx = ClampOptionIndex(params.autosplit_breath_policy, AUTOSPLIT_BREATH_POLICY_OPTIONS)
    params.autosplit_breath_policy = idx
    return AUTOSPLIT_BREATH_POLICY_OPTIONS[idx], idx
end

local function GetSelectedAutoLevelDetector()
    local idx = ClampOptionIndex(params.autolevel_detector_mode, AUTOLEVEL_DETECTOR_OPTIONS)
    params.autolevel_detector_mode = idx
    return AUTOLEVEL_DETECTOR_OPTIONS[idx], idx
end

local function GetSelectedAutoLevelTarget()
    local idx = ClampOptionIndex(params.autolevel_target_env, AUTOLEVEL_TARGET_OPTIONS)
    params.autolevel_target_env = idx
    return AUTOLEVEL_TARGET_OPTIONS[idx], idx
end

local function GetSelectedAutoLevelPreset()
    local idx = ClampOptionIndex(params.autolevel_preset, AUTOLEVEL_PRESET_OPTIONS)
    params.autolevel_preset = idx
    return AUTOLEVEL_PRESET_OPTIONS[idx], idx
end

local function ApplyAutoLevelPresetByIndex(idx)
    local preset = AUTOLEVEL_PRESET_OPTIONS[idx]
    if not preset then return end

    if preset.key == "smooth" then
        -- Smooth Voice is tuned for LUFS meter parity and stable narration leveling.
        params.autolevel_detector_mode = 2 -- LUFS-style
        params.autolevel_window_ms = 300.0
        params.autolevel_point_step_ms = 80.0
        params.autolevel_tolerance_db = 1.0
        params.autolevel_silence_db = -48.0
        params.autolevel_lookahead_ms = 20.0
        params.autolevel_attack_ms = 120.0
        params.autolevel_release_ms = 600.0
        params.autolevel_hold_ms = 220.0
        params.autolevel_range_db = 12.0
        params.autolevel_max_up_db = 8.0
        params.autolevel_slew_dbps = 12.0
        params.autolevel_gate_view = false
        params.autolevel_gate_mark_db = 4.0
        params.autolevel_gate_hold_ms = 180.0
        params.autolevel_gate_close_ms = 140.0
    elseif preset.key == "longform" then
        params.autolevel_detector_mode = 2 -- LUFS-style
        params.autolevel_window_ms = 400.0
        params.autolevel_point_step_ms = 120.0
        params.autolevel_tolerance_db = 1.6
        params.autolevel_silence_db = -48.0
        params.autolevel_lookahead_ms = 20.0
        params.autolevel_attack_ms = 160.0
        params.autolevel_release_ms = 800.0
        params.autolevel_hold_ms = 260.0
        params.autolevel_range_db = 9.0
        params.autolevel_max_up_db = 6.0
        params.autolevel_slew_dbps = 9.0
        params.autolevel_gate_view = false
        params.autolevel_gate_mark_db = 4.0
        params.autolevel_gate_hold_ms = 220.0
        params.autolevel_gate_close_ms = 180.0
    end

    params.autolevel_preset = idx
end

local function DbToAmp(db)
    return 10 ^ ((db or 0.0) / 20.0)
end

local function AmpToDb(amp)
    if not amp or amp <= 0 then return -120.0 end
    return 20.0 * math.log(amp) / math.log(10)
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function FindTrackEnvelopeByCandidates(track, candidates)
    if not track then return nil end
    for _, name in ipairs(candidates) do
        local env = r.GetTrackEnvelopeByName(track, name)
        if env then return env end
    end
    return nil
end

local function FindTrackEnvelopeByChunkCandidates(track, chunks)
    if not track or not r.GetTrackEnvelopeByChunkName then return nil end
    for _, chunk_name in ipairs(chunks) do
        local env = r.GetTrackEnvelopeByChunkName(track, chunk_name)
        if env then return env end
    end
    return nil
end

-- Built-in track envelope configuration-chunk keys (language-independent).
-- VOLENV = Volume (Pre-FX), VOLENV2 = Volume, VOLENV3 = Trim Volume.
local AUTOLEVEL_TARGET_CHUNK_KEY = {
    track_vol = "VOLENV2",
    trim_vol  = "VOLENV3",
    prefx_vol = "VOLENV",
}

-- Create a built-in track envelope by inserting its config block into the track chunk if missing.
local function EnsureTrackEnvelopeByChunkKey(track, key)
    if not track or not key then return nil end
    local existing = r.GetTrackEnvelopeByChunkName(track, "<" .. key)
    if existing then return existing end
    if not r.GetTrackStateChunk or not r.SetTrackStateChunk then return nil end
    local ok, chunk = r.GetTrackStateChunk(track, "", false)
    if not ok or not chunk then return nil end

    -- Insert the envelope block just before the final '>' that closes the TRACK block.
    local pos = nil
    for i = #chunk, 1, -1 do
        if chunk:sub(i, i) == ">" then pos = i break end
    end
    if not pos then return nil end

    local env_block = "<" .. key .. "\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 1\nDEFSHAPE 0 -1 -1\n>\n"
    local new_chunk = chunk:sub(1, pos - 1) .. env_block .. chunk:sub(pos)
    if r.SetTrackStateChunk(track, new_chunk, false) then
        return r.GetTrackEnvelopeByChunkName(track, "<" .. key)
    end
    return nil
end

-- Create the active take volume envelope if missing, preserving the current item selection.
local function EnsureTakeVolumeEnvelope(item, take)
    if not item or not take then return nil end
    local env = r.GetTakeEnvelopeByName(take, "Volume")
    if env then return env end

    local prev_sel = {}
    local cnt = r.CountSelectedMediaItems(0)
    for i = 0, cnt - 1 do prev_sel[#prev_sel + 1] = r.GetSelectedMediaItem(0, i) end

    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    if r.SetActiveTake then r.SetActiveTake(take) end
    r.Main_OnCommand(40693, 0) -- Take: Toggle take volume envelope

    r.SelectAllMediaItems(0, false)
    for _, it in ipairs(prev_sel) do
        if it then r.SetMediaItemSelected(it, true) end
    end

    return r.GetTakeEnvelopeByName(take, "Volume")
end

local function ResolveAutoLevelEnvelope(item, take, target_opt, allow_create)
    if not item or not take or not target_opt then return nil, nil, "missing_item" end
    local track = r.GetMediaItemTrack(item)
    if not track then return nil, nil, "missing_track" end

    local key = target_opt.key
    if key == "take_vol" then
        local env = r.GetTakeEnvelopeByName(take, "Volume")
        if not env and allow_create then
            env = EnsureTakeVolumeEnvelope(item, take)
        end
        local baseline = math.abs(r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0)
        return env, baseline, env and nil or "take_volume_envelope_missing"
    end

    local chunk_key = AUTOLEVEL_TARGET_CHUNK_KEY[key]
    if not chunk_key then return nil, nil, "unknown_target" end

    local env = r.GetTrackEnvelopeByChunkName(track, "<" .. chunk_key)
    if not env and allow_create then
        env = EnsureTrackEnvelopeByChunkKey(track, chunk_key)
    end

    local baseline = 1.0
    if key == "track_vol" then
        baseline = math.abs(r.GetMediaTrackInfo_Value(track, "D_VOL") or 1.0)
    end
    return env, baseline, env and nil or (key .. "_envelope_missing")
end

local function BuildAutoLevelContexts(target_opt, allow_create)
    local contexts = {}
    -- Snapshot selected items first: creating envelopes may temporarily change item selection.
    local items = {}
    local sel_count = r.CountSelectedMediaItems(0)
    for i = 0, sel_count - 1 do
        items[#items + 1] = r.GetSelectedMediaItem(0, i)
    end
    for _, item in ipairs(items) do
        local take = item and r.GetActiveTake(item) or nil
        if item and take and (not r.TakeIsMIDI or not r.TakeIsMIDI(take)) then
            local env, baseline, err = ResolveAutoLevelEnvelope(item, take, target_opt, allow_create)
            if env and baseline then
                local key = tostring(env)
                local ctx_entry = contexts[key]
                if not ctx_entry then
                    ctx_entry = {
                        env = env,
                        target_key = target_opt.key,
                        baseline = baseline,
                        points = {},
                        spans = {},
                        scale_mode = r.GetEnvelopeScalingMode(env) or 0
                    }
                    contexts[key] = ctx_entry
                end
                ctx_entry.spans[#ctx_entry.spans + 1] = {
                    item = item,
                    take = take,
                    start_t = r.GetMediaItemInfo_Value(item, "D_POSITION"),
                    end_t = r.GetMediaItemInfo_Value(item, "D_POSITION") + r.GetMediaItemInfo_Value(item, "D_LENGTH")
                }
            else
                r.ShowConsoleMsg("[VO Tool] Auto-Level: skipped item (" .. tostring(err) .. ")\n")
            end
        end
    end
    return contexts
end

local function CollectAutoLevelPointsForSpan(ctx_entry, span, detector_opt)
    local out_points = {}
    local take = span.take
    local accessor = r.CreateTakeAudioAccessor(take)
    if not accessor then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: failed to create audio accessor\n")
        return out_points
    end

    local scan_start = span.start_t
    local scan_end = span.end_t
    local acc_start = r.GetAudioAccessorStartTime(accessor)
    local acc_end = r.GetAudioAccessorEndTime(accessor)
    if scan_end <= scan_start then
        r.DestroyAudioAccessor(accessor)
        return out_points
    end

    local src = r.GetMediaItemTake_Source(take)
    local num_channels = math.max(1, math.min(8, r.GetMediaSourceNumChannels(src) or 1))
    local sample_rate = 16000
    local window_sec = math.max(0.05, (tonumber(params.autolevel_window_ms) or 1200.0) / 1000.0)
    local point_step_sec = math.max(0.01, (tonumber(params.autolevel_point_step_ms) or 70.0) / 1000.0)
    -- Momentary loudness block: capped so the rider follows material instead of collapsing to a flat line.
    local analysis_window_sec = math.max(0.10, math.min(0.40, window_sec))
    local analysis_hop_sec = math.max(0.01, math.min(0.03, analysis_window_sec * 0.10))
    local hop_sec = analysis_hop_sec
    local lookahead_sec = math.max(0.0, (tonumber(params.autolevel_lookahead_ms) or 40.0) / 1000.0)
    local attack_sec = math.max(0.005, (tonumber(params.autolevel_attack_ms) or 35.0) / 1000.0)
    local release_sec = math.max(0.005, (tonumber(params.autolevel_release_ms) or 220.0) / 1000.0)
    local hold_sec = math.max(0.0, (tonumber(params.autolevel_hold_ms) or 100.0) / 1000.0)
    local tol_db = math.max(0.0, tonumber(params.autolevel_tolerance_db) or 1.5)
    local silence_db = tonumber(params.autolevel_silence_db) or -48.0
    local range_db = math.max(0.5, tonumber(params.autolevel_range_db) or 8.0)
    local up_range_db = math.max(0.3, math.min(range_db, tonumber(params.autolevel_max_up_db) or 2.0))
    local slew_dbps = math.max(2.0, tonumber(params.autolevel_slew_dbps) or 18.0)
    local target_db = tonumber(params.autolevel_target_db) or -20.0
    local baseline_db = AmpToDb(math.max(0.000001, ctx_entry.baseline or 1.0))
    local gate_view_on = params.autolevel_gate_view and (detector_opt.key == "lufs_style")
    local gate_mark_db = math.max(0.5, tonumber(params.autolevel_gate_mark_db) or 4.0)

    if not r.new_array then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: reaper.new_array unavailable\n")
        r.DestroyAudioAccessor(accessor)
        return out_points
    end

    local samples_per_window = math.max(1, math.floor(sample_rate * analysis_window_sec + 0.5))
    local buf_count = samples_per_window * num_channels
    local sample_buffer = r.new_array(buf_count)

    local frame_times = {}
    local measured_frames = {}
    local measured_ctrl = {}
    local rms_frames = {}
    local raw_corrections = {}
    local gate_flags = {}
    local t = scan_start
    local item_loopsrc = (r.GetMediaItemInfo_Value(span.item, "B_LOOPSRC") or 0) > 0.5
    local acc_len = math.max(0.0, acc_end - acc_start)
    -- Take accessor time can differ from item timeline; map span time to accessor domain.
    local acc_time_offset = acc_start - scan_start
    local hold_frames = math.max(0, math.floor(hold_sec / hop_sec + 0.5))
    local hold_left = 0
    local prev_desired = 0.0
    local integ_db = nil
    local lufs_alpha = math.exp(-hop_sec / 0.40)
    local ctrl_db = nil
    local ctrl_tau = 0.65
    local ctrl_alpha = math.exp(-hop_sec / ctrl_tau)
    local speech_floor_db = silence_db + 3.0
    local speech_hang_frames = math.max(0, math.floor(0.06 / hop_sec + 0.5))
    local speech_hang_left = 0
    local speech_flags = {}
    local ebu_rel_lu = 10.0
    local gate_hold_frames = math.max(1, math.floor((math.max(20.0, tonumber(params.autolevel_gate_hold_ms) or 180.0) / 1000.0) / hop_sec + 0.5))
    local gate_close_confirm_frames = math.max(1, math.floor((math.max(20.0, tonumber(params.autolevel_gate_close_ms) or 140.0) / 1000.0) / hop_sec + 0.5))
    local gate_open_hys_db = 0.6
    local gate_close_hys_db = 0.8

    while t < scan_end do
        local ret = 0
        local read_t = t + acc_time_offset
        if read_t < acc_start or read_t >= acc_end then
            if item_loopsrc and acc_len > 0.000001 then
                local rel = (read_t - acc_start) % acc_len
                if rel < 0 then rel = rel + acc_len end
                read_t = acc_start + rel
            end
        end
        if read_t >= acc_start and read_t < acc_end then
            ret = r.GetAudioAccessorSamples(accessor, sample_rate, num_channels, read_t, samples_per_window, sample_buffer)
            if ret < 0 then
                r.ShowConsoleMsg("[VO Tool] Auto-Level: accessor read error\n")
                break
            end
        end

        local sum_sq = 0.0
        local n = 0
        if ret > 0 then
            for i = 1, buf_count do
                local v = sample_buffer[i] or 0.0
                sum_sq = sum_sq + (v * v)
                n = n + 1
            end
        end

        local rms = (n > 0) and math.sqrt(sum_sq / n) or 0.0
        local rms_db = AmpToDb(rms)
        if integ_db == nil then integ_db = rms_db end
        integ_db = lufs_alpha * integ_db + (1.0 - lufs_alpha) * rms_db
        local measured_db = (detector_opt.key == "lufs_style") and integ_db or rms_db
        if ctrl_db == nil then ctrl_db = measured_db end
        ctrl_db = ctrl_alpha * ctrl_db + (1.0 - ctrl_alpha) * measured_db

        if rms_db > speech_floor_db then
            speech_hang_left = speech_hang_frames
        else
            speech_hang_left = math.max(0, speech_hang_left - 1)
        end
        local speech_active = speech_hang_left > 0

        frame_times[#frame_times + 1] = t
        measured_frames[#measured_frames + 1] = measured_db
        measured_ctrl[#measured_ctrl + 1] = ctrl_db
        rms_frames[#rms_frames + 1] = rms_db
        speech_flags[#speech_flags + 1] = speech_active
        t = t + hop_sec
    end

    local nframes = #frame_times
    if nframes == 0 then
        r.DestroyAudioAccessor(accessor)
        return out_points
    end

    -- Absolute silence gate: closes ONLY when momentary loudness drops to the Silence floor (real pauses),
    -- so it never triggers mid-sentence where speech level stays well above silence.
    if detector_opt.key == "lufs_style" then
        local open_thr = silence_db + math.max(3.0, gate_open_hys_db * 6.0)   -- must clearly exceed silence to open
        local close_thr = silence_db + gate_close_hys_db                       -- close only when near silence
        if open_thr <= close_thr + 1.0 then open_thr = close_thr + 4.0 end

        local gate_state = false
        local gate_hold_left = 0
        local gate_close_acc = 0
        for i = 1, nframes do
            local db = rms_frames[i] or -120.0
            if not gate_state then
                if db >= open_thr then
                    gate_state = true
                    gate_hold_left = gate_hold_frames
                    gate_close_acc = 0
                end
            else
                if db >= open_thr then
                    -- Still clearly speech: keep open and refresh hold.
                    gate_hold_left = gate_hold_frames
                    gate_close_acc = 0
                elseif gate_hold_left > 0 then
                    -- Hold window after last speech peak; ignore brief dips.
                    gate_hold_left = gate_hold_left - 1
                    gate_close_acc = 0
                elseif db <= close_thr then
                    gate_close_acc = gate_close_acc + 1
                    if gate_close_acc >= gate_close_confirm_frames then
                        gate_state = false
                        gate_close_acc = 0
                    end
                else
                    gate_close_acc = 0
                end
            end
            gate_flags[i] = gate_state
        end
    else
        for i = 1, nframes do
            gate_flags[i] = (rms_frames[i] or -120.0) > (silence_db + 2.0)
        end
    end

    -- Destination-domain absolute level per frame (measured voice loudness + envelope baseline gain).
    local level_db = {}
    for i = 1, nframes do
        level_db[i] = (measured_frames[i] or -120.0) + baseline_db
    end

    -- Average voiced loudness (energy mean over gated frames) used for ride deviation centering.
    local sum_lin = 0.0
    local n_voiced = 0
    for i = 1, nframes do
        if gate_flags[i] then
            sum_lin = sum_lin + 10 ^ (level_db[i] / 10.0)
            n_voiced = n_voiced + 1
        end
    end
    local avg_level_db = target_db
    if n_voiced > 0 and sum_lin > 0.0 then
        avg_level_db = 10.0 * math.log(sum_lin / n_voiced) / math.log(10)
    end

    -- STATIC gain anchor from REAPER native normalization (same engine used for actual loudness targeting).
    -- This removes persistent real-meter offsets between internal detector estimates and measured output.
    local static_gain_db = nil
    if r.CalculateNormalization then
        local source = r.GetMediaItemTake_Source(take)
        if source then
            local unit_api_value = (detector_opt.key == "lufs_style") and 0 or 1 -- LUFS-I / RMS-I
            local target_linear = r.CalculateNormalization(source, unit_api_value, target_db, 0, 0)
            if type(target_linear) == "number" and target_linear > 0 then
                -- For track-domain targets, compensate fixed pre-envelope gains (item/take volume)
                -- so native source normalization maps correctly into the chosen envelope domain.
                local pre_env_fixed_db = 0.0
                if ctx_entry.target_key ~= "take_vol" then
                    local item_vol = math.abs(r.GetMediaItemInfo_Value(span.item, "D_VOL") or 1.0)
                    local take_vol = math.abs(r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0)
                    pre_env_fixed_db = AmpToDb(math.max(0.000001, item_vol)) + AmpToDb(math.max(0.000001, take_vol))
                end
                static_gain_db = AmpToDb(target_linear) - pre_env_fixed_db - baseline_db
            end
        end
    end
    if static_gain_db == nil then
        -- Fallback if native normalization is unavailable.
        static_gain_db = target_db - avg_level_db
    end
    static_gain_db = Clamp(static_gain_db, -24.0, 24.0)

    -- Ride variation around the average: quiet frames pushed up, loud frames pushed down,
    -- bounded by Range (down) / Max Up. The static gain carries the overall level to Target.
    local last_corr = static_gain_db
    for i = 1, nframes do
        local desired
        if gate_flags[i] then
            local dev = level_db[i] - avg_level_db          -- +louder / -quieter than average
            local ride = Clamp(-dev, -range_db, up_range_db) -- compensate deviation
            if math.abs(dev) <= tol_db then ride = 0.0 end    -- inside tolerance: no micro-moves
            desired = static_gain_db + ride
            last_corr = desired
        else
            -- Pause: hold last voiced gain (continuous level, no jumps).
            desired = last_corr
        end
        raw_corrections[i] = desired
    end

    -- Smooth with asymmetric attack/release plus symmetric slew limit (removes syllable pumping).
    local max_step_db = slew_dbps * hop_sec
    local smoothed = raw_corrections[1] or 0.0
    local smoothed_corr = {}
    for i = 1, nframes do
        local target_corr = raw_corrections[i] or 0.0
        local tau = (target_corr > smoothed) and attack_sec or release_sec
        local alpha = math.exp(-hop_sec / tau)
        local next_smoothed = alpha * smoothed + (1.0 - alpha) * target_corr
        local lo = smoothed - max_step_db
        local hi = smoothed + max_step_db
        smoothed = Clamp(next_smoothed, lo, hi)
        smoothed_corr[i] = smoothed
    end

    -- Final voiced-average trim in the SAME detector domain to remove systematic Target offset.
    do
        local sum_pred_lin = 0.0
        local n_pred = 0
        for i = 1, nframes do
            if gate_flags[i] then
                sum_pred_lin = sum_pred_lin + 10 ^ (((level_db[i] or -120.0) + (smoothed_corr[i] or 0.0)) / 10.0)
                n_pred = n_pred + 1
            end
        end
        if n_pred > 0 and sum_pred_lin > 0.0 then
            local avg_pred_db = 10.0 * math.log(sum_pred_lin / n_pred) / math.log(10)
            local trim_db = Clamp(target_db - avg_pred_db, -12.0, 12.0)
            if math.abs(trim_db) > 0.03 then
                for i = 1, nframes do
                    smoothed_corr[i] = (smoothed_corr[i] or 0.0) + trim_db
                end
            end
        end
    end

    local point_step_frames = math.max(1, math.floor(point_step_sec / hop_sec + 0.5))
    local write_each_frame = gate_view_on

    out_points[#out_points + 1] = { t = scan_start, val = r.ScaleToEnvelopeMode(ctx_entry.scale_mode, ctx_entry.baseline) }
    for i = 1, nframes do
        if write_each_frame or (i % point_step_frames) == 0 or i == nframes then
            local out_amp
            if gate_view_on then
                -- Binary gate trace for clear visual QA: mark only pause/silence closures.
                local gate_closed_vis = (not gate_flags[i])
                local vis_db = gate_closed_vis and (-gate_mark_db) or 0.0
                out_amp = ctx_entry.baseline * DbToAmp(vis_db)
            else
                out_amp = ctx_entry.baseline * DbToAmp(smoothed_corr[i] or 0.0)
            end
            out_amp = Clamp(out_amp, 0.0001, 16.0)
            local raw_val = r.ScaleToEnvelopeMode(ctx_entry.scale_mode, out_amp)
            out_points[#out_points + 1] = { t = frame_times[i], val = raw_val }
        end
    end
    out_points[#out_points + 1] = { t = scan_end, val = r.ScaleToEnvelopeMode(ctx_entry.scale_mode, ctx_entry.baseline) }

    r.DestroyAudioAccessor(accessor)
    return out_points
end

local function RunAutoLevelWrite()
    if not params.autolevel_enabled then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: enable rider first\n")
        return false
    end

    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: no selected items\n")
        return false
    end

    local detector_opt, _ = GetSelectedAutoLevelDetector()
    if params.autolevel_gate_view and detector_opt.key ~= "lufs_style" then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: Show Gate On Env works in LUFS-style detector mode only\n")
    end
    local target_opt, _ = GetSelectedAutoLevelTarget()
    local contexts = BuildAutoLevelContexts(target_opt, true)

    local context_count = 0
    for _ in pairs(contexts) do context_count = context_count + 1 end
    if context_count == 0 then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: no writable target envelopes found\n")
        return false
    end

    local function EnsureEnvelopeShown(env)
        if not env then return end
        if r.GetSetEnvelopeInfo_String then
            r.GetSetEnvelopeInfo_String(env, "ACTIVE", "1", true)
            r.GetSetEnvelopeInfo_String(env, "VISIBLE", "1", true)
            r.GetSetEnvelopeInfo_String(env, "SHOWLANE", "1", true)
        end
    end

    local total_points = 0
    local written_envs = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for _, ctx_entry in pairs(contexts) do
        local min_t, max_t = nil, nil
        for _, span in ipairs(ctx_entry.spans) do
            local pts = CollectAutoLevelPointsForSpan(ctx_entry, span, detector_opt)
            for _, p in ipairs(pts) do
                ctx_entry.points[#ctx_entry.points + 1] = p
            end
            if min_t == nil or span.start_t < min_t then min_t = span.start_t end
            if max_t == nil or span.end_t > max_t then max_t = span.end_t end
        end

        if #ctx_entry.points > 0 and min_t and max_t and max_t > min_t then
            EnsureEnvelopeShown(ctx_entry.env)
            r.DeleteEnvelopePointRangeEx(ctx_entry.env, -1, min_t - 0.0005, max_t + 0.0005)
            for _, p in ipairs(ctx_entry.points) do
                r.InsertEnvelopePoint(ctx_entry.env, p.t, p.val, 2, 0.0, false, true)
                total_points = total_points + 1
            end
            r.Envelope_SortPointsEx(ctx_entry.env, -1)
            written_envs = written_envs + 1
        end
    end

    r.PreventUIRefresh(-1)
    if r.TrackList_AdjustWindows then
        r.TrackList_AdjustWindows(false)
    end
    r.UpdateArrange()
    r.Undo_EndBlock("VO Auto-Level Rider Write", -1)

    r.ShowConsoleMsg(string.format("[VO Tool] Auto-Level: target=%s, detector=%s, envelopes=%d, points=%d\n", target_opt.label, detector_opt.label, written_envs, total_points))
    return written_envs > 0
end

local function RunAutoLevelClear()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] Auto-Level: no selected items for clear\n")
        return false
    end

    local target_opt, _ = GetSelectedAutoLevelTarget()
    local contexts = BuildAutoLevelContexts(target_opt, false)
    local cleared = 0

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, ctx_entry in pairs(contexts) do
        local min_t, max_t = nil, nil
        for _, span in ipairs(ctx_entry.spans) do
            if min_t == nil or span.start_t < min_t then min_t = span.start_t end
            if max_t == nil or span.end_t > max_t then max_t = span.end_t end
        end
        if min_t and max_t and max_t > min_t then
            r.DeleteEnvelopePointRangeEx(ctx_entry.env, -1, min_t - 0.0005, max_t + 0.0005)
            r.Envelope_SortPointsEx(ctx_entry.env, -1)
            cleared = cleared + 1
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("VO Auto-Level Rider Clear", -1)

    r.ShowConsoleMsg(string.format("[VO Tool] Auto-Level: cleared target=%s, envelopes=%d\n", target_opt.label, cleared))
    return cleared > 0
end

local function ClearAutoSplitPreviewRegions()
    autosplit_preview_regions = {}
    if not r.CountProjectMarkers then return end

    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local total = (num_markers or 0) + (num_regions or 0)
    if total <= 0 then return end

    local enum_idx = 0
    while enum_idx < total do
        local retval, isrgn, pos, rgnend, name, idx, color
        if r.EnumProjectMarkers3 then
            retval, isrgn, pos, rgnend, name, idx, color = r.EnumProjectMarkers3(0, enum_idx)
        else
            retval, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers(enum_idx)
            color = 0
        end

        if retval and isrgn and type(name) == "string" and name:find(AUTOSPLIT_PREVIEW_PREFIX, 1, true) == 1 then
            if r.DeleteProjectMarkerByIndex then
                r.DeleteProjectMarkerByIndex(0, enum_idx)
                total = total - 1
            elseif r.DeleteProjectMarker then
                r.DeleteProjectMarker(0, idx, true)
                enum_idx = enum_idx + 1
            else
                enum_idx = enum_idx + 1
            end
        else
            enum_idx = enum_idx + 1
        end
    end
end

local function CreateAutoSplitPreviewRegions(segments)
    ClearAutoSplitPreviewRegions()
    if not segments or #segments == 0 then return end

    for i, seg in ipairs(segments) do
        if seg.finish > seg.start + 0.001 then
            local idx = r.AddProjectMarker2(0, true, seg.start, seg.finish, AUTOSPLIT_PREVIEW_PREFIX .. " " .. i, -1, 0)
            autosplit_preview_regions[#autosplit_preview_regions + 1] = idx
        end
    end
end

local function IsBreathLikeSilence(seg_len, avg_db, threshold_db)
    local aggr = math.max(0.0, math.min(1.0, tonumber(params.autosplit_breath_aggr) or 0.65))
    local max_len = 0.28 + (0.52 * aggr)
    if seg_len > max_len then return false end

    local db_offset = 6.0 + (14.0 * aggr)
    return avg_db > (threshold_db - db_offset)
end

local function IsLikelyFricativeDip(seg_len, avg_db, threshold_db)
    if seg_len > 0.09 then return false end
    return avg_db > (threshold_db - 6.0)
end

local function ShouldRemoveBreathSegment(breath_key, likely_breath, run_len, run_prev_db, run_next_db, threshold_db)
    if not likely_breath then return false end
    local aggr = math.max(0.0, math.min(1.0, tonumber(params.autosplit_breath_aggr) or 0.65))
    local context_margin = 4.0 + 4.0 * aggr
    local has_speech_context = (run_prev_db >= threshold_db + context_margin) and (run_next_db >= threshold_db + context_margin)
    if not has_speech_context then return false end

    if breath_key == "remove_breaths" then
        return true
    end

    if breath_key == "balanced" then
        local max_balanced_len = 0.14 + 0.16 * aggr
        return run_len <= max_balanced_len
    end

    return false
end

local function AnalyzeSilenceSegmentsForItem(item, take, threshold_db, min_silence_sec, pre_pad_sec, post_pad_sec, breath_key, stats)
    local segments = {}
    if not item or not take then return segments end
    if r.TakeIsMIDI and r.TakeIsMIDI(take) then return segments end

    local source = r.GetMediaItemTake_Source(take)
    if not source then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: skipped take without source\n")
        return segments
    end

    local num_channels = math.max(1, math.min(8, r.GetMediaSourceNumChannels(source) or 1))
    local accessor = r.CreateTakeAudioAccessor(take)
    if not accessor then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: failed to create audio accessor\n")
        return segments
    end

    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_pos + item_len

    local acc_start = r.GetAudioAccessorStartTime(accessor)
    local acc_end = r.GetAudioAccessorEndTime(accessor)
    local scan_start = math.max(item_pos, acc_start)
    local scan_end = math.min(item_end, acc_end)
    if scan_end <= scan_start then
        r.DestroyAudioAccessor(accessor)
        return segments
    end

    local sample_rate = 16000
    local min_cut_sec = math.max(0.01, (tonumber(params.autosplit_min_cut_ms) or 55.0) / 1000.0)
    local breath_aggr = math.max(0.0, math.min(1.0, tonumber(params.autosplit_breath_aggr) or 0.65))
    local detect_threshold_db = threshold_db
    if breath_key == "remove_breaths" then
        detect_threshold_db = threshold_db + (1.0 + 3.0 * breath_aggr)
    elseif breath_key == "balanced" then
        detect_threshold_db = threshold_db + (0.5 + 1.5 * breath_aggr)
    end
    local window_sec = math.max(0.010, (params.autosplit_window_ms or 40.0) / 1000.0)
    local hop_sec = math.max(0.005, (params.autosplit_hop_ms or 10.0) / 1000.0)
    local samples_per_window = math.max(1, math.floor(sample_rate * window_sec + 0.5))
    local buffer_samples = samples_per_window * num_channels
    if not r.new_array then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: reaper.new_array is unavailable in this REAPER build\n")
        r.DestroyAudioAccessor(accessor)
        return segments
    end
    local sample_buffer = r.new_array(buffer_samples)

    local run_start = nil
    local run_sum_db = 0.0
    local run_count = 0
    local run_prev_db = -120.0
    local prev_frame_db = -120.0

    local t = scan_start
    while t < scan_end do
        local ret = r.GetAudioAccessorSamples(accessor, sample_rate, num_channels, t, samples_per_window, sample_buffer)
        if ret < 0 then
            r.ShowConsoleMsg("[VO Tool] AutoSplit: accessor read error\n")
            break
        end

        local frame_peak = 0.0
        if ret > 0 then
            for i = 1, buffer_samples do
                local v = sample_buffer[i]
                if v == nil then v = sample_buffer[i - 1] end
                local av = math.abs(v or 0.0)
                if av > frame_peak then frame_peak = av end
            end
        end

        local db = AmpToDb(frame_peak)
        local frame_end = math.min(t + window_sec, scan_end)
        local is_silent = db <= detect_threshold_db

        if is_silent then
            if not run_start then
                run_start = t
                run_sum_db = 0.0
                run_count = 0
                run_prev_db = prev_frame_db
            end
            run_sum_db = run_sum_db + db
            run_count = run_count + 1
        elseif run_start then
            local run_end = frame_end
            local run_len = run_end - run_start
            local avg_db = run_count > 0 and (run_sum_db / run_count) or db
            local likely_fricative = IsLikelyFricativeDip(run_len, avg_db, threshold_db)
            local likely_breath = IsBreathLikeSilence(run_len, avg_db, threshold_db)
            local run_next_db = db
            local remove_as_breath = ShouldRemoveBreathSegment(breath_key, likely_breath, run_len, run_prev_db, run_next_db, threshold_db)
            local strict_silence = avg_db <= threshold_db

            if run_len >= min_silence_sec and not likely_fricative then
                local seg_start = math.max(item_pos, run_start + pre_pad_sec)
                local seg_end = math.min(item_end, run_end - post_pad_sec)
                local keep_segment = (seg_end - seg_start) >= min_cut_sec and strict_silence

                if remove_as_breath then
                    keep_segment = false
                    stats.breaths_filtered = (stats.breaths_filtered or 0) + 1
                end

                if keep_segment then
                    segments[#segments + 1] = {
                        item = item,
                        start = seg_start,
                        finish = seg_end,
                        guid = ({r.GetSetMediaItemInfo_String(item, "GUID", "", false)})[2] or tostring(item)
                    }
                end
            elseif likely_fricative then
                stats.fricative_filtered = (stats.fricative_filtered or 0) + 1
            end

            run_start = nil
            run_sum_db = 0.0
            run_count = 0
        end

        prev_frame_db = db
        t = t + hop_sec
    end

    if run_start then
        local run_end = scan_end
        local run_len = run_end - run_start
        local avg_db = run_count > 0 and (run_sum_db / run_count) or threshold_db
        local likely_fricative = IsLikelyFricativeDip(run_len, avg_db, threshold_db)
        local likely_breath = IsBreathLikeSilence(run_len, avg_db, threshold_db)
        local run_next_db = threshold_db - 12.0
        local remove_as_breath = ShouldRemoveBreathSegment(breath_key, likely_breath, run_len, run_prev_db, run_next_db, threshold_db)
        local strict_silence = avg_db <= threshold_db

        if run_len >= min_silence_sec and not likely_fricative then
            local seg_start = math.max(item_pos, run_start + pre_pad_sec)
            local seg_end = math.min(item_end, run_end - post_pad_sec)
            local keep_segment = (seg_end - seg_start) >= min_cut_sec and strict_silence
            if remove_as_breath then
                keep_segment = false
                stats.breaths_filtered = (stats.breaths_filtered or 0) + 1
            end
            if keep_segment then
                segments[#segments + 1] = {
                    item = item,
                    start = seg_start,
                    finish = seg_end,
                    guid = ({r.GetSetMediaItemInfo_String(item, "GUID", "", false)})[2] or tostring(item)
                }
            end
        elseif likely_fricative then
            stats.fricative_filtered = (stats.fricative_filtered or 0) + 1
        end
    end

    r.DestroyAudioAccessor(accessor)
    return segments
end

local function AnalyzeVoiceAutoSplitPreview()
    if not params.autosplit_enabled then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: enable Auto-Split first\n")
        return false
    end

    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: no selected items\n")
        return false
    end

    local breath_policy, _ = GetSelectedAutoSplitBreathPolicy()
    local threshold_db = tonumber(params.autosplit_threshold_db) or -42.0
    local min_silence_sec = math.max(0.02, (tonumber(params.autosplit_min_silence_ms) or 90.0) / 1000.0)
    local pre_pad_sec = math.max(0.0, (tonumber(params.autosplit_pre_pad_ms) or 35.0) / 1000.0)
    local post_pad_sec = math.max(0.0, (tonumber(params.autosplit_post_pad_ms) or 35.0) / 1000.0)

    local all_segments = {}
    local stats = { items = 0, segments = 0, breaths_filtered = 0, fricative_filtered = 0, keep_merged = 0 }

    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = item and r.GetActiveTake(item) or nil
        if item and take and (not r.TakeIsMIDI or not r.TakeIsMIDI(take)) then
            local segs = AnalyzeSilenceSegmentsForItem(item, take, threshold_db, min_silence_sec, pre_pad_sec, post_pad_sec, breath_policy.key, stats)
            stats.items = stats.items + 1
            for _, seg in ipairs(segs) do
                all_segments[#all_segments + 1] = seg
            end
        end
    end

    table.sort(all_segments, function(a, b)
        if a.start == b.start then
            return (a.finish or 0) < (b.finish or 0)
        end
        return a.start < b.start
    end)

    local min_keep_sec = math.max(0.01, (tonumber(params.autosplit_min_keep_ms) or 95.0) / 1000.0)
    if min_keep_sec > 0 and #all_segments > 1 then
        local grouped = {}
        local grouped_order = {}
        for _, seg in ipairs(all_segments) do
            local k = seg.guid or tostring(seg.item)
            if k and k ~= "" then
                if not grouped[k] then
                    grouped[k] = {}
                    grouped_order[#grouped_order + 1] = k
                end
                grouped[k][#grouped[k] + 1] = seg
            end
        end

        local merged_result = {}
        for _, k in ipairs(grouped_order) do
            local segs = grouped[k]
            table.sort(segs, function(a, b) return a.start < b.start end)
            if #segs > 0 then
                local curr = {
                    item = segs[1].item,
                    start = segs[1].start,
                    finish = segs[1].finish,
                    guid = segs[1].guid
                }
                for i = 2, #segs do
                    local nxt = segs[i]
                    local gap_keep = (nxt.start or 0) - (curr.finish or 0)
                    if gap_keep < min_keep_sec then
                        if (nxt.finish or 0) > (curr.finish or 0) then
                            curr.finish = nxt.finish
                        end
                        stats.keep_merged = (stats.keep_merged or 0) + 1
                    else
                        merged_result[#merged_result + 1] = curr
                        curr = {
                            item = nxt.item,
                            start = nxt.start,
                            finish = nxt.finish,
                            guid = nxt.guid
                        }
                    end
                end
                merged_result[#merged_result + 1] = curr
            end
        end

        all_segments = merged_result
        table.sort(all_segments, function(a, b)
            if a.start == b.start then
                return (a.finish or 0) < (b.finish or 0)
            end
            return a.start < b.start
        end)
    end

    autosplit_preview_segments = all_segments
    stats.segments = #all_segments
    autosplit_last_stats = stats

    CreateAutoSplitPreviewRegions(all_segments)
    r.UpdateArrange()
    r.ShowConsoleMsg(string.format("[VO Tool] AutoSplit preview: items=%d, segments=%d, breaths_filtered=%d, fricative_filtered=%d, keep_merged=%d\n", stats.items, stats.segments, stats.breaths_filtered, stats.fricative_filtered, stats.keep_merged or 0))
    return true
end

local function ApplyVoiceAutoSplitFromPreview()
    local mode, _ = GetSelectedAutoSplitMode()
    if mode.key == "preview" then
        r.ShowConsoleMsg("[VO Tool] AutoSplit apply: Mode is 'Preview only'. Switch Mode to 'Split only' or 'Split + delete silence'.\n")
        return AnalyzeVoiceAutoSplitPreview()
    end

    if not autosplit_preview_segments or #autosplit_preview_segments == 0 then
        if not AnalyzeVoiceAutoSplitPreview() then return false end
    end
    if not autosplit_preview_segments or #autosplit_preview_segments == 0 then
        r.ShowConsoleMsg("[VO Tool] AutoSplit: no split segments found\n")
        return false
    end

    local grouped = {}
    for _, seg in ipairs(autosplit_preview_segments) do
        local key = seg.guid or tostring(seg.item) or ""
        if key ~= "" then
            grouped[key] = grouped[key] or {}
            grouped[key][#grouped[key] + 1] = seg
        end
    end

    local split_count = 0
    local deleted_count = 0
    local min_cut_sec = math.max(0.01, (tonumber(params.autosplit_min_cut_ms) or 55.0) / 1000.0)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for guid, segs in pairs(grouped) do
        table.sort(segs, function(a, b) return a.start < b.start end)
        local current_item = nil
        local first_seg = segs[1]
        if first_seg and first_seg.item and r.ValidatePtr(first_seg.item, "MediaItem*") then
            current_item = first_seg.item
        else
            current_item = RecoverItemByGUID(guid)
        end
        if not current_item then
            r.ShowConsoleMsg(string.format("[VO Tool] AutoSplit apply: skipped group, item not found (%s)\n", tostring(guid)))
        end
        if current_item then
            for _, seg in ipairs(segs) do
                if not current_item then break end
                local item_pos = r.GetMediaItemInfo_Value(current_item, "D_POSITION")
                local item_len = r.GetMediaItemInfo_Value(current_item, "D_LENGTH")
                local item_end = item_pos + item_len
                local s = math.max(item_pos + 0.0001, math.min(seg.start, item_end - 0.0002))
                local e = math.max(item_pos + 0.0002, math.min(seg.finish, item_end - 0.0001))

                if e > s + min_cut_sec then
                    local right = r.SplitMediaItem(current_item, s)
                    if right then
                        split_count = split_count + 1
                        local tail = r.SplitMediaItem(right, e)
                        if tail then
                            split_count = split_count + 1
                        end

                        if mode.key == "split_delete" then
                            local tr = r.GetMediaItemTrack(right)
                            if tr and r.ValidatePtr(right, "MediaItem*") then
                                r.DeleteTrackMediaItem(tr, right)
                                deleted_count = deleted_count + 1
                            end
                        end

                        current_item = tail
                    end
                end
            end
        end
    end

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("VO Auto-Split by Silence", -1)

    if mode.key ~= "preview" then
        ClearAutoSplitPreviewRegions()
    end

    if split_count == 0 then
        r.ShowConsoleMsg("[VO Tool] AutoSplit apply: 0 splits made. Check Mode and threshold/min-silence settings.\n")
    end
    r.ShowConsoleMsg(string.format("[VO Tool] AutoSplit apply: mode=%s, splits=%d, deleted=%d\n", mode.label, split_count, deleted_count))
    return true
end

-- CalculateNormalization returns a LINEAR multiplier to set as take D_VOL directly.
-- Returns a table {target_linear, cur_take_vol_abs} for apply + mode filtering.
local function GetItemNormalizeData(item, take, unit_api_value, target_db)
    if not item or not take then return nil, "missing_take" end
    if r.TakeIsMIDI and r.TakeIsMIDI(take) then return nil, "midi_take" end

    local source = r.GetMediaItemTake_Source(take)
    if not source then return nil, "missing_source" end

    -- Returns LINEAR gain to set as take D_VOL (not dB).
    local target_linear = r.CalculateNormalization(source, unit_api_value, target_db, 0, 0)
    if type(target_linear) ~= "number" or target_linear <= 0 then return nil, "calc_failed" end

    local cur_take_vol_abs = math.abs(r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0)

    return { target_linear = target_linear, cur_take_vol_abs = cur_take_vol_abs }, nil
end

-- Set take D_VOL directly to target_linear (the value from CalculateNormalization).
-- Preserves polarity. Does NOT touch item D_VOL. Idempotent on repeated calls.
local function ApplyItemNormalize(item, take, target_linear)
    if not item or not take or type(target_linear) ~= "number" or target_linear <= 0 then return false end

    local cur_take_vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1.0
    local take_sign    = (cur_take_vol < 0) and -1 or 1

    return r.SetMediaItemTakeInfo_Value(take, "D_VOL", take_sign * target_linear)
end

local function RunNativeNormalization()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: no selected items\n")
        return false, 0, 0
    end

    if not r.CalculateNormalization then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: CalculateNormalization API is not available in this REAPER version\n")
        return false, 0, sel_count
    end

    local unit, _ = GetSelectedNormalizeUnit()
    local mode, _ = GetSelectedNormalizeMode()
    local target_db = tonumber(params.preprod_normalize_target)
    if not target_db then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: invalid target value\n")
        return false, 0, 0
    end

    local adjustments = {}
    local sum_target_db = 0  -- accumulate in dB for proper average
    local valid_count = 0
    local skipped_count = 0

    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = item and r.GetActiveTake(item) or nil
        if item and take then
            local nd, err = GetItemNormalizeData(item, take, unit.api_value, target_db)
            if nd ~= nil then
                adjustments[#adjustments + 1] = {
                    item              = item,
                    take              = take,
                    target_linear     = nd.target_linear,
                    cur_take_vol_abs  = nd.cur_take_vol_abs
                }
                sum_target_db = sum_target_db + (20 * math.log(nd.target_linear) / math.log(10))
                valid_count = valid_count + 1
            else
                skipped_count = skipped_count + 1
                r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: skipped item (" .. tostring(err) .. ")\n")
            end
        else
            skipped_count = skipped_count + 1
            r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: skipped item without active take\n")
        end
    end

    if valid_count == 0 then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD normalize: no valid audio takes to process\n")
        return false, 0, skipped_count
    end

    -- Average target in dB space, then convert back to linear for apply.
    -- We also use this average as the split point for quiet/loud mode filtering,
    -- so mode behavior is relative to the current selection (not a fixed threshold).
    local avg_target_db     = sum_target_db / valid_count
    local avg_target_linear = 10 ^ (avg_target_db / 20)
    local applied_count = 0
    local quiet_candidates = 0
    local loud_candidates = 0

    for _, row in ipairs(adjustments) do
        if row.target_linear > avg_target_linear + 0.000001 then
            quiet_candidates = quiet_candidates + 1
        elseif row.target_linear < avg_target_linear - 0.000001 then
            loud_candidates = loud_candidates + 1
        end
    end

    for _, row in ipairs(adjustments) do
        local apply_linear = row.target_linear
        local should_apply = false

        if mode.key == "all" then
            should_apply = true
        elseif mode.key == "quiet_only" then
            -- Quiet relative to selected set: items requiring more gain than selected average.
            should_apply = row.target_linear > avg_target_linear + 0.000001
        elseif mode.key == "loud_only" then
            -- Loud relative to selected set: items requiring less gain than selected average.
            should_apply = row.target_linear < avg_target_linear - 0.000001
        elseif mode.key == "average_selected" then
            should_apply = true
            apply_linear = avg_target_linear
        end

        if should_apply and ApplyItemNormalize(row.item, row.take, apply_linear) then
            applied_count = applied_count + 1
        end
    end

    r.ShowConsoleMsg(string.format("[VO Tool] PRE-PROD normalize: unit=%s, target=%.2f, mode=%s, applied=%d, skipped=%d, quiet=%d, loud=%d\n", unit.label, target_db, mode.label, applied_count, skipped_count, quiet_candidates, loud_candidates))
    return true, applied_count, skipped_count
end

local function RunNormalizeOnly()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    RunNativeNormalization()
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Normalize Items", -1)
end

local function AddChainPresetToTake(take, chain_entry)
    if not take or not chain_entry then return false end

    local candidates = {
        "FXCHAIN:" .. tostring(chain_entry.rel_no_ext or ""),
        "FXCHAIN:" .. tostring(chain_entry.rel_file or ""),
        "FXCHAIN:" .. tostring(PREPROD_CHAIN_SUBFOLDER) .. "/" .. tostring(chain_entry.rel_no_ext or ""),
        "FXCHAIN:" .. tostring(PREPROD_CHAIN_SUBFOLDER) .. "/" .. tostring(chain_entry.rel_file or ""),
        "FXCHAIN:" .. tostring(chain_entry.path),
        "FXCHAIN:" .. tostring(chain_entry.file),
        tostring(chain_entry.path)
    }

    for _, fxname in ipairs(candidates) do
        if fxname and fxname ~= "" then
            local fx_idx = r.TakeFX_AddByName(take, fxname, 1)
            if fx_idx >= 0 then
                return true
            end

            local fx_alt = fxname:gsub("/", "\\")
            if fx_alt ~= fxname then
                fx_idx = r.TakeFX_AddByName(take, fx_alt, 1)
                if fx_idx >= 0 then
                    return true
                end
            end
        end
    end

    r.ShowConsoleMsg("[VO Tool] PRE-PROD: failed to load chain preset: " .. tostring(chain_entry.name) .. "\n")
    return false
end

local function NormalizeToOSPath(p)
    if not p then return "" end
    local is_windows = package.config:sub(1, 1) == "\\"
    if is_windows then
        return (tostring(p):gsub("/", "\\"))
    else
        return (tostring(p):gsub("\\", "/"))
    end
end

local function LoadChainOnTrack(track, chain_entry)
    if not track or not chain_entry then return nil, nil end

    local before = r.TrackFX_GetCount and r.TrackFX_GetCount(track) or 0
    
    local abs_path = NormalizeToOSPath(chain_entry.path)
    
    -- Verify the file exists on disk first to prevent REAPER's fuzzy matching!
    -- Use native r.file_exists to support Unicode/UTF-8 path characters on Windows.
    if not r.file_exists(abs_path) then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD: FX chain file not found on disk: " .. tostring(abs_path) .. "\n")
        return nil, nil
    end

    local rel_no_ext = PREPROD_CHAIN_SUBFOLDER .. "/" .. (chain_entry.rel_no_ext or "")
    local rel_file = PREPROD_CHAIN_SUBFOLDER .. "/" .. (chain_entry.rel_file or "")

    local raw_candidates = {
        abs_path,
        "FXCHAIN:" .. abs_path,
        "FXCHAIN:" .. rel_no_ext,
        "FXCHAIN:" .. rel_file,
        rel_file,
        rel_no_ext,
    }

    -- Expand with Windows backslash variants
    local candidates = {}
    for _, cand in ipairs(raw_candidates) do
        candidates[#candidates + 1] = cand
        local win_cand = cand:gsub("/", "\\")
        if win_cand ~= cand then
            candidates[#candidates + 1] = win_cand
        end
    end

    -- Try loading using instantiate = -1 (force add).
    -- Negative instantiate is required by REAPER to successfully add an FX chain.
    for _, fxname in ipairs(candidates) do
        r.TrackFX_AddByName(track, fxname, false, -1)
        local after = r.TrackFX_GetCount and r.TrackFX_GetCount(track) or before
        if after > before then
            return before, after - 1
        end
    end

    r.ShowConsoleMsg("[VO Tool] PRE-PROD: failed to load FX chain from: " .. tostring(abs_path) .. "\n")
    return nil, nil
end

local function CopyTrackChainToTake(track, fx_first, fx_last, take)
    if not track or not take then return false end
    if type(fx_first) ~= "number" or type(fx_last) ~= "number" or fx_last < fx_first then return false end

    local before = r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0
    for fx = fx_first, fx_last do
        r.TrackFX_CopyToTake(track, fx, take, -1, false)
    end
    local after = r.TakeFX_GetCount and r.TakeFX_GetCount(take) or before
    return after > before
end

local function StartPreProdBounce()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD: no selected items\n")
        return
    end

    if preprod_job then
        r.ShowConsoleMsg("[VO Tool] PRE-PROD: job is already running\n")
        return
    end

    local needs_fx = params.preprod_chain_enabled
    local selected_chain = nil
    if needs_fx then
        RefreshPreProdChainCache()
        EnsurePreProdChainSelection()
        selected_chain = GetSelectedPreProdChain()
        if not selected_chain then
            r.ShowConsoleMsg("[VO Tool] PRE-PROD: no chain preset selected or found in FXChains/VO\n")
            return
        end
    end

    r.Undo_BeginBlock()

    local added_fx_count = 0
    local failed_fx_count = 0
    local temp_track_guid = nil

    if needs_fx then
        -- Load the FX chain ONCE on a single temporary track.
        -- This track is kept alive during the bounce/glue stage to ensure that
        -- complex plugins (e.g. UAD) have a stable host context to initialize
        -- and render. It is deleted at the very end of the deferred pipeline.
        local tr_count = r.CountTracks(0)
        r.InsertTrackAtIndex(tr_count, false)
        local temp_track = r.GetTrack(0, tr_count)
        if temp_track then
            -- Hide track and set name
            r.GetSetMediaTrackInfo_String(temp_track, "P_NAME", "VO_Tool_Temp_FX", true)
            r.SetMediaTrackInfo_Value(temp_track, "B_SHOWINTM", 0) -- Hide in TCP
            r.SetMediaTrackInfo_Value(temp_track, "B_SHOWINMIXER", 0) -- Hide in Mixer
            
            local _, curr_guid = r.GetSetMediaTrackInfo_String(temp_track, "GUID", "", false)
            temp_track_guid = curr_guid

            local fx_first, fx_last = LoadChainOnTrack(temp_track, selected_chain)
            if fx_first ~= nil then
                for i = 0, sel_count - 1 do
                    local item = r.GetSelectedMediaItem(0, i)
                    local take = item and r.GetActiveTake(item) or nil
                    local is_midi = take and r.TakeIsMIDI and r.TakeIsMIDI(take)

                    if take and not is_midi then
                        local before = r.TakeFX_GetCount(take)
                        if CopyTrackChainToTake(temp_track, fx_first, fx_last, take) then
                            local after_n = r.TakeFX_GetCount(take)
                            -- Explicitly bring every newly-added FX online and enabled.
                            for fx_i = before, after_n - 1 do
                                if r.TakeFX_SetEnabled then r.TakeFX_SetEnabled(take, fx_i, true) end
                                if r.TakeFX_SetOffline then r.TakeFX_SetOffline(take, fx_i, false) end
                            end
                            added_fx_count = added_fx_count + 1
                            r.ShowConsoleMsg(string.format(
                                "[VO Tool] PRE-PROD item[%d]: loaded %d FX from temp track\n",
                                i, after_n - before
                            ))
                        else
                            failed_fx_count = failed_fx_count + 1
                            r.ShowConsoleMsg(string.format(
                                "[VO Tool] PRE-PROD item[%d]: failed to copy FX from temp track\n", i
                            ))
                        end
                    elseif is_midi then
                        -- skip
                    else
                        failed_fx_count = failed_fx_count + 1
                        r.ShowConsoleMsg("[VO Tool] PRE-PROD: item " .. i .. " has no active take\n")
                    end
                end
            else
                failed_fx_count = sel_count
                r.ShowConsoleMsg("[VO Tool] PRE-PROD: failed to load chain on temp track\n")
            end
        else
            failed_fx_count = sel_count
            r.ShowConsoleMsg("[VO Tool] PRE-PROD: failed to create temp track\n")
        end
    end

    -- Show FX badge on items before bounce fires so user can confirm chain is loaded
    r.UpdateArrange()

    local now = r.time_precise and r.time_precise() or 0
    preprod_job = {
        stage = "wait_bounce",
        run_at = now + math.max(0, params.preprod_wait_before_apply or 0)
                     + math.max(0, params.preprod_wait_before_bounce or 0),
        needs_fx = needs_fx,
        selected_chain_name = selected_chain and selected_chain.name or "(none)",
        added_fx_count = added_fx_count,
        failed_fx_count = failed_fx_count,
        normalize_after_bounce = params.preprod_normalize_enabled,
        normalized_count = 0,
        normalize_skipped = 0,
        temp_track_guid = temp_track_guid
    }
end

local function RecoverTrackByGUID(guid_str)
    if not guid_str or guid_str == "" then return nil end
    local count = r.CountTracks(0)
    for i = 0, count - 1 do
        local tr = r.GetTrack(0, i)
        local _, curr_guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
        if curr_guid == guid_str then return tr end
    end
    return nil
end

local function ProcessPreProdJob()
    if not preprod_job then return end
    local now = r.time_precise and r.time_precise() or 0
    if now < (preprod_job.run_at or 0) then return end

    if preprod_job.stage == "wait_bounce" then
        -- Fire the glue/bounce command, then yield for one defer frame.
        -- REAPER completes the glue asynchronously; the selection will be
        -- updated to the new bounced item only after the current engine pass.
        r.Main_OnCommand(PREPROD_GLUE_CMD_ID, 0)
        preprod_job.stage = "wait_normalize"
        preprod_job.run_at = 0  -- run as soon as possible in the next defer frame
        return
    end

    if preprod_job.stage == "wait_normalize" then
        -- Clean up the temp track now that the bounce/glue is finished.
        if preprod_job.temp_track_guid then
            local temp_track = RecoverTrackByGUID(preprod_job.temp_track_guid)
            if temp_track then
                r.DeleteTrack(temp_track)
            end
        end

        -- At this point REAPER has completed the glue and the new bounced
        -- item is selected.  Normalization now correctly reads the manual
        -- settings from the UI (preprod_normalize_unit/target/mode).
        if preprod_job.normalize_after_bounce then
            local _, applied_count, skipped_count = RunNativeNormalization()
            preprod_job.normalized_count = applied_count or 0
            preprod_job.normalize_skipped = skipped_count or 0
        end
        r.UpdateArrange()
        r.Undo_EndBlock("PRE-PROD Bounce", -1)
        r.ShowConsoleMsg(string.format(
            "[VO Tool] PRE-PROD done. Chain: %s, Added FX: %d, Failed FX ops: %d, Normalized: %d, Normalize skipped: %d\n",
            preprod_job.selected_chain_name or "(none)",
            preprod_job.added_fx_count or 0,
            preprod_job.failed_fx_count or 0,
            preprod_job.normalized_count or 0,
            preprod_job.normalize_skipped or 0
        ))
        preprod_job = nil
    end
end

-- Resolves the root file source by walking up the GetMediaSourceParent chain.
local function ResolveRootFileSource(source)
    if not source then return nil end
    local root = source
    while true do
        local parent = r.GetMediaSourceParent(root)
        if not parent then break end
        root = parent
    end
    return root
end

-- Get file modification time as a human-readable string (uses lfs if available).
local function GetFileMtimeStr(path)
    if not path or path == "" then return "—" end
    local ok_l, lfs = pcall(require, "lfs")
    if ok_l and lfs then
        local ok_a, mtime = pcall(function() return lfs.attributes(path, "modification") end)
        if ok_a and type(mtime) == "number" then
            return os.date("%d.%m.%y %H:%M", mtime)
        end
    end
    return "—"
end

-- Walk the -glued[digits] suffix chain and collect all existing ancestor files.
-- Returns list ordered oldest→newest (NOT including filepath itself).
-- Entry: {path, mtime, exists}
local function CollectGluedVersions(filepath)
    local chain = {}
    local current = filepath
    for _ = 1, 20 do
        local dir       = current:match("^(.*[\\/])")
        local base      = current:match("[\\/]([^\\/]+)$") or current
        local no_ext    = base:match("^(.+)%.[^%.]+$") or base
        local ext       = base:match("%.([^%.]+)$") or "wav"
        local prev_stem = no_ext:match("^(.-)%-glued[_%-]?%d*$")
        if not prev_stem or prev_stem == "" then break end
        local prev_path = (dir or "") .. prev_stem .. "." .. ext
        table.insert(chain, 1, {
            path  = prev_path,
            mtime = GetFileMtimeStr(prev_path),
            exists = r.file_exists(prev_path)
        })
        current = prev_path
    end
    return chain
end

-- Strip exactly n -glued[digits] suffixes from filepath.
local function StripGlueSuffix(filepath, n)
    local current = filepath
    for _ = 1, n do
        local dir       = current:match("^(.*[\\/])")
        local base      = current:match("[\\/]([^\\/]+)$") or current
        local no_ext    = base:match("^(.+)%.[^%.]+$") or base
        local ext       = base:match("%.([^%.]+)$") or "wav"
        local prev_stem = no_ext:match("^(.-)%-glued[_%-]?%d*$")
        if not prev_stem or prev_stem == "" then break end
        current = (dir or "") .. prev_stem .. "." .. ext
    end
    return current
end

local function GetMediaSourceFileNameSafe(source)
    if not source then return nil end
    local ok1, name1 = pcall(r.GetMediaSourceFileName, source)
    if ok1 and type(name1) == "string" and name1 ~= "" then
        return name1
    end
    local ok2, name2 = pcall(r.GetMediaSourceFileName, source, "")
    if ok2 and type(name2) == "string" and name2 ~= "" then
        return name2
    end
    return nil
end

local function ResolveRestorePath(filepath, strip_count)
    local target = StripGlueSuffix(filepath, strip_count)
    if target and r.file_exists(target) then return target end

    for s = strip_count - 1, 0, -1 do
        local alt = StripGlueSuffix(filepath, s)
        if alt and r.file_exists(alt) then
            return alt
        end
    end
    return nil
end

-- Place items from items_ctx on new tracks below their source tracks,
-- using source files derived by stripping strip_count glue suffixes.
local function DoRestoreItems(items_ctx, strip_count)
    local restore_tracks = {}
    local inserted = 0
    for _, ctx in ipairs(items_ctx) do
        local filename = ResolveRestorePath(ctx.filename, strip_count)
        if not filename or not r.file_exists(filename) then
            r.ShowConsoleMsg(string.format("[VO Tool] Restore: file not found for source: %s\n", tostring(ctx.filename)))
            goto rskip
        end
        local src_track = nil
        if ctx.src_track and r.ValidatePtr(ctx.src_track, "MediaTrack*") then
            src_track = ctx.src_track
        elseif ctx.src_track_num and ctx.src_track_num > 0 then
            src_track = r.GetTrack(0, ctx.src_track_num - 1)
        end
        if not src_track then goto rskip end
        local track_key   = tostring(src_track)
        local rst = restore_tracks[track_key]
        if not rst or not r.ValidatePtr(rst, "MediaTrack*") then
            local tn = math.floor(r.GetMediaTrackInfo_Value(src_track, "IP_TRACKNUMBER"))
            r.InsertTrackAtIndex(tn, false)
            rst = r.GetTrack(0, tn)
            if rst then
                local _, sname = r.GetTrackName(src_track)
                r.GetSetMediaTrackInfo_String(rst, "P_NAME", "Orig: " .. (sname or ""), true)
                local upd = {}
                for k, t in pairs(restore_tracks) do
                    if r.ValidatePtr(t, "MediaTrack*") then upd[k] = t end
                end
                upd[track_key] = rst
                restore_tracks = upd
            end
        end
        if not rst then goto rskip end
        local ni = r.AddMediaItemToTrack(rst)
        if not ni then goto rskip end
        r.SetMediaItemInfo_Value(ni, "D_POSITION",  ctx.pos)
        r.SetMediaItemInfo_Value(ni, "D_LENGTH",    ctx.len)
        r.SetMediaItemInfo_Value(ni, "D_FADEINLEN",  ctx.fi_len)
        r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", ctx.fo_len)
        local nt = r.AddTakeToMediaItem(ni)
        if not nt then goto rskip end
        local ns = r.PCM_Source_CreateFromFile(filename)
        if not ns then
            r.ShowConsoleMsg(string.format("[VO Tool] Restore: cannot create source: %s\n", filename))
            goto rskip
        end
        r.SetMediaItemTake_Source(nt, ns)
        local restored_basename = filename:match("[\\/]([^\\/]+)$") or filename
        r.GetSetMediaItemTakeInfo_String(nt, "P_NAME", restored_basename, true)
        r.SetMediaItemTakeInfo_Value(nt, "D_STARTOFFS", ctx.offs)
        r.SetMediaItemTakeInfo_Value(nt, "D_PLAYRATE",  ctx.rate)
        r.UpdateItemInProject(ni)
        inserted = inserted + 1
        ::rskip::
    end
    return inserted
end

-- Build restore context and open version picker (or restore directly if no chain).
local function OpenRestorePopup()
    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        r.ShowConsoleMsg("[VO Tool] Restore: no items selected\n")
        return
    end
    local items_ctx    = {}
    local example_chain = nil
    local example_file  = nil
    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = item and r.GetActiveTake(item)
        if not take or (r.TakeIsMIDI and r.TakeIsMIDI(take)) then goto osk end
        local source = r.GetMediaItemTake_Source(take)
        if not source then goto osk end
        local fsrc = ResolveRootFileSource(source)
        if not fsrc then goto osk end
        local filename = GetMediaSourceFileNameSafe(fsrc)
        if not filename or filename == "" then goto osk end
        local chain = CollectGluedVersions(filename)
        items_ctx[#items_ctx + 1] = {
            item = item, take = take, filename = filename,
            pos    = r.GetMediaItemInfo_Value(item, "D_POSITION"),
            len    = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
            offs   = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0,
            rate   = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0,
            fi_len = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0,
            fo_len = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0,
            src_track = r.GetMediaItemTrack(item),
            src_track_num = math.floor(r.GetMediaTrackInfo_Value(r.GetMediaItemTrack(item), "IP_TRACKNUMBER") or 0)
        }
        if not example_chain and #chain > 0 then
            example_chain = chain ; example_file = filename
        end
        ::osk::
    end
    if #items_ctx == 0 then
        r.ShowConsoleMsg("[VO Tool] Restore: no valid audio items\n")
        return
    end
    -- Build display list: ancestors first, current last
    local display = {}
    if example_chain then
        for idx, entry in ipairs(example_chain) do
            local lbl   = (idx == 1) and "Original" or ("After bounce " .. (idx - 1))
            local bname = entry.path:match("[\\/]([^\\/]+)$") or entry.path
            display[#display + 1] = {
                path = entry.path, basename = bname, mtime = entry.mtime,
                exists = entry.exists, label = lbl,
                strip_count = #example_chain - (idx - 1)
            }
        end
    end
    local cur_file  = example_file or (items_ctx[1] and items_ctx[1].filename) or ""
    local cur_bname = cur_file:match("[\\/]([^\\/]+)$") or cur_file
    display[#display + 1] = {
        path = cur_file, basename = cur_bname, mtime = GetFileMtimeStr(cur_file),
        exists = r.file_exists(cur_file), label = "Current (bounced)", strip_count = 0
    }
    preprod_restore_popup = { versions = display, selected = 1, items_ctx = items_ctx }
    r.ImGui_OpenPopup(ctx, "Choose Version##restore_modal")
end

RecoverItemByGUID = function(guid_str)
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

SaveItemsState = function()
    drag_state.items_data = {}
    drag_state.trim_start_base = params.trim_start or 0.0
    drag_state.trim_end_base = params.trim_end or 0.0
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
            r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", params.fade_in_shape)
            r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", params.fade_out_shape)
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function ApplyTrim()
    r.PreventUIRefresh(1)
    local delta_trim_start = (params.trim_start or 0.0) - (drag_state.trim_start_base or 0.0)
    local delta_trim_end = (params.trim_end or 0.0) - (drag_state.trim_end_base or 0.0)
    for _, data in ipairs(drag_state.items_data) do
        local item = ValidateOrRecover(data)
        if item and data.has_take then
            local take = r.GetActiveTake(item)
            if take then
                -- Trim Start trims item container start edge (position + length + source offset).
                -- Trim End trims item container end edge (length).
                local new_pos = data.pos + delta_trim_start
                local new_len = data.len - delta_trim_start - delta_trim_end
                local new_off = data.take_off + (delta_trim_start * data.take_rate)
                if new_len > 0.0001 then
                    r.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
                    r.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", math.max(0, new_off))
                end
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

local function GetSelectedRegionCount()
    if r.CountSelectedProjectMarkers then
        local attempts = {
            function() return r.CountSelectedProjectMarkers() end,
            function() return r.CountSelectedProjectMarkers(0) end,
            function() return r.CountSelectedProjectMarkers(0, false) end,
            function() return r.CountSelectedProjectMarkers(0, true) end,
            function() return r.CountSelectedProjectMarkers(0, 0) end,
            function() return r.CountSelectedProjectMarkers(0, 1) end
        }
        for _, attempt in ipairs(attempts) do
            local ok, a, b = pcall(attempt)
            if ok then
                if type(a) == "number" and type(b) == "number" then
                    if b >= 0 then return b end
                    if a >= 0 then return a end
                elseif type(a) == "number" and a >= 0 then
                    return a
                end
            end
        end
    end

    if r.CountSelectedProjectMarkers2 then
        local attempts2 = {
            function() return r.CountSelectedProjectMarkers2(0, true) end,
            function() return r.CountSelectedProjectMarkers2(0, 1) end,
            function() return r.CountSelectedProjectMarkers2(0) end
        }
        for _, attempt in ipairs(attempts2) do
            local ok, a, b = pcall(attempt)
            if ok then
                if type(a) == "number" and type(b) == "number" then
                    if b >= 0 then return b end
                    if a >= 0 then return a end
                elseif type(a) == "number" and a >= 0 then
                    return a
                end
            end
        end
    end

    -- Fallback: approximate by counting unique regions that contain selected item centers.
    local regions = GetAllRegions()
    if #regions == 0 then return 0 end

    local sel_count = r.CountSelectedMediaItems(0)
    if sel_count == 0 then
        -- Secondary fallback: if time selection is active, count regions that overlap it.
        -- This is only an approximation when region-selection APIs are unavailable.
        local ok, a, b, c = pcall(r.GetSet_LoopTimeRange2, 0, false, false, 0, 0, false)
        local ts_start, ts_end = nil, nil
        if ok then
            if type(a) == "boolean" then
                ts_start = b
                ts_end = c
            else
                ts_start = a
                ts_end = b
            end
        end

        if type(ts_start) == "number" and type(ts_end) == "number" and ts_end > ts_start then
            local count_ts = 0
            for _, reg in ipairs(regions) do
                if reg.s < ts_end and reg.e > ts_start then
                    count_ts = count_ts + 1
                end
            end
            return count_ts
        end
        return 0
    end

    local region_map = {}
    local count = 0
    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local center = pos + len * 0.5

        for _, reg in ipairs(regions) do
            if center >= reg.s and center <= reg.e then
                if not region_map[reg.enum_idx] then
                    region_map[reg.enum_idx] = true
                    count = count + 1
                end
                break
            end
        end
    end

    return count
end

local function HealSplits()
    local safety = 0
    while true do
        safety = safety + 1
        if safety > 256 then
            r.ShowConsoleMsg("[VO Tool] HealSplits: safety break triggered\n")
            return
        end

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

UpdateRegions = function(force_update)
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
    local existing_regions = GetAllRegions()
    for i = #existing_regions, 1, -1 do
        local reg = existing_regions[i]
        if (reg.s < search_end) and (reg.e > search_start) then
            if not r.DeleteProjectMarkerByIndex(0, reg.enum_idx) then
                r.ShowConsoleMsg("[VO Tool] UpdateRegions: failed to delete region by index\n")
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
    
    local all_regions = GetAllRegions()
    
    for i = 0, sel_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local center = pos + (item_end - pos)/2
        
        for _, reg in ipairs(all_regions) do
            if center >= reg.s and center <= reg.e then
                if not region_map[reg.enum_idx] then
                    region_map[reg.enum_idx] = true
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
            local ok = r.SetProjectMarkerByIndex2(0, reg.enum_idx, true, new_start, new_end, reg.idx, reg.name or "", reg.color or 0, 0)
            if not ok then
                r.ShowConsoleMsg("[VO Tool] ApplyRegionSpacing: failed to move region by index\n")
            end
            
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
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x1E463BFF)          -- Premium dark green-teal
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x2A6353FF)   -- Hover green-teal
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x347A66FF)    -- Active green-teal
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SeparatorActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGrip(), COLOR_BG_LIGHTER)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripHovered(), COLOR_ACCENT_LITE)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripActive(), COLOR_ACCENT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR_TEXT)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), COLOR_TEXT_DIM)
 
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 16, 12)    -- Increased window padding
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)       -- Increased frame padding for taller elements
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 10, 8)       -- Increased item spacing
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(), 8, 4)   -- Increased inner item spacing
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
    local open = r.ImGui_CollapsingHeader(ctx, "  " .. name, r.ImGui_TreeNodeFlags_DefaultOpen())
    if header_font then r.ImGui_PopFont(ctx) end
    return open
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
    r.ImGui_Dummy(ctx, 0, 2)
end

local function Loop()
    SetModernTheme()
    if r.ImGui_SetNextFrameWantCaptureKeyboard then
        r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
    end
    HandleRegionTimelinePlayback()
    
    r.ImGui_SetNextWindowSize(ctx, 450, 540, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'VO Tool v2.59', true)
    
    if visible then
        if IsShiftQPressed() then
            ApplyAlignDuplicates()
        end
        
        local sel_count = r.CountSelectedMediaItems(0)
        local sel_regions = GetSelectedRegionCount()
        local current_region, _ = FindCurrentAndNextRegionAtTime(r.GetPlayPosition())
        r.ImGui_Separator(ctx)
        if sel_count > 0 then
            r.ImGui_TextColored(ctx, 0x77DD77FF, "ACTIVE SELECTION: " .. sel_count .. " Items")
        else
            r.ImGui_TextColored(ctx, 0xEE6666FF, "NO SELECTION")
        end
        r.ImGui_SameLine(ctx)
        if sel_regions > 0 then
            r.ImGui_TextColored(ctx, 0x77AAEEFF, "| Regions: " .. sel_regions)
        else
            r.ImGui_TextColored(ctx, 0x777777FF, "| Regions: 0")
        end
        r.ImGui_SameLine(ctx)
        if params.region_timeline_follow then
            if current_region then
                r.ImGui_TextColored(ctx, 0x77DD77FF, "| Playback: Region Follow ON")
            else
                r.ImGui_TextColored(ctx, 0xFFCC66FF, "| Playback: Region Follow ON (outside region)")
            end
        else
            r.ImGui_TextColored(ctx, 0x777777FF, "| Playback: Region Follow OFF")
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("PRE-PROD##sec_preprod") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            if #preprod_chain_cache == 0 then
                RefreshPreProdChainCache()
            end
            EnsurePreProdChainSelection()

            local pp_chain_ch, pp_chain_new = r.ImGui_Checkbox(ctx, "Use VO Chain##preprod_chain", params.preprod_chain_enabled)
            if pp_chain_ch then params.preprod_chain_enabled = pp_chain_new end

            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Refresh VO Presets##preprod_refresh", 150, 0) then
                RefreshPreProdChainCache()
                EnsurePreProdChainSelection()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Rescan ResourcePath/FXChains/VO")
            end

            local selected_chain_name = params.preprod_chain_preset
            if selected_chain_name == "" then selected_chain_name = "(no preset found in FXChains/VO)" end
            r.ImGui_SetNextItemWidth(ctx, 300)
            if r.ImGui_BeginCombo(ctx, "VO Chain Preset##preprod_chain_preset", selected_chain_name) then
                for i, entry in ipairs(preprod_chain_cache) do
                    local is_sel = params.preprod_chain_preset == entry.name
                    if r.ImGui_Selectable(ctx, entry.name .. "##preprod_chain_item_" .. i, is_sel) then
                        params.preprod_chain_preset = entry.name
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            local pp_norm_ch, pp_norm_new = r.ImGui_Checkbox(ctx, "Normalize##preprod_norm", params.preprod_normalize_enabled)
            if pp_norm_ch then params.preprod_normalize_enabled = pp_norm_new end

            local norm_unit, norm_unit_idx = GetSelectedNormalizeUnit()
            r.ImGui_SetNextItemWidth(ctx, 105)
            if r.ImGui_BeginCombo(ctx, "Unit##preprod_norm_unit", norm_unit.label) then
                for i, entry in ipairs(NORMALIZE_UNIT_OPTIONS) do
                    local is_sel = norm_unit_idx == i
                    if r.ImGui_Selectable(ctx, entry.label .. "##preprod_norm_unit_item_" .. i, is_sel) then
                        params.preprod_normalize_unit = i
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 115)
            local norm_target_ch, norm_target_new = r.ImGui_InputDouble(ctx, "Target##preprod_norm_target", params.preprod_normalize_target, 0.5, 1.0, "%.2f")
            if norm_target_ch then params.preprod_normalize_target = norm_target_new end

            local norm_mode, norm_mode_idx = GetSelectedNormalizeMode()
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "Mode##preprod_norm_mode", norm_mode.label) then
                for i, entry in ipairs(NORMALIZE_MODE_OPTIONS) do
                    local is_sel = norm_mode_idx == i
                    if r.ImGui_Selectable(ctx, entry.label .. "##preprod_norm_mode_item_" .. i, is_sel) then
                        params.preprod_normalize_mode = i
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            if r.ImGui_Button(ctx, "Normalize Only##preprod_norm_only", 150, 0) then
                RunNormalizeOnly()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Normalize selected items with CalculateNormalization.")
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Reset Vol##preprod_reset_vol", 90, 0) then
                local cnt = r.CountSelectedMediaItems(0)
                if cnt > 0 then
                    r.Undo_BeginBlock()
                    for i = 0, cnt - 1 do
                        local it = r.GetSelectedMediaItem(0, i)
                        local tk = it and r.GetActiveTake(it) or nil
                        if it then r.SetMediaItemInfo_Value(it, "D_VOL", 1.0) end
                        if tk then r.SetMediaItemTakeInfo_Value(tk, "D_VOL", 1.0) end
                    end
                    r.UpdateArrange()
                    r.Undo_EndBlock("Reset Volume to 0dB", -1)
                end
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Reset item and take volume to 0 dB (1.0) for all selected items.")
            end

            r.ImGui_TextColored(ctx, 0xAAAAAAFF, "Folder scope: ResourcePath/FXChains/VO")
            r.ImGui_TextWrapped(ctx, "Bounce normalization uses the same target value set here.")

            r.ImGui_SetNextItemWidth(ctx, 120)
            local wait_apply_ch, wait_apply_new = r.ImGui_SliderDouble(ctx, "Wait after Chain##preprod_wait_apply", params.preprod_wait_before_apply, 0.0, 5.0, "%.2fs")
            if wait_apply_ch then params.preprod_wait_before_apply = wait_apply_new end
            ApplySliderRightClickReset("preprod_wait_before_apply", nil, nil, false)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Pause after adding take FX.")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 120)
            local wait_bounce_ch, wait_bounce_new = r.ImGui_SliderDouble(ctx, "Extra wait##preprod_wait_bounce", params.preprod_wait_before_bounce, 0.0, 5.0, "%.2fs")
            if wait_bounce_ch then params.preprod_wait_before_bounce = wait_bounce_new end
            ApplySliderRightClickReset("preprod_wait_before_bounce", nil, nil, false)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Extra pause before bounce.")
            end

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, "Pre-Prod + Bounce##preprod_run", -1, 0) then
                StartPreProdBounce()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Add chain, bounce, then normalize the bounced result.")
            end
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0xE06010FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF8030FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0xC05008FF)
            if r.ImGui_Button(ctx, "Restore to New Track...##preprod_restore", -1, 0) then
                OpenRestorePopup()
            end
            r.ImGui_PopStyleColor(ctx, 3)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Pick which pre-bounce version (-glued chain) to place on a new track below.")
            end

            -- Version picker modal (opened by OpenRestorePopup)
            if r.ImGui_BeginPopupModal(ctx, "Choose Version##restore_modal", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
                if preprod_restore_popup then
                    r.ImGui_Text(ctx, "Select which version to restore to a new track:")
                    r.ImGui_Spacing(ctx)
                    local tflags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()
                    if r.ImGui_BeginTable(ctx, "restore_ver_tbl", 3, tflags, 520, 0) then
                        r.ImGui_TableSetupColumn(ctx, "Version",  r.ImGui_TableColumnFlags_WidthFixed(), 140)
                        r.ImGui_TableSetupColumn(ctx, "Modified", r.ImGui_TableColumnFlags_WidthFixed(), 135)
                        r.ImGui_TableSetupColumn(ctx, "File",     r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableHeadersRow(ctx)
                        for idx, ver in ipairs(preprod_restore_popup.versions) do
                            r.ImGui_TableNextRow(ctx)
                            r.ImGui_TableSetColumnIndex(ctx, 0)
                            local is_sel = preprod_restore_popup.selected == idx
                            local warn = (not ver.exists) and " (!)" or ""
                            local selectable_no_close = (r.ImGui_SelectableFlags_DontClosePopups and r.ImGui_SelectableFlags_DontClosePopups()) or 1
                            if r.ImGui_Selectable(ctx, ver.label .. warn .. "##vrsel_" .. idx, is_sel, selectable_no_close) then
                                preprod_restore_popup.selected = idx
                            end
                            r.ImGui_TableSetColumnIndex(ctx, 1)
                            r.ImGui_Text(ctx, ver.mtime)
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            r.ImGui_Text(ctx, ver.basename)
                        end
                        r.ImGui_EndTable(ctx)
                    end
                    r.ImGui_Spacing(ctx)
                    if r.ImGui_Button(ctx, "Restore##restore_ok", 120, 0) then
                        local sv = preprod_restore_popup.versions[preprod_restore_popup.selected]
                        if sv and sv.exists then
                            r.Undo_BeginBlock()
                            r.PreventUIRefresh(1)
                            local cnt = DoRestoreItems(preprod_restore_popup.items_ctx, sv.strip_count)
                            r.PreventUIRefresh(-1)
                            r.UpdateArrange()
                            r.Undo_EndBlock("Restore Source Version to New Track", -1)
                            r.ShowConsoleMsg(string.format("[VO Tool] Restore: %d item(s) -> %s\n", cnt, sv.basename))
                            if cnt <= 0 then
                                r.ShowMessageBox("Не вдалося вставити жоден item. Перевір шлях файлу в списку версій та відкрий консоль для деталей.", "VO Tool Restore", 0)
                            else
                                preprod_restore_popup = nil
                                r.ImGui_CloseCurrentPopup(ctx)
                            end
                        else
                            r.ShowMessageBox("Обрана версія файлу не існує на диску.", "VO Tool Restore", 0)
                        end
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Cancel##restore_cancel", 120, 0) then
                        preprod_restore_popup = nil
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                else
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_EndPopup(ctx)
            end

            if preprod_job then
                r.ImGui_TextColored(ctx, 0xFFCC66FF, "PRE-PROD running: " .. tostring(preprod_job.stage))
            end

                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("TIMING & PITCH##sec_timing") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            r.ImGui_SetNextItemWidth(ctx, 140)
            local r_changed, new_rate = r.ImGui_SliderDouble(ctx, "Rate", params.rate, 0.5, 2.0, "%.2fx")
            if r_changed then params.rate = new_rate end
            ApplySliderRightClickReset("rate", ApplyRate, "Reset Rate", true)
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
                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("ITEM SPACING##sec_spacing") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            local real_gap = GetNonLinearSpacing(params.spacing_val, params.spacing_max)
            r.ImGui_Text(ctx, string.format("Item Gap: %.3f sec", real_gap))

            r.ImGui_SetNextItemWidth(ctx, 140)
            local s_changed, new_s = r.ImGui_SliderDouble(ctx, "##GapSlider", params.spacing_val, 0.0, 1.0, "")
            if s_changed then params.spacing_val = new_s end
            ApplySliderRightClickReset("spacing_val", ApplySpacing, "Reset Spacing", true)
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
                ApplySliderRightClickReset("spacing_max_gap", nil, nil, false)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Only group items closer than this distance") end
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Max Gap")
            end

                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("TRIM & FADES##sec_trim") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            if r.ImGui_BeginTable(ctx, "EditTable", 2) then
                r.ImGui_TableSetupColumn(ctx, "C1", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx, "C2", r.ImGui_TableColumnFlags_WidthStretch())

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local ts_ch, new_ts = r.ImGui_SliderDouble(ctx, "Trim Start##trim_start", params.trim_start, -3.0, 3.0, "%.3fs")
                if ts_ch then params.trim_start = new_ts end
                ApplySliderRightClickReset("trim_start", ApplyTrim, "Reset Trim Start", true, true)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Negative extends start, positive trims start") end
                if r.ImGui_IsItemActivated(ctx) then RememberSliderPrevValue("trim_start"); r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyTrim(); if params.auto_regions then UpdateRegions(false) end end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Trim Start", -1) end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local te_ch, new_te = r.ImGui_SliderDouble(ctx, "Trim End##trim_end", params.trim_end, -3.0, 3.0, "%.3fs")
                if te_ch then params.trim_end = new_te end
                ApplySliderRightClickReset("trim_end", ApplyTrim, "Reset Trim End", true, true)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Negative extends end, positive trims end") end
                if r.ImGui_IsItemActivated(ctx) then RememberSliderPrevValue("trim_end"); r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyTrim(); if params.auto_regions then UpdateRegions(false) end end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Trim End", -1) end

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local fi_ch, new_fi = r.ImGui_SliderDouble(ctx, "Fade In", params.fade_in, 0.0, 1.0, "%.3fs")
                if fi_ch then params.fade_in = new_fi end
                ApplySliderRightClickReset("fade_in", ApplyFades, "Reset Fade In", false, true)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Fade in length") end
                if r.ImGui_IsItemActivated(ctx) then RememberSliderPrevValue("fade_in"); r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyFades() end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Fade In", -1) end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local fo_ch, new_fo = r.ImGui_SliderDouble(ctx, "Fade Out", params.fade_out, 0.0, 1.0, "%.3fs")
                if fo_ch then params.fade_out = new_fo end
                ApplySliderRightClickReset("fade_out", ApplyFades, "Reset Fade Out", false, true)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Fade out length") end
                if r.ImGui_IsItemActivated(ctx) then RememberSliderPrevValue("fade_out"); r.Undo_BeginBlock(); SaveItemsState() end
                if r.ImGui_IsItemActive(ctx) then ApplyFades() end
                if r.ImGui_IsItemDeactivated(ctx) then r.Undo_EndBlock("Fade Out", -1) end

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                local fade_shape_labels = {
                    "Linear", "Start/End Slow", "Start/End Fast", "Fast Start", "Fast End", "Bezier", "SCurve"
                }
                r.ImGui_Text(ctx, "Fade In Shape")
                r.ImGui_SetNextItemWidth(ctx, -1)
                if r.ImGui_BeginCombo(ctx, "##fade_in_shape", fade_shape_labels[params.fade_in_shape + 1] or "Linear") then
                    for i = 0, 6 do
                        local selected = params.fade_in_shape == i
                        if r.ImGui_Selectable(ctx, fade_shape_labels[i + 1], selected) then
                            params.fade_in_shape = i
                            r.Undo_BeginBlock(); SaveItemsState(); ApplyFades(); r.Undo_EndBlock("Fade In Shape", -1)
                        end
                        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_Text(ctx, "Fade Out Shape")
                r.ImGui_SetNextItemWidth(ctx, -1)
                if r.ImGui_BeginCombo(ctx, "##fade_out_shape", fade_shape_labels[params.fade_out_shape + 1] or "Linear") then
                    for i = 0, 6 do
                        local selected = params.fade_out_shape == i
                        if r.ImGui_Selectable(ctx, fade_shape_labels[i + 1], selected) then
                            params.fade_out_shape = i
                            r.Undo_BeginBlock(); SaveItemsState(); ApplyFades(); r.Undo_EndBlock("Fade Out Shape", -1)
                        end
                        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end

                r.ImGui_EndTable(ctx)
            end
                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("AUTO-LEVEL (RIDER)##sec_rider") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            local rider_on_ch, rider_on_new = r.ImGui_Checkbox(ctx, "Enable Rider##autolevel_enabled", params.autolevel_enabled)
            if rider_on_ch then params.autolevel_enabled = rider_on_new end

            local detector_opt, detector_idx = GetSelectedAutoLevelDetector()
            r.ImGui_SetNextItemWidth(ctx, 140)
            if r.ImGui_BeginCombo(ctx, "Detector##autolevel_detector", detector_opt.label) then
                for i, entry in ipairs(AUTOLEVEL_DETECTOR_OPTIONS) do
                    local is_sel = detector_idx == i
                    if r.ImGui_Selectable(ctx, entry.label .. "##autolevel_detector_item_" .. i, is_sel) then
                        params.autolevel_detector_mode = i
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            r.ImGui_SameLine(ctx)
            local target_opt, target_idx = GetSelectedAutoLevelTarget()
            r.ImGui_SetNextItemWidth(ctx, 180)
            if r.ImGui_BeginCombo(ctx, "Apply To##autolevel_target", target_opt.label) then
                for i, entry in ipairs(AUTOLEVEL_TARGET_OPTIONS) do
                    local is_sel = target_idx == i
                    if r.ImGui_Selectable(ctx, entry.label .. "##autolevel_target_item_" .. i, is_sel) then
                        params.autolevel_target_env = i
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end

            local gv_changed, gv_new = r.ImGui_Checkbox(ctx, "Show Gate On Env##autolevel_gate_view", params.autolevel_gate_view)
            if gv_changed then params.autolevel_gate_view = gv_new end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Debug view: writes binary gate trace (0 dB open, -Gate Mark dB closed in pauses/silence)")
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 140)
            local gm_changed, gm_new = r.ImGui_SliderDouble(ctx, "Gate Mark##autolevel_gate_mark_db", params.autolevel_gate_mark_db, 0.5, 12.0, "%.1f dB")
            if gm_changed then params.autolevel_gate_mark_db = gm_new end
            ApplySliderRightClickReset("autolevel_gate_mark_db", nil, nil, false)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Depth of binary gate dip in debug view")
            end

            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local col_w = math.max(120, (avail_w - 10) * 0.5)
            local tflags = r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_BordersInnerV()
            local function DrawRiderSlider(label, slider_id, param_key, vmin, vmax, fmt, tooltip)
                r.ImGui_Text(ctx, label)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local changed, new_val = r.ImGui_SliderDouble(ctx, "##" .. slider_id, params[param_key], vmin, vmax, fmt)
                if changed then params[param_key] = new_val end
                ApplySliderRightClickReset(param_key, nil, nil, false)
                if tooltip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
            end
            if r.ImGui_BeginTable(ctx, "rider_params_tbl", 2, tflags, -1, 0) then
                r.ImGui_TableSetupColumn(ctx, "L", r.ImGui_TableColumnFlags_WidthFixed(), col_w)
                r.ImGui_TableSetupColumn(ctx, "R", r.ImGui_TableColumnFlags_WidthFixed(), col_w)

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Target", "autolevel_target_db", "autolevel_target_db", -36.0, -6.0, "%.1f dB", "Desired average voice level")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Tolerance", "autolevel_tolerance_db", "autolevel_tolerance_db", 0.0, 6.0, "%.1f dB", "No correction inside +/- tolerance")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Silence", "autolevel_silence_db", "autolevel_silence_db", -72.0, -24.0, "%.0f dB", "LUFS gate absolute floor (Dolby/EBU-like gate also uses relative threshold = Integrated - 10 LU)")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Slope", "autolevel_slew_dbps", "autolevel_slew_dbps", 4.0, 40.0, "%.1f dB/s", "Maximum rider curve speed to avoid pumping")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Gate Hold", "autolevel_gate_hold_ms", "autolevel_gate_hold_ms", 20.0, 500.0, "%.0f ms", "How long LUFS gate stays open after crossing open threshold")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Gate Close", "autolevel_gate_close_ms", "autolevel_gate_close_ms", 20.0, 500.0, "%.0f ms", "Required continuous under-threshold time before LUFS gate closes")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Window", "autolevel_window_ms", "autolevel_window_ms", 100.0, 3000.0, "%.0f ms", "Loudness measurement window (recommended 400..2000 ms)")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Point Step", "autolevel_point_step_ms", "autolevel_point_step_ms", 10.0, 3000.0, "%.0f ms", "Step between written envelope points")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Lookahead", "autolevel_lookahead_ms", "autolevel_lookahead_ms", 0.0, 250.0, "%.0f ms")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Hold", "autolevel_hold_ms", "autolevel_hold_ms", 0.0, 500.0, "%.0f ms")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Attack", "autolevel_attack_ms", "autolevel_attack_ms", 5.0, 400.0, "%.0f ms")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Release", "autolevel_release_ms", "autolevel_release_ms", 20.0, 1200.0, "%.0f ms")

                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                DrawRiderSlider("Range", "autolevel_range_db", "autolevel_range_db", 1.0, 18.0, "+/-%0.1f dB")
                r.ImGui_TableSetColumnIndex(ctx, 1)
                DrawRiderSlider("Max Up", "autolevel_max_up_db", "autolevel_max_up_db", 0.3, 6.0, "+%.1f dB", "Hard cap for upward rider boost; keeps bumps under control")

                r.ImGui_EndTable(ctx)
            end

            if r.ImGui_Button(ctx, "Write Rider##autolevel_write", 140, 0) then
                RunAutoLevelWrite()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Offline write envelope points over selected items")
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Clear in Selection##autolevel_clear", 170, 0) then
                RunAutoLevelClear()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Delete existing rider points in selected item time range")
            end

            local preset_opt, preset_idx = GetSelectedAutoLevelPreset()
            r.ImGui_SetNextItemWidth(ctx, 190)
            if r.ImGui_BeginCombo(ctx, "Preset##autolevel_preset_combo", preset_opt.label) then
                for i, entry in ipairs(AUTOLEVEL_PRESET_OPTIONS) do
                    local is_sel = preset_idx == i
                    if r.ImGui_Selectable(ctx, entry.label .. "##autolevel_preset_item_" .. i, is_sel) then
                        ApplyAutoLevelPresetByIndex(i)
                    end
                    if is_sel then r.ImGui_SetItemDefaultFocus(ctx) end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Select a rider preset")
            end

            r.ImGui_TextColored(ctx, 0xAAAAAAFF, "Writes to selected target envelope. Supports Track/Trim/Pre-FX/Take Volume.")

                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("ALIGN TAKES##sec_align") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

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
                ApplySliderRightClickReset("heal_gap", nil, nil, false)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Maximum gap to heal") end
            else
                r.ImGui_Spacing(ctx)
                r.ImGui_Text(ctx, "Group Gap")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 200)
                local gap_ch, new_gap = r.ImGui_SliderDouble(ctx, "##AlignGroupGap", params.align_group_gap, 0.1, 5.0, "%.2fs")
                if gap_ch then params.align_group_gap = new_gap end
                ApplySliderRightClickReset("align_group_gap", nil, nil, false)
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Max gap to treat items as one duplicate group") end
            end

            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, "Align##Duplicates", -1, 0) then
                ApplyAlignDuplicates()
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align items by center on separate tracks (Shift+Q)") end

                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()

        r.ImGui_BeginGroup(ctx)
            if DrawSectionHeader("REGIONS##sec_regions") then
                r.ImGui_Indent(ctx, 5)
                r.ImGui_Dummy(ctx, 0, 6)

            r.ImGui_Text(ctx, "New Regions")
            r.ImGui_Spacing(ctx)

            local reg_on_ch, new_reg_on = r.ImGui_Checkbox(ctx, "Auto Live Update", params.auto_regions)
            if reg_on_ch then params.auto_regions = new_reg_on end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Automatically update regions when slider change") end

            r.ImGui_SameLine(ctx)
            local follow_ch, new_follow = r.ImGui_Checkbox(ctx, "Playback by Regions##region_follow", params.region_timeline_follow)
            if follow_ch then params.region_timeline_follow = new_follow end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "When enabled, playback stays inside regions and jumps to the next region")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            local th_ch, new_th = r.ImGui_SliderDouble(ctx, "##MaxSil", params.region_gap_threshold, 0.1, 10.0, "%.1fs")
            if th_ch then params.region_gap_threshold = new_th; if params.auto_regions then r.Undo_BeginBlock(); UpdateRegions(false); r.Undo_EndBlock("Reg Threshold", -1) end end
            ApplySliderRightClickReset("region_gap_threshold", nil, nil, false)
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
                ApplySliderRightClickReset("region_pad_start", nil, nil, false)

                r.ImGui_TableSetColumnIndex(ctx, 1)
                r.ImGui_SetNextItemWidth(ctx, -1)
                local pe_ch, new_pe = r.ImGui_SliderDouble(ctx, "##PadR", params.region_pad_end, 0.0, 1.0, "%.2f")
                if pe_ch then params.region_pad_end = new_pe; if params.auto_regions then r.Undo_BeginBlock(); UpdateRegions(false); r.Undo_EndBlock("Reg Pad", -1) end end
                ApplySliderRightClickReset("region_pad_end", nil, nil, false)

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
            ApplySliderRightClickReset("region_reposition_gap", nil, nil, false)
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Gap between repositioned regions") end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Gap")
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Align", 60, 0) then
                r.Undo_BeginBlock(); ApplyRegionSpacing(); r.Undo_EndBlock("Align Regions", -1)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align selected regions with specified gap") end

                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Unindent(ctx, 5)
            end
        r.ImGui_EndGroup(ctx)
        FinishSection()
        r.ImGui_End(ctx)
    end
    
    -- PopStyleVar and PopStyleColor
    r.ImGui_PopStyleVar(ctx, 15)
    r.ImGui_PopStyleColor(ctx, 32)

    ProcessPreProdJob()

    SaveParamsIfChanged(false)
    
    if open or preprod_job then r.defer(Loop) end
end

LoadParams()
r.defer(Loop)
