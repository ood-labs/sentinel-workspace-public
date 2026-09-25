--!strict
local M={}
for i=0,288 do
    local wing=if i<64 or i>=256 then 0 else 1+math.floor((i-64)/16)
    local localIndex=if i>=256 then i-192 else if wing==0 then i else (i-64)%16
    M[i+1]={id=tostring(i),record=tostring(i),slot=i,mover=i<288,wing=wing,row=wing+1,
        local_index=localIndex,bay=if wing>0 then math.floor((wing-1)/4)+1 else 0,
        upper=wing>0 and (wing-1)%4<2,left=wing>0 and (wing-1)%2==0,
        name=if i==288 then "LED SYSTEM" else if wing==0 then "SPINE "..(localIndex+1) else "W"..wing.." / "..(localIndex+1)}
end
return M
