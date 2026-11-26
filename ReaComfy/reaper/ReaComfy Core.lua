-- @description REAPER AI - Process selected item(s) with ComfyUI (legacy implementation)
-- @version 0.1.0
-- @noindex
-- @about Uploads the selected audio source to local ComfyUI and imports the result as a new take.

local script_path = ({reaper.get_action_context()})[2]
if script_path then script_path = script_path:gsub("^@", "") end
local source_path = debug.getinfo(1, "S").source:sub(2):gsub("^@", "")
local root = (script_path and script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$"))
  or source_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
if not root and reaper.GetResourcePath then
  local scripts_root = reaper.GetResourcePath() .. "/Scripts/ReaComfy"
  if reaper.file_exists(scripts_root .. "/reaper/AI Workflow Config.lua") then root = scripts_root end
end
if not root then reaper.ShowConsoleMsg("REAPER AI: Could not locate the ReaComfy folder.\n"); return end
local config = dofile(root .. "/reaper/AI Workflow Config.lua")
local bridge = root .. "/bridge/reaper_comfy_bridge.py"
local status_file = root .. "/runtime/latest_result.json"
local workflows_dir = root .. "/workflows"
local python = config.bridge_python
if not python or python == "" then
  python = os.getenv("REACOMFY_PYTHON") or (package.config:sub(1, 1) == "\\" and "python" or "python3")
end

local function log(message)
  reaper.ShowConsoleMsg("REAPER AI: " .. message .. "\n")
end

local reaper_os = reaper.GetOS and reaper.GetOS() or ""
local is_windows = reaper_os:match("^Win") ~= nil or package.config:sub(1, 1) == "\\"
local function shell_quote(value)
  value = tostring(value)
  if is_windows then return '"' .. value:gsub('"', '\\"') .. '"' end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function launch_background(arguments, title)
  if is_windows then
    -- Run a short batch launcher so cmd.exe parses paths and macro arguments
    -- exactly once. Directly nesting the whole quoted command after `start`
    -- is unreliable when the project path contains spaces or Unicode.
    reaper.RecursiveCreateDirectory(root .. "/runtime", 0)
    local launcher_path = root .. "/runtime/reacomfy_bridge_launch.cmd"
    local launcher = io.open(launcher_path, "w")
    if not launcher then return nil, "launcher", 1 end
    launcher:write("@echo off\r\n")
    launcher:write(table.concat(arguments, " "), "\r\n")
    launcher:write("del \"%~f0\" >nul 2>&1\r\n")
    launcher:close()
    return os.execute('cmd /c start "" /b "' .. launcher_path:gsub("/", "\\") .. '"')
  end
  return os.execute(table.concat(arguments, " ") .. " >/dev/null 2>&1 &")
end

local selected_filename = reaper.GetExtState("REAPER_AI", "selected_workflow")
local node_send_mode = reaper.GetExtState("REAPER_AI", "node_send") == "1"
local launcher_manages_job = reaper.GetExtState("REAPER_AI", "launcher_manages_job") == "1"
reaper.DeleteExtState("REAPER_AI", "launcher_manages_job", false)
reaper.DeleteExtState("REAPER_AI", "node_send", false)
if selected_filename == "" and not node_send_mode then
  dofile(root .. "/reaper/AI Workflow Launcher.lua")
  return
end
reaper.DeleteExtState("REAPER_AI", "selected_workflow", false)
if node_send_mode then selected_filename = "__NODE_SEND__" end
local workflow_overrides = reaper.GetExtState("REAPER_AI", "workflow_overrides")
reaper.DeleteExtState("REAPER_AI", "workflow_overrides", false)
local output_format = reaper.GetExtState("REAPER_AI", "output_format")
reaper.DeleteExtState("REAPER_AI", "output_format", false)
if output_format ~= "wav" then output_format = "flac" end
local input_mode = reaper.GetExtState("REAPER_AI", "input_mode")
reaper.DeleteExtState("REAPER_AI", "input_mode", false)
if input_mode ~= "glue" then input_mode = "source" end
local destination_mode = reaper.GetExtState("REAPER_AI", "destination_mode")
reaper.DeleteExtState("REAPER_AI", "destination_mode", false)
if destination_mode ~= "track" and destination_mode ~= "selected" then destination_mode = "lane" end
local destination_track_name = reaper.GetExtState("REAPER_AI", "destination_track_name")
reaper.DeleteExtState("REAPER_AI", "destination_track_name", false)
if destination_track_name == "" then destination_track_name = "AI Result" end
local return_position_mode = reaper.GetExtState("REAPER_AI", "return_position_pref")
if return_position_mode ~= "source" then return_position_mode = "cursor" end
local track_output_mode = reaper.GetExtState("REAPER_AI", "track_output_mode")
reaper.DeleteExtState("REAPER_AI", "track_output_mode", false)
if track_output_mode ~= "lanes" then track_output_mode = "separate" end
local selected_workflow = {
  filename = selected_filename,
  label = selected_filename:gsub("_api%.json$", ""):gsub("_", " ")
}
local workflow_path = workflows_dir .. "/" .. selected_workflow.filename
if not reaper.file_exists(workflow_path) and config.private_workflows_dir then
  local private_path = config.private_workflows_dir .. "/" .. selected_workflow.filename
  if reaper.file_exists(private_path) then workflow_path = private_path end
end
log("Selected workflow: " .. selected_workflow.label .. " (input: " .. input_mode .. ")")

local item = reaper.GetSelectedMediaItem(0, 0)
local selected_count = reaper.CountSelectedMediaItems(0)
if not item or selected_count < 1 then
  log("Select at least one audio item.")
  return
end
if input_mode ~= "glue" and selected_count ~= 1 then
  log("Original source mode accepts exactly one audio item. Use Glue visible item to combine multiple items.")
  return
end

local take = reaper.GetActiveTake(item)
if not take or reaper.TakeIsMIDI(take) then
  log("The selected item must contain audio, not MIDI.")
  return
end

local selected_items = {}
for i = 0, selected_count - 1 do
  local selected_item = reaper.GetSelectedMediaItem(0, i)
  local selected_take = selected_item and reaper.GetActiveTake(selected_item)
  if not selected_take or reaper.TakeIsMIDI(selected_take) then
    log("All selected items must contain audio, not MIDI.")
    return
  end
  selected_items[#selected_items + 1] = selected_item
end

-- Capture the exact visible slice before starting the asynchronous AI job.
local original_track = reaper.GetMediaItemTrack(item)
local original_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local original_end = original_position + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
for _, selected_item in ipairs(selected_items) do
  local selected_position = reaper.GetMediaItemInfo_Value(selected_item, "D_POSITION")
  local selected_end = selected_position + reaper.GetMediaItemInfo_Value(selected_item, "D_LENGTH")
  if selected_position < original_position then original_position = selected_position end
  if selected_end > original_end then original_end = selected_end end
end
local original_length = original_end - original_position
local original_snap_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
local original_source_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
local original_playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
local original_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
local original_preserve_pitch = reaper.GetMediaItemTakeInfo_Value(take, "B_PPITCH")
local original_lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")

-- Keep job status and outputs together with the current project.
local project_dir = reaper.GetProjectPathEx(0, "")
if project_dir and project_dir ~= "" then
  local project_cache = project_dir .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(project_cache, 0)
  status_file = project_cache .. "/latest_result.json"
end
if node_send_mode then log("Node exchange cache: " .. status_file:gsub("latest_result%.json$", "")) end

local function find_source_file(media_source)
  if not media_source then return nil end
  local _, path = reaper.GetMediaSourceFileName(media_source, "")
  -- Let the Python bridge perform the final filesystem check. REAPER's
  -- file_exists() can reject an otherwise valid path from some media sources.
  if path and path ~= "" and (path:match("^%a:[\\/]") or path:match("^\\\\") or path:match("^/")) then return path end
  -- Glue may return a filename relative to the saved project directory.
  if path and path ~= "" and not path:match("^%a:[\\/]") and not path:match("^\\\\") and not path:match("^/") then
    local project_path = reaper.GetProjectPathEx(0, "")
    if project_path and project_path ~= "" then
      local absolute_path = project_path .. "/" .. path
      return absolute_path
    end
  end
  -- Section, reverse and similar sources wrap the actual file source.
  local parent = reaper.GetMediaSourceParent(media_source)
  if parent and parent ~= media_source then return find_source_file(parent) end
  return nil
end

local function find_source_from_item_chunk(media_item)
  -- Some item types do not expose a filename through the media-source API,
  -- but REAPER still stores it in the item's native project chunk.
  local ok, chunk = reaper.GetItemStateChunk(media_item, "", false)
  if not ok or not chunk then return nil end
  local path = chunk:match('[\r\n]FILE%s+"([^"]+)"')
  if not path or path == "" then return nil end
  path = path:gsub('\\"', '"')
  if path:match("^%a:[\\/]") or path:match("^\\\\") or path:match("^/") then return path end
  local project_path = reaper.GetProjectPathEx(0, "")
  if project_path and project_path ~= "" then return project_path .. "/" .. path end
  return nil
end

-- Create a temporary glued file that represents exactly the visible item slice.
-- This is important when the item is only a trimmed section of a larger file:
-- AI receives the section, not the whole source. The original item is never
-- modified; the temporary track is removed immediately after Glue completes.
local function make_temporary_glued_source()
  local temp_track_index = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(temp_track_index, false)
  local temp_track = reaper.GetTrack(0, temp_track_index)
  if not temp_track then return nil end
  reaper.GetSetMediaTrackInfo_String(temp_track, "P_NAME", "[REAPER AI temporary Glue]", true)

  for _, source_item in ipairs(selected_items) do
    local source_take = reaper.GetActiveTake(source_item)
    local temp_item = reaper.AddMediaItemToTrack(temp_track)
    local source_position = reaper.GetMediaItemInfo_Value(source_item, "D_POSITION")
    reaper.SetMediaItemInfo_Value(temp_item, "D_POSITION", source_position - original_position)
    reaper.SetMediaItemInfo_Value(temp_item, "D_LENGTH", reaper.GetMediaItemInfo_Value(source_item, "D_LENGTH"))
    reaper.SetMediaItemInfo_Value(temp_item, "D_FADEINLEN", reaper.GetMediaItemInfo_Value(source_item, "D_FADEINLEN"))
    reaper.SetMediaItemInfo_Value(temp_item, "D_FADEOUTLEN", reaper.GetMediaItemInfo_Value(source_item, "D_FADEOUTLEN"))
    reaper.SetMediaItemInfo_Value(temp_item, "D_VOL", reaper.GetMediaItemInfo_Value(source_item, "D_VOL"))
    reaper.SetMediaItemInfo_Value(temp_item, "D_PAN", reaper.GetMediaItemInfo_Value(source_item, "D_PAN"))
    reaper.SetMediaItemInfo_Value(temp_item, "B_MUTE", reaper.GetMediaItemInfo_Value(source_item, "B_MUTE"))

    local temp_take = reaper.AddTakeToMediaItem(temp_item)
    local source = reaper.GetMediaItemTake_Source(source_take)
    if not temp_take or not source then
      reaper.DeleteTrack(temp_track)
      return nil
    end
    reaper.SetMediaItemTake_Source(temp_take, source)
    reaper.SetMediaItemTakeInfo_Value(temp_take, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(source_take, "D_STARTOFFS"))
    reaper.SetMediaItemTakeInfo_Value(temp_take, "D_PLAYRATE", reaper.GetMediaItemTakeInfo_Value(source_take, "D_PLAYRATE"))
    reaper.SetMediaItemTakeInfo_Value(temp_take, "D_PITCH", reaper.GetMediaItemTakeInfo_Value(source_take, "D_PITCH"))
    reaper.SetMediaItemTakeInfo_Value(temp_take, "B_PPITCH", reaper.GetMediaItemTakeInfo_Value(source_take, "B_PPITCH"))
    reaper.SetMediaItemTakeInfo_Value(temp_take, "D_VOL", reaper.GetMediaItemTakeInfo_Value(source_take, "D_VOL"))
    reaper.SetMediaItemTakeInfo_Value(temp_take, "D_PAN", reaper.GetMediaItemTakeInfo_Value(source_take, "D_PAN"))
    reaper.UpdateItemInProject(temp_item)
  end

  reaper.SelectAllMediaItems(0, false)
  for i = 0, reaper.CountTrackMediaItems(temp_track) - 1 do
    reaper.SetMediaItemSelected(reaper.GetTrackMediaItem(temp_track, i), true)
  end
  reaper.SetOnlyTrackSelected(temp_track)
  reaper.UpdateArrange()
  -- Native Glue runs without opening the Render dialog.
  -- 40362 is REAPER's standard "Glue items" action. 41588 is a context-
  -- dependent Glue variant (including time-selection behavior) and can leave
  -- the temporary item unrendered when no time selection is active.
  reaper.Main_OnCommand(40362, 0)
  reaper.UpdateArrange()

  -- Prefer the item on the temporary track; selection can be changed by
  -- extensions or by a Glue command variant.
  local glued_item = reaper.GetTrackMediaItem(temp_track, 0) or reaper.GetSelectedMediaItem(0, 0)
  local glued_take = glued_item and reaper.GetActiveTake(glued_item)
  local glued_path = glued_take and find_source_file(reaper.GetMediaItemTake_Source(glued_take))
  if not glued_path and glued_item then glued_path = find_source_from_item_chunk(glued_item) end
  if not glued_path then
    log("Glue command completed, but no media filename was exposed by the glued item. Temporary track was left for inspection.")
    reaper.UpdateArrange()
    return nil
  end
  reaper.DeleteTrack(temp_track)
  reaper.UpdateArrange()
  return glued_path
end

local temporary_source_path = nil
local source_path
if input_mode == "glue" then
  temporary_source_path = make_temporary_glued_source()
  source_path = temporary_source_path
end
if not source_path then
  if input_mode == "glue" then
    log("Glue mode was selected, but REAPER did not create a readable glued file. Original source was not used.")
    return
  end
  source_path = find_source_file(reaper.GetMediaItemTake_Source(take))
  if not source_path then source_path = find_source_from_item_chunk(item) end
end
if not source_path then
  log("Source path was not found in the REAPER API or item state chunk.")
  return
end

if node_send_mode then
  local manifest = status_file:gsub("latest_result%.json$", "reaper_to_comfy.json")
  os.remove(manifest:gsub("reaper_to_comfy%.json$", "comfy_to_reaper.json"))
  local function json_escape(value)
    return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
  end
  local file = io.open(manifest, "w")
  if not file then
    log("Could not create REAPER Input manifest: " .. manifest)
    return
  end
  local job_id = tostring(os.time()) .. "_" .. tostring(math.floor((reaper.time_precise and reaper.time_precise() or os.clock()) * 1000) % 1000000)
  file:write(string.format('{"job_id":"%s","path":"%s","position":%.12f,"length":%.12f,"item_count":%d}', job_id, json_escape(source_path), original_position, original_length, selected_count))
  file:close()
  local pointer_dir = os.getenv("USERPROFILE") or os.getenv("HOME")
  if pointer_dir then
    local pointer_folder = pointer_dir .. "/REAPER_AI_CACHE"
    reaper.RecursiveCreateDirectory(pointer_folder, 0)
    local pointer = io.open(pointer_folder .. "/current_project.txt", "w")
    local pointer_path = manifest:gsub("[\\/]reaper_to_comfy%.json$", "")
    if pointer then pointer:write(pointer_path); pointer:close() end
  end
  log("REAPER Input is ready for ComfyUI: " .. source_path)
  return
end

local python_is_path = python:match("^[A-Za-z]:[\\/]") or python:match("^[/\\\\]")
if python_is_path and not reaper.file_exists(python) then
  if temporary_source_path then os.remove(temporary_source_path) end
  log("Configured Python executable was not found: " .. python)
  return
end

os.remove(status_file)
local macro_arguments = ""
for node, input, value in (workflow_overrides or ""):gmatch("([^|;]+)|([^|;]+)|([^;]+)") do
  macro_arguments = macro_arguments .. string.format(' --set "%s:%s:%s"', node, input, value)
end
local arguments = {shell_quote(python), shell_quote(bridge), "--base-url", shell_quote(config.comfy_url), "clean-vocal", "--input", shell_quote(source_path), "--workflow", shell_quote(workflow_path), "--status", shell_quote(status_file), "--output-format", output_format}
for node, input, value in (workflow_overrides or ""):gmatch("([^|;]+)|([^|;]+)|([^;]+)") do
  arguments[#arguments + 1] = "--set"; arguments[#arguments + 1] = shell_quote(node .. ":" .. input .. ":" .. value)
end
local launch_ok, launch_kind, launch_code = launch_background(arguments, "ReaComfy ComfyUI")
log("Bridge launch result: " .. tostring(launch_ok) .. " (" .. tostring(launch_kind) .. ", " .. tostring(launch_code) .. ")")
if not launch_ok then
  log("Could not start the ComfyUI bridge process.")
  return
end

log("AI audio job submitted to ComfyUI.")
log("Bridge launched (" .. (is_windows and "Windows" or "POSIX") .. "); status file: " .. status_file)

-- The launcher owns the defer cycle when it stays open. It will watch the
-- project cache and invoke the importer after the bridge writes the manifest.
if launcher_manages_job then return end

local function import_when_ready()
  local file = io.open(status_file, "r")
  if not file then
    reaper.defer(import_when_ready)
    return
  end
  local content = file:read("*a")
  file:close()
  if content:find('"status": "failed"') then
    local error = content:match('"error":%s*"(.-)"') or "See the REAPER Console for details."
    if temporary_source_path then os.remove(temporary_source_path) end
    log("ComfyUI job failed: " .. error)
    return
  end
  local outputs = {}
  local outputs_json = content:match('"outputs":%s*(%b{})')
  if outputs_json then
    for label, path in outputs_json:gmatch('"(.-)"%s*:%s*"(.-)"') do
      table.insert(outputs, { label = label, path = path:gsub("\\\\", "\\") })
    end
  end
  if #outputs == 0 then
    local output = content:match('"output":%s*"(.-)"')
    if output then table.insert(outputs, { label = "AI result", path = output:gsub("\\\\", "\\") }) end
  end
  if #outputs == 0 then
    reaper.defer(import_when_ready)
    return
  end
  for _, result in ipairs(outputs) do
    if not reaper.file_exists(result.path) then
      if temporary_source_path then os.remove(temporary_source_path) end
      log("ComfyUI reported an output file, but it was not found: " .. result.path)
      return
    end
  end
  if temporary_source_path then os.remove(temporary_source_path) end
  reaper.Undo_BeginBlock()
  local placement_position = return_position_mode == "source" and original_position or reaper.GetCursorPosition()
  local target_track = original_track
  local target_lane = nil
  if destination_mode == "track" then
    local new_track_index = reaper.CountTracks(0)
    if track_output_mode == "lanes" then
      reaper.InsertTrackAtIndex(new_track_index, false)
      target_track = reaper.GetTrack(0, new_track_index)
      reaper.GetSetMediaTrackInfo_String(target_track, "P_NAME", destination_track_name, true)
      reaper.SetMediaTrackInfo_Value(target_track, "I_FREEMODE", 2)
      reaper.SetMediaTrackInfo_Value(target_track, "I_NUMFIXEDLANES", #outputs)
      target_lane = 0
    end
  else
    -- Put the AI result in a new fixed lane, never in REAPER's legacy take stack.
    if reaper.GetMediaTrackInfo_Value(original_track, "I_FREEMODE") ~= 2 then
      reaper.SetMediaTrackInfo_Value(original_track, "I_FREEMODE", 2)
      reaper.UpdateTimeline()
    end
    local lane_count = reaper.GetMediaTrackInfo_Value(original_track, "I_NUMFIXEDLANES")
    target_lane = math.max(math.floor(original_lane) + 1, math.floor(lane_count))
    reaper.SetMediaTrackInfo_Value(original_track, "I_NUMFIXEDLANES", target_lane + #outputs)
  end
  for index, result in ipairs(outputs) do
    if destination_mode == "track" and track_output_mode == "separate" then
      local new_track_index = reaper.CountTracks(0)
      reaper.InsertTrackAtIndex(new_track_index, false)
      target_track = reaper.GetTrack(0, new_track_index)
      reaper.GetSetMediaTrackInfo_String(target_track, "P_NAME", destination_track_name, true)
    end
    local processed_item = reaper.AddMediaItemToTrack(target_track)
    reaper.SetMediaItemInfo_Value(processed_item, "D_POSITION", placement_position)
    reaper.SetMediaItemInfo_Value(processed_item, "D_LENGTH", original_length)
    reaper.SetMediaItemInfo_Value(processed_item, "D_SNAPOFFSET", original_snap_offset)
    if target_lane then reaper.SetMediaItemInfo_Value(processed_item, "I_FIXEDLANE", target_lane + index - 1) end
    reaper.SetMediaItemInfo_Value(processed_item, "B_MUTE", 0)
    local processed_take = reaper.AddTakeToMediaItem(processed_item)
    local processed_source = reaper.PCM_Source_CreateFromFile(result.path)
    reaper.SetMediaItemTake_Source(processed_take, processed_source)
    if temporary_source_path then
      -- The hidden Glue already rendered the original source offset, rate and
      -- pitch into the AI input. Do not apply them a second time on import.
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_STARTOFFS", 0)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_PLAYRATE", 1)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_PITCH", 0)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "B_PPITCH", 0)
    else
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_STARTOFFS", original_source_offset)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_PLAYRATE", original_playrate)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "D_PITCH", original_pitch)
      reaper.SetMediaItemTakeInfo_Value(processed_take, "B_PPITCH", original_preserve_pitch)
    end
    reaper.GetSetMediaItemTakeInfo_String(processed_take, "P_NAME", result.label, true)
    reaper.UpdateItemInProject(processed_item)
  end
  reaper.Undo_EndBlock("AI audio result", -1)
  local destination_log = "new fixed lane(s)"
  if destination_mode == "track" then
    destination_log = track_output_mode == "lanes" and ("fixed lanes on new track '" .. destination_track_name .. "'") or "separate new tracks"
  end
  log("Completed: " .. #outputs .. " AI result(s) were added to " .. destination_log .. ". Original item was left unchanged.")
end

reaper.defer(import_when_ready)
