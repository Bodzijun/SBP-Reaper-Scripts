-- @description ReaComfy - Import latest YuE2 Score Output as MIDI
-- @version 0.1.0
-- @noindex

local script_path = ({reaper.get_action_context()})[2]
if script_path then script_path = script_path:gsub("^@", "") end
local source_path = debug.getinfo(1, "S").source:sub(2):gsub("^@", "")
local root = (script_path and script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$"))
  or source_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
if not root and reaper.GetResourcePath then
  local scripts_root = reaper.GetResourcePath() .. "/Scripts/ReaComfy"
  if reaper.file_exists(scripts_root .. "/reaper/AI Workflow Launcher.lua") then root = scripts_root end
end
local function log(message) reaper.ShowConsoleMsg("ReaComfy: " .. message .. "\n") end
if not root then log("Could not locate the ReaComfy folder."); return end

local project_dir = reaper.GetProjectPathEx(0, "")
local candidates = {}
if project_dir and project_dir ~= "" then candidates[#candidates + 1] = project_dir .. "/REAPER_AI_CACHE" end
candidates[#candidates + 1] = root .. "/runtime"
local profile = os.getenv("USERPROFILE") or os.getenv("HOME")
if profile then candidates[#candidates + 1] = profile .. "/REAPER_AI_CACHE" end

local content
for _, cache in ipairs(candidates) do
  local file = io.open(cache .. "/reacomfy_score.json", "r")
  if file then content = file:read("*a"); file:close(); if content then break end end
end
if not content then log("Score manifest was not found."); return end

local function json_path(key)
  local value = content:match('"' .. key .. '"%s*:%s*"(.-)"')
  if not value then return nil end
  return value:gsub("\\\\", "\\"):gsub('\\"', '"')
end
local midi_path = json_path("midi_path")
local abc_path = json_path("abc_path")
local lyrics_path = json_path("lyrics_path")
local midi_error = content:match('"midi_error"%s*:%s*"(.-)"')
local label = content:match('"label"%s*:%s*"(.-)"') or "YuE2 score"
if not midi_path or midi_path == "" or not reaper.file_exists(midi_path) then
  if midi_error then
    midi_error = midi_error:gsub("\\\\", "\\"):gsub('\\"', '"')
    log("Score MIDI export failed: " .. midi_error)
  else
    log("The score manifest has no readable MIDI export. Re-run REAPER Score Output with export_midi enabled.")
  end
  if abc_path then log("ABC source recorded at: " .. abc_path) end
  return
end

local track_name = reaper.GetExtState("REAPER_AI", "score_output_track_name")
if track_name == "" then track_name = "YuE2 Score" end
local destination = reaper.GetExtState("REAPER_AI", "score_output_destination")
local track
if destination == "selected" then track = reaper.GetSelectedTrack(0, 0) end
if not track then
  for i = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
    if name == track_name then track = candidate; break end
  end
end

local function find_or_create_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, i)
    local _, candidate_name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
    if candidate_name == name then return candidate end
  end
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local created = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(created, "P_NAME", name, true)
  return created
end

local function read_text(path)
  if not path or path == "" or not reaper.file_exists(path) then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function add_text_item(track_name, item_name, text, position)
  if not text or text == "" then return false end
  local item = reaper.AddMediaItemToTrack(find_or_create_track(track_name))
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(4.0, math.min(300.0, #text / 18.0)))
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", text, true)
  local take = reaper.AddTakeToMediaItem(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_name, true) end
  return true
end
if not track then
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", track_name, true)
end

local position = reaper.GetCursorPosition()
reaper.Undo_BeginBlock()
reaper.SetOnlyTrackSelected(track)
reaper.SelectAllMediaItems(0, false)
reaper.SetEditCurPos(position, true, false)
reaper.InsertMedia(midi_path, 0)
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
  local take = reaper.GetActiveTake(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", label, true) end
end
local imported_text = 0
if add_text_item("YuE2 Score ABC", label .. " — ABC", read_text(abc_path), position) then imported_text = imported_text + 1 end
if add_text_item("Lyrics", label .. " — Lyrics", read_text(lyrics_path), position) then imported_text = imported_text + 1 end
reaper.Undo_EndBlock("Import ReaComfy YuE2 score, ABC and lyrics", -1)
reaper.UpdateArrange()
log("Imported YuE2 score MIDI: " .. midi_path .. "; text items: " .. tostring(imported_text))
if abc_path and reaper.file_exists(abc_path) then log("ABC source: " .. abc_path) end
