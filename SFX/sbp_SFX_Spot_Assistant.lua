-- @description SBP SFX Spot Assistant — AI SFX spotting and generation
-- @version 1.0.1
-- @author SBP & AI
-- @license MIT
-- @about AI-assisted SFX spotting tool for REAPER. Analyzes video frames with local Ollama, displays copyable UCS-style tags, and generates SFX through MMAudio or StableDaw.
-- @changelog
--   1.0.1: Portable FFmpeg discovery via REAPER resource path; refined StableDaw runner, controls, tag layout, and English dialogs.
--   1.0.0: Initial unified release with Ollama analysis, MMAudio/StableDaw generation, tag selection, caching, and REAPER item placement.

local r = reaper
local VIEWER_DIR = debug.getinfo(1, "S").source:match("^@(.+[\\/])") or ""
local SETTINGS_SECTION = "SBP_SFX_Spot_Assistant"
local function setting(key, default) local v = reaper.GetExtState(SETTINGS_SECTION, key); return v ~= "" and v or default end
local SCENE_TRACK_NAME = setting("scene_track", "__SFX_SCENES__")
local VIDEO_TRACK_NAME = setting("video_track", "na zvuk")
local GENERATED_TRACK_NAME = setting("generated_track", "__SFX_AI_GENERATED__")
local OLLAMA_MODEL = setting("ollama_model", "gemma4:12b")
local analysis_mode = tonumber(setting("analysis_mode", "3")) or 3
local AI_BEGIN = "--- AI SFX ANALYSIS ---"
local AI_END = "--- END AI SFX ANALYSIS ---"

if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui extension is required.\n\nInstall it via ReaPack: Extensions > ReaPack > Browse packages > ReaImGui.", "SBP SFX Spot Viewer", 0)
  return
end

local function trim(text)
  return (text or ""):match("^%s*(.-)%s*$")
end
local function file_exists(path)
  local f=io.open(path,"rb"); if f then f:close(); return true end; return false
end
local function safe_name(text)
  text=(text or ""):upper():gsub("[^%w]+","_"):gsub("_+","_"):gsub("^_"," "):gsub("_$","")
  return text:sub(1,72)
end
local function cache_root()
  local p = r.GetProjectPath("", "")
  local root = (p ~= "" and p or r.GetResourcePath() .. "/Temp") .. "/SBP_SFX_Cache"
  r.RecursiveCreateDirectory(root .. "/clips", 0); r.RecursiveCreateDirectory(root .. "/outputs", 0); r.RecursiveCreateDirectory(root .. "/failed", 0)
  return root
end
local function clear_cache()
  local root = cache_root()
  for _, sub in ipairs({"clips", "outputs", "failed"}) do
    local dir = root .. "/" .. sub
    local files = {}
    local i = 0
    while true do local f = r.EnumerateFiles(dir, i); if not f then break end; files[#files+1]=f; i=i+1 end
    for _, f in ipairs(files) do os.remove(dir .. "/" .. f) end
  end
end
local function psq(v) return "'" .. tostring(v):gsub("'", "''") .. "'" end
local function cache_hash(value)
  local h = 2166136261
  for i=1,#value do h = (h ~ value:byte(i)) * 16777619 % 4294967296 end
  return string.format("%08X", h)
end

local function item_at_cursor()
  local cursor = r.GetCursorPosition()
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, name = r.GetTrackName(track, "")
    if name == SCENE_TRACK_NAME then
      for ii = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, ii)
        local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local finish = start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if cursor >= start and cursor <= finish then return item end
      end
    end
  end
end

local function read_analysis()
  local item = item_at_cursor()
  if not item then return nil, "Place the edit cursor on an item on track '" .. SCENE_TRACK_NAME .. "'." end
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local from = notes:find(AI_BEGIN, 1, true)
  if not from then return nil, "This item does not contain an AI SFX ANALYSIS block yet." end
  from = from + #AI_BEGIN
  local until_at = notes:find(AI_END, from, true) or (#notes + 1)
  return trim(notes:sub(from, until_at - 1))
end

local function parse_groups(text)
  local groups = {}
  for line in text:gmatch("[^\r\n]+") do
    local title, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
    if title and value then
      local tags = {}
      for tag in value:gmatch("[^,]+") do
        tag = trim(tag)
        if tag ~= "" then tags[#tags + 1] = tag end
      end
      groups[#groups + 1] = { title = trim(title), tags = tags, raw = value }
    end
  end
  return groups
end

local analysis, error_text, groups = nil, nil, {}
local shown_item = false

local function refresh_from_cursor(force)
  local item = item_at_cursor()
  if not force and item == shown_item then return end
  shown_item = item
  analysis, error_text = read_analysis()
  groups = analysis and parse_groups(analysis) or {}
end

refresh_from_cursor(true)
local ctx = r.ImGui_CreateContext("SBP SFX Spot Viewer")
local open = true
local show_settings = false
local request_mmaudio, request_stabledaw = false, false
local analysis_running = false
local batch_running = false

local function run_analyzer()
  if analysis_running then return end
  analysis_running = true
  -- Run on the next UI cycle so the button state is visibly updated first.
  r.defer(function()
    dofile(VIEWER_DIR .. "sbp_Analyze_SFX_Spot_with_Ollama.lua")
    analysis_running = false
    refresh_from_cursor(true)
  end)
end
local function run_batch()
  if batch_running then return end
  batch_running=true
  r.defer(function()
    for ti=0,r.CountTracks(0)-1 do
      local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
      if n==SCENE_TRACK_NAME then
        for ii=0,r.CountTrackMediaItems(tr)-1 do
          local it=r.GetTrackMediaItem(tr,ii)
          r.SetEditCurPos(r.GetMediaItemInfo_Value(it,"D_POSITION"),false,false)
          dofile(VIEWER_DIR.."sbp_Analyze_SFX_Spot_with_Ollama.lua")
        end
        break
      end
    end
    batch_running=false; refresh_from_cursor(true)
  end)
end
local selected_tags, use_video, use_time_selection = {}, setting("use_video","1")=="1", setting("use_time_selection","1")=="1"
local variations, seed, custom_prompt, negative_prompt = tonumber(setting("variations","2")) or 2, tonumber(setting("seed","-1")) or -1, setting("prompt",""), setting("negative","music")
local guidance, steps = tonumber(setting("guidance","4.5")) or 4.5, tonumber(setting("steps","25")) or 25
local sd_prompt, sd_negative = setting("sd_prompt", ""), setting("sd_negative", "")
local sd_duration, sd_steps, sd_cfg, sd_seed = tonumber(setting("sd_duration", "8")) or 8, tonumber(setting("sd_steps", "8")) or 8, tonumber(setting("sd_cfg", "1")) or 1, tonumber(setting("sd_seed", "-1")) or -1
local function save_setting(k,v) r.SetExtState(SETTINGS_SECTION,k,tostring(v),true) end
local function clean_tag(tag)
  return (tostring(tag or ""):gsub("_+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end
local function selected_prompt()
  local out = {}
  for gi, group in ipairs(groups) do for ti, tag in ipairs(group.tags) do if selected_tags[gi.."_"..ti] then out[#out+1] = clean_tag(tag) end end end
  return table.concat(out, ", ")
end

-- Dark studio palette: neutral charcoal panels, amber action controls, and
-- restrained category accents so it sits naturally beside NVK-style tools.
local C = {
  bg = 0x101418FF, panel = 0x171D23FF, frame = 0x222B33FF,
  border = 0x34404AFF, text = 0xE3E8EDFF, dim = 0x8E9BA7FF,
  amber = 0xD87945FF, green = 0x2D8C78FF,
  tag_amb = 0xB59A52FF, tag_foley = 0x4D8FA3FF,
  orange = 0xC86F43FF, violet = 0x9B7BC4FF,
}

local function push_app_style()
  if not (r.ImGui_PushStyleColor and r.ImGui_PopStyleColor) then return 0 end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), C.dim)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), C.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1F6B5CFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2D8C78FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3AA88EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.frame)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), C.amber)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xF09A5EFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x303A43FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3B4853FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x465460FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.panel)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), C.amber)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x303B45FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x394752FF)
  if r.ImGui_PushStyleVar then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
  end
  return 20
end

local function pop_colors(count)
  if count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function pop_app_style(count)
  if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, 3) end
  pop_colors(count)
end

local function category_color(title)
  title = title:upper()
  if title:find("AMB", 1, true) then return C.tag_amb end
  if title:find("FOLEY", 1, true) then return C.tag_foley end
  if title:find("HARD", 1, true) then return C.orange end
  return C.violet
end

local function draw_tag(label, id, color, service, text_color, compact)
  local pushed = 0
  if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color - 0x00000033)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color - 0x00000066)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color or 0xFFFFFFFF)
    if r.ImGui_PushStyleVar then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), service and 4 or 1)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), service and 6 or 4, service and 4 or 3)
    end
    pushed = 4
  end
  local clicked = r.ImGui_Button(ctx, label .. "##" .. id, 0, service and 28 or 0)
  pop_colors(pushed)
  if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, 2) end
  return clicked
end

local function available_tag_width()
  -- GetWindowSize exists in older ReaImGui versions too. Leave generous room
  -- for window padding and the scrollbar so a chip never touches the edge.
  if r.ImGui_GetWindowSize then
    local width = r.ImGui_GetWindowSize(ctx)
    return math.max(180, width - 42)
  end
  return 600
end

local function loop()
  -- The viewer follows the edit cursor: changing scene items changes the data
  -- immediately, with no need to close and reopen the window.
  refresh_from_cursor(false)
  r.ImGui_SetNextWindowSize(ctx, 680, 410, r.ImGui_Cond_FirstUseEver())
  local style_count = push_app_style()
  local visible
  visible, open = r.ImGui_Begin(ctx, "SBP SFX Spot Assistant", open)
  if visible then
    r.ImGui_Text(ctx, "SFX SPOT ASSISTANT")
    r.ImGui_SameLine(ctx)
    if draw_tag(analysis_running and "ANALYZING..." or "ANALYZE FRAME", "analyze", C.amber, true) then run_analyzer() end
    r.ImGui_SameLine(ctx)
    if draw_tag(batch_running and "BATCH..." or "BATCH ANALYZE", "batch", C.green, true) then run_batch() end
    r.ImGui_SameLine(ctx)
    if draw_tag("MMAUDIO FX", "mmaudio_top", C.green, true) then request_mmaudio = true end
    r.ImGui_SameLine(ctx)
    if draw_tag("STABLEDAW FX", "stabledaw_top", C.green, true) then request_stabledaw = true end
    r.ImGui_Separator(ctx)
    show_settings = r.ImGui_CollapsingHeader(ctx, "SCRIPT SETTINGS", true)
    if show_settings then
      r.ImGui_Separator(ctx)
      local changed, value = r.ImGui_InputText(ctx, "Scene track", SCENE_TRACK_NAME)
      if changed then SCENE_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"scene_track",value,true); refresh_from_cursor(true) end
      changed, value = r.ImGui_InputText(ctx, "Video track", VIDEO_TRACK_NAME)
      if changed then VIDEO_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"video_track",value,true) end
      changed, value = r.ImGui_InputText(ctx, "Generated SFX track", GENERATED_TRACK_NAME)
      if changed then GENERATED_TRACK_NAME=value; r.SetExtState(SETTINGS_SECTION,"generated_track",value,true) end
      changed, value = r.ImGui_InputText(ctx, "Ollama model", OLLAMA_MODEL)
      if changed then OLLAMA_MODEL=value; r.SetExtState(SETTINGS_SECTION,"ollama_model",value,true) end
      r.ImGui_Text(ctx, "Frame analysis")
      if r.ImGui_RadioButton(ctx, "Single frame", analysis_mode == 1) then analysis_mode=1; r.SetExtState(SETTINGS_SECTION,"analysis_mode","1",true) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Start / middle / end", analysis_mode == 3) then analysis_mode=3; r.SetExtState(SETTINGS_SECTION,"analysis_mode","3",true) end
      r.ImGui_Text(ctx, "LLM analysis style")
      local analysis_style = setting("analysis_style", "short")
      if r.ImGui_RadioButton(ctx, "Short / literal", analysis_style == "short") then r.SetExtState(SETTINGS_SECTION,"analysis_style","short",true) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_RadioButton(ctx, "Creative / layered", analysis_style == "creative") then r.SetExtState(SETTINGS_SECTION,"analysis_style","creative",true) end
      if r.ImGui_Button(ctx, "CLEAR CACHE") then clear_cache() end
    end
    r.ImGui_Separator(ctx)
    if error_text then
      r.ImGui_TextWrapped(ctx, error_text)
    else
      local tags_open = r.ImGui_CollapsingHeader(ctx, "SFX TAGS", true)
      if tags_open then
      if draw_tag("SELECT ALL", "select_all", C.green, true) then
        for gi, group in ipairs(groups) do
          for ti, _ in ipairs(group.tags) do selected_tags[gi .. "_" .. ti] = true end
        end
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_SameLine(ctx)
      if draw_tag("COPY ALL", "all", C.amber, true) then r.ImGui_SetClipboardText(ctx, analysis) end
      for gi, group in ipairs(groups) do
        r.ImGui_SameLine(ctx)
        if draw_tag("COPY " .. group.title, "copytop" .. gi, C.frame, true, category_color(group.title), true) then
          r.ImGui_SetClipboardText(ctx, (group.raw or ""):gsub("_+", " "))
        end
      end
      r.ImGui_Dummy(ctx, 0, 5)
      for gi, group in ipairs(groups) do
        r.ImGui_Separator(ctx)
        local accent = category_color(group.title)
        if r.ImGui_SetCursorPosY then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 2) end
        local header_colors = 0
        if r.ImGui_PushStyleColor and r.ImGui_PopStyleColor then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accent)
          header_colors = 1
        end
        r.ImGui_Text(ctx, group.title)
        pop_colors(header_colors)
        local row_width = 0
        local max_row_width = available_tag_width()
        for ti, tag in ipairs(group.tags) do
          -- Checkbox + chip; clicking the chip still copies the tag.
          local display_tag = clean_tag(tag)
          local tag_width = r.ImGui_CalcTextSize(ctx, display_tag) + 52
          if ti > 1 and row_width + 8 + tag_width <= max_row_width then
            r.ImGui_SameLine(ctx)
            row_width = row_width + 8 + tag_width
          else
            row_width = tag_width
          end
          local key = gi .. "_" .. ti
          local changed, checked = r.ImGui_Checkbox(ctx, "##select_" .. key, selected_tags[key] or false)
          if changed then selected_tags[key] = checked end
          r.ImGui_SameLine(ctx, nil, 3)
          if draw_tag(display_tag, key, accent) then
            r.ImGui_SetClipboardText(ctx, display_tag)
          end
        end
        end
      end
      end
      r.ImGui_Separator(ctx)
      local mma_open = r.ImGui_CollapsingHeader(ctx, "MMAUDIO GENERATE", true) or request_mmaudio
      if mma_open then
      local changed
      changed, use_video = r.ImGui_Checkbox(ctx, "Use video reference", use_video)
      if changed then save_setting("use_video", use_video and 1 or 0) end
      r.ImGui_SameLine(ctx)
      changed, use_time_selection = r.ImGui_Checkbox(ctx, "Use Time Selection (else scene item)", use_time_selection)
      if changed then save_setting("use_time_selection", use_time_selection and 1 or 0) end
      changed, variations = r.ImGui_SliderInt(ctx, "Variations", variations, 1, 4); if changed then save_setting("variations",variations) end
      changed, seed = r.ImGui_InputInt(ctx, "Seed (-1 random)", seed); if changed then save_setting("seed",seed) end
      if r.ImGui_InputTextMultiline then
        r.ImGui_Text(ctx, "PROMPT OVERRIDE")
        r.ImGui_TextDisabled(ctx, "Optional alternative sound description")
        changed, custom_prompt = r.ImGui_InputTextMultiline(ctx, "##prompt_override", custom_prompt, -1, 70)
        if changed then save_setting("prompt",custom_prompt) end
      end
      changed, negative_prompt = r.ImGui_InputText(ctx, "Negative prompt", negative_prompt); if changed then save_setting("negative",negative_prompt) end
      changed, guidance = r.ImGui_SliderDouble(ctx, "Guidance", guidance, 1, 10); if changed then save_setting("guidance",guidance) end
      changed, steps = r.ImGui_SliderInt(ctx, "Steps", steps, 5, 50); if changed then save_setting("steps",steps) end
      end -- MMAUDIO GENERATE
      if r.ImGui_CollapsingHeader(ctx, "STABLEDAW DESIGN FX", true) or request_stabledaw then
        changed, sd_prompt = r.ImGui_InputTextMultiline(ctx, "##sd_prompt", sd_prompt, -1, 55); if changed then save_setting("sd_prompt",sd_prompt) end
        changed, sd_negative = r.ImGui_InputText(ctx, "SD Negative", sd_negative); if changed then save_setting("sd_negative",sd_negative) end
        changed, sd_duration = r.ImGui_SliderDouble(ctx, "SD Duration", sd_duration, 1, 30); if changed then save_setting("sd_duration",sd_duration) end
        changed, sd_steps = r.ImGui_SliderInt(ctx, "SD Steps", sd_steps, 4, 30); if changed then save_setting("sd_steps",sd_steps) end
        changed, sd_cfg = r.ImGui_SliderDouble(ctx, "SD CFG", sd_cfg, 0.1, 5); if changed then save_setting("sd_cfg",sd_cfg) end
        changed, sd_seed = r.ImGui_InputInt(ctx, "SD Seed (-1 random)", sd_seed); if changed then save_setting("sd_seed",sd_seed) end
        if request_stabledaw then request_stabledaw = false
          local sd_tags = selected_prompt(); local sd_text = sd_prompt ~= "" and (sd_prompt .. (sd_tags ~= "" and ", " or "") .. sd_tags) or sd_tags
          if sd_text == "" then sd_text = "cinematic sound effect" end
          local out = cache_root() .. "/stabledaw_" .. tostring(os.time()) .. ".wav"
          local sd_log = out .. ".log"
          local sd_err = out .. ".err.log"
          local py = setting("python", "C:/Users/User/AppData/Local/Programs/Python/Python311/python.exe")
          local client = setting("stabledaw_client", "E:/Codex/pinokio_agent/skills/local/stabledaw/clients/generate.py")
          local ps = cache_root() .. "/stabledaw_run.ps1"
          local lf0 = io.open(sd_log, "wb"); if lf0 then lf0:write("StableDaw launch started\n"); lf0:close() end
          local function q(x) return "'" .. tostring(x):gsub("'", "''") .. "'" end
          local body = "& "..q(py).." -u "..q(client).." --base-url 'http://127.0.0.1:8600'"
            .." --prompt "..q(sd_text).." --negative-prompt "..q(sd_negative).." --duration "..q(sd_duration).." --steps "..q(sd_steps).." --cfg-scale "..q(sd_cfg).." --seed "..q(sd_seed).." --output "..q(out)
          local f=io.open(ps,"wb"); if f then f:write(body); f:close() else r.ShowMessageBox("Cannot create StableDaw runner script:\n"..ps,"SBP StableDaw",0); return end
          local lf1 = io.open(sd_log, "ab"); if lf1 then lf1:write("Runner: "..body.."\n"); lf1:close() end
          -- Execute inline, matching the verified manual PowerShell command.
          os.execute('powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "' .. body .. '"')
          if file_exists(out) then
            -- StableDaw may pad short generations; trim the returned WAV to the requested duration.
            local ff = setting("ffmpeg", r.GetResourcePath() .. "/UserPlugins/ffmpeg.exe")
            local trimmed = out .. ".trim.wav"
            os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "& '..q(ff)..' -y -i '..q(out)..' -t '..q(sd_duration)..' -c:a pcm_s24le '..q(trimmed)..' 2>$null"')
            if file_exists(trimmed) then out = trimmed end
            r.SetEditCurPos(r.GetCursorPosition(),false,false); r.InsertMedia(out,0)
          else
            local lf=io.open(sd_log,"rb"); local msg=lf and lf:read("*a") or "(no log)"; if lf then lf:close() end
            local le=io.open(sd_err,"rb"); local em=le and le:read("*a") or ""; if le then le:close() end
            if em ~= "" then msg=msg.."\nSTDERR:\n"..em end
            if #msg>1800 then msg=msg:sub(-1800) end
            r.ShowMessageBox("StableDaw did not create a WAV file.\n\nLog:\n"..msg,"SBP StableDaw",0)
          end
        end
      end
      local selected_count = 0
      for _, is_selected in pairs(selected_tags) do
        if is_selected then selected_count = selected_count + 1 end
      end
      if request_mmaudio then request_mmaudio = false
        local prompt = selected_prompt()
        if prompt == "" then prompt = custom_prompt ~= "" and custom_prompt or "cinematic sound effects" end
        local scene = item_at_cursor()
        local start = scene and r.GetMediaItemInfo_Value(scene, "D_POSITION") or r.GetCursorPosition()
        local length = scene and r.GetMediaItemInfo_Value(scene, "D_LENGTH") or 8
        local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if use_time_selection and ts_end > ts_start then start, length = ts_start, ts_end-ts_start end
        local root = cache_root()
        local video = ""
        for ti=0,r.CountTracks(0)-1 do local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
          if n==VIDEO_TRACK_NAME then for ii=0,r.CountTrackMediaItems(tr)-1 do local it=r.GetTrackMediaItem(tr,ii); local p=r.GetMediaItemInfo_Value(it,"D_POSITION"); if start>=p and start<=p+r.GetMediaItemInfo_Value(it,"D_LENGTH") then local tk=r.GetActiveTake(it); if tk then video=r.GetMediaSourceFileName(r.GetMediaItemTake_Source(tk),"") end end end end
        end
        if video=="" then r.ShowMessageBox("Video was not found on track: "..VIDEO_TRACK_NAME,"SBP MMAudio",0) else
          local key_source = video .. "|" .. tostring(start) .. "|" .. tostring(length) .. "|" .. prompt .. "|" .. tostring(seed)
          local cache_id = "mmaudio_v2_" .. cache_hash(key_source)
          local base = root .. "/clips/" .. cache_id
          local clip=base..".mp4"; local out=root.."/outputs/"..cache_id.."_generated.mp4"
          start, length, seed = tonumber(start) or 0, tonumber(length) or 8, tonumber(seed) or -1
          local ffmpeg = setting("ffmpeg", r.GetResourcePath() .. "/UserPlugins/ffmpeg.exe")
          local ff_log = base .. "_ffmpeg_clip.log"
          local ff_script = "& "..psq(ffmpeg).." '-y' '-ss' "..psq(tostring(start)).." '-i' "..psq(video).." '-t' "..psq(tostring(length + 0.5)).." '-c:v' 'libx264' '-preset' 'ultrafast' '-c:a' 'aac' "..psq(clip).." 2> "..psq(ff_log).."; exit $LASTEXITCODE"
          if not file_exists(clip) then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "'..ff_script..'"') end
          if not file_exists(clip) then
            local ef=io.open(ff_log,"rb"); local et=ef and ef:read("*a") or "(log is empty)"; if ef then ef:close() end
            if #et>1800 then et=et:sub(-1800) end
            r.ShowMessageBox("FFmpeg did not create the temporary video clip.\n\nSource: "..video.."\nTime: "..tostring(start).." sec.\n\n"..et,"SBP MMAudio",0); return
          end
          local py=setting("python","C:/Users/User/AppData/Local/Programs/Python/Python311/python.exe"); local client=setting("mmaudio_client","E:/Codex/pinokio_agent/skills/local/mmaudio-git/clients/generate.py")
          local client_log = base .. "_mmaudio.log"
          local lf0 = io.open(client_log, "wb"); if lf0 then lf0:write("MMAudio client launched...\n"); lf0:close() end
          if not file_exists(py) then r.ShowMessageBox("Python was not found:\n"..py,"SBP MMAudio",0); return end
          if not file_exists(client) then r.ShowMessageBox("MMAudio client was not found:\n"..client,"SBP MMAudio",0); return end
          local runner = base .. "_mmaudio_runner.ps1"
          local client_err = base .. "_mmaudio_error.log"
          local generated_count = 0
          for variation=1,variations do
          local variation_out = base .. "_generated_" .. variation .. ".mp4"
          local variation_seed = seed < 0 and -1 or seed + variation - 1
          local script = "$ErrorActionPreference='Continue'\n$p=Start-Process -FilePath "..psq(py)
            .. " -ArgumentList @("..psq(client)..","..psq('--base-url')..","..psq('http://127.0.0.1:42003')..","..psq('--video')..","..psq(clip)..","..psq('--prompt')..","..psq(prompt)..","..psq('--duration')..","..psq(tostring(length))..","..psq('--seed')..","..psq(tostring(variation_seed))..","..psq('--output')..","..psq(variation_out)..") -Wait -PassThru -RedirectStandardOutput "..psq(client_log).." -RedirectStandardError "..psq(client_err).."\nexit $p.ExitCode\n"
          local rf = io.open(runner, "wb"); if rf then rf:write(script); rf:close() end
          if not file_exists(variation_out) then os.execute('powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' .. runner .. '"') end
          out = variation_out
          if file_exists(out) then
            local wav = base .. "_generated_" .. variation .. ".wav"
            os.execute('powershell.exe -WindowStyle Hidden -NoProfile -Command "& '..psq(ffmpeg)..' -y -i '..psq(out)..' -t '..psq(tostring(length))..' -vn -acodec pcm_s24le '..psq(wav)..' 2>$null; exit $LASTEXITCODE"')
            if not file_exists(wav) then r.ShowMessageBox("MMAudio created an MP4, but WAV extraction failed.","SBP MMAudio",0); return end
            local target, target_index
            local range_end = start + length
            for ti=0,r.CountTracks(0)-1 do
              local tr=r.GetTrack(0,ti); local _,n=r.GetTrackName(tr,"")
              if n==GENERATED_TRACK_NAME or n:sub(1,#GENERATED_TRACK_NAME+1)==GENERATED_TRACK_NAME.." " then
                local occupied=false
                for ii=0,r.CountTrackMediaItems(tr)-1 do
                  local it=r.GetTrackMediaItem(tr,ii); local ip=r.GetMediaItemInfo_Value(it,"D_POSITION"); local ie=ip+r.GetMediaItemInfo_Value(it,"D_LENGTH")
                  if ip < range_end and ie > start then occupied=true; break end
                end
                if not occupied then target=tr; target_index=ti; break end
              end
            end
            if not target then
              r.InsertTrackAtIndex(r.CountTracks(0), true)
              target=r.GetTrack(0,r.CountTracks(0)-1)
              local suffix=1
              while true do
                local candidate=GENERATED_TRACK_NAME .. " " .. suffix; local taken=false
                for ti=0,r.CountTracks(0)-1 do local _,n=r.GetTrackName(r.GetTrack(0,ti),""); if n==candidate then taken=true end end
                if not taken then r.GetSetMediaTrackInfo_String(target,"P_NAME",candidate,true); break end
                suffix=suffix+1
              end
            end
            for ti=0,r.CountTracks(0)-1 do r.SetMediaTrackInfo_Value(r.GetTrack(0,ti),"I_SELECTED",0) end
            r.SetMediaTrackInfo_Value(target,"I_SELECTED",1)
            local old_cursor=r.GetCursorPosition()
            r.SetEditCurPos(start, false, false)
            local new_item = r.InsertMedia(wav,0)
            -- InsertMedia may return only a success flag in some REAPER builds.
            -- Resolve the actual MediaItem from the destination track before
            -- calling MediaItem APIs (important for variation 2+).
            if new_item then
              local resolved = nil
              for ii=0,r.CountTrackMediaItems(target)-1 do
                local candidate = r.GetTrackMediaItem(target, ii)
                local pos = r.GetMediaItemInfo_Value(candidate, "D_POSITION")
                if math.abs(pos - start) < 0.01 then resolved = candidate end
              end
              new_item = resolved
            end
            if new_item then
              local tag_name = safe_name(prompt)
              local take = r.GetActiveTake(new_item)
              if take then r.GetSetMediaItemTakeInfo_String(take,"P_NAME","AI_"..tag_name.."_V"..variation,true) end
              local meta = string.format("AI MMAUDIO\nSeed: %s\nPrompt: %s\nNegative: %s\nGuidance: %s\nSteps: %s\nRange start: %.3f\nRange length: %.3f", tostring(variation_seed), prompt, negative_prompt, tostring(guidance), tostring(steps), start, length)
              r.GetSetMediaItemInfo_String(new_item,"P_NOTES",meta,true)
            end
            r.SetEditCurPos(old_cursor, false, false)
            generated_count = generated_count + 1
          else
            local lf = io.open(client_log, "rb"); local logtxt = lf and lf:read("*a") or ""; if lf then lf:close() end
            local le = io.open(client_err, "rb"); local errtxt = le and le:read("*a") or ""; if le then le:close() end
            logtxt = logtxt .. (errtxt ~= "" and ("\nSTDERR:\n" .. errtxt) or "\n(stderr is empty)")
            if #logtxt > 1600 then logtxt = logtxt:sub(-1600) end
            if generated_count == 0 and variation == variations then
              r.ShowMessageBox("MMAudio did not create any result. [BUILD v2]\n\nClip: "..clip.."\nPython: "..py.."\n\nLog:\n"..logtxt,"SBP MMAudio",0)
            end
          end
        end
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, "Checkbox = generate selection; click tag = copy")
      r.ImGui_TextDisabled(ctx, "Click a tag to copy it to the clipboard")
      if #groups == 0 then r.ImGui_TextWrapped(ctx, "No categories detected. Click Copy All to copy the raw analysis.") end
    end
    r.ImGui_End(ctx)
  end
  pop_app_style(style_count)
  if open then
    r.defer(loop)
  elseif r.ImGui_DestroyContext then
    -- Older ReaImGui releases release the context automatically.
    r.ImGui_DestroyContext(ctx)
  end
end

r.defer(loop)
