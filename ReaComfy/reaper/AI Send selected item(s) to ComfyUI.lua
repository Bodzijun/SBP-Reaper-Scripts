-- @description REAPER AI - Send selected item(s) to ComfyUI Input node
-- @version 0.1.0
-- @noindex

local script_path = ({reaper.get_action_context()})[2]
if script_path then script_path = script_path:gsub("^@", "") end
local source_path = debug.getinfo(1, "S").source:sub(2):gsub("^@", "")
local root = (script_path and script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$"))
  or source_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
if not root and reaper.GetResourcePath then
  local scripts_root = reaper.GetResourcePath() .. "/Scripts/ReaComfy"
  if reaper.file_exists(scripts_root .. "/reaper/ReaComfy Core.lua") then root = scripts_root end
end
reaper.ShowConsoleMsg("REAPER AI: Send-to-Comfy button started.\n")
if not root then
  reaper.ShowConsoleMsg("REAPER AI: Could not resolve reaper-comfy-ai root from script path.\n")
  return
end
local input_mode = reaper.GetExtState("REAPER_AI", "input_mode_pref")
if input_mode ~= "glue" then input_mode = "source" end
reaper.SetExtState("REAPER_AI", "input_mode", input_mode, false)
reaper.SetExtState("REAPER_AI", "node_send", "1", false)
dofile(root .. "/reaper/ReaComfy Core.lua")
