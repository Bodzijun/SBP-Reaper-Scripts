-- Recording helper for the MotorSynth 2 setup panel.
local R = {}
local r = reaper
local fields = {'I_RECARM','I_RECMODE','I_RECMODE_FLAGS','B_AUTO_RECARM','B_MUTE'}

local function item_id(item)
  local ok, id = r.GetSetMediaItemInfo_String(item, 'GUID', '', false)
  return ok and id or nil
end

function R.start(track)
  local project = r.EnumProjects(-1, '')
  if (r.GetPlayStateEx(project) & 4) ~= 0 then return nil, 'REAPER is already recording.' end
  local rec = {project=project, track=track, guid=r.GetTrackGUID(track), before={}, saved={}}
  for _, key in ipairs(fields) do rec.saved[key] = r.GetMediaTrackInfo_Value(track,key) end
  for i=0,r.CountTrackMediaItems(track)-1 do
    local id=item_id(r.GetTrackMediaItem(track,i)); if id then rec.before[id]=true end
  end
  r.SetMediaTrackInfo_Value(track,'B_AUTO_RECARM',0)
  r.SetMediaTrackInfo_Value(track,'I_RECMODE',3)
  r.SetMediaTrackInfo_Value(track,'I_RECMODE_FLAGS',math.floor(rec.saved.I_RECMODE_FLAGS) & (~3))
  r.SetMediaTrackInfo_Value(track,'B_MUTE',0)
  r.SetMediaTrackInfo_Value(track,'I_RECARM',1)
  local ok, err = pcall(r.Main_OnCommand,1013,0) -- Transport: Record
  if not ok or (r.GetPlayStateEx(project) & 4)==0 then
    for _,key in ipairs(fields) do r.SetMediaTrackInfo_Value(track,key,rec.saved[key]) end
    return nil, ok and 'REAPER did not start recording.' or ('Could not start recording: '..tostring(err))
  end
  return rec
end

function R.finish(rec)
  if not r.ValidatePtr2(rec.project,rec.track,'MediaTrack*') then return false,'The source track no longer exists.' end
  local items={}
  for i=0,r.CountTrackMediaItems(rec.track)-1 do
    local item=r.GetTrackMediaItem(rec.track,i); local id=item_id(item)
    if id and not rec.before[id] then items[#items+1]=item end
  end
  for _,key in ipairs(fields) do r.SetMediaTrackInfo_Value(rec.track,key,rec.saved[key]) end
  if #items==0 then return false,'No new recording was kept; the source was not muted.' end
  local destination
  for i=0,r.CountTracks(rec.project)-1 do
    local track=r.GetTrack(rec.project,i)
    local _,owner=r.GetSetMediaTrackInfo_String(track,'P_EXT:SBP_MS2_RECORD_SOURCE','',false)
    if owner==rec.guid then destination=track;break end
  end
  r.Undo_BeginBlock2(rec.project)
  if not destination then
    local index=r.CountTracks(rec.project)
    r.InsertTrackAtIndex(index,true); destination=r.GetTrack(rec.project,index)
    r.GetSetMediaTrackInfo_String(destination,'P_NAME','MotorSynth REC',true)
    r.GetSetMediaTrackInfo_String(destination,'P_EXT:SBP_MS2_RECORD_SOURCE',rec.guid,true)
  end
  local moved=0
  for _,item in ipairs(items) do if r.MoveMediaItemToTrack(item,destination) then moved=moved+1 end end
  if moved>0 then r.SetMediaTrackInfo_Value(rec.track,'B_MUTE',1) end
  r.Undo_EndBlock2(rec.project,'MotorSynth 2: move recorded audio',-1)
  r.TrackList_AdjustWindows(false);r.UpdateArrange()
  if moved<#items then return false,('Moved %d of %d recorded items. Check the source track.'):format(moved,#items) end
  return true,('Moved %d recording(s) to MotorSynth REC. Source muted.'):format(moved)
end

return R
