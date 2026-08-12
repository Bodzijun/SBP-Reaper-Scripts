-- @description Chord Voicing Editor v47.0 (Safer Chords & Optimized Voice Leading)
-- @version 47.0
-- @author SBP & Gemini (modified by TouristKiller)
-- @donation Donate via PayPal: mailto:bodzik@gmail.com
-- @about
--   This script provides an advanced chord voicing editor for MIDI within REAPER.
--   1. ADD CHORD (Triads, Sus, Dim, Aug)
--   2. ADD INTERVAL (Extensions)
--   3. CHORD VOICING (Inversions, Drops, Voice Leading + Glue)
--   4. SELECTION (Select All + Filter)
--   5. TOOLS (Octaves, Duplication, Glue)
--   6. HUMANIZE (Classic Buttons + Sliders)
-- @link https://forum.cockos.com/showthread.php?t=305655
-- @changelog
--   add Strum.(the direction depends on the mode up or down at top of scrip)
--   add Settings.(theme colour settings, enable hints, slider for adjusting chord sensitivity, how much note deviation is allowed in time (useful if humanisation is applied to chords), "sync close" button moved)
--   Improved humanisation algorithm (chords are now determined even after shifted in time (tolerance in settings)
--   fixed: tritone no longer belongs to fifths
--   fixed: The algorithm for gluing neighbouring notes has been corrected.

local r = reaper
local ctx = r.ImGui_CreateContext('Chord Voicing Editor v47.0')

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
    max_chord_span = 180,
    glue_tolerance = 15,
    voice_lock_bass = false,
    voice_lock_top = false,
    voice_low = 36,
    voice_high = 96,
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
    if not settings.max_chord_span then settings.max_chord_span = 180 end
    if not settings.glue_tolerance then settings.glue_tolerance = 15 end
    if settings.voice_lock_bass == nil then settings.voice_lock_bass = false end
    if settings.voice_lock_top == nil then settings.voice_lock_top = false end
    if not settings.voice_low then settings.voice_low = 36 end
    if not settings.voice_high then settings.voice_high = 96 end
    if not settings.accent_col then settings.accent_col = DEFAULT_ACCENT end
    if not settings.sec_col then settings.sec_col = DEFAULT_SEC end
    settings.tolerance = math.max(0, math.min(200, settings.tolerance))
    settings.max_chord_span = math.max(20, math.min(960, settings.max_chord_span))
    settings.glue_tolerance = math.max(0, math.min(240, settings.glue_tolerance))
    settings.voice_low = math.max(0, math.min(126, settings.voice_low))
    settings.voice_high = math.max(1, math.min(127, settings.voice_high))
    if settings.voice_low >= settings.voice_high then
        settings.voice_low, settings.voice_high = 36, 96
    end
end

-- Load State. v46 is accepted as a migration source.
local ext_state = r.GetExtState("ChordVoicingEditor", "Settings_v47")
if ext_state == "" then ext_state = r.GetExtState("ChordVoicingEditor", "Settings_v46") end
if ext_state ~= "" then
    local values = {}
    for token in ext_state:gmatch("[^,]+") do values[#values + 1] = tonumber(token) end
    if values[1] then settings.direction = values[1] end
    if values[2] then settings.voice_mode = values[2] end
    if values[3] then settings.auto_close = values[3] == 1 end
    if values[4] then settings.show_tooltips = values[4] == 1 end
    if values[5] then settings.hum_vel_str = values[5] end
    if values[6] then settings.hum_time_str = values[6] end
    if values[7] then settings.strum_val = values[7] end
    if values[8] then settings.tolerance = values[8] end
    if values[9] then settings.accent_col = values[9] end
    if values[10] then settings.sec_col = values[10] end
    if values[11] then settings.max_chord_span = values[11] end
    if values[12] then settings.glue_tolerance = values[12] end
    if values[13] then settings.voice_lock_bass = values[13] == 1 end
    if values[14] then settings.voice_lock_top = values[14] == 1 end
    if values[15] then settings.voice_low = values[15] end
    if values[16] then settings.voice_high = values[16] end
    if values[17] then settings.targets.root = values[17] == 1 end
    if values[18] then settings.targets.third = values[18] == 1 end
    if values[19] then settings.targets.fifth = values[19] == 1 end
    if values[20] then settings.targets.seventh = values[20] == 1 end
end
ValidateSettings() 

local function SaveState()
    local ac_val = settings.auto_close and 1 or 0
    local tips_val = settings.show_tooltips and 1 or 0
    local col_val = math.floor(settings.accent_col or DEFAULT_ACCENT)
    local scol_val = math.floor(settings.sec_col or DEFAULT_SEC)
    
    local str = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
        settings.direction, settings.voice_mode, ac_val, tips_val,
        settings.hum_vel_str, settings.hum_time_str, settings.strum_val,
        settings.tolerance, col_val, scol_val, settings.max_chord_span,
        settings.glue_tolerance, settings.voice_lock_bass and 1 or 0,
        settings.voice_lock_top and 1 or 0, settings.voice_low, settings.voice_high,
        settings.targets.root and 1 or 0, settings.targets.third and 1 or 0,
        settings.targets.fifth and 1 or 0, settings.targets.seventh and 1 or 0)
    r.SetExtState("ChordVoicingEditor", "Settings_v47", str, true)
end

-- === CONFIG CONSTANTS ===
local BG_COLOR        = 0x202020FF
local FRAME_BG        = 0x333333FF
local TEXT_COLOR      = 0xEEEEEEFF

local function Lighten(color, amt)
    local r = (color >> 24) & 0xFF
    local g = (color >> 16) & 0xFF
    local b = (color >> 8) & 0xFF
    local a = color & 0xFF
    r = math.min(255, r + amt); g = math.min(255, g + amt); b = math.min(255, b + amt)
    return (r << 24) | (g << 16) | (b << 8) | a
end

local CHROM_MAP = {
    [1]=2, [2]=4, [3]=5, [4]=7, [5]=9, [6]=10, [7]=12, 
    [8]=14, [10]=17, [11]=17, [12]=21, [13]=21 
}

-- Explicit chord qualities. The root is the selected seed note and therefore
-- is not repeated in these interval lists.
local CHORD_TYPES = {
    major = {4, 7}, minor = {3, 7},
    maj7 = {4, 7, 11}, min7 = {3, 7, 10}, dominant7 = {4, 7, 10},
    minor_major7 = {3, 7, 11}, half_dim = {3, 6, 10}, dim7 = {3, 6, 9},
    sixth = {4, 7, 9}, minor6 = {3, 7, 9}, add9 = {4, 7, 14},
    six_nine = {4, 7, 9, 14}, sus7 = {5, 7, 10},
    dim = {3, 6}, aug = {4, 8}, quartal = {5, 10}
}

-- Lua starts with a deterministic PRNG sequence unless explicitly seeded.
local seed_source = r.time_precise and r.time_precise() or os.clock()
math.randomseed(math.floor(seed_source * 1000000) % 2147483647)
math.random(); math.random(); math.random()

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
            for i=0,11 do if ((m>>i)&1)==1 then map[(root+i)%12]=true; valid=true end end
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

local function NoteKey(chan, pitch, startppq)
    return string.format("%d:%d:%d", chan, pitch, math.floor(startppq + 0.5))
end

local function BuildNoteLookup(take)
    local lookup = {}
    local _, cnt = r.MIDI_CountEvts(take)
    for i = 0, cnt - 1 do
        local ok, _, _, startppq, _, chan, pitch = r.MIDI_GetNote(take, i)
        if ok then lookup[NoteKey(chan, pitch, startppq)] = true end
    end
    return lookup
end

local function InsertUniqueNotes(take, notes, select_new)
    local lookup = BuildNoteLookup(take)
    local inserted = 0
    for _, n in ipairs(notes) do
        local key = NoteKey(n.chan, n.pitch, n.start)
        if not lookup[key] then
            r.MIDI_InsertNote(take, select_new, n.muted, n.start, n.endppq,
                n.chan, n.pitch, n.vel, true)
            lookup[key] = true
            inserted = inserted + 1
        end
    end
    return inserted
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
    local chord_anchor = all_sel[1].start
    local last_added_start = all_sel[1].start
    
    for i = 2, #all_sel do
        local note = all_sel[i]
        local near_previous = math.abs(note.start - last_added_start) <= settings.tolerance
        local inside_span = math.abs(note.start - chord_anchor) <= settings.max_chord_span
        if near_previous and inside_span then
            table.insert(current_chord, note)
            last_added_start = note.start
        else
            table.sort(current_chord, function(a,b) return a.pitch < b.pitch end)
            table.insert(chords, current_chord)
            current_chord = {note}
            chord_anchor = note.start
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
    if not hwnd then return end
    local take = r.MIDIEditor_GetTake(hwnd)
    if not take then return end
    local item = r.GetMediaItemTake_Item(take)
    r.Undo_BeginBlock2(0)
    r.MIDI_DisableSort(take)
    local ok, err = xpcall(function() func(take, hwnd) end, debug.traceback)
    r.MIDI_Sort(take)
    r.UpdateItemInProject(item)
    if ok then
        r.Undo_EndBlock2(0, name, -1)
        SaveState()
    else
        r.Undo_EndBlock2(0, name .. " (failed)", -1)
        r.ShowMessageBox("Chord Voicing Editor error:\n\n" .. tostring(err), "Chord Voicing Editor", 0)
    end
end

-- === ACTIONS ===
local function SelectAllNotes(take)
    r.MIDI_SelectAll(take, true)
end

local function Action_SmartHarmonize(take, hwnd, steps, fixed_semitones)
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local map = nil
    if scale_enabled then map = GetScaleBitMap(take, hwnd) end
    local chords = GetSelectedChords(take)
    local notes_to_add = {}
    for _, chord in ipairs(chords) do
        if #chord == 1 then
            local note = chord[1]
            local np = fixed_semitones and (note.pitch + fixed_semitones * settings.direction)
                or (scale_enabled and GetDiatonicPitch(note.pitch, map, steps, settings.direction)
                or (note.pitch + ((CHROM_MAP[steps] or 12) * settings.direction)))
            if np >= 0 and np <= 127 then table.insert(notes_to_add, {muted=note.muted, start=note.start, endppq=note.endp, chan=note.chan, pitch=np, vel=note.vel}) end
        elseif #chord > 1 then
            local pitches = {}; local pitch_lookup = {} 
            for _, n in ipairs(chord) do table.insert(pitches, n.pitch); pitch_lookup[n.pitch] = true end
            local bass_pitch = pitches[1]
            local scale_root = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
            local root_pitch_class = FindChordRoot(pitches, scale_root)
            local root_pitch = bass_pitch + ((root_pitch_class - (bass_pitch % 12) + 12) % 12)
            local target_pitch = fixed_semitones and (root_pitch + fixed_semitones * settings.direction)
                or (scale_enabled and GetDiatonicPitch(root_pitch, map, steps, settings.direction)
                or (root_pitch + ((CHROM_MAP[steps] or 12) * settings.direction)))
            if not pitch_lookup[target_pitch] and target_pitch >= 0 and target_pitch <= 127 then
                 local ref_note = chord[1] 
                 table.insert(notes_to_add, {muted=ref_note.muted, start=ref_note.start, endppq=ref_note.endp, chan=ref_note.chan, pitch=target_pitch, vel=ref_note.vel})
            end
        end
    end
    r.MIDI_SelectAll(take, false)
    InsertUniqueNotes(take, notes_to_add, true)
end

local function Action_BuildChord(take, hwnd, type_str)
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local map = nil
    if scale_enabled then map = GetScaleBitMap(take, hwnd) end
    local add = {}
    local scale_root = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
    for _, chord in ipairs(GetSelectedChords(take)) do
        local seed = chord[1]
        if #chord > 1 then
            local pitches = {}
            for _, note in ipairs(chord) do pitches[#pitches + 1] = note.pitch end
            local root_pc = FindChordRoot(pitches, scale_root)
            for _, note in ipairs(chord) do
                if note.pitch % 12 == root_pc then
                    if not seed or (settings.direction == 1 and note.pitch < seed.pitch)
                            or (settings.direction == -1 and note.pitch > seed.pitch) then
                        seed = note
                    elseif seed.pitch % 12 ~= root_pc then
                        seed = note
                    end
                end
            end
        end
        local pitch = seed.pitch
        local intervals = {}
        if CHORD_TYPES[type_str] then
            for _, semitones in ipairs(CHORD_TYPES[type_str]) do
                intervals[#intervals + 1] = pitch + semitones * settings.direction
            end
        elseif type_str == "triad" then
            if scale_enabled then intervals = {GetDiatonicPitch(pitch, map, 2, settings.direction), GetDiatonicPitch(pitch, map, 4, settings.direction)}
            else intervals = {pitch + 4 * settings.direction, pitch + 7 * settings.direction} end
        elseif type_str == "sus2" then
            if scale_enabled then intervals = {GetDiatonicPitch(pitch, map, 1, settings.direction), GetDiatonicPitch(pitch, map, 4, settings.direction)}
            else intervals = {pitch + 2 * settings.direction, pitch + 7 * settings.direction} end
        elseif type_str == "sus4" then
            if scale_enabled then intervals = {GetDiatonicPitch(pitch, map, 3, settings.direction), GetDiatonicPitch(pitch, map, 4, settings.direction)}
            else intervals = {pitch + 5 * settings.direction, pitch + 7 * settings.direction} end
        end
        for _, new_pitch in ipairs(intervals) do
            if new_pitch >= 0 and new_pitch <= 127 then
                add[#add + 1] = {muted=seed.muted, start=seed.start, endppq=seed.endp,
                    chan=seed.chan, pitch=new_pitch, vel=seed.vel}
            end
        end
    end
    r.MIDI_SelectAll(take, false)
    InsertUniqueNotes(take, add, true)
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
        InsertUniqueNotes(take, to_dup, true)
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
        if a.chan ~= b.chan then return a.chan < b.chan end
        if a.pitch ~= b.pitch then return a.pitch < b.pitch end
        if a.muted ~= b.muted then return not a.muted end
        return a.start < b.start
    end)

    r.MIDI_DisableSort(take)
    local to_delete = {}
    local i = 1
    while i < #sel_notes do
        local curr = sel_notes[i]
        local next_n = sel_notes[i+1]
        if next_n and curr.pitch == next_n.pitch
                and curr.chan == next_n.chan and curr.muted == next_n.muted then
            local gap = next_n.start - curr.endp
            if gap <= settings.glue_tolerance then
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

local function SortedChordPitches(chord)
    local pitches = {}
    for _, note in ipairs(chord) do pitches[#pitches + 1] = note.pitch end
    table.sort(pitches)
    return pitches
end

local function VoiceTarget(prev_pitches, voice_index, voice_count)
    if voice_count == 1 then
        local sum = 0
        for _, pitch in ipairs(prev_pitches) do sum = sum + pitch end
        return sum / #prev_pitches
    end
    local position = (voice_index - 1) / (voice_count - 1)
    local prev_index = math.floor(1 + position * (#prev_pitches - 1) + 0.5)
    return prev_pitches[prev_index]
end

local function PitchCandidates(original_pitch, locked, target)
    if locked then return {original_pitch} end
    local low = math.max(0, math.min(settings.voice_low, settings.voice_high))
    local high = math.min(127, math.max(settings.voice_low, settings.voice_high))
    local pc = original_pitch % 12
    local candidates, seen = {}, {}
    for pitch = low, high do
        if pitch % 12 == pc then
            candidates[#candidates + 1] = pitch
            seen[pitch] = true
        end
    end
    if not seen[original_pitch] then candidates[#candidates + 1] = original_pitch end
    table.sort(candidates, function(a, b)
        local da, db = math.abs(a - target), math.abs(b - target)
        if da == db then return math.abs(a - original_pitch) < math.abs(b - original_pitch) end
        return da < db
    end)
    return candidates
end

-- Find the lowest-cost ascending realization. Voices are compared with
-- corresponding previous voices and are never allowed to cross.
local function OptimizeChordVoicing(previous, current)
    local prev_pitches = SortedChordPitches(previous)
    local voice_count = #current
    local candidate_sets, targets = {}, {}
    for i, note in ipairs(current) do
        local target = VoiceTarget(prev_pitches, i, voice_count)
        targets[i] = target
        local locked = (settings.voice_lock_bass and i == 1)
            or (settings.voice_lock_top and i == voice_count)
        candidate_sets[i] = PitchCandidates(note.pitch, locked, target)
    end

    local best_cost = math.huge
    local best, working = nil, {}
    local function search(i, last_pitch, running_cost)
        if running_cost >= best_cost then return end
        if i > voice_count then
            best_cost = running_cost
            best = {}
            for n = 1, voice_count do best[n] = working[n] end
            return
        end
        local original, target = current[i].pitch, targets[i]
        for _, pitch in ipairs(candidate_sets[i]) do
            if not last_pitch or pitch > last_pitch then
                local movement = math.abs(pitch - target)
                local cost = movement
                if movement > 7 then cost = cost + (movement - 7) * 2.0 end
                cost = cost + math.abs(pitch - original) * 0.08
                -- Exact common tones naturally have zero movement cost.
                if last_pitch then
                    local spacing = pitch - last_pitch
                    if spacing > 12 then cost = cost + (spacing - 12) * 0.8 end
                    if spacing < 3 then cost = cost + (3 - spacing) * 1.5 end
                end
                working[i] = pitch
                search(i + 1, pitch, running_cost + cost)
            end
        end
    end
    search(1, nil, 0)
    return best or SortedChordPitches(current)
end

local function Action_VoiceLeading(take, hwnd)
    local chords = GetSelectedChords(take)
    if #chords < 2 then return end

    local c1 = chords[1]
    if settings.voice_mode > 0 and #c1 > 1 then
        local pitches = SortedChordPitches(c1)
        local bass = pitches[1]
        local scale = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
        local scale_root = scale and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
        local root_pc = FindChordRoot(pitches, scale_root)
        local root_pitch = bass + ((root_pc - (bass % 12) + 12) % 12)
        local target_role = settings.voice_mode == 1 and "root"
            or (settings.voice_mode == 2 and "third" or "fifth")
        local function role_of(pitch)
            local interval = (pitch - root_pitch) % 12
            if interval == 0 then return "root" end
            if interval == 3 or interval == 4 then return "third" end
            if interval == 7 or interval == 8 then return "fifth" end
            return "other"
        end
        local anchor = nil
        for _, note in ipairs(c1) do
            if role_of(note.pitch) == target_role then anchor = note; break end
        end
        if anchor then
            local base_pitch = anchor.pitch
            for _, note in ipairs(c1) do
                if note ~= anchor then
                    local distance = (note.pitch - base_pitch) % 12
                    if distance == 0 then distance = 12 end
                    local new_pitch = base_pitch + distance
                    if new_pitch <= 127 and new_pitch ~= note.pitch then
                        r.MIDI_SetNote(take, note.idx, nil, nil, nil, nil, nil, new_pitch, nil, true)
                        note.pitch = new_pitch
                    end
                end
            end
        end
    end

    for chord_index = 2, #chords do
        local current = chords[chord_index]
        table.sort(current, function(a, b) return a.pitch < b.pitch end)
        local optimized = OptimizeChordVoicing(chords[chord_index - 1], current)
        for i, note in ipairs(current) do
            local new_pitch = optimized[i]
            if new_pitch and new_pitch ~= note.pitch then
                r.MIDI_SetNote(take, note.idx, nil, nil, nil, nil, nil, new_pitch, nil, true)
                note.pitch = new_pitch
            end
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
        Tooltip("Maximum gap between consecutive attacks inside one chord")

        r.ImGui_SetNextItemWidth(ctx, 150)
        rv, nv = r.ImGui_SliderInt(ctx, "Max chord span", settings.max_chord_span, 20, 960)
        if rv then settings.max_chord_span = nv; SaveState() end
        Tooltip("Maximum time from the first to the last note of a strummed chord")

        r.ImGui_SetNextItemWidth(ctx, 150)
        rv, nv = r.ImGui_SliderInt(ctx, "Glue gap", settings.glue_tolerance, 0, 240)
        if rv then settings.glue_tolerance = nv; SaveState() end
        Tooltip("Maximum gap in ticks between notes merged by Glue")

        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Voice Leading Optimizer:")
        rv, nv = r.ImGui_Checkbox(ctx, "Lock Bass", settings.voice_lock_bass)
        if rv then settings.voice_lock_bass = nv; SaveState() end
        Tooltip("Keep the original MIDI pitch of each chord's bass note")
        r.ImGui_SameLine(ctx)
        rv, nv = r.ImGui_Checkbox(ctx, "Lock Top", settings.voice_lock_top)
        if rv then settings.voice_lock_top = nv; SaveState() end
        Tooltip("Keep the original MIDI pitch of each chord's top note")

        r.ImGui_SetNextItemWidth(ctx, 150)
        rv, nv = r.ImGui_SliderInt(ctx, "Lowest note", settings.voice_low, 0, 126)
        if rv then settings.voice_low = math.min(nv, settings.voice_high - 1); SaveState() end
        r.ImGui_SetNextItemWidth(ctx, 150)
        rv, nv = r.ImGui_SliderInt(ctx, "Highest note", settings.voice_high, 1, 127)
        if rv then settings.voice_high = math.max(nv, settings.voice_low + 1); SaveState() end
        Tooltip("Preferred register for generated inversions; original out-of-range notes remain available")
        
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

    local visible, open = r.ImGui_Begin(ctx, 'Chord Editor v47.0', true, r.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
        -- Header
        if r.ImGui_Button(ctx, "Settings") then settings.show_settings = not settings.show_settings end
        Tooltip("Open configuration (Theme, Tolerance, Sync Close)")
        
        r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, 0xAAAAAAFF, "| Direction:")
        r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "DOWN", settings.direction == -1) then settings.direction = -1; SaveState() end
        Tooltip("Harmonize intervals downwards / Strum High->Low (Upstroke)")
        r.ImGui_SameLine(ctx); if r.ImGui_RadioButton(ctx, "UP", settings.direction == 1) then settings.direction = 1; SaveState() end
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
        if r.ImGui_Button(ctx, "Chords...", w) then r.ImGui_OpenPopup(ctx, "dimaug_popup") end; Tooltip("Build explicit chord qualities and modern structures. Uses fixed interval formulas and ignores the key/scale selected in the MIDI Editor.")
        if r.ImGui_BeginPopup(ctx, "dimaug_popup") then
            if r.ImGui_Selectable(ctx, "Major") then DoAction(function(t,h) Action_BuildChord(t,h,"major") end, "Build Major") end
            if r.ImGui_Selectable(ctx, "Minor") then DoAction(function(t,h) Action_BuildChord(t,h,"minor") end, "Build Minor") end
            if r.ImGui_Selectable(ctx, "Major 7") then DoAction(function(t,h) Action_BuildChord(t,h,"maj7") end, "Build Major 7") end
            if r.ImGui_Selectable(ctx, "Minor 7") then DoAction(function(t,h) Action_BuildChord(t,h,"min7") end, "Build Minor 7") end
            if r.ImGui_Selectable(ctx, "Dominant 7") then DoAction(function(t,h) Action_BuildChord(t,h,"dominant7") end, "Build Dominant 7") end
            if r.ImGui_Selectable(ctx, "Minor Major 7") then DoAction(function(t,h) Action_BuildChord(t,h,"minor_major7") end, "Build Minor Major 7") end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "Half-Diminished 7") then DoAction(function(t,h) Action_BuildChord(t,h,"half_dim") end, "Build Half-Diminished 7") end
            if r.ImGui_Selectable(ctx, "Diminished") then DoAction(function(t,h) Action_BuildChord(t,h,"dim") end, "Build Diminished") end
            if r.ImGui_Selectable(ctx, "Diminished 7") then DoAction(function(t,h) Action_BuildChord(t,h,"dim7") end, "Build Diminished 7") end
            if r.ImGui_Selectable(ctx, "Augmented") then DoAction(function(t,h) Action_BuildChord(t,h,"aug") end, "Build Augmented") end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "6") then DoAction(function(t,h) Action_BuildChord(t,h,"sixth") end, "Build 6") end
            if r.ImGui_Selectable(ctx, "Minor 6") then DoAction(function(t,h) Action_BuildChord(t,h,"minor6") end, "Build Minor 6") end
            if r.ImGui_Selectable(ctx, "Add 9") then DoAction(function(t,h) Action_BuildChord(t,h,"add9") end, "Build Add 9") end
            if r.ImGui_Selectable(ctx, "6/9") then DoAction(function(t,h) Action_BuildChord(t,h,"six_nine") end, "Build 6/9") end
            if r.ImGui_Selectable(ctx, "7sus4") then DoAction(function(t,h) Action_BuildChord(t,h,"sus7") end, "Build 7sus4") end
            if r.ImGui_Selectable(ctx, "Quartal") then DoAction(function(t,h) Action_BuildChord(t,h,"quartal") end, "Build Quartal") end
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
            if r.ImGui_Selectable(ctx, p.."b9") then DoAction(function(t,h) Action_SmartHarmonize(t,h,8,13) end, "Add b9") end
            if r.ImGui_Selectable(ctx, p.."#9") then DoAction(function(t,h) Action_SmartHarmonize(t,h,8,15) end, "Add #9") end
            if r.ImGui_Selectable(ctx, p.."#11") then DoAction(function(t,h) Action_SmartHarmonize(t,h,10,18) end, "Add #11") end
            if r.ImGui_Selectable(ctx, p.."b13") then DoAction(function(t,h) Action_SmartHarmonize(t,h,12,20) end, "Add b13") end
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
            if r.ImGui_Selectable(ctx, "Follow First Chord", settings.voice_mode == 0) then settings.voice_mode = 0; SaveState() end
            if r.ImGui_Selectable(ctx, "Anchor: Root (Closed)", settings.voice_mode == 1) then settings.voice_mode = 1; SaveState() end
            if r.ImGui_Selectable(ctx, "Anchor: 3rd (1st Inv)", settings.voice_mode == 2) then settings.voice_mode = 2; SaveState() end
            if r.ImGui_Selectable(ctx, "Anchor: 5th (2nd Inv)", settings.voice_mode == 3) then settings.voice_mode = 3; SaveState() end
            r.ImGui_EndCombo(ctx)
        end; Tooltip("Choose logic for Voice Leading algorithm")
        r.ImGui_PopItemWidth(ctx)
        local glue_w = (r.ImGui_GetContentRegionAvail(ctx) - 8) / 3; local voice_w = r.ImGui_GetContentRegionAvail(ctx) - glue_w - 8
        
        SafePushStyleColor(r.ImGui_Col_Button(), SEC)
        SafePushStyleColor(r.ImGui_Col_ButtonHovered(), Lighten(SEC, 20))
        if r.ImGui_Button(ctx, "APPLY VOICE LEADING", voice_w) then DoAction(Action_VoiceLeading, "Voice Leading") end; Tooltip("Optimize corresponding voices, common tones, spacing and register without voice crossing")
        SafePopStyleColor(2)
        
        r.ImGui_SameLine(ctx); SafePushStyleColor(r.ImGui_Col_Button(), ACCENT); if r.ImGui_Button(ctx, "GLUE", glue_w) then DoAction(Action_GlueNotes, "Glue") end; SafePopStyleColor(1); Tooltip("Merge adjacent selected notes")

        -- 4. SELECTION
        r.ImGui_Separator(ctx); r.ImGui_TextColored(ctx, 0xFFFFFFFF, "SELECTION")
        if r.ImGui_Button(ctx, "SELECT ALL NOTES", -1) then DoAction(SelectAllNotes, "Select All") end; Tooltip("Select all notes in the active MIDI item")
        local rv, nv
        rv, nv = r.ImGui_Checkbox(ctx, "ROOT", settings.targets.root); r.ImGui_SameLine(ctx); if rv then settings.targets.root = nv; SaveState() end
        rv, nv = r.ImGui_Checkbox(ctx, "3rd", settings.targets.third); r.ImGui_SameLine(ctx); if rv then settings.targets.third = nv; SaveState() end
        rv, nv = r.ImGui_Checkbox(ctx, "5th", settings.targets.fifth); r.ImGui_SameLine(ctx); if rv then settings.targets.fifth = nv; SaveState() end
        rv, nv = r.ImGui_Checkbox(ctx, "7th", settings.targets.seventh); if rv then settings.targets.seventh = nv; SaveState() end
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
