-- @description VO QC Analyzer - Voice-Over Quality Control Tool
-- @author SBP & AI
-- @version 2.0.2
-- @about Automated quality control for voice-over recordings using speech-to-text analysis
-- @link https://github.com/SBP-Reaper-Scripts
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--   v1.0.0 - Initial release with Flask server integration and Whisper STT
--   v1.0.1 - Fix JSON parsing, restore audio path extraction, and apply results reliably
--   v1.0.2 - Fix trimmed/offset items rendering, add item notes and regions with transcribed text
--   v2.0.0 - Split results into sentence-level analysis, add Whisper timestamp integration
--   v2.0.1 - Add async HTTP polling, fix UI freezing during analysis
--   v2.0.2 - Complete rewrite of check_http_response() with file stability detection
--          - Add detection for duplicate source files (multiple items from one wav)
--          - Add options to save transcribed text to item notes and create regions
--   v1.0.3 - Fix Unicode decoding (кирилиця in JSON responses)
--          - Add UTF-8 BOM to CSV export for proper Excel display
--          - Improve CSV field escaping for special characters
--          - Add detailed debug logging for transcribed text
--   v2.0.0 - **MAJOR UPDATE: Professional Sentence-by-Sentence Analysis**
--          - Auto-detect language (no more hardcoded UK)
--          - Split text into sentences for granular comparison
--          - Create separate region for each sentence (optional)
--          - Professional CSV export with sentence-level comparison
--          - Show detected language in results
--          - Better duplicate detection (immediate repeats)
--          - Comprehensive Excel report format
--   v2.0.1 - **PRODUCTION FEATURES & STABILITY**
--          - ✓ Settings persistence (save/load all user preferences automatically)
--          - ✓ Force language option (avoid wrong auto-detection)
--          - ✓ Terminology/glossary support (improve Whisper recognition)
--          - ✓ Create text track with transcribed items
--          - ✓ Fix region text truncation (smart truncate with ellipsis)
--          - ✓ Auto-load settings on startup
--          - ✓ Auto-save settings on each frame

local r = reaper
local ctx = nil

-- Initialize ReaImGui context only if available
if r.APIExists('ImGui_GetVersion') then
  ctx = r.ImGui_CreateContext('VO QC Analyzer v2.0')
end

-- Configuration
local CONFIG = {
  server_url = "http://localhost:5000",
  server_timeout = 600,  -- 10 minutes for long audio files (Whisper takes ~1x realtime on CPU)
  temp_dir = r.GetResourcePath() .. "/Temp/VO_QC",
  language = nil,  -- Auto-detect language (Whisper will determine it)
  check_server_interval = 0.5,
  settings_file = r.GetResourcePath() .. "/VO_QC_Settings.json"  -- Store settings here
}

-- ============================================================
-- COLORS
-- ============================================================

local COLOR = {
  bg_dark = 0x1A1A1AFF,
  bg_lighter = 0x252525FF,
  accent = 0x2D8C6DFF,
  accent_lite = 0x2A7A5FFF,
  header = 0xFF8C6DFF,
  text = 0xE0E0E0FF,
  text_dim = 0x808080FF,
  error_red = 0xFF6B6BFF,
  warn_yellow = 0xFFD93DFF,
  ok_green = 0x6BCB77FF,
  off_blue = 0x4D96FFFF
}

-- ============================================================
-- UTILITY FUNCTIONS (defined early to avoid nil references)
-- ============================================================

local function table_to_json(tbl)
  -- Check if json library is available (Lua 5.3+)
  if json and json.encode then
    return json.encode(tbl)
  end
  
  -- Fallback: manual JSON serialization
  local function encode_value(val)
    if type(val) == "string" then
      -- Properly escape JSON strings
      local escaped = val
        :gsub("\\", "\\\\")  -- Escape backslashes first
        :gsub('"', '\\"')    -- Escape quotes
        :gsub("\n", "\\n")   -- Escape newlines
        :gsub("\r", "\\r")   -- Escape carriage returns
        :gsub("\t", "\\t")   -- Escape tabs
      return '"' .. escaped .. '"'
    elseif type(val) == "number" then
      return tostring(val)
    elseif type(val) == "boolean" then
      return val and "true" or "false"
    elseif type(val) == "table" then
      return table_to_json(val)
    else
      return "null"
    end
  end
  
  local is_array = #tbl > 0
  local result = {}
  
  if is_array then
    local items = {}
    for _, v in ipairs(tbl) do
      table.insert(items, encode_value(v))
    end
    return "[" .. table.concat(items, ",") .. "]"
  else
    local items = {}
    for k, v in pairs(tbl) do
      table.insert(items, '"' .. k .. '":' .. encode_value(v))
    end
    return "{" .. table.concat(items, ",") .. "}"
  end
end

local function parse_json(json_str)
  -- Full recursive JSON parser with Unicode support
  if not json_str or json_str == "" then return nil end
  
  -- Decode Unicode escape sequences (\uXXXX)
  local function decode_unicode(str)
    if not str then return str end
    
    local original = str
    
    -- Decode \uXXXX sequences
    str = str:gsub("\\u(%x%x%x%x)", function(hex)
      local codepoint = tonumber(hex, 16)
      if codepoint < 128 then
        return string.char(codepoint)
      elseif codepoint < 2048 then
        return string.char(
          192 + math.floor(codepoint / 64),
          128 + (codepoint % 64)
        )
      elseif codepoint < 65536 then
        return string.char(
          224 + math.floor(codepoint / 4096),
          128 + (math.floor(codepoint / 64) % 64),
          128 + (codepoint % 64)
        )
      end
      return "?" -- Fallback for unsupported codepoints
    end)
    
    -- Decode other escape sequences
    str = str:gsub("\\(.)", {
      ["n"] = "\n",
      ["r"] = "\r",
      ["t"] = "\t",
      ["\\"] = "\\",
      ['"'] = '"',
      ["/"] = "/"
    })
    
    -- Debug log if string changed
    if str ~= original and #original < 100 then
      r.ShowConsoleMsg("[DEBUG] Decoded Unicode: '" .. original:sub(1, 50) .. "' -> '" .. str:sub(1, 50) .. "'\n")
    end
    
    return str
  end
  
  local function parse_value(str, pos)
    if not str then return nil, pos end
    while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n") do
      pos = pos + 1
    end
    
    if pos > #str then return nil, pos end
    
    local char = str:sub(pos, pos)
    
    if char == '"' then
      -- String
      local start = pos + 1
      while pos < #str do
        pos = pos + 1
        if str:sub(pos, pos) == '"' and str:sub(pos - 1, pos - 1) ~= "\\" then
          local raw_str = str:sub(start, pos - 1)
          local decoded_str = decode_unicode(raw_str)
          return decoded_str, pos + 1
        end
      end
    elseif char == '{' then
      -- Object
      local obj = {}
      pos = pos + 1
      while pos <= #str do
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n" or str:sub(pos, pos) == ",") do
          pos = pos + 1
        end
        if str:sub(pos, pos) == "}" then
          return obj, pos + 1
        end
        
        -- Parse key
        local key, new_pos = parse_value(str, pos)
        if not key or not new_pos then
          return obj, pos
        end
        pos = new_pos
        
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == ":") do
          pos = pos + 1
        end
        
        -- Parse value
        local value, new_pos2 = parse_value(str, pos)
        if not new_pos2 then
          return obj, pos
        end
        pos = new_pos2
        
        if key then
          obj[key] = value
        end
      end
      return obj, pos
    elseif char == '[' then
      -- Array
      local arr = {}
      pos = pos + 1
      local idx = 1
      while pos <= #str do
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n" or str:sub(pos, pos) == ",") do
          pos = pos + 1
        end
        if str:sub(pos, pos) == "]" then
          return arr, pos + 1
        end
        
        local value, new_pos = parse_value(str, pos)
        if not new_pos then
          return arr, pos
        end
        pos = new_pos
        if value ~= nil then
          arr[idx] = value
          idx = idx + 1
        end
      end
      return arr, pos
    else
      -- Number or boolean
      local start = pos
      while pos <= #str and str:sub(pos, pos):match("[0-9.e+-]") do
        pos = pos + 1
      end
      local num_str = str:sub(start, pos - 1)
      
      if num_str == "true" then return true, pos
      elseif num_str == "false" then return false, pos
      elseif num_str == "null" then return nil, pos
      else return tonumber(num_str), pos
      end
    end
  end
  
  local result, _ = parse_value(json_str, 1)
  return result
end

local function log_msg(msg)
  r.ShowConsoleMsg("[VO QC] " .. msg .. "\n")
end

-- ============================================================
-- STATE
-- ============================================================

local state = {
  -- UI
  selected_source = 1,  -- 1: Selected Items, 2: All Items
  script_text = "",
  script_file = "",
  output_csv_path = "",
  
  -- Language settings
  force_language = false,         -- Force specific language instead of auto-detect
  language_code = "auto",         -- Language code: auto, uk, ru, en, etc
  terminology_text = "",          -- Custom terminology/glossary for better recognition
  
  -- Model selection
  model_choice = 4,              -- 1=turbo, 2=base, 3=small, 4=medium, 5=large-v3 (default)
  model_names = {"turbo", "base", "small", "medium", "large-v3"},
  
  -- Detection flags
  detect_mismatches = true,
  detect_duplicates = true,
  detect_off_script = true,
  detect_missing = true,
  similarity_threshold = 0.85,
  duplicate_gap_threshold = 2.0,  -- Gap threshold for duplicate detection
  
  -- Output
  create_markers = true,
  color_items = true,
  export_csv = false,
  add_item_notes = true,      -- Add transcribed text to item notes
  create_regions = false,      -- Create regions with transcribed text (always per sentence)
  region_prefix = "VO: ",      -- Prefix for region names
  create_text_track = false,   -- Create track with text items (per sentence)
  
  -- Server status
  server_status = "UNKNOWN",
  server_message = "Checking...",
  
  -- Analysis state
  analyzing = false,
  analysis_progress = 0,
  analysis_message = "",
  analysis_results = nil,
  
  -- Async HTTP polling state
  http_waiting = false,
  http_response_file = nil,
  http_start_time = 0,
  http_last_checked = 0,
  http_last_size = nil,
  http_size_stable_count = 0,
  
  -- Items data
  items_data = {},
}

-- ============================================================
-- ADDITIONAL UTILITY FUNCTIONS
-- ============================================================

local function create_temp_dir()
  if not r.file_exists(CONFIG.temp_dir) then
    r.RecursiveCreateDirectory(CONFIG.temp_dir, 0)
  end
  return CONFIG.temp_dir
end

local function save_settings()
  -- Save settings to JSON file
  local settings_to_save = {
    script_file = state.script_file,
    output_csv_path = state.output_csv_path,
    force_language = state.force_language,
    language_code = state.language_code,
    terminology_text = state.terminology_text,
    model_choice = state.model_choice,
    detect_mismatches = state.detect_mismatches,
    detect_duplicates = state.detect_duplicates,
    detect_off_script = state.detect_off_script,
    detect_missing = state.detect_missing,
    similarity_threshold = state.similarity_threshold,
    duplicate_gap_threshold = state.duplicate_gap_threshold,
    create_markers = state.create_markers,
    color_items = state.color_items,
    export_csv = state.export_csv,
    add_item_notes = state.add_item_notes,
    create_regions = state.create_regions,
    region_prefix = state.region_prefix,
    create_text_track = state.create_text_track
  }
  
  -- Convert to JSON
  local json = table_to_json(settings_to_save)
  
  local f = io.open(CONFIG.settings_file, "w")
  if f then
    f:write(json)
    f:close()
    -- Silent save - no console spam
  else
    r.ShowConsoleMsg("[WARNING] Failed to save settings\n")
  end
end

local function load_settings()
  -- Load settings from JSON file
  if not r.file_exists(CONFIG.settings_file) then
    r.ShowConsoleMsg("[INFO] No saved settings found, using defaults\n")
    return
  end
  
  local f = io.open(CONFIG.settings_file, "r")
  if not f then
    r.ShowConsoleMsg("[WARNING] Failed to load settings\n")
    return
  end
  
  local json_str = f:read("*a")
  f:close()
  
  local settings = parse_json(json_str)
  if not settings then
    r.ShowConsoleMsg("[ERROR] Failed to parse settings JSON\n")
    return
  end
  
  -- Restore settings
  state.script_file = settings.script_file or state.script_file
  state.output_csv_path = settings.output_csv_path or state.output_csv_path
  state.force_language = settings.force_language or state.force_language
  state.language_code = settings.language_code or state.language_code
  state.terminology_text = settings.terminology_text or state.terminology_text
  state.model_choice = tonumber(settings.model_choice) or state.model_choice
  state.detect_mismatches = settings.detect_mismatches ~= false
  state.detect_duplicates = settings.detect_duplicates ~= false
  state.detect_off_script = settings.detect_off_script ~= false
  state.detect_missing = settings.detect_missing ~= false
  state.similarity_threshold = tonumber(settings.similarity_threshold) or state.similarity_threshold
  state.duplicate_gap_threshold = tonumber(settings.duplicate_gap_threshold) or state.duplicate_gap_threshold
  state.create_markers = settings.create_markers ~= false
  state.color_items = settings.color_items ~= false
  state.export_csv = settings.export_csv or state.export_csv
  state.add_item_notes = settings.add_item_notes ~= false
  state.create_regions = settings.create_regions or state.create_regions
  state.region_prefix = settings.region_prefix or state.region_prefix
  state.create_text_track = settings.create_text_track or state.create_text_track
  
  r.ShowConsoleMsg("[VO QC] ✓ Settings loaded from: " .. CONFIG.settings_file .. "\n")
end

local function export_audio_item(item, index)
  -- Export ACTUAL audio fragment from item using "Apply track FX to items"
  -- This correctly handles trimmed/offset items
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  
  if length <= 0 then
    return nil
  end
  
  r.ShowConsoleMsg("[VO QC] Processing item " .. index .. " (pos=" .. pos .. ", len=" .. length .. ")\n")
  
  -- Get active take
  local take = r.GetActiveTake(item)
  if not take then
    r.ShowConsoleMsg("[ERROR] Item " .. index .. " has no active take\n")
    return nil
  end
  
  -- Get source and check offset
  local source = r.GetMediaItemTake_Source(take)
  if not source then
    r.ShowConsoleMsg("[ERROR] Take has no source\n")
    return nil
  end
  
  local take_offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local take_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  
  r.ShowConsoleMsg("[DEBUG] Take offset: " .. take_offset .. "s, rate: " .. take_rate .. "\n")
  
  -- Build output path
  local output_file = CONFIG.temp_dir .. "/item_" .. index .. ".wav"
  
  -- Check if item is trimmed (has offset) or rate-changed
  local needs_render = (take_offset > 0.01) or (math.abs(take_rate - 1.0) > 0.01)
  
  if needs_render then
    r.ShowConsoleMsg("[INFO] Item has offset/rate change - will render to temp file\n")
    
    -- Save current selection
    local num_sel_items = r.CountSelectedMediaItems(0)
    local sel_items = {}
    for i = 0, num_sel_items - 1 do
      sel_items[i + 1] = r.GetSelectedMediaItem(0, i)
    end
    
    -- Select only this item
    r.Main_OnCommand(40289, 0) -- Unselect all items
    r.SetMediaItemSelected(item, true)
    r.UpdateArrange()
    
    -- Use "Apply track FX to items as new take (mono output)"
    -- This creates a new wav file with exact audio content
    r.Main_OnCommand(40361, 0) -- Apply track/take FX to items (mono output)
    
    -- Get the new take that was created
    local new_take = r.GetActiveTake(item)
    if new_take then
      local new_source = r.GetMediaItemTake_Source(new_take)
      if new_source then
        local rendered_file, _ = r.GetMediaSourceFileName(new_source, "")
        if rendered_file and rendered_file ~= "" and r.file_exists(rendered_file) then
          r.ShowConsoleMsg("[VO QC] ✓ Rendered to: " .. rendered_file .. "\n")
          
          -- Undo to restore original take
          r.Undo_DoUndo2(0)
          
          -- Restore selection
          r.Main_OnCommand(40289, 0)
          for i = 1, #sel_items do
            r.SetMediaItemSelected(sel_items[i], true)
          end
          r.UpdateArrange()
          
          return rendered_file
        end
      end
    end
    
    -- Restore selection if render failed
    r.Main_OnCommand(40289, 0)
    for i = 1, #sel_items do
      r.SetMediaItemSelected(sel_items[i], true)
    end
    r.UpdateArrange()
    
    r.ShowConsoleMsg("[WARNING] Render failed, falling back to source file\n")
  end
  
  -- Use source file directly (no trimming)
  local retval, _ = r.GetMediaSourceFileName(source, "")
  if retval and retval ~= "" and r.file_exists(retval) then
    r.ShowConsoleMsg("[VO QC] Using source file: " .. retval .. "\n")
    return retval
  end
  
  r.ShowConsoleMsg("[ERROR] Could not get audio for item " .. index .. "\n")
  return nil
end

local function http_post_json_async(url, json_data)
  -- ASYNC HTTP POST: Launch curl in TRUE background, return immediately
  -- Use batch file to launch curl without blocking Lua
  
  local temp_json = CONFIG.temp_dir .. "/request.json"
  local temp_response = CONFIG.temp_dir .. "/response.json"
  local batch_file = CONFIG.temp_dir .. "/curl_async.bat"
  
  -- Convert Lua paths (using /) to Windows batch paths (using \)
  local function lua_path_to_batch(lua_path)
    return lua_path:gsub("/", "\\")
  end
  
  local batch_json = lua_path_to_batch(temp_json)
  local batch_response = lua_path_to_batch(temp_response)
  local batch_file_path = lua_path_to_batch(batch_file)
  
  -- Clean old response
  if r.file_exists(temp_response) then os.remove(temp_response) end
  
  -- Write JSON request to file (MUST be written before running batch!)
  local f = io.open(temp_json, "w")
  if not f then 
    r.ShowConsoleMsg("[ERROR] Failed to create temp JSON file\n")
    return nil
  end
  f:write(json_data)
  f:close()
  r.ShowConsoleMsg("[DEBUG] Wrote JSON to: " .. temp_json .. "\n")
  
  -- Create batch file that runs curl in background
  -- IMPORTANT: All paths use Windows backslashes in the batch file
  local batch_content = string.format(
    '@echo off\n' ..
    'setlocal enabledelayedexpansion\n' ..
    'curl -s -X POST --max-time %d "%s" -H "Content-Type: application/json" -d @"%s" -o "%s" 2>nul\n' ..
    'exit /b 0\n',
    CONFIG.server_timeout,
    url,
    batch_json,  -- Use Windows path here
    batch_response  -- Use Windows path here
  )
  
  local bf = io.open(batch_file, "w")
  if not bf then
    r.ShowConsoleMsg("[ERROR] Failed to create batch file\n")
    return nil
  end
  bf:write(batch_content)
  bf:close()
  r.ShowConsoleMsg("[DEBUG] Wrote batch to: " .. batch_file .. "\n")
  
  -- Launch batch file in TRUE background (cmd /C start returns immediately)
  local launch_cmd = string.format('cmd.exe /C start "" "%s"', batch_file_path)
  r.ShowConsoleMsg("[DEBUG] Launching batch: " .. batch_file_path .. "\n")
  os.execute(launch_cmd)
  
  r.ShowConsoleMsg("[INFO] ✓ Request sent to background\n")
  r.ShowConsoleMsg("[WAIT] curl is processing (will poll for response)\n")
  
  return temp_response  -- Return path to check (Lua format)
end

local function parse_json(json_str)
  -- Full recursive JSON parser with Unicode support
  if not json_str or json_str == "" then return nil end
  
  -- Decode Unicode escape sequences (\uXXXX)
  local function decode_unicode(str)
    if not str then return str end
    
    local original = str
    
    -- Decode \uXXXX sequences
    str = str:gsub("\\u(%x%x%x%x)", function(hex)
      local codepoint = tonumber(hex, 16)
      if codepoint < 128 then
        return string.char(codepoint)
      elseif codepoint < 2048 then
        return string.char(
          192 + math.floor(codepoint / 64),
          128 + (codepoint % 64)
        )
      elseif codepoint < 65536 then
        return string.char(
          224 + math.floor(codepoint / 4096),
          128 + (math.floor(codepoint / 64) % 64),
          128 + (codepoint % 64)
        )
      end
      return "?" -- Fallback for unsupported codepoints
    end)
    
    -- Decode other escape sequences
    str = str:gsub("\\(.)", {
      ["n"] = "\n",
      ["r"] = "\r",
      ["t"] = "\t",
      ["\\"] = "\\",
      ['"'] = '"',
      ["/"] = "/"
    })
    
    -- Debug log if string changed
    if str ~= original and #original < 100 then
      r.ShowConsoleMsg("[DEBUG] Decoded Unicode: '" .. original:sub(1, 50) .. "' -> '" .. str:sub(1, 50) .. "'\n")
    end
    
    return str
  end
  
  local function parse_value(str, pos)
    if not str then return nil, pos end
    while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n") do
      pos = pos + 1
    end
    
    if pos > #str then return nil, pos end
    
    local char = str:sub(pos, pos)
    
    if char == '"' then
      -- String
      local start = pos + 1
      while pos < #str do
        pos = pos + 1
        if str:sub(pos, pos) == '"' and str:sub(pos - 1, pos - 1) ~= "\\" then
          local raw_str = str:sub(start, pos - 1)
          local decoded_str = decode_unicode(raw_str)
          return decoded_str, pos + 1
        end
      end
    elseif char == '{' then
      -- Object
      local obj = {}
      pos = pos + 1
      while pos <= #str do
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n" or str:sub(pos, pos) == ",") do
          pos = pos + 1
        end
        if str:sub(pos, pos) == "}" then
          return obj, pos + 1
        end
        
        -- Parse key
        local key, new_pos = parse_value(str, pos)
        if not key or not new_pos then
          return obj, pos
        end
        pos = new_pos
        
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == ":") do
          pos = pos + 1
        end
        
        -- Parse value
        local value, new_pos2 = parse_value(str, pos)
        if not new_pos2 then
          return obj, pos
        end
        pos = new_pos2
        
        if key then
          obj[key] = value
        end
      end
      return obj, pos
    elseif char == '[' then
      -- Array
      local arr = {}
      pos = pos + 1
      local idx = 1
      while pos <= #str do
        while pos <= #str and (str:sub(pos, pos) == " " or str:sub(pos, pos) == "\n" or str:sub(pos, pos) == ",") do
          pos = pos + 1
        end
        if str:sub(pos, pos) == "]" then
          return arr, pos + 1
        end
        
        local value, new_pos = parse_value(str, pos)
        if not new_pos then
          return arr, pos
        end
        pos = new_pos
        if value ~= nil then
          arr[idx] = value
          idx = idx + 1
        end
      end
      return arr, pos
    else
      -- Number or boolean
      local start = pos
      while pos <= #str and str:sub(pos, pos):match("[0-9.e+-]") do
        pos = pos + 1
      end
      local num_str = str:sub(start, pos - 1)
      
      if num_str == "true" then return true, pos
      elseif num_str == "false" then return false, pos
      elseif num_str == "null" then return nil, pos
      else return tonumber(num_str), pos
      end
    end
  end
  
  local result, _ = parse_value(json_str, 1)
  return result
end
local function check_server_health()
  -- Check if server is running
  if not ctx then return false end
  
  local health_url = CONFIG.server_url .. "/health"
  
  -- Try curl with timeout
  local cmd = 'curl -s --connect-timeout 2 "' .. health_url .. '" 2>nul'
  local handle = io.popen(cmd)
  if not handle then
    state.server_status = "DISCONNECTED"
    state.server_message = "curl not found or error"
    r.ShowConsoleMsg("ERROR: check_server_health - cannot execute curl\n")
    return false
  end
  
  local response = handle:read("*a")
  handle:close()
  
  if response and response ~= "" then
    -- Debug: show raw response
    r.ShowConsoleMsg("Server health response: " .. response .. "\n")
    
    local data = parse_json(response)
    if data then
      if not data.status then
        data.status = response:match('"status"%s*:%s*"([^"]+)"')
      end
      
      r.ShowConsoleMsg("Parsed data - status: " .. tostring(data.status) .. ", model: " .. tostring(data.model) .. "\n")
      
      -- Check different response formats
      if data.status == "ok" or data.status == "success" then
        state.server_status = "OK"
        state.server_message = "Connected - Model: " .. (data.model or "?")
        return true
      end
    else
      r.ShowConsoleMsg("ERROR: Failed to parse JSON response\n")
    end
  else
    r.ShowConsoleMsg("ERROR: Empty response from server\n")
  end
  
  state.server_status = "DISCONNECTED"
  state.server_message = "Server not responding"
  return false
end

local function collect_items_data()
  state.items_data = {}
  
  local count = 0
  if state.selected_source == 1 then
    count = r.CountSelectedMediaItems(0)
  else
    count = r.CountMediaItems(0)
  end
  
  r.ShowConsoleMsg("[DEBUG] Collecting items (selected_source=" .. state.selected_source .. ", count=" .. count .. ")\n")
  
  for i = 0, count - 1 do
    local item
    if state.selected_source == 1 then
      item = r.GetSelectedMediaItem(0, i)
    else
      item = r.GetMediaItem(0, i)
    end
    
    if item then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
      
      r.ShowConsoleMsg("[DEBUG] Item " .. i .. ": pos=" .. pos .. ", len=" .. len .. ", guid=" .. (guid or "?") .. "\n")
      
      table.insert(state.items_data, {
        item = item,
        guid = guid or "",
        index = i,
        position = pos,
        length = len,
        audio_path = nil
      })
    end
  end
  
  r.ShowConsoleMsg("[DEBUG] Collected " .. #state.items_data .. " items total\n")
  return #state.items_data
end

local function split_into_sentences(text)
  -- Split text into sentences by punctuation (.!?)
  -- CRITICAL: This ensures proper alignment with Whisper transcription output
  if not text or text == "" then return {} end
  
  -- Normalize: collapse newlines/multi-space
  text = text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  
  local sentences = {}
  local current = ""
  
  for char in text:gmatch(".") do
    current = current .. char
    -- Check if current ends with sentence-ending punctuation
    if char:match("[.!?]") then
      -- Found sentence end, save it
      current = current:gsub("^%s+", ""):gsub("%s+$", "")
      if current ~= "" then
        table.insert(sentences, current)
      end
      current = ""
    end
  end
  
  -- Handle remaining text (no ending punctuation)
  current = current:gsub("^%s+", ""):gsub("%s+$", "")
  if current ~= "" then
    table.insert(sentences, current)
  end
  
  return sentences
end

local function build_analysis_request()
  -- Build JSON request for server
  local audio_files = {}
  local script_sentences = {}
  
  -- Split script into SENTENCES (not lines) for proper alignment with Whisper
  -- CRITICAL: Ensures sentence count matches between script and transcription
  script_sentences = split_into_sentences(state.script_text)
  
  r.ShowConsoleMsg("[DEBUG] Building request with " .. #script_sentences .. " script sentences\n")
  
  -- Export audio files
  for idx, item_data in ipairs(state.items_data) do
    r.ShowConsoleMsg("[DEBUG] Processing item " .. idx .. "...\n")
    local audio_path = export_audio_item(item_data.item, idx)
    
    if audio_path then
      item_data.audio_path = audio_path
      
      -- KEEP WINDOWS PATHS WITH BACKSLASHES for Python
      -- Python on Windows needs C:\Path\To\File, not C:/Path/To/File
      -- JSON will properly escape them as "C:\\Path\\To\\File"
      local json_path = audio_path  -- Use as-is with backslashes
      
      table.insert(audio_files, {
        path = json_path,
        guid = item_data.guid,
        index = idx - 1  -- 0-based for server
      })
      
      r.ShowConsoleMsg("[DEBUG] Added audio file: " .. json_path .. "\n")
    else
      r.ShowConsoleMsg("[WARNING] Skipped item " .. idx .. " (could not get audio file)\n")
    end
  end
  
  r.ShowConsoleMsg("[DEBUG] Total audio files: " .. #audio_files .. "\n")
  
  -- Check for duplicate source files (multiple items using same wav file)
  local source_count = {}
  for _, af in ipairs(audio_files) do
    local path = af.path:lower() -- Case-insensitive comparison
    source_count[path] = (source_count[path] or 0) + 1
  end
  
  local has_duplicates = false
  for path, count in pairs(source_count) do
    if count > 1 then
      has_duplicates = true
      r.ShowConsoleMsg("[WARNING] Source file used by " .. count .. " items: " .. path .. "\n")
      r.ShowConsoleMsg("[WARNING] These items will have IDENTICAL analysis results!\n")
      r.ShowConsoleMsg("[INFO] Consider using 'Apply track FX to items' to create unique renders.\n")
    end
  end
  
  if has_duplicates then
    r.ShowConsoleMsg("[NOTICE] Multiple items share source files - results may not be unique per item.\n")
  end
  
  -- Build request object
  local request = {
    audio_files = audio_files,
    script_sentences = script_sentences,
    language = state.force_language and state.language_code or nil,  -- nil will trigger auto-detect on server
    model = state.model_names[state.model_choice],  -- Pass selected model name to server
    terminology = state.terminology_text ~= "" and state.terminology_text or nil,
    detection_flags = {
      mismatches = state.detect_mismatches,
      duplicates = state.detect_duplicates,
      off_script = state.detect_off_script,
      missing = state.detect_missing
    },
    duplicate_gap_threshold = state.duplicate_gap_threshold,
    similarity_threshold = state.similarity_threshold
  }
  
  return request
end

local apply_analysis_results

local function analyze_selected_items()
  -- First, collect items before analysis
  r.ShowConsoleMsg("[VO QC] Collecting items before analysis...\n")
  collect_items_data()
  
  if #state.items_data == 0 then
    r.ShowConsoleMsg("[ERROR] No items collected\n")
    r.ShowMessageBox("No items to analyze", "Error", 0)
    return
  end
  
  r.ShowConsoleMsg("[VO QC] Found " .. #state.items_data .. " items to analyze\n")
  
  if state.script_text == "" then
    r.ShowMessageBox("Please load script text first", "Error", 0)
    return
  end
  
  -- Calculate estimated processing time
  local total_duration = 0
  for _, item_data in ipairs(state.items_data) do
    total_duration = total_duration + item_data.length
  end
  local estimated_min = math.ceil(total_duration * 0.8 / 60)  -- ~0.8x realtime on GPU
  
  -- CRITICAL WARNING: Inform user about UI freeze during processing
  local warning_msg = string.format(
    "⚠️ IMPORTANT: Analysis will take ~%d minute(s)\n\n" ..
    "During Whisper processing, Reaper UI will appear FROZEN.\n" ..
    "This is NORMAL - the script is working in background.\n\n" ..
    "✓ Do NOT close Reaper or kill the process\n" ..
    "✓ Just wait patiently for completion\n" ..
    "✓ Watch ReaScript console for progress updates\n\n" ..
    "Items to analyze: %d\n" ..
    "Total audio duration: %.1f seconds\n\n" ..
    "Click OK to start (or Cancel to abort)",
    estimated_min,
    #state.items_data,
    total_duration
  )
  
  local user_response = r.ShowMessageBox(warning_msg, "VO QC - Confirm Analysis", 1)
  if user_response ~= 1 then
    r.ShowConsoleMsg("[INFO] Analysis cancelled by user\n")
    return
  end
  
  state.analyzing = true
  state.analysis_message = "Preparing audio files..."
  r.ShowConsoleMsg("[VO QC] Starting analysis...\n")
  r.ShowConsoleMsg("[INFO] User confirmed - proceeding with analysis\n")
  
  local request = build_analysis_request()
  r.ShowConsoleMsg("[VO QC] Request object built with " .. #state.items_data .. " items\n")
  
  local json_str = table_to_json(request)
  r.ShowConsoleMsg("[VO QC] JSON created, length: " .. #json_str .. " bytes\n")
  
  state.analysis_message = "Sending to server..."
  
  -- Send request
  local url = CONFIG.server_url .. "/analyze"
  r.ShowConsoleMsg("[VO QC] Sending request to: " .. url .. "\n")
  r.ShowConsoleMsg("[VO QC] ⏳ Whisper processing started (this will freeze UI - please wait)...\n")
  r.ShowConsoleMsg("[INFO] Estimated time: " .. estimated_min .. " minute(s)\n")
  
  state.analysis_message = string.format("Processing audio (est. %d min)...", estimated_min)
  
  -- LAUNCH ASYNC HTTP REQUEST
  -- This returns immediately, polling happens in main defer loop
  local response_file = http_post_json_async(url, json_str)
  
  if not response_file then
    state.analyzing = false
    state.analysis_message = "Failed to send request"
    r.ShowConsoleMsg("[ERROR] Failed to send request to server\n")
    r.ShowMessageBox("Failed to send analysis request to server.", "Error", 0)
    return
  end
  
  -- Set state to polling
  state.http_waiting = true
  state.http_response_file = response_file
  state.http_start_time = os.time()
  state.http_last_checked = state.http_start_time
  
  r.ShowConsoleMsg("[INFO] ✓ Polling file: " .. response_file .. "\n")
  -- Function will return - polling happens in main loop via check_http_response()
  return
end

apply_analysis_results = function()
  if not state.analysis_results then
    r.ShowConsoleMsg("[ERROR] No analysis_results in state\n")
    r.ShowMessageBox("No analysis results", "Error", 0)
    return
  end
  
  r.ShowConsoleMsg("[VO QC] apply_analysis_results() called\n")
  r.ShowConsoleMsg("[DEBUG] state.analysis_results type: " .. type(state.analysis_results) .. "\n")
  
  -- Show what's in the results object
  local results_table = state.analysis_results
  if type(results_table) == "table" then
    for k, v in pairs(results_table) do
      if k == "results" and type(v) == "table" then
        r.ShowConsoleMsg("[DEBUG] - Found 'results' array with " .. #v .. " items\n")
      else
        r.ShowConsoleMsg("[DEBUG] - Found field '" .. k .. "' = " .. tostring(v) .. "\n")
      end
    end
  end
  
  r.Undo_BeginBlock()
  
  local results = state.analysis_results.results or {}
  r.ShowConsoleMsg("[VO QC] Processing " .. #results .. " results from server\n")
  
  for idx, result in ipairs(results) do
    r.ShowConsoleMsg("[VO QC] Applying result " .. idx .. ": guid=" .. (result.guid or "?") .. ", type=" .. (result.error_type or "?") .. "\n")
    
    local item_data = state.items_data[idx]
    if not item_data then 
      r.ShowConsoleMsg("[WARNING] No item_data for result " .. idx .. "\n")
      break 
    end
    
    r.ShowConsoleMsg("[DEBUG] Got item_data for result " .. idx .. "\n")
    local item = item_data.item
    local error_type = result.error_type or "NONE"
    
    -- Set item color
    if state.color_items then
      r.ShowConsoleMsg("[DEBUG] Coloring items is enabled\n")
      local color = 0
      if error_type == "MISMATCH" then
        color = 0xFF6B6BFF  -- Red
      elseif error_type == "DUPLICATE" then
        color = 0xFFD93DFF  -- Yellow
      elseif error_type == "MINOR_DIFF" then
        color = 0xFF9F43FF  -- Orange
      end
      
      if color ~= 0 then
        r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
        r.ShowConsoleMsg("[VO QC] ✓ Colored item " .. idx .. " with color " .. string.format("0x%X\n", color))
      end
    end
    
    r.ShowConsoleMsg("[DEBUG] Finished processing result " .. idx .. "\n")
  end
  
  -- Add transcribed text to item notes
  if state.add_item_notes then
    r.ShowConsoleMsg("[DEBUG] Adding transcribed text to item notes...\n")
    for idx, result in ipairs(results) do
      local item_data = state.items_data[idx]
      if not item_data then break end
      
      local item = item_data.item
      local transcribed = result.transcribed_text or ""
      r.ShowConsoleMsg("[DEBUG] Item " .. idx .. " transcribed text: '" .. (transcribed or "nil") .. "'\n")
      r.ShowConsoleMsg("[DEBUG] Transcribed length: " .. #transcribed .. " chars\n")
      
      if transcribed ~= "" then
        local take = r.GetActiveTake(item)
        if take then
          -- Get existing notes
          local _, existing_notes = r.GetSetMediaItemTakeInfo_String(take, "P_NOTES", "", false)
          
          -- Append transcribed text
          local new_notes = existing_notes
          if existing_notes ~= "" then
            new_notes = existing_notes .. "\n\n--- TRANSCRIBED ---\n" .. transcribed
          else
            new_notes = "--- TRANSCRIBED ---\n" .. transcribed
          end
          
          r.GetSetMediaItemTakeInfo_String(take, "P_NOTES", new_notes, true)
          r.ShowConsoleMsg("[VO QC] ✓ Added transcribed text to item " .. idx .. " notes\n")
        else
          r.ShowConsoleMsg("[WARNING] Item " .. idx .. " has no active take\n")
        end
      else
        r.ShowConsoleMsg("[DEBUG] Item " .. idx .. " has empty transcribed text\n")
      end
    end
  end
  
  -- Create regions with transcribed text (always per sentence)
  if state.create_regions then
    r.ShowConsoleMsg("[DEBUG] Creating regions with sentence text...\n")
    for idx, result in ipairs(results) do
      local item_data = state.items_data[idx]
      if not item_data then break end
      
      local item = item_data.item
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      
      -- Check if we have sentence alignments
      local sentence_alignments = result.sentence_alignments
      
      if sentence_alignments and #sentence_alignments > 0 then
        -- Create region for EACH sentence
        local sentence_count = #sentence_alignments
        local total_chars = 0
        for _, alignment in ipairs(sentence_alignments) do
          local t = alignment.transcribed or ""
          total_chars = total_chars + math.max(1, #t)
        end
        if total_chars <= 0 then total_chars = sentence_count end
        
        local cursor = pos
        for sent_idx, alignment in ipairs(sentence_alignments) do
          local sent_text = alignment.transcribed or ""
          local weight = math.max(1, #sent_text)
          local sent_len = len * (weight / total_chars)
          local sent_start = cursor
          local sent_end = cursor + sent_len
          cursor = sent_end
          
          if sent_text ~= "" then
            -- Build region name - full text always
            local region_name = state.region_prefix .. sent_text
            
            -- Color based on sentence status
            local region_color = 0x00FF00FF -- Green for match
            if alignment.status == "mismatch" then
              region_color = 0xFF6B6BFF  -- Red
            elseif alignment.status == "minor_diff" then
              region_color = 0xFF9F43FF  -- Orange
            end
            
            r.AddProjectMarker2(0, true, sent_start, sent_end, region_name, -1, region_color)
          end
        end
      end
    end
  end
  
  if state.create_markers then
    r.ShowConsoleMsg("[DEBUG] Creating markers...\n")
    for idx, result in ipairs(results) do
      local item_data = state.items_data[idx]
      if not item_data then break end
      
      local item = item_data.item
      local error_type = result.error_type or "NONE"
      
      if error_type ~= "NONE" then
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        local marker_name = error_type
        if result.issues and result.issues[1] then
          local desc = result.issues[1].note or result.issues[1].description or ""
          if desc ~= "" then
            marker_name = marker_name .. ": " .. desc:sub(1, 40)
          end
        end
        
        r.AddProjectMarker2(0, false, pos + len, pos + len, marker_name, -1, 0xFF6B6BFF)
        r.ShowConsoleMsg("[VO QC] ✓ Added marker at position " .. pos + len .. "\n")
      end
    end
  end
  
  if state.export_csv and state.output_csv_path ~= "" then
    r.ShowConsoleMsg("[DEBUG] Exporting professional CSV report to: " .. state.output_csv_path .. "\n")
    
    -- Helper function to escape CSV fields
    local function escape_csv(str)
      if not str then return "" end
      -- Replace quotes with double quotes and wrap in quotes if needed
      str = tostring(str):gsub('"', '""')
      if str:match('[,"\n\r]') then
        return '"' .. str .. '"'
      end
      return str
    end
    
    -- Start with UTF-8 BOM for proper Excel display
    local csv = "\239\187\191"  -- UTF-8 BOM
    
    -- Header with timings and duplicate tracking
    csv = csv .. "Item,GUID,Filename,Start_Time,End_Time,Duration,Language,Overall_Status,Overall_Similarity,Sentence#,Script_Sentence,Transcribed_Sentence,Sent_Similarity,Sent_Status,Duplicate_Of,Difference\n"
    
    for idx, result in ipairs(results) do
      local sentence_alignments = result.sentence_alignments
      local detected_lang = result.detected_language or "auto"
      local item_data = state.items_data[idx]
      local pos = item_data and r.GetMediaItemInfo_Value(item_data.item, "D_POSITION") or 0
      local len = item_data and r.GetMediaItemInfo_Value(item_data.item, "D_LENGTH") or 0
      local duplicate_of = result.duplicate_of or ""
      
      -- Format timings
      local function format_time(sec)
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        local s = sec % 60
        return string.format("%02d:%02d:%06.3f", h, m, s)
      end
      
      if sentence_alignments and #sentence_alignments > 0 then
        -- Export sentence-by-sentence comparison with PRECISE WHISPER TIMESTAMPS
        for sent_idx, alignment in ipairs(sentence_alignments) do
          local script_sent = alignment.script or ""
          local trans_sent = alignment.transcribed or ""
          local sent_similarity = alignment.similarity or 0
          local sent_status = alignment.status or "unknown"
          
          -- CRITICAL FIX: Use precise Whisper segment timestamps instead of proportional estimation
          -- This fixes 10-second desync issue reported by user
          local sent_start_time = alignment.start_time or pos  -- Fallback to item position
          local sent_end_time = alignment.end_time or (pos + len)
          local sent_duration = alignment.duration or len
          
          -- Check for duplicate info (internal duplicates within same audio)
          local dup_info = alignment.duplicate_info
          local sent_duplicate_note = ""
          if dup_info and dup_info.is_duplicate then
            sent_duplicate_note = string.format("Sentence %d", dup_info.reference_sentence)
          end
          
          -- Calculate difference
          local diff = ""
          if script_sent ~= trans_sent then
            if script_sent == "" then
              diff = "[OFF-SCRIPT]"
            elseif trans_sent == "" then
              diff = "[MISSING]"
            else
              diff = string.format("[%.0f%% match]", sent_similarity * 100)
            end
          end
          
          -- Add duplicate note to diff if present
          if sent_duplicate_note ~= "" then
            diff = diff .. (diff ~= "" and " " or "") .. "[DUPLICATE of " .. sent_duplicate_note .. "]"
          end
          
          local line = string.format('%d,%s,%s,%s,%s,%.3f,%s,%s,%.3f,%d,%s,%s,%.3f,%s,%s,%s\n',
            idx,
            escape_csv(result.guid or ""),
            escape_csv(result.filename or ""),
            format_time(sent_start_time),  -- Whisper timestamp, not estimated!
            format_time(sent_end_time),    -- Whisper timestamp, not estimated!
            sent_duration,                 -- Whisper duration, not estimated!
            escape_csv(detected_lang),
            escape_csv(result.error_type or "OK"),
            result.similarity or 0,
            sent_idx,
            escape_csv(script_sent),
            escape_csv(trans_sent),
            sent_similarity,
            escape_csv(sent_status),
            escape_csv(duplicate_of),
            escape_csv(diff)
          )
          csv = csv .. line
        end
      else
        -- Fallback: export as single item
        local line = string.format('%d,%s,%s,%s,%s,%.3f,%s,%s,%.3f,1,%s,%s,%.3f,%s,%s,%s\n',
          idx,
          escape_csv(result.guid or ""),
          escape_csv(result.filename or ""),
          format_time(pos),
          format_time(pos + len),
          len,
          escape_csv(detected_lang),
          escape_csv(result.error_type or "OK"),
          result.similarity or 0,
          escape_csv(result.script_text or ""),
          escape_csv(result.transcribed_text or ""),
          result.similarity or 0,
          escape_csv(result.error_type or "OK"),
          escape_csv(duplicate_of),
          ""
        )
        csv = csv .. line
      end
    end
    
    local f = io.open(state.output_csv_path, "wb")  -- Binary mode for UTF-8 BOM
    if f then
      f:write(csv)
      f:close()
      log_msg("Professional CSV report exported: " .. state.output_csv_path)
      r.ShowConsoleMsg("[DEBUG] CSV file written with sentence-level analysis\n")
    else
      r.ShowConsoleMsg("[ERROR] Failed to open CSV file for writing\n")
    end
  end
  
  if state.create_text_track then
    r.ShowConsoleMsg("[DEBUG] Creating text track with sentence items...\n")
    
    -- Get last track or create new one
    local track_count = r.CountTracks(0)
    local text_track
    
    if track_count == 0 then
      r.InsertTrackAtIndex(0, false)
      text_track = r.GetTrack(0, 0)
    else
      r.InsertTrackAtIndex(track_count, false)
      text_track = r.GetTrack(0, track_count)
    end
    
    if not text_track then
      r.ShowConsoleMsg("[ERROR] Failed to create text track\n")
    else
      -- Set track name
      r.GetSetMediaTrackInfo_String(text_track, "P_NAME", "[VO QC] Transcribed Text", true)
      
      local total_items_created = 0
      
      -- Create separate items for EACH SENTENCE
      for idx, result in ipairs(results) do
        local item_data = state.items_data[idx]
        if not item_data then break end
        
        local item = item_data.item
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        
        -- Check if we have sentence alignments
        local sentence_alignments = result.sentence_alignments
        
        if sentence_alignments and #sentence_alignments > 0 then
          -- CRITICAL FIX: Use precise Whisper timestamps for text items
          for sent_idx, alignment in ipairs(sentence_alignments) do
            local sent_text = alignment.transcribed or ""
            
            -- Use Whisper segment timestamps (absolute time, not item-relative)
            local sent_start = alignment.start_time or pos
            local sent_duration = alignment.duration or 0
            
            if sent_text ~= "" and sent_duration > 0 then
              -- Create item for this sentence with EXACT Whisper timing
              local new_item = r.AddMediaItemToTrack(text_track)
              r.SetMediaItemInfo_Value(new_item, "D_POSITION", sent_start)
              r.SetMediaItemInfo_Value(new_item, "D_LENGTH", sent_duration)
              
              -- Add transcribed text to item notes
              r.GetSetMediaItemInfo_String(new_item, "P_NOTES", sent_text, true)
              
              total_items_created = total_items_created + 1
            end
          end
        end
      end
      
      log_msg("✓ Created text track with " .. total_items_created .. " sentence items")
    end
  end
  
  r.Undo_EndBlock("VO QC Analysis", -1)
  r.UpdateArrange()
  
  log_msg("✓ Applied " .. (#results) .. " analysis results to timeline")
end

-- ============================================================
-- GUI RENDERING
-- ============================================================

local function set_modern_theme()
  if not ctx then return end
  
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLOR.bg_dark)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLOR.bg_dark)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLOR.bg_lighter)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x353535FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLOR.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLOR.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLOR.accent_lite)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLOR.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLOR.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), COLOR.text_dim)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLOR.bg_lighter)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLOR.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLOR.accent_lite)
  
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 16, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 10, 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
end

local function draw_section_header(name)
  r.ImGui_TextColored(ctx, COLOR.header, name)
  r.ImGui_Separator(ctx)
  r.ImGui_Spacing(ctx)
end

local function draw_server_status()
  r.ImGui_Text(ctx, "Server Status:")
  r.ImGui_SameLine(ctx)
  
  local color = COLOR.error_red
  if state.server_status == "OK" then
    color = COLOR.ok_green
  elseif state.server_status == "DISCONNECTED" then
    color = COLOR.warn_yellow
  end
  
  r.ImGui_TextColored(ctx, color, "● " .. state.server_status)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextDisabled(ctx, "(" .. state.server_message .. ")")
  
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Refresh", 80, 0) then
    check_server_health()
  end
  r.ImGui_Spacing(ctx)
end

local function draw_source_selection()
  draw_section_header("SOURCE")
  
  local old_source = state.selected_source
  
  if r.ImGui_RadioButton(ctx, "Selected Items", state.selected_source == 1) then
    state.selected_source = 1
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "All Items", state.selected_source == 2) then
    state.selected_source = 2
  end
  
  -- Only collect items when source changes
  if old_source ~= state.selected_source then
    collect_items_data()
  end
  
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Refresh Items", 90, 0) then
    collect_items_data()
  end
  
  r.ImGui_TextDisabled(ctx, string.format("(%d items available)", #state.items_data))
  r.ImGui_Spacing(ctx)
end

local function draw_script_section()
  draw_section_header("SCRIPT TEXT")
  
  r.ImGui_Text(ctx, "Script File Path:")
  
  -- Display current file path with inline status
  if state.script_file ~= "" then
    local file_exists = r.file_exists(state.script_file:gsub("/", "\\"))
    local status_color = file_exists and 0x00FF00FF or 0xFF0000FF  -- Green if exists, Red if missing
    r.ImGui_TextColored(ctx, status_color, state.script_file)
    if not file_exists then
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, "(⚠ FILE NOT FOUND)")
    end
  else
    r.ImGui_TextDisabled(ctx, "(no file selected)")
  end
  
  -- Browse button (as it's done for terminology and CSV files)
  if r.ImGui_Button(ctx, "📂 Browse", 100, 0) then
    local retval, file = r.JS_Dialog_BrowseForOpenFiles("Select Script File", "", "", "txt\0", false)
    if retval and retval ~= 0 and file ~= "" then
      state.script_file = file
      local f = io.open(file, "r")
      if f then
        state.script_text = f:read("*a")
        f:close()
        save_settings()
        r.ShowConsoleMsg("[VO QC] ✓ Loaded: " .. file .. "\n")
      else
        r.ShowConsoleMsg("[ERROR] Could not read file: " .. file .. "\n")
        state.script_file = ""
      end
    end
  end
  
  -- Manual path input
  r.ImGui_SameLine(ctx)
  local changed = false
  changed, state.script_file = r.ImGui_InputText(ctx, "##script_path", state.script_file, 1024)
  
  -- Load button
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Load", 50, 0) then
    if state.script_file ~= "" then
      -- Normalize path - convert backslashes to forward slashes and trim
      local normalized_path = state.script_file:gsub("\\", "/"):match("^%s*(.-)%s*$")
      
      -- Check if it's a folder
      local is_folder = false
      if normalized_path then
        -- Check if path ends with separator
        if normalized_path:sub(-1) == "/" then
          is_folder = true
        else
          -- Check if the file exists; if not, try to treat as folder
          if not r.file_exists(normalized_path) and r.file_exists(normalized_path .. "/") then
            is_folder = true
            normalized_path = normalized_path .. "/"
          end
        end
      end
      
      if is_folder then
        r.ShowConsoleMsg("[VO QC] Searching for .txt files in: " .. normalized_path .. "\n")
        -- Try to find .txt file in the folder
        local found_file = nil
        local search_dir = normalized_path:gsub("/", "\\")
        
        -- Create a temporary search script
        local temp_script = CONFIG.temp_dir .. "/find_txt.bat"
        local f = io.open(temp_script, "w")
        if f then
          f:write("@echo off\n")
          f:write("for /f \"delims=\" %%a in ('dir /b \"" .. search_dir .. "*.txt\" 2^>nul') do (\n")
          f:write("  echo %%a\n")
          f:write("  exit /b 0\n")
          f:write(")\n")
          f:close()
          
          local handle = io.popen(temp_script)
          if handle then
            found_file = handle:read("*l"):match("^%s*(.-)%s*$") or nil
            handle:close()
          end
          os.remove(temp_script)
        end
        
        if found_file then
          local full_path = normalized_path .. found_file
          if r.file_exists(full_path) then
            local script_f = io.open(full_path, "r")
            if script_f then
              state.script_text = script_f:read("*a")
              script_f:close()
              state.script_file = full_path
              r.ShowConsoleMsg("[VO QC] ✓ Found and loaded: " .. full_path .. "\n")
            else
              r.ShowConsoleMsg("[ERROR] Could not read file: " .. full_path .. "\n")
            end
          end
        else
          r.ShowConsoleMsg("[ERROR] No .txt files found in folder: " .. normalized_path .. "\n")
          r.ShowConsoleMsg("[VO QC] Please enter full path to a .txt file\n")
        end
      elseif r.file_exists(normalized_path) then
        local f = io.open(normalized_path, "r")
        if f then
          state.script_text = f:read("*a")
          f:close()
          state.script_file = normalized_path
          r.ShowConsoleMsg("[VO QC] ✓ Loaded: " .. normalized_path .. "\n")
        else
          r.ShowConsoleMsg("[ERROR] Could not read file: " .. normalized_path .. "\n")
        end
      else
        r.ShowConsoleMsg("[ERROR] File not found: " .. normalized_path .. "\n")
        r.ShowConsoleMsg("[VO QC] Tips:\n")
        r.ShowConsoleMsg("  - Check if path is correct (copy full path from Windows Explorer)\n")
        r.ShowConsoleMsg("  - If you selected a folder, try to find .txt file inside\n")
        r.ShowConsoleMsg("  - Make sure file has .txt extension\n")
      end
    else
      r.ShowConsoleMsg("[ERROR] Path is empty\n")
    end
  end
  
  r.ImGui_Spacing(ctx)
  
  if state.script_text ~= "" then
    local line_count = select(2, state.script_text:gsub("\n", "\n"))
    r.ImGui_TextColored(ctx, COLOR.ok_green, string.format("✓ Loaded: %d lines", line_count + 1))
  else
    r.ImGui_TextDisabled(ctx, "No script loaded")
  end
  
  r.ImGui_Spacing(ctx)
end

local function draw_detection_flags()
  draw_section_header("DETECTION FLAGS")
  
  local c, v = r.ImGui_Checkbox(ctx, "Mismatches", state.detect_mismatches)
  if c then state.detect_mismatches = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Duplicates", state.detect_duplicates)
  if c then state.detect_duplicates = v end
  
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  c, v = r.ImGui_SliderDouble(ctx, "##gap", state.duplicate_gap_threshold, 0.1, 5.0, "Gap: %.2fs")
  if c then state.duplicate_gap_threshold = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Off-Script", state.detect_off_script)
  if c then state.detect_off_script = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Missing", state.detect_missing)
  if c then state.detect_missing = v end
  
  r.ImGui_Separator(ctx)
  
  -- Language Detection Options
  draw_section_header("LANGUAGE & RECOGNITION")
  
  c, v = r.ImGui_Checkbox(ctx, "Force Language", state.force_language)
  if c then state.force_language = v end
  
  if state.force_language then
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 80)
    -- Language dropdown
    local lang_options = { "uk", "ru", "en", "de", "fr", "es", "it", "pl", "auto" }
    local current_idx = 1
    for i, lang in ipairs(lang_options) do
      if state.language_code == lang then
        current_idx = i
        break
      end
    end
    local items = table.concat(lang_options, "\0") .. "\0"
    c, v = r.ImGui_Combo(ctx, "##lang_select", current_idx - 1, items)
    if c then
      state.language_code = lang_options[v + 1] or "auto"
    end
  end
  
  -- Model selection dropdown
  r.ImGui_Text(ctx, "Whisper Model:")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local model_items = table.concat(state.model_names, "\0") .. "\0"
  c, v = r.ImGui_Combo(ctx, "##model_select", state.model_choice - 1, model_items)
  if c then
    state.model_choice = v + 1
    save_settings()
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextDisabled(ctx, "(turbo: fast, large-v3: best)")
  
  -- Terminology/Glossary (direct input, no file loading)
  r.ImGui_Text(ctx, "Glossary (один термін на рядок):")
  r.ImGui_SetNextItemWidth(ctx, -1)
  c, v = r.ImGui_InputTextMultiline(ctx, "##terminology", state.terminology_text, -1, 60)
  if c then state.terminology_text = v end
  
  r.ImGui_Spacing(ctx)
end

local function draw_output_section()
  draw_section_header("OUTPUT")
  
  local c, v = r.ImGui_Checkbox(ctx, "Create Markers", state.create_markers)
  if c then state.create_markers = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Color Items", state.color_items)
  if c then state.color_items = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Add Item Notes (Transcribed Text)", state.add_item_notes)
  if c then state.add_item_notes = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Create Regions (per sentence)", state.create_regions)
  if c then state.create_regions = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Create Text Track (per sentence)", state.create_text_track)
  if c then state.create_text_track = v end
  
  c, v = r.ImGui_Checkbox(ctx, "Export CSV", state.export_csv)
  if c then state.export_csv = v end
  
  if state.export_csv then
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Browse...", 100, 0) then
      local retval, file = r.JS_Dialog_BrowseForSaveFile("Save CSV report", "", "report.csv", "csv")
      if retval and retval ~= 0 and file and file ~= "" then
        state.output_csv_path = file
      end
    end
    r.ImGui_Text(ctx, state.output_csv_path)
  end
  r.ImGui_Spacing(ctx)
end

local function draw_analysis_section()
  draw_section_header("ANALYSIS")
  
  if state.analyzing then
    r.ImGui_TextColored(ctx, COLOR.warn_yellow, "⏳ " .. state.analysis_message)
  else
    if r.ImGui_Button(ctx, "ANALYZE SELECTED", -1, 40) then
      analyze_selected_items()
    end
    
    if state.analysis_results then
      r.ImGui_TextColored(ctx, COLOR.ok_green, "✓ Analysis complete")
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Apply Results", 120, 0) then
        apply_analysis_results()
      end
      
      local summary = state.analysis_results.summary
      if summary then
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, string.format("Total: %d | Errors: %d | Duplicates: %d | Mismatches: %d",
          summary.total, summary.errors, summary.duplicates, summary.mismatches))
      end
    end
  end
end

local function check_http_response()
  -- Poll for HTTP response file without blocking
  if not state.http_waiting or not state.http_response_file then return end
  
  local now = os.time()
  if now - state.http_last_checked < 2 then return end  -- Check every 2 seconds
  state.http_last_checked = now
  
  local elapsed = now - state.http_start_time
  
  -- Timeout check
  if elapsed >= CONFIG.server_timeout then
    r.ShowConsoleMsg("[ERROR] Timeout after " .. elapsed .. "s\n")
    state.http_waiting = false
    state.analyzing = false
    state.analysis_message = "Timeout"
    r.ShowMessageBox("Server timeout.", "Timeout", 0)
    return
  end
  
  -- Check if response file exists
  if not r.file_exists(state.http_response_file) then
    if elapsed % 30 == 0 then
      r.ShowConsoleMsg("[WAIT] Processing... (" .. elapsed .. "s)\n")
    end
    return
  end
  
  -- File exists - check if it's done being written
  local f = io.open(state.http_response_file, "r")
  if not f then return end
  
  local response = f:read("*a")
  f:close()
  
  local current_size = #response
  
  -- First time seeing file
  if not state.http_last_size then
    state.http_last_size = current_size
    state.http_size_stable_count = 0
    return
  end
  
  -- Check if file size is stable (done writing)
  if current_size == state.http_last_size and current_size > 10 then
    state.http_size_stable_count = (state.http_size_stable_count or 0) + 1
    if state.http_size_stable_count < 2 then
      state.http_last_size = current_size
      return  -- Wait 1 more check
    end
    
    -- File is ready - process it
    r.ShowConsoleMsg("[OK] Response ready (" .. current_size .. " bytes)\n")
    state.http_waiting = false
    state.http_last_size = nil
    state.http_size_stable_count = nil
    
    local parse_ok, parsed = pcall(parse_json, response)
    if parse_ok and parsed then
      state.analysis_results = parsed
      state.analyzing = false
      state.analysis_message = "✓ Complete"
      r.ShowConsoleMsg("[OK] Analysis complete!\n")
      r.ShowMessageBox("Success!", "Success", 0)
      
      -- Cleanup
      os.remove(state.http_response_file)
      local req = CONFIG.temp_dir .. "/request.json"
      if r.file_exists(req) then os.remove(req) end
    else
      state.analyzing = false
      state.analysis_message = "Parse error"
      r.ShowConsoleMsg("[ERROR] JSON parse failed\n")
      r.ShowMessageBox("Failed to parse response.", "Error", 0)
    end
  else
    -- Size changed - file still being written
    state.http_last_size = current_size
    state.http_size_stable_count = 0
  end
end

local function loop()
  if not ctx then return end  -- Safety check: ensure context exists
  
  -- FIRST: Check for HTTP responses (async polling)
  check_http_response()
  
  set_modern_theme()
  
r.ImGui_SetNextWindowSize(ctx, 480, 620, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, "VO QC Analyzer v2.0 - Professional Analysis", true)
  
  if visible then
    r.ImGui_Spacing(ctx)
    draw_server_status()
    draw_source_selection()
    draw_script_section()
    draw_detection_flags()
    draw_output_section()
    draw_analysis_section()
    
    r.ImGui_End(ctx)
  end
  
  r.ImGui_PopStyleVar(ctx, 4)
  r.ImGui_PopStyleColor(ctx, 13)
  
  -- Save settings on each frame to ensure they persist
  save_settings()
  
  if open then
    r.defer(loop)
  end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

if r.APIExists('ImGui_GetVersion') then
  if ctx then
    r.ShowConsoleMsg("[VO QC] Initializing...\n")
    create_temp_dir()
    
    -- Load saved settings
    r.ShowConsoleMsg("[VO QC] Loading settings...\n")
    load_settings()
    
    r.ShowConsoleMsg("[VO QC] Checking server health...\n")
    check_server_health()
    r.ShowConsoleMsg("[VO QC] Server status: " .. state.server_status .. " - " .. state.server_message .. "\n")
    r.defer(loop)
  else
    r.ShowConsoleMsg("ERROR: Failed to create ImGui context\n")
    r.ShowMessageBox("Failed to create ReaImGui context. Try restarting REAPER.", "Error", 0)
  end
else
  r.ShowConsoleMsg("ERROR: ReaImGui extension not found\n")
  r.ShowMessageBox("ReaImGui extension required. Install via ReaPack", "Error", 0)
end
