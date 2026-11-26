-- @description ReaComfy - Send chord text to ComfyUI
-- @version 0.1.0
-- @noindex

local script_path = ({reaper.get_action_context()})[2]
local root = script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$") or debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local function log(message) reaper.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n") end
local function escape(value) return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n") end
local project_dir = reaper.GetProjectPathEx(0, "")
local cache = project_dir ~= "" and project_dir .. "/REAPER_AI_CACHE" or root .. "/runtime"
reaper.RecursiveCreateDirectory(cache, 0)
local chords_track_name = reaper.GetExtState("REAPER_AI", "yue2_chords_track")
if chords_track_name == "" then chords_track_name = "Chords" end
local function normalized_name(value) return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower() end
local wanted_chords_track = normalized_name(chords_track_name)
local lines = {}
for index = 0, reaper.CountMediaItems(0) - 1 do
  local item = reaper.GetMediaItem(0, index)
  local track = reaper.GetMediaItem_Track(item)
  local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if track_name and normalized_name(track_name) == wanted_chords_track then
    local _, text_value = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    if not text_value or text_value:gsub("%s", "") == "" then
      local take = reaper.GetActiveTake(item)
      if take then _, text_value = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false) end
    end
    if text_value and text_value:gsub("%s", "") ~= "" then
      local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      lines[#lines + 1] = {position = position, finish = position + math.max(0, length), text = text_value:gsub("\r\n", "\n")}
    end
  end
end
if #lines == 0 then log("No chord text found on a track named Chords."); return end
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor(os.clock() * 1000) % 1000)
os.remove(cache .. "/comfy_to_reaper.json")
local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_root then os.remove(user_root .. "/REAPER_AI_CACHE/comfy_to_reaper.json") end
local raw_lines = {}
for _, line in ipairs(lines) do raw_lines[#raw_lines + 1] = string.format("%.6f|%s", line.position, line.text) end
local text = table.concat(raw_lines, "\n")
local function tag_for_region(name)
  local lower = tostring(name or ""):lower()
  if lower:match("intro") then return "Intro" end
  if lower:match("pre[%s%-_]*chorus") then return "Pre-Chorus" end
  if lower:match("chorus") or lower:match("hook") then return "Chorus" end
  if lower:match("verse") then return "Verse" end
  if lower:match("bridge") then return "Bridge" end
  if lower:match("outro") or lower:match("ending") then return "Outro" end
  return tostring(name or "Section"):gsub("[%[%]]", "")
end
local chord_prompt_parts = {}
local used = {}
local regions = {}
for index = 0, reaper.CountProjectMarkers(0) - 1 do
  local _, is_region, start_time, end_time, name = reaper.EnumProjectMarkers3(0, index)
  if is_region then regions[#regions + 1] = {start_time, end_time, tag_for_region(name)} end
end
table.sort(regions, function(a, b) return a[1] < b[1] end)
for _, region in ipairs(regions) do
  local section = {}
  for index, line in ipairs(lines) do
    local overlaps = line.position < region[2] and line.finish > region[1]
    if line.finish <= line.position then overlaps = line.position >= region[1] and line.position < region[2] end
    if overlaps then
      section[#section + 1] = line.text
      used[index] = true
    end
  end
  if #section > 0 then
    chord_prompt_parts[#chord_prompt_parts + 1] = "[" .. region[3] .. "] " .. table.concat(section, " ")
  end
end
for index, line in ipairs(lines) do
  if not used[index] then chord_prompt_parts[#chord_prompt_parts + 1] = line.text end
end
local chord_prompt = table.concat(chord_prompt_parts, "\n\n")
local file = io.open(cache .. "/reaper_to_comfy.json", "w")
if not file then log("Cannot write chord manifest: " .. cache); return end
file:write(string.format('{"source":"chords","job_id":"%s","text":"%s","chords":"%s"}', job_id, escape(chord_prompt), escape(text)))
file:close()
log("Chord text is ready for ComfyUI: " .. cache .. "/reaper_to_comfy.json")
