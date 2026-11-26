-- @description ReaComfy - Import text output as REAPER items, regions or markers
-- @version 0.1.3
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

local content, manifest_path
for _, cache in ipairs(candidates) do
  local path = cache .. "/reacomfy_text.json"
  local file = io.open(path, "r")
  if file then content = file:read("*a"); file:close(); if content then manifest_path = path; break end end
end
if not content then log("Text manifest was not found. Run REAPER Text Output first."); return end

local function json_string(key, fallback)
  local value = content:match('"' .. key .. '"%s*:%s*"(.-)"')
  if not value then return fallback end
  return value:gsub("\\\\", "\\"):gsub('\\"', '"'):gsub("\\n", "\n")
end
local mode = json_string("mode", "items")
local track_name = json_string("track_name", "TTS Subtitles")
local label = json_string("label", "ComfyUI Text")
local segments_path = json_string("segments_path", "")
if not segments_path or segments_path == "" or not reaper.file_exists(segments_path) then
  log("Text manifest has no readable segments file: " .. tostring(segments_path)); return
end

local function unescape(value)
  value = value:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t"):gsub('\\"', '"')
  return value:gsub("\\\\", "\\")
end
local function find_or_create_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, current = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if current == name then return track end
  end
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  local track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  return track
end
local function add_item(track, start_time, end_time, text)
  local item = reaper.AddMediaItemToTrack(track)
  if not item then return false end
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_time)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.05, end_time - start_time))
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", text, true)
  local take = reaper.AddTakeToMediaItem(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", label, true) end
  reaper.SetMediaItemSelected(item, true)
  return true
end

local file = io.open(segments_path, "r")
if not file then log("Could not open segments file."); return end
local cursor = reaper.GetCursorPosition()
-- A corrupted/overflowed REAPER cursor can return an enormous value. Do not
-- place subtitles billions of seconds away or force the arrange view there.
if not cursor or cursor ~= cursor or cursor < 0 or cursor > 86400 * 30 then
  log("Invalid edit-cursor position detected (" .. tostring(cursor) .. "); using 0 seconds.")
  cursor = 0
end
local track = mode == "items" and find_or_create_track(track_name) or nil
local count, first_time, last_time = 0, nil, nil
reaper.Undo_BeginBlock()
for line in file:lines() do
  local start_value, end_value, text = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
  local start_time, end_time = tonumber(start_value), tonumber(end_value)
  local valid_range = start_time and end_time and start_time >= -86400 * 30 and end_time >= start_time and end_time <= 86400 * 30
  if valid_range then
    start_time, end_time = start_time + cursor, end_time + cursor
    text = unescape(text or "")
    local title = text ~= "" and text or label
    local created = false
    if mode == "regions" then
      created = reaper.AddProjectMarker2(0, true, start_time, end_time, title, -1, 0) >= 0
    elseif mode == "markers" then
      created = reaper.AddProjectMarker2(0, false, start_time, 0, title, -1, 0) >= 0
    else
      created = add_item(track, start_time, end_time, text)
    end
    if created then
      if not first_time then first_time = start_time end
      last_time = end_time
      count = count + 1
    end
  elseif start_time and end_time then
    log("Skipping out-of-range text segment: " .. tostring(start_value) .. " -> " .. tostring(end_value))
  end
end
file:close()
reaper.Undo_EndBlock("Import ReaComfy text output", -1)
reaper.UpdateArrange()
if first_time then reaper.SetEditCurPos(first_time, true, false) end
if first_time then
  log("Imported " .. tostring(count) .. " text segment(s) as " .. mode .. " from " .. string.format("%.3f", first_time) .. "s to " .. string.format("%.3f", last_time) .. "s.")
else
  log("No REAPER objects were created from the parsed text segments.")
end
