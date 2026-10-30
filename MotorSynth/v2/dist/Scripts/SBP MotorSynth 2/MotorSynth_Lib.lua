-- SBP MotorSynth 2: project setup only. Audio and the editor live in JSFX/WebUI.
-- 2.0.0pre2: EngineSim (UI8) chain support and alternative stem routing schemes.
local M = {}
local r = reaper
M.effect = 'SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx'
M.reapack_effect = 'MotorSynth/v2/SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx'
local lib_path = debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):lower()
if lib_path:find('/scripts/motorsynth/v2/sbp motorsynth 2/',1,true) then
  M.effect, M.reapack_effect = M.reapack_effect, M.effect
end
M.stems = {'Exhaust','Engine','Mechanical','Gearbox','Intake','Turbo BOV','Tires','Chassis','Brakes','Backfire','Wind','Cabin','Accessories','Electric','Environment'}

---------------------------------------------------------------------------
-- EngineSim (UI8) chain: Link JSFX -> EngineSim Stems CLAP -> MotorSynth UI8
---------------------------------------------------------------------------
M.bench = 'SBP MotorSynth 2'
-- MotorSynth builds that have the 14 EngineSim inputs (in pins 33..46).
M.es_effects = { M.bench..'/sbp_MotorSynth_v2.jsfx', M.effect, M.reapack_effect }
M.link_effect = M.bench..'/sbp_EngineSim_Link.jsfx'
M.clap_id = 'ua.sbp.engine-sim-stems'
M.clap_names = { 'CLAPi: SBP EngineSim Stems (SBP)', 'CLAP: SBP EngineSim Stems (SBP)', 'CLAPi:SBP EngineSim Stems', 'SBP EngineSim Stems' }
M.es_channels = 64          -- track channel count with EngineSim
M.es_first = 32             -- CLAP output 1 -> track channel 33 (0-based 32)
M.es_inputs = 14            -- MotorSynth reads 33..46
M.P_LINK_ID, M.P_LINK_ON = 218, 226          -- slider219, slider227
M.P_SIM_ENGINE, M.P_SIM_EXHAUST = 213, 214   -- slider214, slider215
M.copy_from = {             -- older MotorSynth instances whose settings can be copied
  { 'SBP MotorSynth Stems UI7 Bench/sbp_MotorSynth_v2.jsfx', 223 },
  { 'SBP MotorSynth Stems UI6 Bench/sbp_MotorSynth_v2.jsfx', 223 },
  { M.effect, 209 }, { M.reapack_effect, 209 },
}
-- Dry stems written by the CLAP (0-based track channels). mono=true -> one channel.
M.es_stems = {
  { key='main',   name='EngineSim Exhaust (Main)', ch=32 },
  { key='exa',    name='EngineSim Exhaust A',      ch=34 },
  { key='exb',    name='EngineSim Exhaust B',      ch=36 },
  { key='intake', name='EngineSim Intake',         ch=38 },
  { key='block',  name='EngineSim Block',          ch=40 },
  { key='valve',  name='EngineSim Valvetrain',     ch=42 },
  { key='start',  name='EngineSim Starter',        ch=44 },
}
M.es_cyl_first, M.es_cyl_max = 46, 16   -- Cyl 1..16 mono on 47..62

local function ident(track,fx)
  local ok,v=r.TrackFX_GetNamedConfigParm(track,fx,'fx_ident')
  return ok and v and v:gsub('\\','/') or ''
end
M.ident = ident
local function ends(v,s) return v==s or v:sub(-#s)==s end
function M.find_fx(track,test)
  if not track then return nil end
  for i=0,r.TrackFX_GetCount(track)-1 do
    if test(ident(track,i)) then return i end
  end
end

function M.find(track)
  if not track then return nil end
  local first,enabled
  for i=0,r.TrackFX_GetCount(track)-1 do
    if ident(track,i):match('sbp_MotorSynth_v2%.jsfx$') then
      first=first or i
      if r.TrackFX_GetEnabled(track,i) then
        if M.has_es_inputs(track,i) then return i end
        enabled=enabled or i
      end
    end
  end
  return enabled or first
end
function M.has_es_inputs(track,fx)
  local _,ins=r.TrackFX_GetIOSize(track,fx)
  return (ins or 0)>=M.es_first+M.es_inputs
end
function M.find_link(track) return M.find_fx(track,function(v) return ends(v,'sbp_EngineSim_Link.jsfx') end) end
function M.find_clap(track) return M.find_fx(track,function(v) return v==M.clap_id end) end
-- Returns true when the track carries the EngineSim chain feeding a UI8 MotorSynth.
function M.engine_sim(track,fx)
  fx=fx or M.find(track)
  return fx and M.find_clap(track) and M.has_es_inputs(track,fx) and true or false
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
  return ok
end
local function bits(ch)
  if ch<32 then return 1<<ch,0 end
  return 0,1<<(ch-32)
end
M.bits=bits
-- MotorSynth outputs 1..32. With EngineSim the track keeps 64 channels and
-- MotorSynth inputs 33..46 read the CLAP dry stems; channels 33..62 pass through.
function M.configure(track,fx)
  local es=M.engine_sim(track,fx)
  local want=es and M.es_channels or 32
  if r.GetMediaTrackInfo_Value(track,'I_NCHAN')<want or not es then
    r.SetMediaTrackInfo_Value(track,'I_NCHAN',want)
  end
  for pin=0,31 do r.TrackFX_SetPinMappings(track,fx,1,pin,1<<pin,0) end
  if es then
    for p=0,M.es_inputs-1 do
      local lo,hi=bits(M.es_first+p)
      r.TrackFX_SetPinMappings(track,fx,0,M.es_first+p,lo,hi)
    end
    local clap=M.find_clap(track)
    local _,_,outs=r.TrackFX_GetIOSize(track,clap)
    for p=0,math.min(outs or 0,30)-1 do
      local lo,hi=bits(M.es_first+p)
      r.TrackFX_SetPinMappings(track,clap,1,p,lo,hi)
    end
  end
  return es
end

local function add(track,names,prefix)
  for _,n in ipairs(names) do
    local i=r.TrackFX_AddByName(track,(prefix or '')..n,false,-1)
    if i>=0 then return i end
  end
  return -1
end
local function move(track,from,to)
  if from and from~=to then r.TrackFX_CopyToTrack(track,from,track,to,true) end
end
local function used_link_ids(except)
  local used={}
  for t=0,r.CountTracks(0)-1 do
    local track=r.GetTrack(0,t)
    if track~=except then
      local c=M.find(track)
      if c and M.has_es_inputs(track,c) then used[math.floor(r.TrackFX_GetParam(track,c,M.P_LINK_ID)+.5)]=true end
    end
  end
  return used
end

-- Builds (or repairs) Link -> CLAP -> MotorSynth UI8 on a track. Call inside M.transaction.
-- Returns ok, report lines, link id.
function M.setup_engine_sim(track)
  local report={}
  local ctrl=M.find(track)
  if not (ctrl and M.has_es_inputs(track,ctrl)) then
    local old=ctrl
    ctrl=-1
    for _,n in ipairs(M.es_effects) do
      local i=r.TrackFX_AddByName(track,n,false,-1)
      if i>=0 then
        if M.has_es_inputs(track,i) then ctrl=i break end
        r.TrackFX_Delete(track,i)            -- build without EngineSim inputs
      end
    end
    if ctrl<0 then
      return false,{'MotorSynth with EngineSim inputs was not found.\nCopy "'..M.bench..'" into REAPER/Effects and refresh the FX browser.'}
    end
    for _,src in ipairs(M.copy_from) do
      local o=M.find_fx(track,function(v) return ends(v,src[1]) end)
      if o and o~=ctrl then
        local n=math.min(r.TrackFX_GetNumParams(track,o),src[2])
        for p=0,n-1 do r.TrackFX_SetParam(track,ctrl,p,r.TrackFX_GetParam(track,o,p)) end
        r.TrackFX_SetEnabled(track,o,false)
        report[#report+1]='Settings copied from '..src[1]..' (old instance bypassed, not deleted).'
        break
      end
    end
    if old and r.TrackFX_GetEnabled(track,old) and old~=ctrl then r.TrackFX_SetEnabled(track,old,false) end
  end
  local clap=M.find_clap(track)
  if not clap then
    local i=add(track,M.clap_names)
    if i>=0 then clap=i else report[#report+1]='EngineSim Stems CLAP not found: install the .clap and rescan plug-ins.' end
  end
  local link=M.find_link(track)
  if not link then
    local i=add(track,{M.link_effect},'JS:')
    if i>=0 then link=i else report[#report+1]='Could not add '..M.link_effect..'.' end
  end
  local scene=M.find_fx(track,function(v) return ends(v,'sbp_Stems_Scene_Mix.jsfx') end)
  if scene and r.TrackFX_GetEnabled(track,scene) then
    r.TrackFX_SetEnabled(track,scene,false)
    report[#report+1]='Stems Scene Mix bypassed (no longer needed).'
  end
  ctrl=M.find(track)
  if link and clap then
    local pos=math.min(link,clap,ctrl)
    move(track,M.find_link(track),pos)
    move(track,M.find_clap(track),pos+1)
    move(track,M.find(track),pos+2)
    link,clap,ctrl=M.find_link(track),M.find_clap(track),M.find(track)
  end
  if clap then
    local _,ins=r.TrackFX_GetIOSize(track,clap)
    for p=0,math.max(0,ins or 0)-1 do r.TrackFX_SetPinMappings(track,clap,0,p,0,0) end
    r.TrackFX_SetParamNormalized(track,clap,25,0)                       -- input passthrough off
    local on=r.TrackFX_GetParam(track,ctrl,M.P_LINK_ON)>.5
    r.TrackFX_SetParamNormalized(track,clap,0,on and 0 or 1)            -- MotorSynth MIDI / Manual
  end
  M.configure(track,ctrl)
  if r.GetMediaTrackInfo_Value(track,'I_NCHAN')<M.es_channels then r.SetMediaTrackInfo_Value(track,'I_NCHAN',M.es_channels) end
  local used,id=used_link_ids(track),math.floor(r.TrackFX_GetParam(track,ctrl,M.P_LINK_ID)+.5)
  if used[id] then id=0 while used[id] and id<63 do id=id+1 end end
  r.TrackFX_SetParam(track,ctrl,M.P_LINK_ID,id)
  if link then r.TrackFX_SetParam(track,link,0,id) end
  report[#report+1]=('Chain ready. Link ID %d, %d channels.\nEngineSim dry stems: 33-62. MotorSynth outputs: 1-32.'):format(id,M.es_channels)
  return clap~=nil and link~=nil,report,id
end

---------------------------------------------------------------------------
-- Stem routing schemes
---------------------------------------------------------------------------
-- spatial : MotorSynth spatial stems 1..32 (original scheme; EngineSim mixed inside).
-- print   : spatial stems + muted EngineSim dry folder (for printing / parallel FX).
-- split   : spatial stems without EngineSim layers + audible EngineSim dry folder.
-- dry     : EngineSim dry stems only (MotorSynth stems are not routed).
M.schemes = {
  { key='spatial', name='Spatial stems (original)' },
  { key='print',   name='Spatial stems + dry EngineSim (muted, for print)' },
  { key='split',   name='Split: MotorSynth stems + dry EngineSim' },
  { key='dry',     name='Dry EngineSim stems only' },
  { key='grip_print', name='Spatial stems + dry GRIP (muted)' },
  { key='grip_split', name='Spatial stems + separate dry GRIP' },
}
-- Exhaust can be taken as two systems (A/B), as one Main signal, or per cylinder.
-- All three are created; the chosen one is audible, the other two are muted.
M.exhaust_modes = {
  { key='systems',   name='Exhaust A / B' },
  { key='main',      name='Exhaust Main' },
  { key='cylinders', name='Per-cylinder' },
}
local function ext(track,key,value)
  if value==nil then local _,v=r.GetSetMediaTrackInfo_String(track,'P_EXT:'..key,'',false) return v end
  r.GetSetMediaTrackInfo_String(track,'P_EXT:'..key,value,true)
end
M.ext=ext
local function is_routing_role(role)
  return role=='folder' or role:match('^stem_') or role:match('^es_') or role:match('^folder_') or role:match('^grip_')
end
function M.routing_tracks(guid)
  local list={}
  for i=0,r.CountTracks(0)-1 do
    local track=r.GetTrack(0,i)
    if ext(track,'SBP_MS2_SOURCE')==guid and is_routing_role(ext(track,'SBP_MS2_ROLE')) then list[#list+1]=track end
  end
  return list
end
-- Restores EngineSim layers switched off by the split scheme.
function M.restore_layers(source,fx)
  local saved=ext(source,'SBP_MS2_ES_SAVED')
  local a,b=saved:match('^([%d%.%-e]+),([%d%.%-e]+)$')
  if a then
    r.TrackFX_SetParam(source,fx,M.P_SIM_ENGINE,tonumber(a))
    r.TrackFX_SetParam(source,fx,M.P_SIM_EXHAUST,tonumber(b))
  end
  ext(source,'SBP_MS2_ES_SAVED','')
  local grip=tonumber(ext(source,'SBP_MS2_GRIP_SAVED'))
  if grip then r.TrackFX_SetParam(source,fx,227,grip) end
  ext(source,'SBP_MS2_GRIP_SAVED','')
end
-- Removes the component tracks of this vehicle and pulls the source out of the folder.
function M.remove_routing(source,fx)
  local guid=r.GetTrackGUID(source)
  local list=M.routing_tracks(guid)
  for _,track in ipairs(list) do r.DeleteTrack(track) end
  if #list>0 then
    r.SetMediaTrackInfo_Value(source,'I_FOLDERDEPTH',0)
    r.SetMediaTrackInfo_Value(source,'B_MAINSEND',1)
  end
  if fx then M.restore_layers(source,fx) end
  ext(source,'SBP_MS2_SCHEME','')
  return #list
end

local function send(source,track,ch,mono)
  local s=r.CreateTrackSend(source,track)
  assert(s>=0,'Could not create stem send')
  r.SetTrackSendInfo_Value(source,0,s,'I_SRCCHAN',mono and (ch|1024) or ch)
  r.SetTrackSendInfo_Value(source,0,s,'I_DSTCHAN',0)
  r.SetTrackSendInfo_Value(source,0,s,'I_MIDIFLAGS',31)
  r.SetTrackSendInfo_Value(source,0,s,'I_SENDMODE',3)
  r.SetTrackSendInfo_Value(source,0,s,'D_VOL',1)
end

-- opts: scheme, exhaust ('systems'|'main'|'cylinders'), cylinders (1..16)
-- Call inside M.transaction on a source outside folders with no routing yet.
function M.build_routing(source,fx,opts)
  opts=opts or {}
  local scheme=opts.scheme or 'spatial'
  local exhaust=opts.exhaust or 'systems'
  local cyls=math.max(1,math.min(M.es_cyl_max,math.floor(opts.cylinders or M.es_cyl_max)))
  local grip_scheme=scheme=='grip_print' or scheme=='grip_split'
  if grip_scheme and not M.engine_sim(source,fx) then error('GRIP routing requires the 64-channel EngineSim + GRIP prototype chain.') end
  local es=M.configure(source,fx)
  local es_dry=scheme=='print' or scheme=='split' or scheme=='dry'
  if grip_scheme then
    local id=ident(source,fx)
    local grip=M.find_fx(source,function(v) return v:lower():find('grip.vst3',1,true)~=nil end)
    if not grip or not id:find('SBP MotorSynth 2/sbp_MotorSynth_v2.jsfx',1,true) then error('This scheme requires the MotorSynth 2 vehicle and GRIP on the same track.') end
    local l,h=r.TrackFX_GetPinMappings(source,grip,1,0);local l2,h2=r.TrackFX_GetPinMappings(source,grip,1,1)
    if (h & (1<<30))==0 or (h2 & (1<<31))==0 then error('GRIP outputs must be connected to channels 63/64. Use Connect GRIP first.') end
  end
  if es_dry and not es then
    error('This scheme needs the EngineSim chain on the vehicle track.\nRun "Add EngineSim chain" first.')
  end
  local guid=r.GetTrackGUID(source)
  -- Flat plan: level 0 = top folder, 1 = its children, 2/3 = nested folders.
  local plan={}
  local function item(t) plan[#plan+1]=t return t end
  if scheme~='dry' then
    for i,name in ipairs(M.stems) do item{name=name,role='stem_'..i,level=1,ch=i*2} end
  end
  if grip_scheme then item{name='GRIP — Dry stereo',role='grip_dry',level=1,ch=62,mute=(scheme=='grip_print')} end
  if es_dry then
    item{name='EngineSim — Dry stems',role='folder_dry',level=1,folder=true,mute=(scheme=='print')}
    for _,s in ipairs(M.es_stems) do
      local exhaust_stem=(s.key=='main' or s.key=='exa' or s.key=='exb')
      local on=not exhaust_stem or (exhaust=='main' and s.key=='main') or (exhaust=='systems' and s.key~='main')
      item{name=s.name,role='es_'..s.key,level=2,ch=s.ch,mute=not on}
    end
    item{name='EngineSim — Cylinders',role='folder_cyl',level=2,folder=true,mute=(exhaust~='cylinders')}
    for c=1,cyls do
      item{name=('EngineSim Cyl %d'):format(c),role='es_cyl_'..c,level=3,ch=M.es_cyl_first+c-1,mono=true}
    end
  end
  if scheme=='grip_split' then
    if ext(source,'SBP_MS2_GRIP_SAVED')=='' then ext(source,'SBP_MS2_GRIP_SAVED',tostring(r.TrackFX_GetParam(source,fx,227))) end
    r.TrackFX_SetParam(source,fx,227,0)
  end
  if scheme=='split' then
    if ext(source,'SBP_MS2_ES_SAVED')=='' then
      ext(source,'SBP_MS2_ES_SAVED',('%.6f,%.6f'):format(r.TrackFX_GetParam(source,fx,M.P_SIM_ENGINE),r.TrackFX_GetParam(source,fx,M.P_SIM_EXHAUST)))
    end
    r.TrackFX_SetParam(source,fx,M.P_SIM_ENGINE,0)
    r.TrackFX_SetParam(source,fx,M.P_SIM_EXHAUST,0)
  end

  local index=math.floor(r.GetMediaTrackInfo_Value(source,'IP_TRACKNUMBER'))-1
  r.InsertTrackAtIndex(index,true)
  local folder=r.GetTrack(0,index)
  r.GetSetMediaTrackInfo_String(folder,'P_NAME',scheme=='dry' and 'MotorSynth 2 — EngineSim' or 'MotorSynth 2 — Components',true)
  ext(folder,'SBP_MS2_SOURCE',guid);ext(folder,'SBP_MS2_ROLE','folder')
  r.SetMediaTrackInfo_Value(folder,'I_FOLDERDEPTH',1)
  r.SetMediaTrackInfo_Value(source,'B_MAINSEND',0)
  -- Source sits at index+1 inside the folder at level 1.
  local levels={1}
  for _,p in ipairs(plan) do levels[#levels+1]=p.level end
  local function depth(k) -- k: 1 = source, k>1 = plan[k-1]
    local here=levels[k]
    local entry=plan[k-1]
    if entry and entry.folder then return 1 end
    local nxt=levels[k+1] or 0
    return nxt-here
  end
  r.SetMediaTrackInfo_Value(source,'I_FOLDERDEPTH',depth(1))
  for k,p in ipairs(plan) do
    local at=index+1+k
    r.InsertTrackAtIndex(at,true)
    local track=r.GetTrack(0,at)
    r.GetSetMediaTrackInfo_String(track,'P_NAME',p.name,true)
    ext(track,'SBP_MS2_SOURCE',guid);ext(track,'SBP_MS2_ROLE',p.role)
    r.SetMediaTrackInfo_Value(track,'I_NCHAN',2)
    r.SetMediaTrackInfo_Value(track,'I_FOLDERDEPTH',depth(k+1))
    if p.mute then r.SetMediaTrackInfo_Value(track,'B_MUTE',1) end
    if p.ch then send(source,track,p.ch,p.mono) end
  end
  ext(source,'SBP_MS2_SCHEME',scheme..':'..exhaust..':'..cyls)
  return #plan
end
return M
