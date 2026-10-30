-- @description SBP MotorSynth 2 - Build Routing: dry EngineSim stems only
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
SBP_MS2_ROUTING={scheme='dry'}
dofile(path..'sbp_MotorSynth2_Build_Routing.lua')
