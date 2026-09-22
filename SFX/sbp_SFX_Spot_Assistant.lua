-- @description SBP SFX Spot Assistant — AI SFX spotting and generation
-- @version 1.5.7
-- @author SBP & AI
-- @license MIT
-- @about AI-assisted SFX spotting tool for REAPER. Analyzes video frames with local Ollama, displays copyable UCS-style tags, and generates SFX through MMAudio or StableDaw.
-- @changelog
--   1.5.7: Prevented duplicate I'm Feeling Lucky placements by recording a stable event identifier in each automatic item's Notes and skipping it on later runs.
--   1.5.6: Removed the obsolete START/MIDDLE/END cue option from Script Settings; precise SFX markers are now the primary event workflow.
--   1.5.5: Excluded common English function words from library matching so prepositions and articles no longer create false SFX candidates.
--   1.5.4: Added Broad, Balanced and Strict library-search modes; Balanced is now the default and rejects one-word partial matches for multi-word SFX tags.
--   1.5.3: Separated SFX-marker and CutScene batch targets at shared timeline positions and darkened the SFX batch control to distinguish its dedicated workflow.
--   1.5.2: Fixed batch analysis at adjacent CutScene boundaries, made batch runs silent until a single failure summary, and kept video-frame lookup on the following item at exact edit boundaries.
--   1.5.1: Moved automatic-placement options into Script Settings, renamed visible CutScene wording, and grouped SFX batch analysis beside its marker controls.
--   1.5.0: Added automatic top-match placement, optional CutScene-boundary limiting, level-based leading-silence trimming for sync, and bounded candidate-folder creation as takes.
--   1.4.16: Added category-aware SFX placement: FOLEY, HARD FX, DESIGN and AMB use separate reusable lanes, with numbered overflow lanes only when an item would overlap. Candidate paging now uses compact single-arrow controls.
--   1.4.15: Simplified SFX-marker navigation to equal-sized arrow controls and separated each tag's candidate pager with a divider.
--   1.4.14: Turned marker review into a focused marker-by-marker workflow with previous/next timeline navigation and three-candidate paging for every tag.
--   1.4.13: Connected analyzed SFX EVENT/PROCESS/DESIGN markers to the library review queue; each returned tag now receives ranked candidates at its exact marker time.
--   1.4.12: Switched SFX-marker insertion to REAPER's current AddRegionOrMarker API and verify each marker exists before reporting success.
--   1.4.11: Made SFX-marker creation explicit and reliable, refreshed the timeline immediately, and added a clear creation/error status below the marker buttons.
--   1.4.10: Replaced the PowerShell folder-picker launcher with hidden Windows Script Host and restored unrestricted folder navigation.
--   1.4.9: Replaced the slow WinForms library-folder dialog with the native Windows Shell folder picker.
--   1.4.8: Moved the library-folder caption outside the table and placed each removal cross at the far edge of its folder row.
--   1.4.7: Removed the duplicate library-folder label and replaced folder removal text with a centered cross icon.
--   1.4.6: Kept the MMAudio time-selection checkbox aligned with every input mode by moving the Image2Audio note below it.
--   1.4.5: Redesigned the SFX-library folder list as an aligned table with centered controls and path tooltips.
--   1.4.4: Moved the no-CutScene guidance into the collapsible SFX TAGS section so it no longer splits the interface.
--   1.4.3: Unified header colors by function: analysis controls are amber and SFX-marker controls are blue.
--   1.4.2: Separated the Assistant title from the action controls for a clearer header layout.
--   1.4.1: Fixed missing marker-button palette aliases that could prevent the Assistant window from opening.
--   1.4.0: Added EVENT, PROCESS and DESIGN SFX markers with one-, two- and three-frame local Ollama analysis around the exact sync point.
--   1.3.4: Added a forced final-answer prefix for Qwen3-VL when legacy Ollama keeps returning thinking-only responses.
--   1.3.3: Added reliable non-thinking Qwen3-VL analysis for older Ollama installations, preventing tag requests from ending in internal reasoning.
--   1.3.2: Three-frame analysis now keeps samples inside the video item and validates each FFmpeg frame before Ollama starts.
--   1.3.1: Timed event cues now apply only to three-frame analysis; Qwen reasoning is excluded from SFX tags.
--   1.3.0: Added timed START/MIDDLE/END event cues from vision analysis so Scene Review Queue can place candidates at scene-relative positions.
--   1.2.1: Redesigned library candidate lists as aligned table rows with modern audition/place controls and path tooltips.
--   1.2.0: Added per-tag scene review queue with independently ranked library candidates for each selected SFX event.
--   1.1.3: Replaced the library-file workaround with a native Windows folder picker.
--   1.1.2: Persisted the lightweight SFX library index between Assistant launches; rescanning is now manual or folder-change driven.
--   1.1.1: Added audition and manual placement for reviewed library candidates; new installs default to Qwen3-VL 4B.
--   1.1.0: Added local SFX library folders, filename indexing, and tag-based candidate search as the first review stage before placement.
--   1.0.6: Image2Audio now extracts the reference frame automatically from the configured video track via FFmpeg.
--   1.0.5: Added complete MMAudio Video2Audio, Text2Audio, and Image2Audio support; text generation no longer requires a video item.
--   1.0.4: Added strict post-processing so Notes contain only clean AMB/FOLEY/HARD FX/DESIGN tag lines.
--   1.0.3: Three-frame Ollama fallback now accepts message.thinking when content is empty.
--   1.0.2: Added quick analysis from Time Selection; automatically creates the scene track and item when needed.
--   1.0.1: Portable FFmpeg discovery via REAPER resource path; refined StableDaw runner, controls, tag layout, and English dialogs.
--   1.0.0: Initial unified release with Ollama analysis, MMAudio/StableDaw generation, tag selection, caching, and REAPER item placement.

local r = reaper
local VIEWER_DIR = debug.getinfo(1, "S").source:match("^@(.+[\\/])") or ""
local SETTINGS_SECTION = "SBP_SFX_Spot_Assistant"
local function setting(key, default) local v = reaper.GetExtState(SETTINGS_SECTION, key); return v ~= "" and v or default end
local SCENE_TRACK_NAME = setting("scene_track", "__SFX_SCENES__")
local VIDEO_TRACK_NAME = setting("video_track", "na zvuk")
local GENERATED_TRACK_NAME = setting("generated_track", "__SFX_AI_GENERATED__")
local LIBRARY_TRACK_NAME = setting("library_track", "__SFX_LIBRARY_MATCHES__")
local OLLAMA_MODEL = setting("ollama_model", "qwen3-vl:4b")
local analysis_mode = tonumber(setting("analysis_mode", "3")) or 3
local AI_BEGIN = "--- AI SFX ANALYSIS ---"
local AI_END = "--- END AI SFX ANALYSIS ---"
local EVENTS_BEGIN = "--- AI SFX EVENTS ---"
local EVENTS_END = "--- END AI SFX EVENTS ---"

if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui extension is required.\n\nInstall it via ReaPack: Extensions > ReaPack > Browse packages > ReaImGui.", "SBP SFX Spot Viewer", 0)
  return
end

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end
local function file_exists(path)
  local f=io.open(path,"rb"); if f then f:close(); return true end; return false
end
local function safe_name(text)
  text=(text or ""):upper():gsub("[^%w]+","_"):gsub("_+","_"):gsub("^_"," "):gsub("_$","")
  return text:sub(1,72)
end
local function cache_root()
  local p = r.GetProjectPath("", "")
  local root = (p ~= "" and p or r.GetResourcePath() .. "/Temp") .. "/SBP_SFX_Cache"
  r.RecursiveCreateDirectory(root .. "/clips", 0); r.RecursiveCreateDirectory(root .. "/outputs", 0); r.RecursiveCreateDirectory(root .. "/failed", 0)
  return root
end
local function clear_cache()
  local root = cache_root()
  for _, sub in ipairs({"clips", "outputs", "failed"}) do
    local dir = root .. "/" .. sub
    local files = {}
    local i = 0
    while true do local f = r.EnumerateFiles(dir, i); if not f then break end; files[#files+1]=f; i=i+1 end
    for _, f in ipairs(files) do os.remove(dir .. "/" .. f) end
  end
end
local function psq(v) return "'" .. tostring(v):gsub("'", "''") .. "'" end
local function vbsq(v) return '"' .. tostring(v):gsub('"', '""') .. '"' end
local function cache_hash(value)
  local h = 2166136261
  for i=1,#value do h = (h ~ value:byte(i)) * 16777619 % 4294967296 end
  return string.format("%08X", h)
end

local function item_at_cursor()
  local cursor = r.GetCursorPosition()
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    if name == SCENE_TRACK_NAME then
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, ii)
        local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local finish = start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if cursor >= start and cursor < finish then return item end
      end
    end
  end
end

local function video_source_at_position(position)
  for ti=0,r.CountTracks(0)-1 do
    local tr=r.GetTrack(0,ti); local _,name=r.GetTrackName(tr,"")
    if name == VIDEO_TRACK_NAME then
      for ii=0,r.CountTrackMediaItems(tr)-1 do
        local item=r.GetTrackMediaItem(tr,ii)
        local item_start=r.GetMediaItemInfo_Value(item,"D_POSITION")
        local item_end=item_start+r.GetMediaItemInfo_Value(item,"D_LENGTH")
        if position >= item_start and position < item_end then
          local take=r.GetActiveTake(item)
          if take then
            local path=r.GetMediaSourceFileName(r.GetMediaItemTake_Source(take),"")
            local offset=r.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
            local rate=r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
            if path ~= "" then return path, offset + (position-item_start)*rate end
          end
        end
      end
      break
    end
  end
  return "", 0
end

local function read_analysis()
  local item = item_at_cursor()
  if not item then return nil, "Place the edit cursor on an item on track '" .. SCENE_TRACK_NAME .. "'." end
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local from = notes:find(AI_BEGIN, 1, true)
  if not from then return nil, "This item does not contain an AI SFX ANALYSIS block yet." end
  from = from + #AI_BEGIN
  local until_at = notes:find(AI_END, from, true) or (#notes + 1)
  return trim(notes:sub(from, until_at - 1))
end

local function read_timed_events(item)
  if not item then return {} end
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local from = notes:find(EVENTS_BEGIN, 1, true)
  if not from then return {} end
  from = from + #EVENTS_BEGIN
  local until_at = notes:find(EVENTS_END, from, true) or (#notes + 1)
  local events = {}
  for line in notes:sub(from, until_at - 1):gmatch("[^\r\n]+") do
    local anchor, category, tag = line:upper():match("^%s*([A-Z]+)%s*|%s*([A-Z ]-)%s*|%s*(.-)%s*$")
    if (anchor == "START" or anchor == "MIDDLE" or anchor == "END") and (category == "AMB" or category == "FOLEY" or category == "HARD FX" or category == "DESIGN") and tag and tag ~= "" then
      events[#events+1] = { anchor=anchor, category=category, tag=trim(tag) }
    end
  end
  return events
end

local function parse_groups(text)
  local groups = {}
  for line in text:gmatch("[^\r\n]+") do
    local title, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
    if title and value then
      local tags = {}
      for tag in value:gmatch("[^,]+") do
        tag = trim(tag)
        if tag ~= "" then tags[#tags + 1] = tag end
      end
      groups[#groups + 1] = { title = trim(title), tags = tags, raw = value }
    end
  end
  return groups
end

local analysis, error_text, groups, scene_events = nil, nil, {}, {}
local shown_item = false

local function refresh_from_cursor(force)
  local item = item_at_cursor()
  if not force and item == shown_item then return end
  shown_item = item
  analysis, error_text = read_analysis()
  groups = analysis and parse_groups(analysis) or {}
  scene_events = read_timed_events(item)
end

refresh_from_cursor(true)
local ctx = r.ImGui_CreateContext("SBP SFX Spot Viewer")
local open = true
local show_settings = false
local request_mmaudio, request_stabledaw = false, false
local analysis_running = false
local batch_running = false
local marker_batch_running = false
local marker_status = nil

local SFX_MARKER_COLORS = {
  EVENT = r.ColorToNative(190, 104, 66) | 0x1000000,
  PROCESS = r.ColorToNative(65, 143, 163) | 0x1000000,
  DESIGN = r.ColorToNative(141, 102, 180) | 0x1000000
}

local function sfx_marker_at_cursor(cursor)
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  for i=0,marker_count + region_count - 1 do
    local ok, is_region, position, _, name, marker_id, color = r.EnumProjectMarkers3(0, i)
    local kind = ok and not is_region and (name or ""):upper():match("^SFX%s+([A-Z]+)")
    if kind ~= "EVENT" and kind ~= "PROCESS" and kind ~= "DESIGN" then kind = nil end
    if kind and math.abs(position - cursor) < 0.001 then return { id=marker_id, position=position, kind=kind, color=color or 0 } end
  end
end

local function add_sfx_marker(kind)
  local cursor = r.GetCursorPosition()
  local existing = sfx_marker_at_cursor(cursor)
  r.Undo_BeginBlock()
  if existing then
    r.SetProjectMarker3(0, existing.id, false, existing.position, 0, "SFX " .. kind, SFX_MARKER_COLORS[kind])
  else
    if r.AddRegionOrMarker then
      r.AddRegionOrMarker(0, false, cursor, 0, "SFX " .. kind, -1, SFX_MARKER_COLORS[kind])
    else
      r.AddProjectMarker2(0, false, cursor, 0, "SFX " .. kind, -1, SFX_MARKER_COLORS[kind])
    end
  end
  r.Undo_EndBlock("SBP: Add SFX " .. kind .. " marker", -1)
  r.UpdateTimeline()
  r.UpdateArrange()
  local confirmed = sfx_marker_at_cursor(cursor)
  if not confirmed or confirmed.kind ~= kind then
    marker_status = "REAPER did not confirm the SFX " .. kind .. " marker. No false success message was shown."
    return false
  end
  marker_status = string.format("SFX %s marker created at %.3f s.", kind, cursor)
  return true
end

local function ensure_scene_item_from_time_selection()
  local item = item_at_cursor()
  if item then return item end
  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if not ts_end or ts_end <= ts_start then return nil end
  local track
  for ti=0,r.CountTracks(0)-1 do
    local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
    if n == SCENE_TRACK_NAME then track=tr; break end
  end
  if not track then
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    track=r.GetTrack(0,r.CountTracks(0)-1)
    r.GetSetMediaTrackInfo_String(track,"P_NAME",SCENE_TRACK_NAME,true)
  end
  item=r.AddMediaItemToTrack(track)
  if item then
    r.SetMediaItemInfo_Value(item,"D_POSITION",ts_start)
    r.SetMediaItemInfo_Value(item,"D_LENGTH",ts_end-ts_start)
    r.SetEditCurPos(ts_start,false,false)
    r.UpdateItemInProject(item)
  end
  return item
end

local function run_analyzer()
  if analysis_running then return end
  if not sfx_marker_at_cursor(r.GetCursorPosition()) then ensure_scene_item_from_time_selection() end
  analysis_running = true
  -- Run on the next UI cycle so the button state is visibly updated first.
  r.defer(function()
    dofile(VIEWER_DIR .. "sbp_Analyze_SFX_Spot_with_Ollama.lua")
    analysis_running = false
    refresh_from_cursor(true)
  end)
end

local function collect_batch_error(errors, position)
  local detail = r.GetExtState(SETTINGS_SECTION, "analysis_error")
  if detail ~= "" then
    errors[#errors+1] = string.format("%.3f sec — %s", position, detail)
    r.DeleteExtState(SETTINGS_SECTION, "analysis_error", false)
  end
end

local function show_batch_errors(label, errors)
  if #errors == 0 then return end
  local lines = {}
  for i = 1, math.min(3, #errors) do lines[#lines+1] = errors[i] end
  if #errors > #lines then lines[#lines+1] = string.format("…and %d more.", #errors - #lines) end
  r.ShowMessageBox(label .. " finished with " .. #errors .. " failed item(s):\n\n" .. table.concat(lines, "\n\n"), "SBP SFX Spot", 0)
end

local function run_marker_batch()
  if marker_batch_running then return end
  local markers = {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  for i=0,marker_count + region_count - 1 do
    local ok, is_region, position, _, name = r.EnumProjectMarkers3(0, i)
    local kind = ok and not is_region and (name or ""):upper():match("^SFX%s+([A-Z]+)")
    if kind == "EVENT" or kind == "PROCESS" or kind == "DESIGN" then markers[#markers+1] = position end
  end
  if #markers == 0 then
    r.ShowMessageBox("Add EVENT, PROCESS, or DESIGN SFX markers first.", "SBP SFX Spot", 0)
    return
  end
  table.sort(markers)
  marker_batch_running = true
  r.defer(function()
    local original_cursor = r.GetCursorPosition()
    local previous_silent = r.GetExtState(SETTINGS_SECTION, "analysis_silent")
    local previous_target = r.GetExtState(SETTINGS_SECTION, "analysis_target")
    local errors = {}
    r.SetExtState(SETTINGS_SECTION, "analysis_silent", "1", false)
    r.SetExtState(SETTINGS_SECTION, "analysis_target", "marker", false)
    for _, position in ipairs(markers) do
      r.SetEditCurPos(position, false, false)
      dofile(VIEWER_DIR .. "sbp_Analyze_SFX_Spot_with_Ollama.lua")
      collect_batch_error(errors, position)
    end
    if previous_silent == "" then r.DeleteExtState(SETTINGS_SECTION, "analysis_silent", false) else r.SetExtState(SETTINGS_SECTION, "analysis_silent", previous_silent, false) end
    if previous_target == "" then r.DeleteExtState(SETTINGS_SECTION, "analysis_target", false) else r.SetExtState(SETTINGS_SECTION, "analysis_target", previous_target, false) end
    r.SetEditCurPos(original_cursor, false, false)
    marker_batch_running = false
    refresh_from_cursor(true)
    show_batch_errors("SFX marker batch", errors)
  end)
end
local function run_batch()
  if batch_running then return end
  batch_running=true
  r.defer(function()
    local original_cursor = r.GetCursorPosition()
    local previous_silent = r.GetExtState(SETTINGS_SECTION, "analysis_silent")
    local previous_target = r.GetExtState(SETTINGS_SECTION, "analysis_target")
    local errors = {}
    r.SetExtState(SETTINGS_SECTION, "analysis_silent", "1", false)
    r.SetExtState(SETTINGS_SECTION, "analysis_target", "scene", false)
    for ti=0,r.CountTracks(0)-1 do
      local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
      if n==SCENE_TRACK_NAME then
        for ii=0,r.CountTrackMediaItems(tr)-1 do
          local it=r.GetTrackMediaItem(tr,ii)
          local position = r.GetMediaItemInfo_Value(it,"D_POSITION")
          r.SetEditCurPos(position,false,false)
          dofile(VIEWER_DIR.."sbp_Analyze_SFX_Spot_with_Ollama.lua")
          collect_batch_error(errors, position)
        end
        break
      end
    end
    if previous_silent == "" then r.DeleteExtState(SETTINGS_SECTION, "analysis_silent", false) else r.SetExtState(SETTINGS_SECTION, "analysis_silent", previous_silent, false) end
    if previous_target == "" then r.DeleteExtState(SETTINGS_SECTION, "analysis_target", false) else r.SetExtState(SETTINGS_SECTION, "analysis_target", previous_target, false) end
    r.SetEditCurPos(original_cursor, false, false)
    batch_running=false; refresh_from_cursor(true)
    show_batch_errors("CutScene batch", errors)
  end)
end
local selected_tags, use_video, use_time_selection = {}, setting("use_video","1")=="1", setting("use_time_selection","1")=="1"
local mma_input_mode = setting("mma_input_mode", use_video and "video" or "text")
local library_roots = setting("library_roots", "")
local library_query = setting("library_query", "")
local library_match_mode = setting("library_match_mode", "balanced")
local library_index, library_candidates, library_review_queue = {}, {}, {}
local library_review_marker_groups, library_review_marker_index = {}, 1
local library_status = "Add one or more library folders, then scan them."
local auto_limit_to_scene = setting("auto_limit_to_scene", "1") == "1"
local auto_snap_onset = setting("auto_snap_onset", "0") == "1"
local auto_snap_threshold = tonumber(setting("auto_snap_threshold", "-36")) or -36
local candidate_take_limit = math.max(1, math.min(3, tonumber(setting("candidate_take_limit", "3")) or 3))
local variations, seed, custom_prompt, negative_prompt = tonumber(setting("variations","2")) or 2, tonumber(setting("seed","-1")) or -1, setting("prompt",""), setting("negative","music")
local guidance, steps = tonumber(setting("guidance","4.5")) or 4.5, tonumber(setting("steps","25")) or 25
local sd_prompt, sd_negative = setting("sd_prompt", ""), setting("sd_negative", "")
local sd_duration, sd_steps, sd_cfg, sd_seed = tonumber(setting("sd_duration", "8")) or 8, tonumber(setting("sd_steps", "8")) or 8, tonumber(setting("sd_cfg", "1")) or 1, tonumber(setting("sd_seed", "-1")) or -1
local function save_setting(k,v) r.SetExtState(SETTINGS_SECTION,k,tostring(v),true) end

local AUDIO_EXTENSIONS = { wav=true, flac=true, aif=true, aiff=true, mp3=true, ogg=true, opus=true }
-- These words help tag grammar but do not describe a sound source or action.
-- Excluding them from matching keeps "SCOOTER WHEEL ON PAVEMENT" from
-- surfacing unrelated files merely because their filename includes "ON".
local SEARCH_STOP_WORDS = {
  A=true, AN=true, THE=true, AND=true, OR=true,
  ON=true, IN=true, AT=true, BY=true, TO=true, OF=true, FOR=true,
  WITH=true, FROM=true, INTO=true, ONTO=true, OVER=true, UNDER=true,
  BETWEEN=true, THROUGH=true, ACROSS=true, AROUND=true, AGAINST=true,
  AS=true, IS=true, ARE=true, WAS=true, WERE=true, BE=true, BEEN=true,
  DO=true, DOES=true, DID=true, HAS=true, HAVE=true, HAD=true
}
local function normalize_search(text)
  return (text or ""):upper():gsub("[^%w]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
local function words_from(text)
  local result = {}
  for word in normalize_search(text):gmatch("%S+") do
    if #word > 1 and not SEARCH_STOP_WORDS[word] then result[#result+1] = word end
  end
  return result
end
local function library_root_list()
  local roots, seen = {}, {}
  for root in (library_roots .. "|"):gmatch("(.-)|") do
    root = trim(root)
    if root ~= "" and not seen[root:lower()] then roots[#roots+1] = root; seen[root:lower()] = true end
  end
  return roots
end
local function set_library_roots(roots)
  library_roots = table.concat(roots, "|")
  save_setting("library_roots", library_roots)
  library_index, library_candidates = {}, {}
  library_status = "Library folders changed. Scan them to refresh the index."
end
local function library_index_path()
  return r.GetResourcePath() .. "/SBP_SFX_Library_Index.tsv"
end
local function save_library_index()
  local file = io.open(library_index_path(), "wb")
  if not file then return end
  file:write("#SBP_SFX_LIBRARY\t", library_roots, "\n")
  for _, record in ipairs(library_index) do file:write(record.path, "\t", record.name, "\n") end
  file:close()
end
local function load_library_index()
  local file = io.open(library_index_path(), "rb")
  if not file then return end
  local header = file:read("*l") or ""
  local stored_roots = header:match("^#SBP_SFX_LIBRARY\t(.*)$")
  if stored_roots ~= library_roots then file:close(); return end
  local records, seen = {}, {}
  for line in file:lines() do
    local path, name = line:match("^(.-)\t(.-)$")
    if path and name and path ~= "" and not seen[path:lower()] then
      seen[path:lower()] = true
      records[#records+1] = { path=path, name=name, normalized=normalize_search(name) }
    end
  end
  file:close()
  if #records > 0 then
    library_index = records
    library_status = string.format("Loaded %d indexed audio files. Scan Library after changing its contents.", #records)
  end
end
local function choose_library_folder()
  local root = cache_root()
  local result_path, script_path = root .. "/library_folder.txt", root .. "/choose_library_folder.vbs"
  os.remove(result_path)
  -- BrowseForFolder's final argument is a navigation root, not an initial
  -- folder. Keep it at Desktop (0) so users can freely reach any drive.
  -- WScript starts without a terminal, unlike an os.execute PowerShell wrapper.
  local script = "On Error Resume Next\r\n"
    .. "Set shell = CreateObject(" .. vbsq("Shell.Application") .. ")\r\n"
    .. "Set folder = shell.BrowseForFolder(0, " .. vbsq("Choose an SFX library folder") .. ", &H50, 0)\r\n"
    .. "If Not (folder Is Nothing) Then\r\n"
    .. "  Set fso = CreateObject(" .. vbsq("Scripting.FileSystemObject") .. ")\r\n"
    .. "  Set output = fso.CreateTextFile(" .. vbsq(result_path) .. ", True, False)\r\n"
    .. "  output.Write folder.Self.Path\r\n"
    .. "  output.Close\r\n"
    .. "End If\r\n"
  local file = io.open(script_path, "wb")
  if not file then return nil end
  file:write(script); file:close()
  os.execute('wscript.exe //nologo "' .. script_path .. '"')
  local selected = io.open(result_path, "rb")
  local folder = selected and trim(selected:read("*a")) or ""
  if selected then selected:close() end
  os.remove(result_path)
  return folder ~= "" and folder or nil
end
local function add_library_root()
  local folder = choose_library_folder()
  if not folder then return end
  local roots = library_root_list()
  for _, root in ipairs(roots) do if root:lower() == folder:lower() then return end end
  roots[#roots+1] = folder
  set_library_roots(roots)
end
local function scan_library_directory(folder, records, seen, limit)
  if #records >= limit then return end
  local file_index = 0
  while #records < limit do
    local filename = r.EnumerateFiles(folder, file_index)
    if not filename then break end
    file_index = file_index + 1
    local extension = filename:match("%.([^.]+)$")
    if extension and AUDIO_EXTENSIONS[extension:lower()] then
      local path = folder .. "/" .. filename
      local key = path:lower()
      if not seen[key] then
        seen[key] = true
        records[#records+1] = { path=path, name=filename, normalized=normalize_search(filename) }
      end
    end
  end
  local directory_index = 0
  while #records < limit do
    local subdirectory = r.EnumerateSubdirectories(folder, directory_index)
    if not subdirectory then break end
    directory_index = directory_index + 1
    scan_library_directory(folder .. "/" .. subdirectory, records, seen, limit)
  end
end
local function scan_library()
  local roots = library_root_list()
  if #roots == 0 then library_status = "Add a library folder first."; return end
  local records, seen = {}, {}
  for _, root in ipairs(roots) do scan_library_directory(root, records, seen, 50000) end
  library_index, library_candidates = records, {}
  save_library_index()
  library_status = string.format("Indexed %d audio files from %d folder(s).", #records, #roots)
  if #records >= 50000 then library_status = library_status .. " Limit reached; split very large libraries into profiles later." end
end
local function rank_library_candidates(query)
  local terms = words_from(query)
  local candidates = {}
  if #library_index == 0 or #terms == 0 then return candidates end
  local required_matches = 1
  if library_match_mode == "balanced" then
    required_matches = math.min(#terms, 2)
  elseif library_match_mode == "strict" then
    required_matches = #terms
  end
  local normalized_query = normalize_search(query)
  for _, record in ipairs(library_index) do
    local score, matches = 0, 0
    for _, term in ipairs(terms) do
      if record.normalized:find(term, 1, true) then score = score + #term; matches = matches + 1 end
    end
    if matches >= required_matches then
      score = score + (matches / #terms) * 100
      if record.normalized:find(normalized_query, 1, true) then score = score + 200 end
      candidates[#candidates+1] = { record=record, score=score, matches=matches }
    end
  end
  table.sort(candidates, function(a,b) return a.score == b.score and a.record.name < b.record.name or a.score > b.score end)
  return candidates
end
local function find_library_candidates(query)
  if #library_index == 0 then library_status = "Scan the library before searching."; return end
  if #words_from(query) == 0 then library_status = "Enter a search phrase or use selected tags."; return end
  library_candidates = rank_library_candidates(query)
  library_status = string.format("Found %d candidate(s) for: %s", #library_candidates, query)
end
local function library_placement_range()
  local scene = item_at_cursor()
  local start = scene and r.GetMediaItemInfo_Value(scene, "D_POSITION") or r.GetCursorPosition()
  local length = scene and r.GetMediaItemInfo_Value(scene, "D_LENGTH") or 0
  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if use_time_selection and ts_end > ts_start then start, length = ts_start, ts_end - ts_start end
  return start, length
end
local function library_placement_start()
  return library_placement_range()
end
local function source_length_seconds(path)
  if not (r.PCM_Source_CreateFromFile and r.GetMediaSourceLength) then return 0 end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return 0 end
  local length, is_qn = r.GetMediaSourceLength(source)
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  return is_qn and 0 or math.max(0, length or 0)
end
local function scene_end_at(position)
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    if name == SCENE_TRACK_NAME then
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, ii)
        local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if position >= item_start and position < item_end then return item_end end
      end
      return nil
    end
  end
end
local function detect_take_onset(take, item_start, item_length, threshold_db)
  if not (r.new_array and r.GetMediaItemTake_Peaks) or item_length <= 0 then return 0 end
  local peak_rate = 1000
  local sample_count = math.max(1, math.min(30000, math.ceil(item_length * peak_rate)))
  local buffer = r.new_array(sample_count * 2)
  buffer.clear()
  local returned = r.GetMediaItemTake_Peaks(take, peak_rate, item_start, 1, sample_count, 0, buffer) & 0xFFFFF
  if returned <= 0 then return 0 end
  local threshold = 10 ^ (threshold_db / 20)
  for i = 1, returned do
    local peak = math.max(math.abs(buffer[i]), math.abs(buffer[i + returned]))
    if peak >= threshold then return (i - 1) / peak_rate end
  end
  return 0
end
local function apply_auto_placement(item, scene_end, use_onset_snap, threshold_db)
  local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local take = r.GetActiveTake(item)
  if use_onset_snap and take then
    local onset = detect_take_onset(take, start, length, threshold_db)
    if onset > 0.001 and onset < length - 0.01 then
      r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", onset)
      length = length - onset
      r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    end
  end
  if scene_end then
    local allowed = scene_end - start
    if allowed > 0 then r.SetMediaItemInfo_Value(item, "D_LENGTH", math.min(r.GetMediaItemInfo_Value(item, "D_LENGTH"), allowed)) end
  end
end
local function placement_exists(placement_key, start, tag, category)
  if not placement_key or placement_key == "" then return false end
  local needle = "Placement ID: " .. placement_key
  local legacy_query = "Query: " .. tostring(tag or "")
  local legacy_category = category and ("Category: " .. category) or nil
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ii = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, ii)
      local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      if (notes or ""):find(needle, 1, true) then return true end
      -- Placements made before 1.5.7 had no event ID. Treat a matching manual
      -- library placement at the same sync point as already prepared too.
      if start and math.abs(r.GetMediaItemInfo_Value(item, "D_POSITION") - start) < 0.001
        and (notes or ""):find("SFX LIBRARY MATCH", 1, true)
        and (notes or ""):find(legacy_query, 1, true)
        and (not legacy_category or (notes or ""):find(legacy_category, 1, true)) then return true end
    end
  end
  return false
end
local function track_is_free_at(track, start, length)
  local finish = start + math.max(length, 0.01)
  for ii = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, ii)
    local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if start < item_end - 0.001 and finish > item_start + 0.001 then return false end
  end
  return true
end
local function category_track_base(category)
  local normalized = normalize_search(category)
  if normalized == "FOLEY" then return "SFX - FOLEY" end
  if normalized == "HARD FX" then return "SFX - HARD FX" end
  if normalized == "DESIGN" then return "SFX - DESIGN" end
  if normalized == "AMB" then return "SFX - AMB" end
  return LIBRARY_TRACK_NAME
end
local function library_target_track(start, length, category)
  local base = category_track_base(category)
  local matching, highest_iteration = {}, 1
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    local suffix = name:sub(#base + 1)
    local iteration = suffix:match("^ %[(%d+)%]$")
    if name == base or iteration then
      iteration = tonumber(iteration) or 1
      highest_iteration = math.max(highest_iteration, iteration)
      matching[#matching+1] = { track=track, name=name }
    end
  end
  table.sort(matching, function(a, b) return a.name < b.name end)
  for _, entry in ipairs(matching) do
    if track_is_free_at(entry.track, start, length) then return entry.track end
  end
  local name = base
  if #matching > 0 then name = base .. " [" .. tostring(highest_iteration + 1) .. "]" end
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  local track = r.GetTrack(0, r.CountTracks(0) - 1)
  r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  return track
end
local function place_library_candidate(candidate, start, event_tag, event_category, options)
  start = start or library_placement_start()
  local scene_end = options and options.limit_to_scene and scene_end_at(start) or nil
  if scene_end and scene_end <= start then
    library_status = "Marker is outside its CutScene item; nothing was placed."
    return false
  end
  local source_length = source_length_seconds(candidate.record.path)
  local planned_length = scene_end and math.min(source_length, scene_end - start) or source_length
  local track = library_target_track(start, planned_length, event_category)
  local old_cursor = r.GetCursorPosition()
  r.Undo_BeginBlock()
  for ti=0,r.CountTracks(0)-1 do r.SetMediaTrackInfo_Value(r.GetTrack(0,ti), "I_SELECTED", 0) end
  r.SetMediaTrackInfo_Value(track, "I_SELECTED", 1)
  r.SetEditCurPos(start, false, false)
  local inserted = r.InsertMedia(candidate.record.path, 0)
  if inserted then
    local new_item
    for ii=0,r.CountTrackMediaItems(track)-1 do
      local item=r.GetTrackMediaItem(track,ii)
      if math.abs(r.GetMediaItemInfo_Value(item,"D_POSITION") - start) < 0.01 then new_item=item end
    end
    if new_item then
      local take=r.GetActiveTake(new_item)
      if take then r.GetSetMediaItemTakeInfo_String(take,"P_NAME",candidate.record.name,true) end
      local query = event_tag or library_query
      local category_line = event_category and ("\nCategory: " .. event_category) or ""
      local placement_line = options and options.placement_key and ("\nPlacement ID: " .. options.placement_key) or ""
      r.GetSetMediaItemInfo_String(new_item,"P_NOTES","SFX LIBRARY MATCH\nQuery: "..query..category_line..placement_line.."\nFile: "..candidate.record.path,true)
      apply_auto_placement(new_item, scene_end, options and options.snap_onset, options and options.snap_threshold or -36)
    end
    local _, track_name = r.GetTrackName(track, "")
    library_status = "Placed on " .. track_name .. ": " .. candidate.record.name
  else
    library_status = "REAPER could not insert: " .. candidate.record.path
  end
  r.SetEditCurPos(old_cursor, false, false)
  r.Undo_EndBlock("SBP: Place SFX library candidate", -1)
  r.UpdateArrange()
  return inserted and true or false
end
load_library_index()
local function clean_tag(tag)
  return (tostring(tag or ""):gsub("_+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end
local function selected_prompt()
  local out = {}
  for gi, group in ipairs(groups) do for ti, tag in ipairs(group.tags) do if selected_tags[gi.."_"..ti] then out[#out+1] = clean_tag(tag) end end end
  return table.concat(out, ", ")
end
local function marker_review_events()
  local events, marker_ids = {}, {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  for i = 0, marker_count + region_count - 1 do
    local ok, is_region, position, _, name, marker_id = r.EnumProjectMarkers3(0, i)
    local marker_name = ok and not is_region and (name or "") or ""
    local kind, summary = marker_name:match("^SFX%s+([A-Z]+)%s*•%s*(.+)$")
    if kind == "EVENT" or kind == "PROCESS" or kind == "DESIGN" then
      marker_ids[marker_id] = true
      for section in summary:gmatch("[^•]+") do
        local category, tags = section:match("^%s*([^:]+):%s*(.-)%s*$")
        category, tags = clean_tag(category):upper(), clean_tag(tags)
        if (category == "FOLEY" or category == "HARD FX" or category == "DESIGN") and tags ~= "" and tags:upper() ~= "NONE" then
          for tag in tags:gmatch("[^,]+") do
            tag = clean_tag(tag)
            if tag ~= "" and tag:upper() ~= "NONE" then
              events[#events+1] = { category=category, tag=tag, start=position, anchor=kind, marker_id=marker_id }
            end
          end
        end
      end
    end
  end
  table.sort(events, function(a, b)
    if a.start == b.start then return a.tag < b.tag end
    return a.start < b.start
  end)
  local marker_total = 0
  for _ in pairs(marker_ids) do marker_total = marker_total + 1 end
  return events, marker_total
end
local function build_marker_review_groups()
  local groups_by_id, ordered = {}, {}
  for index, event in ipairs(library_review_queue) do
    event.queue_index, event.candidate_page = index, 1
    if event.marker_id then
      local group = groups_by_id[event.marker_id]
      if not group then
        group = { marker_id=event.marker_id, kind=event.anchor, start=event.start, events={} }
        groups_by_id[event.marker_id] = group
        ordered[#ordered+1] = group
      end
      group.events[#group.events+1] = event
    end
  end
  table.sort(ordered, function(a, b) return a.start < b.start end)
  library_review_marker_groups, library_review_marker_index = ordered, 1
end
local function go_to_review_marker(index)
  if #library_review_marker_groups == 0 then return end
  library_review_marker_index = math.max(1, math.min(index, #library_review_marker_groups))
  r.SetEditCurPos(library_review_marker_groups[library_review_marker_index].start, false, false)
  r.UpdateArrange()
end
local function build_library_review_queue()
  if #library_index == 0 then library_status = "Scan the library before building a review queue."; return end
  -- Analyzed SFX markers are precise spot events. They deliberately take
  -- priority over CutScene selections, which remain the fallback for ambient
  -- and scene-wide tagging workflows.
  local marker_events, marker_total = marker_review_events()
  library_review_queue = {}
  library_review_marker_groups, library_review_marker_index = {}, 1
  if #marker_events > 0 then
    for _, event in ipairs(marker_events) do
      event.candidates = rank_library_candidates(event.tag)
      library_review_queue[#library_review_queue+1] = event
    end
    build_marker_review_groups()
    library_status = string.format("Built a review queue for %d tag(s) from %d analyzed SFX marker(s).", #library_review_queue, marker_total)
    return
  end
  local start, length = library_placement_range()
  local selected = {}
  for gi, group in ipairs(groups) do
    for ti, tag in ipairs(group.tags) do
      if selected_tags[gi .. "_" .. ti] then selected[clean_tag(tag):upper()] = true end
    end
  end
  for _, event in ipairs(scene_events) do
    if selected[event.tag:upper()] then
      local ratio = event.anchor == "START" and 0 or (event.anchor == "MIDDLE" and 0.5 or 0.9)
      local query = clean_tag(event.tag)
      library_review_queue[#library_review_queue+1] = {
        category=event.category, tag=query, start=start + length * ratio, candidates=rank_library_candidates(query), anchor=event.anchor
      }
    end
  end
  if #library_review_queue > 0 then
    library_status = string.format("Built a timed review queue for %d selected SFX event(s).", #library_review_queue)
    return
  end
  for gi, group in ipairs(groups) do
    for ti, tag in ipairs(group.tags) do
      if selected_tags[gi .. "_" .. ti] then
        local query = clean_tag(tag)
        library_review_queue[#library_review_queue+1] = {
          category=group.title, tag=query, start=start, candidates=rank_library_candidates(query)
        }
      end
    end
  end
  if #library_review_queue == 0 then
    library_status = "Select one or more tags before building a review queue."
  else
    library_status = string.format("Built a review queue for %d selected SFX event(s). Timed cues were not available.", #library_review_queue)
  end
end
local function clear_item_selection()
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    r.SetMediaTrackInfo_Value(track, "I_SELECTED", 0)
    for ii = 0, r.CountTrackMediaItems(track) - 1 do r.SetMediaItemSelected(r.GetTrackMediaItem(track, ii), false) end
  end
end
local function review_events_for_auto_place()
  -- The focused marker view is deliberately for reviewing. Lucky placement is
  -- global: it prepares the best match for every SFX event in the built queue.
  return library_review_queue
end
local function auto_place_lucky_matches()
  local events, placed, skipped = review_events_for_auto_place(), 0, 0
  if #events == 0 then library_status = "Build a review queue before automatic placement."; return end
  for _, event in ipairs(events) do
    local event_key = (event.marker_id and ("marker:" .. event.marker_id) or ("scene:" .. string.format("%.6f", event.start)))
      .. ":" .. normalize_search(event.category) .. ":" .. normalize_search(event.tag)
    local options = { limit_to_scene=auto_limit_to_scene, snap_onset=auto_snap_onset, snap_threshold=auto_snap_threshold, placement_key=event_key }
    if placement_exists(event_key, event.start, event.tag, event.category) then
      skipped = skipped + 1
    elseif event.candidates and event.candidates[1] and place_library_candidate(event.candidates[1], event.start, event.tag, event.category, options) then
      placed = placed + 1
    end
  end
  library_status = string.format("I'm Feeling Lucky placed %d of %d top matches; skipped %d existing placement(s).", placed, #events, skipped)
end
local function next_candidate_folder_name()
  local base, highest = "SFX CANDIDATES", 0
  for ti = 0, r.CountTracks(0) - 1 do
    local _, name = r.GetTrackName(r.GetTrack(0, ti), "")
    if name == base then highest = math.max(highest, 1) end
    local iteration = name:match("^SFX CANDIDATES %[(%d+)%]$")
    if iteration then highest = math.max(highest, tonumber(iteration)) end
  end
  return highest == 0 and base or base .. " [" .. tostring(highest + 1) .. "]"
end
local function add_candidate_take(item, path)
  clear_item_selection()
  r.SetMediaItemSelected(item, true)
  if not r.InsertMedia(path, 3) then return false end
  local take = r.GetActiveTake(item)
  if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", path:match("[^\\/]+$") or path, true) end
  return true
end
local function create_candidate_folder()
  local events = review_events_for_auto_place()
  local usable = {}
  for _, event in ipairs(events) do if event.candidates and #event.candidates > 0 then usable[#usable+1] = event end end
  if #usable == 0 then library_status = "No ranked candidates are available for a candidate folder."; return end
  local old_cursor = r.GetCursorPosition()
  r.Undo_BeginBlock()
  r.InsertTrackAtIndex(r.CountTracks(0), true)
  local parent = r.GetTrack(0, r.CountTracks(0) - 1)
  r.GetSetMediaTrackInfo_String(parent, "P_NAME", next_candidate_folder_name(), true)
  r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)
  local last_child, created = nil, 0
  for _, event in ipairs(usable) do
    r.InsertTrackAtIndex(r.CountTracks(0), true)
    local child = r.GetTrack(0, r.CountTracks(0) - 1)
    r.GetSetMediaTrackInfo_String(child, "P_NAME", "CANDIDATE - " .. event.category .. " - " .. event.tag, true)
    r.SetEditCurPos(event.start, false, false)
    clear_item_selection()
    r.SetMediaTrackInfo_Value(child, "I_SELECTED", 1)
    if r.InsertMedia(event.candidates[1].record.path, 0) then
      local item = r.GetTrackMediaItem(child, r.CountTrackMediaItems(child) - 1)
      if item then
        local take = r.GetActiveTake(item)
        if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", event.candidates[1].record.name, true) end
        local count = math.min(candidate_take_limit, #event.candidates)
        for candidate_index = 2, count do add_candidate_take(item, event.candidates[candidate_index].record.path) end
        r.GetSetMediaItemInfo_String(item, "P_NOTES", "SFX CANDIDATES\nQuery: " .. event.tag .. "\nCategory: " .. event.category, true)
        last_child, created = child, created + 1
      end
    end
  end
  if last_child then r.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH", -1) else r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 0) end
  r.SetEditCurPos(old_cursor, false, false)
  r.Undo_EndBlock("SBP: Create SFX candidate folder", -1)
  r.UpdateArrange()
  library_status = string.format("Created a candidate folder with %d event(s), up to %d takes each.", created, candidate_take_limit)
end

-- Dark studio palette: neutral charcoal panels, amber action controls, and
-- restrained category accents so it sits naturally beside NVK-style tools.
local C = {
  bg = 0x101418FF, panel = 0x171D23FF, frame = 0x222B33FF,
  border = 0x34404AFF, text = 0xE3E8EDFF, dim = 0x8E9BA7FF,
  amber = 0xD87945FF, green = 0x2D8C78FF,
  tag_amb = 0xB59A52FF, tag_foley = 0x4D8FA3FF, marker_batch = 0x356A79FF,
  orange = 0xC86F43FF, violet = 0x9B7BC4FF,
}

local function push_app_style()
  if not (r.ImGui_PushStyleColor and r.ImGui_PopStyleColor) then return 0 end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), C.dim)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), C.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1F6B5CFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2D8C78FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3AA88EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.frame)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), C.amber)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xF09A5EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x303A43FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3B4853FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x465460FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), C.amber)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x303B45FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x394752FF)
  if r.ImGui_PushStyleVar then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
  end
  return 20
end

local function pop_colors(count)
  if count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function pop_app_style(count)
  if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, 3) end
  pop_colors(count)
end

local function category_color(title)
  title = title:upper()
  if title:find("AMB", 1, true) then return C.tag_amb end
  if title:find("FOLEY", 1, true) then return C.tag_foley end
  if title:find("HARD", 1, true) then return C.orange end
  return C.violet
end

local function draw_tag(label, id, color, service, text_color, compact)
  local pushed = 0
  if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color - 0x00000033)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color - 0x00000066)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color or 0xFFFFFFFF)
    if r.ImGui_PushStyleVar then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), service and 4 or 1)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), service and 6 or 4, service and 4 or 3)
    end
    pushed = 4
  end
  local clicked = r.ImGui_Button(ctx, label .. "##" .. id, 0, service and 28 or 0)
  pop_colors(pushed)
  if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, 2) end
  return clicked
end

local function draw_library_button(label, id, color, width)
  local pushed = 0
  if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color - 0x00000033)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color - 0x00000066)
    pushed = 3
  end
  local clicked = r.ImGui_Button(ctx, label .. "##" .. id, width or 78, 22)
  pop_colors(pushed)
  return clicked
end

local function show_candidate_name(candidate)
  r.ImGui_Text(ctx, candidate.record.name)
  if r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, candidate.record.path) end
end

local function begin_candidate_table(id)
  if not r.ImGui_BeginTable then return false end
  local flags = 0
  if r.ImGui_TableFlags_RowBg then flags = flags | r.ImGui_TableFlags_RowBg() end
  if r.ImGui_TableFlags_BordersInnerH then flags = flags | r.ImGui_TableFlags_BordersInnerH() end
  if r.ImGui_TableFlags_SizingStretchProp then flags = flags | r.ImGui_TableFlags_SizingStretchProp() end
  if not r.ImGui_BeginTable(ctx, id, 4, flags) then return false end
  local fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
  r.ImGui_TableSetupColumn(ctx, "SAMPLE")
  r.ImGui_TableSetupColumn(ctx, "MATCH", fixed, 64)
  r.ImGui_TableSetupColumn(ctx, "", fixed, 86)
  r.ImGui_TableSetupColumn(ctx, "", fixed, 82)
  return true
end

local function draw_library_roots_table(roots)
  if #roots == 0 then
    r.ImGui_TextDisabled(ctx, "No library folders added yet.")
    return nil
  end
  if not r.ImGui_BeginTable then
    for i, root in ipairs(roots) do
      r.ImGui_TextWrapped(ctx, root)
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "REMOVE##library_root_" .. i) then return i end
    end
    return nil
  end
  local flags = 0
  if r.ImGui_TableFlags_RowBg then flags = flags | r.ImGui_TableFlags_RowBg() end
  if r.ImGui_TableFlags_BordersInnerH then flags = flags | r.ImGui_TableFlags_BordersInnerH() end
  if r.ImGui_TableFlags_SizingStretchProp then flags = flags | r.ImGui_TableFlags_SizingStretchProp() end
  if not r.ImGui_BeginTable(ctx, "library_roots", 1, flags) then return nil end
  local remove_index
  for i, root in ipairs(roots) do
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableSetColumnIndex(ctx, 0)
    local x = r.ImGui_GetCursorPosX and r.ImGui_GetCursorPosX(ctx) or 0
    local y = r.ImGui_GetCursorPosY and r.ImGui_GetCursorPosY(ctx) or 0
    local available = r.ImGui_GetContentRegionAvail and r.ImGui_GetContentRegionAvail(ctx) or 400
    if r.ImGui_PushTextWrapPos and r.ImGui_PopTextWrapPos then r.ImGui_PushTextWrapPos(ctx, x + math.max(110, available - 30)) end
    r.ImGui_TextWrapped(ctx, root)
    if r.ImGui_PushTextWrapPos and r.ImGui_PopTextWrapPos then r.ImGui_PopTextWrapPos(ctx) end
    if r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, root) end
    if r.ImGui_SetCursorPosX then r.ImGui_SetCursorPosX(ctx, x + math.max(0, available - 22)) end
    if r.ImGui_SetCursorPosY then r.ImGui_SetCursorPosY(ctx, y) end
    local remove_clicked = draw_library_button("×", "library_root_" .. i, C.orange, 22)
    if r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove library folder") end
    if remove_clicked then remove_index = i end
  end
  r.ImGui_EndTable(ctx)
  return remove_index
end

local function draw_candidate_table_row(candidate, id, terms, place_start, event_tag, event_category)
  r.ImGui_TableNextRow(ctx)
  r.ImGui_TableSetColumnIndex(ctx, 0); show_candidate_name(candidate)
  r.ImGui_TableSetColumnIndex(ctx, 1); r.ImGui_TextDisabled(ctx, string.format("%d/%d", candidate.matches, terms))
  r.ImGui_TableSetColumnIndex(ctx, 2)
  if draw_library_button("AUDITION", id .. "_audition", C.tag_foley) then r.OpenMediaExplorer(candidate.record.path, true) end
  r.ImGui_TableSetColumnIndex(ctx, 3)
  if draw_library_button("PLACE", id .. "_place", C.amber) then place_library_candidate(candidate, place_start, event_tag, event_category) end
end

local function available_tag_width()
  -- GetWindowSize exists in older ReaImGui versions too. Leave generous room
  -- for window padding and the scrollbar so a chip never touches the edge.
  if r.ImGui_GetWindowSize then
    local width = r.ImGui_GetWindowSize(ctx)
    return math.max(180, width - 42)
  end
  return 600
end

local function loop()
  -- The viewer follows the edit cursor: changing scene items changes the data
  -- immediately, with no need to close and reopen the window.
  refresh_from_cursor(false)
  r.ImGui_SetNextWindowSize(ctx, 680, 410, r.ImGui_Cond_FirstUseEver())
  local style_count = push_app_style()
  local visible
  visible, open = r.ImGui_Begin(ctx, "SBP SFX Spot Assistant", open)
  if visible then
    r.ImGui_Text(ctx, "SFX SPOT ASSISTANT")
    r.ImGui_Separator(ctx)
    if draw_tag(analysis_running and "ANALYZING..." or "ANALYZE", "analyze", C.amber, true) then run_analyzer() end
    r.ImGui_SameLine(ctx)
    if draw_tag(batch_running and "BATCH..." or "BATCH ANALYZE", "batch", C.amber, true) then run_batch() end
    r.ImGui_SameLine(ctx)
    if draw_tag("MMAUDIO FX", "mmaudio_top", C.green, true) then request_mmaudio = true end
    r.ImGui_SameLine(ctx)
    if draw_tag("STABLEDAW FX", "stabledaw_top", C.green, true) then request_stabledaw = true end
    r.ImGui_Separator(ctx)
    if draw_tag("+ EVENT", "add_event_marker", C.tag_foley, true) then add_sfx_marker("EVENT") end
    r.ImGui_SameLine(ctx)
    if draw_tag("+ PROCESS", "add_process_marker", C.tag_foley, true) then add_sfx_marker("PROCESS") end
    r.ImGui_SameLine(ctx)
    if draw_tag("+ DESIGN", "add_design_marker", C.tag_foley, true) then add_sfx_marker("DESIGN") end
    r.ImGui_SameLine(ctx)
    if draw_tag(marker_batch_running and "SFX BATCH..." or "BATCH SFX", "marker_batch", C.marker_batch, true) then run_marker_batch() end
    if marker_status then r.ImGui_TextDisabled(ctx, marker_status) end
    r.ImGui_Separator(ctx)
    show_settings = r.ImGui_CollapsingHeader(ctx, "SCRIPT SETTINGS", true)
    if show_settings then
      r.ImGui_Separator(ctx)
      local changed, value = r.ImGui_InputText(ctx, "CutScene track", SCENE_TRACK_NAME)
      if changed then SCENE_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"scene_track",value,true); refresh_from_cursor(true) end
      changed, value = r.ImGui_InputText(ctx, "Video track", VIDEO_TRACK_NAME)
      if changed then VIDEO_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"video_track",value,true) end
      changed, value = r.ImGui_InputText(ctx, "Generated SFX track", GENERATED_TRACK_NAME)
      if changed then GENERATED_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"generated_track",value,true) end
      changed, value = r.ImGui_InputText(ctx, "Library matches track", LIBRARY_TRACK_NAME)
      if changed then LIBRARY_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"library_track",value,true) end
      changed, value = r.ImGui_InputText(ctx, "Ollama model", OLLAMA_MODEL)
      if changed then OLLAMA_MODEL=value; r.SetExtState(SETTINGS_SECTION,"ollama_model",value,true) end
      r.ImGui_Text(ctx, "Frame analysis")
      if r.ImGui_RadioButton(ctx, "Single frame", analysis_mode == 1) then analysis_mode=1; r.SetExtState(SETTINGS_SECTION,"analysis_mode","1",true) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Start / middle / end", analysis_mode == 3) then analysis_mode=3; r.SetExtState(SETTINGS_SECTION,"analysis_mode","3",true) end
      r.ImGui_Text(ctx, "SFX marker context")
      local event_context = tonumber(setting("event_context_seconds", "0.35")) or 0.35
      changed, event_context = r.ImGui_SliderDouble(ctx, "Seconds before / after marker", event_context, 0.05, 1.5)
      if changed then r.SetExtState(SETTINGS_SECTION, "event_context_seconds", string.format("%.2f", event_context), true) end
      r.ImGui_TextDisabled(ctx, "EVENT: marker frame · PROCESS: before + marker · DESIGN: before + marker + after")
      r.ImGui_Separator(ctx)
      r.ImGui_Text(ctx, "AUTOMATIC PLACEMENT")
      changed, auto_limit_to_scene = r.ImGui_Checkbox(ctx, "Limit inserted SFX to CutScene", auto_limit_to_scene)
      if changed then save_setting("auto_limit_to_scene", auto_limit_to_scene and 1 or 0) end
      changed, auto_snap_onset = r.ImGui_Checkbox(ctx, "Trim leading silence for sync", auto_snap_onset)
      if changed then save_setting("auto_snap_onset", auto_snap_onset and 1 or 0) end
      if auto_snap_onset then
        changed, auto_snap_threshold = r.ImGui_SliderDouble(ctx, "Onset threshold (dB)", auto_snap_threshold, -60, -12)
        if changed then save_setting("auto_snap_threshold", string.format("%.1f", auto_snap_threshold)) end
      end
      changed, candidate_take_limit = r.ImGui_SliderInt(ctx, "Candidate takes per event", candidate_take_limit, 1, 3)
      if changed then save_setting("candidate_take_limit", candidate_take_limit) end
      r.ImGui_Text(ctx, "LLM analysis style")
      local analysis_style = setting("analysis_style", "short")
      if r.ImGui_RadioButton(ctx, "Short / literal", analysis_style == "short") then r.SetExtState(SETTINGS_SECTION,"analysis_style","short",true) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Creative / layered", analysis_style == "creative") then r.SetExtState(SETTINGS_SECTION,"analysis_style","creative",true) end
      if r.ImGui_Button(ctx, "CLEAR CACHE") then clear_cache() end
    end
    r.ImGui_Separator(ctx)
    local tags_open = r.ImGui_CollapsingHeader(ctx, "SFX TAGS", true)
    if tags_open then
      if error_text then
        r.ImGui_TextWrapped(ctx, error_text)
      else
      if draw_tag("SELECT ALL", "select_all", C.green, true) then
        for gi, group in ipairs(groups) do
          for ti, _ in ipairs(group.tags) do selected_tags[gi .. "_" .. ti] = true end
        end
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_SameLine(ctx)
      if draw_tag("COPY ALL", "all", C.amber, true) then r.ImGui_SetClipboardText(ctx, analysis) end
      for gi, group in ipairs(groups) do
        r.ImGui_SameLine(ctx)
        if draw_tag("COPY " .. group.title, "copytop" .. gi, C.frame, true, category_color(group.title), true) then
          r.ImGui_SetClipboardText(ctx, (group.raw or ""):gsub("_+", " "))
        end
      end
      r.ImGui_Dummy(ctx, 0, 5)
      for gi, group in ipairs(groups) do
        r.ImGui_Separator(ctx)
        local accent = category_color(group.title)
        if r.ImGui_SetCursorPosY then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 2) end
        local header_colors = 0
        if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accent)
          header_colors = 1
        end
        r.ImGui_Text(ctx, group.title)
        pop_colors(header_colors)
        local row_width = 0
        local max_row_width = available_tag_width()
        for ti, tag in ipairs(group.tags) do
          -- Checkbox + chip; clicking the chip still copies the tag.
          local display_tag = clean_tag(tag)
          local tag_width = r.ImGui_CalcTextSize(ctx, display_tag) + 52
          if ti > 1 and row_width + 8 + tag_width <= max_row_width then
            r.ImGui_SameLine(ctx)
            row_width = row_width + 8 + tag_width
          else
            row_width = tag_width
          end
          local key = gi .. "_" .. ti
          local changed, checked = r.ImGui_Checkbox(ctx, "##select_" .. key, selected_tags[key] or false)
          if changed then selected_tags[key] = checked end
          r.ImGui_SameLine(ctx, nil, 3)
          if draw_tag(display_tag, key, accent) then
            r.ImGui_SetClipboardText(ctx, display_tag)
          end
        end
        end
      end
      end
      r.ImGui_Separator(ctx)
      local library_open = r.ImGui_CollapsingHeader(ctx, "SFX LIBRARY", true)
      if library_open then
        local roots = library_root_list()
        r.ImGui_Text(ctx, "LIBRARY FOLDER")
        local remove_index = draw_library_roots_table(roots)
        if remove_index then table.remove(roots, remove_index); set_library_roots(roots) end
        if r.ImGui_Button(ctx, "ADD LIBRARY FOLDER...") then add_library_root() end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "SCAN LIBRARY") then scan_library() end
        r.ImGui_TextDisabled(ctx, library_status)
        local changed
        changed, library_query = r.ImGui_InputText(ctx, "Search SFX", library_query)
        if changed then save_setting("library_query", library_query) end
        r.ImGui_Text(ctx, "MATCH")
        if r.ImGui_RadioButton(ctx, "Broad", library_match_mode == "broad") then library_match_mode = "broad"; save_setting("library_match_mode", library_match_mode) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Balanced", library_match_mode == "balanced") then library_match_mode = "balanced"; save_setting("library_match_mode", library_match_mode) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Strict", library_match_mode == "strict") then library_match_mode = "strict"; save_setting("library_match_mode", library_match_mode) end
        if library_match_mode == "broad" then
          r.ImGui_TextDisabled(ctx, "Broad: one meaningful matching word is enough.")
        elseif library_match_mode == "strict" then
          r.ImGui_TextDisabled(ctx, "Strict: every meaningful word in the tag must match.")
        else
          r.ImGui_TextDisabled(ctx, "Balanced: multi-word tags need at least two meaningful matching words.")
        end
        if r.ImGui_Button(ctx, "USE SELECTED TAGS") then
          library_query = selected_prompt()
          save_setting("library_query", library_query)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "FIND CANDIDATES") then find_library_candidates(library_query) end
        if #library_candidates > 0 then
          r.ImGui_Text(ctx, "SEARCH RESULTS")
          r.ImGui_TextDisabled(ctx, "Hover a sample name to see its full path.")
          local visible_candidates = math.min(#library_candidates, 20)
          if begin_candidate_table("library_search_results") then
            r.ImGui_TableHeadersRow(ctx)
            local terms = #words_from(library_query)
            for i=1,visible_candidates do draw_candidate_table_row(library_candidates[i], "library_" .. i, terms) end
            r.ImGui_EndTable(ctx)
          end
          if #library_candidates > visible_candidates then r.ImGui_TextDisabled(ctx, string.format("Showing the first %d of %d candidates.", visible_candidates, #library_candidates)) end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "BUILD REVIEW QUEUE") then build_library_review_queue() end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "CLEAR REVIEW QUEUE") then
          library_review_queue, library_review_marker_groups, library_review_marker_index = {}, {}, 1
        end
        r.ImGui_Text(ctx, "AUTO PLACE")
        if r.ImGui_Button(ctx, "I'M FEELING LUCKY (ALL)") then auto_place_lucky_matches() end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "CREATE CANDIDATE FOLDER") then create_candidate_folder() end
        r.ImGui_TextDisabled(ctx, "Lucky uses the top match for every queued event. Candidate Folder uses the take limit from Script Settings.")
        if #library_review_queue > 0 then
          r.ImGui_Text(ctx, "SFX REVIEW QUEUE")
          local visible_events = library_review_queue
          if #library_review_marker_groups > 0 then
            local marker_group = library_review_marker_groups[library_review_marker_index]
            if r.ImGui_Button(ctx, "<<<##review_marker_previous", 34, 0) then go_to_review_marker(library_review_marker_index - 1) end
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, string.format("MARKER %d / %d — %s · %.3f sec", library_review_marker_index, #library_review_marker_groups, marker_group.kind, marker_group.start))
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, ">>>##review_marker_next", 34, 0) then go_to_review_marker(library_review_marker_index + 1) end
            visible_events = marker_group.events
          end
          for local_index, event in ipairs(visible_events) do
            local event_index = event.queue_index or local_index
            local accent = category_color(event.category)
            local pushed = 0
            if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accent); pushed = 1 end
            r.ImGui_Text(ctx, string.format("%d. %s — %s", local_index, event.category, event.tag))
            pop_colors(pushed)
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, string.format("%s · %.3f sec", event.anchor or "SCENE", event.start))
            local candidate_total = #event.candidates
            if candidate_total == 0 then
              r.ImGui_TextDisabled(ctx, "No matching filename found.")
            else
              local page_total = math.max(1, math.ceil(candidate_total / 3))
              local page = math.max(1, math.min(event.candidate_page or 1, page_total))
              event.candidate_page = page
              local first_candidate = (page - 1) * 3 + 1
              local last_candidate = math.min(candidate_total, first_candidate + 2)
              if begin_candidate_table("queue_event_" .. event_index) then
                local terms = #words_from(event.tag)
                for candidate_index=first_candidate,last_candidate do draw_candidate_table_row(event.candidates[candidate_index], "queue_" .. event_index .. "_" .. candidate_index, terms, event.start, event.tag, event.category) end
                r.ImGui_EndTable(ctx)
              end
              if page_total > 1 then
                if r.ImGui_Button(ctx, "<##queue_prev_" .. event_index, 24, 0) then event.candidate_page = math.max(1, page - 1) end
                r.ImGui_SameLine(ctx)
                r.ImGui_TextDisabled(ctx, string.format("Candidates %d–%d of %d · page %d / %d", first_candidate, last_candidate, candidate_total, page, page_total))
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, ">##queue_next_" .. event_index, 24, 0) then event.candidate_page = math.min(page_total, page + 1) end
              end
            end
            r.ImGui_Separator(ctx)
          end
        end
      end
      r.ImGui_Separator(ctx)
      local mma_open = r.ImGui_CollapsingHeader(ctx, "MMAUDIO GENERATE", true) or request_mmaudio
      if mma_open then
      local changed
      r.ImGui_Text(ctx, "INPUT MODE")
      if r.ImGui_RadioButton(ctx, "Video2Audio", mma_input_mode == "video") then
        mma_input_mode = "video"; use_video = true; save_setting("mma_input_mode", mma_input_mode); save_setting("use_video", 1)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Text2Audio", mma_input_mode == "text") then
        mma_input_mode = "text"; use_video = false; save_setting("mma_input_mode", mma_input_mode); save_setting("use_video", 0)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Image2Audio", mma_input_mode == "image") then
        mma_input_mode = "image"; use_video = false; save_setting("mma_input_mode", mma_input_mode); save_setting("use_video", 0)
      end
      r.ImGui_SameLine(ctx)
      changed, use_time_selection = r.ImGui_Checkbox(ctx, "Use Time Selection (else scene item)", use_time_selection)
      if changed then save_setting("use_time_selection", use_time_selection and 1 or 0) end
      if mma_input_mode == "image" then
        r.ImGui_TextDisabled(ctx, "A reference frame is extracted automatically from the video track at the generation start.")
      end
      changed, variations = r.ImGui_SliderInt(ctx, "Variations", variations, 1, 4); if changed then save_setting("variations",variations) end
      changed, seed = r.ImGui_InputInt(ctx, "Seed (-1 random)", seed); if changed then save_setting("seed",seed) end
      if r.ImGui_InputTextMultiline then
        r.ImGui_Text(ctx, "PROMPT OVERRIDE")
        r.ImGui_TextDisabled(ctx, "Optional alternative sound description")
        changed, custom_prompt = r.ImGui_InputTextMultiline(ctx, "##prompt_override", custom_prompt, -1, 70)
        if changed then save_setting("prompt",custom_prompt) end
      end
      changed, negative_prompt = r.ImGui_InputText(ctx, "Negative prompt", negative_prompt); if changed then save_setting("negative",negative_prompt) end
      changed, guidance = r.ImGui_SliderDouble(ctx, "Guidance", guidance, 1, 10); if changed then save_setting("guidance",guidance) end
      changed, steps = r.ImGui_SliderInt(ctx, "Steps", steps, 5, 50); if changed then save_setting("steps",steps) end
      end -- MMAUDIO GENERATE
      if r.ImGui_CollapsingHeader(ctx, "STABLEDAW DESIGN FX", true) or request_stabledaw then
        changed, sd_prompt = r.ImGui_InputTextMultiline(ctx, "##sd_prompt", sd_prompt, -1, 55); if changed then save_setting("sd_prompt",sd_prompt) end
        changed, sd_negative = r.ImGui_InputText(ctx, "SD Negative", sd_negative); if changed then save_setting("sd_negative",sd_negative) end
        changed, sd_duration = r.ImGui_SliderDouble(ctx, "SD Duration", sd_duration, 1, 30); if changed then save_setting("sd_duration",sd_duration) end
        changed, sd_steps = r.ImGui_SliderInt(ctx, "SD Steps", sd_steps, 4, 30); if changed then save_setting("sd_steps",sd_steps) end
        changed, sd_cfg = r.ImGui_SliderDouble(ctx, "SD CFG", sd_cfg, 0.1, 5); if changed then save_setting("sd_cfg",sd_cfg) end
        changed, sd_seed = r.ImGui_InputInt(ctx, "SD Seed (-1 random)", sd_seed); if changed then save_setting("sd_seed",sd_seed) end
        if request_stabledaw then request_stabledaw = false
          local sd_tags = selected_prompt(); local sd_text = sd_prompt ~= "" and (sd_prompt .. (sd_tags ~= "" and ", " or "") .. sd_tags) or sd_tags
          if sd_text == "" then sd_text = "cinematic sound effect" end
          local out = cache_root() .. "/stabledaw_" .. tostring(os.time()) .. ".wav"
          local sd_log = out .. ".log"
          local sd_err = out .. ".err.log"
          local py = setting("python", "C:/Users/User/AppData/Local/Programs/Python/Python311/python.exe")
          local client = setting("stabledaw_client", "E:/Codex/pinokio_agent/skills/local/stabledaw/clients/generate.py")
          local ps = cache_root() .. "/stabledaw_run.ps1"
          local lf0 = io.open(sd_log, "wb"); if lf0 then lf0:write("StableDaw launch started\n"); lf0:close() end
          local function q(x) return "'" .. tostring(x):gsub("'", "''") .. "'" end
          local body = "& "..q(py).." -u "..q(client).." --base-url 'http://127.0.0.1:8600'"
            .." --prompt "..q(sd_text).." --negative-prompt "..q(sd_negative).." --duration "..q(sd_duration).." --steps "..q(sd_steps).." --cfg-scale "..q(sd_cfg).." --seed "..q(sd_seed).." --output "..q(out)
          local f=io.open(ps,"wb"); if f then f:write(body); f:close() else r.ShowMessageBox("Cannot create StableDaw runner script:\n"..ps,"SBP StableDaw",0); return end
          local lf1 = io.open(sd_log, "ab"); if lf1 then lf1:write("Runner: "..body.."\n"); lf1:close() end
          -- Execute inline, matching the verified manual PowerShell command.
          os.execute('powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "' .. body .. '"')
          if file_exists(out) then
            -- StableDaw may pad short generations; trim the returned WAV to the requested duration.
            local ff = setting("ffmpeg", r.GetResourcePath() .. "/UserPlugins/ffmpeg.exe")
            local trimmed = out .. ".trim.wav"
            os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "& '..q(ff)..' -y -i '..q(out)..' -t '..q(sd_duration)..' -c:a pcm_s24le '..q(trimmed)..' 2>$null"')
            if file_exists(trimmed) then out = trimmed end
            r.SetEditCurPos(r.GetCursorPosition(),false,false); r.InsertMedia(out,0)
          else
            local lf=io.open(sd_log,"rb"); local msg=lf and lf:read("*a") or "(no log)"; if lf then lf:close() end
            local le=io.open(sd_err,"rb"); local em=le and le:read("*a") or ""; if le then le:close() end
            if em ~= "" then msg=msg.."\nSTDERR:\n"..em end
            if #msg>1800 then msg=msg:sub(-1800) end
            r.ShowMessageBox("StableDaw did not create a WAV file.\n\nLog:\n"..msg,"SBP StableDaw",0)
          end
        end
      end
      local selected_count = 0
      for _, is_selected in pairs(selected_tags) do
        if is_selected then selected_count = selected_count + 1 end
      end
      if request_mmaudio then request_mmaudio = false
        local prompt = selected_prompt()
        if prompt == "" then prompt = custom_prompt ~= "" and custom_prompt or "cinematic sound effects" end
        local scene = item_at_cursor()
        local start = scene and r.GetMediaItemInfo_Value(scene, "D_POSITION") or r.GetCursorPosition()
        local length = scene and r.GetMediaItemInfo_Value(scene, "D_LENGTH") or 8
        local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if use_time_selection and ts_end > ts_start then start, length = ts_start, ts_end-ts_start end
        local root = cache_root()
        local video, source_time = "", 0
        if mma_input_mode == "video" or mma_input_mode == "image" then video, source_time = video_source_at_position(start) end
        if (mma_input_mode == "video" or mma_input_mode == "image") and video=="" then r.ShowMessageBox("Video was not found on track: "..VIDEO_TRACK_NAME,"SBP MMAudio",0)
        else
          local source_key = (mma_input_mode == "video" or mma_input_mode == "image") and (video .. "|" .. tostring(source_time)) or "text"
          local key_source = mma_input_mode .. "|" .. source_key .. "|" .. tostring(start) .. "|" .. tostring(length) .. "|" .. prompt .. "|" .. tostring(seed)
          local cache_id = "mmaudio_v2_" .. cache_hash(key_source)
          local base = root .. "/clips/" .. cache_id
          local clip, frame = base..".mp4", base.."_frame.jpg"
          start, length, seed = tonumber(start) or 0, tonumber(length) or 8, tonumber(seed) or -1
          local ffmpeg = setting("ffmpeg", r.GetResourcePath() .. "/UserPlugins/ffmpeg.exe")
          local ff_log = base .. "_ffmpeg_clip.log"
          local ff_script = "& "..psq(ffmpeg).." '-y' '-ss' "..psq(tostring(source_time)).." '-i' "..psq(video).." '-t' "..psq(tostring(length + 0.5)).." '-c:v' 'libx264' '-preset' 'ultrafast' '-c:a' 'aac' "..psq(clip).." 2> "..psq(ff_log).."; exit $LASTEXITCODE"
          if mma_input_mode == "video" and not file_exists(clip) then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "'..ff_script..'"') end
          if mma_input_mode == "video" and not file_exists(clip) then
            local ef=io.open(ff_log,"rb"); local et=ef and ef:read("*a") or "(log is empty)"; if ef then ef:close() end
            if #et>1800 then et=et:sub(-1800) end
            r.ShowMessageBox("FFmpeg did not create the temporary video clip.\n\nSource: "..video.."\nTime: "..tostring(start).." sec.\n\n"..et,"SBP MMAudio",0); return
          end
          local frame_script = "& "..psq(ffmpeg).." '-y' '-ss' "..psq(tostring(source_time)).." '-i' "..psq(video).." '-frames:v' '1' '-vf' "..psq("scale=1280:-2").." '-q:v' '2' "..psq(frame).." 2> "..psq(ff_log).."; exit $LASTEXITCODE"
          if mma_input_mode == "image" and not file_exists(frame) then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "'..frame_script..'"') end
          if mma_input_mode == "image" and not file_exists(frame) then
            local ef=io.open(ff_log,"rb"); local et=ef and ef:read("*a") or "(log is empty)"; if ef then ef:close() end
            if #et>1800 then et=et:sub(-1800) end
            r.ShowMessageBox("FFmpeg did not create a reference frame for Image2Audio.\n\nSource: "..video.."\nTime: "..tostring(source_time).." sec.\n\n"..et,"SBP MMAudio",0); return
          end
          local py=setting("python","C:/Users/User/AppData/Local/Programs/Python/Python311/python.exe"); local client=setting("mmaudio_client","E:/Codex/pinokio_agent/skills/local/mmaudio-git/clients/generate.py")
          local client_log = base .. "_mmaudio.log"
          local lf0 = io.open(client_log, "wb"); if lf0 then lf0:write("MMAudio client launched...\n"); lf0:close() end
          if not file_exists(py) then r.ShowMessageBox("Python was not found:\n"..py,"SBP MMAudio",0); return end
          if not file_exists(client) then r.ShowMessageBox("MMAudio client was not found:\n"..client,"SBP MMAudio",0); return end
          local runner = base .. "_mmaudio_runner.ps1"
          local client_err = base .. "_mmaudio_error.log"
          local generated_count = 0
          for variation=1,variations do
            local variation_out = base .. "_generated_" .. variation .. (mma_input_mode == "text" and ".wav" or ".mp4")
            local variation_seed = seed < 0 and -1 or seed + variation - 1
            local input_args = ""
            if mma_input_mode == "video" then input_args = ","..psq('--video')..","..psq(clip)
            elseif mma_input_mode == "image" then input_args = ","..psq('--image')..","..psq(frame) end
            local script = "$ErrorActionPreference='Continue'\n$p=Start-Process -FilePath "..psq(py)
              .. " -ArgumentList @("..psq(client)..","..psq('--base-url')..","..psq('http://127.0.0.1:42003')..input_args..","..psq('--prompt')..","..psq(prompt)..","..psq('--negative')..","..psq(negative_prompt)..","..psq('--steps')..","..psq(tostring(steps))..","..psq('--guidance')..","..psq(tostring(guidance))..","..psq('--duration')..","..psq(tostring(length))..","..psq('--seed')..","..psq(tostring(variation_seed))..","..psq('--output')..","..psq(variation_out)..") -Wait -PassThru -RedirectStandardOutput "..psq(client_log).." -RedirectStandardError "..psq(client_err).."\nexit $p.ExitCode\n"
          local rf = io.open(runner, "wb"); if rf then rf:write(script); rf:close() end
          if not file_exists(variation_out) then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' .. runner .. '"') end
          local out = variation_out
          if file_exists(out) then
            local wav = mma_input_mode ~= "text" and (base .. "_generated_" .. variation .. ".wav") or out
            if mma_input_mode ~= "text" then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "& '..psq(ffmpeg)..' -y -i '..psq(out)..' -t '..psq(tostring(length))..' -vn -acodec pcm_s24le '..psq(wav)..' 2>$null; exit $LASTEXITCODE"') end
            if not file_exists(wav) then r.ShowMessageBox("MMAudio created an MP4, but WAV extraction failed.","SBP MMAudio",0); return end
            local target, target_index
            local range_end = start + length
            for ti=0,r.CountTracks(0)-1 do
              local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
              if n==GENERATED_TRACK_NAME or n:sub(1,#GENERATED_TRACK_NAME+1)==GENERATED_TRACK_NAME.." " then
                local occupied=false
                for ii=0,r.CountTrackMediaItems(tr)-1 do
                  local it=r.GetTrackMediaItem(tr,ii); local ip=r.GetMediaItemInfo_Value(it,"D_POSITION"); local ie=ip+r.GetMediaItemInfo_Value(it,"D_LENGTH")
                  if ip < range_end and ie > start then occupied=true; break end
                end
                if not occupied then target=tr; target_index=ti; break end
              end
            end
            if not target then
              r.InsertTrackAtIndex(r.CountTracks(0), true)
              target=r.GetTrack(0,r.CountTracks(0)-1)
              local suffix=1
              while true do
                local candidate=GENERATED_TRACK_NAME .. " " .. suffix; local taken=false
                for ti=0,r.CountTracks(0)-1 do local _,n=r.GetTrackName(r.GetTrack(0,ti),""); if n==candidate then taken=true end end
                if not taken then r.GetSetMediaTrackInfo_String(target,"P_NAME",candidate,true); break end
                suffix=suffix+1
              end
            end
            for ti=0,r.CountTracks(0)-1 do r.SetMediaTrackInfo_Value(r.GetTrack(0,ti),"I_SELECTED",0) end
            r.SetMediaTrackInfo_Value(target,"I_SELECTED",1)
            local old_cursor=r.GetCursorPosition()
            r.SetEditCurPos(start, false, false)
            local new_item = r.InsertMedia(wav,0)
            -- InsertMedia may return only a success flag in some REAPER builds.
            -- Resolve the actual MediaItem from the destination track before
            -- calling MediaItem APIs (important for variation 2+).
            if new_item then
              local resolved = nil
              for ii=0,r.CountTrackMediaItems(target)-1 do
                local candidate = r.GetTrackMediaItem(target, ii)
                local pos = r.GetMediaItemInfo_Value(candidate, "D_POSITION")
                if math.abs(pos - start) < 0.01 then resolved = candidate end
              end
              new_item = resolved
            end
            if new_item then
              local tag_name = safe_name(prompt)
              local take = r.GetActiveTake(new_item)
              if take then r.GetSetMediaItemTakeInfo_String(take,"P_NAME","AI_"..tag_name.."_V"..variation,true) end
              local meta = string.format("AI MMAUDIO\nMode: %s\nSeed: %s\nPrompt: %s\nNegative: %s\nGuidance: %s\nSteps: %s\nRange start: %.3f\nRange length: %.3f", mma_input_mode, tostring(variation_seed), prompt, negative_prompt, tostring(guidance), tostring(steps), start, length)
              r.GetSetMediaItemInfo_String(new_item,"P_NOTES",meta,true)
            end
            r.SetEditCurPos(old_cursor, false, false)
            generated_count = generated_count + 1
          else
            local lf = io.open(client_log, "rb"); local logtxt = lf and lf:read("*a") or ""; if lf then lf:close() end
            local le = io.open(client_err, "rb"); local errtxt = le and le:read("*a") or ""; if le then le:close() end
            logtxt = logtxt .. (errtxt ~= "" and ("\nSTDERR:\n" .. errtxt) or "\n(stderr is empty)")
            if #logtxt > 1600 then logtxt = logtxt:sub(-1600) end
            if generated_count == 0 and variation == variations then
              local source = mma_input_mode == "video" and clip or (mma_input_mode == "image" and frame or "text prompt only")
              r.ShowMessageBox("MMAudio did not create any result.\n\nMode: "..mma_input_mode.."\nInput: "..source.."\nPython: "..py.."\n\nLog:\n"..logtxt,"SBP MMAudio",0)
            end
          end
        end
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, "Checkbox = generate selection; click tag = copy")
      r.ImGui_TextDisabled(ctx, "Click a tag to copy it to the clipboard")
      if #groups == 0 then r.ImGui_TextWrapped(ctx, "No categories detected. Click Copy All to copy the raw analysis.") end
    end
    r.ImGui_End(ctx)
  end
  pop_app_style(style_count)
  if open then
    r.defer(loop)
  elseif r.ImGui_DestroyContext then
    -- Older ReaImGui releases release the context automatically.
    r.ImGui_DestroyContext(ctx)
  end
end

r.defer(loop)
