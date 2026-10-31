local platform = dofile(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') .. 'platform.lua')
-- Own cache/control files live beside a saved RPP. REAPER peak/browser caches
-- remain owned by their respective engines.
local M={}
function M.directory(r)
  local filename
  if r.EnumProjects then local _,path=r.EnumProjects(-1,'');filename=path end
  local parent=filename and filename:match('^(.*)[/\\][^/\\]+$')
  if parent and parent~='' and r.RecursiveCreateDirectory then
    local folder=parent..'/SBP_LoudnessCache'
    r.RecursiveCreateDirectory(folder,0)
    local probe=io.open(folder..'/.write-check','wb')
    if probe then probe:close();os.remove(folder..'/.write-check');return folder,true end
  end
  return assert(platform.temp(),'Temporary directory unavailable'),false
end
return M
