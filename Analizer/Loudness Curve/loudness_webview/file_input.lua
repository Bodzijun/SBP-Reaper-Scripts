-- Explicit user-triggered file selection and macOS clipboard access.
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local platform=dofile(directory..'platform.lua')
local M={}
local function checked(path,kind)
  local normalized,err=platform.path(path);assert(normalized,err)
  if kind=='report' then assert(normalized:lower():match('%.html?$'),'Choose a REAPER HTML render report') end
  if kind=='stem' then assert(normalized:lower():match('%.wave?$'),'Choose a WAV stem file') end
  return normalized
end
function M.browse(r,value)
  local kind,current=value:match('^(%a+)~(.*)$')
  assert(kind=='report' or kind=='audio' or kind=='stem','Invalid file selection request')
  local initial=platform.path(current) or ''
  local title=kind=='report' and 'Choose REAPER render statistics' or (kind=='stem' and 'Choose original WAV stem' or 'Choose matching original audio')
  local ok,path
  if r.GetUserFileName then
    local filter=kind=='report' and 'REAPER reports|*.html;*.htm|All files|*.*' or (kind=='stem' and 'WAV audio|*.wav;*.wave|All files|*.*' or '')
    ok,path=r.GetUserFileName(1,title,initial,filter)
  else
    assert(r.GetUserFileNameForRead,'Native file selection is unavailable in this REAPER version')
    ok,path=r.GetUserFileNameForRead(initial,title,'')
  end
  if not ok then return {cancelled=true} end
  return {path=checked(path,kind)}
end
function M.clipboard(r,kind)
  assert(kind=='report' or kind=='audio' or kind=='stem','Invalid clipboard request')
  local osname=r.GetOS and r.GetOS() or ''
  if not (osname:match('OSX') or osname:match('macOS')) then return {available=false} end
  assert(r.ExecProcess,'System clipboard access is unavailable; use Browse')
  local output=r.ExecProcess('/usr/bin/pbpaste',2000)
  local code,text
  if type(output)=='string' then code,text=output:match('^([%-]?%d+)\r?\n(.*)$') end
  assert(tonumber(code)==0,'Could not read macOS clipboard; use Browse')
  assert(text and text:match('%S'),'Clipboard is empty; copy a file pathname or use Browse')
  return {available=true,path=checked(text,kind)}
end
return M
