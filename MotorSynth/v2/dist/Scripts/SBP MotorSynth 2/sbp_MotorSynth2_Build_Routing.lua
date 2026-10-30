-- @description SBP MotorSynth 2 - Build Routing
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
-- Scheme comes from SBP_MS2_ROUTING (set by the scheme actions / Control Center),
-- otherwise from ExtState SBP_MotorSynth2/routing_scheme, otherwise 'spatial'
-- (the original 15 spatial component tracks).
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local r=reaper
local req=SBP_MS2_ROUTING;SBP_MS2_ROUTING=nil
local function state(key,default)
  local v=r.GetExtState('SBP_MotorSynth2',key)
  return v~='' and v or default
end
local opts={
  scheme=req and req.scheme or state('routing_scheme','spatial'),
  exhaust=req and req.exhaust or state('routing_exhaust','systems'),
  cylinders=tonumber(req and req.cylinders or state('routing_cylinders','16')),
}
local rebuild=req and req.rebuild
local source,fx=M.source();if not source then return end
local guid=r.GetTrackGUID(source)
local existing=#M.routing_tracks(guid)
if existing>0 and not rebuild then
  local answer=r.ShowMessageBox('Component outputs already exist for this MotorSynth 2 instance.\n\nDelete them and build the selected scheme again?\n(Undo restores the previous tracks.)','MotorSynth 2',4)
  if answer~=6 then return end
  rebuild=true
end
if existing==0 and (r.GetParentTrack(source) or r.GetMediaTrackInfo_Value(source,'I_FOLDERDEPTH')~=0) then
  r.ShowMessageBox('Select a standalone MotorSynth 2 track outside a folder to build routing.','MotorSynth 2',0)
  return
end
if (opts.scheme=='print' or opts.scheme=='split' or opts.scheme=='dry') and not M.engine_sim(source,fx) then
  local answer=r.ShowMessageBox('This scheme uses the EngineSim dry stems (channels 33-62), but the vehicle has no EngineSim chain.\n\nAdd the chain (Link + EngineSim Stems CLAP + MotorSynth UI8) now?','MotorSynth 2',4)
  if answer~=6 then return end
  local done
  M.transaction('MotorSynth 2: add EngineSim chain',function()
    local ok,report=M.setup_engine_sim(source)
    done=ok
    if not ok then error(table.concat(report,'\n')) end
  end)
  if not done then return end
  fx=M.find(source)
end
M.transaction('MotorSynth 2: build component routing ('..opts.scheme..')',function()
  if existing>0 then
    -- Track index must be re-read after deletion; parent folder must be gone too.
    M.remove_routing(source,fx)
    if r.GetParentTrack(source) then error('The vehicle track is inside another folder; move it out and try again.') end
  end
  M.build_routing(source,fx,opts)
end)
