-- @description Select all items with the same audio source
-- @author SBP / OpenAI
-- @version 1.0
-- @about
--   Uses the active takes of the currently selected items as references.
--   Selects every project item whose active take points to any of the same
--   underlying audio files. Source sections and reversed sources are resolved
--   to their root source. MIDI and empty items are ignored.

local r = reaper

local function show_message(text)
  r.ShowMessageBox(text, "Select items with same audio source", 0)
end

-- REAPER 7.78 fixed GetMediaSourceFileName() for section/reverse sources.
-- Resolve the root ourselves so the script also works correctly on older 7.x.
local function root_source(source)
  local seen = {}

  while source and not seen[tostring(source)] do
    seen[tostring(source)] = true
    local parent = r.GetMediaSourceParent(source)
    if not parent then break end
    source = parent
  end

  return source
end

local function source_filename(source)
  if not source then return nil end

  -- Current ReaScript signature (REAPER 7.x).
  local ok, filename = pcall(r.GetMediaSourceFileName, source)
  if ok and type(filename) == "string" and filename ~= "" then
    return filename
  end

  -- Compatibility with builds/bindings that still expect the old buffer arg.
  ok, filename = pcall(r.GetMediaSourceFileName, source, "")
  if ok and type(filename) == "string" and filename ~= "" then
    return filename
  end

  return nil
end

local function normalize_path(path)
  path = path:gsub("\\", "/")
  path = path:gsub("/+", "/")

  local os_name = r.GetOS()
  if os_name:find("Win", 1, true) or os_name:find("OSX", 1, true) then
    path = path:lower()
  end

  return path
end

local function audio_source_key(item)
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return nil end

  local source = root_source(r.GetMediaItemTake_Source(take))
  if not source or r.GetMediaSourceNumChannels(source) < 1 then return nil end

  local filename = source_filename(source)
  if not filename then return nil end

  return normalize_path(filename)
end

local selected_count = r.CountSelectedMediaItems(0)
if selected_count == 0 then
  show_message("Спочатку виберіть хоча б один аудіо-айтем-зразок.")
  return
end

local wanted_sources = {}
for i = 0, selected_count - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local key = audio_source_key(item)
  if key then wanted_sources[key] = true end
end

if not next(wanted_sources) then
  show_message("У вибраних айтемах немає файлового аудіоджерела.")
  return
end

r.Undo_BeginBlock2(0)
r.PreventUIRefresh(1)

local matched_count = 0
for i = 0, r.CountMediaItems(0) - 1 do
  local item = r.GetMediaItem(0, i)
  local selected = wanted_sources[audio_source_key(item)] == true
  r.SetMediaItemSelected(item, selected)
  if selected then matched_count = matched_count + 1 end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock2(0, "Select items with the same audio source", -1)

if matched_count == 0 then
  show_message("Айтемів із тим самим аудіоджерелом не знайдено.")
end
