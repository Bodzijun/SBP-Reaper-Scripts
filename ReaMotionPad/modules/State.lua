local State = {}
local r = reaper

local EXT_SECTION = "SBP_ReaMotionPad"
local EXT_KEY = "ProjectState"

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
    sx = 0.1,
    sy = 0.2,
    px = 0.5,
    py = 0.8,
    ex = 0.9,
    ey = 0.2,
    tension = 0.0,
    enabled = true
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
      write_shape = 1,
      write_tension = 0.0,
      random_seed = 1001
    },
    segment = {
      mode = 0,
      points = 4,
      division = 2,
      bars = 4,
      manual_positions = {0.0, 0.333, 0.667, 1.0},
      inherit_all = true
    },
    random = {
      pad_a = true,
      pad_b = true,
      pad_c = true,
      morph = true,
      lfo = false,
      env = false
    },
    external = {
      pad = defaultPad("External"),
      sources = {
        {name = "Ext 1", ch_l = 1, ch_r = 2, gain = 1.0, enabled = true},
        {name = "Ext 2", ch_l = 3, ch_r = 4, gain = 1.0, enabled = true},
        {name = "Ext 3", ch_l = 5, ch_r = 6, gain = 1.0, enabled = false},
        {name = "Ext 4", ch_l = 7, ch_r = 8, gain = 1.0, enabled = false}
      }
    },
    pads = {
      link_a = defaultPad("Link A"),
      link_b = defaultPad("Link B"),
      link_c = defaultPad("Link C"),
      morph = defaultPad("Morph")
    },
    lfo = {
      lfo1 = {rate = 1.0, depth = 1.0, offset = 0.5, shape = 0, enabled = true},
      lfo2 = {rate = 0.5, depth = 0.7, offset = 0.5, shape = 2, enabled = false}
    },
    env = {
      env1 = {attack = 0.1, decay = 0.25, sustain = 0.65, release = 0.2, enabled = true}
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
  local raw = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  local state = State.GetDefault()
  if not raw or raw == "" then
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
    if pad.sx and not pad.points then
      pad.points = {
        {x = 0.0, y = pad.sy or 0.2},
        {x = pad.px or 0.5, y = pad.py or 0.8},
        {x = 1.0, y = pad.ey or 0.2}
      }
    end
  end
  
  if state.pads then
    migratePad(state.pads.link_a)
    migratePad(state.pads.link_b)
    migratePad(state.pads.link_c)
    migratePad(state.pads.morph)
  end
  if state.external and state.external.pad then
    migratePad(state.external.pad)
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

return State
