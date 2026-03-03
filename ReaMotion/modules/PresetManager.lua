---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local PresetManager = {}

local r = reaper

-- JSON-like serializer (Lua table -> string, readable format)
local function serialize(val, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local pad1 = string.rep("  ", indent + 1)

  if type(val) == "table" then
    -- Check if array (sequential integer keys)
    local is_array = true
    local max_n = 0
    for k, _ in pairs(val) do
      if type(k) == "number" and k == math.floor(k) and k > 0 then
        if k > max_n then max_n = k end
      else
        is_array = false
        break
      end
    end
    if max_n == 0 and next(val) ~= nil then is_array = false end

    if is_array and max_n > 0 then
      local items = {}
      for i = 1, max_n do
        items[#items + 1] = pad1 .. serialize(val[i], indent + 1)
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
    else
      local items = {}
      -- Sort keys for deterministic output
      local keys = {}
      for k in pairs(val) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      for _, k in ipairs(keys) do
        local v = val[k]
        local key_str = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
        items[#items + 1] = pad1 .. key_str .. ": " .. serialize(v, indent + 1)
      end
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
    end
  elseif type(val) == "string" then
    -- Escape special chars
    local escaped = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. escaped .. '"'
  elseif type(val) == "boolean" then
    return val and "true" or "false"
  elseif type(val) == "number" then
    if val ~= val then return "0" end -- NaN
    if val == math.huge then return "999999" end
    if val == -math.huge then return "-999999" end
    return tostring(val)
  elseif val == nil then
    return "null"
  end
  return tostring(val)
end

-- Simple JSON parser (handles our output format)
local function parse_json(str)
  local pos = 1
  local len = #str

  local function skip_ws()
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
        pos = pos + 1
      else
        break
      end
    end
  end

  local function peek()
    skip_ws(); return str:sub(pos, pos)
  end
  local function next_char()
    skip_ws(); local c = str:sub(pos, pos); pos = pos + 1; return c
  end

  local parse_value -- forward declaration

  local function parse_string()
    pos = pos + 1 -- skip opening "
    local result = {}
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(result)
      elseif c == '\\' then
        pos = pos + 1
        local esc = str:sub(pos, pos)
        if esc == 'n' then
          result[#result + 1] = '\n'
        elseif esc == 'r' then
          result[#result + 1] = '\r'
        elseif esc == 't' then
          result[#result + 1] = '\t'
        elseif esc == '"' then
          result[#result + 1] = '"'
        elseif esc == '\\' then
          result[#result + 1] = '\\'
        else
          result[#result + 1] = esc
        end
        pos = pos + 1
      else
        result[#result + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(result)
  end

  local function parse_number()
    local start = pos
    if str:sub(pos, pos) == '-' then pos = pos + 1 end
    while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
    if pos <= len and str:sub(pos, pos) == '.' then
      pos = pos + 1
      while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
    end
    if pos <= len and str:sub(pos, pos):lower() == 'e' then
      pos = pos + 1
      if pos <= len and (str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-') then pos = pos + 1 end
      while pos <= len and str:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
    end
    return tonumber(str:sub(start, pos - 1)) or 0
  end

  local function parse_object()
    pos = pos + 1 -- skip {
    local obj = {}
    skip_ws()
    if str:sub(pos, pos) == '}' then
      pos = pos + 1; return obj
    end
    while true do
      skip_ws()
      if str:sub(pos, pos) ~= '"' then break end
      local key = parse_string()
      skip_ws()
      if str:sub(pos, pos) == ':' then pos = pos + 1 end
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      if str:sub(pos, pos) == ',' then
        pos = pos + 1
      elseif str:sub(pos, pos) == '}' then
        pos = pos + 1
        return obj
      else
        break
      end
    end
    return obj
  end

  local function parse_array()
    pos = pos + 1 -- skip [
    local arr = {}
    skip_ws()
    if str:sub(pos, pos) == ']' then
      pos = pos + 1; return arr
    end
    while true do
      skip_ws()
      arr[#arr + 1] = parse_value()
      skip_ws()
      if str:sub(pos, pos) == ',' then
        pos = pos + 1
      elseif str:sub(pos, pos) == ']' then
        pos = pos + 1
        return arr
      else
        break
      end
    end
    return arr
  end

  parse_value = function()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == '"' then
      return parse_string()
    elseif c == '{' then
      return parse_object()
    elseif c == '[' then
      return parse_array()
    elseif c == 't' then
      pos = pos + 4; return true
    elseif c == 'f' then
      pos = pos + 5; return false
    elseif c == 'n' then
      pos = pos + 4; return nil
    elseif c == '-' or c:match('[0-9]') then
      return parse_number()
    end
    return nil
  end

  return parse_value()
end

-- Get presets directory path
function PresetManager.GetPresetsDir(script_path)
  return script_path .. 'presets'
end

-- Ensure presets directory exists
function PresetManager.EnsurePresetsDir(script_path)
  local dir = PresetManager.GetPresetsDir(script_path)
  r.RecursiveCreateDirectory(dir, 0)
  return dir
end

-- Sanitize filename (remove invalid chars)
local function sanitize_filename(name)
  local clean = name:gsub('[<>:"/\\|?*]', '_')
  clean = clean:gsub('^%s+', ''):gsub('%s+$', '')
  if clean == '' then clean = 'unnamed' end
  return clean
end

-- List all preset files in the presets directory
function PresetManager.ListPresets(script_path)
  local dir = PresetManager.GetPresetsDir(script_path)
  local presets = {}

  -- Use reaper.EnumerateFiles to list .json files
  local idx = 0
  while true do
    local filename = r.EnumerateFiles(dir, idx)
    if not filename then break end
    if filename:sub(-5) == '.json' then
      local name = filename:sub(1, -6) -- remove .json
      presets[#presets + 1] = {
        name = name,
        filename = filename,
        path = dir .. '/' .. filename
      }
    end
    idx = idx + 1
  end

  -- Sort alphabetically
  table.sort(presets, function(a, b) return a.name:lower() < b.name:lower() end)

  return presets
end

-- Collect motion data from state for saving
function PresetManager.CollectPresetData(state)
  local data = {
    version = "1.0",
    -- Pads (link A, link B, morph)
    pads = state.pads,
    -- External pad shape + sources (without hardware routing)
    external = nil,
    -- Master modulators
    master_lfo = state.master_lfo,
    master_mseg = state.master_mseg,
    -- Sub-LFOs
    lfo = state.lfo,
    -- Envelope
    env = state.env,
    -- Independent modulator (LFO + MSEG + targets config)
    independent_modulator = state.independent_modulator,
    -- Global segmentation
    segment = state.segment,
  }

  -- Save external but strip hardware channel assignments
  if type(state.external) == 'table' then
    data.external = {
      pad = state.external.pad,
      sources = {}
    }
    if type(state.external.sources) == 'table' then
      for i, src in ipairs(state.external.sources) do
        data.external.sources[i] = {
          name = src.name,
          gain = src.gain,
          enabled = src.enabled
          -- ch_l, ch_r deliberately excluded — hardware-specific
        }
      end
    end
  end

  return data
end

-- Apply loaded preset data to current state
function PresetManager.ApplyPresetData(state, data)
  if type(data) ~= 'table' then return false end

  -- Deep merge helper
  local function deep_merge(dst, src)
    if type(dst) ~= 'table' or type(src) ~= 'table' then return src end
    for k, v in pairs(src) do
      if type(v) == 'table' and type(dst[k]) == 'table' then
        deep_merge(dst[k], v)
      else
        dst[k] = v
      end
    end
    return dst
  end

  -- Apply each section if present
  if data.pads then deep_merge(state.pads, data.pads) end
  if data.master_lfo then deep_merge(state.master_lfo, data.master_lfo) end
  if data.master_mseg then deep_merge(state.master_mseg, data.master_mseg) end
  if data.lfo then deep_merge(state.lfo, data.lfo) end
  if data.env then deep_merge(state.env, data.env) end
  if data.independent_modulator then
    deep_merge(state.independent_modulator, data.independent_modulator)
  end
  if data.segment then deep_merge(state.segment, data.segment) end

  -- Apply external (merge pad + sources without overwriting ch_l/ch_r)
  if data.external then
    if data.external.pad and state.external then
      deep_merge(state.external.pad, data.external.pad)
    end
    if data.external.sources and state.external and state.external.sources then
      for i, src in ipairs(data.external.sources) do
        if state.external.sources[i] then
          if src.name then state.external.sources[i].name = src.name end
          if src.gain then state.external.sources[i].gain = src.gain end
          if src.enabled ~= nil then state.external.sources[i].enabled = src.enabled end
        end
      end
    end
  end

  return true
end

-- Save preset to disk
function PresetManager.SavePresetFile(script_path, name, state)
  local dir = PresetManager.EnsurePresetsDir(script_path)
  local filename = sanitize_filename(name) .. '.json'
  local filepath = dir .. '/' .. filename

  local data = PresetManager.CollectPresetData(state)
  data.preset_name = name

  local ok, json_str = pcall(serialize, data)
  if not ok then
    r.ShowConsoleMsg('[ReaMotionPad] Preset serialize error: ' .. tostring(json_str) .. '\n')
    return false, 'Serialize error'
  end

  local file = io.open(filepath, 'w')
  if not file then
    r.ShowConsoleMsg('[ReaMotionPad] Cannot write preset file: ' .. filepath .. '\n')
    return false, 'Cannot write file'
  end

  file:write(json_str)
  file:close()

  return true, filepath
end

-- Load preset from disk
function PresetManager.LoadPresetFile(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return nil, 'Cannot read file'
  end

  local content = file:read('*a')
  file:close()

  if not content or content == '' then
    return nil, 'Empty file'
  end

  local ok, data = pcall(parse_json, content)
  if not ok or type(data) ~= 'table' then
    return nil, 'Parse error: ' .. tostring(data)
  end

  return data
end

-- Delete preset file
function PresetManager.DeletePresetFile(filepath)
  return os.remove(filepath)
end

-- Build null-terminated list for ImGui Combo
function PresetManager.BuildComboList(presets)
  if #presets == 0 then
    return '(none)\0'
  end
  local items = {}
  for _, p in ipairs(presets) do
    items[#items + 1] = p.name
  end
  return table.concat(items, '\0') .. '\0'
end

return PresetManager
