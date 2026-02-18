-- @description Post Agent
-- @version 2.3.4
-- @author SBP & AI
-- @about Workflow orchestration agent for film post-production in REAPER. Scans project tracks and items, provides quick-access actions: batch rename, color-code by type, collect empty tracks, mute/solo groups, project reports, cutscene tag management, music cue sheet generator, track templates, gap finder, batch notes editor, and ADR cue sheet generator.
-- @link https://forum.cockos.com/showthread.php?t=301263
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   v2.3.4 - ADR: Line source changed from take name to P_NOTES (sentences in item notes). Added Scene Track field — specify track name for scenes/locations (uses P_NOTES of items on that track) or leave empty to use tags from Cutscene Manager. FIX: Nested track scanning now checks depth <= 0 (includes last child in folder). UI: Tools section more compact — selection buttons in one row
--   v2.3.3 - REFACTOR: Unified rename functionality — added Target toggle (Tag names / Item notes) to main rename section. When "Item notes" is selected, operations apply to P_NOTES of items in tag time range. Removed separate Batch Notes section from Tools (now integrated into main rename workflow). Template mode = Copy Take Name when working with item notes
--   v2.3.2 - UI: Moved manual tag name editor from Tools to directly under tag table for faster access. Auto-saves on edit. Removed redundant P_NOTES section from Tools (functionality covered by Batch Notes + manual editor)
--   v2.3.1 - ADR FIX: Scan nested tracks in DIA/DX/ADR/VO/DUB folders (character names from child track names). Remove text truncation (full line/scene text). UTF-8 BOM in CSV export for Cyrillic support in Excel. Default filter: DIA, DX, ADR, VO, DUB
--   v2.3 - NEW: ADR Cue Sheet Generator — scan DIA/DX/ADR tracks, extract character names from track names, timecodes, dialogue lines from take names, scene context from tags. Navigable cue table with click-to-jump. "Mark for ADR" paints items red + adds ADR prefix to notes. Export CSV (Cue, Character, TC In/Out, Duration, Line, Notes, Scene, Priority). Text report with clipboard copy
--   v2.2 - NEW: Track Template Builder (Film Post/TV/Commercial presets, auto-folders + colors). Gap Finder (find gaps & overlaps by track type, navigate, mark). Batch Notes Editor (prepend/append/find-replace/clear/copy take name on selected items or tag range). FIX: Ctrl/Shift multi-select now uses correct ImGui API
--   v2.1 - Tag Manager UX BOOST: Multi-select tags (Ctrl=toggle, Shift=range). Click color cube to paint instantly. Template: {UN} wildcard for unique name numbering. Tools: "Select Same Name" button (ignores _N suffix). Presets: NEW Custom tab for user wildcards. All batch operations support multi-selection
--   v2.0 - MAJOR UI RESTRUCTURE: Merged Batch Rename, Color-Code, Track Cleanup, Group Tracks into single TRACKS MANAGER section with compact TreeNode sub-sections. Tag Manager: NEW Replace mode (complete name replacement), aligned Find/Replace fields, Clear Name button (X). FIX: Playing mode now auto-selects playing tag. Quick Edit: preset selector and Add/Replace buttons on one line with split alignment
--   v1.9 - UI COMPACT: Rename always visible under tag table, single-line UI (mode+input+button). Preset block: prefix/suffix on one line. FIX: Group Tracks buttons now clickable. Playing mode: added status messages
--   v1.8 - FEATURE: Tag selection modes - Selected | Playing | All. Operations can now target: selected tag, currently playing tag, or all tags. Replaces simple All checkbox with three radio buttons
--   v1.7 - FIX: Music metadata error (GetMediaFileMetadata type check). UI: Solo button now square/orange, tag list always visible with fixed height (10 tags), playback indicator (green arrow), removed redundant tag dropdown
--   v1.6 - CRITICAL FIX: Tags now use P_NOTES instead of take names (matches AmbientGen/Universal Scene Controller workflow). Cutscene Manager: Prefix/suffix moved to Quick Edit Zone preset block, presets now apply auto-numbering
--   v1.5 - Project Report: added sample rate, frame rate, timeline duration, =START/=END markers duration. Cutscene Rename: prefix/suffix options, auto-numbering for duplicates. Tools: Copy Name to Notes button, auto-load notes on tag selection
--   v1.4 - Music Cue Sheet: custom track filter, metadata extraction (Artist/Title/Album from ID3/Vorbis), CSV export with metadata, Close buttons for reports. Cutscene Manager Tools: added H:M:S:F time ruler format button
--   v1.3 - Added Music Cue Sheet generator: smart merge of adjacent/overlapping music cues, export to CSV with name/start/duration, filters unmuted music tracks
--   v1.2 - Improved UI: collapsible sections, expanded track types (DIA, FX, HFX, DES, VCA, VIDEO, PRINTMASTER, #). Group Tracks: toggle mute/solo, show/hide TCP/MCP, scroll to top. Cutscene Manager: track picker for # tracks, quick edit zone with location/scene type presets
--   v1.1 - Added Cutscene Manager: tag scanning, rename (prefix/suffix/find-replace/template with wildcards), coloring (picker/random/by-name), merge, group with context, markers/regions, notes editor, tag overview with navigation
--   v1.0 - Initial release: Project scanner, batch rename, color-coding, track cleanup, group mute/solo, project report

local r = reaper

-- =========================================================
-- DEPENDENCY CHECK
-- =========================================================
if not r.ImGui_CreateContext then
  r.ShowConsoleMsg("Error: ReaImGui is required for Post Agent.\n")
  return
end

local ctx = r.ImGui_CreateContext('SBP_PostAgent_v1')

-- =========================================================
-- COLORS (matched to sbp_ItemFX / sbp_AmbientGen style)
-- =========================================================
local C = {
  BG        = 0x252525FF,
  BG_DARK   = 0x1A1A1AFF,
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
  ACCENT    = 0x2D8C6DFF,
  HEADER    = 0xFF8C6DFF,
}

local EXTSTATE_SECTION = "SBP_PostAgent"

-- =========================================================
-- TRACK TYPE DEFINITIONS
-- =========================================================
local TRACK_TYPES = {
  { key = "DIA",  label = "Dialogues",   color = 0x4A90D9 },
  { key = "DX",   label = "Dialogue",    color = 0x4A90D9 },
  { key = "MX",   label = "Music",       color = 0xD4753F },
  { key = "FX",   label = "FX",          color = 0x2D8C6D },
  { key = "SFX",  label = "SFX",         color = 0x2D8C6D },
  { key = "HFX",  label = "Hard FX",     color = 0x1F6B4F },
  { key = "DES",  label = "Designed FX", color = 0x3AA876 },
  { key = "FOLEY",label = "Foley",       color = 0x8B5CF6 },
  { key = "AMB",  label = "Ambience",    color = 0x6B8E23 },
  { key = "VO",   label = "Voiceover",   color = 0xE06C75 },
  { key = "BG",   label = "Backgrounds", color = 0x56B6C2 },
  { key = "VCA",  label = "VCA",         color = 0xA0A0A0 },
  { key = "AUX",  label = "Aux/Bus",     color = 0x808080 },
  { key = "#",    label = "Utility",     color = 0x505050 },
  { key = "VIDEO",label = "Video",       color = 0xC97F3D },
  { key = "PRINTMASTER", label = "Print Master", color = 0xD4AF37 },
}

-- =========================================================
-- STATE
-- =========================================================
local state = {
  scan_results = nil,
  rename_prefix = "",
  rename_mode = 0,      -- 0=prefix, 1=suffix, 2=replace
  rename_find = "",
  rename_replace = "",
  selected_type_idx = 1,
  report_text = "",
  show_report = false,
  music_report_text = "",
  show_music_report = false,
  music_track_filter = "",  -- comma-separated track names for music search
  music_include_metadata = true,
  music_merged_list = {},   -- cached merged list for CSV export
  status_msg = "",
  status_time = 0,
  -- Cutscene Manager
  cm_tag_tracks_input = "",
  cm_tags = {},
  cm_selected_tag_idx = 0,
  cm_select_mode = 0,           -- 0=Selected, 1=Playing, 2=All
  cm_rename_mode = 0,          -- 0=Prefix, 1=Suffix, 2=Find/Replace, 3=Template, 4=Replace
  cm_rename_text = "",
  cm_rename_find = "",
  cm_rename_replace = "",
  cm_rename_template = "{NAME}_{N}",
  cm_rename_replace_text = "",     -- New name for Replace mode
  cm_rename_prefix_suffix = "",   -- prefix/suffix text for checkbox mode
  cm_rename_is_prefix = true,     -- true=prefix, false=suffix
  cm_rename_auto_number = true,   -- auto-numbering if duplicate names
  cm_color_pick = 0x226757FF,
  cm_merge_mode = 0,           -- 0=Selected, 1=Adjacent
  cm_notes_text = "",
  cm_show_track_picker = false,
  cm_preset_mode = 0,          -- 0=Locations, 1=Scene Types, 2=Custom
  cm_preset_insert_mode = 0,   -- 0=Add, 1=Replace
  cm_quick_edit_idx = -1,      -- -1=none, otherwise tag index for quick edit
  cm_selected_tags = {},       -- Multi-selection support: {[idx] = true}
  cm_template_numbering_mode = 0, -- 0=by item index, 1=by unique name
  cm_custom_input = "",        -- Input field for new custom preset
  cm_rename_target = 0,        -- 0=Tag names (P_NOTES of tags), 1=Item notes (P_NOTES of items in tag range)
  -- Track Template Builder
  tm_template_idx = 0,
  -- Gap Finder
  gf_min_gap = 0.5,
  gf_track_filter_idx = 0,    -- 0=DIA, 1=FOLEY, 2=FX, 3=AMB, 4=All
  gf_results = {},
  gf_selected_result = -1,
  -- ADR Cue Sheet
  adr_track_filter = "DIA, DX, ADR, VO, DUB",
  adr_scene_track = "",       -- Track name for scene/location items (empty = use tags from Cutscene Manager)
  adr_cues = {},              -- scanned ADR cue list
  adr_report_text = "",
  adr_show_report = false,
  adr_selected_cue = -1,
}

local cm_preset_colors = {}
local cm_preset_name_counts = {}  -- Track preset name counts for auto-numbering
local cm_custom_presets = {}      -- Custom user-defined wildcards

-- Preset tags for quick renaming
local LOCATION_PRESETS = {
  "Room", "Corridor", "Street", "Forest", "Car", "Kitchen", "Bathroom", "Office",
  "Bedroom", "Warehouse", "Park", "Bridge", "Alley", "Rooftop", "Basement", "Garage",
  "Store", "Restaurant", "Bar", "Hospital", "School"
}

local SCENE_TYPE_PRESETS = {
  {section = "SCENES", items = {"General", "Motion", "Zoom", "Pan", "Tilt", "Roll", "Flip"}},
  {section = "POSITIONS", items = {"Left", "Right", "Front", "Rear"}},
  {section = "SHOTS", items = {"CU", "MS", "WS", "ECU"}},
  {section = "ANGLES", items = {"45deg", "-45deg", "90deg", "-90deg", "180deg"}},
  {section = "MOTION", items = {"Pass-by", "Static", "Rotate"}},
}

local TRACK_TEMPLATES = {
  {
    name = "Film Post Standard",
    tracks = {
      {prefix = "DIA",   count = 4, folder = true, ch = 2},
      {prefix = "ADR",   count = 2, folder = false, ch = 2},
      {prefix = "FX",    count = 4, folder = true, ch = 2},
      {prefix = "SFX",   count = 2, folder = false, ch = 2},
      {prefix = "HFX",   count = 2, folder = false, ch = 2},
      {prefix = "DES",   count = 2, folder = false, ch = 2},
      {prefix = "FOLEY", count = 4, folder = true, ch = 2},
      {prefix = "AMB",   count = 4, folder = true, ch = 2},
      {prefix = "MX",    count = 2, folder = true, ch = 2},
      {prefix = "VO",    count = 1, folder = false, ch = 2},
      {prefix = "AUX",   count = 2, folder = false, ch = 6},
      {prefix = "VCA",   count = 3, folder = false, ch = 0},
      {prefix = "PRINTMASTER", count = 1, folder = false, ch = 6},
    }
  },
  {
    name = "TV Episodic",
    tracks = {
      {prefix = "DIA",   count = 2, folder = true, ch = 2},
      {prefix = "FX",    count = 2, folder = true, ch = 2},
      {prefix = "FOLEY", count = 2, folder = true, ch = 2},
      {prefix = "AMB",   count = 2, folder = true, ch = 2},
      {prefix = "MX",    count = 2, folder = true, ch = 2},
      {prefix = "AUX",   count = 1, folder = false, ch = 2},
      {prefix = "VCA",   count = 2, folder = false, ch = 0},
      {prefix = "PRINTMASTER", count = 1, folder = false, ch = 2},
    }
  },
  {
    name = "Commercial Spot",
    tracks = {
      {prefix = "DIA",   count = 1, folder = false, ch = 2},
      {prefix = "VO",    count = 1, folder = false, ch = 2},
      {prefix = "FX",    count = 2, folder = false, ch = 2},
      {prefix = "MX",    count = 1, folder = false, ch = 2},
      {prefix = "AMB",   count = 1, folder = false, ch = 2},
      {prefix = "PRINTMASTER", count = 1, folder = false, ch = 2},
    }
  },
}

local GF_TRACK_FILTERS = {"DIA", "FOLEY", "FX", "AMB", "MX", "All"}

-- =========================================================
-- UTILITY FUNCTIONS
-- =========================================================
local function SetStatus(msg)
  state.status_msg = msg
  state.status_time = r.time_precise()
end

local function Clamp(val, lo, hi)
  if val < lo then return lo end
  if val > hi then return hi end
  return val
end

local function ColorToNativeReaper(col)
  return r.ColorToNative(
    (col >> 16) & 0xFF,
    (col >> 8) & 0xFF,
    col & 0xFF
  ) | 0x1000000
end

local function ColorToImGui(col)
  return ((col & 0xFF) << 24) | ((col >> 8 & 0xFF) << 16) | ((col >> 16 & 0xFF) << 8) | 0xFF
end

local function FormatTime(sec)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then
    return string.format("%d:%02d:%05.2f", h, m, s)
  else
    return string.format("%d:%05.2f", m, s)
  end
end

-- =========================================================
-- CUTSCENE MANAGER — UTILITIES
-- =========================================================
local function GetRandomReaperColor()
  local red = math.random(60, 200)
  local green = math.random(60, 200)
  local blue = math.random(60, 200)
  return r.ColorToNative(red, green, blue) | 0x1000000
end

local function ReaperColorToImGui(reaper_color)
  if reaper_color == 0 then return C.TEXT_DIM end
  local r_val, g_val, b_val = r.ColorFromNative(reaper_color & 0xFFFFFF)
  return (r_val << 24) | (g_val << 16) | (b_val << 8) | 0xFF
end

local function ImGuiColorToReaper(imgui_color)
  local r_val = (imgui_color >> 24) & 0xFF
  local g_val = (imgui_color >> 16) & 0xFF
  local b_val = (imgui_color >> 8) & 0xFF
  return r.ColorToNative(r_val, g_val, b_val) | 0x1000000
end

local function GetTagName(item)
  -- CRITICAL: Prioritize P_NOTES (matches AmbientGen/Universal Scene Controller)
  local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  if note ~= "" then return note end
  -- Fallback to take name if P_NOTES is empty
  local take = r.GetActiveTake(item)
  if take then
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if name ~= "" then return name end
  end
  return nil
end

local function IsEmptyItem(item)
  local take = r.GetActiveTake(item)
  if not take then return true end
  local source = r.GetMediaItemTake_Source(take)
  if not source then return true end
  return false
end

local function ParseTrackNames(input)
  local names = {}
  for name in input:gmatch("[^,]+") do
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed ~= "" then table.insert(names, trimmed) end
  end
  return names
end

local function ScanTagTracks()
  local tags = {}
  local track_names = ParseTrackNames(state.cm_tag_tracks_input)
  if #track_names == 0 then
    state.cm_tags = tags
    SetStatus("Enter tag track names first")
    return tags
  end

  for _, track_name in ipairs(track_names) do
    for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      if tn == track_name then
        local count = r.CountTrackMediaItems(tr)
        for j = 0, count - 1 do
          local item = r.GetTrackMediaItem(tr, j)
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
          local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
          local name = GetTagName(item) or string.format("Tag %d", j + 1)
          table.insert(tags, {
            item = item,
            name = name,
            start = pos,
            finish = pos + len,
            color = color,
            track = tr,
            track_name = track_name,
            notes = notes,
          })
        end
        break
      end
    end
  end

  table.sort(tags, function(a, b) return a.start < b.start end)
  state.cm_tags = tags
  SetStatus("Found " .. #tags .. " tags")
  return tags
end

local function GetPlayingTagIdx()
  if r.GetPlayState() & 1 ~= 1 then return -1 end  -- Not playing
  local play_pos = r.GetPlayPosition()
  for i, tag in ipairs(state.cm_tags) do
    if play_pos >= tag.start and play_pos < tag.finish then
      return i - 1  -- Return 0-based index
    end
  end
  return -1  -- No tag at current position
end

local function ShouldProcessTag(tag_idx)
  -- Returns true if tag at tag_idx should be processed based on cm_select_mode
  -- tag_idx is 0-based
  if state.cm_select_mode == 2 then return true end  -- All mode
  if state.cm_select_mode == 0 then  -- Selected mode
    -- Support multi-selection
    if next(state.cm_selected_tags) then
      return state.cm_selected_tags[tag_idx]
    else
      return tag_idx == state.cm_selected_tag_idx
    end
  end
  if state.cm_select_mode == 1 then  -- Playing mode
    return tag_idx == GetPlayingTagIdx()
  end
  return false
end

local function MergeTagItems(items)
  if #items < 2 then return 0 end
  -- фильтруем невалидные указатели
  local valid = {}
  for _, item in ipairs(items) do
    if r.ValidatePtr(item, "MediaItem*") then
      table.insert(valid, item)
    end
  end
  if #valid < 2 then return 0 end

  local min_start, max_end = math.huge, -math.huge
  local first_item = nil

  for _, item in ipairs(valid) do
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if pos < min_start then
      min_start = pos
      first_item = item
    end
    if pos + len > max_end then max_end = pos + len end
  end

  r.SetMediaItemInfo_Value(first_item, "D_POSITION", min_start)
  r.SetMediaItemInfo_Value(first_item, "D_LENGTH", max_end - min_start)

  local deleted = 0
  for _, item in ipairs(valid) do
    if item ~= first_item then
      local track = r.GetMediaItem_Track(item)
      if track then r.DeleteTrackMediaItem(track, item) end
      deleted = deleted + 1
    end
  end
  return deleted
end

local function ExpandTemplate(template, tag_name, index, item, unique_num)
  local result = template
  result = result:gsub("{NAME}", tag_name or "")
  result = result:gsub("{N}", tostring(index or 0))
  result = result:gsub("{N2}", string.format("%02d", index or 0))
  result = result:gsub("{N3}", string.format("%03d", index or 0))
  result = result:gsub("{UN}", tostring(unique_num or index or 0))  -- Unique numbering
  result = result:gsub("{UN2}", string.format("%02d", unique_num or index or 0))
  result = result:gsub("{UN3}", string.format("%03d", unique_num or index or 0))

  -- Custom wildcards from cm_custom_presets
  for wildcard, value in pairs(cm_custom_presets) do
    result = result:gsub("{" .. wildcard .. "}", value)
  end

  if item then
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local h = math.floor(pos / 3600)
    local m = math.floor((pos % 3600) / 60)
    local s = math.floor(pos % 60)
    local f = math.floor((pos % 1) * 24)
    result = result:gsub("{TC}", string.format("%02d:%02d:%02d:%02d", h, m, s, f))
    result = result:gsub("{TIME}", string.format("%02d:%05.2f", math.floor(pos / 60), pos % 60))
  end
  return result
end

local function SaveTagColors()
  local parts = {}
  for name, color in pairs(cm_preset_colors) do
    table.insert(parts, name .. "=" .. string.format("%08X", color))
  end
  r.SetExtState(EXTSTATE_SECTION, "cm_tag_colors", table.concat(parts, ";"), true)
end

local function LoadTagColors()
  local s = r.GetExtState(EXTSTATE_SECTION, "cm_tag_colors")
  if s == "" then return end
  for name, hex in s:gmatch("([^=;]+)=(%x+)") do
    cm_preset_colors[name] = tonumber(hex, 16)
  end
end

local function SaveCustomPresets()
  local parts = {}
  for _, preset in ipairs(cm_custom_presets) do
    table.insert(parts, preset)
  end
  r.SetExtState(EXTSTATE_SECTION, "cm_custom_presets", table.concat(parts, ";"), true)
end

local function LoadCustomPresets()
  local s = r.GetExtState(EXTSTATE_SECTION, "cm_custom_presets")
  if s == "" then return end
  cm_custom_presets = {}
  for preset in s:gmatch("[^;]+") do
    table.insert(cm_custom_presets, preset)
  end
end

local function NavigateToTag(tag)
  r.SetEditCurPos(tag.start, false, false)
  local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
  local view_len = end_time - start_time
  local new_start = tag.start - view_len * 0.1
  if new_start < 0 then new_start = 0 end
  r.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_start + view_len)
  r.Main_OnCommand(40289, 0) -- deselect all items
  r.SetMediaItemSelected(tag.item, true)
  r.UpdateArrange()
end

-- =========================================================
-- PROJECT SCANNER
-- =========================================================
local function ScanProject()
  local results = {
    total_tracks = 0,
    empty_tracks = {},
    muted_tracks = {},
    solo_tracks = {},
    total_items = 0,
    total_length = 0,
    tracks_by_type = {},
    track_list = {},
  }

  local num_tracks = r.CountTracks(0)
  if num_tracks == 0 then
    SetStatus("No tracks in project")
    return results
  end

  results.total_tracks = num_tracks

  for i = 0, num_tracks - 1 do
    local track = r.GetTrack(0, i)
    local _, name = r.GetTrackName(track)
    local item_count = r.CountTrackMediaItems(track)
    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

    local track_info = {
      track = track,
      name = name,
      index = i + 1,
      item_count = item_count,
      is_muted = is_muted,
      is_solo = is_solo,
      depth = depth,
    }

    table.insert(results.track_list, track_info)

    if item_count == 0 then
      table.insert(results.empty_tracks, track_info)
    end

    if is_muted then
      table.insert(results.muted_tracks, track_info)
    end

    if is_solo then
      table.insert(results.solo_tracks, track_info)
    end

    results.total_items = results.total_items + item_count

    -- Classify by prefix
    local upper_name = name:upper()
    local classified = false
    for _, ttype in ipairs(TRACK_TYPES) do
      if upper_name:find(ttype.key) then
        if not results.tracks_by_type[ttype.key] then
          results.tracks_by_type[ttype.key] = {}
        end
        table.insert(results.tracks_by_type[ttype.key], track_info)
        classified = true
        break
      end
    end
    if not classified then
      if not results.tracks_by_type["OTHER"] then
        results.tracks_by_type["OTHER"] = {}
      end
      table.insert(results.tracks_by_type["OTHER"], track_info)
    end

    -- Sum item lengths
    for j = 0, item_count - 1 do
      local item = r.GetTrackMediaItem(track, j)
      results.total_length = results.total_length + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
  end

  state.scan_results = results
  SetStatus("Project scanned: " .. num_tracks .. " tracks, " .. results.total_items .. " items")
  return results
end

-- =========================================================
-- BATCH RENAME
-- =========================================================
local function BatchRenameSelected()
  local count = r.CountSelectedTracks(0)
  if count == 0 then
    SetStatus("No tracks selected")
    return
  end

  r.Undo_BeginBlock()

  for i = 0, count - 1 do
    local track = r.GetSelectedTrack(0, i)
    local _, name = r.GetTrackName(track)

    local new_name = name
    if state.rename_mode == 0 and state.rename_prefix ~= "" then
      new_name = state.rename_prefix .. name
    elseif state.rename_mode == 1 and state.rename_prefix ~= "" then
      new_name = name .. state.rename_prefix
    elseif state.rename_mode == 2 and state.rename_find ~= "" then
      new_name = name:gsub(state.rename_find, state.rename_replace)
    end

    r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
  end

  r.Undo_EndBlock("Post Agent: Batch Rename", -1)
  SetStatus("Renamed " .. count .. " tracks")

  if state.scan_results then ScanProject() end
end

-- =========================================================
-- COLOR-CODE TRACKS
-- =========================================================
local function ColorCodeTracks()
  local num_tracks = r.CountTracks(0)
  if num_tracks == 0 then
    SetStatus("No tracks in project")
    return
  end

  r.Undo_BeginBlock()
  local colored = 0

  for i = 0, num_tracks - 1 do
    local track = r.GetTrack(0, i)
    local _, name = r.GetTrackName(track)
    local upper_name = name:upper()

    for _, ttype in ipairs(TRACK_TYPES) do
      if upper_name:find(ttype.key) then
        r.SetTrackColor(track, ColorToNativeReaper(ttype.color))
        colored = colored + 1
        break
      end
    end
  end

  r.Undo_EndBlock("Post Agent: Color-Code Tracks", -1)
  SetStatus("Color-coded " .. colored .. " tracks")
end

-- =========================================================
-- COLOR SELECTED TRACKS BY TYPE
-- =========================================================
local function ColorSelectedByType()
  local count = r.CountSelectedTracks(0)
  if count == 0 then
    SetStatus("No tracks selected")
    return
  end

  local ttype = TRACK_TYPES[state.selected_type_idx]
  if not ttype then return end

  r.Undo_BeginBlock()

  local native_color = ColorToNativeReaper(ttype.color)

  for i = 0, count - 1 do
    local track = r.GetSelectedTrack(0, i)
    r.SetTrackColor(track, native_color)
  end

  r.Undo_EndBlock("Post Agent: Color Selected", -1)
  SetStatus("Colored " .. count .. " tracks as " .. ttype.label)
end

-- =========================================================
-- TRACK CLEANUP
-- =========================================================
local function SelectEmptyTracks()
  if not state.scan_results then ScanProject() end
  local results = state.scan_results

  if #results.empty_tracks == 0 then
    SetStatus("No empty tracks found")
    return
  end

  r.Undo_BeginBlock()

  -- Deselect all
  for i = 0, r.CountTracks(0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end

  -- Select empty tracks
  for _, info in ipairs(results.empty_tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      r.SetTrackSelected(info.track, true)
    end
  end

  r.Undo_EndBlock("Post Agent: Select Empty Tracks", -1)
  SetStatus("Selected " .. #results.empty_tracks .. " empty tracks")
end

local function DeleteEmptyTracks()
  if not state.scan_results then ScanProject() end
  local results = state.scan_results

  if #results.empty_tracks == 0 then
    SetStatus("No empty tracks to delete")
    return
  end

  r.Undo_BeginBlock()

  -- Delete from end to keep indices valid
  local deleted = 0
  for i = #results.empty_tracks, 1, -1 do
    local info = results.empty_tracks[i]
    if r.ValidatePtr(info.track, "MediaTrack*") then
      -- Skip folder parents that may contain child tracks
      local depth = r.GetMediaTrackInfo_Value(info.track, "I_FOLDERDEPTH")
      if depth <= 0 then
        r.DeleteTrack(info.track)
        deleted = deleted + 1
      end
    end
  end

  r.Undo_EndBlock("Post Agent: Delete Empty Tracks", -1)
  SetStatus("Deleted " .. deleted .. " empty tracks")
  ScanProject()
end

-- =========================================================
-- GROUP MUTE / SOLO
-- =========================================================
local function MuteTracksByType(type_key, mute_val)
  if not state.scan_results then ScanProject() end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then
    SetStatus("No " .. type_key .. " tracks found")
    return
  end

  r.Undo_BeginBlock()

  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(info.track, "B_MUTE", mute_val)
    end
  end

  r.Undo_EndBlock("Post Agent: " .. (mute_val == 1 and "Mute" or "Unmute") .. " " .. type_key, -1)
  SetStatus((mute_val == 1 and "Muted" or "Unmuted") .. " " .. type_key .. " tracks (" .. #tracks .. ")")
  ScanProject()
end

local function SoloTracksByType(type_key, solo_val)
  if not state.scan_results then ScanProject() end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then
    SetStatus("No " .. type_key .. " tracks found")
    return
  end

  r.Undo_BeginBlock()

  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(info.track, "I_SOLO", solo_val)
    end
  end

  r.Undo_EndBlock("Post Agent: " .. (solo_val > 0 and "Solo" or "Unsolo") .. " " .. type_key, -1)
  SetStatus((solo_val > 0 and "Soloed" or "Unsoloed") .. " " .. type_key .. " tracks (" .. #tracks .. ")")
  ScanProject()
end

local function UnmuteAll()
  r.Undo_BeginBlock()
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
  end
  r.Undo_EndBlock("Post Agent: Unmute All", -1)
  SetStatus("Unmuted all tracks")
  if state.scan_results then ScanProject() end
end

local function UnsoloAll()
  r.Undo_BeginBlock()
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
  end
  r.Undo_EndBlock("Post Agent: Unsolo All", -1)
  SetStatus("Unsoloed all tracks")
  if state.scan_results then ScanProject() end
end

-- =========================================================
-- PROJECT REPORT
-- =========================================================
local function GenerateReport()
  if not state.scan_results then ScanProject() end
  local res = state.scan_results

  -- Get project settings
  local samplerate = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local timeline_end = r.GetProjectLength(0)

  -- Get FPS from project settings
  local _, fps_num, fps_denom = r.TimeMap_curFrameRate(0)
  local fps = 25 -- default
  if fps_num and fps_denom and fps_denom > 0 then
    fps = fps_num / fps_denom
  end

  -- Get =START and =END markers
  local start_marker_pos = nil
  local end_marker_pos = nil
  local num_markers = r.CountProjectMarkers(0)
  for i = 0, num_markers - 1 do
    local _, _, pos, _, name, _ = r.EnumProjectMarkers(i)
    if name == "=START" then start_marker_pos = pos end
    if name == "=END" then end_marker_pos = pos end
  end

  local lines = {}
  table.insert(lines, "=== Post AGENT PROJECT REPORT ===")
  table.insert(lines, "Project: " .. (r.GetProjectName(0) ~= "" and r.GetProjectName(0) or "(untitled)"))
  table.insert(lines, "Date: " .. os.date("%Y-%m-%d %H:%M"))
  table.insert(lines, "")
  table.insert(lines, "PROJECT SETTINGS:")
  table.insert(lines, "  Sample Rate: " .. string.format("%.0f Hz", samplerate))
  table.insert(lines, "  Frame Rate: " .. string.format("%.2f fps", fps))
  table.insert(lines, "  Timeline Duration: " .. FormatTime(timeline_end))
  if start_marker_pos and end_marker_pos then
    local marker_duration = end_marker_pos - start_marker_pos
    table.insert(lines, "  =START to =END: " .. FormatTime(marker_duration) ..
      " (" .. FormatTime(start_marker_pos) .. " - " .. FormatTime(end_marker_pos) .. ")")
  elseif start_marker_pos then
    table.insert(lines, "  =START marker: " .. FormatTime(start_marker_pos))
  elseif end_marker_pos then
    table.insert(lines, "  =END marker: " .. FormatTime(end_marker_pos))
  end
  table.insert(lines, "")
  table.insert(lines, "SUMMARY:")
  table.insert(lines, "  Total Tracks: " .. res.total_tracks)
  table.insert(lines, "  Total Items:  " .. res.total_items)
  table.insert(lines, "  Total Content Length: " .. FormatTime(res.total_length))
  table.insert(lines, "  Empty Tracks: " .. #res.empty_tracks)
  table.insert(lines, "  Muted Tracks: " .. #res.muted_tracks)
  table.insert(lines, "  Solo Tracks:  " .. #res.solo_tracks)
  table.insert(lines, "")

  table.insert(lines, "TRACKS BY TYPE:")
  for _, ttype in ipairs(TRACK_TYPES) do
    local tracks = res.tracks_by_type[ttype.key]
    local count = tracks and #tracks or 0
    table.insert(lines, "  " .. ttype.label .. " (" .. ttype.key .. "): " .. count)
  end
  local other = res.tracks_by_type["OTHER"]
  table.insert(lines, "  Other: " .. (other and #other or 0))
  table.insert(lines, "")

  if #res.empty_tracks > 0 then
    table.insert(lines, "EMPTY TRACKS:")
    for _, info in ipairs(res.empty_tracks) do
      table.insert(lines, "  [" .. info.index .. "] " .. info.name)
    end
    table.insert(lines, "")
  end

  if #res.muted_tracks > 0 then
    table.insert(lines, "MUTED TRACKS:")
    for _, info in ipairs(res.muted_tracks) do
      table.insert(lines, "  [" .. info.index .. "] " .. info.name)
    end
    table.insert(lines, "")
  end

  table.insert(lines, "================================")

  state.report_text = table.concat(lines, "\n")
  state.show_report = true
  SetStatus("Report generated")
end

-- =========================================================
-- MUSIC CUE SHEET REPORT
-- =========================================================
local function GenerateMusicReport()
  -- 1. Parse track filter if provided
  local filter_tracks = {}
  if state.music_track_filter ~= "" then
    local names = ParseTrackNames(state.music_track_filter)
    for _, name in ipairs(names) do
      filter_tracks[name] = true
    end
  end

  -- 2. Collect all non-muted audio items from project
  local items = {}
  local total_items = r.CountMediaItems(0)

  for i = 0, total_items - 1 do
    local item = r.GetMediaItem(0, i)

    -- Skip muted items
    local is_muted = r.GetMediaItemInfo_Value(item, "B_MUTE")
    if is_muted == 0 then
      local take = r.GetActiveTake(item)
      if take then
        local track = r.GetMediaItem_Track(item)
        local _, track_name = r.GetTrackName(track)

        -- Check if track matches filter (if filter is set)
        local track_matches = false
        if state.music_track_filter == "" then
          -- No filter - auto-detect music tracks
          track_matches = track_name:upper():find("MX") or track_name:upper():find("MUSIC")
        else
          -- Use filter
          track_matches = filter_tracks[track_name] ~= nil
        end

        if track_matches or (state.music_track_filter == "" and total_items < 100) then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local end_pos = pos + len

          -- Get name and source file for identification
          local name = r.GetTakeName(take)
          local source = r.GetMediaItemTake_Source(take)
          local filename = r.GetMediaSourceFileName(source)

          if filename == "" then filename = name end

          -- Get metadata if enabled
          local artist = ""
          local title = ""
          local album = ""
          if state.music_include_metadata and source then
            local meta = r.GetMediaFileMetadata(source, "ID3:ARTIST")
            artist = (type(meta) == "string" and meta ~= "") and meta or ""
            if artist == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:ARTIST")
              artist = (type(meta) == "string" and meta ~= "") and meta or ""
            end

            meta = r.GetMediaFileMetadata(source, "ID3:TITLE")
            title = (type(meta) == "string" and meta ~= "") and meta or ""
            if title == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:TITLE")
              title = (type(meta) == "string" and meta ~= "") and meta or ""
            end

            meta = r.GetMediaFileMetadata(source, "ID3:ALBUM")
            album = (type(meta) == "string" and meta ~= "") and meta or ""
            if album == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:ALBUM")
              album = (type(meta) == "string" and meta ~= "") and meta or ""
            end
          end

          table.insert(items, {
            name = name,
            source_id = filename,
            start = pos,
            len = len,
            end_pos = end_pos,
            is_music = track_matches,
            artist = artist,
            title = title,
            album = album
          })
        end
      end
    end
  end

  if #items == 0 then
    state.music_report_text = "No audio items found in specified tracks."
    state.show_music_report = true
    SetStatus("No audio items to report")
    return
  end

  -- If no filter was set and no music tracks found, include all items
  if state.music_track_filter == "" and #items == 0 then
    for i = 0, total_items - 1 do
      local item = r.GetMediaItem(0, i)
      local is_muted = r.GetMediaItemInfo_Value(item, "B_MUTE")
      if is_muted == 0 then
        local take = r.GetActiveTake(item)
        if take then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local end_pos = pos + len
          local name = r.GetTakeName(take)
          local source = r.GetMediaItemTake_Source(take)
          local filename = r.GetMediaSourceFileName(source)
          if filename == "" then filename = name end

          local artist = ""
          local title = ""
          local album = ""
          if state.music_include_metadata and source then
            local meta = r.GetMediaFileMetadata(source, "ID3:ARTIST")
            artist = (type(meta) == "string" and meta ~= "") and meta or ""
            if artist == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:ARTIST")
              artist = (type(meta) == "string" and meta ~= "") and meta or ""
            end

            meta = r.GetMediaFileMetadata(source, "ID3:TITLE")
            title = (type(meta) == "string" and meta ~= "") and meta or ""
            if title == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:TITLE")
              title = (type(meta) == "string" and meta ~= "") and meta or ""
            end

            meta = r.GetMediaFileMetadata(source, "ID3:ALBUM")
            album = (type(meta) == "string" and meta ~= "") and meta or ""
            if album == "" then
              meta = r.GetMediaFileMetadata(source, "VORBIS:ALBUM")
              album = (type(meta) == "string" and meta ~= "") and meta or ""
            end
          end

          table.insert(items, {
            name = name, source_id = filename, start = pos, len = len,
            end_pos = end_pos, is_music = true,
            artist = artist, title = title, album = album
          })
        end
      end
    end
  end

  -- 2. Sort by start time
  table.sort(items, function(a, b) return a.start < b.start end)

  -- 3. Smart merge - combine adjacent/overlapping items from same source
  local merged_list = {}
  if #items > 0 then
    table.insert(merged_list, items[1])

    for i = 2, #items do
      local current = items[i]
      local last = merged_list[#merged_list]

      -- Merge if: same source AND (adjacent OR overlapping)
      local same_source = (current.source_id == last.source_id)
      local is_adjacent = (current.start <= (last.end_pos + 0.1)) -- 0.1s tolerance for crossfades

      if same_source and is_adjacent then
        -- Extend if current ends later than previous
        if current.end_pos > last.end_pos then
          last.end_pos = current.end_pos
          last.len = last.end_pos - last.start
        end
      else
        -- New track
        table.insert(merged_list, current)
      end
    end
  end

  -- 4. Generate report
  local lines = {}
  table.insert(lines, "=== MUSIC CUE SHEET ===")
  table.insert(lines, "Project: " .. (r.GetProjectName(0) ~= "" and r.GetProjectName(0) or "(untitled)"))
  table.insert(lines, "Date: " .. os.date("%Y-%m-%d %H:%M"))
  table.insert(lines, "Total Cues: " .. #merged_list)
  table.insert(lines, "")

  if state.music_include_metadata then
    table.insert(lines, string.format("%-30s %-20s %-20s %-12s %-12s", "Name", "Artist", "Title", "Start", "Duration"))
    table.insert(lines, string.rep("-", 94))
  else
    table.insert(lines, string.format("%-40s %-12s %-12s", "Name", "Start", "Duration"))
    table.insert(lines, string.rep("-", 64))
  end

  local total_duration = 0
  for _, item in ipairs(merged_list) do
    local t_start = FormatTime(item.start)
    local t_dur = FormatTime(item.len)

    if state.music_include_metadata then
      local artist = item.artist ~= "" and item.artist or "-"
      local title = item.title ~= "" and item.title or "-"
      table.insert(lines, string.format("%-30s %-20s %-20s %-12s %-12s",
        item.name:sub(1, 30), artist:sub(1, 20), title:sub(1, 20), t_start, t_dur))
    else
      table.insert(lines, string.format("%-40s %-12s %-12s",
        item.name:sub(1, 40), t_start, t_dur))
    end
    total_duration = total_duration + item.len
  end

  if state.music_include_metadata then
    table.insert(lines, string.rep("-", 94))
    table.insert(lines, string.format("%-30s %-20s %-20s %-12s %-12s",
      "TOTAL:", "", "", "", FormatTime(total_duration)))
  else
    table.insert(lines, string.rep("-", 64))
    table.insert(lines, string.format("%-40s %-12s %-12s",
      "TOTAL:", "", FormatTime(total_duration)))
  end

  table.insert(lines, "")
  table.insert(lines, "================================")

  state.music_report_text = table.concat(lines, "\n")
  state.show_music_report = true
  state.music_merged_list = merged_list  -- Cache for CSV export
  SetStatus("Music report generated: " .. #merged_list .. " cues")
end

local function ExportMusicCSV()
  if #state.music_merged_list == 0 then
    SetStatus("Generate music report first")
    return
  end

  -- Generate CSV from cached merged list
  local csv_content
  if state.music_include_metadata then
    csv_content = "Name,Artist,Title,Album,Start,Duration\n"
  else
    csv_content = "Name,Start,Duration\n"
  end

  for _, item in ipairs(state.music_merged_list) do
    local safe_name = item.name:gsub('"', '""')
    if safe_name:find(",") then safe_name = '"' .. safe_name .. '"' end

    local t_start = FormatTime(item.start)
    local t_dur = FormatTime(item.len)

    if state.music_include_metadata then
      local artist = item.artist or ""
      local title = item.title or ""
      local album = item.album or ""
      -- Escape CSV values
      artist = artist:gsub('"', '""')
      title = title:gsub('"', '""')
      album = album:gsub('"', '""')
      if artist:find(",") then artist = '"' .. artist .. '"' end
      if title:find(",") then title = '"' .. title .. '"' end
      if album:find(",") then album = '"' .. album .. '"' end

      csv_content = csv_content .. string.format("%s,%s,%s,%s,%s,%s\n",
        safe_name, artist, title, album, t_start, t_dur)
    else
      csv_content = csv_content .. string.format("%s,%s,%s\n", safe_name, t_start, t_dur)
    end
  end

  -- Save to project directory
  local proj_path = r.GetProjectPath()
  if proj_path == "" then
    SetStatus("Save project first")
    return
  end

  local os_sep = package.config:sub(1,1)
  local filepath = proj_path .. os_sep .. "Music_Cue_Sheet.csv"

  local file = io.open(filepath, "w")
  if file then
    file:write(csv_content)
    file:close()
    SetStatus("CSV exported: Music_Cue_Sheet.csv")
    r.MB("File saved:\n" .. filepath, "Music Cue Sheet Exported", 0)
  else
    SetStatus("Failed to create CSV file")
  end
end

-- =========================================================
-- ADR CUE SHEET
-- =========================================================
local function FormatTimecode(sec)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  local f = math.floor((sec % 1) * 25) -- 25fps default
  return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

local function GenerateADRSheet()
  -- Parse track filter (added VO, DUB)
  local filter_names = ParseTrackNames(state.adr_track_filter)
  local filter_map = {}
  for _, name in ipairs(filter_names) do
    filter_map[name:upper()] = true
  end

  state.adr_cues = {}
  local num_tracks = r.CountTracks(0)

  for t = 0, num_tracks - 1 do
    local track = r.GetTrack(0, t)
    local _, track_name = r.GetTrackName(track)
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

    -- Check if track OR its parent folder matches filter
    local match = false
    local parent_track = nil
    local parent_name = ""

    -- Check direct match
    for filter_key, _ in pairs(filter_map) do
      if track_name:upper():sub(1, #filter_key) == filter_key then
        match = true
        break
      end
    end

    -- Check parent folder if this is a child track
    if not match and depth <= 0 then  -- depth = 0 (normal child) or -1 (last child in folder)
      -- Walk up to find parent folder
      local parent_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 2 -- -1 for 1-based, -1 more to get parent
      if parent_idx >= 0 then
        parent_track = r.GetTrack(0, parent_idx)
        if parent_track then
          local parent_depth = r.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH")
          if parent_depth == 1 then -- Is a folder parent
            _, parent_name = r.GetTrackName(parent_track)
            for filter_key, _ in pairs(filter_map) do
              if parent_name:upper():sub(1, #filter_key) == filter_key then
                match = true
                break
              end
            end
          end
        end
      end
    end

    if match then
      local item_count = r.CountTrackMediaItems(track)
      for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local is_muted = r.GetMediaItemInfo_Value(item, "B_MUTE")
        if is_muted == 0 then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
          local color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))

          -- Get dialogue line from P_NOTES
          local line = notes

          -- Extract character name:
          -- If track is child of DIA/DX/ADR folder, use child track name as character
          -- Otherwise extract from track name after prefix
          local character = track_name
          if parent_name ~= "" then
            -- Child track — use full track name as character
            character = track_name
          else
            -- Direct track with prefix — extract after underscore
            local prefix_end = track_name:find("_")
            if prefix_end then
              character = track_name:sub(prefix_end + 1)
            end
          end

          -- Find scene context from scene track or tags
          local scene = ""
          if state.adr_scene_track ~= "" then
            -- Use specified scene track
            for s = 0, num_tracks - 1 do
              local scene_track = r.GetTrack(0, s)
              local _, scene_track_name = r.GetTrackName(scene_track)
              if scene_track_name == state.adr_scene_track then
                -- Find item on scene track that overlaps with ADR item position
                local scene_item_count = r.CountTrackMediaItems(scene_track)
                for si = 0, scene_item_count - 1 do
                  local scene_item = r.GetTrackMediaItem(scene_track, si)
                  local scene_pos = r.GetMediaItemInfo_Value(scene_item, "D_POSITION")
                  local scene_len = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
                  if pos >= scene_pos and pos < (scene_pos + scene_len) then
                    -- Get scene name from P_NOTES of scene item
                    local _, scene_notes = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
                    scene = scene_notes
                    break
                  end
                end
                break
              end
            end
          else
            -- Use tags from Cutscene Manager (original behavior)
            if #state.cm_tags > 0 then
              for _, tag in ipairs(state.cm_tags) do
                if pos >= tag.start and pos < tag.finish then
                  scene = tag.name
                  break
                end
              end
            end
          end

          -- Determine if marked for ADR (red-ish color or notes contain "ADR")
          local is_adr_marked = notes:upper():find("ADR") ~= nil
          local priority = is_adr_marked and "HIGH" or ""

          table.insert(state.adr_cues, {
            item = item,
            track = track,
            character = character,
            track_name = track_name,
            tc_in = pos,
            tc_out = pos + len,
            duration = len,
            line = line,
            notes = notes,
            scene = scene,
            priority = priority,
            color = color,
          })
        end
      end
    end
  end

  -- Sort by timecode
  table.sort(state.adr_cues, function(a, b) return a.tc_in < b.tc_in end)

  -- Generate text report
  local lines = {}
  table.insert(lines, "=== ADR CUE SHEET ===")
  table.insert(lines, "Project: " .. (r.GetProjectName(0) ~= "" and r.GetProjectName(0) or "(untitled)"))
  table.insert(lines, "Date: " .. os.date("%Y-%m-%d %H:%M"))
  table.insert(lines, string.format("Total cues: %d", #state.adr_cues))
  table.insert(lines, "")
  table.insert(lines, string.format("%-4s %-20s %-14s %-14s %-8s %-50s %-20s %-8s",
    "#", "Character", "TC In", "TC Out", "Dur", "Line", "Scene", "Priority"))
  table.insert(lines, string.rep("-", 140))

  for i, cue in ipairs(state.adr_cues) do
    table.insert(lines, string.format("%-4d %-20s %-14s %-14s %-8s %-50s %-20s %-8s",
      i, cue.character,
      FormatTimecode(cue.tc_in), FormatTimecode(cue.tc_out),
      FormatTime(cue.duration),
      cue.line, cue.scene, cue.priority))
  end

  state.adr_report_text = table.concat(lines, "\n")
  state.adr_show_report = true
  state.adr_selected_cue = -1
  SetStatus(string.format("ADR Sheet: %d cues found", #state.adr_cues))
end

local function MarkItemsForADR()
  local cnt = r.CountSelectedMediaItems(0)
  if cnt == 0 then SetStatus("Select items to mark for ADR"); return end

  r.Undo_BeginBlock()
  local marked = 0
  local adr_color = r.ColorToNative(200, 60, 60) | 0x1000000 -- Red tint

  for i = 0, cnt - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

    -- Add ADR prefix to notes if not already there
    if not notes:upper():find("ADR") then
      local new_notes = notes == "" and "ADR" or ("ADR: " .. notes)
      r.GetSetMediaItemInfo_String(item, "P_NOTES", new_notes, true)
    end

    -- Set red color
    r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", adr_color)
    marked = marked + 1
  end

  r.Undo_EndBlock("Post Agent: Mark for ADR", -1)
  r.UpdateArrange()
  SetStatus(string.format("Marked %d item(s) for ADR", marked))
end

local function ExportADRCSV()
  if #state.adr_cues == 0 then
    SetStatus("Generate ADR sheet first"); return
  end

  -- UTF-8 BOM for Excel compatibility with Cyrillic
  local csv = "\239\187\191" -- UTF-8 BOM (EF BB BF)
  csv = csv .. "Cue,Character,TC_In,TC_Out,Duration,Line,Notes,Scene,Priority\n"

  for i, cue in ipairs(state.adr_cues) do
    local function esc(s)
      s = s:gsub('"', '""')
      if s:find('[,\n"]') then s = '"' .. s .. '"' end
      return s
    end
    csv = csv .. string.format("%d,%s,%s,%s,%s,%s,%s,%s,%s\n",
      i,
      esc(cue.character),
      FormatTimecode(cue.tc_in),
      FormatTimecode(cue.tc_out),
      FormatTime(cue.duration),
      esc(cue.line),
      esc(cue.notes),
      esc(cue.scene),
      esc(cue.priority))
  end

  local proj_path = r.GetProjectPath()
  if proj_path == "" then SetStatus("Save project first"); return end

  local os_sep = package.config:sub(1, 1)
  local filepath = proj_path .. os_sep .. "ADR_Cue_Sheet.csv"

  local file = io.open(filepath, "wb") -- Binary mode to preserve BOM
  if file then
    file:write(csv)
    file:close()
    SetStatus("CSV exported: ADR_Cue_Sheet.csv")
    r.MB("File saved:\n" .. filepath, "ADR Cue Sheet Exported", 0)
  else
    SetStatus("Failed to create CSV file")
  end
end

local function NavigateToADRCue(idx)
  if idx < 0 or idx >= #state.adr_cues then return end
  local cue = state.adr_cues[idx + 1]
  r.SetEditCurPos(cue.tc_in, false, false)
  local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
  local view_len = end_time - start_time
  local new_start = cue.tc_in - view_len * 0.1
  if new_start < 0 then new_start = 0 end
  r.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_start + view_len)
  r.Main_OnCommand(40289, 0) -- deselect all
  r.SetMediaItemSelected(cue.item, true)
  r.UpdateArrange()
end

-- =========================================================
-- CUTSCENE MANAGER — FEATURE FUNCTIONS
-- =========================================================
local function RenameTagItems()
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end

  r.Undo_BeginBlock()
  local renamed = 0

  -- TARGET: Item notes (work on items in tag time range, not tags themselves)
  if state.cm_rename_target == 1 then
    -- Collect all items in time range of selected tags
    local items_to_edit = {}
    for i, tag in ipairs(tags) do
      if ShouldProcessTag(i - 1) then
        local tag_start = r.GetMediaItemInfo_Value(tag.item, "D_POSITION")
        local tag_len = r.GetMediaItemInfo_Value(tag.item, "D_LENGTH")
        local tag_end = tag_start + tag_len

        -- Find all items on other tracks in this time range
        local total_items = r.CountMediaItems(0)
        for j = 0, total_items - 1 do
          local item = r.GetMediaItem(0, j)
          local item_track = r.GetMediaItem_Track(item)
          if item_track ~= tag.track then -- Exclude tag track itself
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len
            -- Check if item overlaps with tag time range
            if item_pos < tag_end and item_end > tag_start then
              items_to_edit[item] = true
            end
          end
        end
      end
    end

    -- Apply rename operation to item notes
    for item, _ in pairs(items_to_edit) do
      local _, old_notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      local new_notes = old_notes

      if state.cm_rename_mode == 0 and state.cm_rename_text ~= "" then
        new_notes = state.cm_rename_text .. old_notes
      elseif state.cm_rename_mode == 1 and state.cm_rename_text ~= "" then
        new_notes = old_notes .. state.cm_rename_text
      elseif state.cm_rename_mode == 2 and state.cm_rename_find ~= "" then
        new_notes = old_notes:gsub(state.cm_rename_find, state.cm_rename_replace)
      elseif state.cm_rename_mode == 4 and state.cm_rename_replace_text ~= "" then
        new_notes = state.cm_rename_replace_text
      -- Mode 3 (Template) - copy take name to notes
      elseif state.cm_rename_mode == 3 then
        local take = r.GetActiveTake(item)
        if take then
          new_notes = r.GetTakeName(take)
        end
      end

      r.GetSetMediaItemInfo_String(item, "P_NOTES", new_notes, true)
      renamed = renamed + 1
    end

    r.Undo_EndBlock("Post Agent: Edit Item Notes", -1)
    r.UpdateArrange()
    SetStatus(string.format("Edited notes on %d item(s) in tag range", renamed))
    return
  end

  -- TARGET: Tag names (original behavior)
  local name_counts = {} -- Track name occurrences for auto-numbering
  local unique_name_counts = {} -- Track unique base names for {UN} wildcard

  for i, tag in ipairs(tags) do
    if not ShouldProcessTag(i - 1) then
      goto continue
    end

    local new_name = tag.name
    local unique_num = i

    -- Calculate unique number for Template mode
    if state.cm_rename_mode == 3 then
      local base_name = tag.name:gsub("_%d+$", "") -- Strip trailing numbers
      if not unique_name_counts[base_name] then
        unique_name_counts[base_name] = 0
      end
      unique_name_counts[base_name] = unique_name_counts[base_name] + 1
      unique_num = unique_name_counts[base_name]
    end

    if state.cm_rename_mode == 0 and state.cm_rename_text ~= "" then
      new_name = state.cm_rename_text .. tag.name
    elseif state.cm_rename_mode == 1 and state.cm_rename_text ~= "" then
      new_name = tag.name .. state.cm_rename_text
    elseif state.cm_rename_mode == 2 and state.cm_rename_find ~= "" then
      new_name = tag.name:gsub(state.cm_rename_find, state.cm_rename_replace)
    elseif state.cm_rename_mode == 3 then
      new_name = ExpandTemplate(state.cm_rename_template, tag.name, i, tag.item, unique_num)
    elseif state.cm_rename_mode == 4 and state.cm_rename_replace_text ~= "" then
      new_name = state.cm_rename_replace_text  -- Complete replacement
    end

    -- Apply prefix/suffix if text is provided
    if state.cm_rename_prefix_suffix ~= "" then
      if state.cm_rename_is_prefix then
        new_name = state.cm_rename_prefix_suffix .. new_name
      else
        new_name = new_name .. state.cm_rename_prefix_suffix
      end
    end

    -- Auto-numbering for duplicates
    if state.cm_rename_auto_number then
      if name_counts[new_name] then
        name_counts[new_name] = name_counts[new_name] + 1
        new_name = new_name .. "_" .. name_counts[new_name]
      else
        name_counts[new_name] = 1
      end
    end

    -- Write to P_NOTES (matches AmbientGen workflow)
    r.GetSetMediaItemInfo_String(tag.item, "P_NOTES", new_name, true)
    renamed = renamed + 1
    ::continue::
  end

  r.Undo_EndBlock("Post Agent: Rename Tags", -1)
  r.UpdateArrange()

  -- Status message showing mode
  local mode_name = state.cm_select_mode == 0 and "Selected" or (state.cm_select_mode == 1 and "Playing" or "All")
  if state.cm_select_mode == 1 and renamed == 0 then
    SetStatus("No playing tag found (start playback or check position)")
  else
    SetStatus("Renamed " .. renamed .. " tag(s) [" .. mode_name .. " mode]")
  end
  ScanTagTracks()
end

local function ColorTagItems(mode)
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end

  r.Undo_BeginBlock()
  local colored = 0

  for i, tag in ipairs(tags) do
    if not ShouldProcessTag(i - 1) then
      goto continue
    end

    local new_color
    if mode == 0 then
      new_color = ImGuiColorToReaper(state.cm_color_pick)
    elseif mode == 1 then
      new_color = GetRandomReaperColor()
    elseif mode == 2 then
      if not cm_preset_colors[tag.name] then
        cm_preset_colors[tag.name] = ReaperColorToImGui(GetRandomReaperColor())
      end
      new_color = ImGuiColorToReaper(cm_preset_colors[tag.name])
    end

    r.SetMediaItemInfo_Value(tag.item, "I_CUSTOMCOLOR", new_color)
    colored = colored + 1
    ::continue::
  end

  r.Undo_EndBlock("Post Agent: Color Tags", -1)
  r.UpdateArrange()
  if mode == 2 then SaveTagColors() end
  SetStatus("Colored " .. colored .. " tags")
  ScanTagTracks()
end

local function MergeSelectedTags()
  r.Undo_BeginBlock()

  if state.cm_merge_mode == 0 then
    local items = {}
    local count = r.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
      local item = r.GetSelectedMediaItem(0, i)
      if IsEmptyItem(item) then table.insert(items, item) end
    end
    if #items < 2 then
      SetStatus("Select 2+ empty items to merge")
      r.Undo_EndBlock("Post Agent: Merge (cancelled)", -1)
      return
    end
    local deleted = MergeTagItems(items)
    SetStatus("Merged: removed " .. deleted .. " items")
  else
    local tags = state.cm_tags
    if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
    local by_track = {}
    for _, tag in ipairs(tags) do
      local key = tostring(tag.track)
      if not by_track[key] then by_track[key] = {} end
      table.insert(by_track[key], tag.item)
    end
    local total = 0
    for _, items in pairs(by_track) do
      total = total + MergeTagItems(items)
    end
    SetStatus("Merged adjacent: removed " .. total .. " items")
  end

  r.Undo_EndBlock("Post Agent: Merge Tags", -1)
  r.UpdateArrange()
  ScanTagTracks()
end

local function GroupTagsWithContext()
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end

  r.Undo_BeginBlock()
  local groups_created = 0

  for i, tag in ipairs(tags) do
    if not ShouldProcessTag(i - 1) then
      goto continue
    end

    local group_id = math.floor((r.time_precise() * 10000) + (tag.start * 100)) % 100000000
    if group_id == 0 then group_id = 1 end

    r.SetMediaItemInfo_Value(tag.item, "I_GROUPID", group_id)
    local grouped = 1

    local total_items = r.CountMediaItems(0)
    for j = 0, total_items - 1 do
      local item = r.GetMediaItem(0, j)
      if item ~= tag.item then
        local item_tr = r.GetMediaItem_Track(item)
        if item_tr ~= tag.track then
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          if pos < tag.finish and (pos + len) > tag.start then
            r.SetMediaItemInfo_Value(item, "I_GROUPID", group_id)
            grouped = grouped + 1
          end
        end
      end
    end

    if grouped > 1 then groups_created = groups_created + 1 end
    ::continue::
  end

  r.Undo_EndBlock("Post Agent: Group with Context", -1)
  r.UpdateArrange()
  SetStatus("Created " .. groups_created .. " groups")
end

local function ReadTagNotes()
  local tags = state.cm_tags
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #tags then
    local tag = tags[state.cm_selected_tag_idx + 1]
    local _, notes = r.GetSetMediaItemInfo_String(tag.item, "P_NOTES", "", false)
    state.cm_notes_text = notes
  end
end

local function WriteTagNotes()
  local tags = state.cm_tags
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #tags then
    local tag = tags[state.cm_selected_tag_idx + 1]
    r.Undo_BeginBlock()
    r.GetSetMediaItemInfo_String(tag.item, "P_NOTES", state.cm_notes_text, true)
    r.Undo_EndBlock("Post Agent: Write Notes", -1)
    SetStatus("Notes saved for '" .. tag.name .. "'")
  end
end

local function CopyNameToNotes()
  local tags = state.cm_tags
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #tags then
    local tag = tags[state.cm_selected_tag_idx + 1]
    state.cm_notes_text = tag.name
    WriteTagNotes()
    SetStatus("Copied name to notes: '" .. tag.name .. "'")
  end
end

local function CreateMarkersFromTags(is_region)
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end

  r.Undo_BeginBlock()
  local created = 0

  for i, tag in ipairs(tags) do
    if not ShouldProcessTag(i - 1) then
      goto continue
    end
    local exists = false
    local num_markers = r.CountProjectMarkers(0)
    for m = 0, num_markers - 1 do
      local _, isrgn, pos, _, mname, _ = r.EnumProjectMarkers(m)
      if isrgn == is_region and mname == tag.name and math.abs(pos - tag.start) < 0.01 then
        exists = true; break
      end
    end
    if not exists then
      local color = math.floor(r.GetMediaItemInfo_Value(tag.item, "I_CUSTOMCOLOR"))
      r.AddProjectMarker2(0, is_region, tag.start, tag.finish, tag.name, -1, color)
      created = created + 1
    end
    ::continue::
  end

  r.Undo_EndBlock("Post Agent: Create " .. (is_region and "Regions" or "Markers"), -1)
  r.UpdateArrange()
  SetStatus("Created " .. created .. " " .. (is_region and "regions" or "markers"))
end

local function SelectItemsInTagRange()
  local tags = state.cm_tags
  if state.cm_selected_tag_idx < 0 or state.cm_selected_tag_idx >= #tags then
    SetStatus("Select a tag first"); return
  end
  local tag = tags[state.cm_selected_tag_idx + 1]

  r.Main_OnCommand(40289, 0) -- deselect all items
  local sel_cnt = 0
  local total = r.CountMediaItems(0)
  for i = 0, total - 1 do
    local item = r.GetMediaItem(0, i)
    local tr = r.GetMediaItem_Track(item)
    if tr ~= tag.track then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos < tag.finish and (pos + len) > tag.start then
        r.SetMediaItemInfo_Value(item, "B_UISEL", 1)
        sel_cnt = sel_cnt + 1
      end
    end
  end
  r.UpdateArrange()
  SetStatus(string.format("Selected %d items in '%s'", sel_cnt, tag.name))
end

local function SelectTagsWithSameName()
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end
  if state.cm_selected_tag_idx < 0 or state.cm_selected_tag_idx >= #tags then
    SetStatus("Select a tag first"); return
  end

  local selected_tag = tags[state.cm_selected_tag_idx + 1]
  -- Remove trailing numbers from name (e.g., "Room_1" -> "Room")
  local base_name = selected_tag.name:gsub("_%d+$", "")

  -- Clear previous multi-selection
  state.cm_selected_tags = {}

  local count = 0
  for i, tag in ipairs(tags) do
    local tag_base = tag.name:gsub("_%d+$", "")
    if tag_base == base_name then
      state.cm_selected_tags[i - 1] = true
      count = count + 1
    end
  end

  SetStatus(string.format("Selected %d tags with base name '%s'", count, base_name))
end

-- =========================================================
-- BATCH NOTES EDITOR
-- =========================================================
-- TRACK TEMPLATE BUILDER
-- =========================================================
local function GetTrackTypeColor(prefix)
  for _, ttype in ipairs(TRACK_TYPES) do
    if ttype.key == prefix then
      return ColorToNativeReaper(ttype.color)
    end
  end
  return 0
end

local function BuildTrackTemplate(template_idx)
  local tmpl = TRACK_TEMPLATES[template_idx]
  if not tmpl then SetStatus("Invalid template"); return end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local insert_idx = r.CountTracks(0) -- Insert at end
  local folder_depth_pending = 0      -- Track pending folder closures

  for _, entry in ipairs(tmpl.tracks) do
    local color = GetTrackTypeColor(entry.prefix)

    if entry.folder then
      -- Close any pending folder first
      if folder_depth_pending > 0 then
        local prev_track = r.GetTrack(0, insert_idx - 1)
        if prev_track then
          local cur_depth = r.GetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH")
          r.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", cur_depth - folder_depth_pending)
        end
        folder_depth_pending = 0
      end

      -- Create folder parent
      r.InsertTrackAtIndex(insert_idx, true)
      local folder_track = r.GetTrack(0, insert_idx)
      r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", entry.prefix, true)
      r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
      if color ~= 0 then r.SetMediaTrackInfo_Value(folder_track, "I_CUSTOMCOLOR", color) end
      if entry.ch > 0 then r.SetMediaTrackInfo_Value(folder_track, "I_NCHAN", entry.ch) end
      insert_idx = insert_idx + 1

      -- Create child tracks
      for n = 1, entry.count do
        r.InsertTrackAtIndex(insert_idx, true)
        local track = r.GetTrack(0, insert_idx)
        r.GetSetMediaTrackInfo_String(track, "P_NAME", string.format("%s_%02d", entry.prefix, n), true)
        if color ~= 0 then r.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", color) end
        if entry.ch > 0 then r.SetMediaTrackInfo_Value(track, "I_NCHAN", entry.ch) end
        insert_idx = insert_idx + 1
      end
      folder_depth_pending = 1
    else
      -- Non-folder tracks
      for n = 1, entry.count do
        r.InsertTrackAtIndex(insert_idx, true)
        local track = r.GetTrack(0, insert_idx)
        local name = entry.count > 1 and string.format("%s_%02d", entry.prefix, n) or entry.prefix
        r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
        if color ~= 0 then r.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", color) end
        if entry.ch > 0 then r.SetMediaTrackInfo_Value(track, "I_NCHAN", entry.ch) end
        insert_idx = insert_idx + 1
      end
    end
  end

  -- Close last folder if pending
  if folder_depth_pending > 0 then
    local prev_track = r.GetTrack(0, insert_idx - 1)
    if prev_track then
      local cur_depth = r.GetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH")
      r.SetMediaTrackInfo_Value(prev_track, "I_FOLDERDEPTH", cur_depth - folder_depth_pending)
    end
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Post Agent: Build Track Template (" .. tmpl.name .. ")", -1)

  local total = 0
  for _, e in ipairs(tmpl.tracks) do total = total + e.count + (e.folder and 1 or 0) end
  SetStatus(string.format("Created %d tracks from template '%s'", total, tmpl.name))
end

-- =========================================================
-- GAP FINDER
-- =========================================================
local function FindGapsOnTracks(find_overlaps)
  state.gf_results = {}
  state.gf_selected_result = -1

  local filter_key = GF_TRACK_FILTERS[state.gf_track_filter_idx + 1]
  local num_tracks = r.CountTracks(0)

  for t = 0, num_tracks - 1 do
    local track = r.GetTrack(0, t)
    local _, track_name = r.GetTrackName(track)

    -- Check if track matches filter
    local match = false
    if filter_key == "All" then
      match = true
    else
      -- Match track name prefix (e.g., "DIA_01" matches "DIA")
      match = track_name:sub(1, #filter_key) == filter_key
    end

    if match then
      local item_count = r.CountTrackMediaItems(track)
      if item_count >= 2 then
        -- Collect items sorted by position
        local items_sorted = {}
        for i = 0, item_count - 1 do
          local item = r.GetTrackMediaItem(track, i)
          local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          table.insert(items_sorted, {pos = pos, finish = pos + len, item = item})
        end
        table.sort(items_sorted, function(a, b) return a.pos < b.pos end)

        -- Compare consecutive items
        for i = 1, #items_sorted - 1 do
          local curr = items_sorted[i]
          local next_item = items_sorted[i + 1]

          if not find_overlaps then
            -- Find gaps
            local gap = next_item.pos - curr.finish
            if gap >= state.gf_min_gap then
              table.insert(state.gf_results, {
                track = track,
                track_name = track_name,
                start = curr.finish,
                duration = gap,
                result_type = "Gap",
              })
            end
          else
            -- Find overlaps
            if next_item.pos < curr.finish then
              local overlap = curr.finish - next_item.pos
              table.insert(state.gf_results, {
                track = track,
                track_name = track_name,
                start = next_item.pos,
                duration = overlap,
                result_type = "Overlap",
              })
            end
          end
        end
      end
    end
  end

  local type_str = find_overlaps and "overlaps" or "gaps"
  SetStatus(string.format("Found %d %s on '%s' tracks", #state.gf_results, type_str, filter_key))
end

local function MarkGapsWithMarkers()
  if #state.gf_results == 0 then SetStatus("No results to mark"); return end

  r.Undo_BeginBlock()
  local created = 0
  for _, result in ipairs(state.gf_results) do
    local label = string.format("%s: %s (%.2fs)", result.result_type, result.track_name, result.duration)
    r.AddProjectMarker(0, false, result.start, 0, label, -1)
    created = created + 1
  end
  r.Undo_EndBlock("Post Agent: Mark Gaps/Overlaps", -1)
  r.UpdateArrange()
  SetStatus(string.format("Created %d markers", created))
end

local function NavigateToGapResult(idx)
  if idx < 0 or idx >= #state.gf_results then return end
  local result = state.gf_results[idx + 1]
  r.SetEditCurPos(result.start, false, false)
  local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
  local view_len = end_time - start_time
  local new_start = result.start - view_len * 0.1
  if new_start < 0 then new_start = 0 end
  r.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_start + view_len)
  r.UpdateArrange()
end

-- =========================================================
-- STATE PERSISTENCE
-- =========================================================
local function SaveState()
  r.SetExtState(EXTSTATE_SECTION, "rename_prefix", state.rename_prefix, true)
  r.SetExtState(EXTSTATE_SECTION, "rename_mode", tostring(state.rename_mode), true)
  r.SetExtState(EXTSTATE_SECTION, "rename_find", state.rename_find, true)
  r.SetExtState(EXTSTATE_SECTION, "rename_replace", state.rename_replace, true)
  r.SetExtState(EXTSTATE_SECTION, "selected_type_idx", tostring(state.selected_type_idx), true)
  -- Cutscene Manager
  r.SetExtState(EXTSTATE_SECTION, "cm_tag_tracks_input", state.cm_tag_tracks_input, true)
  r.SetExtState(EXTSTATE_SECTION, "cm_rename_template", state.cm_rename_template, true)
  SaveTagColors()
  SaveCustomPresets()
end

local function LoadState()
  local v
  v = r.GetExtState(EXTSTATE_SECTION, "rename_prefix")
  if v ~= "" then state.rename_prefix = v end
  v = r.GetExtState(EXTSTATE_SECTION, "rename_mode")
  if v ~= "" then state.rename_mode = tonumber(v) or 0 end
  v = r.GetExtState(EXTSTATE_SECTION, "rename_find")
  if v ~= "" then state.rename_find = v end
  v = r.GetExtState(EXTSTATE_SECTION, "rename_replace")
  if v ~= "" then state.rename_replace = v end
  v = r.GetExtState(EXTSTATE_SECTION, "selected_type_idx")
  if v ~= "" then state.selected_type_idx = tonumber(v) or 1 end
  -- Cutscene Manager
  v = r.GetExtState(EXTSTATE_SECTION, "cm_tag_tracks_input")
  if v ~= "" then state.cm_tag_tracks_input = v end
  v = r.GetExtState(EXTSTATE_SECTION, "cm_rename_template")
  if v ~= "" then state.cm_rename_template = v end
  LoadTagColors()
  LoadCustomPresets()
end

-- =========================================================
-- UI THEME
-- =========================================================
local style_color_count = 0
local style_var_count = 0

local function PushTheme()
  style_color_count = 0
  style_var_count = 0

  local function pc(col_enum, val)
    r.ImGui_PushStyleColor(ctx, col_enum, val)
    style_color_count = style_color_count + 1
  end
  local function pv(var_enum, ...)
    r.ImGui_PushStyleVar(ctx, var_enum, ...)
    style_var_count = style_var_count + 1
  end

  pc(r.ImGui_Col_WindowBg(),       C.BG)
  pc(r.ImGui_Col_FrameBg(),        C.FRAME)
  pc(r.ImGui_Col_FrameBgHovered(), C.BTN_HOV)
  pc(r.ImGui_Col_FrameBgActive(),  C.ACCENT)
  pc(r.ImGui_Col_Button(),         C.BTN)
  pc(r.ImGui_Col_ButtonHovered(),  C.BTN_HOV)
  pc(r.ImGui_Col_ButtonActive(),   C.ACCENT)
  pc(r.ImGui_Col_Text(),           C.TEXT)
  pc(r.ImGui_Col_Header(),         C.BTN)
  pc(r.ImGui_Col_HeaderHovered(),  C.BTN_HOV)
  pc(r.ImGui_Col_HeaderActive(),   C.ACCENT)
  pc(r.ImGui_Col_CheckMark(),      C.TEAL_HOV)
  pc(r.ImGui_Col_SliderGrab(),     C.ACCENT)
  pc(r.ImGui_Col_SliderGrabActive(), C.TEAL_HOV)
  pc(r.ImGui_Col_Separator(),      C.BORDER)
  pc(r.ImGui_Col_PopupBg(),        C.BG_DARK)

  pv(r.ImGui_StyleVar_FrameRounding(), 4)
  pv(r.ImGui_StyleVar_WindowBorderSize(), 0)
  pv(r.ImGui_StyleVar_ItemSpacing(), 6, 6)
  pv(r.ImGui_StyleVar_WindowPadding(), 8, 8)
end

local function PopTheme()
  r.ImGui_PopStyleColor(ctx, style_color_count)
  r.ImGui_PopStyleVar(ctx, style_var_count)
end

-- =========================================================
-- UI HELPER FUNCTIONS
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

local function DimText(text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.TEXT_DIM)
  r.ImGui_Text(ctx, text)
  r.ImGui_PopStyleColor(ctx, 1)
end

-- =========================================================
-- UI SECTIONS
-- =========================================================
local function DrawScanSection()
  if not r.ImGui_CollapsingHeader(ctx, "PROJECT OVERVIEW") then return end

  if TealButton("Scan Project##scan", 0, 0) then
    ScanProject()
  end
  r.ImGui_SameLine(ctx)
  if TealButton("Generate Report##genrep", 0, 0) then
    GenerateReport()
  end

  r.ImGui_Spacing(ctx)
  r.ImGui_Separator(ctx)
  DimText("Music Cue Sheet:")

  r.ImGui_SetNextItemWidth(ctx, -1)
  _, state.music_track_filter = r.ImGui_InputTextWithHint(ctx, "##music_tracks",
    "Track filter (e.g. MX, Music) - leave empty for auto", state.music_track_filter)

  _, state.music_include_metadata = r.ImGui_Checkbox(ctx, "Include Metadata (Artist, Title, Album)",
    state.music_include_metadata)

  if TealButton("Generate Music Report##musicrep", 0, 0) then
    GenerateMusicReport()
  end
  r.ImGui_SameLine(ctx)
  if state.show_music_report and state.music_report_text ~= "" then
    if r.ImGui_Button(ctx, "Export CSV##exportcsv", 0, 0) then
      ExportMusicCSV()
    end
  end

  if state.scan_results then
    local res = state.scan_results
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Tracks: " .. res.total_tracks .. "  |  Items: " .. res.total_items)
    r.ImGui_Text(ctx, "Content: " .. FormatTime(res.total_length))

    if #res.empty_tracks > 0 then
      DimText("Empty tracks: " .. #res.empty_tracks)
    end
    if #res.muted_tracks > 0 then
      DimText("Muted tracks: " .. #res.muted_tracks)
    end
    if #res.solo_tracks > 0 then
      DimText("Solo tracks: " .. #res.solo_tracks)
    end

    -- Type breakdown
    r.ImGui_Spacing(ctx)
    for _, ttype in ipairs(TRACK_TYPES) do
      local tracks = res.tracks_by_type[ttype.key]
      if tracks and #tracks > 0 then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), ColorToImGui(ttype.color))
        r.ImGui_Text(ctx, string.format("  %-10s %d", ttype.key, #tracks))
        r.ImGui_PopStyleColor(ctx, 1)
      end
    end
    local other_tracks = res.tracks_by_type["OTHER"]
    if other_tracks and #other_tracks > 0 then
      DimText(string.format("  %-10s %d", "OTHER", #other_tracks))
    end
  end

  -- Report section
  if state.show_report and state.report_text ~= "" then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    if r.ImGui_Button(ctx, "Copy to Clipboard##copyrep", 0, 0) then
      r.CF_SetClipboard(state.report_text)
      SetStatus("Report copied to clipboard")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Print to Console##printrep", 0, 0) then
      r.ShowConsoleMsg("\n" .. state.report_text .. "\n")
      SetStatus("Report printed to console")
    end
    r.ImGui_SameLine(ctx)
    if RedButton("Close##closerep", 0, 0) then
      state.show_report = false
    end

    r.ImGui_Spacing(ctx)

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_InputTextMultiline(ctx, "##report_view", state.report_text, avail_w, 200,
      r.ImGui_InputTextFlags_ReadOnly())
  end

  -- Music Report section
  if state.show_music_report and state.music_report_text ~= "" then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    if r.ImGui_Button(ctx, "Copy Music Report##copymusic", 0, 0) then
      r.CF_SetClipboard(state.music_report_text)
      SetStatus("Music report copied to clipboard")
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Print to Console##printmusic", 0, 0) then
      r.ShowConsoleMsg("\n" .. state.music_report_text .. "\n")
      SetStatus("Music report printed to console")
    end
    r.ImGui_SameLine(ctx)
    if RedButton("Close##closemusic", 0, 0) then
      state.show_music_report = false
    end

    r.ImGui_Spacing(ctx)

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_InputTextMultiline(ctx, "##music_report_view", state.music_report_text, avail_w, 200,
      r.ImGui_InputTextFlags_ReadOnly())
  end

  -- === ADR CUE SHEET ===
  r.ImGui_Spacing(ctx)
  r.ImGui_Separator(ctx)
  DimText("ADR Cue Sheet:")

  r.ImGui_SetNextItemWidth(ctx, -1)
  _, state.adr_track_filter = r.ImGui_InputTextWithHint(ctx, "##adr_tracks",
    "Track filter (e.g. DIA, DX, ADR, VO, DUB)", state.adr_track_filter)

  r.ImGui_SetNextItemWidth(ctx, -1)
  _, state.adr_scene_track = r.ImGui_InputTextWithHint(ctx, "##adr_scene_track",
    "Scene track name (empty = use tags from Cutscene Manager)", state.adr_scene_track)

  if TealButton("Generate ADR Sheet##adr_gen", 0, 0) then
    GenerateADRSheet()
  end
  r.ImGui_SameLine(ctx)
  if TealButton("Export CSV##adr_csv", 0, 0) then
    ExportADRCSV()
  end
  r.ImGui_SameLine(ctx)
  if OrangeButton("Mark for ADR##adr_mark", 0, 0) then
    MarkItemsForADR()
  end

  if #state.adr_cues > 0 then
    DimText(string.format("%d ADR cues", #state.adr_cues))

    local row_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
    local list_height = math.min(row_height * #state.adr_cues + 30, row_height * 10 + 30)

    if r.ImGui_BeginTable(ctx, "##adr_tbl", 7,
      r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_BordersInnerH() |
      r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_Resizable(), 0, list_height) then

      r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
      r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 25)
      r.ImGui_TableSetupColumn(ctx, "Character", r.ImGui_TableColumnFlags_WidthFixed(), 75)
      r.ImGui_TableSetupColumn(ctx, "TC In", r.ImGui_TableColumnFlags_WidthFixed(), 85)
      r.ImGui_TableSetupColumn(ctx, "TC Out", r.ImGui_TableColumnFlags_WidthFixed(), 85)
      r.ImGui_TableSetupColumn(ctx, "Line", r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableSetupColumn(ctx, "Scene", r.ImGui_TableColumnFlags_WidthFixed(), 70)
      r.ImGui_TableSetupColumn(ctx, "!", r.ImGui_TableColumnFlags_WidthFixed(), 20)
      r.ImGui_TableHeadersRow(ctx)

      for i, cue in ipairs(state.adr_cues) do
        r.ImGui_TableNextRow(ctx)

        r.ImGui_TableSetColumnIndex(ctx, 0)
        r.ImGui_Text(ctx, tostring(i))

        r.ImGui_TableSetColumnIndex(ctx, 1)
        local is_sel = (i - 1 == state.adr_selected_cue)
        if r.ImGui_Selectable(ctx, cue.character .. "##adr_" .. i, is_sel,
          r.ImGui_SelectableFlags_SpanAllColumns()) then
          state.adr_selected_cue = i - 1
          NavigateToADRCue(i - 1)
        end

        r.ImGui_TableSetColumnIndex(ctx, 2)
        DimText(FormatTimecode(cue.tc_in))

        r.ImGui_TableSetColumnIndex(ctx, 3)
        DimText(FormatTimecode(cue.tc_out))

        r.ImGui_TableSetColumnIndex(ctx, 4)
        r.ImGui_Text(ctx, cue.line)

        r.ImGui_TableSetColumnIndex(ctx, 5)
        if cue.scene ~= "" then
          DimText(cue.scene)
        end

        r.ImGui_TableSetColumnIndex(ctx, 6)
        if cue.priority == "HIGH" then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.RED)
          r.ImGui_Text(ctx, "!")
          r.ImGui_PopStyleColor(ctx)
        end
      end

      r.ImGui_EndTable(ctx)
    end
  end

  -- ADR text report viewer
  if state.adr_show_report and state.adr_report_text ~= "" then
    r.ImGui_Spacing(ctx)
    if r.ImGui_Button(ctx, "Copy ADR Report##copyadr", 0, 0) then
      r.CF_SetClipboard(state.adr_report_text)
      SetStatus("ADR report copied to clipboard")
    end
    r.ImGui_SameLine(ctx)
    if RedButton("Close##closeadr", 0, 0) then
      state.adr_show_report = false
    end

    r.ImGui_Spacing(ctx)
    local avail_w2 = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_InputTextMultiline(ctx, "##adr_report_view", state.adr_report_text, avail_w2, 150,
      r.ImGui_InputTextFlags_ReadOnly())
  end
end


local function ToggleTracksMute(type_key)
  if not state.scan_results then return end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return end

  local any_unmuted = false
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      if r.GetMediaTrackInfo_Value(info.track, "B_MUTE") == 0 then
        any_unmuted = true
        break
      end
    end
  end

  MuteTracksByType(type_key, any_unmuted and 1 or 0)
end

local function ToggleTracksSolo(type_key)
  if not state.scan_results then return end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return end

  local any_unsoloed = false
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      if r.GetMediaTrackInfo_Value(info.track, "I_SOLO") == 0 then
        any_unsoloed = true
        break
      end
    end
  end

  SoloTracksByType(type_key, any_unsoloed and 2 or 0)
end

local function ToggleTCP(type_key, show)
  if not state.scan_results then return end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return end

  r.Undo_BeginBlock()
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(info.track, "B_SHOWINTCP", show and 1 or 0)
    end
  end
  r.Undo_EndBlock("Post Agent: " .. (show and "Show" or "Hide") .. " in TCP", -1)
  SetStatus((show and "Shown" or "Hidden") .. " " .. type_key .. " in TCP")
end

local function ToggleMCP(type_key, show)
  if not state.scan_results then return end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return end

  r.Undo_BeginBlock()
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(info.track, "B_SHOWINMIXER", show and 1 or 0)
    end
  end
  r.Undo_EndBlock("Post Agent: " .. (show and "Show" or "Hide") .. " in MCP", -1)
  SetStatus((show and "Shown" or "Hidden") .. " " .. type_key .. " in MCP")
end

local function ScrollTracksToTop(type_key)
  if not state.scan_results then return end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return end

  if r.ValidatePtr(tracks[1].track, "MediaTrack*") then
    r.SetMixerScroll(tracks[1].track)
    r.SetOnlyTrackSelected(tracks[1].track)
    r.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
  end
end

local function GetTCPState(type_key)
  if not state.scan_results then return false end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return false end
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      if r.GetMediaTrackInfo_Value(info.track, "B_SHOWINTCP") == 0 then
        return false
      end
    end
  end
  return true
end

local function GetMCPState(type_key)
  if not state.scan_results then return false end
  local tracks = state.scan_results.tracks_by_type[type_key]
  if not tracks or #tracks == 0 then return false end
  for _, info in ipairs(tracks) do
    if r.ValidatePtr(info.track, "MediaTrack*") then
      if r.GetMediaTrackInfo_Value(info.track, "B_SHOWINMIXER") == 0 then
        return false
      end
    end
  end
  return true
end

-- =========================================================
-- TRACKS MANAGER (Merged: Batch Rename, Color-Code, Track Cleanup, Group Tracks)
-- =========================================================
local function DrawTracksManagerSection()
  if not r.ImGui_CollapsingHeader(ctx, "TRACKS MANAGER") then return end

  -- === BATCH RENAME ===
  if r.ImGui_TreeNode(ctx, "Batch Rename##tm_rename") then
    local rename_modes = "Add Prefix\0Add Suffix\0Find & Replace\0"
    r.ImGui_SetNextItemWidth(ctx, 150)
    _, state.rename_mode = r.ImGui_Combo(ctx, "Mode##rename", state.rename_mode, rename_modes)

    r.ImGui_SameLine(ctx)
    if state.rename_mode == 0 or state.rename_mode == 1 then
      r.ImGui_SetNextItemWidth(ctx, -1)
      _, state.rename_prefix = r.ImGui_InputTextWithHint(ctx, "##rename_prefix",
        state.rename_mode == 0 and "Prefix..." or "Suffix...", state.rename_prefix)
    else
      local field_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) / 2
      r.ImGui_SetNextItemWidth(ctx, field_width)
      _, state.rename_find = r.ImGui_InputTextWithHint(ctx, "##rename_find", "Find...", state.rename_find)
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, field_width)
      _, state.rename_replace = r.ImGui_InputTextWithHint(ctx, "##rename_replace", "Replace...", state.rename_replace)
    end

    if TealButton("Apply to Selected Tracks##rename", -1, 0) then
      BatchRenameSelected()
    end
    DimText("Select tracks in TCP first")
    r.ImGui_TreePop(ctx)
  end

  -- === COLOR-CODE ===
  if r.ImGui_TreeNode(ctx, "Color-Code##tm_color") then
    if TealButton("Auto Color by Name##autocolor", -1, 0) then
      ColorCodeTracks()
    end
    r.ImGui_SameLine(ctx)
    DimText("DIA, DX, MX, FX, SFX, HFX, DES, FOLEY, AMB, VO, BG, VCA, AUX, #, VIDEO, PRINTMASTER")

    r.ImGui_Spacing(ctx)

    -- Manual color assignment - compact line
    local type_labels = ""
    for _, ttype in ipairs(TRACK_TYPES) do
      type_labels = type_labels .. ttype.label .. " (" .. ttype.key .. ")\0"
    end
    r.ImGui_SetNextItemWidth(ctx, 200)
    _, state.selected_type_idx = r.ImGui_Combo(ctx, "##colortype", state.selected_type_idx - 1, type_labels)
    state.selected_type_idx = state.selected_type_idx + 1
    r.ImGui_SameLine(ctx)
    if TealButton("Color Selected as Type##colorsel", 0, 0) then
      ColorSelectedByType()
    end
    r.ImGui_TreePop(ctx)
  end

  -- === TRACK CLEANUP ===
  if r.ImGui_TreeNode(ctx, "Track Cleanup##tm_cleanup") then
    if TealButton("Select Empty Tracks##selempty", 0, 0) then
      SelectEmptyTracks()
    end
    r.ImGui_SameLine(ctx)
    if RedButton("Delete Empty Tracks##delempty", 0, 0) then
      DeleteEmptyTracks()
    end
    r.ImGui_SameLine(ctx)
    DimText("Skips folder parents with children")
    r.ImGui_TreePop(ctx)
  end

  -- === GROUP TRACKS ===
  if r.ImGui_TreeNode(ctx, "Group Tracks##tm_group") then
    if not state.scan_results then
      DimText("Scan project first")
    else
      if OrangeButton("Unmute All##unmall", 0, 0) then UnmuteAll() end
      r.ImGui_SameLine(ctx)
      if OrangeButton("Unsolo All##unsall", 0, 0) then UnsoloAll() end

      r.ImGui_Spacing(ctx)

      if r.ImGui_BeginTable(ctx, "GroupTable", 6, r.ImGui_TableFlags_BordersInnerV()) then
        r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthStretch())
        r.ImGui_TableSetupColumn(ctx, "M", r.ImGui_TableColumnFlags_WidthFixed(), 32)
        r.ImGui_TableSetupColumn(ctx, "S", r.ImGui_TableColumnFlags_WidthFixed(), 32)
        r.ImGui_TableSetupColumn(ctx, "TCP", r.ImGui_TableColumnFlags_WidthFixed(), 40)
        r.ImGui_TableSetupColumn(ctx, "MCP", r.ImGui_TableColumnFlags_WidthFixed(), 40)
        r.ImGui_TableSetupColumn(ctx, "↑", r.ImGui_TableColumnFlags_WidthFixed(), 28)
        r.ImGui_TableHeadersRow(ctx)

        for _, ttype in ipairs(TRACK_TYPES) do
          local tracks = state.scan_results.tracks_by_type[ttype.key]
          if tracks and #tracks > 0 then
            r.ImGui_TableNextRow(ctx)

            r.ImGui_TableSetColumnIndex(ctx, 0)
            r.ImGui_Selectable(ctx, ttype.label .. " (" .. #tracks .. ")##grp_" .. ttype.key, false)
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
              ScrollTracksToTop(ttype.key)
            end

            r.ImGui_TableSetColumnIndex(ctx, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.RED)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.RED_HOV)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.RED_HOV)
            if r.ImGui_SmallButton(ctx, "M##m_" .. ttype.key) then
              ToggleTracksMute(ttype.key)
              ScanProject()
            end
            r.ImGui_PopStyleColor(ctx, 3)

            r.ImGui_TableSetColumnIndex(ctx, 2)
            local btn_size = r.ImGui_GetFrameHeight(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.ORANGE)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.ORANGE_HOV)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.ORANGE_HOV)
            if r.ImGui_Button(ctx, "S##s_" .. ttype.key, btn_size, btn_size) then
              ToggleTracksSolo(ttype.key)
              ScanProject()
            end
            r.ImGui_PopStyleColor(ctx, 3)

            r.ImGui_TableSetColumnIndex(ctx, 3)
            local tcp_state = GetTCPState(ttype.key)
            if r.ImGui_Checkbox(ctx, "##tcp_" .. ttype.key, tcp_state) then
              ToggleTCP(ttype.key, not tcp_state)
            end

            r.ImGui_TableSetColumnIndex(ctx, 4)
            local mcp_state = GetMCPState(ttype.key)
            if r.ImGui_Checkbox(ctx, "##mcp_" .. ttype.key, mcp_state) then
              ToggleMCP(ttype.key, not mcp_state)
            end

            r.ImGui_TableSetColumnIndex(ctx, 5)
            if r.ImGui_SmallButton(ctx, "↑##top_" .. ttype.key) then ScrollTracksToTop(ttype.key) end
          end
        end

        r.ImGui_EndTable(ctx)
      end
    end
    r.ImGui_TreePop(ctx)
  end

  -- === TRACK TEMPLATES ===
  if r.ImGui_TreeNode(ctx, "Track Templates##tm_templates") then
    r.ImGui_SetNextItemWidth(ctx, -1)
    local tmpl_labels = ""
    for _, tmpl in ipairs(TRACK_TEMPLATES) do
      tmpl_labels = tmpl_labels .. tmpl.name .. "\0"
    end
    _, state.tm_template_idx = r.ImGui_Combo(ctx, "##tm_tpl_combo", state.tm_template_idx, tmpl_labels)

    -- Show template preview
    local tmpl = TRACK_TEMPLATES[state.tm_template_idx + 1]
    if tmpl then
      local total = 0
      for _, e in ipairs(tmpl.tracks) do total = total + e.count + (e.folder and 1 or 0) end
      DimText(string.format("%d tracks: ", total))
      r.ImGui_SameLine(ctx)
      local preview = {}
      for _, e in ipairs(tmpl.tracks) do
        table.insert(preview, e.prefix .. "x" .. e.count)
      end
      DimText(table.concat(preview, ", "))
    end

    if OrangeButton("Build Template##tm_build", -1, 0) then
      BuildTrackTemplate(state.tm_template_idx + 1)
    end
    DimText("Creates folder structure with auto-colored tracks")
    r.ImGui_TreePop(ctx)
  end

  -- === GAP FINDER ===
  if r.ImGui_TreeNode(ctx, "Gap Finder##tm_gaps") then
    r.ImGui_SetNextItemWidth(ctx, 80)
    _, state.gf_min_gap = r.ImGui_InputDouble(ctx, "##gf_min", state.gf_min_gap, 0.1, 0.5, "%.1fs")
    if state.gf_min_gap < 0.01 then state.gf_min_gap = 0.01 end

    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 100)
    local filter_labels = ""
    for _, f in ipairs(GF_TRACK_FILTERS) do filter_labels = filter_labels .. f .. "\0" end
    _, state.gf_track_filter_idx = r.ImGui_Combo(ctx, "##gf_filter", state.gf_track_filter_idx, filter_labels)

    r.ImGui_SameLine(ctx)
    if TealButton("Gaps##gf_find", 0, 0) then FindGapsOnTracks(false) end
    r.ImGui_SameLine(ctx)
    if TealButton("Overlaps##gf_over", 0, 0) then FindGapsOnTracks(true) end
    r.ImGui_SameLine(ctx)
    if OrangeButton("Mark##gf_mark", 0, 0) then MarkGapsWithMarkers() end

    if #state.gf_results > 0 then
      DimText(string.format("%d results found", #state.gf_results))

      local row_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
      local list_height = math.min(row_height * #state.gf_results + 30, row_height * 8 + 30)

      if r.ImGui_BeginTable(ctx, "##gf_tbl", 5,
        r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_BordersInnerH() |
        r.ImGui_TableFlags_ScrollY(), 0, list_height) then

        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
        r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 28)
        r.ImGui_TableSetupColumn(ctx, "Track", r.ImGui_TableColumnFlags_WidthStretch())
        r.ImGui_TableSetupColumn(ctx, "Start", r.ImGui_TableColumnFlags_WidthFixed(), 70)
        r.ImGui_TableSetupColumn(ctx, "Duration", r.ImGui_TableColumnFlags_WidthFixed(), 60)
        r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 55)
        r.ImGui_TableHeadersRow(ctx)

        for i, result in ipairs(state.gf_results) do
          r.ImGui_TableNextRow(ctx)

          r.ImGui_TableSetColumnIndex(ctx, 0)
          r.ImGui_Text(ctx, tostring(i))

          r.ImGui_TableSetColumnIndex(ctx, 1)
          local is_sel = (i - 1 == state.gf_selected_result)
          if r.ImGui_Selectable(ctx, result.track_name .. "##gf_" .. i, is_sel, r.ImGui_SelectableFlags_SpanAllColumns()) then
            state.gf_selected_result = i - 1
            NavigateToGapResult(i - 1)
          end

          r.ImGui_TableSetColumnIndex(ctx, 2)
          DimText(FormatTime(result.start))

          r.ImGui_TableSetColumnIndex(ctx, 3)
          DimText(string.format("%.2fs", result.duration))

          r.ImGui_TableSetColumnIndex(ctx, 4)
          if result.result_type == "Overlap" then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.ORANGE)
            r.ImGui_Text(ctx, result.result_type)
            r.ImGui_PopStyleColor(ctx)
          else
            DimText(result.result_type)
          end
        end

        r.ImGui_EndTable(ctx)
      end
    end

    r.ImGui_TreePop(ctx)
  end
end

local function GetHashTracks()
  local hash_tracks = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name:sub(1, 1) == "#" then
      table.insert(hash_tracks, name)
    end
  end
  return hash_tracks
end

local function ApplyPresetToTag(tag_idx, preset_text)
  if tag_idx < 0 or tag_idx >= #state.cm_tags then return end
  local tag = state.cm_tags[tag_idx + 1]

  r.Undo_BeginBlock()
  local new_name
  if state.cm_preset_insert_mode == 0 then
    -- Add mode
    new_name = tag.name .. " " .. preset_text
  else
    -- Replace mode
    new_name = preset_text
  end

  -- Apply prefix/suffix if text is provided
  if state.cm_rename_prefix_suffix ~= "" then
    if state.cm_rename_is_prefix then
      new_name = state.cm_rename_prefix_suffix .. new_name
    else
      new_name = new_name .. state.cm_rename_prefix_suffix
    end
  end

  -- Auto-numbering for duplicates
  if state.cm_rename_auto_number then
    if cm_preset_name_counts[new_name] then
      cm_preset_name_counts[new_name] = cm_preset_name_counts[new_name] + 1
      new_name = new_name .. "_" .. cm_preset_name_counts[new_name]
    else
      cm_preset_name_counts[new_name] = 1
    end
  end

  -- Write to P_NOTES (matches AmbientGen workflow)
  r.GetSetMediaItemInfo_String(tag.item, "P_NOTES", new_name, true)
  r.Undo_EndBlock("Post Agent: Apply Preset to Tag", -1)
  r.UpdateArrange()
  SetStatus((state.cm_preset_insert_mode == 0 and "Added" or "Replaced with") .. " '" .. preset_text .. "'")
  ScanTagTracks()
end

local function DrawCutsceneSection()
  if not r.ImGui_CollapsingHeader(ctx, "CUTSCENE MANAGER") then return end

  -- Tag track input with picker
  DimText("Tag tracks (comma-separated):")
  r.ImGui_SetNextItemWidth(ctx, -140)
  _, state.cm_tag_tracks_input = r.ImGui_InputTextWithHint(
    ctx, "##cm_tracks", "#Location, #Shotplan", state.cm_tag_tracks_input)

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Pick Tracks##cm_pick", 130, 0) then
    state.cm_show_track_picker = not state.cm_show_track_picker
  end

  if state.cm_show_track_picker then
    local hash_tracks = GetHashTracks()
    if #hash_tracks > 0 then
      r.ImGui_Indent(ctx, 10)
      for _, track_name in ipairs(hash_tracks) do
        if r.ImGui_Selectable(ctx, track_name .. "##pick_" .. track_name, false) then
          if state.cm_tag_tracks_input == "" then
            state.cm_tag_tracks_input = track_name
          else
            state.cm_tag_tracks_input = state.cm_tag_tracks_input .. ", " .. track_name
          end
        end
      end
      r.ImGui_Unindent(ctx, 10)
    else
      r.ImGui_Indent(ctx, 10)
      DimText("No tracks starting with #")
      r.ImGui_Unindent(ctx, 10)
    end
  end

  if TealButton("Scan Tags##cm_scan", -1, 0) then
    ScanTagTracks()
    state.cm_show_track_picker = false
  end

  if #state.cm_tags == 0 then
    DimText("No tags scanned. Enter track names and click Scan.")
    return
  end

  -- Tag count + selection mode
  r.ImGui_Text(ctx, #state.cm_tags .. " tags found")
  r.ImGui_SameLine(ctx)
  DimText("Apply to:")
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "Selected##cm_sel0", state.cm_select_mode == 0) then
    state.cm_select_mode = 0
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "Playing##cm_sel1", state.cm_select_mode == 1) then
    state.cm_select_mode = 1
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "All##cm_sel2", state.cm_select_mode == 2) then
    state.cm_select_mode = 2
  end

  r.ImGui_Spacing(ctx)

  -- === TAG LIST (Always visible, fixed height for 10 tags) ===
  -- Get current playback position to highlight playing tag
  local play_pos = r.GetPlayPosition()
  local playing_tag_idx = -1
  if r.GetPlayState() & 1 == 1 then  -- Check if playing
    for i, tag in ipairs(state.cm_tags) do
      if play_pos >= tag.start and play_pos < tag.finish then
        playing_tag_idx = i - 1
        break
      end
    end
  end

  -- Auto-select playing tag when in Playing mode
  if state.cm_select_mode == 1 and playing_tag_idx >= 0 then
    if state.cm_selected_tag_idx ~= playing_tag_idx then
      state.cm_selected_tag_idx = playing_tag_idx
      ReadTagNotes()  -- Auto-read notes for the playing tag
    end
  end

  -- Calculate height for 10 rows (row height ~20px + header ~25px + padding)
  local row_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
  local list_height = row_height * 10 + 30

  if r.ImGui_BeginTable(ctx, "##cm_tags_tbl", 6,
    r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_BordersInnerH() |
    r.ImGui_TableFlags_ScrollY(), 0, list_height) then

    r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)  -- Freeze header row
    r.ImGui_TableSetupColumn(ctx, "▶", r.ImGui_TableColumnFlags_WidthFixed(), 20)  -- Play indicator
    r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 28)
    r.ImGui_TableSetupColumn(ctx, "Color", r.ImGui_TableColumnFlags_WidthFixed(), 20)
    r.ImGui_TableSetupColumn(ctx, "Name", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Start", r.ImGui_TableColumnFlags_WidthFixed(), 70)
    r.ImGui_TableSetupColumn(ctx, "Dur", r.ImGui_TableColumnFlags_WidthFixed(), 60)
    r.ImGui_TableHeadersRow(ctx)

    for i, tag in ipairs(state.cm_tags) do
      r.ImGui_TableNextRow(ctx)

      -- Play indicator column
      r.ImGui_TableSetColumnIndex(ctx, 0)
      if playing_tag_idx == i - 1 then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00FF00FF)  -- Green
        r.ImGui_Text(ctx, "▶")
        r.ImGui_PopStyleColor(ctx)
      else
        r.ImGui_Text(ctx, "")
      end

      r.ImGui_TableSetColumnIndex(ctx, 1)
      r.ImGui_Text(ctx, tostring(i))

      r.ImGui_TableSetColumnIndex(ctx, 2)
      local col = tag.color ~= 0 and ReaperColorToImGui(tag.color) or C.TEXT_DIM
      if r.ImGui_ColorButton(ctx, "##clr_" .. i, col, r.ImGui_ColorEditFlags_NoTooltip(), 14, 14) then
        -- Click on color button to change color directly
        r.Undo_BeginBlock()
        local new_color = ImGuiColorToReaper(state.cm_color_pick)
        r.SetMediaItemInfo_Value(tag.item, "I_CUSTOMCOLOR", new_color)
        r.Undo_EndBlock("Post Agent: Paint Tag Color", -1)
        r.UpdateArrange()
        SetStatus("Color applied to tag: " .. tag.name)
        ScanTagTracks()
      end

      r.ImGui_TableSetColumnIndex(ctx, 3)
      local is_sel = (i - 1 == state.cm_selected_tag_idx) or state.cm_selected_tags[i - 1]
      if r.ImGui_Selectable(ctx, tag.name .. "##ov_" .. i, is_sel, r.ImGui_SelectableFlags_SpanAllColumns() | r.ImGui_SelectableFlags_AllowDoubleClick()) then
        -- Check keyboard modifiers
        local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
        local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())

        if ctrl then
          -- Ctrl: Toggle individual selection
          state.cm_selected_tags[i - 1] = not state.cm_selected_tags[i - 1]
          state.cm_selected_tag_idx = i - 1
        elseif shift and state.cm_selected_tag_idx >= 0 then
          -- Shift: Range selection
          state.cm_selected_tags = {}
          local start_idx = math.min(state.cm_selected_tag_idx, i - 1)
          local end_idx = math.max(state.cm_selected_tag_idx, i - 1)
          for idx = start_idx, end_idx do
            state.cm_selected_tags[idx] = true
          end
        else
          -- Normal click: Clear multi-selection
          state.cm_selected_tags = {}
          state.cm_selected_tag_idx = i - 1
        end

        -- Auto-read notes when tag is selected
        ReadTagNotes()
        if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          NavigateToTag(tag)
        end
      end

      r.ImGui_TableSetColumnIndex(ctx, 4)
      DimText(FormatTime(tag.start))

      r.ImGui_TableSetColumnIndex(ctx, 5)
      DimText(FormatTime(tag.finish - tag.start))
    end

    r.ImGui_EndTable(ctx)
  end

  r.ImGui_Spacing(ctx)

  -- === RENAME (Compact, always visible) ===
  -- Target selector
  r.ImGui_SetNextItemWidth(ctx, 90)
  local rename_targets = "Tag names\0Item notes\0"
  _, state.cm_rename_target = r.ImGui_Combo(ctx, "##cm_target", state.cm_rename_target, rename_targets)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Tag names: rename tags themselves\nItem notes: edit P_NOTES of items in tag time range")
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local rename_modes = state.cm_rename_target == 0 and "Prefix\0Suffix\0Find/Replace\0Template\0Replace\0" or "Prefix\0Suffix\0Find/Replace\0Take Name\0Replace\0"
  _, state.cm_rename_mode = r.ImGui_Combo(ctx, "##cm_ren_mode", state.cm_rename_mode, rename_modes)

  r.ImGui_SameLine(ctx)
  if state.cm_rename_mode == 0 or state.cm_rename_mode == 1 then
    r.ImGui_SetNextItemWidth(ctx, -180)
    _, state.cm_rename_text = r.ImGui_InputTextWithHint(ctx, "##cm_ren_text", state.cm_rename_mode == 0 and "Prefix text..." or "Suffix text...", state.cm_rename_text)
  elseif state.cm_rename_mode == 2 then
    -- Find/Replace - two equal width fields
    local field_width = (r.ImGui_GetContentRegionAvail(ctx) - 180) / 2
    r.ImGui_SetNextItemWidth(ctx, field_width)
    _, state.cm_rename_find = r.ImGui_InputTextWithHint(ctx, "##cm_ren_find", "Find...", state.cm_rename_find)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, field_width)
    _, state.cm_rename_replace = r.ImGui_InputTextWithHint(ctx, "##cm_ren_repl", "Replace...", state.cm_rename_replace)
  elseif state.cm_rename_mode == 3 then
    r.ImGui_SetNextItemWidth(ctx, -180)
    _, state.cm_rename_template = r.ImGui_InputTextWithHint(ctx, "##cm_ren_tpl", "{NAME}_{UN}", state.cm_rename_template)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Wildcards:\n{NAME} - Tag name\n{N}, {N2}, {N3} - Item index\n{UN}, {UN2}, {UN3} - Unique name count\n{TC} - Timecode HH:MM:SS:FF\n{TIME} - Time MM:SS.ms\nCustom wildcards available in Presets > Custom")
    end
  elseif state.cm_rename_mode == 4 then
    r.ImGui_SetNextItemWidth(ctx, -180)
    _, state.cm_rename_replace_text = r.ImGui_InputTextWithHint(ctx, "##cm_ren_replace_full", "New name...", state.cm_rename_replace_text)
  end

  r.ImGui_SameLine(ctx)
  if TealButton("Rename##cm_dorename", 130, 0) then RenameTagItems() end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "X##cm_clear", 40, 0) then
    -- Clear tag name
    if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #state.cm_tags then
      local tag = state.cm_tags[state.cm_selected_tag_idx + 1]
      r.Undo_BeginBlock()
      r.GetSetMediaItemInfo_String(tag.item, "P_NOTES", "", true)
      r.Undo_EndBlock("Post Agent: Clear Tag Name", -1)
      r.UpdateArrange()
      SetStatus("Cleared tag name")
      ScanTagTracks()
    end
  end

  -- === TAG NAME EDITOR ===
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #state.cm_tags then
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    DimText("Manual Edit:")

    -- Text editor with buttons below
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    _, state.cm_notes_text = r.ImGui_InputTextMultiline(ctx, "##cm_notes_editor",
      state.cm_notes_text, avail_w, 70)

    if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
      WriteTagNotes()
    end

    -- Buttons on one line
    if TealButton("Write##cm_notes_write", 0, 0) then
      WriteTagNotes()
    end
    r.ImGui_SameLine(ctx)
    if TealButton("Copy Name to Notes##cm_notes_copy", 0, 0) then
      CopyNameToNotes()
    end
  end

  -- === QUICK EDIT ZONE ===
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #state.cm_tags then
    local tag = state.cm_tags[state.cm_selected_tag_idx + 1]
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.HEADER)
    r.ImGui_Text(ctx, "Quick Edit: " .. tag.name)
    r.ImGui_PopStyleColor(ctx, 1)

    -- Preset mode toggle (left side) and Insert mode toggle (right side) on one line
    if r.ImGui_RadioButton(ctx, "Locations##cm_preset0", state.cm_preset_mode == 0) then
      state.cm_preset_mode = 0
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Scene Types##cm_preset1", state.cm_preset_mode == 1) then
      state.cm_preset_mode = 1
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Custom##cm_preset2", state.cm_preset_mode == 2) then
      state.cm_preset_mode = 2
    end

    -- Right-aligned Add/Replace buttons
    local text_width = r.ImGui_CalcTextSize(ctx, "Add")
    local btn_width = text_width + 40  -- Approximate button width with padding
    r.ImGui_SameLine(ctx, r.ImGui_GetContentRegionAvail(ctx) - btn_width * 2 - 8)
    if r.ImGui_RadioButton(ctx, "Add##cm_insert0", state.cm_preset_insert_mode == 0) then
      state.cm_preset_insert_mode = 0
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Replace##cm_insert1", state.cm_preset_insert_mode == 1) then
      state.cm_preset_insert_mode = 1
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)

    -- Prefix/Suffix - all on one line
    if r.ImGui_RadioButton(ctx, "Prefix##cm_ps_quick", state.cm_rename_is_prefix) then
      state.cm_rename_is_prefix = true
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Suffix##cm_ps_quick", not state.cm_rename_is_prefix) then
      state.cm_rename_is_prefix = false
    end
    r.ImGui_SameLine(ctx)
    _, state.cm_rename_auto_number = r.ImGui_Checkbox(ctx, "Auto##cm_auto_quick", state.cm_rename_auto_number)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    _, state.cm_rename_prefix_suffix = r.ImGui_InputTextWithHint(ctx, "##cm_ps_quick_text",
      "Text (e.g., _EXT, INT_)", state.cm_rename_prefix_suffix)

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)

    -- Preset buttons
    if state.cm_preset_mode == 0 then
      -- Locations
      local cols = 4
      local btn_width = (r.ImGui_GetContentRegionAvail(ctx) - (cols - 1) * 4) / cols
      for i, loc in ipairs(LOCATION_PRESETS) do
        if (i - 1) % cols ~= 0 then r.ImGui_SameLine(ctx) end
        if r.ImGui_Button(ctx, loc .. "##preset_loc_" .. i, btn_width, 0) then
          ApplyPresetToTag(state.cm_selected_tag_idx, loc)
        end
      end
    elseif state.cm_preset_mode == 1 then
      -- Scene Types
      for _, section_data in ipairs(SCENE_TYPE_PRESETS) do
        DimText(section_data.section)
        local cols = 4
        local btn_width = (r.ImGui_GetContentRegionAvail(ctx) - (cols - 1) * 4) / cols
        for i, item in ipairs(section_data.items) do
          if (i - 1) % cols ~= 0 then r.ImGui_SameLine(ctx) end
          if r.ImGui_Button(ctx, item .. "##preset_scene_" .. section_data.section .. "_" .. i, btn_width, 0) then
            ApplyPresetToTag(state.cm_selected_tag_idx, item)
          end
        end
        r.ImGui_Spacing(ctx)
      end
    else
      -- Custom Wildcards
      DimText("Custom Presets (Wildcards)")

      -- Add new custom preset
      if not state.cm_custom_input then state.cm_custom_input = "" end
      r.ImGui_SetNextItemWidth(ctx, -90)
      _, state.cm_custom_input = r.ImGui_InputTextWithHint(ctx, "##cm_custom_new", "Preset name...", state.cm_custom_input)
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Add##cm_add_custom", 80, 0) and state.cm_custom_input ~= "" then
        table.insert(cm_custom_presets, state.cm_custom_input)
        state.cm_custom_input = ""
        SaveCustomPresets()
        SetStatus("Added custom preset: " .. cm_custom_presets[#cm_custom_presets])
      end

      r.ImGui_Spacing(ctx)

      -- Display custom presets
      if #cm_custom_presets > 0 then
        local cols = 3
        local btn_width = (r.ImGui_GetContentRegionAvail(ctx) - (cols - 1) * 4) / cols
        for i, preset in ipairs(cm_custom_presets) do
          if (i - 1) % cols ~= 0 then r.ImGui_SameLine(ctx) end
          if r.ImGui_Button(ctx, preset .. "##preset_custom_" .. i, btn_width, 0) then
            ApplyPresetToTag(state.cm_selected_tag_idx, preset)
          end

          -- Right-click context menu to delete
          if r.ImGui_BeginPopupContextItem(ctx, "##ctx_" .. i) then
            if r.ImGui_MenuItem(ctx, "Delete") then
              table.remove(cm_custom_presets, i)
              SaveCustomPresets()
              SetStatus("Deleted custom preset")
            end
            r.ImGui_EndPopup(ctx)
          end
        end
      else
        DimText("No custom presets yet. Add one above!")
      end
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
  end


  -- === COLOR ===
  if r.ImGui_TreeNode(ctx, "Color##cm_color") then
    local flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel()
    _, state.cm_color_pick = r.ImGui_ColorEdit4(ctx, "##cm_picker", state.cm_color_pick, flags)
    r.ImGui_SameLine(ctx)
    if TealButton("Paint##cm_paint", 0, 0) then ColorTagItems(0) end
    r.ImGui_SameLine(ctx)
    if OrangeButton("Random##cm_rndcol", 0, 0) then ColorTagItems(1) end
    r.ImGui_SameLine(ctx)
    if TealButton("By Name##cm_byloc", 0, 0) then ColorTagItems(2) end
    r.ImGui_TreePop(ctx)
  end

  -- === MERGE ===
  if r.ImGui_TreeNode(ctx, "Merge##cm_merge") then
    if r.ImGui_RadioButton(ctx, "Selected items##cm_mrg0", state.cm_merge_mode == 0) then state.cm_merge_mode = 0 end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Adjacent on track##cm_mrg1", state.cm_merge_mode == 1) then state.cm_merge_mode = 1 end
    if OrangeButton("Merge##cm_domerge", -1, 0) then MergeSelectedTags() end
    DimText("Extends first item, deletes the rest")
    r.ImGui_TreePop(ctx)
  end

  -- === GROUP ===
  if r.ImGui_TreeNode(ctx, "Group##cm_group") then
    if TealButton("Group with Context##cm_grp", -1, 0) then GroupTagsWithContext() end
    DimText("Groups tag + overlapping items (I_GROUPID)")
    r.ImGui_TreePop(ctx)
  end

  -- === TOOLS ===
  if r.ImGui_TreeNode(ctx, "Tools##cm_tools") then
    -- Selection tools in one row
    if TealButton("Select in Range##cm_selrange", 0, 0) then SelectItemsInTagRange() end
    r.ImGui_SameLine(ctx)
    if TealButton("Select Same Name##cm_selsame", 0, 0) then SelectTagsWithSameName() end
    DimText("Multi-select tags with same base name (ignores _N suffix)")

    r.ImGui_Spacing(ctx)
    if TealButton("Create Regions##cm_rgn", 0, 0) then CreateMarkersFromTags(true) end
    r.ImGui_SameLine(ctx)
    if TealButton("Create Markers##cm_mkr", 0, 0) then CreateMarkersFromTags(false) end

    r.ImGui_Spacing(ctx)
    if TealButton("Item Ruler: H:M:S:F##cm_ruler", -1, 0) then
      r.Main_OnCommand(42314, 0)  -- Item properties: Display item time ruler in H:M:S:F format
      SetStatus("Item ruler format changed to H:M:S:F")
    end

    r.ImGui_TreePop(ctx)
  end
end

local function DrawStatusBar()
  if state.status_msg ~= "" then
    local elapsed = r.time_precise() - state.status_time
    if elapsed < 5.0 then
      r.ImGui_Separator(ctx)
      DimText(state.status_msg)
    end
  end
end

-- =========================================================
-- MAIN LOOP
-- =========================================================
local function Loop()
  r.ImGui_SetNextWindowSize(ctx, 420, 900, r.ImGui_Cond_FirstUseEver())

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.TITLE)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.TITLE)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), C.TITLE)

  local visible, open = r.ImGui_Begin(ctx, 'Post Agent v2.3.2', true)

  if visible then
    PushTheme()

    DrawScanSection()
    r.ImGui_Spacing(ctx)

    DrawTracksManagerSection()
    r.ImGui_Spacing(ctx)

    DrawCutsceneSection()

    DrawStatusBar()

    PopTheme()
    r.ImGui_End(ctx)
  end

  r.ImGui_PopStyleColor(ctx, 3)

  if open then
    r.defer(Loop)
  else
    SaveState()
  end
end

-- =========================================================
-- INIT
-- =========================================================
math.randomseed(os.time())
LoadState()
r.atexit(SaveState)
Loop()
