local platform = dofile(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') .. 'platform.lua')
local M = {}

local function timestamp_seconds(text)
  local value = 0
  local count = 0
  for part in text:gmatch("[^:]+") do
    local number = tonumber(part)
    if not number then return nil end
    value, count = value * 60 + number, count + 1
  end
  if count < 2 or count > 3 then return nil end
  return value
end

function M.path_from_url(url)
  if type(url) ~= "string" then return nil, "Enter a local HTML path" end
  local path, err = platform.path(url)
  if not path then return nil, err end
  if not path:lower():match("%.html?$") then
    return nil, "Choose a REAPER HTML render report"
  end
  return path
end

function M.parse(html)
  if type(html) ~= "string" then return nil, "Missing HTML report" end
  local length = tonumber(html:match("%f[%w]length:%s*([%d%.]+)"))
  local integrated = tonumber(html:match("integrated:%s*%[[^%]]-,'([%-%d%.]+)'%]"))
  local series_text = html:match("series:%s*%[([^%]]+)%]")
  if not length or length <= 0 or not series_text then return nil, "REAPER loudness chart was not found" end
  local series = {}
  for name in series_text:gmatch("'([^']+)'") do series[#series + 1] = name end
  local metadata = {}
  local header = html:match("<thead>(.-)</thead>")
  local row = html:match("<tbody>%s*<tr>(.-)</tr>")
  if header and row then
    local headings, cells = {}, {}
    for text in header:gmatch("<th[^>]*>(.-)</th>") do headings[#headings+1] = text:gsub("<[^>]+>", ""):gsub("%s+", "") end
    for text in row:gmatch("<td[^>]*>(.-)</td>") do cells[#cells+1] = text:gsub("<[^>]+>", "") end
    local names = {Peak="peak",TruePeak="true_peak",LRA="lra",["MaxLUFS-M"]="max_m",["MaxLUFS-S"]="max_s"}
    for index, name in ipairs(headings) do if names[name] then metadata[names[name]] = tonumber(cells[index]) end end
  end
  local histogram = {}
  local histogram_body = html:match("histogram:%s*%[(.-)%],%s*%}")
  if histogram_body then
    for fraction, high, low in histogram_body:gmatch("%[[%d%.]+,%s*[%d%.]+,%s*([%d%.]+),%s*'([^']+)',%s*'([^']+)'[^%]]*%]") do
      local value, upper = tonumber(fraction), tonumber(high)
      local lower = tonumber(low)
      if value and value >= 0 and value <= 1 and upper and (lower or low == '-inf') then
        histogram[#histogram+1] = {lower=lower, upper=upper, fraction=value}
      end
    end
  end
  local peak_indices = {}
  local m_index, s_index
  for index, name in ipairs(series) do
    if name:match("^Peak") then peak_indices[#peak_indices+1] = index+1 end
    if name == "LUFS-M" then m_index = index + 1 end
    if name == "LUFS-S" then s_index = index + 1 end
  end
  if not m_index and not s_index then return nil, "No LUFS-M or LUFS-S history in this report" end
  local body = html:match("vals:%s*%[(.-)%],%s*xmaj:")
  if not body then return nil, "Chart sample array was not found" end
  local points = {}
  local previous = -1
  for line in body:gmatch("[^\r\n]+") do
    if line:find("[[", 1, true) then
      local pairs_found = {}
      for number, label in line:gmatch("%[([%d%.%-]+),'([^']*)'%]") do
        pairs_found[#pairs_found + 1] = {number = tonumber(number), label = label}
      end
      local time = pairs_found[1] and timestamp_seconds(pairs_found[1].label)
      if not time or time <= previous or time > length + 0.1 then
        return nil, "Invalid or unordered time in loudness chart"
      end
      local m = m_index and pairs_found[m_index] and tonumber(pairs_found[m_index].label) or nil
      local s = s_index and pairs_found[s_index] and tonumber(pairs_found[s_index].label) or nil
      if not m and not s then return nil, "Missing loudness sample" end
      local peak
      for _, index in ipairs(peak_indices) do
        local value = pairs_found[index] and tonumber(pairs_found[index].label)
        if value then peak = peak and math.max(peak, value) or value end
      end
      points[#points + 1] = {time = time, momentary = m, short_term = s, peak = peak}
      previous = time
      if #points > 200000 then return nil, "Too many chart samples" end
    end
  end
  if #points < 2 then return nil, "Not enough loudness samples" end
  return {length = length, integrated = integrated, series = series, points = points, metadata = metadata, histogram = histogram,
    name = html:match("%f[%w]name:%s*'([^']*)'") or "Render"}
end

function M.load(url)
  local path, err = M.path_from_url(url)
  if not path then return nil, err end
  local file, open_err = io.open(path, "rb")
  if not file then
    return nil, "Cannot open HTML report: " .. path .. (open_err and (" (" .. open_err .. ")") or "") ..
      ". Save the render statistics as HTML from REAPER's Render Statistics window, then Browse to that file."
  end
  local size = file:seek("end")
  if not size or size > 32 * 1024 * 1024 then file:close(); return nil, "HTML report exceeds 32 MB" end
  file:seek("set", 0)
  local html = file:read("*a")
  file:close()
  local report, parse_err = M.parse(html)
  if report then report.path = path end
  return report, parse_err
end

return M
