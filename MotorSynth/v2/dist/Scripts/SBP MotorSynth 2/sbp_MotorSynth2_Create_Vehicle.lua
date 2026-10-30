-- @description SBP MotorSynth 2 - Create Vehicle
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
-- @provides
--   [nomain] MotorSynth_Lib.lua
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
M.transaction('MotorSynth 2: create vehicle',function()
  local track=r.GetSelectedTrack(0,0)
  local fx=M.find(track)
  if not fx then
    -- Refresh old instrument tags without opening FX Browser or Action List.
    r.EnumInstalledFX(-1)
    local index=r.CountTracks(0)
    r.InsertTrackAtIndex(index,true);track=r.GetTrack(0,index)
    r.GetSetMediaTrackInfo_String(track,'P_NAME','MotorSynth 2 — Vehicle',true)
    fx=r.TrackFX_AddByName(track,M.effect,false,-1)
    if fx<0 then fx=r.TrackFX_AddByName(track,M.reapack_effect,false,-1) end
    if fx<0 then
      r.DeleteTrack(track)
      error('MotorSynth 2 was not found. Install the complete package and refresh the FX browser.')
    end
  end
  M.configure(track,fx)
  r.SetOnlyTrackSelected(track)
  r.TrackFX_Show(track,fx,3)
end)
