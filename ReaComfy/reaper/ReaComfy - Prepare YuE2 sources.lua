-- @description ReaComfy - Prepare selected YuE2 sources
-- @version 0.1.0
-- @noindex
-- @about Combines lyrics, MIDI, chords, arrangement and reference audio into one manifest.

local script_path = ({reaper.get_action_context()})[2]
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local function log(message) reaper.ShowConsoleMsg("REAPER AI: " .. tostring(message) .. "\n") end
local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a"); file:close(); return content
end
local function json_string(content, key)
  if not content then return nil end
  local marker = '"' .. key .. '":"'
  local start = content:find(marker, 1, true)
  if not start then return nil end
  local position, result = start + #marker, {}
  while position <= #content do
    local byte = content:sub(position, position)
    if byte == '"' then return table.concat(result) end
    if byte == "\\" then
      local escaped = content:sub(position + 1, position + 1)
      local map = {['n']='\n', ['r']='\r', ['t']='\t', ['"']='"', ['\\']='\\'}
      result[#result + 1] = map[escaped] or escaped
      position = position + 2
    else
      result[#result + 1] = byte; position = position + 1
    end
  end
end
local function json_escape(value)
  return tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end
local function number_value(content, key)
  if not content then return nil end
  return tonumber(content:match('"' .. key .. '":%s*([%+%-]?[%d%.]+)'))
end
local project_dir = reaper.GetProjectPathEx(0, "")
local cache = project_dir ~= "" and project_dir .. "/REAPER_AI_CACHE" or root .. "/runtime"
reaper.RecursiveCreateDirectory(cache, 0)
local manifest_path = cache .. "/reaper_to_comfy.json"
local function run_action(name)
  local ok, error_message = pcall(dofile, root .. "/reaper/" .. name)
  if not ok then log("Could not prepare " .. name .. ": " .. tostring(error_message)) end
  return read_file(manifest_path)
end
local lyrics_manifest, midi_manifest, chords_manifest, arrangement_manifest, reference_manifest
if reaper.GetExtState("REAPER_AI", "yue2_source_lyrics") == "1" then
  lyrics_manifest = run_action("ReaComfy - Send regions as lyrics.lua")
end
if reaper.GetExtState("REAPER_AI", "yue2_source_midi") == "1" then
  midi_manifest = run_action("ReaComfy - Send MIDI source to ComfyUI.lua")
end
if reaper.GetExtState("REAPER_AI", "yue2_source_chords") == "1" then
  chords_manifest = run_action("ReaComfy - Send chords to ComfyUI.lua")
end
if reaper.GetExtState("REAPER_AI", "yue2_source_arrangement") == "1" then
  arrangement_manifest = run_action("ReaComfy - Send arrangement plan to ComfyUI.lua")
end
if reaper.GetExtState("REAPER_AI", "yue2_source_reference") == "1" then
  reference_manifest = run_action("ReaComfy - Send reference audio to ComfyUI.lua")
end
local fields = {}
local function add_string(key, value)
  if value and value ~= "" then fields[#fields + 1] = string.format('"%s":"%s"', key, json_escape(value)) end
end
local function add_number(key, value)
  if value then fields[#fields + 1] = string.format('"%s":%.12f', key, value) end
end
local lyrics_text = json_string(lyrics_manifest, "text")
local chords_text = json_string(chords_manifest, "text")
local arrangement_text = json_string(arrangement_manifest, "text")
add_string("lyrics_text", lyrics_text)
add_string("lyrics_text_path", json_string(lyrics_manifest, "text_path"))
add_string("midi_path", json_string(midi_manifest, "midi_path"))
add_string("chords_text", chords_text)
add_string("chords_timed", json_string(chords_manifest, "chords"))
add_string("arrangement_text", arrangement_text)
add_string("reference_path", json_string(reference_manifest, "path"))
add_number("reference_position", number_value(reference_manifest, "position"))
add_number("reference_length", number_value(reference_manifest, "length"))
local selected_count = #fields
if selected_count == 0 then log("Select at least one YuE2 source first."); return end
local default_text = lyrics_text or chords_text or arrangement_text
if default_text then fields[#fields + 1] = string.format('"text":"%s"', json_escape(default_text)) end
local job_id = tostring(os.time()) .. "_yue2_" .. tostring(math.floor(os.clock() * 1000) % 1000)
os.remove(cache .. "/comfy_to_reaper.json")
local file = io.open(manifest_path, "w")
if not file then log("Cannot write YuE2 source manifest: " .. cache); return end
file:write('{"source":"yue2_sources","job_id":"' .. job_id .. '",' .. table.concat(fields, ",") .. '}')
file:close()
local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_root then
  local fallback = user_root .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(fallback, 0)
  local pointer = io.open(fallback .. "/current_project.txt", "w")
  if pointer and project_dir ~= "" then pointer:write(cache); pointer:close() end
end
log("YuE2 source manifest is ready: " .. manifest_path)
