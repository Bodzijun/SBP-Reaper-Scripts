-- @noindex
-- Shared configuration for the REAPER AI bridge.
-- Keep paths and UI defaults here; workflow-specific controls stay in
-- AI Workflow Macros.lua and workflow files remain in ../workflows.

local script_file = debug.getinfo(1, "S").source:sub(2)
local root = script_file:match("^(.*)[\\/]reaper[\\/][^\\/]+$")

local config = {
  root = root,
  workflows_dir = root .. "/workflows",
  private_workflows_dir = root .. "/workflows_private",
  -- Optional extra preset folders. Use a semicolon-separated list (all platforms).
  additional_workflows_dir = "",
  main_action = root .. "/reaper/ReaComfy - Process selected item(s).lua",
  macros_file = root .. "/reaper/AI Workflow Macros.lua",
  send_action = root .. "/reaper/AI Send selected item(s) to ComfyUI.lua",
  import_action = root .. "/reaper/AI Import ComfyUI result.lua",
  bridge_python = "",
  comfy_url = "http://127.0.0.1:8188",
  defaults = {
    output_format = "flac",
    input_mode = "source",
    destination_mode = "lane",
    track_output_mode = "separate",
    return_position_mode = "cursor",
    destination_track_name = "AI Result",
    yue2_lyrics_track = "Lyrics",
    yue2_chords_track = "Chords",
    yue2_reference_track = "",
    arrangement_folder_name = "Arrangement",
    yue2_midi_scope = "selected",
    video_track_name = "",
    cutscene_track_name = "",
    keep_open = false,
  },
}

-- Optional machine-local overrides. This file is intentionally not shipped
-- with personal paths; users can copy the .example file and edit it.
local user_file = root .. "/reaper/ReaComfy User Config.lua"
if reaper and reaper.file_exists and reaper.file_exists(user_file) then
  local ok, overrides = pcall(dofile, user_file)
  if ok and type(overrides) == "table" then
    for key, value in pairs(overrides) do
      if value ~= nil and value ~= "" then config[key] = value end
    end
  end
end
return config
