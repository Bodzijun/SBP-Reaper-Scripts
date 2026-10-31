-- Standalone read-only project naming settings. No PostMaster files required.
local M = {}
local fields = {
  {'location', '#Location'},
  {'bus_printmaster', 'PRINTMASTER'},
  {'bus_suffix', 'BUS'},
}
function M.load(r)
  local values = {}
  for _, field in ipairs(fields) do
    local key, fallback = field[1], field[2]
    local ok, value = r.GetProjExtState(0, 'SBP_PostMaster.Profile', key)
    -- Preserve projects configured with older Post Agent naming settings.
    if ok <= 0 and key:match('^bus_') then
      local legacy_key = 'stem_bus_' .. key:sub(5)
      ok, value = r.GetProjExtState(0, 'SBP_PostMaster.SBP_PostAgent', legacy_key)
      if ok <= 0 then ok, value = r.GetProjExtState(0, 'SBP_PostAgent', legacy_key) end
    end
    values[key] = ok > 0 and value ~= '' and value or fallback
  end
  return values
end
return M
