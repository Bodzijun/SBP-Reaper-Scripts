-- @description Multi-VSTi Fish Builder
-- @version 0.6.1
-- @author SBP&AI
-- @about
--   Builds configurable multi-output VSTi track structures and routing in REAPER.
--   Supports same-track, legacy split, MIDI-only and output-only routing schemes,
--   MIDI channels or buses, presets, folders and multiple send modes.
--
--   Requires REAPER 7.0 or newer and the ReaImGui extension.
-- @changelog
--   Prepared the metadata header for ReaPack publication.

local SCRIPT_NAME = "Multi-VSTi Fish Builder"
local EXT_SECTION = "MultiVSTiFishBuilder"
local PRE_RECEIVE_SENDMODE = 8
local SENDMODE_PRE_FX = 1
local MIDI_INPUT_ALL_ALL_CHANNELS = 6112
local MIDI_INPUT_ALL_CH1_BASE = 6112
local WINDOW_W, WINDOW_H = 560, 780
local WINDOW_MIN_W, WINDOW_MIN_H = 560, 480
local WINDOW_MAX_W, WINDOW_MAX_H = 560, 1160
local CONTENT_W = 520
local BTN4_W = 122
local ROUTE_SCHEME_SAME_TRACK = 1
local ROUTE_SCHEME_LEGACY_SPLIT = 2
local ROUTE_SCHEME_MIDI_ONLY = 3
local ROUTE_SCHEME_OUT_ONLY = 4
local MIDI_TARGET_CHANNELS = 1
local MIDI_TARGET_BUSES = 2

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("ReaImGui extension is required.", SCRIPT_NAME, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require('imgui')('0.9')
local ctx = ImGui.CreateContext(SCRIPT_NAME)

local THEMES = {
  { name = "Blue",   accent = {48,84,110},  accent_hover = {65,112,145}, accent_active = {42,128,181}, header = {44,76,99},  header_hover = {60,103,133}, check = {82,169,226} },
  { name = "Orange", accent = {118,78,36},  accent_hover = {153,103,46}, accent_active = {201,128,38}, header = {104,70,34}, header_hover = {138,93,41},  check = {239,164,74} },
  { name = "Green",  accent = {41,89,64},   accent_hover = {55,118,85},  accent_active = {46,150,97},  header = {37,78,56},  header_hover = {52,108,78},  check = {98,205,145} },
}

local state = {
  presets = {}, preset_idx = 1,
  plugin_name = "Kontakt 7", host_track_name = "Kontakt",
  track_count = 8, start_pair = 1,
  route_scheme = ROUTE_SCHEME_SAME_TRACK,
  midi_target_mode = MIDI_TARGET_CHANNELS,
  midi_bus_sequence = false,
  tracks_per_bus = 1,
  bus_folder_mode = false,
  use_vsti_folder = true,
  vsti_folder_name = "VSTi",
  child_folder_mode = 0,
  arm_child_midi = false,
  map_input_to_send_channel = false,
  child_name_mode = 1,
  child_custom_prefix = "Instrument",
  midi_send_mode = 0,
  append_to_selected = false,
  last_status = "", theme_idx = 1, show_settings = false,
}
local SEND_MODES = {
  { label = 'Post-Fader (Post-Pan)', value = 0 },
  { label = 'Pre-Fader (Pre-FX)', value = 1 },
  { label = 'Post-FX (Pre-Fader)', value = 3 },
  { label = 'Pre-receive', value = 8 }
}
local function get_send_mode_label(val) for _, m in ipairs(SEND_MODES) do if m.value == val then return m.label end end return 'Post-Fader (Post-Pan)' end

local default_preset_defs = {
  { plugin = "Kontakt 7", host = "Kontakt", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Kontakt", host = "Kontakt", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Play", host = "Play", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Omnisphere", host = "Omnisphere", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Superior Drummer 3", host = "Superior Drummer", scheme = ROUTE_SCHEME_LEGACY_SPLIT, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "EZdrummer 3", host = "EZdrummer", scheme = ROUTE_SCHEME_LEGACY_SPLIT, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Battery 4", host = "Battery", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "SINE Player", host = "SINE", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "HALion Sonic", host = "HALion", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Falcon", host = "Falcon", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Engine", host = "Engine", scheme = ROUTE_SCHEME_SAME_TRACK, midi_target = MIDI_TARGET_CHANNELS, bus_seq = false, tracks_per_bus = 1, child_folder = 0 },
  { plugin = "Vienna Ensemble Pro", host = "Vienna Ensemble", scheme = ROUTE_SCHEME_MIDI_ONLY, midi_target = MIDI_TARGET_BUSES, bus_seq = false, tracks_per_bus = 1, bus_folder = false, child_folder = 0 },
}

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function msg(s) state.last_status = s or "" end
local function rgba(r,g,b,a) return ImGui.ColorConvertDouble4ToU32(r/255,g/255,b/255,a/255) end
local function full_width() ImGui.PushItemWidth(ctx, CONTENT_W) end
local function pop_width() ImGui.PopItemWidth(ctx) end
local function labeled_input_text(label, id, value) ImGui.Text(ctx, label) full_width() local ch; ch, value = ImGui.InputText(ctx, "##"..id, value) pop_width() return ch, value end
local function labeled_input_int(label, id, value) ImGui.Text(ctx, label) full_width() local ch; ch, value = ImGui.InputInt(ctx, "##"..id, value) pop_width() return ch, value end
local function text_wrap_block(text) local wrap = ImGui.GetCursorPosX(ctx) + CONTENT_W ImGui.PushTextWrapPos(ctx, wrap) ImGui.Text(ctx, text) ImGui.PopTextWrapPos(ctx) end

local function preset_escape(s)
  s = tostring(s or "")
  s = s:gsub("%%", "%%25")
  s = s:gsub("|", "%%7C")
  s = s:gsub(";", "%%3B")
  s = s:gsub("  ", "%%09")
  s = s:gsub("\n", "%%0A")
  s = s:gsub("\r", "%%0D")
  return s
end
local function preset_unescape(s)
  s = tostring(s or "")
  s = s:gsub("%%0D", "\r")
  s = s:gsub("%%0A", "\n")
  s = s:gsub("%%09", "  ")
  s = s:gsub("%%3B", ";")
  s = s:gsub("%%7C", "|")
  s = s:gsub("%%25", "%%")
  return s
end
local function serialize_presets(t)
  local rows = {}
  for _, p in ipairs(t) do
    rows[#rows+1] = table.concat({
      preset_escape(p.plugin or ""),
      preset_escape(p.host or ""),
      tostring(p.scheme or 1),
      tostring(p.midi_target or 1),
      p.bus_seq and "1" or "0",
      tostring(p.tracks_per_bus or 1),
      p.bus_folder and "1" or "0",
      tostring(p.child_folder or 0)
    }, "|")
  end
  return table.concat(rows, ";")
end
local function deserialize_presets(s)
  local t = {}
  s = tostring(s or "")
  for row in s:gmatch("([^;]+)") do
    local parts = {}
    for part in (row .. "|"):gmatch("(.-)|") do
      parts[#parts+1] = part
    end
    if #parts >= 4 then
      t[#t+1] = {
        plugin = trim(preset_unescape(parts[1])),
        host = trim(preset_unescape(parts[2])),
        scheme = tonumber(parts[3]) or 1,
        midi_target = tonumber(parts[4]) or 1,
        bus_seq = (tonumber(parts[5]) or 0) == 1,
        tracks_per_bus = tonumber(parts[6]) or 1,
        bus_folder = (tonumber(parts[7]) or 0) == 1,
        child_folder = tonumber(parts[8]) or 0,
      }
    end
  end
  return t
end
local function clone_default_presets() local t={} for i,p in ipairs(default_preset_defs) do t[i]={plugin=p.plugin,host=p.host,scheme=p.scheme,midi_target=p.midi_target,bus_seq=p.bus_seq,tracks_per_bus=p.tracks_per_bus,child_folder=p.child_folder} end return t end
local function sanitize_preset(p)
  p.plugin = trim(p.plugin); if p.plugin=="" then p.plugin="Kontakt 7" end
  p.host = trim(p.host); if p.host=="" then p.host=p.plugin end
  if p.scheme~=1 and p.scheme~=2 and p.scheme~=3 and p.scheme~=4 then p.scheme=1 end
  if p.midi_target~=1 and p.midi_target~=2 then p.midi_target=1 end
  p.bus_seq = not not p.bus_seq
  p.tracks_per_bus = clamp(math.floor(tonumber(p.tracks_per_bus) or 1), 1, 16)
  p.bus_folder = not not p.bus_folder
  p.child_folder = math.floor(tonumber(p.child_folder) or 0); if p.child_folder < 0 or p.child_folder > 2 then p.child_folder = 0 end
  return p
end
local function ensure_valid_presets() if #state.presets==0 then state.presets=clone_default_presets() end for i,p in ipairs(state.presets) do state.presets[i]=sanitize_preset(p) end if state.preset_idx<1 or state.preset_idx>#state.presets then state.preset_idx=1 end end
local function scheme_label(s) if s==2 then return 'Legacy' elseif s==3 then return 'MIDI-only' elseif s==4 then return 'Out-only' else return 'Pre-receive' end end
local function midi_target_label(m) return (m==2) and 'Buses' or 'Channels' end
local function preset_label(p)
  local extra = (p.midi_target==MIDI_TARGET_BUSES and p.bus_seq) and (' / '..tostring(p.tracks_per_bus)..' per bus') or ''
  if p.midi_target==MIDI_TARGET_BUSES and p.bus_seq and p.bus_folder then extra = extra .. ' / Bus folder' end
  return string.format('%s -> %s [%s / %s%s]', p.plugin or '', p.host or '', scheme_label(p.scheme), midi_target_label(p.midi_target), extra)
end
local function preset_matches_state(p)
  return p.plugin==state.plugin_name and p.host==state.host_track_name and p.scheme==state.route_scheme and p.midi_target==state.midi_target_mode and p.bus_seq==state.midi_bus_sequence and p.tracks_per_bus==state.tracks_per_bus and p.bus_folder==state.bus_folder_mode and p.child_folder==state.child_folder_mode
end
local function get_current_preset() return state.presets[state.preset_idx] end
local function sync_preset_index() ensure_valid_presets() for i,p in ipairs(state.presets) do if preset_matches_state(p) then state.preset_idx=i return end end state.preset_idx=clamp(state.preset_idx,1,#state.presets) end
local function apply_preset(index) local p=state.presets[index] if not p then return end state.preset_idx=index state.plugin_name=p.plugin state.host_track_name=p.host state.route_scheme=p.scheme state.midi_target_mode=p.midi_target state.midi_bus_sequence=p.bus_seq state.tracks_per_bus=p.tracks_per_bus state.child_folder_mode=p.child_folder; if state.route_scheme ~= 1 and state.midi_send_mode == 8 then state.midi_send_mode = 0 end end

local function save_state()
  local set = reaper.SetExtState
  set(EXT_SECTION,'plugin_name',state.plugin_name,true); set(EXT_SECTION,'host_track_name',state.host_track_name,true)
  set(EXT_SECTION,'track_count',tostring(state.track_count),true); set(EXT_SECTION,'start_pair',tostring(state.start_pair),true)
  set(EXT_SECTION,'route_scheme',tostring(state.route_scheme),true); set(EXT_SECTION,'midi_target_mode',tostring(state.midi_target_mode),true)
  set(EXT_SECTION,'midi_bus_sequence',state.midi_bus_sequence and '1' or '0',true); set(EXT_SECTION,'tracks_per_bus',tostring(state.tracks_per_bus),true); set(EXT_SECTION,'bus_folder_mode',state.bus_folder_mode and '1' or '0',true)
  set(EXT_SECTION,'use_vsti_folder',state.use_vsti_folder and '1' or '0',true); set(EXT_SECTION,'vsti_folder_name',state.vsti_folder_name,true); set(EXT_SECTION,'child_folder_mode',tostring(state.child_folder_mode),true)
  set(EXT_SECTION,'arm_child_midi',state.arm_child_midi and '1' or '0',true); set(EXT_SECTION,'map_input_to_send_channel',state.map_input_to_send_channel and '1' or '0',true)
  set(EXT_SECTION,'child_name_mode',tostring(state.child_name_mode),true); set(EXT_SECTION,'child_custom_prefix',state.child_custom_prefix,true)
  set(EXT_SECTION,'midi_send_mode',tostring(state.midi_send_mode),true)
  set(EXT_SECTION,'append_to_selected',state.append_to_selected and '1' or '0',true)
  set(EXT_SECTION,'presets',serialize_presets(state.presets),true); set(EXT_SECTION,'theme_idx',tostring(state.theme_idx),true); set(EXT_SECTION,'show_settings',state.show_settings and '1' or '0',true)
end

local function load_state()
  state.presets = deserialize_presets(reaper.GetExtState(EXT_SECTION,'presets')); if #state.presets==0 then state.presets=clone_default_presets() end; ensure_valid_presets()
  state.plugin_name = trim(reaper.GetExtState(EXT_SECTION,'plugin_name')); state.host_track_name = trim(reaper.GetExtState(EXT_SECTION,'host_track_name'))
  state.track_count = tonumber(reaper.GetExtState(EXT_SECTION,'track_count')) or 8; state.start_pair = tonumber(reaper.GetExtState(EXT_SECTION,'start_pair')) or 1
  state.route_scheme = tonumber(reaper.GetExtState(EXT_SECTION,'route_scheme')) or 1; state.midi_target_mode = tonumber(reaper.GetExtState(EXT_SECTION,'midi_target_mode')) or 1
  state.midi_bus_sequence = reaper.GetExtState(EXT_SECTION,'midi_bus_sequence')=='1'; state.tracks_per_bus = tonumber(reaper.GetExtState(EXT_SECTION,'tracks_per_bus')) or 1; state.bus_folder_mode = reaper.GetExtState(EXT_SECTION,'bus_folder_mode')=='1'
  state.use_vsti_folder = reaper.GetExtState(EXT_SECTION,'use_vsti_folder') ~= '0'
  state.vsti_folder_name = reaper.GetExtState(EXT_SECTION,'vsti_folder_name'); if state.vsti_folder_name=='' then state.vsti_folder_name='VSTi' end
  local cf_str = reaper.GetExtState(EXT_SECTION,'child_folder_mode')
  if cf_str == '' then state.child_folder_mode = (reaper.GetExtState(EXT_SECTION,'create_child_folder') == '1') and 1 or 0 else state.child_folder_mode = tonumber(cf_str) or 0 end
  state.arm_child_midi = reaper.GetExtState(EXT_SECTION,'arm_child_midi') == '1'; state.map_input_to_send_channel = reaper.GetExtState(EXT_SECTION,'map_input_to_send_channel') == '1'
  state.child_name_mode = tonumber(reaper.GetExtState(EXT_SECTION,'child_name_mode')) or 1; state.child_custom_prefix = trim(reaper.GetExtState(EXT_SECTION,'child_custom_prefix'))
  state.midi_send_mode = tonumber(reaper.GetExtState(EXT_SECTION,'midi_send_mode')) or 0
  state.append_to_selected = reaper.GetExtState(EXT_SECTION,'append_to_selected') == '1'
  state.theme_idx = clamp(tonumber(reaper.GetExtState(EXT_SECTION,'theme_idx')) or 1,1,#THEMES); state.show_settings = reaper.GetExtState(EXT_SECTION,'show_settings')=='1'
  if state.plugin_name=='' then state.plugin_name=state.presets[1].plugin end; if state.host_track_name=='' then state.host_track_name=state.presets[1].host end
  state.track_count = clamp(math.floor(state.track_count),1,128); state.start_pair = clamp(math.floor(state.start_pair),1,128)
  state.tracks_per_bus = clamp(math.floor(state.tracks_per_bus),1,16)
  if state.child_custom_prefix=='' or state.child_custom_prefix=='Custom' then state.child_custom_prefix='Instrument' end
  sync_preset_index()
end

local function get_track_name(track) local _,name = reaper.GetTrackName(track) return name or '' end
local function set_track_name(track, name) reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', name or '', true) end
local function find_tracks_by_name(name) local m={} for i=0,reaper.CountTracks(0)-1 do local tr=reaper.GetTrack(0,i) if get_track_name(tr)==name then m[#m+1]={track=tr,idx=i} end end return m end
local function track_name_exists(name) return #find_tracks_by_name(name)>0 end
local function make_unique_name(base) if not track_name_exists(base) then return base end local n=2 while true do local c=string.format('%s %d',base,n) if not track_name_exists(c) then return c end n=n+1 end end
local function get_track_index(track) return math.floor(reaper.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER'))-1 end
local function get_folder_last_child_index(folder_idx) local depth=1 local total=reaper.CountTracks(0) for i=folder_idx+1,total-1 do local tr=reaper.GetTrack(0,i) local fd=reaper.GetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH'); depth=depth+fd if depth<=0 then return i end end return total-1 end
local function make_unique_host_name(base) if not track_name_exists(base..' [VSTi]') then return base end local n=2 while true do local c=string.format('%s %d',base,n) if not track_name_exists(c..' [VSTi]') then return c end n=n+1 end end
local function insert_track_at(idx, name) reaper.InsertTrackAtIndex(idx,true) local tr=reaper.GetTrack(0,idx) if name and name~='' then set_track_name(tr,name) end return tr end
local function set_track_channels(tr,ch) reaper.SetMediaTrackInfo_Value(tr,'I_NCHAN',ch) end
local function ensure_track_channels(tr,minch) local cur=reaper.GetMediaTrackInfo_Value(tr,'I_NCHAN') or 2 if cur<minch then reaper.SetMediaTrackInfo_Value(tr,'I_NCHAN',minch) end end
local function disable_master_send(tr) reaper.SetMediaTrackInfo_Value(tr,'B_MAINSEND',0) end
local function enable_master_send(tr) reaper.SetMediaTrackInfo_Value(tr,'B_MAINSEND',1) end
local function add_instrument_fx(tr, plugin_name) return reaper.TrackFX_AddByName(tr, plugin_name, false, -1) end
local function set_send_mode(src_tr, send_idx, mode) reaper.SetTrackSendInfo_Value(src_tr,0,send_idx,'I_SENDMODE',mode) end
local function set_send_audio_none(src_tr, send_idx) reaper.SetTrackSendInfo_Value(src_tr,0,send_idx,'I_SRCCHAN',-1) end
local function set_send_audio_pair(src_tr, send_idx, pair0) reaper.SetTrackSendInfo_Value(src_tr,0,send_idx,'I_SRCCHAN',pair0*2) end
local function set_send_dst_pair(src_tr, send_idx, pair0) reaper.SetTrackSendInfo_Value(src_tr,0,send_idx,'I_DSTCHAN',pair0*2) end
local function set_receive_audio_only(src_tr, send_idx) reaper.SetTrackSendInfo_Value(src_tr,0,send_idx,'I_MIDIFLAGS',31) end

local function get_midi_assignment(local_index)
  if state.midi_target_mode == MIDI_TARGET_BUSES then
    if state.midi_bus_sequence then
      local per_bus = clamp(state.tracks_per_bus, 1, 16)
      local bus = state.start_pair + math.floor((local_index - 1) / per_bus)
      local ch = ((local_index - 1) % per_bus) + 1
      return clamp(bus, 1, 128), ch
    else
      return clamp(state.start_pair + local_index - 1, 1, 128), 0
    end
  else
    return 0, clamp(state.start_pair + local_index - 1, 1, 16)
  end
end

local function make_midi_flags_from_assignment(bus, ch)
  if state.midi_target_mode == MIDI_TARGET_BUSES then
    local flags = (clamp(bus,1,128) << 22)
    if state.midi_bus_sequence and ch and ch > 0 then flags = flags | (clamp(ch,1,16) << 5) end
    return flags
  else
    return clamp(ch,1,16) << 5
  end
end

local function get_bus_count() return clamp(state.track_count,1,128) end
local function get_bus_folder_name(bus) return string.format('MIDI Bus %03d', clamp(bus,1,128)) end
local function get_total_children_to_create()
  if state.midi_target_mode == MIDI_TARGET_BUSES and state.midi_bus_sequence then
    return get_bus_count() * clamp(state.tracks_per_bus,1,16)
  end
  return clamp(state.track_count,1,128)
end

local function get_display_index(local_index)
  if state.midi_target_mode == MIDI_TARGET_BUSES and state.midi_bus_sequence then
    local bus, ch = get_midi_assignment(local_index)
    return string.format('B%03d Ch%02d', bus, ch)
  elseif state.midi_target_mode == MIDI_TARGET_BUSES then
    local bus = select(1, get_midi_assignment(local_index))
    return string.format('B%03d', bus)
  else
    local _, ch = get_midi_assignment(local_index)
    return string.format('%02d', ch)
  end
end

local function ensure_vsti_folder(insert_idx) local m=find_tracks_by_name(state.vsti_folder_name) if #m>0 then return m[1].track, m[1].idx, false end local tr=insert_track_at(insert_idx,state.vsti_folder_name); reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',1); return tr,insert_idx,true end
local function prepare_append_to_vsti_folder(folder_idx) local last=get_folder_last_child_index(folder_idx); local tr=reaper.GetTrack(0,last); local fd=reaper.GetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH'); if fd<0 then reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',fd+1) end return last+1 end
local function open_new_folder_at(idx,name) local folder=insert_track_at(idx,make_unique_name(name)); reaper.SetMediaTrackInfo_Value(folder,'I_FOLDERDEPTH',1); return folder,idx end
local function close_folder_with_last_child(last_child_tr,levels) if not last_child_tr then return end levels=levels or 1 local fd=reaper.GetMediaTrackInfo_Value(last_child_tr,'I_FOLDERDEPTH') reaper.SetMediaTrackInfo_Value(last_child_tr,'I_FOLDERDEPTH',fd-levels) end
local function ensure_existing_folder_accepts_more(folder_tr) local last_idx=get_folder_last_child_index(get_track_index(folder_tr)); local last_tr=reaper.GetTrack(0,last_idx); local fd=reaper.GetMediaTrackInfo_Value(last_tr,'I_FOLDERDEPTH'); if fd<0 then reaper.SetMediaTrackInfo_Value(last_tr,'I_FOLDERDEPTH',fd+1) end return last_idx+1 end

local function make_child_name(host_name, local_index)
  local suffix = get_display_index(local_index)
  if state.child_name_mode == 1 then return string.format('%s %s', host_name, suffix) end
  local prefix = trim(state.child_custom_prefix); if prefix=='' then prefix='Instrument' end
  return string.format('%s %s', prefix, suffix)
end
local function make_legacy_midi_name(host_name, local_index)
  local suffix = get_display_index(local_index)
  if state.child_name_mode == 1 then return string.format('%s MIDI %s', host_name, suffix) end
  local prefix = trim(state.child_custom_prefix); if prefix=='' then prefix=host_name end
  return string.format('%s MIDI %s', prefix, suffix)
end
local function make_out_only_name(host_name, idx)
  if state.child_name_mode == 1 then return string.format('%s Out %02d', host_name, idx) end
  local prefix=trim(state.child_custom_prefix); if prefix=='' then prefix=host_name end
  return string.format('%s Out %02d', prefix, idx)
end
local function make_legacy_audio_name(host_name, idx)
  if state.child_name_mode == 1 then return string.format('%s Outs %02d', host_name, idx) end
  local prefix=trim(state.child_custom_prefix); if prefix=='' then prefix=host_name end
  return string.format('%s Outs %02d', prefix, idx)
end

local function apply_child_record_input(child_tr, local_index)
  local recinput = MIDI_INPUT_ALL_ALL_CHANNELS
  if state.map_input_to_send_channel and state.midi_target_mode == MIDI_TARGET_CHANNELS then
    local _, ch = get_midi_assignment(local_index)
    recinput = MIDI_INPUT_ALL_CH1_BASE + clamp(ch,1,16)
  end
  reaper.SetMediaTrackInfo_Value(child_tr,'I_RECINPUT',recinput)
end

local function find_unique_host_track()
  local host_name = trim(state.host_track_name)
  if host_name=='' then return nil, 'Host track name is empty.' end
  local matches = find_tracks_by_name(host_name..' [VSTi]')
  if #matches==0 then matches = find_tracks_by_name(host_name) end
  if #matches==0 then return nil, "Host not found: '"..host_name.."' or '"..host_name.." [VSTi]'" end
  if #matches>1 then return nil, 'Multiple hosts found with the same name. Please rename duplicates first.' end
  return matches[1].track, nil
end

local function same_track_name_matches_host(host_base, name)
  local esc_host = host_base:gsub('([^%w])','%%%1'); local esc_prefix = trim(state.child_custom_prefix):gsub('([^%w])','%%%1')
  if name:match('^'..esc_host..' .+$') or name:match('^'..esc_host..' Instruments$') then return true end
  if esc_prefix~='' and (name:match('^'..esc_prefix..' .+$') or name:match('^'..esc_prefix..' Instruments$')) then return true end
  return false
end
local function legacy_name_matches_host(host_base, name)
  local esc_host = host_base:gsub('([^%w])','%%%1'); local esc_prefix = trim(state.child_custom_prefix):gsub('([^%w])','%%%1')
  if name:match('^'..esc_host..' MIDI .+$') or name:match('^'..esc_host..' MIDI$') then return true end
  if name:match('^'..esc_host..' Outs %d+$') or name:match('^'..esc_host..' Outs$') then return true end
  if esc_prefix~='' and (name:match('^'..esc_prefix..' MIDI .+$') or name:match('^'..esc_prefix..' MIDI$') or name:match('^'..esc_prefix..' Outs %d+$') or name:match('^'..esc_prefix..' Outs$')) then return true end
  return false
end
local function midi_only_name_matches_host(host_base, name)
  local esc_host = host_base:gsub('([^%w])','%%%1'); local esc_prefix = trim(state.child_custom_prefix):gsub('([^%w])','%%%1')
  if name:match('^'..esc_host..' MIDI .+$') or name:match('^'..esc_host..' MIDI$') then return true end
  if esc_prefix~='' and (name:match('^'..esc_prefix..' MIDI .+$') or name:match('^'..esc_prefix..' MIDI$')) then return true end
  return false
end
local function out_only_name_matches_host(host_base, name)
  local esc_host = host_base:gsub('([^%w])','%%%1'); local esc_prefix = trim(state.child_custom_prefix):gsub('([^%w])','%%%1')
  if name:match('^'..esc_host..' Out %d+$') or name:match('^'..esc_host..' Outs$') then return true end
  if esc_prefix~='' and (name:match('^'..esc_prefix..' Out %d+$') or name:match('^'..esc_prefix..' Outs$')) then return true end
  return false
end
local function get_append_insert_index(host_tr)
  local host_idx=get_track_index(host_tr); local total=reaper.CountTracks(0); local base=trim(state.host_track_name); local last_idx=host_idx
  for i=host_idx+1,total-1 do local tr=reaper.GetTrack(0,i); local name=get_track_name(tr); local matched=false
    if state.route_scheme==ROUTE_SCHEME_LEGACY_SPLIT then matched=legacy_name_matches_host(base,name) elseif state.route_scheme==ROUTE_SCHEME_MIDI_ONLY then matched=midi_only_name_matches_host(base,name) elseif state.route_scheme==ROUTE_SCHEME_OUT_ONLY then matched=out_only_name_matches_host(base,name) else matched=same_track_name_matches_host(base,name) end
    if matched then last_idx=i else break end
  end
  return last_idx+1
end
local function prepare_folder_insertion(host_tr, unique_base_name, folder_suffix, append_mode, folder_mode)
  local f_mode = folder_mode or state.child_folder_mode
  if f_mode == 0 then
    return get_append_insert_index(host_tr), false
  elseif f_mode == 2 then
    if not append_mode then
      reaper.SetMediaTrackInfo_Value(host_tr, 'I_FOLDERDEPTH', 1)
      return get_track_index(host_tr) + 1, true
    else
      return ensure_existing_folder_accepts_more(host_tr), true
    end
  elseif f_mode == 1 then
    local target_name = unique_base_name .. folder_suffix
    if append_mode then
      local m = find_tracks_by_name(target_name)
      if #m > 0 then return ensure_existing_folder_accepts_more(m[1].track), true end
    end
    local idx = get_append_insert_index(host_tr)
    local f, f_idx = open_new_folder_at(idx, target_name)
    return f_idx + 1, true
  end
end


local function create_midi_send(child_tr, host_tr, local_index, sendmode)
  local bus, ch = get_midi_assignment(local_index)
  local send_to_host = reaper.CreateTrackSend(child_tr, host_tr)
  set_send_mode(child_tr, send_to_host, sendmode)
  set_send_audio_none(child_tr, send_to_host)
  reaper.SetTrackSendInfo_Value(child_tr,0,send_to_host,'I_MIDIFLAGS', make_midi_flags_from_assignment(bus, ch))
end

local function append_children_same_track(host_tr, unique_base_name, append_mode)
  local count = get_total_children_to_create()
  local max_pair = count
  ensure_track_channels(host_tr, max_pair * 2)
  local insert_idx, needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' Instruments', append_mode, state.child_folder_mode)
  local last_child_tr=nil
  for i=1,count do
    local child_tr = insert_track_at(insert_idx + (i - 1), make_child_name(unique_base_name, i))
    last_child_tr=child_tr; set_track_channels(child_tr,2); enable_master_send(child_tr)
    if state.arm_child_midi then reaper.SetMediaTrackInfo_Value(child_tr,'I_RECARM',1); reaper.SetMediaTrackInfo_Value(child_tr,'I_RECMON',1) end
    apply_child_record_input(child_tr,i); create_midi_send(child_tr, host_tr, i, state.midi_send_mode)
    local send_to_child = reaper.CreateTrackSend(host_tr, child_tr)
    set_send_audio_pair(host_tr, send_to_child, i - 1); set_send_dst_pair(host_tr, send_to_child, 0); set_receive_audio_only(host_tr, send_to_child)
  end
  if needs_close and last_child_tr then close_folder_with_last_child(last_child_tr,1) end
end

local function append_children_legacy_split(host_tr, unique_base_name, append_mode)
  local count = get_total_children_to_create()
  ensure_track_channels(host_tr, count * 2)
  if state.child_folder_mode > 0 then
    local midi_insert_idx, midi_needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' MIDI', append_mode, state.child_folder_mode)
    local last_midi_tr=nil
    for i=1,count do
      local midi_tr = insert_track_at(midi_insert_idx + (i - 1), make_legacy_midi_name(unique_base_name, i))
      last_midi_tr=midi_tr; set_track_channels(midi_tr,2); enable_master_send(midi_tr)
      if state.arm_child_midi then reaper.SetMediaTrackInfo_Value(midi_tr,'I_RECARM',1); reaper.SetMediaTrackInfo_Value(midi_tr,'I_RECMON',1) end
      apply_child_record_input(midi_tr,i); create_midi_send(midi_tr, host_tr, i, state.midi_send_mode)
    end
    if midi_needs_close and last_midi_tr then close_folder_with_last_child(last_midi_tr, 1) end

    local outs_insert_idx, outs_needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' Outs', append_mode, 1)
    local last_outs_tr=nil
    for i=1,count do
      local outs_tr=insert_track_at(outs_insert_idx + (i - 1), make_legacy_audio_name(unique_base_name, i))
      last_outs_tr=outs_tr; set_track_channels(outs_tr,2); enable_master_send(outs_tr)
      local send_to_outs = reaper.CreateTrackSend(host_tr, outs_tr)
      set_send_audio_pair(host_tr, send_to_outs, i - 1); set_send_dst_pair(host_tr, send_to_outs, 0); set_receive_audio_only(host_tr, send_to_outs)
    end
    if outs_needs_close and last_outs_tr then close_folder_with_last_child(last_outs_tr, 1) end
    return
  end
  local insert_idx = get_append_insert_index(host_tr)
  for i=1,count do
    local midi_tr=insert_track_at(insert_idx + ((i - 1) * 2), make_legacy_midi_name(unique_base_name, i))
    local outs_tr=insert_track_at(insert_idx + ((i - 1) * 2) + 1, make_legacy_audio_name(unique_base_name, i))
    set_track_channels(midi_tr,2); set_track_channels(outs_tr,2); enable_master_send(midi_tr); enable_master_send(outs_tr)
    if state.arm_child_midi then reaper.SetMediaTrackInfo_Value(midi_tr,'I_RECARM',1); reaper.SetMediaTrackInfo_Value(midi_tr,'I_RECMON',1) end
    apply_child_record_input(midi_tr,i); create_midi_send(midi_tr, host_tr, i, state.midi_send_mode)
    local send_to_outs = reaper.CreateTrackSend(host_tr, outs_tr)
    set_send_audio_pair(host_tr, send_to_outs, i - 1); set_send_dst_pair(host_tr, send_to_outs, 0); set_receive_audio_only(host_tr, send_to_outs)
  end
end

local function append_children_midi_bus_foldered(host_tr, unique_base_name, append_mode)
  local bus_count = get_bus_count()
  local per_bus = clamp(state.tracks_per_bus, 1, 16)
  local running_idx, needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' MIDI', append_mode, state.child_folder_mode)
  local last_top_child = nil
  for bus_ofs = 0, bus_count - 1 do
    local bus_num = clamp(state.start_pair + bus_ofs, 1, 128)
    local bus_folder = insert_track_at(running_idx, get_bus_folder_name(bus_num))
    reaper.SetMediaTrackInfo_Value(bus_folder, 'I_FOLDERDEPTH', 1)
    running_idx = running_idx + 1
    for ch = 1, per_bus do
      local local_index = bus_ofs * per_bus + ch
      local child_tr = insert_track_at(running_idx, make_legacy_midi_name(unique_base_name, local_index))
      set_track_channels(child_tr,2)
      disable_master_send(child_tr)
      if state.arm_child_midi then reaper.SetMediaTrackInfo_Value(child_tr,'I_RECARM',1); reaper.SetMediaTrackInfo_Value(child_tr,'I_RECMON',1) end
      apply_child_record_input(child_tr,local_index)
      create_midi_send(child_tr, host_tr, local_index, state.midi_send_mode)
      running_idx = running_idx + 1
      last_top_child = child_tr
      if ch == per_bus then close_folder_with_last_child(child_tr, 1) end
    end
  end
  if needs_close and last_top_child then close_folder_with_last_child(last_top_child, 1) end
end

local function append_children_midi_only(host_tr, unique_base_name, append_mode)
  if state.midi_target_mode == MIDI_TARGET_BUSES and state.midi_bus_sequence and state.bus_folder_mode then
    append_children_midi_bus_foldered(host_tr, unique_base_name, append_mode)
    return
  end
  local count = get_total_children_to_create()
  local insert_idx, needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' MIDI', append_mode, state.child_folder_mode)
  local last_child_tr=nil
  for i=1,count do
    local child_tr = insert_track_at(insert_idx + (i - 1), make_legacy_midi_name(unique_base_name, i))
    last_child_tr=child_tr; set_track_channels(child_tr,2); disable_master_send(child_tr)
    if state.arm_child_midi then reaper.SetMediaTrackInfo_Value(child_tr,'I_RECARM',1); reaper.SetMediaTrackInfo_Value(child_tr,'I_RECMON',1) end
    apply_child_record_input(child_tr,i); create_midi_send(child_tr, host_tr, i, state.midi_send_mode)
  end
  if needs_close and last_child_tr then close_folder_with_last_child(last_child_tr,1) end
end

local function append_children_out_only(host_tr, unique_base_name, append_mode)
  local count = get_total_children_to_create()
  ensure_track_channels(host_tr, count * 2)
  local insert_idx, needs_close = prepare_folder_insertion(host_tr, unique_base_name, ' Outs', append_mode, state.child_folder_mode)
  local last_child_tr = nil
  for i=1,count do
    local child_tr = insert_track_at(insert_idx + (i - 1), make_out_only_name(unique_base_name, i))
    last_child_tr = child_tr; set_track_channels(child_tr,2); enable_master_send(child_tr)
    local send_to_child = reaper.CreateTrackSend(host_tr, child_tr)
    set_send_audio_pair(host_tr, send_to_child, i - 1); set_send_dst_pair(host_tr, send_to_child, 0); set_receive_audio_only(host_tr, send_to_child)
  end
  if needs_close and last_child_tr then close_folder_with_last_child(last_child_tr, 1) end
end
local function append_children_to_host(host_tr, unique_base_name, append_mode)
  if state.route_scheme==ROUTE_SCHEME_LEGACY_SPLIT then append_children_legacy_split(host_tr, unique_base_name, append_mode)
  elseif state.route_scheme==ROUTE_SCHEME_MIDI_ONLY then append_children_midi_only(host_tr, unique_base_name, append_mode)
  elseif state.route_scheme==ROUTE_SCHEME_OUT_ONLY then append_children_out_only(host_tr, unique_base_name, append_mode)
  else append_children_same_track(host_tr, unique_base_name, append_mode) end
end

local function create_fish()
  local plugin_name = trim(state.plugin_name); local host_base_name = trim(state.host_track_name)
  if plugin_name=='' then reaper.MB('Please enter a VSTi name.', SCRIPT_NAME, 0) return end; if host_base_name=='' then host_base_name=plugin_name end
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  local ok, err = pcall(function()
    local insert_idx = reaper.CountTracks(0); local host_idx = insert_idx; local folder_track, folder_idx = nil, -1
    local use_vsti_folder_now = state.use_vsti_folder and not (state.route_scheme == ROUTE_SCHEME_MIDI_ONLY)
    if use_vsti_folder_now then folder_track, folder_idx = ensure_vsti_folder(insert_idx); if folder_track then host_idx = prepare_append_to_vsti_folder(folder_idx) end end
    local unique_base_name = make_unique_host_name(host_base_name)
    local host_tr = insert_track_at(host_idx, unique_base_name .. ' [VSTi]')
    if state.route_scheme ~= ROUTE_SCHEME_MIDI_ONLY then
      set_track_channels(host_tr, math.max(2, get_total_children_to_create() * 2))
      disable_master_send(host_tr)
    else
      enable_master_send(host_tr)
    end
    local fxidx = add_instrument_fx(host_tr, plugin_name); if fxidx < 0 then error('Could not insert FX: ' .. plugin_name) end
    if folder_track then reaper.SetMediaTrackInfo_Value(host_tr, 'I_FOLDERDEPTH', -1) end
    append_children_to_host(host_tr, unique_base_name, false)
    reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
    msg(string.format("Created host '%s [VSTi]' with %d child units using %s / %s.", unique_base_name, get_total_children_to_create(), scheme_label(state.route_scheme), midi_target_label(state.midi_target_mode)))
    save_state()
  end)
  reaper.PreventUIRefresh(-1)
  if ok then reaper.Undo_EndBlock('Create Multi-VSTi fish', -1) else reaper.Undo_EndBlock('Create Multi-VSTi fish (failed)', -1); reaper.MB(tostring(err), SCRIPT_NAME, 0); msg('Error: '..tostring(err)) end
end

local function append_to_host()
  local host_tr
  if state.append_to_selected then
    local sel_count = reaper.CountSelectedTracks(0)
    if sel_count == 0 then reaper.MB('No track selected. Please select a host track.', SCRIPT_NAME, 0); return end
    if sel_count > 1 then reaper.MB('Multiple tracks selected. Please select exactly one host track.', SCRIPT_NAME, 0); return end
    host_tr = reaper.GetSelectedTrack(0, 0)
  else
    local err; host_tr, err = find_unique_host_track(); if not host_tr then reaper.MB(err, SCRIPT_NAME, 0); msg(err); return end
  end
  local host_base = trim(state.host_track_name)
  if state.append_to_selected then
    local _, raw_name = reaper.GetTrackName(host_tr)
    host_base = (raw_name or ''):gsub('%s*%[VSTi%]%s*$',''):match('^%s*(.-)%s*$') or host_base
  end
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  local ok, append_err = pcall(function()
    append_children_to_host(host_tr, host_base, true)
    reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
    msg(string.format("Appended %d child units to '%s' using %s / %s.", get_total_children_to_create(), host_base, scheme_label(state.route_scheme), midi_target_label(state.midi_target_mode)))
    save_state()
  end)
  reaper.PreventUIRefresh(-1)
  if ok then reaper.Undo_EndBlock('Append children to Multi-VSTi fish', -1) else reaper.Undo_EndBlock('Append children to Multi-VSTi fish (failed)', -1); reaper.MB(tostring(append_err), SCRIPT_NAME, 0); msg('Error: '..tostring(append_err)) end
end

local function save_current_as_preset()
  local plugin = trim(state.plugin_name); local host = trim(state.host_track_name); if plugin=='' then return end; if host=='' then host=plugin end
  for i,p in ipairs(state.presets) do if preset_matches_state(p) then apply_preset(i); msg('Preset already exists.'); save_state(); return end end
  table.insert(state.presets, sanitize_preset({plugin=plugin,host=host,scheme=state.route_scheme,midi_target=state.midi_target_mode,bus_seq=state.midi_bus_sequence,tracks_per_bus=state.tracks_per_bus,bus_folder=state.bus_folder_mode,child_folder=state.child_folder_mode}))
  state.preset_idx=#state.presets; msg('Preset added.'); save_state()
end
local function update_current_preset() local p=get_current_preset() if not p then return end p.plugin=trim(state.plugin_name); p.host=trim(state.host_track_name); p.scheme=state.route_scheme; p.midi_target=state.midi_target_mode; p.bus_seq=state.midi_bus_sequence; p.tracks_per_bus=state.tracks_per_bus; p.bus_folder=state.bus_folder_mode; p.child_folder=state.child_folder_mode; sanitize_preset(p); sync_preset_index(); msg('Preset updated.'); save_state() end
local function delete_selected_preset() if #state.presets==0 then return end table.remove(state.presets,state.preset_idx); ensure_valid_presets(); state.preset_idx=clamp(state.preset_idx,1,#state.presets); apply_preset(state.preset_idx); msg('Preset deleted.'); save_state() end
local function reset_defaults() state.presets=clone_default_presets(); apply_preset(1); state.track_count=8; state.start_pair=1; state.route_scheme=ROUTE_SCHEME_SAME_TRACK; state.midi_target_mode=MIDI_TARGET_CHANNELS; state.midi_bus_sequence=false; state.tracks_per_bus=1; state.bus_folder_mode=false; state.use_vsti_folder=true; state.child_folder_mode=0; state.arm_child_midi=false; state.map_input_to_send_channel=false; state.child_name_mode=1; state.child_custom_prefix='Instrument'; state.midi_send_mode=0; state.theme_idx=1; state.show_settings=false; msg('Defaults restored.'); save_state() end

local function draw_theme_buttons() for i,th in ipairs(THEMES) do if ImGui.Button(ctx, th.name .. '##theme' .. i, 165, 0) then state.theme_idx=i save_state() end if i<#THEMES then ImGui.SameLine(ctx) end end end
local function draw_preset_block() ImGui.SeparatorText(ctx,'Preset'); sync_preset_index(); full_width(); local current=get_current_preset() or sanitize_preset({plugin=state.plugin_name,host=state.host_track_name,scheme=state.route_scheme,midi_target=state.midi_target_mode,bus_seq=state.midi_bus_sequence,tracks_per_bus=state.tracks_per_bus}); if ImGui.BeginCombo(ctx,'##preset_combo_unique_v050',preset_label(current)) then for i,p in ipairs(state.presets) do local sel=(i==state.preset_idx) if ImGui.Selectable(ctx,preset_label(p)..'##preset_item_v050_'..i,sel) then apply_preset(i); save_state() end if sel then ImGui.SetItemDefaultFocus(ctx) end end ImGui.EndCombo(ctx) end pop_width(); if ImGui.Button(ctx,'Save as new##preset_add',BTN4_W,0) then save_current_as_preset() end ImGui.SameLine(ctx); if ImGui.Button(ctx,'Update##preset_update',BTN4_W,0) then update_current_preset() end ImGui.SameLine(ctx); if ImGui.Button(ctx,'Delete##preset_delete',BTN4_W,0) then delete_selected_preset() end ImGui.SameLine(ctx); if ImGui.Button(ctx,'Reset defaults##preset_reset',BTN4_W,0) then reset_defaults() end end
local function draw_compact_scheme_row() ImGui.SeparatorText(ctx,'Scheme'); if ImGui.RadioButton(ctx,'Pre-receive##compact_scheme_same',state.route_scheme==1) then state.route_scheme=1 sync_preset_index() save_state() end ImGui.SameLine(ctx); if ImGui.RadioButton(ctx,'Legacy##compact_scheme_legacy',state.route_scheme==2) then state.route_scheme=2; if state.midi_send_mode==8 then state.midi_send_mode=0 end; sync_preset_index() save_state() end ImGui.SameLine(ctx); if ImGui.RadioButton(ctx,'MIDI-only##compact_scheme_midi_only',state.route_scheme==3) then state.route_scheme=3; if state.midi_send_mode==8 then state.midi_send_mode=0 end; sync_preset_index() save_state() end ImGui.SameLine(ctx); if ImGui.RadioButton(ctx,'Out-only##compact_scheme_out_only',state.route_scheme==4) then state.route_scheme=4; if state.midi_send_mode==8 then state.midi_send_mode=0 end; sync_preset_index() save_state() end end
local function draw_action_block()
  ImGui.SeparatorText(ctx,'Actions')
  local label = (state.midi_target_mode==MIDI_TARGET_BUSES and state.midi_bus_sequence) and 'Bus count' or 'Track count'
  local changed
  changed, state.track_count = labeled_input_int(label, 'track_count', state.track_count); if changed then state.track_count=clamp(math.floor(state.track_count),1,128) sync_preset_index() save_state() end
  if state.midi_target_mode==MIDI_TARGET_BUSES and state.midi_bus_sequence then changed, state.tracks_per_bus = labeled_input_int('Tracks per bus', 'tracks_per_bus', state.tracks_per_bus); if changed then state.tracks_per_bus=clamp(math.floor(state.tracks_per_bus),1,16) sync_preset_index() save_state() end end
  changed, state.start_pair = labeled_input_int((state.midi_target_mode==MIDI_TARGET_BUSES) and 'Start bus' or 'Start index', 'start_pair', state.start_pair); if changed then state.start_pair=clamp(math.floor(state.start_pair),1,128) save_state() end
  if ImGui.Button(ctx,'Create routing fish##create',165,0) then create_fish() end; ImGui.SameLine(ctx); if ImGui.Button(ctx,'Append to host##append',165,0) then append_to_host() end; ImGui.SameLine(ctx); if ImGui.Button(ctx,state.show_settings and 'Settings ▲##toggle' or 'Settings ▼##toggle',165,0) then state.show_settings=not state.show_settings save_state() end
  local changed
  changed, state.append_to_selected = ImGui.Checkbox(ctx, 'Append to selected track (ignore name matching)', state.append_to_selected); if changed then save_state() end
end

local function draw_settings_panel()
  if not state.show_settings then return end
  if ImGui.CollapsingHeader(ctx,'Instrument', ImGui.TreeNodeFlags_DefaultOpen) then
    local changed
    changed, state.plugin_name = labeled_input_text('Plugin name','plugin_name',state.plugin_name); if changed then sync_preset_index() save_state() end
    changed, state.host_track_name = labeled_input_text('Host track name','host_track_name',state.host_track_name); if changed then sync_preset_index() save_state() end
    local disable_vsti_folder = (state.route_scheme == ROUTE_SCHEME_MIDI_ONLY)
    ImGui.BeginDisabled(ctx, disable_vsti_folder)
    changed, state.use_vsti_folder = ImGui.Checkbox(ctx, "Put host into folder", state.use_vsti_folder)
    ImGui.SameLine(ctx)
    ImGui.PushItemWidth(ctx, 120)
    local changed_vsti_name; changed_vsti_name, state.vsti_folder_name = ImGui.InputText(ctx, "##vsti_folder_name", state.vsti_folder_name)
    ImGui.PopItemWidth(ctx)
    ImGui.EndDisabled(ctx)
    if (changed or changed_vsti_name) and not disable_vsti_folder then save_state() end
    if state.route_scheme == ROUTE_SCHEME_MIDI_ONLY then ImGui.TextDisabled(ctx, 'Unavailable in MIDI-only mode: the host is inserted at parent level.') end
  end
  if ImGui.CollapsingHeader(ctx,'Children', ImGui.TreeNodeFlags_DefaultOpen) then
    local is_out_only = (state.route_scheme == ROUTE_SCHEME_OUT_ONLY)
    local is_pre_receive = (state.route_scheme == ROUTE_SCHEME_SAME_TRACK)
    ImGui.BeginDisabled(ctx, is_out_only)
    ImGui.TextDisabled(ctx,'MIDI target')
    if ImGui.RadioButton(ctx,'Channels##target_channels',state.midi_target_mode==MIDI_TARGET_CHANNELS) then state.midi_target_mode=MIDI_TARGET_CHANNELS sync_preset_index() save_state() end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx,'Buses##target_buses',state.midi_target_mode==MIDI_TARGET_BUSES) then state.midi_target_mode=MIDI_TARGET_BUSES sync_preset_index() save_state() end
    if state.midi_target_mode == MIDI_TARGET_BUSES then
      ImGui.SameLine(ctx)
      local changed
      changed, state.midi_bus_sequence = ImGui.Checkbox(ctx, 'Sequence MIDI channels', state.midi_bus_sequence)
      if changed then sync_preset_index() save_state() end
      if state.midi_bus_sequence then
        changed, state.bus_folder_mode = ImGui.Checkbox(ctx, 'Put sequenced MIDI channels into MIDI Buses folder(s)', state.bus_folder_mode)
        if changed then sync_preset_index() save_state() end
      else
        state.bus_folder_mode = false
      end
    else
      state.bus_folder_mode = false
    end
    local changed
    ImGui.TextDisabled(ctx, 'MIDI Send Mode')
    full_width()
    if is_pre_receive then state.midi_send_mode = 8 end
    ImGui.BeginDisabled(ctx, is_pre_receive or is_out_only)
    if ImGui.BeginCombo(ctx, '##midi_send_mode', get_send_mode_label(state.midi_send_mode)) then
      for _, m in ipairs(SEND_MODES) do
        local sel = (m.value == state.midi_send_mode)
        if ImGui.Selectable(ctx, m.label .. '##sm_' .. m.value, sel) then
          state.midi_send_mode = m.value; save_state()
        end
        if sel then ImGui.SetItemDefaultFocus(ctx) end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.EndDisabled(ctx)
    pop_width()
    ImGui.EndDisabled(ctx)

    ImGui.TextDisabled(ctx, 'Child Folder Location')
    if (is_pre_receive or is_out_only) and state.child_folder_mode == 2 then state.child_folder_mode = 1; save_state() end
    if ImGui.RadioButton(ctx,'No Folder##cf0',state.child_folder_mode==0) then state.child_folder_mode=0; sync_preset_index(); save_state() end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx,'Parent Folder##cf1',state.child_folder_mode==1) then state.child_folder_mode=1; sync_preset_index(); save_state() end
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, is_pre_receive or is_out_only)
    if ImGui.RadioButton(ctx,'Host-Parent##cf2',state.child_folder_mode==2) then state.child_folder_mode=2; sync_preset_index(); save_state() end
    ImGui.EndDisabled(ctx)

    ImGui.BeginDisabled(ctx, is_out_only)
    ImGui.TextDisabled(ctx, 'MIDI Devices')
    changed, state.arm_child_midi = ImGui.Checkbox(ctx,'Arm MIDI input tracks + monitor',state.arm_child_midi); if changed then save_state() end
    changed, state.map_input_to_send_channel = ImGui.Checkbox(ctx,'Map all hardware MIDI devices to send channel',state.map_input_to_send_channel); if changed then save_state() end
    ImGui.EndDisabled(ctx)

    ImGui.TextDisabled(ctx, 'Naming')
    if ImGui.RadioButton(ctx,'HostName##name_host',state.child_name_mode==1) then state.child_name_mode=1 save_state() end; ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx,'Custom##name_custom',state.child_name_mode==4) then state.child_name_mode=4 save_state() end
    if state.child_name_mode==4 then
      ImGui.SameLine(ctx)
      ImGui.PushItemWidth(ctx, 120)
      local changed
      changed, state.child_custom_prefix = ImGui.InputText(ctx,'##child_prefix',state.child_custom_prefix); if changed then save_state() end
      ImGui.PopItemWidth(ctx)
    end
  end
  if ImGui.CollapsingHeader(ctx,'Theme') then draw_theme_buttons() end
  if ImGui.CollapsingHeader(ctx,'Help') then
    text_wrap_block('Pre-receive: one child track per part, MIDI send plus audio return on the same track.')
    text_wrap_block('Legacy: separate MIDI input tracks and separate Outs return tracks.')
    text_wrap_block("MIDI-only: creates MIDI children only, with no audio returns on the child tracks. The host track keeps its master send enabled so plugin audio can still be heard.")
    text_wrap_block("Out-only: creates audio return tracks only (no MIDI). Use with instruments that do not require MIDI routing from REAPER, or to add extra return tracks to an existing host.")
    text_wrap_block("MIDI target 'Channels' uses channels 1..16.")
    text_wrap_block("MIDI target 'Buses' uses REAPER MIDI buses. REAPER routing supports up to 128 buses, so this mode now supports 1..128 buses. Bus sends keep MIDI source as All and set the destination bus/channel on the send.")
    text_wrap_block("If 'Sequence MIDI channels inside each bus' is enabled, Track count becomes Bus count and an extra 'Tracks per bus' field appears directly below it. The script then creates BusCount x TracksPerBus children, assigning Ch1..ChN inside each bus.")
    text_wrap_block("If 'Put sequenced MIDI channels into MIDI Buses folder(s)' is enabled, the script creates a folder per bus (for example MIDI Bus 001) and puts that bus's MIDI channel tracks inside it. This bus-folder structure can itself live inside the host folder when 'Child inside parent folder' is on, or exist as a separate sibling structure when it is off.")
    text_wrap_block("Start bus 1 maps to B1. Without channel sequencing, one child is created per bus and MIDI goes to that bus with channel left as All.")
    text_wrap_block("'Map all hardware MIDI devices to send channel' affects channel mode only.")
    text_wrap_block('Append reuses matching folder structures under an existing host when the current scheme uses folders.')
    text_wrap_block("For Vienna Ensemble / VST3 MIDI buses, enable plugin I/O option 'Map VST3 MIDI buses to REAPER MIDI buses' manually if needed.")
  end
end

local function draw_ui()
  ImGui.SetNextWindowSize(ctx, WINDOW_W, WINDOW_H, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx, WINDOW_MIN_W, WINDOW_MIN_H, WINDOW_MAX_W, WINDOW_MAX_H)
  local th=THEMES[state.theme_idx] or THEMES[1]
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, rgba(28,30,34,255)); ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, rgba(33,36,41,255)); ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, rgba(32,35,40,252)); ImGui.PushStyleColor(ctx, ImGui.Col_Border, rgba(67,73,84,255)); ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, rgba(37,40,46,255)); ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, rgba(th.header_hover[1],th.header_hover[2],th.header_hover[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, rgba(th.accent_active[1],th.accent_active[2],th.accent_active[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, rgba(24,26,30,255)); ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, rgba(33,36,41,255)); ImGui.PushStyleColor(ctx, ImGui.Col_Button, rgba(th.accent[1],th.accent[2],th.accent[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, rgba(th.accent_hover[1],th.accent_hover[2],th.accent_hover[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, rgba(th.accent_active[1],th.accent_active[2],th.accent_active[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_Header, rgba(th.header[1],th.header[2],th.header[3],160)); ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, rgba(th.header_hover[1],th.header_hover[2],th.header_hover[3],185)); ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, rgba(th.header_hover[1],th.header_hover[2],th.header_hover[3],205)); ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, rgba(th.check[1],th.check[2],th.check[3],255)); ImGui.PushStyleColor(ctx, ImGui.Col_Separator, rgba(63,69,78,255)); ImGui.PushStyleColor(ctx, ImGui.Col_Text, rgba(222,226,230,255)); ImGui.PushStyleColor(ctx, ImGui.Col_TextDisabled, rgba(140,146,156,255))
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 8.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 6.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarRounding, 8.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10.0, 10.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8.0, 5.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8.0, 6.0); ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing, 6.0, 4.0)
  local visible, open = ImGui.Begin(ctx, SCRIPT_NAME .. '##main_window_v050', true)
  if visible then
    ensure_valid_presets(); ImGui.Text(ctx,'REAPER 7.78+ multi-out VSTi builder'); ImGui.TextDisabled(ctx,'Preset-first compact mode')
    draw_preset_block(); draw_compact_scheme_row(); draw_action_block(); ImGui.Dummy(ctx,0,8); draw_settings_panel(); ImGui.SeparatorText(ctx,'Status'); ImGui.Text(ctx, state.last_status ~= '' and state.last_status or 'Ready'); ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx,8); ImGui.PopStyleColor(ctx,19)
  if open then reaper.defer(draw_ui) else save_state() end
end

load_state(); reaper.defer(draw_ui)
