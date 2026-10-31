local platform = dofile(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') .. 'platform.lua')
local M = {}

function M.regions(r, start, duration)
  assert(type(start) == 'number' and start >= 0 and duration > 0, 'Invalid render range')
  local regions, index = {}, 0
  while true do
    local ok, is_region, position, finish, name, id, color = r.EnumProjectMarkers3(0, index)
    if ok == 0 then break end
    if is_region and position < start + duration and finish > start then
      local hex = '#557c83'
      if color and color ~= 0 and r.ColorFromNative then
        local red, green, blue = r.ColorFromNative(color)
        hex = string.format('#%02x%02x%02x', red, green, blue)
      end
      regions[#regions + 1] = {start = math.max(0, position - start), finish = math.min(duration, finish - start),
        name = name ~= '' and name or ('Region ' .. tostring(id)), id = id, color = hex,
        project_start = position, project_finish = finish}
    end
    index = index + 1
    assert(index < 100000, 'Too many project markers')
  end
  table.sort(regions, function(a,b) return a.start < b.start end)
  return regions
end

function M.scenes(r, start, duration, source, track_name, naming, window_start, window_end, max_count)
  max_count=max_count or 2000
  window_start,window_end=window_start or 0,window_end or duration
  assert(window_start>=0 and window_start<window_end and window_end<=duration+1e-6,'Invalid scene time window')
  window_end=math.min(duration,window_end)
  local function selected(position,finish)
    return position-start<window_end and finish-start>window_start
  end
  if source == 'regions' then
    local list={}
    for _,scene in ipairs(M.regions(r,start,duration)) do
      if selected(scene.project_start,scene.project_finish) then list[#list+1]=scene end
    end
    assert(#list<=max_count,'Too many scenes. Select a smaller scene time window (analysis limit: 2000).')
    return list
  end
  assert(source == 'track' and type(start) == 'number' and start >= 0 and duration > 0, 'Invalid scene source or range')
  local wanted = (track_name or ''):match('^%s*(.-)%s*$'):lower()
  assert(wanted ~= '', 'Enter the scene track name')
  assert(naming == 'auto' or naming == 'notes' or naming == 'name', 'Invalid scene naming mode')
  local track
  for i = 0, r.CountTracks(0) - 1 do
    local candidate = r.GetTrack(0, i)
    local _, name = r.GetTrackName(candidate)
    if (name or ''):match('^%s*(.-)%s*$'):lower() == wanted then
      assert(not track, 'Multiple tracks have this scene track name')
      track = candidate
    end
  end
  assert(track, 'Scene track was not found: ' .. track_name)
  local list = {}
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, i)
    local position = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local finish = position + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    if finish > position and position < start + duration and finish > start and selected(position,finish) then
      local name
      if naming ~= 'notes' then
        local take = r.GetActiveTake(item)
        if take then local _, value = r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', false); name = value end
      end
      if naming ~= 'name' and (not name or name:match('^%s*$')) then
        local _, value = r.GetSetMediaItemInfo_String(item, 'P_NOTES', '', false); name = value
      end
      name = (name or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
      local _, guid = r.GetSetMediaItemInfo_String(item, 'GUID', '', false)
      list[#list + 1] = {id = guid or tostring(i), name = name ~= '' and name or ('Scene ' .. (i + 1)),
        start = math.max(0, position - start), finish = math.min(duration, finish - start),
        project_start = position, project_finish = finish, color = '#557c83'}
      assert(#list <= max_count, 'Too many scenes. Select a smaller scene time window (analysis limit: 2000).')
    end
  end
  table.sort(list, function(a,b) return a.start < b.start end)
  return list
end

function M.waveform(r)
  local source, building, result, ready, detail, detail_revision
  detail_revision=0
  local api = {}
  function api.clear()
    if source then
      if building then r.PCM_Source_BuildPeaks(source, 2) end
      r.PCM_Source_Destroy(source)
    end
    source, building, result,ready,detail = nil, false, nil,false,nil
    detail_revision=detail_revision+1
  end
  function api.begin(path)
    api.clear()
    local normalized, err = platform.path(path); assert(normalized, err); path = normalized
    source = r.PCM_Source_CreateFromFileEx(path, true)
    assert(source, 'Cannot open rendered audio')
    local length, quarter_notes = r.GetMediaSourceLength(source)
    local channels = r.GetMediaSourceNumChannels(source)
    if not length or length <= 0 or quarter_notes or channels < 1 or channels > 64 then
      api.clear(); error('Choose a valid rendered audio file')
    end
    result = {length = length, channels = channels, name = path:match('[^/\\]+$') or path, points = {}}
    building = r.PCM_Source_BuildPeaks(source, 0) ~= 0
    return {building = building, length = length, name = result.name}
  end
  function api.poll()
    assert(source and result, 'Load audio first')
    if ready then return {building=false,length=result.length,name=result.name,count=#result.points,step=result.length/4096} end
    if building then
      local remaining = r.PCM_Source_BuildPeaks(source, 1)
      if remaining ~= 0 then return {building = true, remaining = remaining} end
      r.PCM_Source_BuildPeaks(source, 2); building = false
    end
    local count, channels = 4096, result.channels
    local buffer = r.new_array(count * channels * 2)
    local returned = r.PCM_Source_GetPeaks(source, count / result.length, 0, channels, count, 0, buffer) & 0xfffff
    if returned < 1 then api.clear(); error('Audio peak data is unavailable') end
    for sample = 0, math.min(returned, count) - 1 do
      local high, low = 0, 0
      for channel = 1, channels do
        high = math.max(high, buffer[sample * channels + channel])
        low = math.min(low, buffer[count * channels + sample * channels + channel])
      end
      result.points[#result.points + 1] = {time = sample * result.length / count, high = high, low = low}
    end
    ready=true
    return {building = false, length = result.length, name = result.name, count = #result.points, step = result.length / count}
  end
  function api.chunk(offset)
    assert(result and ready, 'Audio peaks are not ready')
    assert(offset and offset >= 0 and offset % 1 == 0, 'Invalid peak offset')
    local points = {}
    for i = offset + 1, math.min(offset + 128, #result.points) do points[#points + 1] = result.points[i] end
    return {offset = offset, total = #result.points, points = points}
  end
  function api.detail(start,finish,count)
    assert(source and ready,'Load waveform peaks first')
    assert(start and finish and count and start>=0 and finish>start and start<result.length and count%1==0 and count>=1 and count<=4096,'Invalid detailed waveform range')
    finish=math.min(finish,result.length)
    local duration=finish-start
    count=math.max(1,math.min(count,math.floor(duration*48000)))
    local channels=result.channels
    local buffer=r.new_array(count*channels*2)
    local returned=r.PCM_Source_GetPeaks(source,count/duration,start,channels,count,0,buffer)&0xfffff
    assert(returned>0,'Detailed waveform peaks are unavailable')
    detail_revision=detail_revision+1
    detail={points={},start=start,finish=finish,step=duration/count,revision=detail_revision}
    for sample=0,math.min(returned,count)-1 do
      local high,low=0,0
      for channel=1,channels do
        high=math.max(high,buffer[sample*channels+channel]);low=math.min(low,buffer[count*channels+sample*channels+channel])
      end
      detail.points[#detail.points+1]={time=start+sample*detail.step,high=high,low=low}
    end
    return {start=start,finish=finish,count=#detail.points,step=detail.step,revision=detail_revision}
  end
  function api.detail_chunk(revision,offset)
    assert(detail and revision==detail.revision and offset and offset>=0 and offset%1==0,'Detailed waveform view changed')
    local points={};for i=offset+1,math.min(offset+256,#detail.points) do points[#points+1]=detail.points[i] end
    return {points=points}
  end
  return api
end
return M
