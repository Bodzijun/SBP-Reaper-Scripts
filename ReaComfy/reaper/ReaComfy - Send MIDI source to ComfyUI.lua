-- @description ReaComfy - Send selected MIDI source to ComfyUI
-- @version 0.1.0
-- @noindex
-- @about Writes the selected external MIDI source to the ReaComfy manifest for YuE2 nodes.

local _, _, section, cmd = reaper.get_action_context()
local script_path = ({reaper.get_action_context()})[2]
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/]reaper[\\/][^\\/]+$") or (script_path or ""):match("^(.*)[\\/][^\\/]+$")

local function log(message)
  reaper.ShowConsoleMsg("ReaComfy: " .. tostring(message) .. "\n")
end

local function json_escape(value)
  value = tostring(value or "")
  return value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function project_cache()
  local project_path = reaper.GetProjectPath(0)
  if project_path and project_path ~= "" then
    local cache = project_path .. "/REAPER_AI_CACHE"
    reaper.RecursiveCreateDirectory(cache, 0)
    return cache
  end
  local cache = root .. "/runtime"
  reaper.RecursiveCreateDirectory(cache, 0)
  return cache
end

local function publish_cache_pointer(cache)
  local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
  if not user_root then return end
  local bridge_cache = user_root .. "/REAPER_AI_CACHE"
  reaper.RecursiveCreateDirectory(bridge_cache, 0)
  local pointer = io.open(bridge_cache .. "/current_project.txt", "w")
  if pointer then pointer:write(cache); pointer:close() end
end

local function be16(value)
  value = math.max(0, math.floor(value or 0))
  return string.char(math.floor(value / 256) % 256, value % 256)
end

local function be32(value)
  value = math.max(0, math.floor(value or 0))
  return string.char(
    math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 256) % 256,
    value % 256)
end

local function vlq(value)
  value = math.max(0, math.floor(value or 0))
  local bytes = {value % 128}
  value = math.floor(value / 128)
  while value > 0 do
    table.insert(bytes, 1, (value % 128) + 128)
    value = math.floor(value / 128)
  end
  local result = {}
  for i = 1, #bytes do result[i] = string.char(bytes[i]) end
  return table.concat(result)
end

local function tempo_event()
  local bpm = reaper.TimeMap_GetDividedBpmAtTime and reaper.TimeMap_GetDividedBpmAtTime(0) or 120
  bpm = math.max(1, tonumber(bpm) or 120)
  local micros = math.floor(60000000 / bpm + 0.5)
  return string.char(0xFF, 0x51, 0x03,
    math.floor(micros / 65536) % 256,
    math.floor(micros / 256) % 256,
    micros % 256)
end

local function read_i32_le(data, offset)
  local b1, b2, b3, b4 = data:byte(offset, offset + 3)
  if not b4 then return nil end
  local value = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  if value >= 2147483648 then value = value - 4294967296 end
  return value
end

local function export_embedded_midi(takes, output_path)
  local ref_take = takes[1]
  local events = {}
  local event_count = 0
  for _, take in ipairs(takes) do
    local ok, packed = reaper.MIDI_GetAllEvts(take, "")
    if ok and packed and packed ~= "" then
      local cursor, running_status, local_tick = 1, nil, 0
      while cursor <= #packed do
        local offset = read_i32_le(packed, cursor)
        local flags = packed:byte(cursor + 4)
        local message_length = read_i32_le(packed, cursor + 5)
        if not offset or not flags or not message_length or message_length < 0 then break end
        local message_start = cursor + 9
        local message_end = message_start + message_length - 1
        if message_end >= #packed + 1 then break end
        local message = packed:sub(message_start, message_end)
        cursor = message_end + 1
        local_tick = local_tick + offset
        if #message > 0 then
          local first = message:byte(1)
          if first < 0x80 and running_status then message = string.char(running_status) .. message end
          local status = message:byte(1)
          if status and status >= 0x80 and status < 0xF0 then running_status = status else running_status = nil end
          if not status or status < 0x80 then message = "" end
          local event = message
          if status == 0xFF and message:byte(2) == 0x0F then event = string.char(0xFF, 0x01) .. vlq(#message - 2) .. message:sub(3) end
          if status == 0xF0 or status == 0xF7 then event = string.char(status) .. vlq(#message - 1) .. message:sub(2) end
          if #event > 0 then
            local project_time = reaper.MIDI_GetProjTimeFromPPQPos(take, local_tick)
            local tick = reaper.MIDI_GetPPQPosFromProjTime(ref_take, project_time)
            events[#events + 1] = {tick = math.max(0, math.floor(tick + 0.5)), data = event}
            event_count = event_count + 1
          end
        end
      end
    end
  end
  if event_count == 0 then return false, "The MIDI take contains no exportable events." end
  local first_item = reaper.GetMediaItemTake_Item(takes[1])
  local last_item = reaper.GetMediaItemTake_Item(takes[#takes])
  if first_item and last_item then
    local item_start = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
    local item_end = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
    for index = 0, reaper.CountProjectMarkers(0) - 1 do
      local _, is_region, start_time, _, name = reaper.EnumProjectMarkers3(0, index)
      if is_region and name and name ~= "" and start_time >= item_start and start_time < item_end then
        local tick = reaper.MIDI_GetPPQPosFromProjTime(ref_take, start_time)
        local marker = string.char(0xFF, 0x06) .. vlq(#name) .. name
        events[#events + 1] = {tick = math.max(0, math.floor(tick + 0.5)), data = marker}
      end
    end
  end
  table.sort(events, function(a, b) return a.tick < b.tick end)
  local track = {vlq(0) .. tempo_event()}
  local previous_tick = 0
  for _, event in ipairs(events) do
    track[#track + 1] = vlq(math.max(0, event.tick - previous_tick)) .. event.data
    previous_tick = event.tick
  end
  track[#track + 1] = vlq(0) .. "\255\47\0"
  local body = table.concat(track)
  local file = io.open(output_path, "wb")
  if not file then return false, "Cannot write MIDI file: " .. output_path end
  file:write("MThd", be32(6), be16(0), be16(1), be16(960))
  file:write("MTrk", be32(#body), body)
  file:close()
  return true
end

-- Export selected REAPER tracks as a Type 1 MIDI file. Items on one track
-- become one MIDI track; track names are kept for YuE2 track selection.
local function export_grouped_midi(groups, output_path)
  local reference_take = groups[1].takes[1]
  local track_bodies = {}
  local max_tick = 0
  for _, group in ipairs(groups) do
    local events, last_tick = {}, 0
    for _, take in ipairs(group.takes) do
      local ok, packed = reaper.MIDI_GetAllEvts(take, "")
      if ok and packed then
        local cursor, local_tick, running = 1, 0, nil
        while cursor <= #packed do
          local offset = read_i32_le(packed, cursor)
          local flags = packed:byte(cursor + 4)
          local length = read_i32_le(packed, cursor + 5)
          if not offset or not flags or not length or length < 0 then break end
          local start = cursor + 9
          local finish = start + length - 1
          if finish >= #packed + 1 then break end
          local message = packed:sub(start, finish)
          cursor = finish + 1
          local_tick = local_tick + offset
          if #message > 0 then
            local first = message:byte(1)
            if first < 0x80 and running then message = string.char(running) .. message end
            local status = message:byte(1)
            if status and status >= 0x80 and status < 0xF0 then running = status else running = nil end
            if status and status >= 0x80 then
              local project_time = reaper.MIDI_GetProjTimeFromPPQPos(take, local_tick)
              local tick = math.max(0, math.floor(reaper.MIDI_GetPPQPosFromProjTime(reference_take, project_time) + 0.5))
              local event = message
              if status == 0xFF and message:byte(2) == 0x0F then event = string.char(0xFF, 0x01) .. vlq(#message - 2) .. message:sub(3) end
              if status == 0xF0 or status == 0xF7 then event = string.char(status) .. vlq(#message - 1) .. message:sub(2) end
              events[#events + 1] = {tick = tick, data = event}
              if tick > max_tick then max_tick = tick end
            end
          end
        end
      end
    end
    table.sort(events, function(a, b) return a.tick < b.tick end)
    local name = group.name ~= "" and group.name or "REAPER MIDI"
    local body, previous = {vlq(0) .. string.char(0xFF, 0x03) .. vlq(#name) .. name}, 0
    for _, event in ipairs(events) do
      body[#body + 1] = vlq(event.tick - previous) .. event.data
      previous = event.tick
    end
    body[#body + 1] = vlq(0) .. "\255\47\0"
    track_bodies[#track_bodies + 1] = table.concat(body)
  end
  local markers, previous = {}, 0
  for index = 0, reaper.CountProjectMarkers(0) - 1 do
    local _, is_region, start_time, _, name = reaper.EnumProjectMarkers3(0, index)
    if is_region and name and name ~= "" then
      local tick = math.max(0, math.floor(reaper.MIDI_GetPPQPosFromProjTime(reference_take, start_time) + 0.5))
      markers[#markers + 1] = {tick = tick, data = string.char(0xFF, 0x06) .. vlq(#name) .. name}
    end
  end
  table.sort(markers, function(a, b) return a.tick < b.tick end)
  local conductor = {vlq(0) .. tempo_event()}
  for _, marker in ipairs(markers) do conductor[#conductor + 1] = vlq(marker.tick - previous) .. marker.data; previous = marker.tick end
  conductor[#conductor + 1] = vlq(0) .. "\255\47\0"
  local file = io.open(output_path, "wb")
  if not file then return false, "Cannot write MIDI file: " .. output_path end
  file:write("MThd", be32(6), be16(1), be16(#track_bodies + 1), be16(960))
  local conductor_body = table.concat(conductor)
  file:write("MTrk", be32(#conductor_body), conductor_body)
  for _, body in ipairs(track_bodies) do file:write("MTrk", be32(#body), body) end
  file:close()
  return true
end

local items = {}
local midi_scope = reaper.GetExtState("REAPER_AI", "yue2_midi_scope")
if midi_scope == "project" then
  for index = 0, reaper.CountMediaItems(0) - 1 do
    local project_item = reaper.GetMediaItem(0, index)
    local project_take = project_item and reaper.GetActiveTake(project_item)
    if project_take and reaper.TakeIsMIDI(project_take) then
      items[#items + 1] = {item = project_item, take = project_take}
    end
  end
else
  for index = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local selected_item = reaper.GetSelectedMediaItem(0, index)
    local selected_take = selected_item and reaper.GetActiveTake(selected_item)
    if selected_take and reaper.TakeIsMIDI(selected_take) then
      items[#items + 1] = {item = selected_item, take = selected_take}
    end
  end
end
if #items == 0 then
  log(midi_scope == "project" and "No MIDI items found in the project." or "Select one or more MIDI items first.")
  return
end
table.sort(items, function(a, b)
  return reaper.GetMediaItemInfo_Value(a.item, "D_POSITION") < reaper.GetMediaItemInfo_Value(b.item, "D_POSITION")
end)
local item, take = items[1].item, items[1].take
local groups, group_map = {}, {}
for _, entry in ipairs(items) do
  local track = reaper.GetMediaItem_Track(entry.item)
  local key = tostring(track)
  if not group_map[key] then
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    group_map[key] = {name = name or "REAPER MIDI", takes = {}}
    groups[#groups + 1] = group_map[key]
  end
  group_map[key].takes[#group_map[key].takes + 1] = entry.take
end

local source = reaper.GetMediaItemTake_Source(take)
local midi_path = source and reaper.GetMediaSourceFileName(source, "") or ""
-- Imported MIDI can expose an empty source filename even when the item chunk
-- still contains the original FILE path. Use it as a compatibility fallback.
if not midi_path or midi_path == "" then
  local _, chunk = reaper.GetItemStateChunk(item, "", false)
  if chunk then
    midi_path = chunk:match('[Ff][Ii][Ll][Ee]%s+"([^"]+%.midi?)"') or ""
  end
end
if midi_path and midi_path ~= "" then
  midi_path = midi_path:gsub('\\\\', '\\')
end
local cache = project_cache()
publish_cache_pointer(cache)
os.remove(cache .. "/comfy_to_reaper.json")
local job_id = tostring(os.time()) .. "_" .. tostring(math.floor(os.clock() * 1000) % 1000)
local user_root = os.getenv("USERPROFILE") or os.getenv("HOME")
if user_root then os.remove(user_root .. "/REAPER_AI_CACHE/comfy_to_reaper.json") end
if #items > 1 or #groups > 1 or not midi_path or midi_path == "" then
  local takes = {}
  for _, entry in ipairs(items) do takes[#takes + 1] = entry.take end
  midi_path = cache .. string.format("/reacomfy_midi_%d.mid", os.time())
  local exported, export_error
  if #groups > 1 then
    exported, export_error = export_grouped_midi(groups, midi_path)
  else
    exported, export_error = export_embedded_midi(takes, midi_path)
  end
  if not exported then
    log("Could not export embedded MIDI: " .. tostring(export_error))
    return
  end
  log((#groups > 1 and "Selected MIDI tracks exported as Type 1: " or #items > 1 and "Selected MIDI items merged automatically: " or "Embedded MIDI exported automatically: ") .. midi_path)
end
if not reaper.file_exists(midi_path) then
  log("The MIDI source path was found but the file is missing: " .. midi_path)
  return
end

local manifest_path = cache .. "/reaper_to_comfy.json"
local manifest = io.open(manifest_path, "w")
if not manifest then
  log("Cannot write manifest: " .. manifest_path)
  return
end
manifest:write(string.format('{"source":"midi","job_id":"%s","midi_path":"%s"}', job_id, json_escape(midi_path)))
manifest:close()
log("MIDI source is ready for ComfyUI: " .. midi_path)
log("Manifest: " .. manifest_path)
