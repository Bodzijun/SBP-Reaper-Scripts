-- @description MotorSynth 2: create vehicle with EngineSim and GRIP (prototype)
-- @noindex
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local track,problem
M.transaction('MotorSynth 2: create GRIP vehicle',function()
 M.es_effects={'SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx'}
 local n=r.CountTracks(0);r.InsertTrackAtIndex(n,true);track=r.GetTrack(0,n)
 r.GetSetMediaTrackInfo_String(track,'P_NAME','MotorSynth 2 — Vehicle (EngineSim + GRIP)',true)
 local ready,report,id=M.setup_engine_sim(track)
 if not ready then problem=table.concat(report,'\n');return end
 local ctrl=M.find(track)
 local motion=r.TrackFX_AddByName(track,'JS: SBP MotorSynth 2/sbp_Grip_Motion_Link.jsfx',false,-1000)
 if motion<0 then problem='GRIP Motion Link not found. Install MotorSynth 2.';return end
 local grip=r.TrackFX_AddByName(track,'VST3i: Grip (BOOM Interactive)',false,-1001)
 if grip<0 then problem='BOOM GRIP not found. Install and scan the VST3 plug-in.';return end
 ctrl=M.find(track);motion=0;grip=1
 r.TrackFX_SetParam(track,motion,0,id)
 for pin=0,1 do
  local hi=pin==0 and 1073741824 or -2147483648
  if not r.TrackFX_SetPinMappings(track,grip,1,pin,0,hi) or not r.TrackFX_SetPinMappings(track,ctrl,0,62+pin,0,hi) then problem='Could not configure GRIP audio pins.';return end
 end
 local dest={0,4,10,3,7};local src={1,2,3,5,6};local names={'Speed','Grip','Blend Surface','IntExt','Suspension Impact'}
 for i=1,#dest do
  local _,nm=r.TrackFX_GetParamName(track,grip,dest[i],'')
  if nm~=names[i] then problem='Unexpected GRIP parameter: '..nm;return end
  local key='param.'..dest[i]..'.'
  for _,pair in ipairs({{'mod.active','1'},{'mod.baseline','0'},{'plink.effect',tostring(motion)},{'plink.param',tostring(src[i])},{'plink.scale','1'},{'plink.offset','0'},{'plink.active','1'}}) do
   if not r.TrackFX_SetNamedConfigParm(track,grip,key..pair[1],pair[2]) then problem='Could not link GRIP parameter '..nm;return end
  end
 end
 r.SetOnlyTrackSelected(track)
end)
if problem then r.ShowMessageBox(problem..'\nThe incomplete test track was kept for inspection; use Undo to remove it.','MotorSynth GRIP',0)
elseif track then r.TrackFX_Show(track,M.find(track),3) end
