-- @description REAPER AI - Process selected item(s) with ComfyUI
-- @version 1.0.0
-- @noindex
-- @about Main public action for the REAPER AI bridge. Legacy implementation is kept for compatibility.

local script_path = ({reaper.get_action_context()})[2]
local root = script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
dofile(root .. "/reaper/ReaComfy Core.lua")
