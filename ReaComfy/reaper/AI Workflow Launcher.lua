-- @description ReaComfy - Workflow Launcher (ReaImGui)
-- @version 0.5.1
-- @noindex
-- @about Selects a ComfyUI API workflow and exposes configured macro controls.

local script_file = debug.getinfo(1, "S").source:sub(2)
local root = script_file:match("^(.*)[\\/]reaper[\\/][^\\/]+$")
local config = dofile(root .. "/reaper/AI Workflow Config.lua")
root = config.root
local workflows_dir = config.workflows_dir
local private_workflows_dir = config.private_workflows_dir
local additional_workflows_dir = config.additional_workflows_dir or ""
local main_action = config.main_action
local macros_file = config.macros_file
local send_action = config.send_action
local import_action = config.import_action
local import_score_action = root .. "/reaper/ReaComfy - Import Score Output.lua"
local import_midi_output_action = root .. "/reaper/ReaComfy - Import MIDI Output.lua"
local import_video_output_action = root .. "/reaper/ReaComfy - Import Video Output.lua"
local import_text_output_action = root .. "/reaper/ReaComfy - Import Text Output.lua"
local export_video_selection_action = root .. "/reaper/ReaComfy - Export video time selection.lua"
local send_video_source_action = root .. "/reaper/ReaComfy - Send video source to ComfyUI.lua"
local reference_action = root .. "/reaper/ReaComfy - Send reference audio to ComfyUI.lua"
local yue2_sources_action = root .. "/reaper/ReaComfy - Prepare YuE2 sources.lua"

local EXT = "REAPER_AI"

local function log(message)
  reaper.ShowConsoleMsg("REAPER AI: " .. message .. "\n")
end

if not reaper.ImGui_CreateContext then
  log("ReaImGui is required for the workflow launcher.")
  return
end

local macro_definitions = {}
local ok, definitions = pcall(dofile, macros_file)
if ok and type(definitions) == "table" then
  macro_definitions = definitions
elseif not ok then
  log("Workflow macro configuration could not be loaded: " .. tostring(definitions))
end

local function read_workflows()
  local result, index = {}, 0
  local seen = {}
  local directories = {
    {path = workflows_dir, group = "public"},
    {path = private_workflows_dir, group = "private"},
  }
  for directory in additional_workflows_dir:gmatch("[^;]+") do
    directories[#directories + 1] = {path = directory:gsub("^%s+", ""):gsub("%s+$", ""), group = "additional"}
  end
  for _, directory in ipairs(directories) do
    index = 0
    while true do
      local filename = reaper.EnumerateFiles(directory.path, index)
      if not filename then break end
      if filename:lower():match("_api%.json$") and not seen[filename] then
        seen[filename] = true
        result[#result + 1] = {
          filename = filename,
          group = directory.group,
          label = filename:gsub("_[Aa][Pp][Ii]%.[Jj][Ss][Oo][Nn]$", ""):gsub("_", " ")
        }
      end
      index = index + 1
    end
  end
  table.sort(result, function(a, b) return a.label:lower() < b.label:lower() end)
  return result
end

local workflows = read_workflows()
if #workflows == 0 then
  log("No API workflows found in: " .. workflows_dir)
  return
end

local ctx = reaper.ImGui_CreateContext("ReaComfy — Workflow Launcher")
local selected = 1
local values = {}
local macros_dirty = {}
local macros_flushed_at = 0
local invalid_fields = {}
local first_frame = true
local pending_action

-- Persistent preferences ----------------------------------------------------

local output_format = reaper.GetExtState(EXT, "output_format_pref")
if output_format ~= "wav" and output_format ~= "flac" then output_format = "flac" end
local input_mode = reaper.GetExtState(EXT, "input_mode_pref")
if input_mode ~= "glue" then input_mode = "source" end
local destination_mode = reaper.GetExtState(EXT, "destination_mode_pref")
if destination_mode ~= "track" and destination_mode ~= "selected" then destination_mode = "lane" end
local return_position_mode = reaper.GetExtState(EXT, "return_position_pref")
if return_position_mode ~= "source" then return_position_mode = "cursor" end
local track_output_mode = reaper.GetExtState(EXT, "track_output_mode_pref")
if track_output_mode ~= "lanes" then track_output_mode = "separate" end
local destination_track_name = reaper.GetExtState(EXT, "destination_track_name_pref")
if destination_track_name == "" then destination_track_name = "AI Result" end
local keep_open_after_launch = reaper.GetExtState(EXT, "keep_open_pref") == "1"
local select_result_on_import = reaper.GetExtState(EXT, "select_result_pref") == "1"
local arrangement_folder_name = reaper.GetExtState(EXT, "arrangement_folder_name")
if arrangement_folder_name == "" then arrangement_folder_name = (config.defaults and config.defaults.arrangement_folder_name) or "Arrangement" end
local yue2_source_lyrics = reaper.GetExtState(EXT, "yue2_source_lyrics") ~= "0"
local yue2_source_midi = reaper.GetExtState(EXT, "yue2_source_midi") ~= "0"
local yue2_source_chords = reaper.GetExtState(EXT, "yue2_source_chords") ~= "0"
local yue2_source_arrangement = reaper.GetExtState(EXT, "yue2_source_arrangement") ~= "0"
local yue2_source_reference = reaper.GetExtState(EXT, "yue2_source_reference") ~= "0"
local yue2_lyrics_track = reaper.GetExtState(EXT, "yue2_lyrics_track")
if yue2_lyrics_track == "" then yue2_lyrics_track = (config.defaults and config.defaults.yue2_lyrics_track) or "Lyrics" end
local yue2_chords_track = reaper.GetExtState(EXT, "yue2_chords_track")
if yue2_chords_track == "" then yue2_chords_track = (config.defaults and config.defaults.yue2_chords_track) or "Chords" end
local yue2_reference_track = reaper.GetExtState(EXT, "yue2_reference_track")
if yue2_reference_track == "" and config.defaults then yue2_reference_track = config.defaults.yue2_reference_track or "" end
local yue2_midi_scope = reaper.GetExtState(EXT, "yue2_midi_scope")
if yue2_midi_scope ~= "project" and yue2_midi_scope ~= "selected" then yue2_midi_scope = (config.defaults and config.defaults.yue2_midi_scope) or "selected" end
local video_track_name = reaper.GetExtState(EXT, "video_track_name")
if video_track_name == "" and config.defaults then video_track_name = config.defaults.video_track_name or "" end
local cutscene_track_name = reaper.GetExtState(EXT, "cutscene_track_name")
if cutscene_track_name == "" and config.defaults then cutscene_track_name = config.defaults.cutscene_track_name or "" end

local workflow_waiting = false
local workflow_started = 0
local cached_picker_open = false
local cached_files = {}
local cached_selected = {}

-- Status line ---------------------------------------------------------------

local STATUS_COLORS = {
  info = 0x9A9A9AFF, ok = 0x3CC593FF, busy = 0xE6A04FFF, error = 0xE86A6AFF,
}
local status = {text = "Ready.", kind = "info"}

local function set_status(text, kind)
  status.text = text
  status.kind = kind or "info"
  if kind == "error" then log(text) end
end

local function draw_status()
  local text, kind = status.text, status.kind
  if workflow_waiting then
    local elapsed = math.max(0, math.floor(reaper.time_precise() - workflow_started))
    text = string.format("Waiting for ComfyUI... %d:%02d", elapsed // 60, elapsed % 60)
    kind = "busy"
  end
  if reaper.ImGui_TextColored then
    reaper.ImGui_TextColored(ctx, STATUS_COLORS[kind] or STATUS_COLORS.info, text)
  else
    reaper.ImGui_Text(ctx, text)
  end
end

-- Cached results --------------------------------------------------------------

local function cached_result_caches()
  local result = {}
  local project_dir = reaper.GetProjectPathEx(0, "")
  if project_dir and project_dir ~= "" then result[#result + 1] = project_dir .. "/REAPER_AI_CACHE" end
  result[#result + 1] = root .. "/runtime"
  local user_profile = os.getenv("USERPROFILE") or os.getenv("HOME")
  if user_profile then result[#result + 1] = user_profile .. "/REAPER_AI_CACHE" end
  return result
end

local function refresh_cached_files()
  local found, seen = {}, {}
  local extensions = {wav = true, flac = true, mp3 = true, ogg = true, m4a = true}
  for _, cache in ipairs(cached_result_caches()) do
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
  cached_files = found
  cached_selected = {}
  -- Results use a sortable timestamp in their filename, so the first row is
  -- the newest cached result. Preselect it for the usual single-result import.
  if #cached_files > 0 then cached_selected[1] = true end
end

local function open_cached_picker()
  refresh_cached_files()
  cached_picker_open = true
end

local function write_cached_selection()
  local chosen = {}
  for i, file in ipairs(cached_files) do
    if cached_selected[i] then chosen[#chosen + 1] = file.path end
  end
  if #chosen == 0 then
    set_status("Select at least one cached result file.", "error")
    return false
  end
  reaper.SetExtState(EXT, "import_selection", table.concat(chosen, "\n"), false)
  return true
end

local function workflow_status_path()
  local project_dir = reaper.GetProjectPathEx(0, "")
  if project_dir and project_dir ~= "" then
    return project_dir .. "/REAPER_AI_CACHE/latest_result.json"
  end
  return root .. "/runtime/latest_result.json"
end

-- Runs a sibling script; errors go to the status line instead of stopping the launcher.
local function run_action(path, ok_text, fail_text)
  local success, error_message = pcall(dofile, path)
  if success then
    if ok_text then set_status(ok_text, "ok") end
  else
    set_status(fail_text .. ": " .. tostring(error_message), "error")
  end
  return success
end

local function poll_workflow_result()
  if not workflow_waiting then return end
  local file = io.open(workflow_status_path(), "r")
  if not file then return end
  local content = file:read("*a")
  file:close()
  if not content or content == "" then return end
  if content:find('"status":%s*"failed"') then
    workflow_waiting = false
    local error_text = content:match('"error":%s*"(.-)"') or "See the REAPER Console for details."
    set_status("ComfyUI job failed: " .. error_text, "error")
  elseif content:find('"status":%s*"complete"') then
    workflow_waiting = false
    run_action(import_action, "ComfyUI job finished; result imported.", "Could not import the ComfyUI result")
  end
end

-- Preferences ---------------------------------------------------------------
-- Values are compared with what was last written, so REAPER's extstate file is
-- only touched when something actually changes (not on every frame).

local function encode_value(value)
  return (tostring(value):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function decode_value(value)
  return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function bool_pref(value) return value and "1" or "0" end

local written_prefs = {}

local function macro_state_key(filename) return "macros|" .. filename end

local function save_macro_values(filename)
  local macros = macro_definitions[filename] or {}
  local current = values[filename]
  if not current then return end
  local parts = {}
  for i, macro in ipairs(macros) do
    if current[i] ~= nil then
      parts[#parts + 1] = encode_value(macro.node .. "|" .. macro.input) .. "=" .. encode_value(current[i])
    end
  end
  reaper.SetExtState(EXT, macro_state_key(filename), table.concat(parts, ";"), true)
end

-- force: also flush macro values right away (used before running and on close).
local function save_preferences(force)
  local prefs = {
    output_format_pref = output_format,
    input_mode_pref = input_mode,
    destination_mode_pref = destination_mode,
    return_position_pref = return_position_mode,
    track_output_mode_pref = track_output_mode,
    destination_track_name_pref = destination_track_name,
    keep_open_pref = bool_pref(keep_open_after_launch),
    select_result_pref = bool_pref(select_result_on_import),
    arrangement_folder_name = arrangement_folder_name,
    yue2_source_lyrics = bool_pref(yue2_source_lyrics),
    yue2_source_midi = bool_pref(yue2_source_midi),
    yue2_source_chords = bool_pref(yue2_source_chords),
    yue2_source_arrangement = bool_pref(yue2_source_arrangement),
    yue2_source_reference = bool_pref(yue2_source_reference),
    yue2_lyrics_track = yue2_lyrics_track,
    yue2_chords_track = yue2_chords_track,
    yue2_reference_track = yue2_reference_track,
    yue2_midi_scope = yue2_midi_scope,
    video_track_name = video_track_name,
    cutscene_track_name = cutscene_track_name,
  }
  for key, value in pairs(prefs) do
    if written_prefs[key] ~= value then
      reaper.SetExtState(EXT, key, value, true)
      written_prefs[key] = value
    end
  end
  -- Slider drags change macro values every frame; write them at most once a second.
  local now = reaper.time_precise()
  if next(macros_dirty) and (force or now - macros_flushed_at >= 1.0) then
    for filename in pairs(macros_dirty) do save_macro_values(filename) end
    macros_dirty = {}
    macros_flushed_at = now
  end
end

-- Workflow macros -------------------------------------------------------------

local function clamp_macro_value(macro, value)
  if macro.kind == "string" then return tostring(value) end
  if macro.kind == "choice" then
    for _, option in ipairs(macro.options or {}) do
      if option == value then return value end
    end
    return nil
  end
  local number = tonumber(value)
  if not number then return nil end
  if macro.min then number = math.max(macro.min, number) end
  if macro.max then number = math.min(macro.max, number) end
  if macro.integer then number = math.floor(number + 0.5) end
  return number
end

local function macro_values(filename)
  if values[filename] then return values[filename] end
  local macros = macro_definitions[filename] or {}
  local current = {}
  for i, macro in ipairs(macros) do
    current[i] = macro.default or macro.min or 0
    if macro.kind == "choice" and macro.default == nil then current[i] = (macro.options or {})[1] end
  end
  -- Restore the values last used with this preset (matched by node + input,
  -- so editing AI Workflow Macros.lua does not shift values between controls).
  local stored = {}
  for pair in reaper.GetExtState(EXT, macro_state_key(filename)):gmatch("[^;]+") do
    local key, value = pair:match("^(.-)=(.*)$")
    if key then stored[decode_value(key)] = decode_value(value) end
  end
  for i, macro in ipairs(macros) do
    local saved = stored[macro.node .. "|" .. macro.input]
    if saved ~= nil then
      local restored = clamp_macro_value(macro, saved)
      if restored ~= nil then current[i] = restored end
    end
  end
  values[filename] = current
  return current
end

local function reset_macro_values(filename)
  values[filename] = nil
  invalid_fields[filename] = nil
  macros_dirty[filename] = nil
  reaper.DeleteExtState(EXT, macro_state_key(filename), true)
  macro_values(filename)
  set_status("Parameters reset to defaults.", "info")
end

-- UI helpers ----------------------------------------------------------------

-- Button roles: send = data leaves REAPER, import = data comes back,
-- run = start the workflow, danger = deletes something, neutral = utility.
local BUTTON_COLORS = {
  send = {0xD97A3AFF, 0xE6924FFF, 0xB95F28FF},
  import = {0x226757FF, 0x29A889FF, 0x1B5347FF},
  run = {0x2F6FB0FF, 0x3C86D0FF, 0x265C93FF},
  danger = {0xB44A4AFF, 0xD05C5CFF, 0x8F3535FF},
  neutral = {0x3A3A3AFF, 0x4A4A4AFF, 0x555555FF},
}

local function set_control_width(width)
  if reaper.ImGui_SetNextItemWidth then reaper.ImGui_SetNextItemWidth(ctx, width) end
end

local function aligned_label(label, width, color)
  if color and reaper.ImGui_TextColored then
    reaper.ImGui_TextColored(ctx, color, label)
  else
    reaper.ImGui_Text(ctx, label)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SetCursorPosX then reaper.ImGui_SetCursorPosX(ctx, width or 190) end
end

local function half_button_width()
  if reaper.ImGui_GetContentRegionAvail then
    local width = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
    if width and width > 120 then return (width - 8) * 0.5 end
  end
  return 300
end

local function tooltip(text)
  if text and reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, text) end
end

local function button(label, width, role, help, height)
  local colors = BUTTON_COLORS[role] or BUTTON_COLORS.neutral
  local pushed = 0
  if reaper.ImGui_Col_Button then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colors[1]); pushed = pushed + 1 end
  if reaper.ImGui_Col_ButtonHovered then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colors[2]); pushed = pushed + 1 end
  if reaper.ImGui_Col_ButtonActive then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colors[3]); pushed = pushed + 1 end
  local clicked = reaper.ImGui_Button(ctx, label, width or 0, height or 28)
  if pushed > 0 then reaper.ImGui_PopStyleColor(ctx, pushed) end
  tooltip(help)
  return clicked
end

local function group_title(title, subtitle)
  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_SeparatorText then
    reaper.ImGui_SeparatorText(ctx, title)
  else
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, title)
  end
  if subtitle then reaper.ImGui_TextDisabled(ctx, subtitle) end
end

local function hint(text)
  if reaper.ImGui_PushTextWrapPos then
    reaper.ImGui_PushTextWrapPos(ctx, 0)
    reaper.ImGui_TextDisabled(ctx, text)
    reaper.ImGui_PopTextWrapPos(ctx)
  else
    reaper.ImGui_TextDisabled(ctx, text)
  end
end

local function text_field(label, id, value)
  aligned_label(label)
  set_control_width(-1)
  local changed, new_value = reaper.ImGui_InputText(ctx, id, value, reaper.ImGui_InputTextFlags_None())
  if changed then return new_value end
  return value
end

-- options: list of {value, label}
local function combo(label, id, current, options)
  aligned_label(label)
  set_control_width(-1)
  local preview = current
  for _, option in ipairs(options) do
    if option[1] == current then preview = option[2] end
  end
  if reaper.ImGui_BeginCombo(ctx, id, preview) then
    for _, option in ipairs(options) do
      if reaper.ImGui_Selectable(ctx, option[2], current == option[1]) then current = option[1] end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  return current
end

local function push_postmaster_theme()
  local colors = {
    {"WindowBg", 0x1E1E1EFF}, {"ChildBg", 0x1E1E1EFF}, {"PopupBg", 0x202020FF},
    {"FrameBg", 0x151515FF}, {"FrameBgHovered", 0x333333FF}, {"FrameBgActive", 0x404040FF},
    {"Text", 0xDEDEDEFF}, {"TextDisabled", 0x7E7E7EFF}, {"Border", 0x3A3A3AFF},
    {"Button", 0x3A3A3AFF}, {"ButtonHovered", 0x4A4A4AFF}, {"ButtonActive", 0x555555FF},
    {"Header", 0x292929FF}, {"HeaderHovered", 0x3B3B3BFF}, {"HeaderActive", 0x484848FF},
    {"CheckMark", 0x2D8C6DFF}, {"SliderGrab", 0x28755FFF}, {"SliderGrabActive", 0x35A482FF},
    {"TitleBg", 0x181818FF}, {"TitleBgActive", 0x202020FF}, {"Separator", 0x4A4A4AFF},
    {"ScrollbarGrab", 0x3A3A3AFF}, {"ScrollbarGrabHovered", 0x4A4A4AFF}, {"ResizeGripActive", 0x2D8C6DFF},
    -- Tab colours; older ReaImGui calls the selected tab "TabActive".
    {"Tab", 0x262626FF}, {"TabHovered", 0x2E7D69FF},
    {"TabActive", 0x226757FF}, {"TabSelected", 0x226757FF}, {"TabSelectedOverline", 0x35A482FF},
  }
  local count = 0
  for _, entry in ipairs(colors) do
    local enum = reaper["ImGui_Col_" .. entry[1]]
    if enum then reaper.ImGui_PushStyleColor(ctx, enum(), entry[2]); count = count + 1 end
  end
  local vars = 0
  if reaper.ImGui_StyleVar_FrameRounding then reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5); vars = vars + 1 end
  if reaper.ImGui_StyleVar_WindowPadding then reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 14, 12); vars = vars + 1 end
  if reaper.ImGui_StyleVar_ItemSpacing then reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 5); vars = vars + 1 end
  return count, vars
end

local function pop_postmaster_theme(count, vars)
  if vars > 0 then reaper.ImGui_PopStyleVar(ctx, vars) end
  if count > 0 then reaper.ImGui_PopStyleColor(ctx, count) end
end

local function destroy_context()
  if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
end

-- Actions -------------------------------------------------------------------

local function refresh_workflows()
  local current_filename = workflows[selected] and workflows[selected].filename
  local refreshed = read_workflows()
  if #refreshed == 0 then
    set_status("No API workflows found; keeping the current list.", "error")
    return
  end
  workflows = refreshed
  selected = 1
  for i, workflow in ipairs(workflows) do
    if workflow.filename == current_filename then selected = i break end
  end
  set_status("Preset list refreshed: " .. #workflows .. " workflow(s) found.", "info")
end

-- Returns true only when the workflow was actually started. A missing required
-- field keeps the launcher open and highlights the field.
local function close_and_launch()
  local workflow = workflows[selected]
  local macros = macro_definitions[workflow.filename] or {}
  local selected_values = macro_values(workflow.filename)
  local overrides, missing = {}, {}
  invalid_fields[workflow.filename] = nil
  for i, macro in ipairs(macros) do
    local value = selected_values[i]
    if macro.required and (not value or tostring(value):match("^%s*$")) then
      invalid_fields[workflow.filename] = invalid_fields[workflow.filename] or {}
      invalid_fields[workflow.filename][i] = true
      missing[#missing + 1] = macro.label
    end
    if macro.kind == "string" or macro.kind == "choice" then value = encode_value(value) end
    overrides[#overrides + 1] = table.concat({macro.node, macro.input, tostring(value)}, "|")
  end
  if #missing > 0 then
    set_status("Fill in the required field(s): " .. table.concat(missing, ", "), "error")
    return false
  end
  reaper.SetExtState(EXT, "selected_workflow", workflow.filename, false)
  reaper.SetExtState(EXT, "workflow_overrides", table.concat(overrides, ";"), false)
  reaper.SetExtState(EXT, "output_format", output_format, false)
  reaper.SetExtState(EXT, "input_mode", input_mode, false)
  reaper.SetExtState(EXT, "destination_mode", destination_mode, false)
  reaper.SetExtState(EXT, "track_output_mode", track_output_mode, false)
  reaper.SetExtState(EXT, "destination_track_name", destination_track_name, false)
  reaper.SetExtState(EXT, "launcher_manages_job", keep_open_after_launch and "1" or "0", false)
  save_preferences(true)
  if not keep_open_after_launch then
    destroy_context()
  end
  dofile(main_action)
  if keep_open_after_launch then
    workflow_waiting = true
    workflow_started = reaper.time_precise()
    set_status("Workflow started: " .. workflow.label, "busy")
  end
  return true
end

local function clear_reacomfy_cache()
  local directories = {}
  local project_dir = reaper.GetProjectPathEx(0, "")
  if project_dir and project_dir ~= "" then directories[#directories + 1] = project_dir .. "/REAPER_AI_CACHE" end
  directories[#directories + 1] = root .. "/runtime"
  local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
  if user_root then directories[#directories + 1] = user_root .. "/REAPER_AI_CACHE" end
  local removed = 0
  local function is_reacomfy_file(name)
    local lower = tostring(name or ""):lower()
    return lower == "reaper_to_comfy.json" or lower == "comfy_to_reaper.json" or lower == "latest_result.json"
      or lower == "current_project.txt" or lower:match("^reacomfy_") or lower:match("^comfy_to_reaper_")
  end
  for _, directory in ipairs(directories) do
    local names, index = {}, 0
    while true do
      local name = reaper.EnumerateFiles(directory, index)
      if not name then break end
      if is_reacomfy_file(name) then names[#names + 1] = name end
      index = index + 1
    end
    for _, name in ipairs(names) do
      if os.remove(directory .. "/" .. name) then removed = removed + 1 end
    end
  end
  set_status("ReaComfy cache cleared (" .. tostring(removed) .. " file(s)).", "ok")
end

local function request_audio_import()
  if select_result_on_import then open_cached_picker() else pending_action = "import" end
end

-- Tabs ----------------------------------------------------------------------

local function draw_macros(workflow)
  local macros = macro_definitions[workflow.filename] or {}
  if #macros == 0 then
    hint("This preset has no adjustable parameters. Add them in AI Workflow Macros.lua.")
    return
  end
  local selected_values = macro_values(workflow.filename)
  local invalid = invalid_fields[workflow.filename] or {}
  for i, macro in ipairs(macros) do
    local changed, new_value
    local error_color = invalid[i] and STATUS_COLORS.error or nil
    local pushed = 0
    if invalid[i] and reaper.ImGui_Col_FrameBg then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x4A2020FF); pushed = 1
    end
    if macro.kind == "choice" then
      aligned_label(macro.label, nil, error_color)
      set_control_width(-1)
      local preview = selected_values[i] or macro.options[1]
      if reaper.ImGui_BeginCombo(ctx, "##macro_choice_" .. i, preview) then
        for _, option in ipairs(macro.options) do
          if reaper.ImGui_Selectable(ctx, option, preview == option) then
            changed, new_value = true, option
          end
        end
        reaper.ImGui_EndCombo(ctx)
      end
    elseif macro.kind == "string" then
      reaper.ImGui_Spacing(ctx)
      local label = macro.label .. (macro.required and " *" or "")
      if error_color and reaper.ImGui_TextColored then
        reaper.ImGui_TextColored(ctx, error_color, label)
      else
        reaper.ImGui_Text(ctx, label)
      end
      if macro.multiline then
        local text_flags = reaper.ImGui_InputTextFlags_None()
        if reaper.ImGui_InputTextFlags_WordWrap then
          text_flags = text_flags | reaper.ImGui_InputTextFlags_WordWrap()
        end
        changed, new_value = reaper.ImGui_InputTextMultiline(ctx, "##macro_text_" .. i, selected_values[i] or "", -1, 78, text_flags)
      else
        set_control_width(-1)
        changed, new_value = reaper.ImGui_InputText(ctx, "##macro_text_" .. i, selected_values[i] or "", reaper.ImGui_InputTextFlags_None())
      end
    elseif macro.integer then
      aligned_label(macro.label, nil, error_color)
      set_control_width(-1)
      changed, new_value = reaper.ImGui_SliderInt(ctx, "##macro_slider_" .. i, math.floor(selected_values[i] + 0.5), macro.min, macro.max)
    else
      aligned_label(macro.label, nil, error_color)
      set_control_width(-1)
      changed, new_value = reaper.ImGui_SliderDouble(ctx, "##macro_slider_" .. i, selected_values[i], macro.min, macro.max, macro.format or "%.2f")
    end
    if pushed > 0 then reaper.ImGui_PopStyleColor(ctx, pushed) end
    tooltip(macro.help)
    if changed then
      selected_values[i] = new_value
      macros_dirty[workflow.filename] = true
      invalid[i] = nil
    end
  end
end

local GROUP_LABELS = {public = "built-in preset", private = "private preset", additional = "additional preset folder"}

local function draw_workflow_tab()
  local width = half_button_width()

  group_title("SEND TO COMFYUI  ->")
  local send_label = input_mode == "glue" and "Export selected item(s) via Glue" or "Send source item"
  local send_help = input_mode == "glue"
    and "Glues the visible part of the selected item(s) into a temporary file for ComfyUI.\nChange this in Settings > Input preparation."
    or "Hands the original media file of the selected item to ComfyUI; the result is trimmed back to the item.\nChange this in Settings > Input preparation."
  if button(send_label, width, "send", send_help) then pending_action = "send" end
  reaper.ImGui_SameLine(ctx)
  if button("Send reference audio", width, "send", "Sends the selected item as reference audio (voice match, voice clone).\nThe target item path is kept.") then pending_action = "reference" end

  group_title("PRESET")
  if button("Refresh", 90, "neutral", "Re-read the preset folders after adding or renaming *_api.json files.", 24) then refresh_workflows() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, tostring(#workflows) .. " preset(s)")
  local preset_style_count = 0
  if reaper.ImGui_PushStyleColor then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x242424FF); preset_style_count = preset_style_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x226757FF); preset_style_count = preset_style_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x2E7D69FF); preset_style_count = preset_style_count + 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x35A482FF); preset_style_count = preset_style_count + 1
  end
  if reaper.ImGui_BeginChild(ctx, "workflow_list", -1, 160, 1) then
    for i, workflow in ipairs(workflows) do
      if reaper.ImGui_Selectable(ctx, workflow.label, i == selected) then selected = i end
      tooltip(workflow.filename .. "  (" .. (GROUP_LABELS[workflow.group] or workflow.group) .. ")")
    end
    reaper.ImGui_EndChild(ctx)
  end
  if preset_style_count > 0 then reaper.ImGui_PopStyleColor(ctx, preset_style_count) end

  local workflow = workflows[selected]
  group_title("PARAMETERS: " .. workflow.label:upper())
  if #(macro_definitions[workflow.filename] or {}) > 0 then
    if button("Reset to defaults", 150, "neutral", "Restore the default values from AI Workflow Macros.lua for this preset.", 24) then
      reset_macro_values(workflow.filename)
    end
  end
  draw_macros(workflow)

  reaper.ImGui_Spacing(ctx)
  if button("Run workflow: " .. workflow.label, -1, "run", "Processes the selected item(s) with this preset in ComfyUI and imports the result.", 36) then
    pending_action = "workflow"
  end

  group_title("<-  IMPORT FROM COMFYUI")
  local import_help = select_result_on_import
    and "Opens a dated list of cached results so you can pick the iteration(s) to import."
    or "Imports the latest ComfyUI audio result.\nEnable 'Choose cached result when importing' in Settings to pick older runs."
  if button("Import audio result", width, "import", import_help) then request_audio_import() end
  reaper.ImGui_SameLine(ctx)
  if button("Import text output", width, "import", "Imports transcription, subtitle or analysis text produced by ComfyUI.") then pending_action = "import_text_output" end
end

local function draw_yue2_tab()
  group_title("YUE2 SOURCES", "Choose the REAPER sources to include in one ComfyUI manifest.")
  local _
  _, yue2_source_lyrics = reaper.ImGui_Checkbox(ctx, "Lyrics from items", yue2_source_lyrics)
  yue2_lyrics_track = text_field("Lyrics track", "##yue2_lyrics_track", yue2_lyrics_track)
  _, yue2_source_midi = reaper.ImGui_Checkbox(ctx, "MIDI score", yue2_source_midi)
  yue2_midi_scope = combo("MIDI range", "##yue2_midi_scope", yue2_midi_scope, {
    {"selected", "Selected MIDI items"}, {"project", "Entire project"},
  })
  _, yue2_source_chords = reaper.ImGui_Checkbox(ctx, "Chords text", yue2_source_chords)
  yue2_chords_track = text_field("Chords track", "##yue2_chords_track", yue2_chords_track)
  _, yue2_source_arrangement = reaper.ImGui_Checkbox(ctx, "Arrangement folder", yue2_source_arrangement)
  arrangement_folder_name = text_field("Arrangement folder", "##yue2_arrangement_folder", arrangement_folder_name)
  _, yue2_source_reference = reaper.ImGui_Checkbox(ctx, "Reference audio", yue2_source_reference)
  yue2_reference_track = text_field("Reference track", "##yue2_reference_track", yue2_reference_track)
  hint("Leave the reference track empty to use the single selected audio item. If the reference has several items, glue them into one first.")

  group_title("SEND TO COMFYUI  ->")
  if button("Export YuE2 sources", -1, "send", "Writes the checked sources into one manifest for the YuE2 workflow.") then pending_action = "yue2_sources" end

  group_title("<-  IMPORT FROM COMFYUI")
  local width = half_button_width()
  if button("Import Score + ABC + Lyrics", width, "import", "Imports the YuE2 score, ABC notation and lyrics output.") then pending_action = "import_score" end
  reaper.ImGui_SameLine(ctx)
  if button("Import external MIDI", width, "import", "Imports a MIDI file produced by an external ComfyUI node.") then pending_action = "import_midi_output" end
end

local function draw_video_tab()
  local width = half_button_width()
  group_title("SEND TO COMFYUI  ->")
  if button("Send video source", width, "send", "Hands the selected video item's source file to ComfyUI.") then pending_action = "send_video_source" end
  reaper.ImGui_SameLine(ctx)
  if button("Export video time selection", width, "send", "Exports the time selection (or the cutscene item) of the video track with FFmpeg and sends it.") then pending_action = "export_video_selection" end

  group_title("<-  IMPORT FROM COMFYUI")
  if button("Import video output", -1, "import", "Imports the video produced by ComfyUI.") then pending_action = "import_video_output" end

  group_title("VIDEO TRACKS")
  video_track_name = text_field("Video track name", "##video_track_name", video_track_name)
  hint("Used by Export video time selection. Leave empty to search all tracks.")
  cutscene_track_name = text_field("Cutscene track name", "##cutscene_track_name", cutscene_track_name)
  hint("Used when there is no time selection: the cutscene item's boundaries are exported.")
end

local function draw_settings_tab()
  group_title("AUDIO TO COMFYUI")
  input_mode = combo("Input preparation", "##input_mode", input_mode, {
    {"source", "Original source"}, {"glue", "Glue visible item"},
  })
  hint(input_mode == "glue"
    and "Creates a temporary Glue of the visible item section before AI processing."
    or "Sends the original media source file; the bridge still returns audio trimmed to the item.")
  output_format = combo("File format", "##output_format", output_format, {
    {"flac", "FLAC"}, {"wav", "WAV"},
  })

  group_title("RESULT IN REAPER")
  destination_mode = combo("Return result", "##destination_mode", destination_mode, {
    {"lane", "New fixed lane"}, {"track", "New track"}, {"selected", "Selected track"},
  })
  if destination_mode == "track" or destination_mode == "selected" then
    destination_track_name = text_field("Track name", "##track_name", destination_track_name)
    track_output_mode = combo("Multiple outputs", "##track_output_mode", track_output_mode, {
      {"separate", "Separate track per output"}, {"lanes", "One track + fixed lanes"},
    })
  end
  return_position_mode = combo("Return position", "##return_position", return_position_mode, {
    {"cursor", "Edit cursor"}, {"source", "Original source position"},
  })

  group_title("LAUNCHER")
  local _
  _, keep_open_after_launch = reaper.ImGui_Checkbox(ctx, "Keep launcher open after starting workflow", keep_open_after_launch)
  tooltip("The launcher stays open, shows the job status and imports the result when ComfyUI finishes.")
  _, select_result_on_import = reaper.ImGui_Checkbox(ctx, "Choose cached result when importing", select_result_on_import)
  hint("Shows a dated list so repeated ComfyUI runs do not get imported together.")

  group_title("MAINTENANCE")
  if button("Clear ReaComfy cache", -1, "danger", "Deletes bridge manifests and temporary comfy_to_reaper_* results.\nProject media is not touched.") then clear_reacomfy_cache() end
  hint("Removes bridge manifests and temporary ReaComfy files only.")
end

local TABS = {
  {label = "Workflow", draw = draw_workflow_tab},
  {label = "YuE2 / Music", draw = draw_yue2_tab},
  {label = "Video", draw = draw_video_tab},
  {label = "Settings", draw = draw_settings_tab},
}

local function draw_tabs()
  if not reaper.ImGui_BeginTabBar(ctx, "reacomfy_tabs") then return end
  for i, tab in ipairs(TABS) do
    -- At launch the first tab (Workflow) is always the one shown.
    local flags = 0
    if first_frame and i == 1 and reaper.ImGui_TabItemFlags_SetSelected then
      flags = reaper.ImGui_TabItemFlags_SetSelected()
    end
    if reaper.ImGui_BeginTabItem(ctx, tab.label, nil, flags) then
      tab.draw()
      reaper.ImGui_EndTabItem(ctx)
    end
  end
  reaper.ImGui_EndTabBar(ctx)
end

local function draw_cached_picker()
  if reaper.ImGui_SetNextWindowSize and reaper.ImGui_Cond_FirstUseEver then
    reaper.ImGui_SetNextWindowSize(ctx, 720, 460, reaper.ImGui_Cond_FirstUseEver())
  end
  local picker_visible, picker_open = reaper.ImGui_Begin(ctx, "ReaComfy — Cached results", true)
  if picker_visible then
    reaper.ImGui_Text(ctx, "Select one or more cached ComfyUI results to import.")
    reaper.ImGui_TextDisabled(ctx, "Newest files are listed first; multiple selections are supported for stems.")
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_BeginChild(ctx, "cached_results_list", -1, 300, 1) then
      if reaper.ImGui_BeginTable then
        reaper.ImGui_BeginTable(ctx, "cached_results_table", 2, 0)
        if reaper.ImGui_TableSetupColumn then
          reaper.ImGui_TableSetupColumn(ctx, "Use")
          reaper.ImGui_TableSetupColumn(ctx, "Cached result")
          if reaper.ImGui_TableHeadersRow then reaper.ImGui_TableHeadersRow(ctx) end
        end
        for i, file in ipairs(cached_files) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local changed, value = reaper.ImGui_Checkbox(ctx, "##cached_" .. tostring(i), cached_selected[i] == true)
          if changed then cached_selected[i] = value end
          reaper.ImGui_TableSetColumnIndex(ctx, 1)
          reaper.ImGui_Text(ctx, file.label)
        end
        reaper.ImGui_EndTable(ctx)
      else
        for i, file in ipairs(cached_files) do
          local changed, value = reaper.ImGui_Checkbox(ctx, string.format("%02d  %s##cached_%d", i, file.label, i), cached_selected[i] == true)
          if changed then cached_selected[i] = value end
        end
      end
      if #cached_files == 0 then
        reaper.ImGui_TextDisabled(ctx, "No cached audio results found.")
      end
      reaper.ImGui_EndChild(ctx)
    end
    if button("Select all", 100, "neutral") then
      for i = 1, #cached_files do cached_selected[i] = true end
    end
    reaper.ImGui_SameLine(ctx)
    if button("Clear", 100, "neutral") then cached_selected = {} end
    reaper.ImGui_SameLine(ctx)
    if button("Import selected", 150, "import") then
      if write_cached_selection() then
        cached_picker_open = false
        pending_action = "import"
      end
    end
    reaper.ImGui_SameLine(ctx)
    if button("Cancel", 100, "neutral") then
      cached_picker_open = false
    end
  end
  if picker_visible then reaper.ImGui_End(ctx) end
  if not picker_open then cached_picker_open = false end
end

-- Actions that close the launcher afterwards unless "Keep launcher open" is on.
local CLOSING_ACTIONS = {
  send = true, import = true, import_score = true, import_midi_output = true,
  import_video_output = true, import_text_output = true, export_video_selection = true,
  send_video_source = true, reference = true, workflow = true,
}

-- Returns true when the action succeeded (failures keep the launcher open).
local function perform_pending_action(action)
  if action == "send" then
    return run_action(send_action, input_mode == "glue" and "Selected item(s) exported via Glue." or "Source item sent to ComfyUI.", "Could not send the selected item(s)")
  elseif action == "import" then
    return run_action(import_action, "Audio result imported.", "Could not import the ComfyUI result")
  elseif action == "import_score" then
    return run_action(import_score_action, "YuE2 score output imported.", "Could not import YuE2 score output")
  elseif action == "import_midi_output" then
    return run_action(import_midi_output_action, "External MIDI imported.", "Could not import external MIDI output")
  elseif action == "import_video_output" then
    return run_action(import_video_output_action, "Video output imported.", "Could not import video output")
  elseif action == "import_text_output" then
    return run_action(import_text_output_action, "Text output imported.", "Text import failed")
  elseif action == "export_video_selection" then
    return run_action(export_video_selection_action, "Video time selection exported.", "Could not export video selection")
  elseif action == "send_video_source" then
    return run_action(send_video_source_action, "Video source sent to ComfyUI.", "Could not send video source")
  elseif action == "reference" then
    return run_action(reference_action, "Reference audio sent to ComfyUI.", "Could not prepare reference audio")
  elseif action == "yue2_sources" then
    return run_action(yue2_sources_action, "YuE2 sources exported.", "Could not prepare YuE2 sources")
  elseif action == "workflow" then
    return close_and_launch()
  end
  return false
end

local function loop()
  pending_action = nil
  save_preferences()
  poll_workflow_result()
  if reaper.ImGui_SetNextWindowSizeConstraints then reaper.ImGui_SetNextWindowSizeConstraints(ctx, 560, 420, 1280, 1100) end
  reaper.ImGui_SetNextWindowSize(ctx, 760, 720, reaper.ImGui_Cond_FirstUseEver())
  if reaper.ImGui_GetMainViewport and reaper.ImGui_Viewport_GetCenter and reaper.ImGui_SetNextWindowPos then
    local viewport = reaper.ImGui_GetMainViewport(ctx)
    local cx, cy = reaper.ImGui_Viewport_GetCenter(viewport)
    reaper.ImGui_SetNextWindowPos(ctx, cx, cy, reaper.ImGui_Cond_FirstUseEver(), 0.5, 0.5)
  end
  local style_colors, style_vars = push_postmaster_theme()
  local visible, open = reaper.ImGui_Begin(ctx, "ReaComfy — Select workflow", true)
  if visible then
    -- Tabs scroll inside a child window so the status line stays at the bottom.
    local footer = 30
    if reaper.ImGui_GetFrameHeightWithSpacing then footer = reaper.ImGui_GetFrameHeightWithSpacing(ctx) + 8 end
    if reaper.ImGui_BeginChild(ctx, "launcher_body", 0, -footer) then
      draw_tabs()
      reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_Separator(ctx)
    draw_status()
    reaper.ImGui_End(ctx)
  end
  if cached_picker_open then draw_cached_picker() end
  pop_postmaster_theme(style_colors, style_vars)
  first_frame = false

  local action = pending_action
  if action then save_preferences(true) end
  local succeeded = action and perform_pending_action(action)
  if succeeded and CLOSING_ACTIONS[action] and not keep_open_after_launch then
    -- A started workflow has already released the context before running.
    if action ~= "workflow" then destroy_context() end
    return
  end
  if open then
    reaper.defer(loop)
  else
    save_preferences(true)
    destroy_context()
  end
end

loop()
