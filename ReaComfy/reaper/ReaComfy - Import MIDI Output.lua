-- @description ReaComfy - Import latest MIDI Output node result
-- @version 0.1.0
-- @noindex

local source_path = debug.getinfo(1, "S").source:sub(2):gsub("^@", "")
local root = source_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local function log(message) reaper.ShowConsoleMsg("ReaComfy: " .. tostring(message) .. "\n") end
if not root then log("Could not locate the ReaComfy folder."); return end
local project_dir = reaper.GetProjectPathEx(0, "")
local candidates = {}
if project_dir and project_dir ~= "" then candidates[#candidates + 1] = project_dir .. "/REAPER_AI_CACHE" end
candidates[#candidates + 1] = root .. "/runtime"
local profile = os.getenv("USERPROFILE") or os.getenv("HOME")
if profile then candidates[#candidates + 1] = profile .. "/REAPER_AI_CACHE" end
local content
for _, cache in ipairs(candidates) do
  local file = io.open(cache .. "/reacomfy_midi.json", "r")
  if file then content = file:read("*a"); file:close(); if content then break end end
end
if not content then log("MIDI output manifest was not found."); return end
local path = content:match('"midi_path"%s*:%s*"(.-)"')
local notes_path = content:match('"notes_json"%s*:%s*"(.-)"')
local label = content:match('"label"%s*:%s*"(.-)"') or "ComfyUI MIDI"
if not path then log("MIDI output manifest has no midi_path."); return end
path = path:gsub("\\\\", "\\"):gsub('\\"', '"')
if notes_path then notes_path = notes_path:gsub("\\\\", "\\"):gsub('\\"', '"') end
if not reaper.file_exists(path) then log("MIDI output file was not found: " .. path); return end
local track_name = label ~= "" and label or "ComfyUI MIDI"
local track
for i = 0, reaper.CountTracks(0) - 1 do
  local candidate = reaper.GetTrack(0, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
  if name == track_name then track = candidate; break end
end
if not track then
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", track_name, true)
end
local function add_notes_item(text)
  if not text or text == "" then return false end
  local notes_track
  for i = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
    if name == "MIDI Notes" then notes_track = candidate; break end
  end
  if not notes_track then
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
    notes_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(notes_track, "P_NAME", "MIDI Notes", true)
  end
  local item = reaper.AddMediaItemToTrack(notes_track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", reaper.GetCursorPosition())
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(4.0, math.min(300.0, #text / 18.0)))
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", text, true)
  local take = reaper.AddTakeToMediaItem(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", label .. " — notes", true) end
  return true
end
reaper.Undo_BeginBlock()
reaper.SetOnlyTrackSelected(track)
reaper.SelectAllMediaItems(0, false)
reaper.SetEditCurPos(reaper.GetCursorPosition(), true, false)
reaper.InsertMedia(path, 0)
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
  local take = reaper.GetActiveTake(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", label, true) end
end
local notes_text
if notes_path and reaper.file_exists(notes_path) then
  local file = io.open(notes_path, "r")
  if file then notes_text = file:read("*a"); file:close() end
end
local notes_imported = add_notes_item(notes_text)
reaper.Undo_EndBlock("Import ReaComfy MIDI output", -1)
reaper.UpdateArrange()
log("Imported MIDI output: " .. path .. (notes_imported and "; notes_json added to MIDI Notes" or ""))
