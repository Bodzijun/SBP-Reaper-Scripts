-- @description SBP Chord Voicing Editor (old LUA)
-- @version 23.3.0
-- @about
--  Chord editing tool for REAPER MIDI items.
-- @author SBP
-- @link https://forum.cockos.com/showthread.php?t=305655
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @changelog
--  Initial ReaPack release.

local r = reaper
local ctx = r.ImGui_CreateContext('Chord Voicing Editor v46.0')

-- === STATE & DEFAULTS ===
local DEFAULT_ACCENT = 0x217763FF
local DEFAULT_SEC    = 0xAA4444FF 

local settings = {
    targets = { root=true, third=false, fifth=false, seventh=false },
    direction = 1,      -- 1 = UP, -1 = DOWN
    voice_mode = 0,     -- 0=Follow, 1=Root, 2=3rd, 3=5th
    auto_close = true,
    show_tooltips = true,
    hum_vel_str = 10,
    hum_time_str = 15,
    strum_val = 20,
    tolerance = 60,     
    accent_col = DEFAULT_ACCENT,
    sec_col = DEFAULT_SEC,
    show_settings = false
}

-- Ensure no nil values
local function ValidateSettings()
    if not settings.direction then settings.direction = 1 end
    if not settings.voice_mode then settings.voice_mode = 0 end
    if settings.auto_close == nil then settings.auto_close = true end
    if settings.show_tooltips == nil then settings.show_tooltips = true end
    if not settings.hum_vel_str then settings.hum_vel_str = 10 end
    if not settings.hum_time_str then settings.hum_time_str = 15 end
    if not settings.strum_val then settings.strum_val = 20 end
    if not settings.tolerance then settings.tolerance = 60 end
    if not settings.accent_col then settings.accent_col = DEFAULT_ACCENT end
    if not settings.sec_col then settings.sec_col = DEFAULT_SEC end
end

-- Load State
local ext_state = r.GetExtState("ChordVoicingEditor", "Settings_v46") -- New key v46
if ext_state ~= "" then
    local d, v, ac, tips, hv, ht, sv, tol, col, scol = ext_state:match("(-?%d),(%d),([01]),([01]),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)")
    if d then settings.direction = tonumber(d) end
    if v then settings.voice_mode = tonumber(v) end
    if ac then settings.auto_close = (ac == "1") end
    if tips then settings.show_tooltips = (tips == "1") end
    if hv then settings.hum_vel_str = tonumber(hv) end
    if ht then settings.hum_time_str = tonumber(ht) end
    if sv then settings.strum_val = tonumber(sv) end
    if tol then settings.tolerance = tonumber(tol) end
    if col then settings.accent_col = tonumber(col) end
    if scol then settings.sec_col = tonumber(scol) end
end
ValidateSettings() 

local function SaveState()
    local ac_val = settings.auto_close and 1 or 0
    local tips_val = settings.show_tooltips and 1 or 0
    local col_val = math.floor(settings.accent_col or DEFAULT_ACCENT)
    local scol_val = math.floor(settings.sec_col or DEFAULT_SEC)
    
    local str = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", 
        settings.direction, settings.voice_mode, ac_val, tips_val,
        settings.hum_vel_str, settings.hum_time_str, settings.strum_val,
        settings.tolerance, col_val, scol_val)
    r.SetExtState("ChordVoicingEditor", "Settings_v46", str, true)
end

-- === CONFIG CONSTANTS ===
local BG_COLOR        = 0x202020FF
local FRAME_BG        = 0x333333FF
local TEXT_COLOR      = 0xEEEEEEFF

-- FIXED FOR OLDER LUA VERSIONS (No bitwise ops)
local function Lighten(color, amt)
    -- Extract RGBA using math instead of bit shifting
    local r = math.floor(color / 16777216) % 256
    local g = math.floor(color / 65536) % 256
    local b = math.floor(color / 256) % 256
    local a = color % 256

    r = math.min(255, r + amt)
    g = math.min(255, g + amt)
    b = math.min(255, b + amt)

    -- Recombine
    return (r * 16777216) + (g * 65536) + (b * 256) + a
end

local CHROM_MAP = {
    [1]=2, [2]=4, [3]=5, [4]=7, [5]=9, [6]=10, [7]=12, 
    [8]=14, [10]=17, [11]=17, [12]=21, [13]=21 
}

-- === HELPERS ===
local function Tooltip(text)
    if not settings.show_tooltips then return end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetFontSize(ctx) * 35.0)
        r.ImGui_Text(ctx, text)
        r.ImGui_PopTextWrapPos(ctx)
        r.ImGui_EndTooltip(ctx)
    end
end

-- === CHORD ROOT DETECTION ===
local function FindChordRoot(pitches, scale_root)
    if #pitches < 2 then return pitches[1] % 12 end
    local pitch_classes = {}
    for _, p in ipairs(pitches) do pitch_classes[(p % 12)] = true end
    local classes = {}
    for pc, _ in pairs(pitch_classes) do table.insert(classes, pc) end
    local bass_pitch_class = pitches[1] % 12
    local best_root = bass_pitch_class
    local best_score = -999
    for _, candidate in ipairs(classes) do
        local score = 0
        local intervals = {}
        for _, pc in ipairs(classes) do intervals[(pc - candidate) % 12] = true end
        if intervals[7] then score = score + 10 end
        if intervals[4] then score = score + 5 end
        if intervals[3] then score = score + 4 end
        if intervals[10] then score = score + 3 end
        if intervals[11] then score = score + 3 end
        if intervals[9] then score = score + 2 end
        if intervals[5] then score = score + 2 end
        if intervals[2] then score = score + 1 end
        if intervals[6] and not intervals[7] then score = score + 2 end
        if candidate == bass_pitch_class then score = score + 1 end
        if scale_root and candidate == (scale_root % 12) then score = score + 1 end
        if score > best_score then best_score = score; best_root = candidate end
    end
    return best_root
end

-- === DATA GATHERING ===
local function GetScaleBitMap(take, hwnd)
    local root = r.MIDIEditor_GetSetting_int(hwnd, "scale_root")
    local ok, _, scale_val = r.MIDI_GetScale(take, root, "")
    local map = {}
    for i=0, 11 do map[i] = false end
    local valid = false
    if ok then
        if type(scale_val) == "string" and #scale_val > 0 then
            map[root%12]=true; for n in scale_val:gmatch("%d+") do map[(root+n)%12]=true end; valid=true
        elseif type(scale_val) == "number" then
            local m = math.floor(scale_val)
            for i=0,11 do 
                -- FIXED: Using math.floor/pow instead of bitwise keys for Lua 5.1/iOS compatibility
                -- (m >> i) & 1 corresponds to: floor(m / 2^i) % 2
                if (math.floor(m / (2^i)) % 2) == 1 then 
                    map[(root+i)%12]=true
                    valid=true 
                end 
            end
        end
    end
    if not valid then 
        local m={0,2,4,5,7,9,11}; for _,v in ipairs(m) do map[(root+v)%12]=true end
    end
    return map
end

local function GetDiatonicPitch(start, map, steps, dir)
    local curr = start
    local taken = 0
    local safe = 0
    while taken < steps and safe < 100 do
        curr = curr + dir 
        if map[curr % 12] then taken = taken + 1 end
        safe = safe + 1
    end
    return curr
end

-- DAISY CHAIN GROUPING
local function GetSelectedChords(take)
    local _, cnt = r.MIDI_CountEvts(take)
    local all_sel = {}
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            table.insert(all_sel, {idx=i, muted=muted, start=start, endp=endp, pitch=pitch, vel=vel, chan=chan})
        end
    end
    if #all_sel == 0 then return {} end
    
    table.sort(all_sel, function(a,b) 
        if a.start == b.start then return a.pitch < b.pitch end
        return a.start < b.start 
    end)
    
    local chords = {}
    local current_chord = {all_sel[1]}
    local last_added_start = all_sel[1].start 
    
    for i = 2, #all_sel do
        local note = all_sel[i]
        if math.abs(note.start - last_added_start) <= settings.tolerance then
            table.insert(current_chord, note)
            last_added_start = note.start
        else
            table.sort(current_chord, function(a,b) return a.pitch < b.pitch end)
            table.insert(chords, current_chord)
            current_chord = {note}
            last_added_start = note.start
        end
    end
    
    if #current_chord > 0 then
        table.sort(current_chord, function(a,b) return a.pitch < b.pitch end)
        table.insert(chords, current_chord)
    end
    return chords
end

-- === ACTION WRAPPER ===
local function DoAction(func, name)
    local hwnd = r.MIDIEditor_GetActive()
    local take = r.MIDIEditor_GetTake(hwnd)
    if not take then return end
    local item = r.GetMediaItemTake_Item(take)
    func(take, hwnd)
    r.MIDI_Sort(take)
    r.UpdateItemInProject(item)
    r.Undo_OnStateChange_Item(0, name, item)
    SaveState()
end

-- === ACTIONS ===
local function SelectAllNotes()
    local take = r.MIDIEditor_GetTake(r.MIDIEditor_GetActive())
    if not take then return end
    r.MIDI_SelectAll(take, true)
end

local function Action_SmartHarmonize(take, hwnd, steps)
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local map = nil
    if scale_enabled then map = GetScaleBitMap(take, hwnd) end
    local chords = GetSelectedChords(take)
    local notes_to_add = {}
    for _, chord in ipairs(chords) do
        if #chord == 1 then
            local note = chord[1]
            local np = scale_enabled and GetDiatonicPitch(note.pitch, map, steps, settings.direction) or (note.pitch + ((CHROM_MAP[steps] or 12) * settings.direction))
            if np >= 0 and np <= 127 then table.insert(notes_to_add, {muted=note.muted, start=note.start, endppq=note.endp, chan=note.chan, pitch=np, vel=note.vel}) end
        elseif #chord > 1 then
            local pitches = {}; local pitch_lookup = {} 
            for _, n in ipairs(chord) do table.insert(pitches, n.pitch); pitch_lookup[n.pitch] = true end
            local bass_pitch = pitches[1]
            local scale_root = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
            local root_pitch_class = FindChordRoot(pitches, scale_root)
            local root_pitch = bass_pitch + ((root_pitch_class - (bass_pitch % 12) + 12) % 12)
            local target_pitch = scale_enabled and GetDiatonicPitch(root_pitch, map, steps, settings.direction) or (root_pitch + ((CHROM_MAP[steps] or 12) * settings.direction))
            if not pitch_lookup[target_pitch] and target_pitch >= 0 and target_pitch <= 127 then
                 local ref_note = chord[1] 
                 table.insert(notes_to_add, {muted=ref_note.muted, start=ref_note.start, endppq=ref_note.endp, chan=ref_note.chan, pitch=target_pitch, vel=ref_note.vel})
            end
        end
    end
    r.MIDI_SelectAll(take, false)
    for _, n in ipairs(notes_to_add) do r.MIDI_InsertNote(take, true, n.muted, n.start, n.endppq, n.chan, n.pitch, n.vel, true) end
end

local function Action_BuildChord(take, hwnd, type_str)
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local map = nil
    if scale_enabled then map = GetScaleBitMap(take, hwnd) end
    local _, cnt = r.MIDI_CountEvts(take)
    local add = {}
    for i=0, cnt-1 do
        local _, sel, mute, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            local intervals = {}
            if type_str == "triad" then
                if scale_enabled then table.insert(intervals, GetDiatonicPitch(pitch, map, 2, settings.direction)); table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else table.insert(intervals, pitch+(4*settings.direction)); table.insert(intervals, pitch+(7*settings.direction)) end
            elseif type_str == "sus2" then
                 if scale_enabled then table.insert(intervals, GetDiatonicPitch(pitch, map, 1, settings.direction)); table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else table.insert(intervals, pitch+(2*settings.direction)); table.insert(intervals, pitch+(7*settings.direction)) end
            elseif type_str == "sus4" then
                 if scale_enabled then table.insert(intervals, GetDiatonicPitch(pitch, map, 3, settings.direction)); table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else table.insert(intervals, pitch+(5*settings.direction)); table.insert(intervals, pitch+(7*settings.direction)) end
            elseif type_str == "dim" then
                table.insert(intervals, pitch+(3*settings.direction)); table.insert(intervals, pitch+(6*settings.direction))
            elseif type_str == "aug" then
                table.insert(intervals, pitch+(4*settings.direction)); table.insert(intervals, pitch+(8*settings.direction))
            end
            for _, p in ipairs(intervals) do if p>=0 and p<=127 then table.insert(add, {muted=mute, start=start, endppq=endp, chan=chan, pitch=p, vel=vel}) end end
        end
    end
    r.MIDI_SelectAll(take, false)
    for _,n in ipairs(add) do r.MIDI_InsertNote(take, true, n.muted, n.start, n.endppq, n.chan, n.pitch, n.vel, true) end
end

local function Action_FilterSelection(take, hwnd)
    local function get_role_exact(note_pitch, root_pitch)
        local interval = (note_pitch - root_pitch) % 12
        if interval == 0 then return "root" end
        if interval == 3 or interval == 4 then return "third" end     
        if interval == 7 or interval == 8 then return "fifth" end 
        if interval == 9 or interval == 10 or interval == 11 then return "seventh" end  
        if interval == 6 then return "tritone" end 
        return "extension"
    end
    local chords = GetSelectedChords(take)
    local events_to_deselect = {}
    for _, c in ipairs(chords) do for _, n in ipairs(c) do events_to_deselect[n.idx] = true end end
    local events_to_keep = {}
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local scale_root = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
    for _, chord in ipairs(chords) do
        local pitches = {}
        for _, n in ipairs(chord) do table.insert(pitches, n.pitch) end
        local bass = pitches[1]
        local root_pc = FindChordRoot(pitches, scale_root)
        local root_pitch = bass + ((root_pc - (bass % 12) + 12) % 12)
        for _, n in ipairs(chord) do
            local role = get_role_exact(n.pitch, root_pitch)
            local keep = false
            if role == "root" and settings.targets.root then keep = true end
            if role == "third" and settings.targets.third then keep = true end
            if role == "fifth" and settings.targets.fifth then keep = true end
            if role == "seventh" and settings.targets.seventh then keep = true end
            if keep then events_to_keep[n.idx] = true end
        end
    end
    for idx, _ in pairs(events_to_deselect) do if not events_to_keep[idx] then r.MIDI_SetNote(take, idx, false, nil, nil, nil, nil, nil, nil, true) end end
end

local function Action_SimpleEdit(take, hwnd, action, param)
    local _, cnt = r.MIDI_CountEvts(take)
    local to_dup = {}
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            if action == "move" then
                local np = pitch + param
                if np >= 0 and np <= 127 then r.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, np, nil, true) end
            elseif action == "duplicate" then
                local np = pitch + param
                if np >= 0 and np <= 127 then table.insert(to_dup, {muted=muted, start=start, endppq=endp, chan=chan, pitch=np, vel=vel}) end
            elseif action == "mute" then
                 r.MIDI_SetNote(take, i, nil, not muted, nil, nil, nil, nil, nil, true)
            end
        end
    end
    if action == "duplicate" then
        r.MIDI_SelectAll(take, false)
        for _, n in ipairs(to_dup) do r.MIDI_InsertNote(take, true, n.muted, n.start, n.endppq, n.chan, n.pitch, n.vel, true) end
    end
end

-- SMART GLUE
local function Action_GlueNotes(take, hwnd)
    local _, cnt = r.MIDI_CountEvts(take)
    local sel_notes = {}
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            table.insert(sel_notes, {idx=i, start=start, endp=endp, pitch=pitch, chan=chan, vel=vel, muted=muted})
        end
    end
    if #sel_notes < 2 then return end

    table.sort(sel_notes, function(a,b) 
        if a.pitch == b.pitch then return a.start < b.start end
        return a.pitch < b.pitch 
    end)

    r.MIDI_DisableSort(take)
    local to_delete = {}
    local GAP_TOLERANCE = 15 
    local i = 1
    while i < #sel_notes do
        local curr = sel_notes[i]
        local next_n = sel_notes[i+1]
        if next_n and curr.pitch == next_n.pitch then
            local gap = next_n.start - curr.endp
            if gap <= GAP_TOLERANCE then
                local new_end = math.max(curr.endp, next_n.endp)
                curr.endp = new_end
                r.MIDI_SetNote(take, curr.idx, nil, nil, nil, new_end, nil, nil, nil, false)
                table.insert(to_delete, next_n.idx)
                table.remove(sel_notes, i+1)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    table.sort(to_delete, function(a,b) return a > b end)
    for _, idx in ipairs(to_delete) do r.MIDI_DeleteNote(take, idx) end
    r.MIDI_Sort(take)
end

local function Action_InvertChords(take, hwnd, direction)
    local chords = GetSelectedChords(take)
    for _, chord in ipairs(chords) do
        if #chord >= 2 then
            if direction == 1 then 
                local note = chord[1]
                local np = note.pitch + 12
                if np <= 127 then r.MIDI_SetNote(take, note.idx, nil,nil,nil,nil,nil, np, nil, true) end
            elseif direction == -1 then
                local note = chord[#chord]
                local np = note.pitch - 12
                if np >= 0 then r.MIDI_SetNote(take, note.idx, nil,nil,nil,nil,nil, np, nil, true) end
            end
        end
    end
end

local function Action_DropVoicing(take, hwnd, drop_type) 
    local chords = GetSelectedChords(take)
    for _, chord in ipairs(chords) do
        if #chord >= drop_type then
            local target_idx = #chord - (drop_type - 1)
            local note_to_drop = chord[target_idx]
            local np = note_to_drop.pitch - 12
            if np >= 0 then r.MIDI_SetNote(take, note_to_drop.idx, nil,nil,nil,nil,nil, np, nil, true) end
        end
    end
end

local function Action_VoiceLeading(take, hwnd)
    local chords = GetSelectedChords(take)
    if #chords < 2 then return end
    local function GetCentroid(chord) local sum = 0; for _, n in ipairs(chord) do sum = sum + n.pitch end; return sum / #chord end
    local c1 = chords[1]
    if settings.voice_mode > 0 and #c1 > 1 then
        local pitches = {}; for _, n in ipairs(c1) do table.insert(pitches, n.pitch) end
        local bass = pitches[1]
        local scale = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
        local s_root = scale and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
        local root_pc = FindChordRoot(pitches, s_root)
        local root_pitch = bass + ((root_pc - (bass % 12) + 12) % 12)
        local target_role = "root"
        if settings.voice_mode == 2 then target_role = "third" end
        if settings.voice_mode == 3 then target_role = "fifth" end
        local function role_ex(np, rp) local i=(np-rp)%12; if i==0 then return "root" elseif i==3 or i==4 then return "third" elseif i==7 or i==8 then return "fifth" end return "o" end
        local target_note = nil
        for _, n in ipairs(c1) do if role_ex(n.pitch, root_pitch) == target_role then target_note = n; break end end
        if target_note then
            local base_p = target_note.pitch
            for _, n in ipairs(c1) do
                if n ~= target_note then
                    local dist = (n.pitch - base_p) % 12; if dist == 0 then dist = 12 end
                    local new_p = base_p + dist
                    if new_p ~= n.pitch then r.MIDI_SetNote(take, n.idx, nil,nil,nil,nil,nil, new_p, nil, true); n.pitch = new_p end
                end
            end
        end
    end
    for i = 2, #chords do
        local curr = chords[i]; local target = GetCentroid(chords[i-1])
        for _, note in ipairs(curr) do
            local best = note.pitch; local dist = math.abs(note.pitch - target)
            local d = note.pitch - 12; if d>=0 and math.abs(d-target)<dist then best=d; dist=math.abs(d-target) end
            local u = note.pitch + 12; if u<=127 and math.abs(u-target)<dist then best=u end
            if best ~= note.pitch then r.MIDI_SetNote(take, note.idx, nil,nil,nil,nil,nil, best, nil, true); note.pitch = best end
        end
    end
end

-- === HUMANIZE ACTIONS ===
local function Action_HumanizeVel(take, hwnd)
    local _, cnt = r.MIDI_CountEvts(take)
    local range = settings.hum_vel_str
    r.MIDI_DisableSort(take)
    for i = 0, cnt - 1 do
        local _, sel, _, _, _, _, _, vel = r.MIDI_GetNote(take, i)
        if sel then
            local drift = math.random(-range, range)
            r.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, nil, math.max(1, math.min(127, vel + drift)), false)
        end
    end
    r.MIDI_Sort(take)
end

local function Action_HumanizeTiming(take, hwnd)
    -- AUTO-TRIM LOGIC
    local _, cnt = r.MIDI_CountEvts(take)
    local notes = {}
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then table.insert(notes, {idx=i, start=start, endp=endp, pitch=pitch}) end
    end
    if #notes == 0 then return end
    
    table.sort(notes, function(a,b) 
        if a.pitch == b.pitch then return a.start < b.start end
        return a.pitch < b.pitch 
    end)
    
    r.MIDI_DisableSort(take)
    local range = settings.hum_time_str
    
    for i, note in ipairs(notes) do
        local drift = math.random(-range, range)
        local new_start = math.max(0, note.start + drift)
        
        if new_start >= note.endp - 5 then new_start = note.endp - 5 end
        
        if i > 1 then
            local prev = notes[i-1]
            if prev.pitch == note.pitch then
                if new_start < prev.endp then
                    r.MIDI_SetNote(take, prev.idx, nil, nil, nil, new_start, nil, nil, nil, false)
                    prev.endp = new_start 
                end
            end
        end
        r.MIDI_SetNote(take, note.idx, nil, nil, new_start, note.endp, nil, nil, nil, false)
    end
    r.MIDI_Sort(take)
end

-- ANCHOR STRUM: Linked to Global Direction
local function Action_Strum(take, hwnd)
    local chords = GetSelectedChords(take)
    local step = settings.strum_val
    
    r.MIDI_DisableSort(take)
    
    for _, chord in ipairs(chords) do
        -- 1. Find Anchor (Earliest time)
        local anchor_time = chord[1].start
        for _, n in ipairs(chord) do
            if n.start < anchor_time then anchor_time = n.start end
        end
        
        -- 2. Sort based on Global Direction settings (settings.direction)
        table.sort(chord, function(a,b) 
            if a.pitch == b.pitch then return a.idx < b.idx end
            if settings.direction == 1 then -- Global UP (Low -> High)
                return a.pitch < b.pitch 
            else -- Global DOWN (High -> Low)
                return a.pitch > b.pitch 
            end
        end)
        
        -- 3. Apply Offsets from Anchor
        for i = 1, #chord do
            local note = chord[i]
            local offset = (i - 1) * step
            local new_start = anchor_time + offset
            
            -- Prevent overlap (Fixed End)
            if new_start >= note.endp - 5 then new_start = note.endp - 5 end
            
            r.MIDI_SetNote(take, note.idx, nil, nil, new_start, note.endp, nil, nil, nil, false)
        end
    end
    r.MIDI_Sort(take)
end

-- === GUI ===
local function SafePushStyleColor(col_idx, col_val) if r.ImGui_PushStyleColor then r.ImGui_PushStyleColor(ctx, col_idx, col_val) end end
local function SafePopStyleColor(count) if r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, count) end end
local function SafePushStyleVar(var_idx, ...) if r.ImGui_PushStyleVar then r.ImGui_PushStyleVar(ctx, var_idx, ...) end end
local function SafePopStyleVar(count) if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, count) end end

local function DrawSettings()
    local visible, open = r.ImGui_Begin(ctx, 'Settings', true, r.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
        local rv, nv
        rv, nv = r.ImGui_Checkbox(ctx, "Sync Close (with MIDI Editor)", settings.auto_close)
        if rv then settings.auto_close = nv; SaveState() end
        Tooltip("Automatically close this script when you close the MIDI Editor")
        
        rv, nv = r.ImGui_Checkbox(ctx, "Show Tooltips", settings.show_tooltips)
        if rv then settings.show_tooltips = nv; SaveState() end
        Tooltip("Enable or disable popup help text on hover")
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Chord Detection:")
        r.ImGui_SetNextItemWidth(ctx, 150)
        rv, nv = r.ImGui_SliderInt(ctx, "Tolerance (ticks)", settings.tolerance, 0, 200)
        if rv then settings.tolerance = nv; SaveState() end
        Tooltip("How loose chords can be played (in ticks) to still be detected as chords for Strumming/Humanizing")
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Theme:")
        rv, nv = r.ImGui_ColorEdit4(ctx, "Accent Color", settings.accent_col, r.ImGui_ColorEditFlags_NoInputs())
        if rv then settings.accent_col = nv; SaveState() end
        Tooltip("Main color for headers and active buttons")
        
        rv, nv = r.ImGui_ColorEdit4(ctx, "Secondary Color", settings.sec_col, r.ImGui_ColorEditFlags_NoInputs())
        if rv then settings.sec_col = nv; SaveState() end
        Tooltip("Color for destructive/heavy actions like Mute and Voice Leading")
        
        r.ImGui_End(ctx)
    end
    if not open then settings.show_settings = false end
end

local function loop()
    if settings.auto_close and not r.MIDIEditor_GetActive() then SaveState(); return end

    local ACCENT = settings.accent_col or DEFAULT_ACCENT
    local SEC    = settings.sec_col or DEFAULT_SEC
    
    SafePushStyleColor(r.ImGui_Col_WindowBg(), BG_COLOR)
    SafePushStyleColor(r.ImGui_Col_TitleBgActive(), ACCENT)
    SafePushStyleColor(r.ImGui_Col_TitleBg(), ACCENT) 
    SafePushStyleColor(r.ImGui_Col_Button(), FRAME_BG)
    SafePushStyleColor(r.ImGui_Col_ButtonHovered(), 0x444444FF)
    SafePushStyleColor(r.ImGui_Col_ButtonActive(), ACCENT)
    SafePushStyleColor(r.ImGui_Col_CheckMark(), ACCENT)
    SafePushStyleColor(r.ImGui_Col_SliderGrab(), ACCENT)
    SafePushStyleColor(r.ImGui_Col_SliderGrabActive(), ACCENT)
    SafePushStyleColor(r.ImGui_Col_FrameBg(), 0x333333FF)
    SafePushStyleColor(r.ImGui_Col_Text(), TEXT_COLOR)
    
    SafePushStyleVar(r.ImGui_StyleVar_WindowRounding(), 6)
    SafePushStyleVar(r.ImGui_StyleVar_FrameRounding(), 4)
    SafePushStyleVar(r.ImGui_StyleVar_ItemSpacing(), 8, 8)

    if settings.show_settings then DrawSettings() end

    local visible, open = r.ImGui_Begin(ctx, 'Chord Editor v46.0', true, r.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
        -- Header
        if r.ImGui_Button(ctx, "Settings") then settings.show_settings = not settings.show_settings end
        Tooltip("Open configuration (Theme, Tolerance, Sync Close)")
        
        r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, 0xAAAAAAFF, "| Direction:")
        r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "DOWN", settings.direction == -1) then settings.direction = -1 end
        Tooltip("Harmonize intervals downwards / Strum High->Low (Upstroke)")
        r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "UP", settings.direction == 1) then settings.direction = 1 end
        Tooltip("Harmonize intervals upwards / Strum Low->High (Downstroke)")
        
        -- 1. ADD CHORD
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "ADD CHORD")
        local w = 60; if r.ImGui_GetContentRegionAvail then w = (r.ImGui_GetContentRegionAvail(ctx)-24)/4 end
        
        if r.ImGui_Button(ctx, "Triad", w) then DoAction(function(t,h) Action_BuildChord(t,h,"triad") end, "Build Triad") end; Tooltip("Build a Triad (Root-3-5) on selected notes")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Sus2", w) then DoAction(function(t,h) Action_BuildChord(t,h,"sus2") end, "Build Sus2") end; Tooltip("Build a Sus2 chord (Root-2-5)")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Sus4", w) then DoAction(function(t,h) Action_BuildChord(t,h,"sus4") end, "Build Sus4") end; Tooltip("Build a Sus4 chord (Root-4-5)")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Dim/Aug", w) then r.ImGui_OpenPopup(ctx, "dimaug_popup") end; Tooltip("Build Diminished or Augmented triads (Fixed intervals)")
        if r.ImGui_BeginPopup(ctx, "dimaug_popup") then
            if r.ImGui_Selectable(ctx, "Diminished (0-3-6)") then DoAction(function(t,h) Action_BuildChord(t,h,"dim") end, "Build Dim") end
            if r.ImGui_Selectable(ctx, "Augmented (0-4-8)") then DoAction(function(t,h) Action_BuildChord(t,h,"aug") end, "Build Aug") end
            r.ImGui_EndPopup(ctx)
        end
        
        -- 2. ADD INTERVAL
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "ADD INTERVAL")
        local p = (settings.direction == 1) and "+" or "-"
        if r.ImGui_Button(ctx, p.."2nd", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,1) end, "Add 2nd") end; Tooltip("Add a 2nd interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."3rd", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,2) end, "Add 3rd") end; Tooltip("Add a 3rd interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."4th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,3) end, "Add 4th") end; Tooltip("Add a 4th interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."5th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,4) end, "Add 5th") end; Tooltip("Add a 5th interval")
        
        if r.ImGui_Button(ctx, p.."6th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,5) end, "Add 6th") end; Tooltip("Add a 6th interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."7th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,6) end, "Add 7th") end; Tooltip("Add a 7th interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."9th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,8) end, "Add 9th") end; Tooltip("Add a 9th interval")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Ext...", w) then r.ImGui_OpenPopup(ctx, "ext_popup") end; Tooltip("More intervals (11th, 13th, Octave)")
        if r.ImGui_BeginPopup(ctx, "ext_popup") then
            if r.ImGui_Selectable(ctx, p.."11th") then DoAction(function(t,h) Action_SmartHarmonize(t,h,10) end, "Add 11th") end
            if r.ImGui_Selectable(ctx, p.."13th") then DoAction(function(t,h) Action_SmartHarmonize(t,h,12) end, "Add 13th") end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, p.."Octave") then DoAction(function(t,h) Action_SmartHarmonize(t,h,7) end, "Add Octave") end
            r.ImGui_EndPopup(ctx)
        end

        -- 3. VOICING
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "CHORD VOICING")
        local bw = w * 2 + 4; if r.ImGui_GetContentRegionAvail then bw = (r.ImGui_GetContentRegionAvail(ctx)-8)/2 end
        
        -- Inversions (Hardcoded Direction 1/-1)
        if r.ImGui_Button(ctx, "Inv DOWN", bw) then DoAction(function(t,h) Action_InvertChords(t,h,-1) end, "Invert Down") end; Tooltip("Move the highest note down an octave")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Inv UP", bw) then DoAction(function(t,h) Action_InvertChords(t,h,1) end, "Invert Up") end; Tooltip("Move the lowest note up an octave")
        
        if r.ImGui_Button(ctx, "Drop 2", bw) then DoAction(function(t,h) Action_DropVoicing(t,h,2) end, "Drop 2") end; Tooltip("Move the 2nd highest note down an octave")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Drop 3", bw) then DoAction(function(t,h) Action_DropVoicing(t,h,3) end, "Drop 3") end; Tooltip("Move the 3rd highest note down an octave")
        
        r.ImGui_PushItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, "##vlmode", settings.voice_mode == 0 and "Lead: Follow First" or (settings.voice_mode == 1 and "Lead: Anchor Root" or (settings.voice_mode == 2 and "Lead: Anchor 3rd" or "Lead: Anchor 5th"))) then
            if r.ImGui_Selectable(ctx, "Follow First Chord", settings.voice_mode == 0) then settings.voice_mode = 0 end
            if r.ImGui_Selectable(ctx, "Anchor: Root (Closed)", settings.voice_mode == 1) then settings.voice_mode = 1 end
            if r.ImGui_Selectable(ctx, "Anchor: 3rd (1st Inv)", settings.voice_mode == 2) then settings.voice_mode = 2 end
            if r.ImGui_Selectable(ctx, "Anchor: 5th (2nd Inv)", settings.voice_mode == 3) then settings.voice_mode = 3 end
            r.ImGui_EndCombo(ctx)
        end; Tooltip("Choose logic for Voice Leading algorithm")
        r.ImGui_PopItemWidth(ctx)
        local glue_w = (r.ImGui_GetContentRegionAvail(ctx) - 8) / 3; local voice_w = r.ImGui_GetContentRegionAvail(ctx) - glue_w - 8
        
        SafePushStyleColor(r.ImGui_Col_Button(), SEC)
        SafePushStyleColor(r.ImGui_Col_ButtonHovered(), Lighten(SEC, 20))
        if r.ImGui_Button(ctx, "APPLY VOICE LEADING", voice_w) then DoAction(Action_VoiceLeading, "Voice Leading") end; Tooltip("Automatically invert chords to minimize movement")
        SafePopStyleColor(2)
        
        r.ImGui_SameLine(ctx); SafePushStyleColor(r.ImGui_Col_Button(), ACCENT); if r.ImGui_Button(ctx, "GLUE", glue_w) then DoAction(Action_GlueNotes, "Glue") end; SafePopStyleColor(1); Tooltip("Merge adjacent selected notes")

        -- 4. SELECTION
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "SELECTION")
        if r.ImGui_Button(ctx, "SELECT ALL NOTES", -1) then DoAction(SelectAllNotes, "Select All") end; Tooltip("Select all notes in the active MIDI item")
        local rv, nv
        rv, nv = r.ImGui_Checkbox(ctx, "ROOT", settings.targets.root); r.ImGui_SameLine(ctx); if rv then settings.targets.root = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "3rd", settings.targets.third); r.ImGui_SameLine(ctx); if rv then settings.targets.third = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "5th", settings.targets.fifth); r.ImGui_SameLine(ctx); if rv then settings.targets.fifth = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "7th", settings.targets.seventh); if rv then settings.targets.seventh = nv end
        SafePushStyleColor(r.ImGui_Col_Button(), ACCENT); if r.ImGui_Button(ctx, "FILTER SELECTION", -1) then DoAction(Action_FilterSelection, "Filter") end; SafePopStyleColor(1); Tooltip("Keep only the selected chord intervals, deselect others")

        -- 5. TOOLS
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "TOOLS")
        if r.ImGui_Button(ctx, "Oct -1", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"move",-12) end, "Octave Down") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Oct +1", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"move",12) end, "Octave Up") end
        if r.ImGui_Button(ctx, "Dup -12", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"duplicate",-12) end, "Dup -12") end; Tooltip("Duplicate selection 1 octave down")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Dup +12", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"duplicate",12) end, "Dup +12") end; Tooltip("Duplicate selection 1 octave up")
        
        -- MUTE BUTTON USING SEC COLOR
        SafePushStyleColor(r.ImGui_Col_Button(), SEC); 
        SafePushStyleColor(r.ImGui_Col_ButtonHovered(), Lighten(SEC, 30))
        if r.ImGui_Button(ctx, "MUTE", -1) then DoAction(function(t,h) Action_SimpleEdit(t,h,"mute",0) end, "Mute") end; Tooltip("Toggle Mute for selected notes")
        SafePopStyleColor(2)

        -- 6. HUMANIZE (CLASSIC: SLIDER + BUTTON)
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "HUMANIZE")
        
        local hum_bw = 70
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        local slider_w = avail_w - hum_bw - 8 -- Standard width for Vel/Time
        
        -- Velocity
        r.ImGui_SetNextItemWidth(ctx, slider_w)
        rv, nv = r.ImGui_SliderInt(ctx, "##vel", settings.hum_vel_str, 1, 60, "Vel +/- %d")
        if rv then settings.hum_vel_str = nv end; Tooltip("Velocity randomization range")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Apply##Vel", hum_bw) then DoAction(Action_HumanizeVel, "Hum Velocity") end; Tooltip("Randomize velocity")

        -- Timing
        r.ImGui_SetNextItemWidth(ctx, slider_w)
        rv, nv = r.ImGui_SliderInt(ctx, "##time", settings.hum_time_str, 1, 100, "Time +/- %d")
        if rv then settings.hum_time_str = nv end; Tooltip("Timing randomization range (ticks)")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Apply##Time", hum_bw) then DoAction(Action_HumanizeTiming, "Hum Timing") end; Tooltip("Randomize Start Time (Attack) without changing End Time")

        -- Strum
        r.ImGui_SetNextItemWidth(ctx, slider_w)
        rv, nv = r.ImGui_SliderInt(ctx, "##strum", settings.strum_val, 1, 120, "Strum: %d ticks")
        if rv then settings.strum_val = nv end; Tooltip("Strum offset per note (ticks)")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Apply##Strum", hum_bw) then DoAction(Action_Strum, "Strum") end
        Tooltip("Strum chords (Delay note starts). \nDirection follows 'Direction' toggle at the top.")

        r.ImGui_End(ctx)
    end
    
    SafePopStyleColor(11)
    SafePopStyleVar(3)
    if open then r.defer(loop) end
end
r.defer(loop)
