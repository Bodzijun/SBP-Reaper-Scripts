-- @description SBP MotorSynth 2 - Build Routing: spatial stems + muted dry EngineSim
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
SBP_MS2_ROUTING={scheme='print'}
dofile(path..'sbp_MotorSynth2_Build_Routing.lua')
