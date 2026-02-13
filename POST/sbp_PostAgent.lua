-- @description Post Agent
-- @version 1.8
-- @author SBP & AI
-- @about Workflow orchestration agent for film post-production in REAPER. Scans project tracks and items, provides quick-access actions: batch rename, color-code by type, collect empty tracks, mute/solo groups, project reports, cutscene tag management, and music cue sheet generator with metadata support.
-- @link https://forum.cockos.com/showthread.php?t=301263
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
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
  cm_rename_mode = 0,          -- 0=Prefix, 1=Suffix, 2=Find/Replace, 3=Template
  cm_rename_text = "",
  cm_rename_find = "",
  cm_rename_replace = "",
  cm_rename_template = "{NAME}_{N}",
  cm_rename_prefix_suffix = "",   -- prefix/suffix text for checkbox mode
  cm_rename_is_prefix = true,     -- true=prefix, false=suffix
  cm_rename_auto_number = true,   -- auto-numbering if duplicate names
  cm_color_pick = 0x226757FF,
  cm_merge_mode = 0,           -- 0=Selected, 1=Adjacent
  cm_notes_text = "",
  cm_show_track_picker = false,
  cm_preset_mode = 0,          -- 0=Locations, 1=Scene Types
  cm_preset_insert_mode = 0,   -- 0=Add, 1=Replace
  cm_quick_edit_idx = -1,      -- -1=none, otherwise tag index for quick edit
}

local cm_preset_colors = {}
local cm_preset_name_counts = {}  -- Track preset name counts for auto-numbering

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
    return tag_idx == state.cm_selected_tag_idx
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

local function ExpandTemplate(template, tag_name, index, item)
  local result = template
  result = result:gsub("{NAME}", tag_name or "")
  result = result:gsub("{N}", tostring(index or 0))
  result = result:gsub("{N2}", string.format("%02d", index or 0))
  result = result:gsub("{N3}", string.format("%03d", index or 0))
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
-- CUTSCENE MANAGER — FEATURE FUNCTIONS
-- =========================================================
local function RenameTagItems()
  local tags = state.cm_tags
  if #tags == 0 then ScanTagTracks(); tags = state.cm_tags end
  if #tags == 0 then SetStatus("No tags found"); return end

  r.Undo_BeginBlock()
  local renamed = 0
  local name_counts = {} -- Track name occurrences for auto-numbering

  for i, tag in ipairs(tags) do
    if not ShouldProcessTag(i - 1) then
      goto continue
    end

    local new_name = tag.name
    if state.cm_rename_mode == 0 and state.cm_rename_text ~= "" then
      new_name = state.cm_rename_text .. tag.name
    elseif state.cm_rename_mode == 1 and state.cm_rename_text ~= "" then
      new_name = tag.name .. state.cm_rename_text
    elseif state.cm_rename_mode == 2 and state.cm_rename_find ~= "" then
      new_name = tag.name:gsub(state.cm_rename_find, state.cm_rename_replace)
    elseif state.cm_rename_mode == 3 then
      new_name = ExpandTemplate(state.cm_rename_template, tag.name, i, tag.item)
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
  SetStatus("Renamed " .. renamed .. " tags")
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
end

local function DrawRenameSection()
  if not r.ImGui_CollapsingHeader(ctx, "BATCH RENAME") then return end

  local rename_modes = "Add Prefix\0Add Suffix\0Find & Replace\0"
  _, state.rename_mode = r.ImGui_Combo(ctx, "Mode##rename", state.rename_mode, rename_modes)

  if state.rename_mode == 0 or state.rename_mode == 1 then
    _, state.rename_prefix = r.ImGui_InputText(ctx, "Text##rename_prefix", state.rename_prefix)
  else
    _, state.rename_find = r.ImGui_InputText(ctx, "Find##rename_find", state.rename_find)
    _, state.rename_replace = r.ImGui_InputText(ctx, "Replace##rename_replace", state.rename_replace)
  end

  if TealButton("Apply to Selected##rename", -1, 0) then
    BatchRenameSelected()
  end

  DimText("Select tracks in TCP, then click Apply")
end

local function DrawColorSection()
  if not r.ImGui_CollapsingHeader(ctx, "COLOR-CODE") then return end

  if TealButton("Auto Color by Name##autocolor", -1, 0) then
    ColorCodeTracks()
  end
  DimText("Auto-colors: DIA, DX, MX, FX, SFX, HFX, DES, FOLEY, AMB, VO, BG, VCA, AUX, #, VIDEO, PRINTMASTER")

  r.ImGui_Spacing(ctx)

  -- Manual color assignment
  local type_labels = ""
  for _, ttype in ipairs(TRACK_TYPES) do
    type_labels = type_labels .. ttype.label .. " (" .. ttype.key .. ")\0"
  end

  local _
  _, state.selected_type_idx = r.ImGui_Combo(ctx, "Type##colortype", state.selected_type_idx - 1, type_labels)
  state.selected_type_idx = state.selected_type_idx + 1

  if TealButton("Color Selected as Type##colorsel", -1, 0) then
    ColorSelectedByType()
  end
end

local function DrawCleanupSection()
  if not r.ImGui_CollapsingHeader(ctx, "TRACK CLEANUP") then return end

  if TealButton("Select Empty Tracks##selempty", -1, 0) then
    SelectEmptyTracks()
  end

  if RedButton("Delete Empty Tracks##delempty", -1, 0) then
    DeleteEmptyTracks()
  end
  DimText("Skips folder parents with children")
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

local function DrawGroupSection()
  if not r.ImGui_CollapsingHeader(ctx, "GROUP TRACKS") then return end

  if not state.scan_results then
    DimText("Scan project first")
    return
  end

  if OrangeButton("Unmute All##unmall", 0, 0) then UnmuteAll() end
  r.ImGui_SameLine(ctx)
  if OrangeButton("Unsolo All##unsall", 0, 0) then UnsoloAll() end

  r.ImGui_Separator(ctx)
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
        if r.ImGui_Selectable(ctx, ttype.label .. " (" .. #tracks .. ")##grp_" .. ttype.key, false, r.ImGui_SelectableFlags_SpanAllColumns() | r.ImGui_SelectableFlags_AllowDoubleClick()) then
          if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            ScrollTracksToTop(ttype.key)
          end
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
      r.ImGui_ColorButton(ctx, "##clr_" .. i, col, r.ImGui_ColorEditFlags_NoTooltip(), 14, 14)

      r.ImGui_TableSetColumnIndex(ctx, 3)
      local is_sel = (i - 1 == state.cm_selected_tag_idx)
      if r.ImGui_Selectable(ctx, tag.name .. "##ov_" .. i, is_sel, r.ImGui_SelectableFlags_SpanAllColumns() | r.ImGui_SelectableFlags_AllowDoubleClick()) then
        state.cm_selected_tag_idx = i - 1
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

  -- === QUICK EDIT ZONE ===
  if state.cm_selected_tag_idx >= 0 and state.cm_selected_tag_idx < #state.cm_tags then
    local tag = state.cm_tags[state.cm_selected_tag_idx + 1]
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.HEADER)
    r.ImGui_Text(ctx, "Quick Edit: " .. tag.name)
    r.ImGui_PopStyleColor(ctx, 1)

    -- Preset mode toggle
    if r.ImGui_RadioButton(ctx, "Locations##cm_preset0", state.cm_preset_mode == 0) then
      state.cm_preset_mode = 0
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Scene Types##cm_preset1", state.cm_preset_mode == 1) then
      state.cm_preset_mode = 1
    end

    r.ImGui_Spacing(ctx)

    -- Insert mode toggle
    if r.ImGui_RadioButton(ctx, "Add##cm_insert0", state.cm_preset_insert_mode == 0) then
      state.cm_preset_insert_mode = 0
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Replace##cm_insert1", state.cm_preset_insert_mode == 1) then
      state.cm_preset_insert_mode = 1
    end

    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    DimText("Prefix/Suffix (applied with preset):")

    -- Prefix/Suffix toggle
    if r.ImGui_RadioButton(ctx, "Prefix##cm_ps_quick", state.cm_rename_is_prefix) then
      state.cm_rename_is_prefix = true
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_RadioButton(ctx, "Suffix##cm_ps_quick", not state.cm_rename_is_prefix) then
      state.cm_rename_is_prefix = false
    end
    r.ImGui_SameLine(ctx)
    _, state.cm_rename_auto_number = r.ImGui_Checkbox(ctx, "Auto-number##cm_auto_quick", state.cm_rename_auto_number)

    r.ImGui_SetNextItemWidth(ctx, -1)
    _, state.cm_rename_prefix_suffix = r.ImGui_InputTextWithHint(ctx, "##cm_ps_quick_text",
      "Optional text (e.g., _EXT, INT_)", state.cm_rename_prefix_suffix)

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
    else
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
    end

    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
  end

  -- === RENAME ===
  if r.ImGui_TreeNode(ctx, "Rename##cm_rename") then
    local rename_modes = "Prefix\0Suffix\0Find & Replace\0Template\0"
    _, state.cm_rename_mode = r.ImGui_Combo(ctx, "Mode##cm_ren_mode", state.cm_rename_mode, rename_modes)

    if state.cm_rename_mode == 0 or state.cm_rename_mode == 1 then
      r.ImGui_SetNextItemWidth(ctx, -1)
      _, state.cm_rename_text = r.ImGui_InputText(ctx, "Text##cm_ren_text", state.cm_rename_text)
    elseif state.cm_rename_mode == 2 then
      r.ImGui_SetNextItemWidth(ctx, -1)
      _, state.cm_rename_find = r.ImGui_InputText(ctx, "Find##cm_ren_find", state.cm_rename_find)
      r.ImGui_SetNextItemWidth(ctx, -1)
      _, state.cm_rename_replace = r.ImGui_InputText(ctx, "Replace##cm_ren_repl", state.cm_rename_replace)
    elseif state.cm_rename_mode == 3 then
      r.ImGui_SetNextItemWidth(ctx, -1)
      _, state.cm_rename_template = r.ImGui_InputText(ctx, "Template##cm_ren_tpl", state.cm_rename_template)
      DimText("{NAME} {N} {N2} {N3} {TC} {TIME}")
    end

    r.ImGui_Spacing(ctx)
    if TealButton("Rename##cm_dorename", -1, 0) then RenameTagItems() end
    r.ImGui_TreePop(ctx)
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
    if TealButton("Select in Range##cm_selrange", -1, 0) then SelectItemsInTagRange() end

    if TealButton("Create Regions##cm_rgn", 0, 0) then CreateMarkersFromTags(true) end
    r.ImGui_SameLine(ctx)
    if TealButton("Create Markers##cm_mkr", 0, 0) then CreateMarkersFromTags(false) end

    r.ImGui_Spacing(ctx)
    if TealButton("Item Ruler: H:M:S:F Format##cm_ruler", -1, 0) then
      r.Main_OnCommand(42314, 0)  -- Item properties: Display item time ruler in H:M:S:F format
      SetStatus("Item ruler format changed to H:M:S:F")
    end

    r.ImGui_Spacing(ctx)
    DimText("Notes (P_NOTES):")

    if TealButton("Copy Name to Notes##cm_copyname", 0, 0) then
      CopyNameToNotes()
    end
    r.ImGui_SameLine(ctx)
    if TealButton("Write##cm_noteswrite", 0, 0) then WriteTagNotes() end

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    _, state.cm_notes_text = r.ImGui_InputTextMultiline(ctx, "##cm_notes",
      state.cm_notes_text, avail_w, 80)

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

  local visible, open = r.ImGui_Begin(ctx, 'Post Agent v1.5', true)

  if visible then
    PushTheme()

    DrawScanSection()
    r.ImGui_Spacing(ctx)

    DrawRenameSection()
    r.ImGui_Spacing(ctx)

    DrawColorSection()
    r.ImGui_Spacing(ctx)

    DrawCleanupSection()
    r.ImGui_Spacing(ctx)

    DrawGroupSection()
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
