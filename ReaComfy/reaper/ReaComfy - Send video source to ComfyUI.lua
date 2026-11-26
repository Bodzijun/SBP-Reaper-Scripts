-- @description ReaComfy - Send video source to ComfyUI
-- @version 1.0.0
-- @noindex
-- @about Publishes the full source video path for REAPER Video Input nodes.

local r = reaper
local function log(message) r.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n") end
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end
local function escape(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end
local function is_video(path)
  if not path or path == "" then return false end
  local lower = path:lower()
  return lower:match("%.mp4$") or lower:match("%.mov$") or lower:match("%.mkv$")
    or lower:match("%.avi$") or lower:match("%.webm$") or lower:match("%.mxf$")
    or lower:match("%.mts$") or lower:match("%.m2ts$") or lower:match("%.wmv$")
end

local track_name = r.GetExtState("REAPER_AI", "video_track_name")
local function allowed(item)
  if track_name == "" then return true end
  local track = r.GetMediaItem_Track(item)
  local _, name = r.GetTrackName(track, "")
  return name == track_name
end
local function item_source(item)
  local take = item and r.GetActiveTake(item)
  local source = take and r.GetMediaItemTake_Source(take) or nil
  local path = source and r.GetMediaSourceFileName(source, "") or ""
  local source_type = source and r.GetMediaSourceType and (r.GetMediaSourceType(source, "") or "") or ""
  if is_video(path) or source_type:lower():find("video", 1, true) then return path end
  return ""
end
local function find_item()
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if allowed(item) and item_source(item) ~= "" then return item end
  end
  local cursor = r.GetCursorPosition()
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ii = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, ii)
      local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local finish = start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if cursor >= start and cursor <= finish and allowed(item) and item_source(item) ~= "" then return item end
    end
  end
end

local item = find_item()
local path = item and item_source(item) or ""
if path == "" then
  log("No video source found. Select a video item or place the cursor on one.")
  return
end
if not exists(path) then
  log("Video source file was not found: " .. path)
  return
end

local project_path = r.GetProjectPath("")
if project_path == "" then project_path = r.GetResourcePath() .. "/Temp" end
local cache = project_path .. "/REAPER_AI_CACHE"
r.RecursiveCreateDirectory(cache, 0)
local manifest = cache .. "/reaper_to_comfy.json"
local f = io.open(manifest, "w")
if not f then log("Could not write video manifest: " .. manifest); return end
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000) % 1000000)
f:write('{"job_id":"', job_id, '","status":"complete","kind":"video_source","video_path":"', escape(path), '"}')
f:close()
log("Full video source is ready for ComfyUI: " .. path)
