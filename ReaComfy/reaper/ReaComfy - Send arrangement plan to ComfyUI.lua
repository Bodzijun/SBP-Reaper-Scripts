-- @description ReaComfy - Send arrangement plan to ComfyUI
-- @version 0.1.0
-- @noindex
local script_path = ({reaper.get_action_context()})[2]
local root = script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$") or debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local function log(message) reaper.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n") end
local function escape(value) return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n") end
local function section_tag(name)
  local lower = tostring(name or ""):lower()
  if lower:match("intro") then return "Intro" end
  if lower:match("pre[%s%-_]*chorus") then return "Pre-Chorus" end
  if lower:match("chorus") or lower:match("hook") then return "Chorus" end
  if lower:match("verse") then return "Verse" end
  if lower:match("bridge") then return "Bridge" end
  if lower:match("outro") or lower:match("ending") then return "Outro" end
  return tostring(name or "Section"):gsub("[%[%]]", "")
end
local project_dir = reaper.GetProjectPathEx(0, "")
local cache = project_dir ~= "" and project_dir .. "/REAPER_AI_CACHE" or root .. "/runtime"
reaper.RecursiveCreateDirectory(cache, 0)
local folder_name = reaper.GetExtState("REAPER_AI", "arrangement_folder_name")
if folder_name == "" then folder_name = "Arrangement" end
local function normalize_name(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end
local wanted_folder_name = normalize_name(folder_name)
local folder_index, folder_end = nil, nil
for track_index = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, track_index)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if normalize_name(name) == wanted_folder_name and reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
    folder_index = track_index
    local depth = 1
    for child = track_index + 1, reaper.CountTracks(0) - 1 do
      depth = depth + reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, child), "I_FOLDERDEPTH")
      -- The track carrying the closing folder depth is still a child track,
      -- so include it in the arrangement range.
      if depth <= 0 then folder_end = child; break end
    end
    folder_end = folder_end or reaper.CountTracks(0) - 1
    break
  end
end
local regions = {}
for index = 0, reaper.CountProjectMarkers(0) - 1 do
  local _, is_region, start_time, end_time, name = reaper.EnumProjectMarkers3(0, index)
  if is_region then regions[#regions + 1] = {start_time, end_time, section_tag(name)} end
end
table.sort(regions, function(a, b) return a[1] < b[1] end)
local sections = {}
for _, region in ipairs(regions) do
  local entries = {}
  for index = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, index)
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = position + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    -- Include every section touched by the item, not only the section where
    -- the item starts. Long sustained parts therefore continue into all
    -- following regions until their actual end.
    if item_end > region[1] and position < region[2] then
      local track = reaper.GetMediaItem_Track(item)
      local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
      local _, instrument = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      local in_arrangement_folder = folder_index and track_index > folder_index and track_index <= folder_end
      if in_arrangement_folder and instrument and instrument ~= "" then
        local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        local line = instrument
        if notes and notes:gsub("%s", "") ~= "" then line = line .. ": " .. notes:gsub("\r\n", " "):gsub("\n", " ") end
        entries[#entries + 1] = line
      end
    end
  end
  if #entries > 0 then sections[#sections + 1] = "[" .. region[3] .. "]\n" .. table.concat(entries, "\n") end
end
if not folder_index then
  log("Arrangement folder not found: " .. folder_name)
  return
end
if #sections == 0 then log("No arrangement items found inside project regions in folder: " .. folder_name); return end
local text = table.concat(sections, "\n\n")
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor(os.clock() * 1000) % 1000)
os.remove(cache .. "/comfy_to_reaper.json")
local file = io.open(cache .. "/reaper_to_comfy.json", "w")
if not file then log("Cannot write arrangement manifest: " .. cache); return end
file:write(string.format('{"source":"arrangement","job_id":"%s","folder":"%s","text":"%s"}', job_id, escape(folder_name), escape(text)))
file:close()
log("Arrangement plan is ready for ComfyUI: " .. cache .. "/reaper_to_comfy.json")
