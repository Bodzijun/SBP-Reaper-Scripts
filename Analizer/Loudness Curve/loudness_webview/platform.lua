-- Local paths and worker executables shared by report, audio and preview.
local M = {}
function M.windows(r)
  if r and r.GetOS then return r.GetOS():match('^Win') ~= nil end
  return package.config:sub(1,1) == '\\'
end
function M.path(value)
  if type(value) ~= 'string' then return nil, 'Enter an absolute local file path' end
  local path = value:match('^%s*(.-)%s*$')
  if path:sub(1,1) == '"' and path:sub(-1) == '"' then path = path:sub(2,-2) end
  if path:lower():match('^file://') then
    local host, rest = path:match('^[Ff][Ii][Ll][Ee]://([^/]*)(/.*)$')
    if not rest or (host ~= '' and host:lower() ~= 'localhost') then
      return nil, 'Use a local file URL (remote hosts are not supported)'
    end
    path = rest:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex,16)) end)
    if path:match('^/%a:[/\\]') then path = path:sub(2) end
  end
  if path:find('[%z\r\n\t]') then return nil, 'Invalid control character in file path' end
  if path:match('^%a:[/\\]') then return (path:gsub('/', '\\')) end
  if path:sub(1,1) == '/' and path:sub(2,2) ~= '/' then return path end
  return nil, 'Use an absolute local path, for example C:\\renders\\Mix.wav or /Users/name/renders/Mix.wav'
end
function M.argument(value, r)
  assert(type(value) == 'string' and not value:find('[%z\r\n]'), 'Invalid executable or file path')
  if M.windows(r) then
    assert(not value:find('"'), 'Invalid quote in executable or file path')
    return '"' .. value .. '"'
  end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end
function M.same_path(a,b,r)
  a,b=M.path(a),M.path(b)
  if not a or not b then return false end
  if M.windows(r) then return a:lower()==b:lower() end
  return a==b
end
local function exists(path)
  local file = io.open(path, 'rb'); if file then file:close(); return true end
end
function M.python(r)
  if M.windows(r) then
    local root = (os.getenv('LOCALAPPDATA') or '') .. '/Programs/Python'
    if r.EnumerateSubdirectories then
      for i = 0,100 do
        local folder = r.EnumerateSubdirectories(root,i); if not folder then break end
        local candidate = root .. '/' .. folder .. '/pythonw.exe'
        if exists(candidate) then return candidate end
      end
    end
    return 'pythonw.exe'
  end
  for _, path in ipairs({'/opt/homebrew/bin/python3','/usr/local/bin/python3','/usr/bin/python3'}) do
    if exists(path) then return path end
  end
  return 'python3'
end
function M.ffmpeg(r)
  local local_path = r.GetResourcePath() .. '/UserPlugins/' .. (M.windows(r) and 'ffmpeg.exe' or 'ffmpeg')
  if exists(local_path) then return local_path end
  if not M.windows(r) then
    for _,path in ipairs({'/opt/homebrew/bin/ffmpeg','/usr/local/bin/ffmpeg','/usr/bin/ffmpeg'}) do
      if exists(path) then return path end
    end
  end
  error('FFmpeg executable not found. Install it in REAPER UserPlugins' .. (M.windows(r) and ' (ffmpeg.exe).' or ' or /opt/homebrew/bin / /usr/local/bin.'))
end
function M.temp()
  return os.getenv('TEMP') or os.getenv('TMP') or os.getenv('TMPDIR') or (package.config:sub(1,1) ~= '\\' and '/tmp')
end
return M
