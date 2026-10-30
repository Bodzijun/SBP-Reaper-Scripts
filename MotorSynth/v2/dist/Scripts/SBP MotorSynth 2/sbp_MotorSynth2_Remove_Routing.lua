-- @description SBP MotorSynth 2 - Remove Routing
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local source,fx=M.source();if not source then return end
if #M.routing_tracks(r.GetTrackGUID(source))==0 then
  r.ShowMessageBox('This MotorSynth 2 instance has no component routing.','MotorSynth 2',0) return
end
M.transaction('MotorSynth 2: remove component routing',function() M.remove_routing(source,fx) end)
