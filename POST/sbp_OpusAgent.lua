-- @description Opus Agent
-- @version 1.0
-- @author SBP & AI
-- @about Workflow orchestration agent for film post-production in REAPER. Scans project tracks and items, provides quick-access actions: batch rename, color-code by type, collect empty tracks, mute/solo groups, and generate project reports.
-- @link https://forum.cockos.com/showthread.php?t=301263
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   v1.0 - Initial release: Project scanner, batch rename, color-coding, track cleanup, group mute/solo, project report

local r = reaper

-- =========================================================
-- DEPENDENCY CHECK
-- =========================================================
if not r.ImGui_CreateContext then
  r.ShowConsoleMsg("Error: ReaImGui is required for Opus Agent.\n")
  return
end

local ctx = r.ImGui_CreateContext('SBP_OpusAgent_v1')

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

local EXTSTATE_SECTION = "SBP_OpusAgent"

-- =========================================================
-- TRACK TYPE DEFINITIONS
-- =========================================================
local TRACK_TYPES = {
  { key = "DX",   label = "Dialogue",    color = r and 0x4A90D9 or 0x4A90D9 },
  { key = "MX",   label = "Music",       color = 0xD4753F },
  { key = "SFX",  label = "SFX",         color = 0x2D8C6D },
  { key = "FOLEY",label = "Foley",       color = 0x8B5CF6 },
  { key = "AMB",  label = "Ambience",    color = 0x6B8E23 },
  { key = "VO",   label = "Voiceover",   color = 0xE06C75 },
  { key = "BG",   label = "Backgrounds", color = 0x56B6C2 },
  { key = "AUX",  label = "Aux/Bus",     color = 0x808080 },
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
  status_msg = "",
  status_time = 0,
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
      new_name = state.rename_prefix .. " " .. name
    elseif state.rename_mode == 1 and state.rename_prefix ~= "" then
      new_name = name .. " " .. state.rename_prefix
    elseif state.rename_mode == 2 and state.rename_find ~= "" then
      new_name = name:gsub(state.rename_find, state.rename_replace)
    end

    r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
  end

  r.Undo_EndBlock("Opus Agent: Batch Rename", -1)
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
        local col = ttype.color
        local native_color = r.ColorToNative(
          (col >> 16) & 0xFF,
          (col >> 8) & 0xFF,
          col & 0xFF
        ) | 0x1000000
        r.SetTrackColor(track, native_color)
        colored = colored + 1
        break
      end
    end
  end

  r.Undo_EndBlock("Opus Agent: Color-Code Tracks", -1)
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

  local col = ttype.color
  local native_color = r.ColorToNative(
    (col >> 16) & 0xFF,
    (col >> 8) & 0xFF,
    col & 0xFF
  ) | 0x1000000

  for i = 0, count - 1 do
    local track = r.GetSelectedTrack(0, i)
    r.SetTrackColor(track, native_color)
  end

  r.Undo_EndBlock("Opus Agent: Color Selected", -1)
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

  r.Undo_EndBlock("Opus Agent: Select Empty Tracks", -1)
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

  r.Undo_EndBlock("Opus Agent: Delete Empty Tracks", -1)
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

  r.Undo_EndBlock("Opus Agent: " .. (mute_val == 1 and "Mute" or "Unmute") .. " " .. type_key, -1)
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

  r.Undo_EndBlock("Opus Agent: " .. (solo_val > 0 and "Solo" or "Unsolo") .. " " .. type_key, -1)
  SetStatus((solo_val > 0 and "Soloed" or "Unsoloed") .. " " .. type_key .. " tracks (" .. #tracks .. ")")
  ScanProject()
end

local function UnmuteAll()
  r.Undo_BeginBlock()
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
  end
  r.Undo_EndBlock("Opus Agent: Unmute All", -1)
  SetStatus("Unmuted all tracks")
  if state.scan_results then ScanProject() end
end

local function UnsoloAll()
  r.Undo_BeginBlock()
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
  end
  r.Undo_EndBlock("Opus Agent: Unsolo All", -1)
  SetStatus("Unsoloed all tracks")
  if state.scan_results then ScanProject() end
end

-- =========================================================
-- PROJECT REPORT
-- =========================================================
local function GenerateReport()
  if not state.scan_results then ScanProject() end
  local res = state.scan_results

  local lines = {}
  table.insert(lines, "=== OPUS AGENT PROJECT REPORT ===")
  table.insert(lines, "Project: " .. (r.GetProjectName(0) ~= "" and r.GetProjectName(0) or "(untitled)"))
  table.insert(lines, "Date: " .. os.date("%Y-%m-%d %H:%M"))
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
-- STATE PERSISTENCE
-- =========================================================
local function SaveState()
  r.SetExtState(EXTSTATE_SECTION, "rename_prefix", state.rename_prefix, true)
  r.SetExtState(EXTSTATE_SECTION, "rename_mode", tostring(state.rename_mode), true)
  r.SetExtState(EXTSTATE_SECTION, "rename_find", state.rename_find, true)
  r.SetExtState(EXTSTATE_SECTION, "rename_replace", state.rename_replace, true)
  r.SetExtState(EXTSTATE_SECTION, "selected_type_idx", tostring(state.selected_type_idx), true)
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

local function SectionHeader(label)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.HEADER)
  r.ImGui_SeparatorText(ctx, label)
  r.ImGui_PopStyleColor(ctx, 1)
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
  SectionHeader("PROJECT SCANNER")

  if TealButton("Scan Project", -1, 0) then
    ScanProject()
  end

  if state.scan_results then
    local res = state.scan_results
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
        local col = ttype.color
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),
          ((col & 0xFF) << 24) | ((col >> 8 & 0xFF) << 16) | ((col >> 16 & 0xFF) << 8) | 0xFF)
        r.ImGui_Text(ctx, string.format("  %-10s %d", ttype.key, #tracks))
        r.ImGui_PopStyleColor(ctx, 1)
      end
    end
    local other_tracks = res.tracks_by_type["OTHER"]
    if other_tracks and #other_tracks > 0 then
      DimText(string.format("  %-10s %d", "OTHER", #other_tracks))
    end
  end
end

local function DrawRenameSection()
  SectionHeader("BATCH RENAME")

  local rename_modes = "Add Prefix\0Add Suffix\0Find & Replace\0"
  local changed
  changed, state.rename_mode = r.ImGui_Combo(ctx, "Mode##rename", state.rename_mode, rename_modes)

  if state.rename_mode == 0 or state.rename_mode == 1 then
    changed, state.rename_prefix = r.ImGui_InputText(ctx, "Text##rename_prefix", state.rename_prefix)
  else
    changed, state.rename_find = r.ImGui_InputText(ctx, "Find##rename_find", state.rename_find)
    changed, state.rename_replace = r.ImGui_InputText(ctx, "Replace##rename_replace", state.rename_replace)
  end

  if TealButton("Apply to Selected##rename", -1, 0) then
    BatchRenameSelected()
  end

  DimText("Select tracks in TCP, then click Apply")
end

local function DrawColorSection()
  SectionHeader("COLOR-CODE")

  if TealButton("Auto Color by Name##autocolor", -1, 0) then
    ColorCodeTracks()
  end
  DimText("Colors tracks matching: DX, MX, SFX, FOLEY, AMB, VO, BG, AUX")

  r.ImGui_Spacing(ctx)

  -- Manual color assignment
  local type_labels = ""
  for _, ttype in ipairs(TRACK_TYPES) do
    type_labels = type_labels .. ttype.label .. " (" .. ttype.key .. ")\0"
  end

  local changed
  changed, state.selected_type_idx = r.ImGui_Combo(ctx, "Type##colortype", state.selected_type_idx - 1, type_labels)
  state.selected_type_idx = state.selected_type_idx + 1

  if TealButton("Color Selected as Type##colorsel", -1, 0) then
    ColorSelectedByType()
  end
end

local function DrawCleanupSection()
  SectionHeader("TRACK CLEANUP")

  if TealButton("Select Empty Tracks##selempty", -1, 0) then
    SelectEmptyTracks()
  end

  if RedButton("Delete Empty Tracks##delempty", -1, 0) then
    DeleteEmptyTracks()
  end
  DimText("Skips folder parents with children")
end

local function DrawGroupSection()
  SectionHeader("GROUP MUTE / SOLO")

  if not state.scan_results then
    DimText("Scan project first")
    return
  end

  -- Unmute/Unsolo all buttons
  if OrangeButton("Unmute All##unmall", 0, 0) then
    UnmuteAll()
  end
  r.ImGui_SameLine(ctx)
  if OrangeButton("Unsolo All##unsall", 0, 0) then
    UnsoloAll()
  end

  r.ImGui_Spacing(ctx)

  -- Per-type mute/solo grid
  if r.ImGui_BeginTable(ctx, "GroupTable", 3) then
    r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Mute", r.ImGui_TableColumnFlags_WidthFixed(), 60)
    r.ImGui_TableSetupColumn(ctx, "Solo", r.ImGui_TableColumnFlags_WidthFixed(), 60)

    for _, ttype in ipairs(TRACK_TYPES) do
      local tracks = state.scan_results.tracks_by_type[ttype.key]
      if tracks and #tracks > 0 then
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableSetColumnIndex(ctx, 0)
        r.ImGui_Text(ctx, ttype.label .. " (" .. #tracks .. ")")

        r.ImGui_TableSetColumnIndex(ctx, 1)
        if r.ImGui_SmallButton(ctx, "M##m_" .. ttype.key) then
          MuteTracksByType(ttype.key, 1)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "U##um_" .. ttype.key) then
          MuteTracksByType(ttype.key, 0)
        end

        r.ImGui_TableSetColumnIndex(ctx, 2)
        if r.ImGui_SmallButton(ctx, "S##s_" .. ttype.key) then
          SoloTracksByType(ttype.key, 2)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "U##us_" .. ttype.key) then
          SoloTracksByType(ttype.key, 0)
        end
      end
    end

    r.ImGui_EndTable(ctx)
  end
end

local function DrawReportSection()
  SectionHeader("PROJECT REPORT")

  if TealButton("Generate Report##genrep", -1, 0) then
    GenerateReport()
  end

  if state.show_report and state.report_text ~= "" then
    r.ImGui_Spacing(ctx)

    if r.ImGui_Button(ctx, "Copy to Clipboard##copyrep", -1, 0) then
      r.CF_SetClipboard(state.report_text)
      SetStatus("Report copied to clipboard")
    end

    if r.ImGui_Button(ctx, "Print to Console##printrep", -1, 0) then
      r.ShowConsoleMsg("\n" .. state.report_text .. "\n")
      SetStatus("Report printed to console")
    end

    r.ImGui_Spacing(ctx)

    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_InputTextMultiline(ctx, "##report_view", state.report_text, avail_w, 200,
      r.ImGui_InputTextFlags_ReadOnly())
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
  r.ImGui_SetNextWindowSize(ctx, 420, 680, r.ImGui_Cond_FirstUseEver())

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.TITLE)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.TITLE)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), C.TITLE)

  local visible, open = r.ImGui_Begin(ctx, 'Opus Agent v1.0', true)

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

    DrawReportSection()

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
LoadState()
Loop()
