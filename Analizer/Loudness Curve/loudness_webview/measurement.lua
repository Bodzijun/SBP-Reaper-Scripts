local platform = dofile(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') .. 'platform.lua')
local M = {}

function M.new(r, directory, encode)
  local cache=dofile(directory..'cache.lua')
  local job
  local api = {}
  function api.busy() return job ~= nil end
  local function marker(path) local file=io.open(path,'wb');if file then file:close() end end
  function api.cancel()
    if job then marker(job.cancel);job.cancel_at=job.cancel_at or r.time_precise();return {requested=true} end
    return {requested=false}
  end
  function api.close()
    if job then marker(job.abandon);marker(job.cancel);job=nil end
  end
  function api.begin(request)
    assert(not job, 'An audio measurement is already running')
    local normalized, err = platform.path(request.audio); assert(normalized, err); request.audio=normalized
    local ffmpeg = platform.ffmpeg(r)
    local python = platform.python(r)
    local temp = cache.directory(r)
    request.cache_dir=temp
    local path = temp .. '/SBP_Loudness_' .. tostring(r.time_precise()):gsub('[^%d]', '') .. '_' .. math.random(1, 2147483647) .. '.json'
    request.ffmpeg = ffmpeg
    local output = assert(io.open(path, 'wb')); output:write(encode(request)); output:close()
    local command = platform.argument(python,r) .. ' ' .. platform.argument(directory .. 'measure_audio.py',r) .. ' ' .. platform.argument(path,r)
    local ok, err = pcall(r.ExecProcess, command, -2)
    if not ok then os.remove(path); error(err) end
    job = {path = path, result = path:gsub('%.json$', '.result'), progress = path:gsub('%.json$', '.progress'), cancel=path:gsub('%.json$','.cancel'),abandon=path:gsub('%.json$','.abandon'),started = r.time_precise(),advance=r.time_precise(),limit=math.max(1800,request.length*2+300)}
    return {running = true}
  end
  function api.poll()
    assert(job, 'No audio measurement is running')
    local file = io.open(job.result, 'rb')
    if not file then
      if job.cancel_at and r.time_precise()-job.cancel_at>=15 then api.close();return {running=false,cancelled=true} end
      if r.time_precise() - job.started < job.limit and r.time_precise()-job.advance<600 then
        local result = {running = true}
        local progress = io.open(job.progress, 'rb')
        if progress then
          local text = progress:read('*a'); progress:close()
          for key, value in text:gmatch('([%w_]+)=([^\r\n]+)') do result[key] = tonumber(value) or value end
          local signature=tostring(result.phase)..':'..tostring(result.percent)..':'..tostring(result.completed)..':'..tostring(result.processed)
          if signature~=job.signature then job.signature=signature;job.advance=r.time_precise() end
        end
        return result
      end
      api.close();error('Audio measurement stopped: no progress for 10 minutes or maximum runtime exceeded.')
    end
    local text = file:read('*a'); file:close()
    os.remove(job.path); os.remove(job.result); os.remove(job.progress);os.remove(job.cancel);os.remove(job.abandon);job = nil
    local result = {running = false}
    for key, value in text:gmatch('([%w_]+)=([^\r\n]+)') do result[key] = tonumber(value) or value end
    if result.status=='cancelled' then result.cancelled=true;return result end
    assert(result.status == 'ok', result.error or 'Audio measurement failed')
    return result
  end
  return api
end
return M
