-- @description REAPER AI - Import ComfyUI Output node result(s)
-- @version 0.5.0
-- @noindex

local script_path = ({reaper.get_action_context()})[2]
if not script_path or script_path == "" then
  script_path = debug.getinfo(1, "S").source:sub(2)
end
local root = script_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
if not root then
  local source_path = debug.getinfo(1, "S").source:sub(2)
  root = source_path:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
end
local function log(message) reaper.ShowConsoleMsg("REAPER AI: " .. message .. "\n") end
if not root then log("Could not locate the ReaComfy installation folder."); return end

local function basename(path)
  return (path:gsub("^.*[\\/]", ""))
end

local function collect_cached_audio(caches)
  local found, seen = {}, {}
  local extensions = {wav = true, flac = true, mp3 = true, ogg = true, m4a = true}
  for _, cache in ipairs(caches) do
    local index = 0
    while true do
      local filename = reaper.EnumerateFiles(cache, index)
      if not filename then break end
      local lower = filename:lower()
      local ext = lower:match("%.([%w]+)$")
      if ext and extensions[ext] and lower:match("comfy_to_reaper[_%-]") then
        local path = cache .. "/" .. filename
        if not seen[path:lower()] and reaper.file_exists(path) then
          seen[path:lower()] = true
          found[#found + 1] = {path = path, label = filename}
        end
      end
      index = index + 1
    end
  end
  table.sort(found, function(a, b) return a.label:lower() > b.label:lower() end)
  return found
end

local function choose_cached_outputs(caches)
  local files = collect_cached_audio(caches)
  if #files == 0 then
    log("No cached ComfyUI audio files were found for manual selection.")
    return nil
  end
  local lines = {"Choose cached ComfyUI result file(s):", ""}
  local limit = math.min(#files, 30)
  for i = 1, limit do
    lines[#lines + 1] = string.format("%2d  %s", i, files[i].label)
  end
  if #files > limit then
    lines[#lines + 1] = string.format("... and %d older file(s)", #files - limit)
  end
  reaper.ShowMessageBox(table.concat(lines, "\n"), "ReaComfy — Cached results", 0)
  local ok, value = reaper.GetUserInputs("ReaComfy — Import cached result", 1,
    "Result number(s), comma-separated:", "1")
  if not ok then return {} end
  local outputs, used = {}, {}
  for token in tostring(value):gmatch("[^,]+") do
    local index = tonumber(token:match("^%s*(%d+)%s*$"))
    if index and index >= 1 and index <= limit and not used[index] then
      used[index] = true
      outputs[#outputs + 1] = files[index]
    end
  end
  return outputs
end

local project_dir = reaper.GetProjectPathEx(0, "")
local candidates = {}
if project_dir and project_dir ~= "" then candidates[#candidates + 1] = project_dir .. "/REAPER_AI_CACHE" end
candidates[#candidates + 1] = root .. "/runtime"
local user_profile = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_profile then candidates[#candidates + 1] = user_profile .. "/REAPER_AI_CACHE" end

local content
local content_kind
local bridge_cache = candidates[1]
if bridge_cache then
  local file = io.open(bridge_cache .. "/latest_result.json", "r")
  if file then
    local candidate = file:read("*a"); file:close()
    if candidate and candidate:find('"status"%s*:%s*"complete"') and candidate:find('"outputs"%s*:') then
      content = candidate
      content_kind = "bridge"
    end
  end
end
if not content then
  for _, cache in ipairs(candidates) do
    local file = io.open(cache .. "/comfy_to_reaper.json", "r")
    if file then content = file:read("*a"); file:close(); break end
  end
  content_kind = "node"
end
local manual_selection = reaper.GetExtState("REAPER_AI", "select_result_pref") == "1"

if not content and not manual_selection then
  log("ComfyUI result manifest was not found. Checked project cache, bridge runtime and user cache."); return
end

local function normalized_path(path)
  return tostring(path or ""):gsub("\\\\", "/"):lower()
end

local function manifest_label_for_path(path)
  if not content then return nil end
  local wanted = normalized_path(path)
  for object in content:gmatch("%b{}") do
    local candidate = object:match('"path"%s*:%s*"(.-)"')
    local label = object:match('"label"%s*:%s*"(.-)"')
    if candidate and label and normalized_path(candidate) == wanted then return label end
  end
  local outputs_object = content:match('"outputs"%s*:%s*(%b{})')
  if outputs_object then
    for label, candidate in outputs_object:gmatch('"(.-)"%s*:%s*"(.-)"') do
      if normalized_path(candidate) == wanted then return label end
    end
  end
  return nil
end

local outputs = {}
local launcher_selection = reaper.GetExtState("REAPER_AI", "import_selection")
if launcher_selection ~= "" then
  for path in launcher_selection:gmatch("[^\r\n]+") do
    if reaper.file_exists(path) then
      outputs[#outputs + 1] = {path = path, label = path:gsub("^.*[\\/]", "")}
    end
  end
  reaper.SetExtState("REAPER_AI", "import_selection", "", false)
  if #outputs > 0 then log("Using ReaImGui cached-result selection: " .. tostring(#outputs) .. " file(s).") end
end
if #outputs == 0 and manual_selection then
  local selected_outputs = choose_cached_outputs(candidates)
  if selected_outputs and #selected_outputs == 0 then
    log("Cached result import cancelled or no valid result number was selected.")
    return
  end
  if selected_outputs and #selected_outputs > 0 then
    outputs = selected_outputs
    log("Manual cached-result selection: " .. tostring(#outputs) .. " file(s).")
  end
end
if not content and #outputs == 0 then
  log("ComfyUI result manifest was not found and no cached result was selected.")
  return
end
if #outputs == 0 and content_kind == "bridge" then
  local outputs_json = content:match('"outputs"%s*:%s*(%b{})')
  if outputs_json then
    for label, path in outputs_json:gmatch('"(.-)"%s*:%s*"(.-)"') do
      outputs[#outputs + 1] = {path = path:gsub("\\\\", "\\"), label = label}
    end
  end
elseif #outputs == 0 then
  local outputs_json = content:match('"outputs"%s*:%s*(%b[])')
  if outputs_json then
    for object in outputs_json:gmatch("%b{}") do
      local path = object:match('"path"%s*:%s*"(.-)"')
      local label = object:match('"label"%s*:%s*"(.-)"') or "ComfyUI result"
      if path then outputs[#outputs + 1] = {path = path:gsub("\\\\", "\\"), label = label} end
    end
  end
  if #outputs == 0 then
    local path = content:match('"path"%s*:%s*"(.-)"')
    if path then outputs[1] = {path = path:gsub("\\\\", "\\"), label = content:match('"label"%s*:%s*"(.-)"') or "ComfyUI result"} end
  end
end
if #outputs == 0 then log("ComfyUI result manifest has no output paths."); return end
for _, output in ipairs(outputs) do
  local filename = basename(output.path)
  local manifest_label = manifest_label_for_path(output.path)
  if not output.label or output.label == "" or output.label == filename then
    output.label = manifest_label or "ComfyUI result"
  end
  if output.label == filename then output.label = "ComfyUI result" end
end
if #outputs > 1 then
  log("Multiple outputs found; importing all " .. tostring(#outputs) .. " results.")
end
for _, output in ipairs(outputs) do
  if not reaper.file_exists(output.path) then log("ComfyUI result file was not found: " .. output.path); return end
end

local destination_mode = reaper.GetExtState("REAPER_AI", "destination_mode_pref")
if destination_mode ~= "track" and destination_mode ~= "selected" then destination_mode = "lane" end
local track_output_mode = reaper.GetExtState("REAPER_AI", "track_output_mode_pref")
if track_output_mode ~= "lanes" then track_output_mode = "separate" end
local destination_track_name = reaper.GetExtState("REAPER_AI", "destination_track_name_pref")
if destination_track_name == "" then destination_track_name = "ComfyUI Result" end
local return_position_mode = reaper.GetExtState("REAPER_AI", "return_position_pref")
if return_position_mode ~= "source" then return_position_mode = "cursor" end
local source_position = content and tonumber(content:match('"position"%s*:%s*([%+%-]?[%d%.]+)')) or nil
if return_position_mode == "source" and not source_position then
  for _, cache in ipairs(candidates) do
    local file = io.open(cache .. "/comfy_to_reaper.json", "r")
    if file then
      local candidate = file:read("*a")
      file:close()
      local candidate_position = tonumber(candidate:match('"position"%s*:%s*([%+%-]?[%d%.]+)'))
      if candidate_position then
        source_position = candidate_position
        log("Using source position from the node-exchange manifest.")
        break
      end
    end
  end
end
if return_position_mode == "source" and not source_position then
  log("Source position was not present in the result manifest; using edit cursor.")
end

local function find_track_by_name(name)
  for index = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, index)
    local _, candidate_name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
    if candidate_name == name then return candidate end
  end
  return nil
end

local function find_tracks_by_name(name)
  local tracks = {}
  for index = 0, reaper.CountTracks(0) - 1 do
    local candidate = reaper.GetTrack(0, index)
    local _, candidate_name = reaper.GetSetMediaTrackInfo_String(candidate, "P_NAME", "", false)
    if candidate_name == name then tracks[#tracks + 1] = candidate end
  end
  return tracks
end

local function track_has_item_at_position(candidate, position)
  if not candidate then return false end
  for index = 0, reaper.CountTrackMediaItems(candidate) - 1 do
    local item = reaper.GetTrackMediaItem(candidate, index)
    local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if position >= item_position and position < item_position + item_length then return true end
  end
  return false
end

local track = destination_mode == "track" and find_track_by_name(destination_track_name) or reaper.GetSelectedTrack(0, 0)
if not track then
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", destination_track_name, true)
end
local named_tracks = destination_mode == "track" and find_tracks_by_name(destination_track_name) or {}
local used_tracks = {}
local position = (return_position_mode == "source" and source_position) or reaper.GetCursorPosition()
local target_track = track
local lane_start
if destination_mode == "lane" then
  if reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE") ~= 2 then reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2) end
  lane_start = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES"))
  reaper.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", lane_start + #outputs)
elseif destination_mode == "track" and track_output_mode == "lanes" then
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
  target_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(target_track, "P_NAME", destination_track_name, true)
  reaper.SetMediaTrackInfo_Value(target_track, "I_FREEMODE", 2)
  reaper.SetMediaTrackInfo_Value(target_track, "I_NUMFIXEDLANES", #outputs)
  lane_start = 0
elseif destination_mode == "selected" and track_output_mode == "lanes" then
  target_track = track
  if reaper.GetMediaTrackInfo_Value(target_track, "I_FREEMODE") ~= 2 then reaper.SetMediaTrackInfo_Value(target_track, "I_FREEMODE", 2) end
  lane_start = math.floor(reaper.GetMediaTrackInfo_Value(target_track, "I_NUMFIXEDLANES"))
  reaper.SetMediaTrackInfo_Value(target_track, "I_NUMFIXEDLANES", lane_start + #outputs)
end

reaper.Undo_BeginBlock()
for index, output in ipairs(outputs) do
  if destination_mode == "track" and track_output_mode == "separate" then
    local reusable_track
    for _, candidate in ipairs(named_tracks) do
      if not used_tracks[candidate] and not track_has_item_at_position(candidate, position) then
        reusable_track = candidate
        break
      end
    end
    if not reusable_track then
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
      reusable_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      reaper.GetSetMediaTrackInfo_String(reusable_track, "P_NAME", destination_track_name, true)
      named_tracks[#named_tracks + 1] = reusable_track
    end
    target_track = reusable_track
    used_tracks[target_track] = true
  end
  reaper.SelectAllMediaItems(0, false)
  reaper.SetOnlyTrackSelected(target_track)
  reaper.SetEditCurPos(position, true, false)
  reaper.InsertMedia(output.path, 0)
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    if lane_start then reaper.SetMediaItemInfo_Value(item, "I_FIXEDLANE", lane_start + index - 1) end
    local take = reaper.GetActiveTake(item)
    if take then
      -- Keep the track name stable, but prefix each imported item with the
      -- originating ComfyUI output channel so stems/IRs are easy to find.
      local channel = tostring(output.label or "ComfyUI result")
      local filename = basename(output.path)
      local take_name = channel
      if channel == "" or channel == filename then take_name = "ComfyUI result" end
      if take_name ~= filename then take_name = take_name .. " | " .. filename end
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
    end
    reaper.SetMediaItemSelected(item, true)
  end
end
reaper.Undo_EndBlock("Import ComfyUI result(s)", -1)
reaper.UpdateArrange()
if reaper.Main_OnCommand then reaper.Main_OnCommand(40913, 0) end
log("Imported " .. #outputs .. " ComfyUI result(s) using saved return settings.")
