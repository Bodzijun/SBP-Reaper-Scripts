-- @description SBP MotorSynth 2 - Control Center
-- @noindex
-- @version 2.0.0pre2
-- @author SBP
local r=reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox('MotorSynth Control Center requires the ReaImGui extension.','MotorSynth 2',0)
  return
end
local path=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local M=dofile(path..'MotorSynth_Lib.lua')
local recorder=dofile(path..'MotorSynth_Record.lua')
local ctx=r.ImGui_CreateContext('MotorSynth 2 Control Center')
local opened,recording,stoppedAt=true,nil,nil
local function state(key,default) local v=r.GetExtState('SBP_MotorSynth2',key) return v~='' and v or default end
local function index_of(list,key) for i,v in ipairs(list) do if v.key==key then return i-1 end end return 0 end
local schemeIndex=index_of(M.schemes,state('routing_scheme','spatial'))
local exhaustIndex=index_of(M.exhaust_modes,state('routing_exhaust','systems'))
local cylinders=math.tointeger(tonumber(state('routing_cylinders','16'))) or 16
local hints={grip_print='Spatial stems plus a muted stereo GRIP track for printing.',grip_split='Spatial stems plus a separate dry GRIP track. GRIP is removed from the spatial road stem.',spatial='MotorSynth stems 1-32 with EngineSim mixed inside.',print='Adds a muted folder with dry EngineSim stems for printing or parallel processing.',
  split='EngineSim layers inside MotorSynth are set to 0; dry stems play from their own folder. Remove routing restores the layers.',dry='Only EngineSim dry stems are routed; MotorSynth outputs are not used.'}
local message='Select a MotorSynth track or one of its component tracks.'
local language=r.GetExtState('SBP_MotorSynth2','language')
if language~='uk' and language~='zh' then language='en' end
local words={
  ['PROJECT SETUP']={'НАЛАШТУВАННЯ ПРОЄКТУ','项目设置'},
  ['Vehicle: ']={'Автомобіль: ','车辆：'},
  ['No MotorSynth vehicle selected']={'Автомобіль MotorSynth не вибрано','未选择 MotorSynth 车辆'},
  ['Select the vehicle or one of its component tracks.']={'Оберіть автомобіль або одну з доріжок його компонентів.','选择车辆或其一条分轨。'},
  ['Select a MotorSynth track or one of its component tracks.']={'Оберіть доріжку MotorSynth або одну з доріжок її компонентів.','选择 MotorSynth 轨道或其一条分轨。'},
  ['Create / open vehicle']={'Створити / відкрити автомобіль','创建 / 打开车辆'},
  ['Prepare automation']={'Підготувати автоматизацію','准备自动化'},
  ['Build component routing']={'Створити маршрутизацію','创建分轨路由'},
  ['STEREO RECORDING']={'ЗАПИС СТЕРЕО','立体声录音'},
  ['Records the vehicle output, moves the new take to MotorSynth REC, then mutes the vehicle.']={'Записує вихід автомобіля, переносить запис на MotorSynth REC і вимикає звук автомобіля.','录制车辆输出，将新录音移至 MotorSynth REC，然后静音车辆。'},
  ['REAPER also records any other armed tracks.']={'REAPER також запише всі інші озброєні доріжки.','REAPER 也会录制其他已启用录音的轨道。'},
  ['STOP RECORDING']={'ЗУПИНИТИ ЗАПИС','停止录音'},
  ['REC  |  Record vehicle']={'REC  |  Записати автомобіль','REC  |  录制车辆'},
  ['Recording... Press STOP or stop in REAPER.']={'Запис... Натисніть STOP або зупиніть у REAPER.','录音中……按 STOP 或在 REAPER 中停止。'},
  ['Return to the recorded project to stop.']={'Поверніться до проєкту запису, щоб зупинити його.','返回录音项目以停止。'},
  ['Return to the recorded project to finish moving the take.']={'Поверніться до проєкту запису, щоб завершити перенесення.','返回录音项目以完成录音移动。'},
  ['REAPER is already recording.']={'REAPER вже записує.','REAPER 已在录音。'},
  ['REAPER did not start recording.']={'REAPER не почав запис.','REAPER 未开始录音。'},
  ['No new recording was kept; the source was not muted.']={'Новий запис не збережено; джерело не вимкнено.','未保留新录音；声源未静音。'},
  ['The source track no longer exists.']={'Доріжка джерела більше не існує.','源轨道已不存在。'},
  ['ENGINESIM']={'ENGINESIM','ENGINESIM'},
  ['EngineSim chain: active (dry stems on 33-62)']={'Ланцюг EngineSim: активний (сухі стеми на 33-62)','EngineSim 链：已启用（干声分轨 33-62）'},
  ['EngineSim chain: not on this track']={'Ланцюг EngineSim: на доріжці відсутній','EngineSim 链：此轨道上没有'},
  ['Spatial stems + dry GRIP (muted)']={'Просторові стеми + сухий GRIP (вимкнено)','空间分轨 + GRIP 干声（静音）'},
  ['Spatial stems + separate dry GRIP']={'Просторові стеми + окремий сухий GRIP','空间分轨 + 独立 GRIP 干声'},
  ['Spatial stems plus a muted stereo GRIP track for printing.']={'Просторові стеми та вимкнена стереодоріжка GRIP для запису.','空间分轨与静音 GRIP 立体声轨道。'},
  ['Spatial stems plus a separate dry GRIP track. GRIP is removed from the spatial road stem.']={'Просторові стеми та окрема суха доріжка GRIP. GRIP прибирається з просторового стему дороги.','空间分轨与独立 GRIP 干声轨道；空间道路分轨中移除 GRIP。'},
  ['Create vehicle with EngineSim and GRIP']={'Створити автомобіль з EngineSim і GRIP','创建带 EngineSim 和 GRIP 的车辆'},
  ['Create vehicle with EngineSim']={'Створити автомобіль з EngineSim','创建带 EngineSim 的车辆'},
  ['Add / repair EngineSim chain']={'Додати / відновити ланцюг EngineSim','添加 / 修复 EngineSim 链'},
  ['STEM ROUTING']={'МАРШРУТИЗАЦІЯ СТЕМІВ','分轨路由'},
  ['Scheme']={'Схема','方案'},
  ['Exhaust']={'Вихлоп','排气'},
  ['Cylinders']={'Циліндри','气缸'},
  ['Spatial stems (original)']={'Просторові стеми (оригінальна)','空间分轨（原始）'},
  ['Spatial stems + dry EngineSim (muted, for print)']={'Просторові + сухі EngineSim (заглушені, для друку)','空间分轨 + EngineSim 干声（静音，用于打印）'},
  ['Split: MotorSynth stems + dry EngineSim']={'Розділено: стеми MotorSynth + сухі EngineSim','拆分：MotorSynth 分轨 + EngineSim 干声'},
  ['Dry EngineSim stems only']={'Лише сухі стеми EngineSim','仅 EngineSim 干声分轨'},
  ['Exhaust A / B']={'Вихлоп A / B','排气 A / B'},
  ['Exhaust Main']={'Вихлоп Main','排气 Main'},
  ['Per-cylinder']={'Поциліндрово','按气缸'},
  ['Build / rebuild routing']={'Створити / перебудувати маршрутизацію','创建 / 重建路由'},
  ['Remove routing']={'Видалити маршрутизацію','删除路由'},
  ['Current scheme: ']={'Поточна схема: ','当前方案：'},
  ['MotorSynth stems 1-32 with EngineSim mixed inside.']={'Стеми MotorSynth 1-32, EngineSim змішано всередині.','MotorSynth 分轨 1-32，内部混入 EngineSim。'},
  ['Adds a muted folder with dry EngineSim stems for printing or parallel processing.']={'Додає заглушену теку сухих стемів EngineSim для друку або паралельної обробки.','添加静音的 EngineSim 干声文件夹，用于打印或并行处理。'},
  ['EngineSim layers inside MotorSynth are set to 0; dry stems play from their own folder. Remove routing restores the layers.']={'Шари EngineSim у MotorSynth обнуляються; сухі стеми звучать з окремої теки. Видалення маршрутизації відновлює шари.','MotorSynth 内的 EngineSim 层设为 0；干声分轨从独立文件夹播放。删除路由会恢复这些层。'},
  ['Only EngineSim dry stems are routed; MotorSynth outputs are not used.']={'Маршрутизуються лише сухі стеми EngineSim; виходи MotorSynth не використовуються.','仅路由 EngineSim 干声分轨；不使用 MotorSynth 输出。'},
}
local function tr(text)
  local entry=words[text]
  if entry and language~='en' then return entry[language=='uk' and 1 or 2] end
  local count=text:match('^Moved (%d+) recording%(s%) to MotorSynth REC%. Source muted%.$')
  if count and language=='uk' then return 'Перенесено записів: '..count..'. Джерело вимкнено.' end
  if count and language=='zh' then return '已移动 '..count..' 个录音至 MotorSynth REC，声源已静音。' end
  return text
end

local function items(list) local t={} for _,v in ipairs(list) do t[#t+1]=tr(v.name) end return table.concat(t,'\0')..'\0' end
local function run(file,request)
  local ok,err=xpcall(function() SBP_MS2_ROUTING=request;dofile(path..file) end,debug.traceback)
  SBP_MS2_ROUTING=nil
  if not ok then r.ShowMessageBox(tostring(err),'MotorSynth 2',0) end
end
local function colors()
  local list={
    {r.ImGui_Col_WindowBg(),0x192129FF}, {r.ImGui_Col_Text(),0xDAE3E8FF},
    {r.ImGui_Col_TextDisabled(),0x8B9BA8FF}, {r.ImGui_Col_Button(),0x202D37FF},
    {r.ImGui_Col_ButtonHovered(),0x34424CFF}, {r.ImGui_Col_ButtonActive(),0x534839FF},
    {r.ImGui_Col_Border(),0x35434DFF}, {r.ImGui_Col_TitleBg(),0x11171DFF},
    {r.ImGui_Col_TitleBgActive(),0x202B33FF}, {r.ImGui_Col_TitleBgCollapsed(),0x11171DFF},
  }
  for _,v in ipairs(list) do r.ImGui_PushStyleColor(ctx,v[1],v[2]) end
  return #list
end
local function watch()
  if not recording then return end
  if (r.GetPlayStateEx(recording.project) & 4)~=0 then stoppedAt=nil;return end
  if not stoppedAt then stoppedAt=r.time_precise();return end
  if r.time_precise()-stoppedAt<0.25 then return end
  if r.EnumProjects(-1,'')~=recording.project then
    message='Return to the recorded project to finish moving the take.';return
  end
  local _,result=recorder.finish(recording);message=result;recording=nil;stoppedAt=nil
end
local function loop()
  watch()
  if opened then
    local savedLanguage=r.GetExtState('SBP_MotorSynth2','language')
    if savedLanguage=='en' or savedLanguage=='uk' or savedLanguage=='zh' then language=savedLanguage end
    local style=colors()
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_WindowRounding(),10)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),6)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_WindowPadding(),14,12)
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_ItemSpacing(),8,7)
    r.ImGui_SetNextWindowSize(ctx,460,720,r.ImGui_Cond_FirstUseEver())
    local visible,stillOpen=r.ImGui_Begin(ctx,'MotorSynth 2 | Control Center',true,r.ImGui_WindowFlags_NoCollapse())
    opened=stillOpen
    if visible then
      r.ImGui_TextColored(ctx,0xEDBF85FF,'MOTORSYNTH 2')
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx,tr('PROJECT SETUP'))
      r.ImGui_SameLine(ctx)
      for _,choice in ipairs({{'en','EN'},{'uk','UA'},{'zh','ZH'}}) do
        if r.ImGui_SmallButton(ctx,choice[2]..'##language') then language=choice[1];r.SetExtState('SBP_MotorSynth2','language',language,true) end
        if choice[1]~='zh' then r.ImGui_SameLine(ctx) end
      end
      r.ImGui_Separator(ctx)
      local track,fx=M.source(true)
      local name=''
      if track then _,name=r.GetTrackName(track) end
      r.ImGui_TextWrapped(ctx,track and (tr('Vehicle: ')..name) or tr('No MotorSynth vehicle selected'))
      r.ImGui_TextDisabled(ctx,tr('Select the vehicle or one of its component tracks.'))
      r.ImGui_Spacing(ctx)
      if r.ImGui_Button(ctx,tr('Create / open vehicle'),-1,34) then
        if track then r.TrackFX_Show(track,fx,3) else run('sbp_MotorSynth2_Create_Vehicle.lua') end
      end
      if r.ImGui_Button(ctx,tr('Prepare automation'),-1,30) then run('sbp_MotorSynth2_Prepare_Controls.lua') end
      r.ImGui_Spacing(ctx);r.ImGui_Separator(ctx)
      r.ImGui_TextColored(ctx,0xEDBF85FF,tr('ENGINESIM'))
      local es=track and M.engine_sim(track,fx)
      r.ImGui_TextDisabled(ctx,tr(es and 'EngineSim chain: active (dry stems on 33-62)' or 'EngineSim chain: not on this track'))
      if r.ImGui_Button(ctx,tr(track and 'Add / repair EngineSim chain' or 'Create vehicle with EngineSim'),-1,30) then
        run(track and 'sbp_MotorSynth2_Add_EngineSim.lua' or 'sbp_MotorSynth2_Create_Vehicle_EngineSim.lua')
      end
      if r.ImGui_Button(ctx,tr('Create vehicle with EngineSim and GRIP'),-1,30) then run('sbp_MotorSynth2_Create_Vehicle_GRIP.lua') end
      r.ImGui_Spacing(ctx);r.ImGui_Separator(ctx)
      r.ImGui_TextColored(ctx,0xEDBF85FF,tr('STEM ROUTING'))
      r.ImGui_SetNextItemWidth(ctx,-90)
      local changed
      changed,schemeIndex=r.ImGui_Combo(ctx,tr('Scheme'),schemeIndex,items(M.schemes))
      if changed then r.SetExtState('SBP_MotorSynth2','routing_scheme',M.schemes[schemeIndex+1].key,true) end
      local scheme=M.schemes[schemeIndex+1].key
      if scheme=='print' or scheme=='split' or scheme=='dry' then
        r.ImGui_SetNextItemWidth(ctx,-90)
        changed,exhaustIndex=r.ImGui_Combo(ctx,tr('Exhaust'),exhaustIndex,items(M.exhaust_modes))
        if changed then r.SetExtState('SBP_MotorSynth2','routing_exhaust',M.exhaust_modes[exhaustIndex+1].key,true) end
        r.ImGui_SetNextItemWidth(ctx,-90)
        changed,cylinders=r.ImGui_SliderInt(ctx,tr('Cylinders'),cylinders,1,M.es_cyl_max)
        if changed then r.SetExtState('SBP_MotorSynth2','routing_cylinders',tostring(cylinders),true) end
      end
      r.ImGui_TextWrapped(ctx,tr(hints[scheme]))
      if track then
        local current=M.ext(track,'SBP_MS2_SCHEME')
        if current~='' then r.ImGui_TextDisabled(ctx,tr('Current scheme: ')..current) end
      end
      if r.ImGui_Button(ctx,tr('Build / rebuild routing'),-1,30) then
        run('sbp_MotorSynth2_Build_Routing.lua',{scheme=scheme,exhaust=M.exhaust_modes[exhaustIndex+1].key,cylinders=cylinders})
      end
      if r.ImGui_Button(ctx,tr('Remove routing'),-1,26) then run('sbp_MotorSynth2_Remove_Routing.lua') end
      r.ImGui_Spacing(ctx);r.ImGui_Separator(ctx)
      r.ImGui_TextColored(ctx,0xEDBF85FF,tr('STEREO RECORDING'))
      r.ImGui_TextWrapped(ctx,tr('Records the vehicle output, moves the new take to MotorSynth REC, then mutes the vehicle.'))
      r.ImGui_TextDisabled(ctx,tr('REAPER also records any other armed tracks.'))
      r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),recording and 0x623431FF or 0x743D37FF)
      r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),0x98534BFF)
      if r.ImGui_Button(ctx,tr(recording and 'STOP RECORDING' or 'REC  |  Record vehicle'),-1,36) then
        if recording then
          if r.EnumProjects(-1,'')==recording.project then r.OnStopButton() else message='Return to the recorded project to stop.' end
        else
          track=M.source()
          if track then recording,message=recorder.start(track) end
          if recording then message='Recording... Press STOP or stop in REAPER.' end
        end
      end
      r.ImGui_PopStyleColor(ctx,2)
      r.ImGui_Spacing(ctx);r.ImGui_TextWrapped(ctx,tr(message or ''))
      r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx,4)
    r.ImGui_PopStyleColor(ctx,style)
  end
  if opened or recording then r.defer(loop) end
end
r.defer(loop)
