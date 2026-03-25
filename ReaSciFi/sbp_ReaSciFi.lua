-- @description SBP ReaSciFi
-- @author SBP & AI
-- @version 0.5.1
-- @about
--   # SBP ReaSciFi
--   Modular sci-fi UI sound generator for REAPER.
--
--   Features in this initial implementation:
--   - Dedicated JSFX preview engine for one-shot and drone design.
--   - Macro workflow for UI beeps, clicks, glitches, drones, and telemetry textures.
--   - Timbre and Motion XY pads.
--   - Built-in LFO and MSEG-style modulation controls.
--   - Factory preset families oriented toward interface sound design.
--
--   [**Donate / Support**](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=bodzik@gmail.com&item_name=ReaSciFi+Support&currency_code=USD)
-- @donation https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=bodzik@gmail.com&item_name=ReaSciFi+Support&currency_code=USD
-- @provides
--   [main] sbp_ReaSciFi.lua
--   modules/State.lua
--   modules/UIHelpers.lua
--   modules/EngineSync.lua
--   modules/PresetManager.lua
--   modules/Randomizer.lua
--   modules/Printer.lua
--   modules/MainUI.lua
--   [nomain] sbp_ReaSciFiEngine.jsfx
-- @changelog
--   v0.5.1 (2026-03-26)
--     + Fixed One-Shot live monitoring pitch reset: moving sliders now preserves current MIDI trigger note instead of falling back to base drone pitch.
--     + Added explicit JSFX playback-state reset hook for preset/morph/randomize/profile transitions.
--     + Improved manual-tweak behavior after loading User Preset: first direct synth edit detaches from loaded preset state.
--   v0.5.0 (2026-03-25)
--     + Morph between factory presets (A/B + Mix) for hybrid sound design.
--     + Batch render with auto-naming (Prefix_001...N) for production workflows.
--     + Optional randomize-per-item mode for batch generation.
--     + Context tooltips added across UI (Global/Render/Post FX/Randomize) for faster onboarding.
--     + Added RELEASE_QUICKSTART.md short usage guide for release publishing.
--     + Preset and user-morph load now reset held one-shot playback state to prevent old sound bleed-through.
--     + Fixed live monitor bug where moving any slider in One-Shot could reset pitch back to default base note instead of current MIDI trigger note.
--   v0.4.2 (2026-03-25)
--     + NEW: Engine 2.0 moved to first row with dedicated 5-column layout.
--     + NEW: Quick Random Profiles (Click / Whoosh / Drone) with auto-mask setup.
--     + NEW: CPU/Quality toggle for Engine 2.0 (Economy mode reduces spectral computation).
--     + Remove Engine 2.0 from Modulation section (upstream to dedicated Engine row).
--   v0.4.1 (2026-03-25)
--     + Exposed Engine 2.0 controls in UI: Character, Grain Mix, Spectral Mix, Reverse Mix, Safety.
--     + Added Randomize Undo (history stack) to restore previous randomized state.
--     + Character response is now family-aware for more musical macro behavior.
--   v0.4.0 (2026-03-25)
--     + Sound Engine 2.0 core: granular layer, spectral shimmer layer, reverse resonator layer.
--     + New Character macro added and exposed in UI, randomizer, and bind targets.
--     + Added output safety stage: anti-DC filtering + smooth peak limiter.
--   v0.3.1 (2026-03-25)
--     + 4 new synthesis families: Metallic Chirp, Subcursor Rumble, Bit Crush, Ephemeral Echo.
--     + Factory presets for all 13 families (0-12).
--     + Fixed ONE-SHOT autoplay bug (now triggers only on MIDI NoteOn).
--     + Smart Randomize styles added: Mild / Creative / Extreme.
--   v0.3.0 (2026-03-25)
--     + Wide-first UI layout with separate visual Layer blocks.
--     + Added per-layer gain controls (Digital/Packet/Noise/Resonator/Chaos).
--     + Switched theme to neutral dark (ReaWhoosh-style).
--     + Added factory presets for new families: Data Burst, Packet Loss, Scanner Orbit.
--     + Added User Bind Pad with manual X/Y parameter target assignment.
--     + One-Shot mode now supports MIDI NoteOn trigger workflow.
--     + Unified all pads as user-rebindable macro pads (Timbre/Motion/User).
--     + Added Invert toggle for X/Y binding axes on each pad.
--     + Rebalanced top-row widths so User Presets + Randomizer fit better.
--   v0.2.0 (2026-03-25)
--     + Offline Print: bounce preview track to stem (ReaSciFi Renders).
--     + Randomizer with 7 independent masks (Osc/Packet/Noise/Mod/Chaos/Tail/Family).
--     + User Presets: Save/Load/Delete via REAPER ExtState.
--     + 3 new synthesis families: Data Burst (6), Packet Loss (7), Scanner Orbit (8).
--   v0.1.0 (2026-03-25)
--     + Initial modular ReaSciFi scaffold.

---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch

local r = reaper

local info = debug.getinfo(1, 'S')
local script_path = info.source:match('@(.*[\\/])') or ''
local shim = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
if r.file_exists(shim) then
  dofile(shim)
end

if not r.ImGui_CreateContext then
  r.ShowConsoleMsg('[ReaSciFi] ReaImGui not found. Install ReaImGui v0.10.0.2+ via ReaPack.\n')
  return
end

local function loadModule(name)
  local ok, mod = pcall(dofile, script_path .. 'modules/' .. name .. '.lua')
  if not ok then
    r.ShowConsoleMsg('[ReaSciFi] Failed to load module ' .. tostring(name) .. ': ' .. tostring(mod) .. '\n')
    return nil
  end
  return mod
end

local State         = loadModule('State')
local UIHelpers     = loadModule('UIHelpers')
local EngineSync    = loadModule('EngineSync')
local PresetManager = loadModule('PresetManager')
local Randomizer    = loadModule('Randomizer')
local Printer       = loadModule('Printer')
local MainUI        = loadModule('MainUI')

if not (State and UIHelpers and EngineSync and PresetManager and Randomizer and Printer and MainUI) then
  r.ShowConsoleMsg('[ReaSciFi] One or more modules failed to load. Aborting.\n')
  return
end

local ctx = r.ImGui_CreateContext('SBP ReaSciFi')
local state = State.GetDefault()
local ui_first_frame = true
local preset_names = PresetManager.GetNames()
-- Load persisted user presets once at startup; refreshed after save/delete.
local user_preset_names = PresetManager.GetUserNames()

-- Dirty flag + throttle for smooth realtime updates while dragging sliders/pads.
-- EngineSync already caches FX index, so throttled live pushes are safe.
local sync_dirty = false
local sync_last_push_t = 0
local SYNC_INTERVAL_SEC = 0.035
local randomize_history = {}
local RANDOMIZE_HISTORY_MAX = 24

local function pushRandomizeSnapshot()
  randomize_history[#randomize_history + 1] = State.DeepCopy(state.synth)
  if #randomize_history > RANDOMIZE_HISTORY_MAX then
    table.remove(randomize_history, 1)
  end
end

local function synthChanged(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return a ~= b
  end

  for key, value in pairs(a) do
    if b[key] ~= value then
      return true
    end
  end

  for key, value in pairs(b) do
    if a[key] ~= value then
      return true
    end
  end

  return false
end

local function safeDestroyContext(context)
  if r.ImGui_DestroyContext then
    r.ImGui_DestroyContext(context)
  end
end

local function syncState()
  local ok, message = EngineSync.PushState(state)
  state.ui.status = message or 'Ready.'
  state.ui.status_is_error = not ok
  sync_dirty = false
  return ok
end

local function applyPreset(index)
  PresetManager.Apply(state, index)
  state.ui.selected_preset = index
  state.ui.loaded_user_preset_name = nil
  -- Push immediately on preset selection (single event, not per-frame).
  syncState()
  EngineSync.ResetPlaybackState(state)
end

local function handleActions(actions)
  local function buildBatchMidiTriggerConfig()
    local ui = state.ui
    return {
      randomize_enabled = ui.batch_midi_rand_enabled == true,
      pitch = math.floor(tonumber(ui.batch_midi_pitch) or 69),
      pitch_randomize = ui.batch_midi_pitch_rand == true,
      pitch_min = math.floor(tonumber(ui.batch_midi_pitch_min) or 60),
      pitch_max = math.floor(tonumber(ui.batch_midi_pitch_max) or 84),
      velocity = math.floor(tonumber(ui.batch_midi_vel) or 110),
      velocity_randomize = ui.batch_midi_vel_rand == true,
      velocity_min = math.floor(tonumber(ui.batch_midi_vel_min) or 85),
      velocity_max = math.floor(tonumber(ui.batch_midi_vel_max) or 127),
      length_ms = math.floor(tonumber(ui.batch_midi_len_ms) or 30),
      length_randomize = ui.batch_midi_len_rand == true,
      length_min_ms = math.floor(tonumber(ui.batch_midi_len_min_ms) or 15),
      length_max_ms = math.floor(tonumber(ui.batch_midi_len_max_ms) or 60),
      auto_fit_range = ui.batch_midi_autofit_range == true
    }
  end

  if actions.apply_preset then
    applyPreset(actions.apply_preset)
  end

  if actions.push_now then
    syncState()
  end

  if actions.print_now then
    local ok, msg = Printer.Print(state, {
      midi_trigger_cfg = buildBatchMidiTriggerConfig(),
      midi_trigger_randomize_index = 1
    })
    state.ui.status = msg or 'Print done.'
    state.ui.status_is_error = not ok
  end

  if actions.print_batch then
    local ok, msg = Printer.PrintBatch(state, {
      count = state.ui.batch_count,
      prefix = state.ui.batch_prefix,
      randomize_each = state.ui.batch_randomize,
      sequential_gap_sec = (math.max(0, tonumber(state.ui.batch_gap_ms) or 20) / 1000.0),
      midi_trigger_cfg = buildBatchMidiTriggerConfig(),
      randomize_fn = function()
        Randomizer.Randomize(state, state.rand_style)
      end,
      sync_fn = syncState
    })
    state.ui.status = msg or 'Batch print done.'
    state.ui.status_is_error = not ok
  end

  if actions.apply_morph and state.ui.morph_enabled == true then
    local names = PresetManager.GetUserNames()
    local idx_a = math.floor(tonumber(state.ui.morph_user_a_sel) or 1)
    local idx_b = math.floor(tonumber(state.ui.morph_user_b_sel) or 1)
    local name_a = names[idx_a]
    local name_b = names[idx_b]
    local ok, msg = PresetManager.MorphUser(state, name_a, name_b, state.ui.morph_t)
    if ok then
      state.ui.loaded_user_preset_name = nil
      syncState()
      EngineSync.ResetPlaybackState(state)
      local mix = math.floor((tonumber(state.ui.morph_t) or 0.5) * 100 + 0.5)
      state.ui.status = string.format('User Morph applied: %s -> %s (%d%%)', tostring(name_a), tostring(name_b), mix)
      state.ui.status_is_error = false
    else
      state.ui.status = msg or 'Morph failed.'
      state.ui.status_is_error = true
    end
  end

  if actions.randomize then
    pushRandomizeSnapshot()
    Randomizer.Randomize(state, state.rand_style)
    state.ui.loaded_user_preset_name = nil
    syncState()
    EngineSync.ResetPlaybackState(state)
  end

  if actions.quick_profile ~= nil then
    pushRandomizeSnapshot()
    state.ui.loaded_user_preset_name = nil
    local profile = math.floor(tonumber(actions.quick_profile) or 0)
    local m = state.rand_masks

    if profile == 0 then
      -- Click: high-frequency bursts, lots of oscillators and packets, minimal tail
      state.synth.mode = 0
      m.osc = true
      m.packet = true
      m.noise = false
      m.modulation = true
      m.chaos = false
      m.tail = false
      m.family = false
      state.rand_style = 2  -- Extreme
      state.ui.status = 'Quick Profile: Click (One-Shot mode)'
    elseif profile == 1 then
      -- Whoosh: everything enabled for maximum motion and sweep
      m.osc = true
      m.packet = true
      m.noise = true
      m.modulation = true
      m.chaos = true
      m.tail = true
      m.family = false
      state.rand_style = 1  -- Creative
      state.ui.status = 'Quick Profile: Whoosh'
    elseif profile == 2 then
      -- Drone: stable foundation with resonator, noise tail, family variation
      state.synth.mode = 1
      m.osc = true
      m.packet = false
      m.noise = true
      m.modulation = false
      m.chaos = false
      m.tail = true
      m.family = true
      state.rand_style = 0  -- Mild
      state.ui.status = 'Quick Profile: Drone (Drone mode)'
    elseif profile == 3 then
      -- Glitch: aggressive digital artifacts and packet/noise instability.
      state.synth.mode = 0
      m.osc = true
      m.packet = true
      m.noise = true
      m.modulation = true
      m.chaos = true
      m.tail = false
      m.family = false
      state.synth.family = 11 -- Bit Crush
      state.rand_style = 2  -- Extreme
      state.ui.status = 'Quick Profile: Glitch'
    elseif profile == 4 then
      -- Scanner: sweeping bed with controlled tail/motion.
      state.synth.mode = 1
      m.osc = true
      m.packet = false
      m.noise = true
      m.modulation = true
      m.chaos = false
      m.tail = true
      m.family = false
      state.synth.family = 8 -- Scanner Orbit
      state.rand_style = 1  -- Creative
      state.ui.status = 'Quick Profile: Scanner'
    else
      -- Telemetry: cleaner UI-data beeps/chirps with moderate modulation.
      state.synth.mode = 0
      m.osc = true
      m.packet = true
      m.noise = false
      m.modulation = true
      m.chaos = false
      m.tail = false
      m.family = false
      state.synth.family = 0 -- Data Chirp
      state.rand_style = 0  -- Mild
      state.ui.status = 'Quick Profile: Telemetry'
    end

    Randomizer.Randomize(state, state.rand_style)
    syncState()
    EngineSync.ResetPlaybackState(state)
  end

  if actions.undo_randomize then
    if #randomize_history > 0 then
      local prev = table.remove(randomize_history)
      State.ReplaceSynth(state, prev)
      state.ui.loaded_user_preset_name = nil
      syncState()
      state.ui.status = 'Randomize undone.'
      state.ui.status_is_error = false
    else
      state.ui.status = 'No randomize history yet.'
      state.ui.status_is_error = false
    end
  end

  if actions.save_user_preset then
    PresetManager.SaveUser(actions.save_user_preset, state)
    user_preset_names = PresetManager.GetUserNames()
    -- Reset selection to the newly saved preset.
    for i, n in ipairs(user_preset_names) do
      if n == actions.save_user_preset then
        state.ui.user_preset_sel = i
        break
      end
    end
    state.ui.status = 'Saved preset: ' .. actions.save_user_preset
    state.ui.status_is_error = false
  end

  if actions.load_user_preset then
    local ok = PresetManager.LoadUser(actions.load_user_preset, state)
    state.ui.status = ok and ('Loaded: ' .. actions.load_user_preset) or 'Preset not found.'
    state.ui.status_is_error = not ok
    if ok then
      state.ui.loaded_user_preset_name = actions.load_user_preset
      syncState()
      EngineSync.ResetPlaybackState(state)
    end
  end

  if actions.delete_user_preset then
    if state.ui.loaded_user_preset_name == actions.delete_user_preset then
      state.ui.loaded_user_preset_name = nil
    end
    PresetManager.DeleteUser(actions.delete_user_preset)
    user_preset_names = PresetManager.GetUserNames()
    state.ui.user_preset_sel = 1
    state.ui.status = 'Deleted: ' .. actions.delete_user_preset
    state.ui.status_is_error = false
  end
end

local function mainLoop()
  UIHelpers.PushTheme(ctx)

  if ui_first_frame then
    r.ImGui_SetNextWindowSize(ctx, 1460, 760, r.ImGui_Cond_FirstUseEver())
    ui_first_frame = false
  end

  local visible, open = r.ImGui_Begin(ctx, 'SBP ReaSciFi', true, r.ImGui_WindowFlags_MenuBar())
  if visible then
    local synth_before_draw = State.DeepCopy(state.synth)
    local changed, actions = MainUI.Draw(ctx, state, preset_names, user_preset_names)

    handleActions(actions)

    local synth_changed = synthChanged(synth_before_draw, state.synth)
    local has_explicit_state_action = actions.push_now or actions.apply_preset or actions.randomize
      or actions.undo_randomize or actions.load_user_preset or actions.print_batch
      or actions.apply_morph or actions.quick_profile ~= nil

    if synth_changed and not has_explicit_state_action and state.ui.loaded_user_preset_name then
      local preset_name = state.ui.loaded_user_preset_name
      state.ui.loaded_user_preset_name = nil
      EngineSync.ResetPlaybackState(state)
      state.ui.status = 'Detached from user preset after manual tweak: ' .. tostring(preset_name)
      state.ui.status_is_error = false
    end

    -- changed==true but no immediate action -> mark dirty.
     if not actions.push_now and not actions.apply_preset
       and not actions.randomize and not actions.undo_randomize and not actions.load_user_preset
       and not actions.print_batch and not actions.apply_morph then
      if changed and state.setup.auto_preview then
        sync_dirty = true
      end
    end

    -- Smooth realtime sync while dragging (throttled), plus guaranteed final sync
    -- on mouse release for exact endpoint value.
    if sync_dirty then
      local now = r.time_precise and r.time_precise() or os.clock()
      local item_active = r.ImGui_IsAnyItemActive(ctx)
      if (item_active and (now - sync_last_push_t) >= SYNC_INTERVAL_SEC) or (not item_active) then
        syncState()
        sync_last_push_t = now
      end
    end

    r.ImGui_End(ctx)
  end

  UIHelpers.PopTheme(ctx)

  if open then
    r.defer(mainLoop)
  else
    safeDestroyContext(ctx)
  end
end

mainLoop()