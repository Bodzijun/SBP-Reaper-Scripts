-- @description SBP MotorSynth 2 - Prepare Controls
-- @noindex
-- @version 2.0.0pre1
-- @author SBP
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local track,fx=M.source();if not track then return end
M.transaction('MotorSynth 2: prepare control envelopes',function()
  for _,id in ipairs({1,2,3,7,8,10,32,68,92,93,94,95,96,99,101,167,168,169,170,171,172,173,174,176,182,184,185}) do
    local env=r.GetFXEnvelope(track,fx,id-1,true)
    if env then
      local ok,chunk=r.GetEnvelopeStateChunk(env,'',false)
      if ok then
        chunk=chunk:gsub('\nVIS %d+','\nVIS 1',1)
        r.SetEnvelopeStateChunk(env,chunk,false)
      end
    end
  end
end)
