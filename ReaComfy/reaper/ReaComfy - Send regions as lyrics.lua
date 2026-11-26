-- @description ReaComfy - Send REAPER regions as YuE2 lyrics
-- @version 0.1.0
-- @noindex
-- @about Builds section-tagged lyrics from project regions and writes the ReaComfy text manifest.

local script_path = ({reaper.get_action_context()})[2]
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/]reaper[\\/][^\\/]+$")

local function log(message)
  reaper.ShowConsoleMsg("REAPER AI: " .. message .. "\n")
end

local function json_escape(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function cache_path()
  local project_dir = reaper.GetProjectPathEx(0, "")
  if project_dir and project_dir ~= "" then
    local cache = project_dir .. "/REAPER_AI_CACHE"
    reaper.RecursiveCreateDirectory(cache, 0)
    return cache
  end
  local cache = root .. "/runtime"
  reaper.RecursiveCreateDirectory(cache, 0)
  return cache
end

local function publish_cache_pointer(cache)
  local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
  if not user_root then return end
  local bridge_cache = user_root .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(bridge_cache, 0)
  local pointer = io.open(bridge_cache .. "/current_project.txt", "w")
  if pointer then pointer:write(cache); pointer:close() end
end

local function section_tag(name)
  local lower = tostring(name or ""):lower()
  if lower:match("intro") then return "Intro" end
  if lower:match("pre[%s%-_]*chorus") then return "Pre-Chorus" end
  if lower:match("chorus") or lower:match("hook") then return "Chorus" end
  if lower:match("verse") then return "Verse" end
  if lower:match("bridge") then return "Bridge" end
  if lower:match("outro") or lower:match("ending") then return "Outro" end
  if lower:match("interlude") then return "Interlude" end
  local clean = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  clean = clean:gsub("[%[%]]", "")
  return clean ~= "" and clean or "Section"
end

local lyrics_track_name = reaper.GetExtState("REAPER_AI", "yue2_lyrics_track")
if lyrics_track_name == "" then lyrics_track_name = "Lyrics" end
local function normalized_name(value) return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower() end
local wanted_lyrics_track = normalized_name(lyrics_track_name)

local function collect_region_text(start_time, end_time)
  local lines = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if not track_name or normalized_name(track_name) ~= wanted_lyrics_track then goto continue end
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = position + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if position >= start_time and position < end_time and item_end > start_time then
      local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      if notes and notes:gsub("%s", "") ~= "" then
        lines[#lines + 1] = notes:gsub("\r\n", "\n")
      else
        local take = reaper.GetActiveTake(item)
        if take and not reaper.TakeIsMIDI(take) then
          local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          if name and name:gsub("%s", "") ~= "" then lines[#lines + 1] = name end
        end
      end
    end
    ::continue::
  end
  return table.concat(lines, "\n")
end

local regions = {}
local index = 0
while true do
  local retval, is_region, start_time, end_time, name = reaper.EnumProjectMarkers3(0, index)
  if retval == 0 then break end
  if is_region then
    regions[#regions + 1] = {start_time = start_time, end_time = end_time, name = name or "Section"}
  end
  index = index + 1
end

if #regions == 0 then
  log("No project regions found. Create regions and add lyrics in item notes.")
  return
end

table.sort(regions, function(a, b) return a.start_time < b.start_time end)
local sections = {}
local manifest_regions = {}
for _, region in ipairs(regions) do
  local tag = section_tag(region.name)
  local body = collect_region_text(region.start_time, region.end_time)
  sections[#sections + 1] = "[" .. tag .. "]"
  if body ~= "" then sections[#sections + 1] = body end
  sections[#sections + 1] = ""
  manifest_regions[#manifest_regions + 1] = string.format(
    '{"name":"%s","tag":"%s","start":%.6f,"end":%.6f}',
    json_escape(region.name), json_escape(tag), region.start_time, region.end_time)
end

local text = table.concat(sections, "\n"):gsub("\n+$", "")
local cache = cache_path()
publish_cache_pointer(cache)
os.remove(cache .. "/comfy_to_reaper.json")
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor(os.clock() * 1000) % 1000)
local manifest = io.open(cache .. "/reaper_to_comfy.json", "w")
if not manifest then
  log("Could not create ReaComfy text manifest: " .. cache)
  return
end
local payload = string.format('{"source":"regions","job_id":"%s","text":"%s","regions":[%s]}', job_id, json_escape(text), table.concat(manifest_regions, ","))
manifest:write(payload)
manifest:close()
local lyrics_file = io.open(cache .. "/reacomfy_lyrics.txt", "w")
if lyrics_file then lyrics_file:write(text); lyrics_file:close() end
local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_root then
  local fallback = user_root .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(fallback, 0)
  os.remove(fallback .. "/comfy_to_reaper.json")
  local fallback_file = io.open(fallback .. "/reaper_to_comfy.json", "w")
  if fallback_file then
    fallback_file:write(payload)
    fallback_file:close()
    local fallback_lyrics = io.open(fallback .. "/reacomfy_lyrics.txt", "w")
    if fallback_lyrics then fallback_lyrics:write(text); fallback_lyrics:close() end
    log("ComfyUI fallback manifest: " .. fallback .. "/reaper_to_comfy.json")
  else
    log("Could not write ComfyUI fallback manifest: " .. fallback)
  end
end
log("Regions converted to YuE2 lyrics: " .. #regions .. " section(s).")
log("Lyrics manifest: " .. cache .. "/reaper_to_comfy.json")
