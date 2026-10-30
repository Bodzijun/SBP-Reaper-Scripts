-- @description SBP MotorSynth 2: EngineSim chain setup
-- @noindex
-- @version 2.0.0pre2
-- Kept for compatibility: same as "Add EngineSim chain" (logic lives in MotorSynth_Lib.lua).
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
dofile(path..'sbp_MotorSynth2_Add_EngineSim.lua')
