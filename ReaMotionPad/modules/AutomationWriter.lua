local AutomationWriter = {}
local r = reaper

local function clearRange(env, start_t, end_t)
  if not env then return end
  local point_count = r.CountEnvelopePoints(env)
  for i = point_count - 1, 0, -1 do
    local ok, time = r.GetEnvelopePoint(env, i)
    if ok and time >= start_t and time <= end_t then
      r.DeleteEnvelopePointEx(env, -1, i)
    end
  end
end

function AutomationWriter.WriteOverwrite(track, targets, points, shape, tension)
  if not track then return 0 end
  if #targets == 0 or #points < 2 then return 0 end

  local written = 0
  local start_t = points[1].time
  local end_t = points[#points].time

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for _, target in ipairs(targets) do
    local env = target.env
    if env then
      clearRange(env, start_t, end_t)
      for _, p in ipairs(points) do
        local v = target.value_at(p.t)
        r.InsertEnvelopePoint(env, p.time, v, shape or 1, tension or 0.0, true, true)
        written = written + 1
      end
      r.Envelope_SortPoints(env)
    end
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("SBP ReaMotion Pad: Write Automation", -1)
  r.UpdateArrange()
  return written
end

return AutomationWriter
