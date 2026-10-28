-- SBP MotorSynth 2: project setup only. Audio and the editor live in JSFX/WebUI.
local M = {}
local r = reaper
M.effect = 'SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx'
M.reapack_effect = 'MotorSynth/v2/SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx'
local lib_path = debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):lower()
if lib_path:find('/scripts/motorsynth/v2/sbp motorsynth 2/',1,true) then
  M.effect, M.reapack_effect = M.reapack_effect, M.effect
end
M.stems = {'Exhaust','Engine','Mechanical','Gearbox','Intake','Turbo BOV','Tires','Chassis','Brakes','Backfire','Wind','Cabin','Accessories','Electric','Environment'}
function M.find(track)
  if not track then return nil end
  for i=0,r.TrackFX_GetCount(track)-1 do
    local _,ident=r.TrackFX_GetNamedConfigParm(track,i,'fx_ident')
    if ident and ident:gsub('\\','/'):match('sbp_MotorSynth_v2%.jsfx$') then return i end
  end
end
function M.source(silent)
  local selected=r.GetSelectedTrack(0,0)
  if selected and M.find(selected) then return selected,M.find(selected) end
  if selected then
    local _,guid=r.GetSetMediaTrackInfo_String(selected,'P_EXT:SBP_MS2_SOURCE','',false)
    if guid~='' then
      for i=0,r.CountTracks(0)-1 do
        local track=r.GetTrack(0,i)
        if r.GetTrackGUID(track)==guid and M.find(track) then return track,M.find(track) end
      end
    end
  end
  if not silent then r.ShowMessageBox('Select the MotorSynth 2 track or one of its stems.','MotorSynth 2',0) end
end
function M.transaction(name,fn)
  r.Undo_BeginBlock2(0);r.PreventUIRefresh(1)
  local ok,err=xpcall(fn,debug.traceback)
  r.PreventUIRefresh(-1);r.TrackList_AdjustWindows(false);r.UpdateArrange()
  r.Undo_EndBlock2(0,name,-1)
  if not ok then r.ShowMessageBox(tostring(err)..'\nChanges can be reverted with Undo.','MotorSynth 2',0) end
end
function M.configure(track,fx)
  r.SetMediaTrackInfo_Value(track,'I_NCHAN',32)
  for pin=0,31 do r.TrackFX_SetPinMappings(track,fx,1,pin,1<<pin,0) end
end
return M
