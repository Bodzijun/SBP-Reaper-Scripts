-- @description SBP MotorSynth 2 - Add EngineSim chain
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
-- Link JSFX -> EngineSim Stems CLAP -> MotorSynth UI8 on the selected vehicle track.
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local track=M.source(true) or r.GetSelectedTrack(0,0)
if not track then r.ShowMessageBox('Select the vehicle track first.','MotorSynth 2',0) return end
local report
M.transaction('MotorSynth 2: EngineSim chain setup',function()
  local _;_,report=M.setup_engine_sim(track)
end)
if report and not SBP_MS2_QUIET then r.ShowMessageBox(table.concat(report,'\n'),'MotorSynth 2 · EngineSim',0) end
