---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local State = {}
local r = reaper

local EXT_SECTION = "SBP_ReaMotionPad"
local EXT_KEY = "ProjectState"

local function defaultSegment()
  return {
    mode = 0,
    points = 2,
    division = 2,
    bars = 4,
    manual_positions = { 0.0, 1.0 },
    curve_mode = 0,
    curve_tension = 0.0,
    apply_all = false,
    segment_shapes = { 0 }
  }
end

local function defaultPadLFO()
  return {
    enabled = false,
    rate = 2.0,
    depth = 0.6,
    offset = 0.5,
    shape = 0,
    mode = 0,
    sync_to_bpm = false,
    random_steps = 8,
    sync_div_idx = 2
  }
end

local function defaultPadMSEG()
  return {
    mode = 0,
    points = 2,
    division = 2,
    bars = 4,
    manual_positions = { 0.0, 1.0 },
    curve_mode = 0,
    segment_shapes = { 0 },
    values = { 0.8, 0.8 },
    selected_segment = 1,
    apply_all_shapes = false
  }
end

local function serialize(val)
  if type(val) == "table" then
    local out = {}
    for k, v in pairs(val) do
      local key = type(k) == "number" and ("[" .. k .. "]=") or ("[\"" .. tostring(k) .. "\"]=")
      out[#out + 1] = key .. serialize(v)
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  if type(val) == "string" then
    return string.format("%q", val)
  end
  if type(val) == "boolean" then
    return val and "true" or "false"
  end
  return tostring(val)
end

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

local function unserialize(str)
  if not str or str == "" then
    return nil
  end
  local fn, err = load("return " .. str)
  if not fn then
    r.ShowConsoleMsg("[ReaMotionPad] Failed to parse state: " .. tostring(err) .. "\n")
    return nil
  end
  local ok, tbl = pcall(fn)
  if not ok then
    r.ShowConsoleMsg("[ReaMotionPad] Failed to load state: " .. tostring(tbl) .. "\n")
    return nil
  end
  return tbl
end

local function defaultPad(name)
  return {
    name = name,
    points = { { x = 0.0, y = 0.5 }, { x = 1.0, y = 0.5 } },
    tension = 0.0,
    enabled = true,
    segment = defaultSegment(),
    link = {
      sources = {
        { enabled = true, fx_guid = "", fx_name = "", param_index = 0, param_name = "", min = 0.0, max = 1.0, invert = false, search = "" },
        { enabled = true, fx_guid = "", fx_name = "", param_index = 0, param_name = "", min = 0.0, max = 1.0, invert = false, search = "" },
        { enabled = true, fx_guid = "", fx_name = "", param_index = 0, param_name = "", min = 0.0, max = 1.0, invert = false, search = "" },
        { enabled = true, fx_guid = "", fx_name = "", param_index = 0, param_name = "", min = 0.0, max = 1.0, invert = false, search = "" }
      }
    }
  }
end

function State.GetDefault()
  return {
    version = "0.1.0",
    setup = {
      target_track_name = "",
      output_mode = 0,
      script_mode = 0,
      tag_match_mode = 0,
      write_shape = 2,
      write_tension = 0.0,
      random_seed = 1001,
      live_write_enabled = false,
      morph_mute_originals = false,
      auto_write = {
        pad_a = true,
        pad_b = true,
        external = true,
        lfo = true,
        mseg = true,
        master_vol = true,
        sel_env = true
      }
    },
    segment = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      inherit_all = true
    },
    master_mseg = {
      mode = 0,
      points = 2,
      division = 2,
      bars = 4,
      manual_positions = { 0.0, 1.0 },
      curve_mode = 0,
      segment_shapes = { 0 },
      values = { 0.8, 0.8 },
      selected_segment = 1,
      apply_all_shapes = false
    },
    master_lfo = {
      enabled = false,
      rate = 2.0,
      depth = 0.6,
      offset = 0.5,
      shape = 0,
      mode = 0,
      sync_to_bpm = false,
      random_steps = 8,
      sync_div_idx = 2,
      rate_sweep = 0.0,
      depth_ramp = 0.0,
      invert = false,
      mseg_to_lfo_rate = 0.0,
      mseg_to_lfo_depth = 0.0,
      lfo_to_mseg_depth = 0.0
    },
    independent_modulator = {
      lfo = {
        enabled = false,
        rate = 2.0,
        depth = 0.6,
        offset = 0.5,
        shape = 0,
        mode = 0,
        sync_to_bpm = false,
        random_steps = 8,
        sync_div_idx = 2,
        waveform_name = "Sine",
        phase = 0.0,
        random_seed = 1000,
        rate_sweep = 0.0,
        depth_ramp = 0.0,
        invert = false
      },
      mseg = {
        mode = 0,
        points = 2,
        division = 2,
        bars = 4,
        manual_positions = { 0.0, 1.0 },
        curve_mode = 0,
        segment_shapes = { 0 },
        values = { 0.8, 0.8 },
        selected_segment = 1,
        apply_all_shapes = false,
        curve_tension = 0.0
      },
      targets = {}
    },
    random = {
      pad_a = true,
      pad_b = true,
      external = false,
      lfo = false,
      mseg = false,
      ind_lfo = false,
      ind_mseg = false
    },
    external = {
      pad = defaultPad("External"),
      sources = {
        { name = "Ext 1", ch_l = 1, ch_r = 2, gain = 1.0, enabled = true },
        { name = "Ext 2", ch_l = 3, ch_r = 4, gain = 1.0, enabled = true },
        { name = "Ext 3", ch_l = 5, ch_r = 6, gain = 1.0, enabled = true },
        { name = "Ext 4", ch_l = 7, ch_r = 8, gain = 1.0, enabled = true }
      }
    },
    mixer = {
      channels = {
        { min = 0.0, max = 1.0 }, -- -60 dB to +6 dB (normalized for JSFX)
        { min = 0.0, max = 1.0 },
        { min = 0.0, max = 1.0 },
        { min = 0.0, max = 1.0 }
      }
    },
    pads = {
      link_a = defaultPad("Link A"),
      link_b = defaultPad("Link B"),
      morph = defaultPad("Morph")
    },
    lfo = {
      lfo1 = { rate = 1.0, depth = 1.0, offset = 0.5, shape = 0, enabled = true },
      lfo2 = { rate = 0.5, depth = 0.7, offset = 0.5, shape = 2, enabled = false }
    },
    env = {
      env1 = { attack = 0.1, decay = 0.25, sustain = 0.65, release = 0.2, enabled = true }
    },
    bindings = {},
    ui = {
      selected_fx = 0,
      selected_param = 0,
      selected_source = 1
    }
  }
end

function State.Load()
  local retval, raw = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  local state = State.GetDefault()
  if retval <= 0 or not raw or raw == "" then
    return state
  end
  local loaded = unserialize(raw)
  if type(loaded) ~= "table" then
    return state
  end

  local function merge(dst, src)
    for k, v in pairs(src) do
      if type(v) == "table" and type(dst[k]) == "table" then
        merge(dst[k], v)
      else
        dst[k] = v
      end
    end
  end

  merge(state, loaded)

  local function migratePad(pad)
    if not pad then
      return
    end

    if pad.sx and not pad.points then
      pad.points = {
        { x = 0.0,           y = pad.sy or 0.2 },
        { x = pad.px or 0.5, y = pad.py or 0.8 },
        { x = 1.0,           y = pad.ey or 0.2 }
      }
    end

    if type(pad.segment) ~= "table" then
      pad.segment = defaultSegment()
    else
      local seg = pad.segment
      seg.mode = math.max(0, math.floor(tonumber(seg.mode) or 0))
      seg.points = math.max(2, math.min(12, math.floor(tonumber(seg.points) or 4)))
      seg.division = math.max(1, math.min(8, math.floor(tonumber(seg.division) or 2)))
      seg.bars = math.max(1, math.min(16, math.floor(tonumber(seg.bars) or 4)))
      seg.curve_mode = math.max(0, math.min(5, math.floor(tonumber(seg.curve_mode) or 0)))
      seg.curve_tension = clamp(tonumber(seg.curve_tension) or 0.0, 0.0, 1.0)
      if seg.apply_all == nil then
        seg.apply_all = false
      end
      if type(seg.manual_positions) ~= "table" then
        seg.manual_positions = { 0.0, 0.333, 0.667, 1.0 }
      end
      if type(seg.segment_shapes) ~= "table" then
        seg.segment_shapes = {}
      end
    end

    if type(pad.link) ~= "table" then
      pad.link = {}
    end

    if type(pad.link.sources) ~= "table" then
      pad.link.sources = {}
    end

    for i = 1, 4 do
      if type(pad.link.sources[i]) ~= "table" then
        local default_axis = (i == 1 or i == 3) and 'x' or 'y'
        pad.link.sources[i] = {
          enabled = true,
          fx_guid = "",
          fx_name = "",
          param_index = 0,
          param_name = "",
          min = 0.0,
          max = 1.0,
          invert = false,
          search =
          "",
          curve = "linear",
          bipolar = false,
          scale = 1.0,
          offset = 0.0,
          axis = default_axis
        }
      else
        local s = pad.link.sources[i]
        if s.enabled == nil then s.enabled = true end
        if s.fx_guid == nil then s.fx_guid = "" end
        if s.fx_name == nil then s.fx_name = "" end
        if s.param_index == nil then s.param_index = 0 end
        if s.param_name == nil then s.param_name = "" end
        if s.min == nil then s.min = 0.0 end
        if s.max == nil then s.max = 1.0 end
        if s.invert == nil then s.invert = false end
        if s.search == nil then s.search = "" end
        if s.curve == nil then s.curve = "linear" end
        if s.bipolar == nil then s.bipolar = false end
        if s.scale == nil then s.scale = 1.0 end
        if s.offset == nil then s.offset = 0.0 end
        if s.axis == nil then s.axis = (i == 1 or i == 3) and 'x' or 'y' end
      end
    end
  end

  local function migrateMasterMSEG(mseg)
    if type(mseg) ~= "table" then
      return
    end

    mseg.mode = math.max(0, math.floor(tonumber(mseg.mode) or 0))
    mseg.points = math.max(2, math.min(16, math.floor(tonumber(mseg.points) or 4)))
    mseg.division = math.max(1, math.min(8, math.floor(tonumber(mseg.division) or 2)))
    mseg.bars = math.max(1, math.min(16, math.floor(tonumber(mseg.bars) or 4)))
    mseg.curve_mode = math.max(0, math.min(5, math.floor(tonumber(mseg.curve_mode) or 0)))

    if type(mseg.manual_positions) ~= "table" then
      mseg.manual_positions = { 0.0, 0.333, 0.667, 1.0 }
    end
    if type(mseg.segment_shapes) ~= "table" then
      mseg.segment_shapes = {}
    end
    if type(mseg.values) ~= "table" then
      mseg.values = {}
    end
    if mseg.apply_all_shapes == nil then
      mseg.apply_all_shapes = false
    end
  end

  local function migrateMasterLFO(lfo)
    if type(lfo) ~= "table" then
      return
    end

    if lfo.enabled == nil then lfo.enabled = false end
    if lfo.sync_to_bpm == nil then lfo.sync_to_bpm = false end
    if lfo.rate_sweep == nil then lfo.rate_sweep = 0.0 end
    if lfo.depth_ramp == nil then lfo.depth_ramp = 0.0 end
    if lfo.invert == nil then lfo.invert = false end
    lfo.rate = clamp(tonumber(lfo.rate) or 2.0, 0.05, 32.0)
    lfo.depth = clamp(tonumber(lfo.depth) or 0.6, 0.0, 1.0)
    lfo.offset = clamp(tonumber(lfo.offset) or 0.5, 0.0, 1.0)
    lfo.shape = math.max(0, math.min(5, math.floor(tonumber(lfo.shape) or 0)))
    lfo.mode = math.max(0, math.min(6, math.floor(tonumber(lfo.mode) or 0)))
    lfo.random_steps = math.max(2, math.min(32, math.floor(tonumber(lfo.random_steps) or 8)))
    lfo.mseg_to_lfo_rate = tonumber(lfo.mseg_to_lfo_rate) or 0.0
    lfo.mseg_to_lfo_depth = tonumber(lfo.mseg_to_lfo_depth) or 0.0
    lfo.lfo_to_mseg_depth = tonumber(lfo.lfo_to_mseg_depth) or 0.0
  end

  if state.pads then
    migratePad(state.pads.link_a)
    migratePad(state.pads.link_b)
  else
    state.pads = State.GetDefault().pads
  end

  if state.external and state.external.pad then
    migratePad(state.external.pad)
  end

  if type(state.external) ~= "table" then
    state.external = State.GetDefault().external
  end
  if type(state.external.sources) ~= "table" then
    state.external.sources = State.GetDefault().external.sources
  end
  if #state.external.sources < 4 then
    local defaults = State.GetDefault().external.sources
    for i = #state.external.sources + 1, 4 do
      state.external.sources[i] = defaults[i]
    end
  end
  for i = 1, 4 do
    local src = state.external.sources[i]
    if type(src) ~= "table" then
      src = State.GetDefault().external.sources[i]
      state.external.sources[i] = src
    end
    if src.enabled == nil then
      src.enabled = true
    end
  end

  if type(state.master_mseg) ~= "table" then
    state.master_mseg = State.GetDefault().master_mseg
  end
  migrateMasterMSEG(state.master_mseg)

  if type(state.master_lfo) ~= "table" then
    state.master_lfo = State.GetDefault().master_lfo
  end
  migrateMasterLFO(state.master_lfo)

  -- Migrate random.mseg (added in v0.4.3)
  if state.random.mseg == nil then
    state.random.mseg = false
  end

  -- Migrate random.ind_lfo and random.ind_mseg (added in v0.5.3)
  if state.random.ind_lfo == nil then
    state.random.ind_lfo = false
  end
  if state.random.ind_mseg == nil then
    state.random.ind_mseg = false
  end

  -- Migrate random.external (added in v0.5.3)
  if state.random.external == nil then
    state.random.external = false
  end

  -- Migrate auto_write settings
  if state.setup.auto_write == nil then
    state.setup.auto_write = State.GetDefault().setup.auto_write
  else
    local defaults = State.GetDefault().setup.auto_write
    for k, v in pairs(defaults) do
      if state.setup.auto_write[k] == nil then
        state.setup.auto_write[k] = v
      end
    end
  end

  -- Migrate mixer channels: convert old 0.667 max to 1.0 (for new -60..+6 dB range)
  if type(state.mixer) == "table" and type(state.mixer.channels) == "table" then
    for i = 1, 4 do
      local ch = state.mixer.channels[i]
      if type(ch) == "table" and ch.max == 0.667 then
        ch.max = 1.0
      end
    end
  end

  return state
end

function State.Save(state)
  local ok, payload = pcall(serialize, state)
  if not ok then
    r.ShowConsoleMsg("[ReaMotionPad] Failed to serialize state: " .. tostring(payload) .. "\n")
    return false
  end
  r.SetProjExtState(0, EXT_SECTION, EXT_KEY, payload)
  return true
end

local PRESET_SECTION = "SBP_ReaMotionPad_Presets"

function State.HasPreset(slot)
  local retval, raw = r.GetProjExtState(0, PRESET_SECTION, 'slot_' .. tostring(slot))
  return retval > 0 and raw and raw ~= ''
end

function State.SavePreset(state, slot, track_name_override)
  local tname = track_name_override or (state.setup and state.setup.target_track_name) or ''
  local data = {
    track_name = tname,
    pads = state.pads,
    master_lfo = state.master_lfo,
    master_mseg = state.master_mseg,
    lfo = state.lfo,
    env = state.env,
    bindings = state.bindings,
    independent_modulator = state.independent_modulator,
  }
  local ok, payload = pcall(serialize, data)
  if not ok then
    r.ShowConsoleMsg('[ReaMotionPad] Preset save error: ' .. tostring(payload) .. '\n')
    return false
  end
  r.SetProjExtState(0, PRESET_SECTION, 'slot_' .. tostring(slot), payload)
  r.SetProjExtState(0, PRESET_SECTION, 'name_' .. tostring(slot), tname ~= '' and tname or '(unnamed)')
  return true
end

function State.LoadPreset(slot)
  local retval, raw = r.GetProjExtState(0, PRESET_SECTION, 'slot_' .. tostring(slot))
  if retval <= 0 or not raw or raw == '' then return nil end
  local data = unserialize(raw)
  if type(data) ~= 'table' then return nil end
  return data
end

function State.GetPresetTrackName(slot)
  local retval, name = r.GetProjExtState(0, PRESET_SECTION, 'name_' .. tostring(slot))
  if retval > 0 and name and name ~= '' then return name end
  return nil
end

return State
