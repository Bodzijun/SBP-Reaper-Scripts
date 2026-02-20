local SegmentEngine = {}

local function clamp(v, min_v, max_v)
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

function SegmentEngine.GetPointCount(cfg, item_len)
  if cfg.mode == 0 then
    return math.max(2, math.floor(cfg.points or 2))
  end

  local div = tonumber(cfg.division or 2) or 2
  div = math.max(1, div)
  local grid = 1.0 / div
  local n = math.floor((item_len / grid) + 0.5) + 1
  return math.max(2, n)
end

function SegmentEngine.BuildTimes(start_t, end_t, seg_cfg)
  local len = math.max(0.001, end_t - start_t)
  local count = SegmentEngine.GetPointCount(seg_cfg, len)
  local out = {}
  if count <= 1 then
    out[1] = start_t
    return out
  end
  for i = 0, count - 1 do
    local t = i / (count - 1)
    out[#out + 1] = start_t + (len * clamp(t, 0.0, 1.0))
  end
  return out
end

return SegmentEngine
