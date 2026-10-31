-- Keep the native projected gain while removing numerically collinear samples.
local M={}
function M.compact(points)
  local out={}
  for _,point in ipairs(points) do
    local count=#out
    if count>=2 then
      local a,b=out[count-1],out[count]
      local expected=a.linear+(point.linear-a.linear)*(b.time-a.time)/(point.time-a.time)
      if math.abs(expected-b.linear)<=1e-12*math.max(1,math.abs(expected),math.abs(b.linear)) then out[count]=nil end
    end
    out[#out+1]=point
  end
  return out
end
return M
