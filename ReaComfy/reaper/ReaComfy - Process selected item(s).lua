-- @description ReaComfy - Process selected item(s)
-- @version 1.0.0
-- @noindex
-- @about Public entry point for the ReaComfy REAPER ↔ ComfyUI bridge.

local script_path = ({reaper.get_action_context()})[2]
local root = script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
dofile(root .. "/reaper/ReaComfy Core.lua")
