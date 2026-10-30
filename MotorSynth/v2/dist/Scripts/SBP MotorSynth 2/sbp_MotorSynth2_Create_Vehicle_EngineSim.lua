-- @description SBP MotorSynth 2 - Create Vehicle with EngineSim
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local track,report,ok
M.transaction('MotorSynth 2: create vehicle with EngineSim',function()
  r.EnumInstalledFX(-1)
  local index=r.CountTracks(0)
  r.InsertTrackAtIndex(index,true);track=r.GetTrack(0,index)
  r.GetSetMediaTrackInfo_String(track,'P_NAME','MotorSynth 2 — Vehicle (EngineSim)',true)
  ok,report=M.setup_engine_sim(track)
  if not M.find(track) then
    r.DeleteTrack(track);track=nil
    error(table.concat(report,'\n'))
  end
  r.SetOnlyTrackSelected(track)
end)
if track then
  if not ok then r.ShowMessageBox(table.concat(report,'\n'),'MotorSynth 2 · EngineSim',0) end
  r.TrackFX_Show(track,M.find(track),3)
end
