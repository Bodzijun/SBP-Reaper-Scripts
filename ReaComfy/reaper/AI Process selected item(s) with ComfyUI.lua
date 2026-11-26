-- @description REAPER AI - Process selected item(s) with ComfyUI
-- @version 1.0.0
-- @noindex
-- @about Main public action for the REAPER AI bridge. Legacy implementation is kept for compatibility.

local script_path = ({reaper.get_action_context()})[2]
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/]reaper[\\/][^\\/]+$")
dofile(root .. "/reaper/ReaComfy Core.lua")
