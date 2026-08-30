-- @description SBP Analyze SFX Spot with Ollama
-- @version 1.0.0
-- @author SBP & AI
-- @about
--   At the edit cursor, finds an item on SCENE_TRACK_NAME, extracts a frame from
--   a video item at the same position, and writes a local Ollama SFX analysis to
--   the scene item's Notes.
-- @changelog
--   Initial release: single- and three-frame local Ollama SFX analysis with UCS tags.

local r = reaper

-- ===== User settings =========================================================
local SETTINGS_SECTION = "SBP_SFX_Spot_Assistant"
local function setting(key, default) local v = r.GetExtState(SETTINGS_SECTION, key); return v ~= "" and v or default end
local SCENE_TRACK_NAME = setting("scene_track", "__SFX_SCENES__")
local VIDEO_TRACK_NAME = setting("video_track", "na zvuk")
local OLLAMA_MODEL = setting("ollama_model", "gemma4:12b") -- Vision-capable Ollama model.
local MULTI_FRAME = setting("analysis_mode", "3") == "3"
local ANALYSIS_STYLE = setting("analysis_style", "short")
local FFMPEG = "C:/Users/User/AppData/Roaming/REAPER/UserPlugins/ffmpeg.exe"
local OLLAMA_URL = "http://localhost:11434/api/chat"
local JPEG_WIDTH = 1280
-- =============================================================================

local AI_BEGIN = "--- AI SFX ANALYSIS ---"
local AI_END = "--- END AI SFX ANALYSIS ---"

local VIDEO_EXTENSIONS = {
  avi=true, mkv=true, mov=true, mp4=true, mpeg=true, mpg=true, mxf=true,
  webm=true, m4v=true, wmv=true, flv=true, ts=true
}

local function message(text)
  r.ShowMessageBox(text, "SBP SFX Spot", 0)
end

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end

local function quote_ps(text)
  return "'" .. tostring(text):gsub("'", "''") .. "'"
end

local function quote_cmd(text)
  -- FFmpeg and curl are launched through cmd.exe by os.execute.
  return '"' .. tostring(text):gsub('"', '\\"') .. '"'
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function command_succeeded(result)
  return result == true or result == 0
end

local function run_powershell(script)
  return os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "' .. script .. '"')
end

local function short_error(path)
  local text = trim(read_file(path) or "")
  if #text > 900 then text = text:sub(1, 900) .. "\n…" end
  return text ~= "" and text or "немає тексту помилки"
end

local function write_file(path, data)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  return true
end

local function cache_root()
  local project_dir = r.GetProjectPath("", "")
  if project_dir and project_dir ~= "" then
    local root = project_dir .. "/SBP_SFX_Cache"
    r.RecursiveCreateDirectory(root .. "/clips", 0)
    r.RecursiveCreateDirectory(root .. "/outputs", 0)
    r.RecursiveCreateDirectory(root .. "/failed", 0)
    return root
  end
  local root = r.GetResourcePath() .. "/Temp/SBP_SFX_Cache"
  r.RecursiveCreateDirectory(root .. "/clips", 0)
  r.RecursiveCreateDirectory(root .. "/outputs", 0)
  r.RecursiveCreateDirectory(root .. "/failed", 0)
  return root
end

local function is_video_path(path)
  local ext = (path or ""):match("%.([^.\\/]+)$")
  return ext and VIDEO_EXTENSIONS[ext:lower()] or false
end

local function item_spans_position(item, position)
  local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return position >= start and position <= start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

local function find_scene_item(cursor)
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    if name == SCENE_TRACK_NAME then
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, ii)
        if item_spans_position(item, cursor) then return item end
      end
      return nil, "На треку '" .. SCENE_TRACK_NAME .. "' немає айтема під курсором."
    end
  end
  return nil, "Не знайдено трек сцен з точним ім’ям '" .. SCENE_TRACK_NAME .. "'."
end

local function video_from_item(item, cursor, allow_any_source)
  local take = r.GetActiveTake(item)
  if not take then return nil end
  local source = r.GetMediaItemTake_Source(take)
  -- GetMediaSourceFileName returns the path itself (unlike GetTrackName, it
  -- does not return a leading boolean). Keeping a second variable here made
  -- every source path nil and falsely reported that no video was selected.
  local path = r.GetMediaSourceFileName(source, "")
  if path == "" or (not allow_any_source and not is_video_path(path)) then return nil end
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  return path, offset + (cursor - item_pos) * rate
end

local function find_video_at_cursor(cursor)
  -- The configured source-video track is deterministic and wins over selection.
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    if name == VIDEO_TRACK_NAME then
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, ii)
        if item_spans_position(item, cursor) then
          local path, time = video_from_item(item, cursor, false)
          if path then return path, time end
        end
      end
      break
    end
  end
  -- A selected item is the explicit choice. Do not require that its item bounds
  -- cover the cursor: scene and source-video items may have different trims.
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local path, time = video_from_item(item, cursor, true)
    if path then return path, time end
  end
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ii = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, ii)
      if item_spans_position(item, cursor) then
        local path, time = video_from_item(item, cursor, false)
        if path then return path, time end
      end
    end
  end
  return nil, "Не знайдено відеоджерело. Виділи айтем із відеофайлом або постав курсор на відеоайтем."
end

local function replace_ai_block(notes, analysis)
  local begin_at = notes:find(AI_BEGIN, 1, true)
  if begin_at then
    local end_at = notes:find(AI_END, begin_at, true)
    if end_at then
      local after = end_at + #AI_END
      return notes:sub(1, begin_at - 1) .. AI_BEGIN .. "\n" .. analysis .. "\n" .. AI_END .. notes:sub(after)
    end
  end
  local separator = notes ~= "" and "\n\n" or ""
  return notes .. separator .. AI_BEGIN .. "\n" .. analysis .. "\n" .. AI_END
end

local function main()
  local cursor = r.GetCursorPosition()
  local scene_item, scene_err = find_scene_item(cursor)
  if not scene_item then return message(scene_err) end

  local video_path, source_time_or_err = find_video_at_cursor(cursor)
  if not video_path then return message(source_time_or_err) end
  if not r.file_exists(video_path) then
    return message("REAPER повернув відеошлях, але файл не існує:\n\n" .. video_path)
  end

  local temp_root = cache_root() .. "/clips"
  local stamp = tostring(math.floor(r.time_precise() * 1000))
  local base = temp_root .. "/spot_" .. stamp
  local frame_path, prompt_path = base .. ".jpg", base .. "_prompt.txt"
  local frame_mid_path, frame_end_path = base .. "_mid.jpg", base .. "_end.jpg"
  local payload_path, response_path, result_path = base .. "_payload.json", base .. "_response.json", base .. "_result.txt"
  local ffmpeg_log_path, payload_log_path = base .. "_ffmpeg.log", base .. "_payload.log"
  local payload_script_path = base .. "_payload.ps1"

  local ok = run_powershell("& " .. quote_ps(FFMPEG) .. " '-version' 2>$null | Out-Null; exit $LASTEXITCODE")
  if not command_succeeded(ok) then
    return message("FFmpeg не запускається. У змінній FFMPEG вкажи 'ffmpeg' або повний шлях до ffmpeg.exe.")
  end

  -- Do not invoke FFmpeg through cmd.exe. REAPER's Lua os.execute uses cmd on
  -- Windows, which can corrupt quoted paths and suppress its diagnostic output.
  local ffmpeg_cmd = "& " .. quote_ps(FFMPEG)
    .. " '-y' '-ss' " .. quote_ps(string.format("%.6f", source_time_or_err))
    .. " '-i' " .. quote_ps(video_path)
    .. " '-frames:v' '1' '-vf' " .. quote_ps("scale=" .. JPEG_WIDTH .. ":-2")
    .. " '-q:v' '2' " .. quote_ps(frame_path)
    .. " 2> " .. quote_ps(ffmpeg_log_path)
    .. "; exit $LASTEXITCODE"
  ok = run_powershell(ffmpeg_cmd)
  if not command_succeeded(ok) or not read_file(frame_path) then
    return message("FFmpeg запустився, але не зміг витягнути кадр.\n\nВідео: " .. video_path .. "\nЧас: " .. string.format("%.3f", source_time_or_err) .. " сек.\n\nFFmpeg:\n" .. short_error(ffmpeg_log_path))
  end
  local scene_length = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
  for _, sample in ipairs(MULTI_FRAME and {{scene_length * 0.5, frame_mid_path}, {math.max(0, scene_length - 0.05), frame_end_path}} or {}) do
    local extra = "& " .. quote_ps(FFMPEG) .. " '-y' '-ss' " .. quote_ps(string.format("%.6f", source_time_or_err + sample[1])) .. " '-i' " .. quote_ps(video_path) .. " '-frames:v' '1' '-vf' " .. quote_ps("scale=" .. JPEG_WIDTH .. ":-2") .. " '-q:v' '2' " .. quote_ps(sample[2])
    run_powershell(extra)
  end

  local prompt = MULTI_FRAME and [[You are a professional film sound designer. Analyze these three video frames from the same scene (beginning, middle, end) as a SFX spotting reference. Infer only visible changes and likely actions. Do not describe music or dialogue.

Return ONLY the following four lines. Use concise, search-ready, UCS-style English SFX tags in ALL CAPS. Each line must contain 2-8 comma-separated tags. No prose, no sentences, no markdown.
AMB: environment and background tags
FOLEY: sync human / prop contact tags
HARD FX: literal event and mechanism tags
DESIGN: optional cinematic design tags; use NONE if not justified
]] or [[You are a professional film sound designer. Analyze this video frame as a SFX spotting reference. Do not describe music or dialogue.

Return ONLY the following four lines. Use concise, search-ready, UCS-style English SFX tags in ALL CAPS. Each line must contain 2-8 comma-separated tags. No prose, no sentences, no markdown.
AMB: environment and background tags
FOLEY: sync human / prop contact tags
HARD FX: literal event and mechanism tags
DESIGN: optional cinematic design tags; use NONE if not justified
]]
  if ANALYSIS_STYLE == "creative" then
    prompt = prompt .. "\nCreative mode: suggest a few plausible cinematic sound-design layers when visually justified, while keeping every tag concrete, searchable, and concise.\n"
  else
    prompt = prompt .. "\nShort mode: return only the most obvious literal sounds; avoid speculation and keep tags to 1-3 words.\n"
  end
  local wrote, write_err = write_file(prompt_path, prompt)
  if not wrote then return message("Не вдалося створити тимчасовий prompt: " .. tostring(write_err)) end

  -- Keep the Base64/JSON operation in a .ps1 file. Passing this code inline
  -- through os.execute is unreliable on some Windows REAPER installations.
  local build_payload = "$ErrorActionPreference = 'Stop'\n"
    .. "try {\n"
    .. "  $img = [Convert]::ToBase64String([IO.File]::ReadAllBytes(" .. quote_ps(frame_path) .. "))\n"
    .. (MULTI_FRAME and ("  $img2 = [Convert]::ToBase64String([IO.File]::ReadAllBytes(" .. quote_ps(frame_mid_path) .. "))\n  $img3 = [Convert]::ToBase64String([IO.File]::ReadAllBytes(" .. quote_ps(frame_end_path) .. "))\n") or "")
    .. "  $prompt = [IO.File]::ReadAllText(" .. quote_ps(prompt_path) .. ")\n"
    .. "  $body = @{ model = " .. quote_ps(OLLAMA_MODEL) .. "; stream = $false; messages = @(@{ role = 'user'; content = $prompt; images = " .. (MULTI_FRAME and "@($img,$img2,$img3)" or "@($img)") .. " }) } | ConvertTo-Json -Depth 8 -Compress\n"
    .. "  [IO.File]::WriteAllText(" .. quote_ps(payload_path) .. ", $body, [System.Text.UTF8Encoding]::new($false))\n"
    .. "} catch {\n"
    .. "  [IO.File]::WriteAllText(" .. quote_ps(payload_log_path) .. ", ($_ | Out-String), [System.Text.UTF8Encoding]::new($false))\n"
    .. "  exit 1\n"
    .. "}\n"
  local saved, save_err = write_file(payload_script_path, build_payload)
  if not saved then return message("Не вдалося створити PowerShell-скрипт для Ollama: " .. tostring(save_err)) end
  ok = os.execute("powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " .. quote_cmd(payload_script_path))
  if not command_succeeded(ok) then
    return message("Не вдалося підготувати запит для Ollama.\n\nPowerShell:\n" .. short_error(payload_log_path))
  end

  -- Vision models can take several minutes for three frames; keep REAPER
  -- waiting instead of aborting while Ollama is still processing.
  local curl_err_path = base .. "_ollama_curl_error.log"
  local curl_script_path = base .. "_ollama_curl.ps1"
  local curl_script = "$ErrorActionPreference='Stop'\n"
    .. "try { $body = [IO.File]::ReadAllText(" .. quote_ps(payload_path) .. "); "
    .. "$resp = Invoke-RestMethod -Uri " .. quote_ps(OLLAMA_URL) .. " -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 900; "
    .. "$resp | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 " .. quote_ps(response_path) .. " } "
    .. "catch { ($_ | Out-String) | Set-Content -Encoding UTF8 " .. quote_ps(curl_err_path) .. "; exit 1 }\n"
  local curl_saved = write_file(curl_script_path, curl_script)
  if not curl_saved then return message("Не вдалося підготувати Curl-запит до Ollama.") end
  ok = os.execute("powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " .. quote_cmd(curl_script_path))
  if not command_succeeded(ok) then
    return message("Ollama не відповіла (триточковий аналіз).\n\nМодель: " .. OLLAMA_MODEL .. "\n\nПомилка:\n" .. short_error(curl_err_path) .. "\n\nВідповідь:\n" .. short_error(response_path))
  end

  local extract_result = "$o=Get-Content -Raw " .. quote_ps(response_path) .. " | ConvertFrom-Json;"
    .. "if($o.message.content){[IO.File]::WriteAllText(" .. quote_ps(result_path) .. ",$o.message.content,(New-Object Text.UTF8Encoding($false)))}else{throw ($o.error)}"
  ok = os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "' .. extract_result .. '"')
  local analysis = read_file(result_path)
  if not command_succeeded(ok) or not analysis or trim(analysis) == "" then
    return message("Ollama повернула відповідь без тексту. Перевір модель і журнал Ollama.")
  end

  local _, notes = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  r.Undo_BeginBlock()
  r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", replace_ai_block(notes or "", trim(analysis)), true)
  r.UpdateItemInProject(scene_item)
  r.Undo_EndBlock("SBP: Analyze SFX spot with Ollama", -1)
  r.UpdateArrange()
  message("SFX-аналіз записано в Notes айтема сцени.")
end

main()
