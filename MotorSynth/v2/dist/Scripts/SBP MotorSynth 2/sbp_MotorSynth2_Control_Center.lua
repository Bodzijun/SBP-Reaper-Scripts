-- @description SBP MotorSynth 2 - Control Center
-- @noindex
-- @version 2.0.0pre1
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
}
local function tr(text)
  local entry=words[text]
  if entry and language~='en' then return entry[language=='uk' and 1 or 2] end
  local count=text:match('^Moved (%d+) recording%(s%) to MotorSynth REC%. Source muted%.$')
  if count and language=='uk' then return 'Перенесено записів: '..count..'. Джерело вимкнено.' end
  if count and language=='zh' then return '已移动 '..count..' 个录音至 MotorSynth REC，声源已静音。' end
  return text
end

local function run(file)
  local ok,err=xpcall(function() dofile(path..file) end,debug.traceback)
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
    r.ImGui_SetNextWindowSize(ctx,440,445,r.ImGui_Cond_FirstUseEver())
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
      if r.ImGui_Button(ctx,tr('Build component routing'),-1,30) then run('sbp_MotorSynth2_Build_Routing.lua') end
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
