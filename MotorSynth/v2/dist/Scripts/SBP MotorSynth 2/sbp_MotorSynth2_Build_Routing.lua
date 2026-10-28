-- @description SBP MotorSynth 2 - Build Routing
-- @noindex
-- @version 2.0.0pre1
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local source,fx=M.source();if not source then return end
local guid=r.GetTrackGUID(source)
for i=0,r.CountTracks(0)-1 do
  local track=r.GetTrack(0,i)
  local _,owner=r.GetSetMediaTrackInfo_String(track,'P_EXT:SBP_MS2_SOURCE','',false)
  local _,role=r.GetSetMediaTrackInfo_String(track,'P_EXT:SBP_MS2_ROLE','',false)
  if owner==guid and role=='folder' then
    r.ShowMessageBox('Component outputs already exist for this MotorSynth 2 instance.','MotorSynth 2',0)
    return
  end
end
-- Keep existing folder nesting intact: v1 of the setup action accepts flat source tracks.
if r.GetParentTrack(source) or r.GetMediaTrackInfo_Value(source,'I_FOLDERDEPTH')~=0 then
  r.ShowMessageBox('Select a standalone MotorSynth 2 track outside a folder to build routing.','MotorSynth 2',0)
  return
end
M.transaction('MotorSynth 2: build component routing',function()
  M.configure(source,fx)
  local index=math.floor(r.GetMediaTrackInfo_Value(source,'IP_TRACKNUMBER'))-1
  r.InsertTrackAtIndex(index,true)
  local folder=r.GetTrack(0,index)
  r.GetSetMediaTrackInfo_String(folder,'P_NAME','MotorSynth 2 — Components',true)
  r.GetSetMediaTrackInfo_String(folder,'P_EXT:SBP_MS2_SOURCE',guid,true)
  r.GetSetMediaTrackInfo_String(folder,'P_EXT:SBP_MS2_ROLE','folder',true)
  r.SetMediaTrackInfo_Value(folder,'I_FOLDERDEPTH',1)
  r.SetMediaTrackInfo_Value(source,'B_MAINSEND',0)
  for i,name in ipairs(M.stems) do
    local at=index+1+i
    r.InsertTrackAtIndex(at,true)
    local track=r.GetTrack(0,at)
    r.GetSetMediaTrackInfo_String(track,'P_NAME',name,true)
    r.GetSetMediaTrackInfo_String(track,'P_EXT:SBP_MS2_SOURCE',guid,true)
    r.GetSetMediaTrackInfo_String(track,'P_EXT:SBP_MS2_ROLE','stem_'..i,true)
    r.SetMediaTrackInfo_Value(track,'I_NCHAN',2)
    r.SetMediaTrackInfo_Value(track,'I_FOLDERDEPTH',i==#M.stems and -1 or 0)
    local send=r.CreateTrackSend(source,track)
    assert(send>=0,'Could not create stem send')
    r.SetTrackSendInfo_Value(source,0,send,'I_SRCCHAN',i*2)
    r.SetTrackSendInfo_Value(source,0,send,'I_DSTCHAN',0)
    r.SetTrackSendInfo_Value(source,0,send,'I_MIDIFLAGS',31)
    r.SetTrackSendInfo_Value(source,0,send,'I_SENDMODE',3)
    r.SetTrackSendInfo_Value(source,0,send,'D_VOL',1)
  end
end)
