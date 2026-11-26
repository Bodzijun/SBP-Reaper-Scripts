-- @description ReaComfy - Send selected reference audio to ComfyUI
-- @version 0.1.0
-- @noindex
-- @about Prepares one selected REAPER audio item for the REAPER Input node.

local script_path = ({reaper.get_action_context()})[2]
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local function log(message) reaper.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n") end
local function escape(value)
  return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end
local function source_path_from_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  local path = ""
  if source then
    local _, source_name = reaper.GetMediaSourceFileName(source, "")
    path = source_name or ""
  end
  if path and path ~= "" then
    if path:match("^%a:[\\/]") or path:match("^\\\\") or path:match("^/") then return path end
    local project_dir = reaper.GetProjectPathEx(0, "")
    if project_dir ~= "" then return project_dir .. "/" .. path end
  end
  local ok, chunk = reaper.GetItemStateChunk(item, "", false)
  local file = ok and chunk and chunk:match('[\r\n]FILE%s+"([^"]+)"') or nil
  if file and not file:match("^%a:[\\/]") and not file:match("^\\\\") and not file:match("^/") then
    local project_dir = reaper.GetProjectPathEx(0, "")
    if project_dir ~= "" then file = project_dir .. "/" .. file end
  end
  return file
end

local reference_track_name = reaper.GetExtState("REAPER_AI", "yue2_reference_track")
local item = nil
if reference_track_name and reference_track_name:gsub("%s", "") ~= "" then
  local wanted = reference_track_name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  for index = 0, reaper.CountMediaItems(0) - 1 do
    local candidate = reaper.GetMediaItem(0, index)
    local track = reaper.GetMediaItem_Track(candidate)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name and track_name:gsub("^%s+", ""):gsub("%s+$", ""):lower() == wanted then
      local candidate_take = reaper.GetActiveTake(candidate)
      if candidate_take and not reaper.TakeIsMIDI(candidate_take) then item = candidate; break end
    end
  end
  if not item then log("No audio reference item found on track: " .. reference_track_name); return end
else
  local selected = {}
  for index = 0, reaper.CountSelectedMediaItems(0) - 1 do selected[#selected + 1] = reaper.GetSelectedMediaItem(0, index) end
  if #selected ~= 1 then log("Select exactly one audio item as the reference."); return end
  item = selected[1]
end
local take = reaper.GetActiveTake(item)
if not take or reaper.TakeIsMIDI(take) then log("The selected item is not an audio reference."); return end
local path = source_path_from_item(item)
if not path or path == "" then log("Could not resolve the reference audio source."); return end
local project_dir = reaper.GetProjectPathEx(0, "")
local cache = project_dir ~= "" and project_dir .. "/REAPER_AI_CACHE" or root .. "/runtime"
reaper.RecursiveCreateDirectory(cache, 0)
local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
local job_id = tostring(os.time()) .. "_reference_" .. tostring(math.floor(os.clock() * 1000) % 1000)
os.remove(cache .. "/comfy_to_reaper.json")
local target_path = ""
local existing = io.open(cache .. "/reaper_to_comfy.json", "r")
if existing then
  local existing_text = existing:read("*a")
  existing:close()
  target_path = existing_text:match('"path"%s*:%s*"(.-)"') or ""
  target_path = target_path:gsub("\\\\", "\\")
end
local file = io.open(cache .. "/reaper_to_comfy.json", "w")
if not file then log("Cannot write reference manifest: " .. cache); return end
local target_field = target_path ~= "" and ('"path":"' .. escape(target_path) .. '",') or ""
file:write(string.format('{"source":"reference","job_id":"%s",%s"reference_path":"%s","reference_position":%.12f,"reference_length":%.12f}', job_id, target_field, escape(path), position, length))
file:close()
local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_root then
  local fallback = user_root .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(fallback, 0)
  local pointer = io.open(fallback .. "/current_project.txt", "w")
  if pointer and project_dir ~= "" then pointer:write(cache); pointer:close() end
end
log("Reference audio is ready for the REAPER Reference Input node: " .. path)
