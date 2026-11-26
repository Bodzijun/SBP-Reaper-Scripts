-- @description ReaComfy - Import latest Video Output node result
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
  local file = io.open(cache .. "/reacomfy_video.json", "r")
  if file then content = file:read("*a"); file:close(); if content then break end end
end
if not content then log("Video output manifest was not found."); return end
local path = content:match('"video_path"%s*:%s*"(.-)"')
local label = content:match('"label"%s*:%s*"(.-)"') or "ComfyUI Video"
if not path then log("Video output manifest has no video_path."); return end
path = path:gsub("\\\\", "\\"):gsub('\\"', '"')
if not reaper.file_exists(path) then log("Video output file was not found: " .. path); return end
local track
for i = 0, reaper.CountTracks(0) - 1 do
  local candidate = reaper.GetTrack(0, i)
  local _, name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
  if name == label then track = candidate; break end
end
if not track then
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", label, true)
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
reaper.Undo_EndBlock("Import ReaComfy video output", -1)
reaper.UpdateArrange()
log("Imported video output: " .. path)
