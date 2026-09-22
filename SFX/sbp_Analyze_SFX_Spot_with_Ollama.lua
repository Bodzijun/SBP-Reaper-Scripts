-- @description SBP Analyze SFX Spot with Ollama
-- @version 1.2.4
-- @author SBP & AI
-- @about
--   At the edit cursor, analyzes either a CutScene item or an SFX EVENT/PROCESS/
--   DESIGN marker, using frames from the configured source-video track.
-- @changelog
--   1.2.4: Retired new START/MIDDLE/END cue generation in favor of precise SFX markers while preserving legacy cue data already stored in CutScene Notes.
--   1.2.3: Added explicit batch targets so CutScene and SFX-marker batch passes cannot steal each other's analysis when they share the same start time.
--   1.2.2: Added a decoder-safe final-frame margin for short MP4s and made silent batch failures available to the Assistant as one final summary instead of blocking pop-ups.
--   1.2.1: Fixed adjacent CutScenes and split video items at the same timeline boundary: the following item now owns its start frame, and source duration is enforced before FFmpeg extraction.
--   1.2.0: Added SFX EVENT, PROCESS and DESIGN marker analysis with marker-specific one-, two- or three-frame context.
--   1.1.4: Force Qwen3-VL into final-answer mode with a closed thinking block when older Ollama ignores both non-thinking switches.
--   1.1.3: Added Qwen3-VL's prompt-level non-thinking switch and a bounded tag-response budget for older Ollama releases.
--   1.1.2: Clamped three-frame extraction to the visible source-video range and report FFmpeg frame failures before contacting Ollama.
--   1.1.1: Never treats Qwen thinking as a tag response; requests non-thinking output and limits timed cues to three-frame analysis.
--   1.1.0: Added optional START/MIDDLE/END event cues for timed SFX-library review and placement.
--   1.0.2: New installs now use Qwen3-VL 4B as the default local vision model.
--   1.0.1: Portable FFmpeg discovery via REAPER resource path and English error dialogs.
--   1.0.0: Initial release: single- and three-frame local Ollama SFX analysis with UCS tags.

local r = reaper

-- ===== User settings =========================================================
local SETTINGS_SECTION = "SBP_SFX_Spot_Assistant"
local function setting(key, default) local v = r.GetExtState(SETTINGS_SECTION, key); return v ~= "" and v or default end
local SCENE_TRACK_NAME = setting("scene_track", "__SFX_SCENES__")
local VIDEO_TRACK_NAME = setting("video_track", "na zvuk")
local OLLAMA_MODEL = setting("ollama_model", "qwen3-vl:4b") -- Vision-capable Ollama model.
local QWEN_NO_THINK = OLLAMA_MODEL:lower():find("qwen3", 1, true) and "/no_think\n" or ""
local QWEN_FORCE_FINAL_MESSAGE = QWEN_NO_THINK ~= "" and "; @{ role = 'assistant'; content = '<think></think>' }" or ""
local MULTI_FRAME = setting("analysis_mode", "3") == "3"
local ANALYSIS_STYLE = setting("analysis_style", "short")
-- Precise EVENT/PROCESS/DESIGN markers supersede approximate scene-relative
-- START/MIDDLE/END cues. Legacy cue blocks remain readable by the Assistant.
local TIMED_EVENTS = false
local EVENT_CONTEXT_SECONDS = math.max(0.05, tonumber(setting("event_context_seconds", "0.35")) or 0.35)
local QUIET_ANALYSIS = setting("analysis_silent", "0") == "1"
local ANALYSIS_TARGET = setting("analysis_target", "") -- "scene", "marker", or manual auto-detection.
local FFMPEG = setting("ffmpeg", r.GetResourcePath() .. "/UserPlugins/ffmpeg.exe")
local OLLAMA_URL = "http://localhost:11434/api/chat"
local JPEG_WIDTH = 1280
-- =============================================================================

local AI_BEGIN = "--- AI SFX ANALYSIS ---"
local AI_END = "--- END AI SFX ANALYSIS ---"
local EVENTS_BEGIN = "--- AI SFX EVENTS ---"
local EVENTS_END = "--- END AI SFX EVENTS ---"

local VIDEO_EXTENSIONS = {
  avi=true, mkv=true, mov=true, mp4=true, mpeg=true, mpg=true, mxf=true,
  webm=true, m4v=true, wmv=true, flv=true, ts=true
}

local function message(text)
  if QUIET_ANALYSIS then
    r.SetExtState(SETTINGS_SECTION, "analysis_error", tostring(text), false)
  else
    r.ShowMessageBox(text, "SBP SFX Spot", 0)
  end
end

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end

local function clean_tag_analysis(text)
  local out, seen = {}, {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*(AMB)%s*:%s*(.+)")
    if not key then key, value = line:match("^%s*(FOLEY)%s*:%s*(.+)") end
    if not key then key, value = line:match("^%s*(HARD FX)%s*:%s*(.+)") end
    if not key then key, value = line:match("^%s*(DESIGN)%s*:%s*(.+)") end
    if key and value and not seen[key] then
      local clean_tags = {}
      for tag in value:gmatch("[^,]+") do
        tag = tag:gsub("[%*`]", ""):gsub("_+", " "):match("^%s*(.-)%s*$")
        -- The prompt requires uppercase UCS tags. This rejects a leaked
        -- thinking sentence instead of showing it as a clickable tag.
        if tag:match("^[A-Z0-9 _%-]+$") and tag:match("%S") then clean_tags[#clean_tags+1] = tag end
      end
      if #clean_tags > 0 then out[#out+1] = key .. ": " .. table.concat(clean_tags, ", "); seen[key] = true end
    end
  end
  return #out > 0 and table.concat(out, "\n") or trim(text)
end

local function clean_event_analysis(text)
  local out, seen = {}, {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local anchor, category, tag = line:upper():match("^%s*EVENT%s*:%s*([A-Z]+)%s*|%s*([A-Z ]-)%s*|%s*(.-)%s*$")
    if (anchor == "START" or anchor == "MIDDLE" or anchor == "END") and (category == "AMB" or category == "FOLEY" or category == "HARD FX" or category == "DESIGN") and tag and tag ~= "" and tag ~= "NONE" then
      tag = tag:gsub("[%*`]", ""):gsub("_+", " "):match("^%s*(.-)%s*$")
      local key = anchor .. "|" .. category .. "|" .. tag
      if not seen[key] then out[#out+1] = key; seen[key] = true end
    end
  end
  return table.concat(out, "\n")
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
  return text ~= "" and text or "(no error text)"
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
  -- Timeline item intervals are half-open: at an exact shared boundary the
  -- following CutScene/video item owns the frame, never the preceding one.
  return position >= start and position < start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
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
      return nil, "No item under the cursor on track '" .. SCENE_TRACK_NAME .. "'."
    end
  end
  return nil, "Scene track not found: '" .. SCENE_TRACK_NAME .. "'."
end

local function find_sfx_marker(cursor)
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  for i = 0, marker_count + region_count - 1 do
    local ok, is_region, position, _, name, marker_id, color = r.EnumProjectMarkers3(0, i)
    local kind = ok and not is_region and (name or ""):upper():match("^SFX%s+([A-Z]+)")
    if kind ~= "EVENT" and kind ~= "PROCESS" and kind ~= "DESIGN" then kind = nil end
    if kind and math.abs(position - cursor) < 0.001 then
      return { id=marker_id, position=position, kind=kind, color=color or 0 }
    end
  end
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
  local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local item_source_end = offset + item_length * rate
  local source_length, length_is_qn = r.GetMediaSourceLength(source)
  local source_end = (not length_is_qn and source_length and source_length > 0) and math.min(item_source_end, source_length) or item_source_end
  return path, offset + (cursor - item_pos) * rate, source_end, offset
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
          local path, time, source_end, source_start = video_from_item(item, cursor, false)
          if path then return path, time, source_end, source_start end
        end
      end
      break
    end
  end
  -- A selected item is the explicit choice. Do not require that its item bounds
  -- cover the cursor: scene and source-video items may have different trims.
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local path, time, source_end, source_start = video_from_item(item, cursor, true)
    if path then return path, time, source_end, source_start end
  end
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ii = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, ii)
      if item_spans_position(item, cursor) then
        local path, time, source_end, source_start = video_from_item(item, cursor, false)
        if path then return path, time, source_end, source_start end
      end
    end
  end
  return nil, "Video source not found. Select a video item or place the cursor on one."
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

local function replace_event_block(notes, events)
  local begin_at = notes:find(EVENTS_BEGIN, 1, true)
  if begin_at then
    local end_at = notes:find(EVENTS_END, begin_at, true)
    if end_at then
      local after = end_at + #EVENTS_END
      if events == "" then return trim(notes:sub(1, begin_at - 1) .. notes:sub(after)) end
      return notes:sub(1, begin_at - 1) .. EVENTS_BEGIN .. "\n" .. events .. "\n" .. EVENTS_END .. notes:sub(after)
    end
  end
  if events == "" then return notes end
  local separator = notes ~= "" and "\n\n" or ""
  return notes .. separator .. EVENTS_BEGIN .. "\n" .. events .. "\n" .. EVENTS_END
end

local function main()
  if QUIET_ANALYSIS then r.DeleteExtState(SETTINGS_SECTION, "analysis_error", false) end
  local cursor = r.GetCursorPosition()
  local marker = ANALYSIS_TARGET == "scene" and nil or find_sfx_marker(cursor)
  local is_marker_analysis = marker ~= nil
  if ANALYSIS_TARGET == "marker" and not marker then return message("No SFX EVENT, PROCESS, or DESIGN marker exists at the batch position.") end
  local scene_item, scene_err
  if not is_marker_analysis then
    scene_item, scene_err = find_scene_item(cursor)
    if not scene_item then return message(scene_err) end
  end

  local video_path, source_time_or_err, source_end, source_start = find_video_at_cursor(cursor)
  if not video_path then return message(source_time_or_err) end
  if not r.file_exists(video_path) then
    return message("REAPER returned a video path, but the file does not exist:\n\n" .. video_path)
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
    return message("FFmpeg could not start. Set FFMPEG to 'ffmpeg' or the full path to ffmpeg.exe.")
  end

  local source_span = math.max(0, (source_end or source_time_or_err) - (source_start or 0))
  -- Container duration frequently lands between actual decodable frame times.
  -- Keep a six-frame-ish margin for short local MP4s so the final-frame request
  -- cannot fail even when a CutScene ends just before the visible video edge.
  local end_guard = math.min(0.35, math.max(0.20, source_span * 0.01))
  local source_last_frame = math.max(source_start or 0, (source_end or source_time_or_err) - end_guard)
  local frame_specs
  if is_marker_analysis then
    if marker.kind == "EVENT" then
      frame_specs = {{ offset=0, path=frame_path, label="event" }}
    elseif marker.kind == "PROCESS" then
      frame_specs = {{ offset=-EVENT_CONTEXT_SECONDS, path=frame_path, label="before" }, { offset=0, path=frame_mid_path, label="event" }}
    else
      frame_specs = {{ offset=-EVENT_CONTEXT_SECONDS, path=frame_path, label="before" }, { offset=0, path=frame_mid_path, label="event" }, { offset=EVENT_CONTEXT_SECONDS, path=frame_end_path, label="after" }}
    end
  else
    local scene_length = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
    frame_specs = MULTI_FRAME and {
      { offset=0, path=frame_path, label="beginning" },
      { offset=scene_length * 0.5, path=frame_mid_path, label="middle" },
      { offset=math.max(0, scene_length - 0.05), path=frame_end_path, label="end" }
    } or {{ offset=0, path=frame_path, label="frame" }}
  end

  -- Do not invoke FFmpeg through cmd.exe. REAPER's Lua os.execute uses cmd on
  -- Windows, which can corrupt quoted paths and suppress its diagnostic output.
  for _, sample in ipairs(frame_specs) do
    local sample_time = math.min(math.max(source_time_or_err + sample.offset, source_start or 0), source_last_frame)
    local frame_log = sample.path == frame_path and ffmpeg_log_path or (base .. "_ffmpeg_" .. sample.label .. ".log")
    local ffmpeg_cmd = "& " .. quote_ps(FFMPEG)
      .. " '-y' '-ss' " .. quote_ps(string.format("%.6f", sample_time))
      .. " '-i' " .. quote_ps(video_path)
      .. " '-frames:v' '1' '-update' '1' '-vf' " .. quote_ps("scale=" .. JPEG_WIDTH .. ":-2")
      .. " '-q:v' '2' " .. quote_ps(sample.path)
      .. " 2> " .. quote_ps(frame_log)
      .. "; exit $LASTEXITCODE"
    local frame_ok = run_powershell(ffmpeg_cmd)
    if not command_succeeded(frame_ok) or not read_file(sample.path) then
      return message("FFmpeg could not extract the " .. sample.label .. " frame.\n\nVideo: " .. video_path .. "\nTime: " .. string.format("%.3f", sample_time) .. " sec.\n\nFFmpeg:\n" .. short_error(frame_log))
    end
  end

  local prompt = (not is_marker_analysis and MULTI_FRAME) and [[You are a professional film sound designer. Analyze these three video frames from the same scene (beginning, middle, end) as a SFX spotting reference. Infer only visible changes and likely actions. Do not describe music or dialogue.

Return these four category lines first. Use concise, search-ready, UCS-style English SFX tags in ALL CAPS. Each line must contain 2-8 comma-separated tags. No prose, no sentences, no markdown.
AMB: environment and background tags
FOLEY: sync human / prop contact tags
HARD FX: literal event and mechanism tags
DESIGN: optional cinematic design tags; use NONE if not justified
]] or [[You are a professional film sound designer. Analyze this video frame as a SFX spotting reference. Do not describe music or dialogue.

Return these four category lines first. Use concise, search-ready, UCS-style English SFX tags in ALL CAPS. Each line must contain 2-8 comma-separated tags. No prose, no sentences, no markdown.
AMB: environment and background tags
FOLEY: sync human / prop contact tags
HARD FX: literal event and mechanism tags
DESIGN: optional cinematic design tags; use NONE if not justified
]]
  if is_marker_analysis then
    local context = marker.kind == "EVENT" and "one frame exactly at the marked event" or (marker.kind == "PROCESS" and "two frames: before the action, then exactly at the marked event" or "three frames: before, exactly at, and after the marked event")
    prompt = [[You are a professional film sound designer. These frames show ]] .. context .. [[. The timeline marker is the exact SFX sync point. Identify only concrete short sounds caused by the visible action. Do not describe dialogue, music, scenery, room tone, or general ambience.

Return only these three category lines. Use concise, search-ready, UCS-style English tags in ALL CAPS. Each line must contain 1-3 comma-separated tags, or NONE. No prose, no sentences, no markdown.
FOLEY: direct human / prop contact at the marker
HARD FX: literal mechanical event at the marker
DESIGN: optional cinematic accent; use NONE unless justified
]]
  elseif TIMED_EVENTS then
    prompt = prompt .. [[
After the four category lines, add up to six event lines only when an event is visible or strongly implied. Use exactly this format:
EVENT: START | FOLEY | FOOTSTEPS MUD
EVENT: MIDDLE | HARD FX | DOOR CREAK
EVENT: END | DESIGN | METAL IMPACT

Use START, MIDDLE, or END to indicate where the event occurs in the scene. Keep the category one of AMB, FOLEY, HARD FX, DESIGN. Do not repeat ambient beds as events.]]
  end
  if ANALYSIS_STYLE == "creative" then
    prompt = prompt .. "\nCreative mode: suggest a few plausible cinematic sound-design layers when visually justified, while keeping every tag concrete, searchable, and concise.\n"
  else
    prompt = prompt .. "\nShort mode: return only the most obvious literal sounds; avoid speculation and keep tags to 1-3 words.\n"
  end
  -- Ollama's current `think=false` field is retained below. Older releases
  -- (including 0.34.x) can ignore it for Qwen3-VL, so Qwen's own documented
  -- prompt-level switch is included as a compatibility fallback.
  prompt = QWEN_NO_THINK .. prompt
  local wrote, write_err = write_file(prompt_path, prompt)
  if not wrote then return message("Could not create temporary prompt: " .. tostring(write_err)) end

  -- Keep the Base64/JSON operation in a .ps1 file. Passing this code inline
  -- through os.execute is unreliable on some Windows REAPER installations.
  local build_payload = "$ErrorActionPreference = 'Stop'\n"
    .. "try {\n"
    .. "  $images = @("
  for index, sample in ipairs(frame_specs) do
    build_payload = build_payload .. (index > 1 and "," or "") .. "[Convert]::ToBase64String([IO.File]::ReadAllBytes(" .. quote_ps(sample.path) .. "))"
  end
  build_payload = build_payload .. ")\n"
    .. "  $prompt = [IO.File]::ReadAllText(" .. quote_ps(prompt_path) .. ")\n"
    .. "  $body = @{ model = " .. quote_ps(OLLAMA_MODEL) .. "; stream = $false; think = $false; options = @{ num_predict = 256; temperature = 0.2 }; messages = @(@{ role = 'user'; content = $prompt; images = $images }" .. QWEN_FORCE_FINAL_MESSAGE .. ") } | ConvertTo-Json -Depth 8 -Compress\n"
    .. "  [IO.File]::WriteAllText(" .. quote_ps(payload_path) .. ", $body, [System.Text.UTF8Encoding]::new($false))\n"
    .. "} catch {\n"
    .. "  [IO.File]::WriteAllText(" .. quote_ps(payload_log_path) .. ", ($_ | Out-String), [System.Text.UTF8Encoding]::new($false))\n"
    .. "  exit 1\n"
    .. "}\n"
  local saved, save_err = write_file(payload_script_path, build_payload)
  if not saved then return message("Could not create the Ollama PowerShell script: " .. tostring(save_err)) end
  ok = os.execute("powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " .. quote_cmd(payload_script_path))
  if not command_succeeded(ok) then
    return message("Could not prepare the Ollama request.\n\nPowerShell:\n" .. short_error(payload_log_path))
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
  if not curl_saved then return message("Could not prepare the Curl request to Ollama.") end
  ok = os.execute("powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " .. quote_cmd(curl_script_path))
  if not command_succeeded(ok) then
    return message("Ollama did not respond (three-frame analysis).\n\nModel: " .. OLLAMA_MODEL .. "\n\nError:\n" .. short_error(curl_err_path) .. "\n\nResponse:\n" .. short_error(response_path))
  end

  local extract_result = "$o=Get-Content -Raw " .. quote_ps(response_path) .. " | ConvertFrom-Json;"
    .. "$t=[string]$o.message.content;"
    .. "if([string]::IsNullOrWhiteSpace($t)){"
    .. "$reason=[string]$o.done_reason; $thinking=[string]$o.message.thinking;"
    .. "if(-not [string]::IsNullOrWhiteSpace($thinking)){throw ('Model returned reasoning but no final tags (done reason: ' + $reason + ').')}"
    .. "if($o.error){throw $o.error}else{throw 'Model returned an empty response.'}"
    .. "}else{[IO.File]::WriteAllText(" .. quote_ps(result_path) .. ",$t,(New-Object Text.UTF8Encoding($false)))}"
  ok = os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "' .. extract_result .. '"')
  local analysis = read_file(result_path)
  if not command_succeeded(ok) or not analysis or trim(analysis) == "" then
    local response = read_file(response_path) or ""
    local reason = response:match('"done_reason"%s*:%s*"([^"]+)"') or "unknown"
    local thought = response:match('"thinking"%s*:%s*"([^"]+)"')
    local detail = thought and "The model spent its response budget on internal reasoning." or "The model returned an empty response."
    return message("Ollama returned no final tags (reason: " .. reason .. ").\n\n" .. detail .. "\n\nUpdate Ollama if this continues, then try again.")
  end

  r.Undo_BeginBlock()
  if is_marker_analysis then
    local marker_lines = {}
    for line in clean_tag_analysis(analysis):gmatch("[^\r\n]+") do
      local category, tags = line:match("^%s*([^:]+):%s*(.-)%s*$")
      if category == "FOLEY" or category == "HARD FX" or category == "DESIGN" then
        if tags and tags ~= "" and tags ~= "NONE" then marker_lines[#marker_lines+1] = category .. ": " .. tags end
      end
    end
    local summary = #marker_lines > 0 and table.concat(marker_lines, " • ") or "NONE"
    r.SetProjectMarker3(0, marker.id, false, marker.position, 0, "SFX " .. marker.kind .. " • " .. summary, marker.color)
    r.Undo_EndBlock("SBP: Analyze SFX event marker", -1)
    r.UpdateArrange()
    if not QUIET_ANALYSIS then message("SFX " .. marker.kind .. " marker analyzed.") end
    return
  end
  local _, notes = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  local updated_notes = replace_ai_block(notes or "", clean_tag_analysis(analysis))
  if TIMED_EVENTS then updated_notes = replace_event_block(updated_notes, clean_event_analysis(analysis)) end
  r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", updated_notes, true)
  r.UpdateItemInProject(scene_item)
  r.Undo_EndBlock("SBP: Analyze SFX spot with Ollama", -1)
  r.UpdateArrange()
  if not QUIET_ANALYSIS then message("SFX analysis saved to the scene item Notes.") end
end

main()
