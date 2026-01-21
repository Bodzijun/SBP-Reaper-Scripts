-- ReaSFX_Sampler_v35.lua
-- v1.35: Insert Button Restored, Centered UI, Fixed Field Widths, Bigger XY
local r = reaper

-- === CONFIG === --
local CONFIG = {
    group_threshold = 0.5,
    global_key = 75,       -- 'K'
    base_note = 36,
    num_keys = 30,
    slot_width = 50,
    layer_height = 6
}

if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("Please install ReaImGui via ReaPack", "Error", 0)
    return
end

local has_js_api = r.APIExists('JS_VKeys_GetState')
local has_sws = r.APIExists('Xen_StartSourcePreview')

-- ANTI-DING
if has_js_api then r.JS_VKeys_Intercept(CONFIG.global_key, 1) end
function ReleaseKeys() if has_js_api then r.JS_VKeys_Intercept(CONFIG.global_key, -1) end end
r.atexit(ReleaseKeys)

-- =========================================================
-- MODULE: CORE
-- =========================================================
local Core = {}
Core.Project = {
    keys = {}, 
    selected_note = 60,
    selected_set = 1,
    multi_sets = {},
    use_snap_align = false,
    placement_mode = 1,
    trigger_mode = 0,
    group_thresh = 0.5,
    
    g_rnd_vol = 0.0, g_rnd_pitch = 0.0, g_rnd_pan = 0.0,
    g_rnd_pos = 0.0, g_rnd_offset = 0.0, g_rnd_fade = 0.0, g_rnd_len = 0.0
}
Core.LastLog = "Engine Ready."
Core.IsPreviewing = false
Core.PreviewID = nil
Core.KeyState = { held = false, start_pos = 0 }
Core.Input = { was_down = false }

function Core.Log(msg) Core.LastLog = msg end

function Core.InitKey(note)
    if not Core.Project.keys[note] then
        Core.Project.keys[note] = { sets = {} }
        for i=1, 16 do
            Core.Project.keys[note].sets[i] = { 
                events = {}, last_idx = -1, trigger_on = 0,
                rnd_vol = 0.0, rnd_pitch = 0.0, rnd_pan = 0.0,
                rnd_pos = 0.0, rnd_offset = 0.0, rnd_fade = 0.0, rnd_len = 0.0,
                xy_x = 0.5, xy_y = 0.5,
                seq_count = 4, seq_rate = 0.150, 
                seq_len = 0.100, seq_fade = 0.020,
                seq_mode = 1 -- 0:First, 1:Random, 2:Stitch
            }
        end
    end
    return Core.Project.keys[note]
end
Core.InitKey(Core.Project.selected_note)

-- === SMART MARKERS === --
function Core.ParseSmartMarkers(item)
    local take = r.GetActiveTake(item)
    if not take then return nil end
    local count = r.GetNumTakeMarkers(take)
    if count == 0 then return nil end
    local markers = { S=nil, L=nil, E=nil, R=nil }
    local found = false
    for i=0, count-1 do
        local retval, pos, name, color = r.GetTakeMarker(take, i)
        if name and type(name) == 'string' then
            local n = name:upper()
            if n == "S" then markers.S = pos; found=true
            elseif n == "L" then markers.L = pos; found=true
            elseif n == "E" then markers.E = pos; found=true
            elseif n == "R" then markers.R = pos; found=true end
        end
    end
    if found then 
        if not markers.S then markers.S = 0 end 
        return markers 
    else return nil end
end

local function SortItemsByPos(a, b) return a.pos < b.pos end

function Core.ClearSet(note, set_idx)
    local k = Core.Project.keys[note]
    if k and k.sets[set_idx] then k.sets[set_idx].events = {}; Core.Log("Cleared Set " .. set_idx) end
end

function Core.CaptureToActiveSet()
    local note = Core.Project.selected_note
    local set_idx = Core.Project.selected_set
    local key_data = Core.InitKey(note)
    local target_set = key_data.sets[set_idx]
    local num_sel = r.CountSelectedMediaItems(0)
    if num_sel == 0 then Core.Log("No items selected!"); return end
    
    local raw_items = {}
    local min_global_pos = math.huge
    for i = 0, num_sel - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        if pos < min_global_pos then min_global_pos = pos end
        local smart_data = Core.ParseSmartMarkers(item)
        table.insert(raw_items, {
            item = item, pos = pos,
            len = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
            snap = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"),
            track_idx = r.GetMediaTrackInfo_Value(r.GetMediaItem_Track(item), "IP_TRACKNUMBER"),
            chunk = select(2, r.GetItemStateChunk(item, "", false)),
            smart = smart_data
        })
    end
    table.sort(raw_items, SortItemsByPos)

    local new_events = {}
    local current_event = { items = {} }
    local group_start = raw_items[1].pos
    local last_end = raw_items[1].pos + raw_items[1].len
    local thresh = Core.Project.group_thresh or 0.5
    
    local function AddToGroup(target, it, start_ref)
        table.insert(target.items, {
            chunk = it.chunk, rel_pos = it.pos - start_ref,
            rel_track = it.track_idx, snap = it.snap,
            smart = it.smart, len = it.len
        })
        if it.smart then target.is_smart = true end
        if it.smart and it.smart.R then target.has_release = true end
    end
    
    AddToGroup(current_event, raw_items[1], group_start)
    for i = 2, #raw_items do
        local it = raw_items[i]
        if (it.pos - last_end) > thresh then
            table.insert(new_events, current_event); current_event = { items = {} }; group_start = it.pos
        end
        AddToGroup(current_event, it, group_start)
        local this_end = it.pos + it.len
        if this_end > last_end then last_end = this_end end
    end
    table.insert(new_events, current_event)
    
    for _, evt in ipairs(new_events) do
        local min_track = math.huge
        for _, it in ipairs(evt.items) do if it.rel_track < min_track then min_track = it.rel_track end end
        for _, it in ipairs(evt.items) do it.rel_track_offset = it.rel_track - min_track end
        evt.probability = 100; evt.vol_offset = 0.0; evt.muted = false
        table.insert(target_set.events, evt)
    end
    Core.Log(string.format("Captured %d events (Thr: %.2fs)", #new_events, thresh))
end

-- === HELPERS === --
function Core.InsertSlice(chunk, track, pos, offset, length, set_params, total_vol_factor)
    local ni = r.AddMediaItemToTrack(track)
    r.SetItemStateChunk(ni, chunk, false)
    r.SetMediaItemInfo_Value(ni, "D_POSITION", pos)
    r.SetMediaItemInfo_Value(ni, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(ni, "D_FADEINLEN", 0.002)
    r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", 0.002)
    local take = r.GetActiveTake(ni)
    if take then
        local base_offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", base_offs + offset)
        local cur_vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", cur_vol * total_vol_factor)
    end
    r.SetMediaItemSelected(ni, true)
    return ni
end

function Core.InsertEventItems(event, play_pos, set_params, is_seq_item)
    local rnd = { vol=0, pitch=0, pan=0, pos=0, off=0, fade=0, len=0 }
    if set_params then
        local mt, md = set_params.xy_x * 2.0, set_params.xy_y * 2.0
        local function GR(r, m) return (math.random()*2-1)*r*m end
        rnd.vol = GR(set_params.rnd_vol + Core.Project.g_rnd_vol, md)
        rnd.pitch = GR(set_params.rnd_pitch + Core.Project.g_rnd_pitch, md)
        rnd.pan = GR((set_params.rnd_pan + Core.Project.g_rnd_pan)/100, mt)
        
        if not is_seq_item or set_params.seq_mode ~= 2 then
            rnd.pos = GR(set_params.rnd_pos + Core.Project.g_rnd_pos, mt)
        end
        rnd.off = math.abs(GR(set_params.rnd_offset + Core.Project.g_rnd_offset, mt))
        rnd.fade = math.abs(GR(set_params.rnd_fade + Core.Project.g_rnd_fade, 1.0))
        rnd.len = GR(set_params.rnd_len + Core.Project.g_rnd_len, 1.0)
    end
    
    local total_vol_factor = 10 ^ ((rnd.vol + (event.vol_offset or 0)) / 20)
    local base_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
    if not base_track then r.InsertTrackAtIndex(0, true); base_track = r.GetTrack(0,0) end
    local mode = Core.Project.placement_mode
    if mode == 1 then r.SetMediaTrackInfo_Value(base_track, "I_FREEMODE", 1) 
    elseif mode == 2 then r.SetMediaTrackInfo_Value(base_track, "I_FREEMODE", 2) end

    r.SelectAllMediaItems(0, false)
    local fipm_h = 1.0; if mode == 1 and #event.items > 1 then fipm_h = 1.0 / #event.items end

    for i, it in ipairs(event.items) do
        local tr = base_track 
        if mode == 0 then 
            local idx = r.GetMediaTrackInfo_Value(base_track, "IP_TRACKNUMBER") + it.rel_track_offset
            tr = r.GetTrack(0, idx - 1); if not tr then r.InsertTrackAtIndex(idx-1, true); tr = r.GetTrack(0, idx-1) end
        end
        local ni = r.AddMediaItemToTrack(tr); r.SetItemStateChunk(ni, it.chunk, false)
        
        if mode == 1 then r.SetMediaItemInfo_Value(ni, "F_FREEMODE_Y", (i-1)*fipm_h); r.SetMediaItemInfo_Value(ni, "F_FREEMODE_H", fipm_h)
        elseif mode == 2 then r.SetMediaItemInfo_Value(ni, "I_FIXEDLANE", i-1) end
        
        local item_pos = play_pos + it.rel_pos + rnd.pos
        if Core.Project.use_snap_align and it.snap > 0 then item_pos = item_pos - it.snap end
        r.SetMediaItemInfo_Value(ni, "D_POSITION", item_pos)
        
        if is_seq_item then
            r.SetMediaItemInfo_Value(ni, "D_LENGTH", set_params.seq_len)
            r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", set_params.seq_fade)
        else
            r.SetMediaItemInfo_Value(ni, "D_LENGTH", math.max(0.1, r.GetMediaItemInfo_Value(ni, "D_LENGTH") + rnd.len))
            r.SetMediaItemInfo_Value(ni, "D_FADEINLEN", r.GetMediaItemInfo_Value(ni, "D_FADEINLEN") + rnd.fade)
            r.SetMediaItemInfo_Value(ni, "D_FADEOUTLEN", r.GetMediaItemInfo_Value(ni, "D_FADEOUTLEN") + rnd.fade)
        end

        local take = r.GetActiveTake(ni)
        if take then
            r.SetMediaItemTakeInfo_Value(take, "D_PITCH", r.GetMediaItemTakeInfo_Value(take, "D_PITCH") + rnd.pitch)
            r.SetMediaItemTakeInfo_Value(take, "D_VOL", r.GetMediaItemTakeInfo_Value(take, "D_VOL") * total_vol_factor)
            local np = r.GetMediaItemTakeInfo_Value(take, "D_PAN") + rnd.pan
            if np > 1 then np = 1 elseif np < -1 then np = -1 end
            r.SetMediaItemTakeInfo_Value(take, "D_PAN", np)
            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + rnd.off)
        end
        if mode == 1 then r.UpdateItemInProject(ni) end
        r.SetMediaItemSelected(ni, true)
    end
    r.UpdateArrange()
end

-- === SEQUENCER LOGIC === --
function Core.PlaySequencer(pos, set)
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local use_sel = (ts_end - ts_start) > 0.001
    
    local count = set.seq_count
    local rate = math.max(0.01, set.seq_rate)
    
    local pool_normal, pool_release = {}, {}
    for i, e in ipairs(set.events) do
        if not e.muted then
            if e.has_release then table.insert(pool_release, e) else table.insert(pool_normal, e) end
        end
    end
    if #pool_release == 0 and #pool_normal == 0 then return end
    if #pool_normal == 0 then pool_normal = pool_release end
    
    local is_stitch = (set.seq_mode == 2)
    
    if use_sel then
        if is_stitch then count = 9999; pos = ts_start
        else count = math.floor((ts_end - ts_start) / rate); if count<1 then count=1 end; pos = ts_start end
    end
    
    r.Undo_BeginBlock(); r.PreventUIRefresh(1)
    local current_pos = pos
    
    for i=0, count-1 do
        if use_sel and current_pos >= ts_end then break end
        
        local is_last = (i == count - 1)
        if use_sel and is_stitch then
            if (ts_end - current_pos) <= (set.seq_len * 1.1) then is_last = true end
        end
        
        local evt_to_play = nil
        if is_last and #pool_release > 0 then
            evt_to_play = pool_release[math.random(#pool_release)]
        else
            if set.seq_mode == 0 then evt_to_play = set.events[1]
            else evt_to_play = pool_normal[math.random(#pool_normal)] end
        end
        
        if evt_to_play then
            Core.InsertEventItems(evt_to_play, current_pos, set, true)
            if is_stitch then current_pos = current_pos + set.seq_len else current_pos = current_pos + rate end
        end
        if is_last and use_sel then break end
    end
    r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("Sequencer", -1)
end

-- === TRIGGER & PREVIEW === --
function Core.GetTriggerEvent(note, set_idx)
    local k = Core.Project.keys[note]; if not k then return nil, nil end
    local s = k.sets[set_idx]; if not s or #s.events == 0 then return nil, nil end
    local pool = {}; for i, evt in ipairs(s.events) do if evt.probability > 0 and not evt.muted then table.insert(pool, i) end end
    if #pool == 0 then return nil, nil end
    local c = -1; if #pool==1 then c=pool[1] else local z=0; repeat c=pool[math.random(1,#pool)]; z=z+1 until (c~=s.last_idx) or (z>20) end
    s.last_idx = c
    return s.events[c], s
end

function Core.StartPreview(event, id)
    if not event or #event.items == 0 then return end
    if has_sws and (not Core.IsPreviewing or Core.PreviewID ~= id) then
        r.Xen_StopSourcePreview(0)
        local fn = event.items[1].chunk:match('FILE "([^"]+)"') or event.items[1].chunk:match('FILE ([^\n]+)')
        if fn then local src = r.PCM_Source_CreateFromFile(fn); if src then r.Xen_StartSourcePreview(src, 10^((event.vol_offset or 0)/20), false); Core.IsPreviewing = true; Core.PreviewID = id end end
    end
end
function Core.StopPreview() if has_sws and Core.IsPreviewing then r.Xen_StopSourcePreview(0); Core.IsPreviewing = false; Core.PreviewID = nil end end

function Core.ExecuteTrigger(note, set_idx, pos, edge_type)
    local k = Core.Project.keys[note]; if not k then return end
    local set = k.sets[set_idx]; if not set then return end
    if set.trigger_on == edge_type then
        local mode = Core.Project.trigger_mode
        if mode == 0 then -- One Shot
            local evt, _ = Core.GetTriggerEvent(note, set_idx)
            if evt then
                r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                Core.InsertEventItems(evt, pos, set)
                r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("Trigger", -1)
            end
        elseif mode == 1 then -- Sequencer
            if edge_type == 0 then Core.PlaySequencer(pos, set) end
        elseif mode == 2 then -- Smart Loop
            local evt, _ = Core.GetTriggerEvent(note, set_idx)
            if edge_type == 0 then Core.KeyState.pending_event = evt; Core.KeyState.pending_set = set end
        end
    end
end

function Core.TriggerMulti(note, main_set_idx, pos, edge_type)
    Core.ExecuteTrigger(note, main_set_idx, pos, edge_type)
    for _, idx in ipairs(Core.Project.multi_sets) do if idx~=main_set_idx then Core.ExecuteTrigger(note, idx, pos, edge_type) end end
end

function Core.SmartLoopRelease(note, main_set_idx, start_pos, end_pos)
    if Core.Project.trigger_mode == 2 then
        local evt = Core.KeyState.pending_event; local set = Core.KeyState.pending_set
        if evt and evt.is_smart then
            r.Undo_BeginBlock(); r.PreventUIRefresh(1)
            Core.BuildSmartLoop(evt, start_pos, end_pos, set)
            r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("SmartLoop", -1)
        end
        Core.KeyState.pending_event = nil
    end
end

function Core.DeleteEvent(note, set_idx, evt_idx)
    local k = Core.Project.keys[note]
    if k and k.sets[set_idx] then table.remove(k.sets[set_idx].events, evt_idx) end
end

-- =========================================================
-- GUI
-- =========================================================
local Gui = {}
local COLORS = { accent=0x0D755CFF, accent_hover=0x149675FF, bg=0x1E1E1EFF, bg_panel=0x252525FF, bg_input=0x141414FF,
    white_key=0xDDDDDDFF, black_key=0x111111FF, active_key=0xD46A3FFF, active_multi=0xD4AA3FFF, mute_active=0xD4AA3FFF,
    text_dim=0x909090FF, xy_bg=0x111111FF, xy_grid=0x333333FF, layer_col=0x0D755C99, smart_col=0x750D5C99, insert_btn=0x0D755CFF }

function Gui.BeginChildBox(ctx, label, w, h)
    local border = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 1
    return r.ImGui_BeginChild(ctx, label, w, h, border, 0)
end
function Gui.PushTheme(ctx)
    if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then return end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLORS.bg_panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COLORS.accent_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COLORS.active_key)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x353535FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x454545FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x252525FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE0E0E0FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLORS.bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x303030FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLORS.bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLORS.active_key)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.active_key)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
end
function Gui.PopTheme(ctx) r.ImGui_PopStyleColor(ctx, 15); r.ImGui_PopStyleVar(ctx, 2) end

function Gui.DrawTopBar(ctx)
    r.ImGui_TextDisabled(ctx, Core.LastLog)
    r.ImGui_SameLine(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + avail_w - 100)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.insert_btn)
    if r.ImGui_Button(ctx, "INSERT (K)", 100, 0) then
        local cursor = r.GetPlayState()~=0 and r.GetPlayPosition() or r.GetCursorPosition()
        Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 0)
        -- Instant Release
        Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 1)
        Core.SmartLoopRelease(Core.Project.selected_note, Core.Project.selected_set, cursor, cursor+0.1)
    end
    r.ImGui_PopStyleColor(ctx, 1)
end

function Gui.DrawKeyboard(ctx)
    r.ImGui_BeginGroup(ctx); r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 0)
    for i = 0, CONFIG.num_keys - 1 do
        local note = CONFIG.base_note + i
        local is_active = (Core.Project.selected_note == note)
        local n = note % 12
        local is_black = (n==1 or n==3 or n==6 or n==8 or n==10)
        local col = is_black and COLORS.black_key or COLORS.white_key
        if is_active then col = COLORS.active_key end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (not is_black or is_active) and 0x000000FF or 0xFFFFFFFF)
        r.ImGui_PushID(ctx, i)
        if r.ImGui_Button(ctx, tostring(note), 28, 80) then Core.Project.selected_note = note; Core.InitKey(note); Core.Project.multi_sets = {} end
        r.ImGui_PopID(ctx); r.ImGui_PopStyleColor(ctx, 2); r.ImGui_SameLine(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1); r.ImGui_EndGroup(ctx)
    r.ImGui_TextColored(ctx, COLORS.accent, "Selected Key: " .. Core.Project.selected_note)
end

function Gui.DrawSetsTabs(ctx)
    r.ImGui_Separator(ctx)
    local k = Core.Project.keys[Core.Project.selected_note]; if not k then return end 
    for i = 1, 16 do
        local is_main = (Core.Project.selected_set == i)
        local is_multi = false; for _,v in ipairs(Core.Project.multi_sets) do if v==i then is_multi=true break end end
        local has_data = k.sets[i] and #k.sets[i].events > 0
        local col = 0x333333FF
        if is_main then col = COLORS.active_key elseif is_multi then col = COLORS.active_multi elseif has_data then col = COLORS.accent end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), (is_main or is_multi) and 0x000000FF or 0xE0E0E0FF)
        if r.ImGui_Button(ctx, "S"..i, 35, 20) then 
            if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt()) then Core.ClearSet(Core.Project.selected_note, i)
            elseif r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
                if is_multi then for idx,v in ipairs(Core.Project.multi_sets) do if v==i then table.remove(Core.Project.multi_sets, idx) break end end
                else table.insert(Core.Project.multi_sets, i) end
            else Core.Project.selected_set = i; Core.Project.multi_sets = {} end
        end
        r.ImGui_PopStyleColor(ctx, 2)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Click: Select\nShift+Click: Add Layer\nAlt+Click: Clear") end
        if i < 16 then r.ImGui_SameLine(ctx) end
    end
    r.ImGui_Separator(ctx)
end

function Gui.DrawEventsSlots(ctx)
    local k = Core.Project.keys[Core.Project.selected_note]; if not k then return end
    local s = k.sets[Core.Project.selected_set]; if not s or #s.events == 0 then r.ImGui_TextDisabled(ctx, "No Events."); return end
    r.ImGui_NewLine(ctx) 
    for i, evt in ipairs(s.events) do
        r.ImGui_PushID(ctx, i); r.ImGui_BeginGroup(ctx)
            local lbl = string.format("E%02d", i) .. (evt.is_smart and " (S)" or "")
            if evt.has_release then lbl = lbl .. " (R)" end
            r.ImGui_TextColored(ctx, evt.is_smart and COLORS.active_multi or COLORS.accent, lbl)
            local w = CONFIG.slot_width; local p = {r.ImGui_GetCursorScreenPos(ctx)}; local dl = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_InvisibleButton(ctx, "l", w, math.max(20, #evt.items*7))
            if r.ImGui_IsItemActive(ctx) then Core.StartPreview(evt, i) else if Core.PreviewID == i then Core.StopPreview() end end
            for li=1, #evt.items do
                local y1 = p[2] + (li-1)*7; 
                r.ImGui_DrawList_AddRectFilled(dl, p[1], y1, p[1]+w, y1+6, (evt.items[li] and evt.items[li].smart) and COLORS.smart_col or COLORS.layer_col)
            end
            local mc = evt.muted and COLORS.mute_active or 0x555555FF
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mc); if r.ImGui_Button(ctx, "M", w, 0) then evt.muted = not evt.muted end; r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SetNextItemWidth(ctx, w); local _, np = r.ImGui_SliderInt(ctx, "##p", evt.probability, 0, 100, ""); if _ then evt.probability=np end
            r.ImGui_TextColored(ctx, COLORS.text_dim, "P: " .. evt.probability .. "%")
            r.ImGui_SetNextItemWidth(ctx, w); local _, nv = r.ImGui_SliderDouble(ctx, "##v", evt.vol_offset or 0, -12, 12, ""); if _ then evt.vol_offset=nv end
            r.ImGui_TextColored(ctx, COLORS.text_dim, "V: " .. string.format("%+.1f", evt.vol_offset or 0))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA4444FF); if r.ImGui_Button(ctx, "X", w, 0) then Core.DeleteEvent(Core.Project.selected_note, Core.Project.selected_set, i) end; r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_EndGroup(ctx); r.ImGui_PopID(ctx); r.ImGui_SameLine(ctx)
    end
    r.ImGui_NewLine(ctx)
end

function Gui.DrawModulationMatrix(ctx, s)
    if not r.ImGui_BeginTable(ctx, "ModMatrix", 3, r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then return end
    r.ImGui_TableSetupColumn(ctx, "P", r.ImGui_TableColumnFlags_WidthFixed(), 40)
    r.ImGui_TableSetupColumn(ctx, "Evt", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Set", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableHeadersRow(ctx)
    local function Rw(n,sv,gv,mx,sf,gf)
        r.ImGui_TableNextRow(ctx); r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, n)
        r.ImGui_TableNextColumn(ctx); r.ImGui_SetNextItemWidth(ctx,-1); local c1,v1=r.ImGui_SliderDouble(ctx,"##s"..n,sv,0,mx,"%.2f"); if c1 then sf(v1) end
        r.ImGui_TableNextColumn(ctx); r.ImGui_SetNextItemWidth(ctx,-1); local c2,v2=r.ImGui_SliderDouble(ctx,"##g"..n,gv,0,mx,"%.2f"); if c2 then gf(v2) end
    end
    Rw("Vol", s.rnd_vol, Core.Project.g_rnd_vol, 12, function(v)s.rnd_vol=v end, function(v)Core.Project.g_rnd_vol=v end)
    Rw("Pit", s.rnd_pitch, Core.Project.g_rnd_pitch, 12, function(v)s.rnd_pitch=v end, function(v)Core.Project.g_rnd_pitch=v end)
    Rw("Pan", s.rnd_pan, Core.Project.g_rnd_pan, 100, function(v)s.rnd_pan=v end, function(v)Core.Project.g_rnd_pan=v end)
    Rw("Pos", s.rnd_pos, Core.Project.g_rnd_pos, 0.2, function(v)s.rnd_pos=v end, function(v)Core.Project.g_rnd_pos=v end)
    Rw("Off", s.rnd_offset, Core.Project.g_rnd_offset, 1.0, function(v)s.rnd_offset=v end, function(v)Core.Project.g_rnd_offset=v end)
    Rw("Fad", s.rnd_fade, Core.Project.g_rnd_fade, 0.5, function(v)s.rnd_fade=v end, function(v)Core.Project.g_rnd_fade=v end)
    Rw("Len", s.rnd_len, Core.Project.g_rnd_len, 1.0, function(v)s.rnd_len=v end, function(v)Core.Project.g_rnd_len=v end)
    r.ImGui_EndTable(ctx)
end

function Gui.DrawSequencerParams(ctx, s)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "SEQ SETTINGS")
    
    r.ImGui_SetNextItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "##sqm", ({"Repeat First", "Random Pool", "Stitch Random"})[s.seq_mode+1]) then
        if r.ImGui_Selectable(ctx, "Repeat First", s.seq_mode==0) then s.seq_mode=0 end
        if r.ImGui_Selectable(ctx, "Random Pool", s.seq_mode==1) then s.seq_mode=1 end
        if r.ImGui_Selectable(ctx, "Stitch Random", s.seq_mode==2) then s.seq_mode=2 end
        r.ImGui_EndCombo(ctx)
    end
    
    -- Compact Table for Inputs
    if r.ImGui_BeginTable(ctx, "SeqT", 2) then
        r.ImGui_TableSetupColumn(ctx, "L", r.ImGui_TableColumnFlags_WidthFixed(), 40)
        r.ImGui_TableSetupColumn(ctx, "V", r.ImGui_TableColumnFlags_WidthStretch())
        
        local function Drag(lbl, val, step, cb)
            r.ImGui_TableNextRow(ctx); r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, lbl)
            r.ImGui_TableNextColumn(ctx); r.ImGui_SetNextItemWidth(ctx, -1)
            local ch, nv = r.ImGui_DragDouble(ctx, "##"..lbl, val, step, 0, 100, "%.3f")
            if ch then cb(nv) end
        end
        
        r.ImGui_TableNextRow(ctx); r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Cnt")
        r.ImGui_TableNextColumn(ctx); r.ImGui_SetNextItemWidth(ctx, -1)
        local c, v = r.ImGui_InputInt(ctx, "##cnt", s.seq_count); if c then s.seq_count = math.max(1, v) end
        
        Drag("Rate", s.seq_rate, 0.005, function(v) s.seq_rate = math.max(0.01, v) end)
        Drag("Len", s.seq_len, 0.005, function(v) s.seq_len = math.max(0.01, v) end)
        Drag("Fade", s.seq_fade, 0.001, function(v) s.seq_fade = math.max(0.001, v) end)
        r.ImGui_EndTable(ctx)
    end
    r.ImGui_EndGroup(ctx)
end

function Gui.DrawXYPad(ctx, s)
    r.ImGui_BeginGroup(ctx)
    r.ImGui_TextDisabled(ctx, "PERFORM (XY)")
    local size = 160 -- Bigger
    -- Center
    local avail = r.ImGui_GetContentRegionAvail(ctx)
    if avail > size then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail-size)*0.5) end
    
    local p = { r.ImGui_GetCursorScreenPos(ctx) }; local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, p[1], p[2], p[1]+size, p[2]+size, COLORS.xy_bg, 4)
    r.ImGui_DrawList_AddRect(dl, p[1], p[2], p[1]+size, p[2]+size, COLORS.xy_grid, 4)
    r.ImGui_DrawList_AddText(dl, p[1]+2, p[2]+2, 0xAAAAAAFF, "Intens")
    r.ImGui_DrawList_AddText(dl, p[1]+size-40, p[2]+size-14, 0xAAAAAAFF, "Spread")
    r.ImGui_InvisibleButton(ctx, "XYPad", size, size)
    if r.ImGui_IsItemActive(ctx) then
        local mx, my = r.ImGui_GetMousePos(ctx)
        s.xy_x = math.max(0, math.min(1, (mx - p[1]) / size))
        s.xy_y = math.max(0, math.min(1, 1 - (my - p[2]) / size))
    end
    local px = p[1] + s.xy_x * size; local py = p[2] + (1 - s.xy_y) * size
    r.ImGui_DrawList_AddCircleFilled(dl, px, py, 6, COLORS.accent)
    r.ImGui_DrawList_AddLine(dl, px, p[2], px, p[2]+size, COLORS.xy_grid)
    r.ImGui_DrawList_AddLine(dl, p[1], py, p[1]+size, py, COLORS.xy_grid)
    r.ImGui_TextColored(ctx, COLORS.text_dim, string.format("X:%.0f%% Y:%.0f%%", s.xy_x*200, s.xy_y*200))
    r.ImGui_EndGroup(ctx)
end

function Gui.DrawMainControls(ctx)
    if Gui.BeginChildBox(ctx, "MA", 0, 240) then
        if r.ImGui_BeginTable(ctx, "LT", 4) then
            -- 4 Equal Columns
            r.ImGui_TableSetupColumn(ctx, "C1", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C2", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C3", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx, "C4", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableNextRow(ctx)
            
            -- COL 1: Capture / Base
            r.ImGui_TableNextColumn(ctx) 
            local k = Core.Project.keys[Core.Project.selected_note]
            if k then
                local s = k.sets[Core.Project.selected_set]
                r.ImGui_TextColored(ctx, COLORS.active_key, "SET " .. Core.Project.selected_set)
                
                -- Center Button
                local avail = r.ImGui_GetContentRegionAvail(ctx)
                r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail-140)*0.5)
                if r.ImGui_Button(ctx, "CAPTURE (+)", 140, 40) then Core.CaptureToActiveSet() end
                
                -- Gap Thresh
                r.ImGui_SetNextItemWidth(ctx, 140)
                local gt, gtv = r.ImGui_DragDouble(ctx, "Gap Thrs", Core.Project.group_thresh, 0.01, 0.01, 2.0, "%.2fs")
                if gt then Core.Project.group_thresh = gtv end
                
                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##trg", ({"Start: Key Down", "Start: Key Up"})[s.trigger_on+1]) then
                    if r.ImGui_Selectable(ctx, "Key Down", s.trigger_on==0) then s.trigger_on=0 end
                    if r.ImGui_Selectable(ctx, "Key Up", s.trigger_on==1) then s.trigger_on=1 end
                    r.ImGui_EndCombo(ctx)
                end

                local _, b = r.ImGui_Checkbox(ctx, "Snap Offset", Core.Project.use_snap_align); if _ then Core.Project.use_snap_align=b end
                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##pm", ({"Rel Layers", "Old FIPM", "Fixed Lanes"})[Core.Project.placement_mode+1]) then
                    if r.ImGui_Selectable(ctx, "Rel Layers", false) then Core.Project.placement_mode=0 end
                    if r.ImGui_Selectable(ctx, "Old FIPM", false) then Core.Project.placement_mode=1 end
                    if r.ImGui_Selectable(ctx, "Fixed Lanes", false) then Core.Project.placement_mode=2 end
                    r.ImGui_EndCombo(ctx)
                end
                if s then r.ImGui_Text(ctx, "Count: " .. #s.events) end
                
                -- COL 2: Modes
                r.ImGui_TableNextColumn(ctx) 
                r.ImGui_Text(ctx, "TRIGGER MODE")
                r.ImGui_SetNextItemWidth(ctx, 140)
                if r.ImGui_BeginCombo(ctx, "##tm", ({"One Shot", "Sequencer", "Smart Loop"})[Core.Project.trigger_mode+1]) then
                    if r.ImGui_Selectable(ctx, "One Shot", false) then Core.Project.trigger_mode=0 end
                    if r.ImGui_Selectable(ctx, "Sequencer", false) then Core.Project.trigger_mode=1 end
                    if r.ImGui_Selectable(ctx, "Smart Loop", false) then Core.Project.trigger_mode=2 end
                    r.ImGui_EndCombo(ctx)
                end
                
                if s and Core.Project.trigger_mode == 1 then
                    r.ImGui_Dummy(ctx, 0, 10)
                    Gui.DrawSequencerParams(ctx, s)
                end
                
                -- COL 3: Matrix
                r.ImGui_TableNextColumn(ctx) 
                if s then Gui.DrawModulationMatrix(ctx, s) end
                
                -- COL 4: XY
                r.ImGui_TableNextColumn(ctx) 
                if s then Gui.DrawXYPad(ctx, s) end
            end
            r.ImGui_EndTable(ctx)
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Separator(ctx)
    if Gui.BeginChildBox(ctx, "Ev", 0, 0) then Gui.DrawEventsSlots(ctx); r.ImGui_EndChild(ctx) end
end

function Gui.HandleGlobalInput()
    if has_js_api then
        local state = r.JS_VKeys_GetState(0)
        local is_down = state:byte(CONFIG.global_key) ~= 0
        local cursor = r.GetPlayState()~=0 and r.GetPlayPosition() or r.GetCursorPosition()
        if is_down and not Core.Input.was_down then
            Core.KeyState.held = true; Core.KeyState.start_pos = cursor
            Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 0)
        elseif not is_down and Core.Input.was_down then
            Core.KeyState.held = false
            Core.TriggerMulti(Core.Project.selected_note, Core.Project.selected_set, cursor, 1)
            Core.SmartLoopRelease(Core.Project.selected_note, Core.Project.selected_set, Core.KeyState.start_pos, cursor)
        end
        Core.Input.was_down = is_down
    end
end

local ctx = nil
local function Loop()
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then ctx = r.ImGui_CreateContext('ReaSFX') end
    if ctx then
        if r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true) end
        Gui.HandleGlobalInput()
        Gui.PushTheme(ctx)
        local v, o = r.ImGui_Begin(ctx, 'ReaSFX Sampler', true, r.ImGui_WindowFlags_MenuBar())
        if v then
            if r.ImGui_BeginMenuBar(ctx) then Gui.DrawTopBar(ctx); r.ImGui_EndMenuBar(ctx) end
            Gui.DrawKeyboard(ctx)
            Gui.DrawSetsTabs(ctx)
            Gui.DrawMainControls(ctx)
            r.ImGui_End(ctx)
        end
        Gui.PopTheme(ctx)
        if o then r.defer(Loop) else ReleaseKeys(); if r.ImGui_DestroyContext then r.ImGui_DestroyContext(ctx) end end
    end
end

r.Undo_BeginBlock(); Loop(); r.Undo_EndBlock("ReaSFX", -1)
