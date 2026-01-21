-- ReaSFX Preset Module
-- v2.0 - Save/Load system using REAPER ExtState
local Preset = {}
local r = reaper

-- JSON serialization (simple implementation for Lua tables)
local function TableToJSON(tbl, indent)
    indent = indent or 0
    local result = {}
    local ind = string.rep("  ", indent)

    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            return '"' .. tbl:gsub('"', '\\"') .. '"'
        else
            return tostring(tbl)
        end
    end

    -- Check if array or dict
    local is_array = true
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        if type(k) ~= "number" or k ~= count then
            is_array = false
            break
        end
    end

    if is_array and count > 0 then
        table.insert(result, "[")
        for i, v in ipairs(tbl) do
            table.insert(result, ind .. "  " .. TableToJSON(v, indent + 1))
            if i < count then
                table.insert(result, ",")
            end
        end
        table.insert(result, ind .. "]")
    else
        table.insert(result, "{")
        local first = true
        for k, v in pairs(tbl) do
            if not first then
                table.insert(result, ",")
            end
            first = false
            local key = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
            table.insert(result, ind .. "  " .. key .. ": " .. TableToJSON(v, indent + 1))
        end
        table.insert(result, ind .. "}")
    end

    return table.concat(result, "\n")
end

-- Simple JSON parser (basic, handles strings, numbers, booleans, tables)
local function JSONToTable(str)
    -- Remove whitespace
    str = str:gsub("^%s*(.-)%s*$", "%1")

    -- Parse string
    if str:sub(1,1) == '"' and str:sub(-1) == '"' then
        return str:sub(2, -2):gsub('\\"', '"')
    end

    -- Parse boolean
    if str == "true" then return true end
    if str == "false" then return false end
    if str == "null" then return nil end

    -- Parse number
    local num = tonumber(str)
    if num then return num end

    -- Parse array
    if str:sub(1,1) == "[" then
        local arr = {}
        local content = str:sub(2, -2)
        local depth = 0
        local current = ""

        for i = 1, #content do
            local c = content:sub(i,i)
            if c == "{" or c == "[" then
                depth = depth + 1
                current = current .. c
            elseif c == "}" or c == "]" then
                depth = depth - 1
                current = current .. c
            elseif c == "," and depth == 0 then
                table.insert(arr, JSONToTable(current))
                current = ""
            else
                current = current .. c
            end
        end

        if current ~= "" then
            table.insert(arr, JSONToTable(current))
        end

        return arr
    end

    -- Parse object
    if str:sub(1,1) == "{" then
        local obj = {}
        local content = str:sub(2, -2)
        local depth = 0
        local current = ""
        local pairs_list = {}

        for i = 1, #content do
            local c = content:sub(i,i)
            if c == "{" or c == "[" then
                depth = depth + 1
                current = current .. c
            elseif c == "}" or c == "]" then
                depth = depth - 1
                current = current .. c
            elseif c == "," and depth == 0 then
                table.insert(pairs_list, current)
                current = ""
            else
                current = current .. c
            end
        end

        if current ~= "" then
            table.insert(pairs_list, current)
        end

        for _, pair in ipairs(pairs_list) do
            local colon_pos = pair:find(":")
            if colon_pos then
                local key = pair:sub(1, colon_pos-1)
                local val = pair:sub(colon_pos+1)
                key = key:gsub("^%s*(.-)%s*$", "%1")
                val = val:gsub("^%s*(.-)%s*$", "%1")

                if key:sub(1,1) == '"' then
                    key = key:sub(2, -2)
                end

                obj[key] = JSONToTable(val)
            end
        end

        return obj
    end

    return str
end

-- =========================================================
-- SAVE PROJECT STATE
-- =========================================================
function Preset.SaveProjectState(Core)
    local data = {
        version = "2.0",
        keys = {},
        selected_note = Core.Project.selected_note,
        selected_set = Core.Project.selected_set,
        placement_mode = Core.Project.placement_mode,
        trigger_mode = Core.Project.trigger_mode,
        group_thresh = Core.Project.group_thresh,
        use_snap_align = Core.Project.use_snap_align,

        -- Global randomization
        g_rnd_vol = Core.Project.g_rnd_vol,
        g_rnd_pitch = Core.Project.g_rnd_pitch,
        g_rnd_pan = Core.Project.g_rnd_pan,
        g_rnd_pos = Core.Project.g_rnd_pos,
        g_rnd_offset = Core.Project.g_rnd_offset,
        g_rnd_fade = Core.Project.g_rnd_fade,
        g_rnd_len = Core.Project.g_rnd_len
    }

    -- Save keys data
    for note, key_data in pairs(Core.Project.keys) do
        data.keys[tostring(note)] = {
            sets = {}
        }

        for set_idx = 1, 16 do
            local set = key_data.sets[set_idx]
            if set and #set.events > 0 then
                data.keys[tostring(note)].sets[tostring(set_idx)] = {
                    trigger_on = set.trigger_on,
                    rnd_vol = set.rnd_vol,
                    rnd_pitch = set.rnd_pitch,
                    rnd_pan = set.rnd_pan,
                    rnd_pos = set.rnd_pos,
                    rnd_offset = set.rnd_offset,
                    rnd_fade = set.rnd_fade,
                    rnd_len = set.rnd_len,
                    xy_x = set.xy_x,
                    xy_y = set.xy_y,
                    seq_count = set.seq_count,
                    seq_rate = set.seq_rate,
                    seq_len = set.seq_len,
                    seq_fade = set.seq_fade,
                    seq_mode = set.seq_mode,
                    loop_crossfade = set.loop_crossfade,
                    loop_sync_mode = set.loop_sync_mode,
                    release_length = set.release_length,
                    release_fade = set.release_fade,
                    events = set.events
                }
            end
        end
    end

    local json_str = TableToJSON(data)
    r.SetExtState("ReaSFX", "ProjectState", json_str, false)

    Core.Log("State saved")
    return true
end

-- =========================================================
-- LOAD PROJECT STATE
-- =========================================================
function Preset.LoadProjectState(Core)
    if not r.HasExtState("ReaSFX", "ProjectState") then
        Core.Log("No saved state found")
        return false
    end

    local json_str = r.GetExtState("ReaSFX", "ProjectState")
    local data = JSONToTable(json_str)

    if not data or type(data) ~= "table" then
        Core.Log("Failed to parse saved state")
        return false
    end

    -- Restore basic settings
    Core.Project.selected_note = data.selected_note or 60
    Core.Project.selected_set = data.selected_set or 1
    Core.Project.placement_mode = data.placement_mode or 1
    Core.Project.trigger_mode = data.trigger_mode or 0
    Core.Project.group_thresh = data.group_thresh or 0.5
    Core.Project.use_snap_align = data.use_snap_align or false

    -- Restore global randomization
    Core.Project.g_rnd_vol = data.g_rnd_vol or 0.0
    Core.Project.g_rnd_pitch = data.g_rnd_pitch or 0.0
    Core.Project.g_rnd_pan = data.g_rnd_pan or 0.0
    Core.Project.g_rnd_pos = data.g_rnd_pos or 0.0
    Core.Project.g_rnd_offset = data.g_rnd_offset or 0.0
    Core.Project.g_rnd_fade = data.g_rnd_fade or 0.0
    Core.Project.g_rnd_len = data.g_rnd_len or 0.0

    -- Restore keys
    Core.Project.keys = {}
    if data.keys and type(data.keys) == "table" then
        for note_str, key_data in pairs(data.keys) do
            local note = tonumber(note_str)
            if note then
                Core.InitKey(note)

                if key_data.sets then
                    for set_idx_str, set_data in pairs(key_data.sets) do
                        local set_idx = tonumber(set_idx_str)
                        if set_idx and set_idx >= 1 and set_idx <= 16 then
                            local set = Core.Project.keys[note].sets[set_idx]

                            set.trigger_on = set_data.trigger_on or 0
                            set.rnd_vol = set_data.rnd_vol or 0.0
                            set.rnd_pitch = set_data.rnd_pitch or 0.0
                            set.rnd_pan = set_data.rnd_pan or 0.0
                            set.rnd_pos = set_data.rnd_pos or 0.0
                            set.rnd_offset = set_data.rnd_offset or 0.0
                            set.rnd_fade = set_data.rnd_fade or 0.0
                            set.rnd_len = set_data.rnd_len or 0.0
                            set.xy_x = set_data.xy_x or 0.5
                            set.xy_y = set_data.xy_y or 0.5
                            set.seq_count = set_data.seq_count or 4
                            set.seq_rate = set_data.seq_rate or 0.150
                            set.seq_len = set_data.seq_len or 0.100
                            set.seq_fade = set_data.seq_fade or 0.020
                            set.seq_mode = set_data.seq_mode or 1
                            set.loop_crossfade = set_data.loop_crossfade or 0.050
                            set.loop_sync_mode = set_data.loop_sync_mode or 0
                            set.release_length = set_data.release_length or 1.0
                            set.release_fade = set_data.release_fade or 0.3
                            set.events = set_data.events or {}
                        end
                    end
                end
            end
        end
    end

    Core.Log("State loaded")
    return true
end

-- =========================================================
-- EXPORT TO FILE
-- =========================================================
function Preset.ExportToFile(Core, filepath)
    local data = {
        version = "2.0",
        keys = Core.Project.keys
    }

    local json_str = TableToJSON(data)
    local file = io.open(filepath, "w")
    if not file then
        Core.Log("Failed to write file: " .. filepath)
        return false
    end

    file:write(json_str)
    file:close()

    Core.Log("Exported to: " .. filepath)
    return true
end

-- =========================================================
-- IMPORT FROM FILE
-- =========================================================
function Preset.ImportFromFile(Core, filepath)
    local file = io.open(filepath, "r")
    if not file then
        Core.Log("Failed to read file: " .. filepath)
        return false
    end

    local json_str = file:read("*all")
    file:close()

    local data = JSONToTable(json_str)
    if not data or type(data) ~= "table" or not data.keys then
        Core.Log("Invalid preset file format")
        return false
    end

    Core.Project.keys = data.keys
    Core.Log("Imported from: " .. filepath)
    return true
end

return Preset
