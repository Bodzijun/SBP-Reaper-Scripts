-- @description ReaComfy - Export video from time selection
-- @version 1.0.0
-- @noindex
-- @about Creates a temporary FFmpeg video clip from the REAPER time selection and publishes it to REAPER Video Input.

local r = reaper

local function log(message)
  r.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n")
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function psq(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local function json_escape(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function is_video(path)
  if not path or path == "" then return false end
  local lower = path:lower()
  return lower:match("%.mp4$") or lower:match("%.mov$") or lower:match("%.mkv$")
    or lower:match("%.avi$") or lower:match("%.webm$") or lower:match("%.mxf$")
    or lower:match("%.mts$") or lower:match("%.m2ts$") or lower:match("%.wmv$")
end

local function source_is_video(source, path)
  if is_video(path) then return true end
  if source and r.GetMediaSourceType then
    local source_type = r.GetMediaSourceType(source, "") or ""
    return source_type:lower():find("video", 1, true) ~= nil
  end
  return false
end

local video_track_name = r.GetExtState("REAPER_AI", "video_track_name")
local cutscene_track_name = r.GetExtState("REAPER_AI", "cutscene_track_name")

local function track_allowed(item)
  if video_track_name == "" then return true end
  local track = r.GetMediaItem_Track(item)
  local _, name = r.GetTrackName(track, "")
  return name == video_track_name
end

local function cutscene_track_allowed(item)
  if cutscene_track_name == "" then return true end
  local track = r.GetMediaItem_Track(item)
  local _, name = r.GetTrackName(track, "")
  return name == cutscene_track_name
end

local function find_video_item(from_time, to_time)
  local selected_count = r.CountSelectedMediaItems(0)
  for pass = 1, 2 do
    local count = pass == 1 and selected_count or 0
    for i = 0, count - 1 do
      local item = pass == 1 and r.GetSelectedMediaItem(0, i) or nil
      if item and track_allowed(item) then
        local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local finish = start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local take = r.GetActiveTake(item)
        local source = take and r.GetMediaItemTake_Source(take) or nil
        local path = source and r.GetMediaSourceFileName(source, "") or ""
        if finish > from_time and start < to_time and source_is_video(source, path) then return item, path end
      end
    end
    if pass == 2 then
      for ti = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, ti)
        for ii = 0, r.CountTrackMediaItems(track) - 1 do
          local item = r.GetTrackMediaItem(track, ii)
          local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local finish = start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
          if finish > from_time and start < to_time and track_allowed(item) then
            local take = r.GetActiveTake(item)
            local source = take and r.GetMediaItemTake_Source(take) or nil
            local path = source and r.GetMediaSourceFileName(source, "") or ""
            if source_is_video(source, path) then return item, path end
          end
        end
      end
    end
  end
end

local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
if not ts_end or ts_end <= ts_start then
  local selected = r.CountSelectedMediaItems(0) > 0 and r.GetSelectedMediaItem(0, 0) or nil
  if selected and not cutscene_track_allowed(selected) then selected = nil end
  if not selected then
    local cursor = r.GetCursorPosition()
    for ti = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, ti)
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local candidate = r.GetTrackMediaItem(track, ii)
        local start = r.GetMediaItemInfo_Value(candidate, "D_POSITION")
        local finish = start + r.GetMediaItemInfo_Value(candidate, "D_LENGTH")
        if cursor >= start and cursor <= finish and cutscene_track_allowed(candidate) then selected = candidate; break end
      end
      if selected then break end
    end
  end
  if not selected or not cutscene_track_allowed(selected) then
    log("Set a time selection or select/place the cursor on a cutscene video item.")
    return
  end
  ts_start = r.GetMediaItemInfo_Value(selected, "D_POSITION")
  ts_end = ts_start + r.GetMediaItemInfo_Value(selected, "D_LENGTH")
  log(string.format("No time selection; using cutscene item %.3f-%.3f s.", ts_start, ts_end))
end

local item, source_path = find_video_item(ts_start, ts_end)
if not item then
  log("No video item overlaps the time selection. Select a video item or place it under the selection.")
  return
end
if not file_exists(source_path) then
  log("Video source file was not found: " .. source_path)
  return
end

local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
local clip_start = math.max(ts_start, item_start)
local clip_end = math.min(ts_end, item_end)
if clip_end <= clip_start then
  log("The selected range does not overlap the video item.")
  return
end

local take = r.GetActiveTake(item)
local source_offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
local playrate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
if not playrate or playrate == 0 then playrate = 1 end
local source_start = source_offset + (clip_start - item_start) * playrate
local duration = (clip_end - clip_start) * math.abs(playrate)

local project_path = r.GetProjectPath("")
if project_path == "" then project_path = r.GetResourcePath() .. "/Temp" end
local cache = project_path .. "/REAPER_AI_CACHE/reacomfy_video_input"
r.RecursiveCreateDirectory(cache, 0)
local stamp = os.date("%Y%m%d_%H%M%S")
local output = cache .. "/reaper_video_" .. stamp .. ".mp4"
local log_path = cache .. "/ffmpeg_" .. stamp .. ".log"
local is_windows = (r.GetOS and r.GetOS() or ""):match("^Win") ~= nil or package.config:sub(1, 1) == "\\"
local ffmpeg = "ffmpeg"
local ffmpeg_candidates = {
  r.GetResourcePath() .. "/UserPlugins/" .. (is_windows and "ffmpeg.exe" or "ffmpeg"),
}
if not is_windows then
  -- GUI apps on macOS do not inherit the shell PATH, so check common installs.
  ffmpeg_candidates[#ffmpeg_candidates + 1] = "/opt/homebrew/bin/ffmpeg"
  ffmpeg_candidates[#ffmpeg_candidates + 1] = "/usr/local/bin/ffmpeg"
  ffmpeg_candidates[#ffmpeg_candidates + 1] = "/usr/bin/ffmpeg"
end
for _, candidate in ipairs(ffmpeg_candidates) do
  if file_exists(candidate) then ffmpeg = candidate; break end
end

local function shq(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local command = "& " .. psq(ffmpeg)
  .. " '-y' '-ss' " .. psq(string.format("%.6f", source_start))
  .. " '-i' " .. psq(source_path)
  .. " '-t' " .. psq(string.format("%.6f", duration))
  .. " '-map' '0:v:0' '-map' '0:a?' '-c:v' 'libx264' '-preset' 'ultrafast' '-pix_fmt' 'yuv420p' '-c:a' 'aac' '-movflags' '+faststart' "
  .. psq(output) .. " 2> " .. psq(log_path) .. "; exit $LASTEXITCODE"

log(string.format("Exporting video selection %.3f-%.3f s with FFmpeg...", ts_start, ts_end))
local exit_code
if is_windows then
  exit_code = os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "' .. command .. '"')
else
  local posix_command = shq(ffmpeg)
    .. " -y -ss " .. shq(string.format("%.6f", source_start))
    .. " -i " .. shq(source_path)
    .. " -t " .. shq(string.format("%.6f", duration))
    .. " -map 0:v:0 -map '0:a?' -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -movflags +faststart "
    .. shq(output) .. " 2> " .. shq(log_path)
  exit_code = os.execute(posix_command)
end
if not file_exists(output) then
  log("FFmpeg did not create the video clip. See: " .. log_path)
  return
end

local manifest = cache .. "/reaper_to_comfy.json"
local f = io.open(manifest, "w")
if not f then
  log("Could not write video manifest: " .. manifest)
  return
end
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000) % 1000000)
f:write('{"job_id":"', job_id, '","status":"complete","kind":"video","video_path":"', json_escape(output), '"}')
f:close()

-- Keep the standard bridge location in sync so REAPER Video Input can find it.
local shared = project_path .. "/REAPER_AI_CACHE/reaper_to_comfy.json"
local sf = io.open(shared, "w")
if sf then
  sf:write('{"job_id":"', job_id, '","status":"complete","kind":"video","video_path":"', json_escape(output), '"}')
  sf:close()
end

log("Video input is ready for ComfyUI: " .. output)
