-- @description Chord Voicing Editor v23.1 (TK Edition)
-- @version 23.1
-- @author SBP & Gemini (modified by TouristKiller)
-- @about
--   UI OVERHAUL & HUMANIZE 2.0
--
--   SECTIONS:
--   1. ADD CHORD (Triads, Sus, Dim, Aug)
--   2. ADD INTERVAL (Extensions)
--   3. CHORD VOICING (Inversions, Drops, Voice Leading)
--   4. SELECTION (Select All + Filter)
--   5. TOOLS (Octaves, Duplication)
--   6. HUMANIZE (Velocity & Timing with Sliders)
--
--   FEATURES:
--   - Persistent Settings for Sliders.
--   - Smart Harmonize & Voice Leading.
--   - Force Undo system.
--
-- @changelog
--   v23.1 (TK Edition):
--   + FIX: Replaced static chord_patterns dictionary with dynamic FindChordRoot algorithm
--     - Old system: Required manual entry for every chord type and inversion (~20 patterns)
--     - New system: Score-based analysis works for ANY chord automatically
--     - Perfect 5th interval = strongest root indicator (+10 points)
--     - Major/minor 3rd, 7ths, 6ths etc. contribute to root detection
--   + Scale-aware root detection: when "Snap to Scale" is enabled, the key root gets a bonus
--     - Helps resolve ambiguous chords like C6 vs Am7 based on musical context
--   + Bass note bonus: in ambiguous cases, the lowest note is preferred as root
--   + Improved get_role_exact function with clearer interval-to-role mapping
--   SBP changes:
--   + Some buttons (down-up, InvDown-InvUp) have been rearranged to maintain a consistent logic (negative actions on the left, positive actions on the right).


local r = reaper
local ctx = r.ImGui_CreateContext('Chord Voicing Editor v23.1 TK')

-- === CONFIG & PERSISTENCE ===
local ACCENT_COLOR    = 0x217763FF
local ACCENT_HOVER    = 0x2B9178FF
local ACCENT_ACTIVE   = 0x18594AFF
local BG_COLOR        = 0x202020FF
local FRAME_BG        = 0x333333FF
local TEXT_COLOR      = 0xEEEEEEFF

local settings = {
    targets = { root=true, third=false, fifth=false, seventh=false },
    direction = 1,      -- 1 = UP, -1 = DOWN
    voice_mode = 0,     -- 0=Follow, 1=Root, 2=3rd, 3=5th
    auto_close = true,
    hum_vel_str = 10,   -- Velocity strength +/-
    hum_time_str = 15   -- Timing strength (ticks) +/-
}

-- Load State
local ext_state = r.GetExtState("ChordVoicingEditor", "Settings_v23")
if ext_state ~= "" then
    local d, v, ac, hv, ht = ext_state:match("(-?%d),(%d),([01]),(%d+),(%d+)")
    if d then settings.direction = tonumber(d) end
    if v then settings.voice_mode = tonumber(v) end
    if ac then settings.auto_close = (ac == "1") end
    if hv then settings.hum_vel_str = tonumber(hv) end
    if ht then settings.hum_time_str = tonumber(ht) end
end

local function SaveState()
    local ac_val = settings.auto_close and 1 or 0
    local str = string.format("%d,%d,%d,%d,%d", 
        settings.direction, settings.voice_mode, ac_val, settings.hum_vel_str, settings.hum_time_str)
    r.SetExtState("ChordVoicingEditor", "Settings_v23", str, true)
end

local CHROM_MAP = {
    [1]=2, [2]=4, [3]=5, [4]=7, [5]=9, [6]=10, [7]=12, 
    [8]=14, [10]=17, [11]=17, [12]=21, [13]=21 
}

-- === HELPERS ===
local function Tooltip(text)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetFontSize(ctx) * 35.0)
        r.ImGui_Text(ctx, text)
        r.ImGui_PopTextWrapPos(ctx)
        r.ImGui_EndTooltip(ctx)
    end
end

-- === CHORD ROOT DETECTION ===
-- MODIFIED by TK: Replaced static chord_patterns dictionary with dynamic score-based root detection.
-- WHY: The dictionary approach can never be complete - it would need entries for every possible
-- chord inversion and voicing. This algorithm works for ANY chord by analyzing interval structures.
-- HOW: Each pitch class is tested as a potential root. Points are awarded for "strong" intervals
-- (perfect 5th = strongest indicator of root). The candidate with highest score wins.
-- ADDED: Optional scale_root parameter - when scale is enabled, notes matching the key get a bonus.

local function FindChordRoot(pitches, scale_root)
    if #pitches < 2 then return pitches[1] % 12 end
    
    local pitch_classes = {}
    for _, p in ipairs(pitches) do
        pitch_classes[(p % 12)] = true
    end
    
    local classes = {}
    for pc, _ in pairs(pitch_classes) do
        table.insert(classes, pc)
    end
    
    local bass_pitch_class = pitches[1] % 12
    local best_root = bass_pitch_class
    local best_score = -999
    
    for _, candidate in ipairs(classes) do
        local score = 0
        local intervals = {}
        for _, pc in ipairs(classes) do
            intervals[(pc - candidate) % 12] = true
        end
        
        -- Score intervals: higher = stronger root indicator
        if intervals[7] then score = score + 10 end   -- Perfect 5th (strongest)
        if intervals[4] then score = score + 5 end    -- Major 3rd
        if intervals[3] then score = score + 4 end    -- Minor 3rd
        if intervals[10] then score = score + 3 end   -- Minor 7th (dominant)
        if intervals[11] then score = score + 3 end   -- Major 7th
        if intervals[9] then score = score + 2 end    -- Major 6th (13th)
        if intervals[5] then score = score + 2 end    -- Perfect 4th
        if intervals[2] then score = score + 1 end    -- Major 2nd (9th)
        
        -- Tritone without 5th suggests diminished
        if intervals[6] and not intervals[7] then score = score + 2 end
        
        -- Bass note bonus: in ambiguous cases (C6 vs Am7), prefer bass as root
        if candidate == bass_pitch_class then score = score + 1 end
        
        -- Scale root bonus: if scale is active, prefer notes matching the key
        if scale_root and candidate == (scale_root % 12) then score = score + 1 end
        
        if score > best_score then
            best_score = score
            best_root = candidate
        end
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

local function GetSelectedChords(take)
    local _, cnt = r.MIDI_CountEvts(take)
    local all_sel = {}
    local distinct_starts = {}
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            table.insert(all_sel, {idx=i, muted=muted, start=start, endp=endp, pitch=pitch, vel=vel, chan=chan})
            distinct_starts[start] = true
        end
    end
    local time_points = {}
    for t, _ in pairs(distinct_starts) do table.insert(time_points, t) end
    table.sort(time_points)
    local chords = {}
    for _, t in ipairs(time_points) do
        local chord_notes = {}
        for _, n in ipairs(all_sel) do
            if n.start <= t and n.endp > t then
                if n.start == t then table.insert(chord_notes, n) end
            end
        end
        if #chord_notes > 0 then
            table.sort(chord_notes, function(a,b) return a.pitch < b.pitch end)
            table.insert(chords, chord_notes)
        end
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

local function Action_SmartHarmonize(take, hwnd, steps)
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local map = nil
    if scale_enabled then map = GetScaleBitMap(take, hwnd) end
    local chords = GetSelectedChords(take)
    local notes_to_add = {}
    
    for _, chord in ipairs(chords) do
        if #chord == 1 then
            local note = chord[1]
            local np
            if scale_enabled then np = GetDiatonicPitch(note.pitch, map, steps, settings.direction)
            else np = note.pitch + ((CHROM_MAP[steps] or 12) * settings.direction) end
            if np >= 0 and np <= 127 then table.insert(notes_to_add, {muted=note.muted, start=note.start, endppq=note.endp, chan=note.chan, pitch=np, vel=note.vel}) end
        elseif #chord > 1 then
            local pitches = {}; local pitch_lookup = {} 
            for _, n in ipairs(chord) do table.insert(pitches, n.pitch); pitch_lookup[n.pitch] = true end
            local bass_pitch = pitches[1]
            -- MODIFIED by TK: Use FindChordRoot with scale_root for better accuracy
            local scale_root_note = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
            local root_pitch_class = FindChordRoot(pitches, scale_root_note)
            local root_pitch = bass_pitch + ((root_pitch_class - (bass_pitch % 12) + 12) % 12)
            local target_pitch
            if scale_enabled then target_pitch = GetDiatonicPitch(root_pitch, map, steps, settings.direction)
            else target_pitch = root_pitch + ((CHROM_MAP[steps] or 12) * settings.direction) end
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
                if scale_enabled then
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 2, settings.direction))
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else
                    table.insert(intervals, pitch + (4 * settings.direction))
                    table.insert(intervals, pitch + (7 * settings.direction))
                end
            elseif type_str == "sus2" then
                 if scale_enabled then
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 1, settings.direction))
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else
                    table.insert(intervals, pitch + (2 * settings.direction))
                    table.insert(intervals, pitch + (7 * settings.direction))
                end
            elseif type_str == "sus4" then
                 if scale_enabled then
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 3, settings.direction))
                    table.insert(intervals, GetDiatonicPitch(pitch, map, 4, settings.direction))
                else
                    table.insert(intervals, pitch + (5 * settings.direction))
                    table.insert(intervals, pitch + (7 * settings.direction))
                end
            elseif type_str == "dim" then
                table.insert(intervals, pitch + (3 * settings.direction))
                table.insert(intervals, pitch + (6 * settings.direction))
            elseif type_str == "aug" then
                table.insert(intervals, pitch + (4 * settings.direction))
                table.insert(intervals, pitch + (8 * settings.direction))
            end
            for _, p in ipairs(intervals) do
                if p >= 0 and p <= 127 then table.insert(add, {muted=mute, start=start, endppq=endp, chan=chan, pitch=p, vel=vel}) end
            end
        end
    end
    r.MIDI_SelectAll(take, false)
    for _,n in ipairs(add) do r.MIDI_InsertNote(take, true, n.muted, n.start, n.endppq, n.chan, n.pitch, n.vel, true) end
end

-- === SELECTION & FILTER ===
local function Action_FilterSelection(take, hwnd)
    -- MODIFIED by TK: Improved role detection with clearer interval mappings
    -- Maps semitone intervals to chord roles for filtering
    local function get_role_exact(note_pitch, root_pitch)
        local interval = (note_pitch - root_pitch) % 12
        if interval == 0 then return "root" end
        if interval == 3 or interval == 4 then return "third" end     -- minor/major 3rd
        if interval == 6 or interval == 7 or interval == 8 then return "fifth" end  -- dim5/perfect5/aug5
        if interval == 9 or interval == 10 or interval == 11 then return "seventh" end  -- 6th/min7/maj7
        if interval == 1 or interval == 2 then return "second" end    -- b9/9
        if interval == 5 then return "fourth" end                      -- 11th
        return "extension"
    end
    local chords = GetSelectedChords(take)
    local events_to_deselect = {}
    for _, c in ipairs(chords) do for _, n in ipairs(c) do events_to_deselect[n.idx] = true end end
    local events_to_keep = {}
    local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
    local scale_root_note = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
    for _, chord in ipairs(chords) do
        local pitches = {}
        for _, n in ipairs(chord) do table.insert(pitches, n.pitch) end
        local bass_pitch = pitches[1]
        -- MODIFIED by TK: Use FindChordRoot with scale_root for better accuracy
        local root_pitch_class = FindChordRoot(pitches, scale_root_note)
        local root_pitch = bass_pitch + ((root_pitch_class - (bass_pitch % 12) + 12) % 12)
        for _, n in ipairs(chord) do
            local role = get_role_exact(n.pitch, root_pitch)
            local is_target = false
            if role == "root" and settings.targets.root then is_target = true end
            if role == "third" and settings.targets.third then is_target = true end
            if role == "fifth" and settings.targets.fifth then is_target = true end
            if role == "seventh" and settings.targets.seventh then is_target = true end
            if is_target then events_to_keep[n.idx] = true end
        end
    end
    for idx, _ in pairs(events_to_deselect) do
        if not events_to_keep[idx] then r.MIDI_SetNote(take, idx, false, nil, nil, nil, nil, nil, nil, true) end
    end
end

-- === TOOLS ===
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

-- === HUMANIZE ===
local function Action_HumanizeVel(take, hwnd)
    local _, cnt = r.MIDI_CountEvts(take)
    local range = settings.hum_vel_str
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            local drift = math.random(-range, range)
            local new_vel = math.max(1, math.min(127, vel + drift))
            r.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, nil, new_vel, true)
        end
    end
end

local function Action_HumanizeTiming(take, hwnd)
    local _, cnt = r.MIDI_CountEvts(take)
    local range = settings.hum_time_str
    for i = 0, cnt - 1 do
        local _, sel, muted, start, endp, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if sel then
            local drift = math.random(-range, range)
            local new_start = math.max(0, start + drift)
            local new_end = math.max(new_start + 1, endp + drift)
            r.MIDI_SetNote(take, i, nil, nil, new_start, new_end, nil, nil, nil, true)
        end
    end
end

-- === VOICING ===
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
    if #chords < 1 then return end
    local function get_role_exact(note_pitch, root_pitch)
        local interval = (note_pitch - root_pitch) % 12
        if interval == 0 then return "root" end
        if interval == 3 or interval == 4 then return "third" end
        if interval == 7 or interval == 6 or interval == 8 then return "fifth" end
        return "other"
    end
    local c1 = chords[1]
    if settings.voice_mode > 0 and #c1 > 1 then
        local pitches = {}
        for _, n in ipairs(c1) do table.insert(pitches, n.pitch) end
        local bass_pitch = pitches[1]
        -- MODIFIED by TK: Use FindChordRoot with scale_root for better accuracy
        local scale_enabled = r.MIDIEditor_GetSetting_int(hwnd, "scale_enabled") == 1
        local scale_root_note = scale_enabled and r.MIDIEditor_GetSetting_int(hwnd, "scale_root") or nil
        local root_pitch_class = FindChordRoot(pitches, scale_root_note)
        local root_pitch = bass_pitch + ((root_pitch_class - (bass_pitch % 12) + 12) % 12)
        local target_role = "root"
        if settings.voice_mode == 2 then target_role = "third" end
        if settings.voice_mode == 3 then target_role = "fifth" end
        local target_note = nil
        for _, n in ipairs(c1) do
            if get_role_exact(n.pitch, root_pitch) == target_role then target_note = n; break end
        end
        if target_note then
            local base_p = target_note.pitch
            for _, n in ipairs(c1) do
                if n ~= target_note then
                    local dist = (n.pitch - base_p) % 12
                    if dist == 0 then dist = 12 end 
                    local new_p = base_p + dist
                    if new_p ~= n.pitch then
                        r.MIDI_SetNote(take, n.idx, nil,nil,nil,nil,nil, new_p, nil, true)
                        n.pitch = new_p 
                    end
                end
            end
        end
    end
    if #chords < 2 then return end
    local function GetCentroid(chord) local sum = 0; for _, n in ipairs(chord) do sum = sum + n.pitch end; return sum / #chord end
    for i = 2, #chords do
        local curr_chord = chords[i]
        local target_center = GetCentroid(chords[i-1]) 
        for _, note in ipairs(curr_chord) do
            local best_pitch = note.pitch
            local dist = math.abs(note.pitch - target_center)
            local down = note.pitch - 12
            if down >= 0 and math.abs(down - target_center) < dist then best_pitch = down; dist = math.abs(down - target_center) end
            local up = note.pitch + 12
            if up <= 127 and math.abs(up - target_center) < dist then best_pitch = up end
            if best_pitch ~= note.pitch then
                r.MIDI_SetNote(take, note.idx, nil,nil,nil,nil,nil, best_pitch, nil, true)
                note.pitch = best_pitch 
            end
        end
    end
end

local function SelectAllNotes()
    local take = r.MIDIEditor_GetTake(r.MIDIEditor_GetActive())
    if not take then return end
    r.MIDI_SelectAll(take, true)
end

-- === GUI LOOP ===
local function SafePushStyleColor(col_idx, col_val) if r.ImGui_PushStyleColor then r.ImGui_PushStyleColor(ctx, col_idx, col_val) end end
local function SafePopStyleColor(count) if r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, count) end end
local function SafePushStyleVar(var_idx, ...) if r.ImGui_PushStyleVar then r.ImGui_PushStyleVar(ctx, var_idx, ...) end end
local function SafePopStyleVar(count) if r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, count) end end

local function loop()
    if settings.auto_close and not r.MIDIEditor_GetActive() then SaveState(); return end

    SafePushStyleVar(r.ImGui_StyleVar_WindowRounding(), 6)
    SafePushStyleVar(r.ImGui_StyleVar_FrameRounding(), 4)
    SafePushStyleVar(r.ImGui_StyleVar_ItemSpacing(), 8, 8)
    SafePushStyleColor(r.ImGui_Col_WindowBg(), BG_COLOR)
    SafePushStyleColor(r.ImGui_Col_TitleBgActive(), ACCENT_COLOR)
    SafePushStyleColor(r.ImGui_Col_TitleBg(), ACCENT_ACTIVE)
    SafePushStyleColor(r.ImGui_Col_Button(), FRAME_BG)
    SafePushStyleColor(r.ImGui_Col_ButtonHovered(), ACCENT_HOVER)
    SafePushStyleColor(r.ImGui_Col_ButtonActive(), ACCENT_ACTIVE)
    SafePushStyleColor(r.ImGui_Col_CheckMark(), ACCENT_COLOR)
    SafePushStyleColor(r.ImGui_Col_Text(), TEXT_COLOR)
    SafePushStyleColor(r.ImGui_Col_SliderGrab(), ACCENT_COLOR)
    SafePushStyleColor(r.ImGui_Col_SliderGrabActive(), ACCENT_ACTIVE)
    SafePushStyleColor(r.ImGui_Col_FrameBg(), 0x444444FF)

    local visible, open = r.ImGui_Begin(ctx, 'Chord Editor v23.1 TK', true, r.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
        
        -- Header
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "SETTINGS")
        r.ImGui_SameLine(ctx)
        r.ImGui_SameLine(ctx, r.ImGui_GetWindowWidth(ctx) - 105) 
        local rv, nv = r.ImGui_Checkbox(ctx, "Sync Close", settings.auto_close)
        if rv then settings.auto_close = nv; SaveState() end
        Tooltip("Auto-close with MIDI Editor")

        if r.ImGui_RadioButton(ctx, "DOWN (-)", settings.direction == -1) then settings.direction = -1 end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "UP (+)", settings.direction == 1) then settings.direction = 1 end
        
        -- 1. ADD CHORD
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "ADD CHORD")
        
        local w = 60
        if r.ImGui_GetContentRegionAvail then w = (r.ImGui_GetContentRegionAvail(ctx)-24)/4 end
        
        if r.ImGui_Button(ctx, "Triad", w) then DoAction(function(t,h) Action_BuildChord(t,h,"triad") end, "Build Triad") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Sus2", w) then DoAction(function(t,h) Action_BuildChord(t,h,"sus2") end, "Build Sus2") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Sus4", w) then DoAction(function(t,h) Action_BuildChord(t,h,"sus4") end, "Build Sus4") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Dim/Aug", w) then r.ImGui_OpenPopup(ctx, "dimaug_popup") end
        if r.ImGui_BeginPopup(ctx, "dimaug_popup") then
            if r.ImGui_Selectable(ctx, "Diminished (0-3-6)") then DoAction(function(t,h) Action_BuildChord(t,h,"dim") end, "Build Dim") end
            if r.ImGui_Selectable(ctx, "Augmented (0-4-8)") then DoAction(function(t,h) Action_BuildChord(t,h,"aug") end, "Build Aug") end
            r.ImGui_EndPopup(ctx)
        end
        
        -- 2. ADD INTERVAL
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "ADD INTERVAL")
        
        local p = (settings.direction == 1) and "+" or "-"
        if r.ImGui_Button(ctx, p.."2nd", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,1) end, "Add 2nd") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."3rd", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,2) end, "Add 3rd") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."4th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,3) end, "Add 4th") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."5th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,4) end, "Add 5th") end
        
        if r.ImGui_Button(ctx, p.."6th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,5) end, "Add 6th") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."7th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,6) end, "Add 7th") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."9th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,8) end, "Add 9th") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, p.."11th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,10) end, "Add 11th") end
        
        if r.ImGui_Button(ctx, p.."13th", w) then DoAction(function(t,h) Action_SmartHarmonize(t,h,12) end, "Add 13th") end

        -- 3. CHORD VOICING
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "CHORD VOICING")
        local bw = w * 2 + 4
        if r.ImGui_GetContentRegionAvail then bw = (r.ImGui_GetContentRegionAvail(ctx)-8)/2 end
        
        if r.ImGui_Button(ctx, "Inv DOWN", bw) then DoAction(function(t,h) Action_InvertChords(t,h,-1) end, "Invert Down") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Inv UP", bw) then DoAction(function(t,h) Action_InvertChords(t,h,1) end, "Invert Up") end
        if r.ImGui_Button(ctx, "Drop 2", bw) then DoAction(function(t,h) Action_DropVoicing(t,h,2) end, "Drop 2") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Drop 3", bw) then DoAction(function(t,h) Action_DropVoicing(t,h,3) end, "Drop 3") end

        r.ImGui_PushItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, "##vlmode", settings.voice_mode == 0 and "Lead: Follow First" or (settings.voice_mode == 1 and "Lead: Anchor Root" or (settings.voice_mode == 2 and "Lead: Anchor 3rd" or "Lead: Anchor 5th"))) then
            if r.ImGui_Selectable(ctx, "Follow First Chord", settings.voice_mode == 0) then settings.voice_mode = 0 end
            if r.ImGui_Selectable(ctx, "Anchor: Root (Closed)", settings.voice_mode == 1) then settings.voice_mode = 1 end
            if r.ImGui_Selectable(ctx, "Anchor: 3rd (1st Inv)", settings.voice_mode == 2) then settings.voice_mode = 2 end
            if r.ImGui_Selectable(ctx, "Anchor: 5th (2nd Inv)", settings.voice_mode == 3) then settings.voice_mode = 3 end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)
        if r.ImGui_Button(ctx, "APPLY VOICE LEADING", -1) then DoAction(Action_VoiceLeading, "Voice Leading") end

        -- 4. SELECTION
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "SELECTION")
        if r.ImGui_Button(ctx, "SELECT ALL NOTES", -1) then SelectAllNotes() end
        
        local rv, nv
        rv, nv = r.ImGui_Checkbox(ctx, "ROOT", settings.targets.root); r.ImGui_SameLine(ctx)
        if rv then settings.targets.root = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "3rd", settings.targets.third); r.ImGui_SameLine(ctx)
        if rv then settings.targets.third = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "5th", settings.targets.fifth); r.ImGui_SameLine(ctx)
        if rv then settings.targets.fifth = nv end
        rv, nv = r.ImGui_Checkbox(ctx, "7th", settings.targets.seventh)
        if rv then settings.targets.seventh = nv end
        
        SafePushStyleColor(r.ImGui_Col_Button(), ACCENT_COLOR)
        if r.ImGui_Button(ctx, "FILTER SELECTION", -1) then DoAction(Action_FilterSelection, "Filter Selection") end
        SafePopStyleColor(1)

        -- 5. TOOLS
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "TOOLS")
        
        if r.ImGui_Button(ctx, "Oct -1", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"move",-12) end, "Octave Down") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Oct +1", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"move",12) end, "Octave Up") end
        if r.ImGui_Button(ctx, "Dup -12", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"duplicate",-12) end, "Dup -12") end; r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Dup +12", bw) then DoAction(function(t,h) Action_SimpleEdit(t,h,"duplicate",12) end, "Dup +12") end
        
        SafePushStyleColor(r.ImGui_Col_Button(), 0xAA4444FF)
        SafePushStyleColor(r.ImGui_Col_ButtonHovered(), 0xC25555FF)
        if r.ImGui_Button(ctx, "MUTE", -1) then DoAction(function(t,h) Action_SimpleEdit(t,h,"mute",0) end, "Mute") end
        SafePopStyleColor(2)

        -- 6. HUMANIZE
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, 0xFFFFFFFF, "HUMANIZE")
        
        -- Velocity Slider
        r.ImGui_SetNextItemWidth(ctx, 120)
        rv, nv = r.ImGui_SliderInt(ctx, "##velstr", settings.hum_vel_str, 1, 60, "%d")
        if rv then settings.hum_vel_str = nv end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "VELOCITY", -1) then DoAction(Action_HumanizeVel, "Humanize Velocity") end
        Tooltip("Randomize velocity by slider amount")

        -- Timing Slider
        r.ImGui_SetNextItemWidth(ctx, 120)
        rv, nv = r.ImGui_SliderInt(ctx, "##timestr", settings.hum_time_str, 1, 100, "%d ticks")
        if rv then settings.hum_time_str = nv end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "TIMING", -1) then DoAction(Action_HumanizeTiming, "Humanize Timing") end
        Tooltip("Shift note start/end randomly by slider amount (ticks)")
        
        r.ImGui_End(ctx)
    end
    SafePopStyleColor(11)
    SafePopStyleVar(3)
    if open then r.defer(loop) end
end
r.defer(loop)
