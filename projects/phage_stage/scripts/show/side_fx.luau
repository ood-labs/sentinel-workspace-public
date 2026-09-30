--!strict
-- Global held overrides, independent of the currently visible page or preset.
return function(host,get)
local C=get("conventions")
local M={blackout=false,strobe=false,last=nil,refresh=0}
function M.set(index,pressed)
    if index==0 then M.blackout=pressed==true elseif index==1 then M.strobe=pressed==true end
end
function M.bind()
    for i=0,7 do host.midi.on("push2.button.side."..i,"momentary",function(ev) M.set(i,ev.pressed) end) end
end
function M.tick(dt)
    M.refresh+=dt or 0
    local signature=tostring(M.blackout)..tostring(M.strobe)
    if M.last==signature and M.refresh<1 then return end
    local messages={}
    for i=0,7 do table.insert(messages,{kind="cc",channel=1,data1=36+i,
        data2=if i==0 then (if M.blackout then 127 else 5) elseif i==1 then (if M.strobe then 127 else 16) else 0}) end
    local result=host.midi.send_many(C.MIDI.out_port,messages)
    if typeof(result)=="table" and (result.failed_count or 0)>0 then M.last=nil;return end
    M.last=signature;M.refresh=0
end
function M.stop()
    M.blackout=false;M.strobe=false;M.last=nil
    host.sentinel.set("/sentinel/pipelines/Phage_Show/parameters/global_strobe",false)
    host.sentinel.set("/sentinel/pipelines/Phage_Show/parameters/blackout",false)
    local rig=get("static_rig");local global=get("page:global")
    local function value(r) return tonumber(host.state.get(rig.root.."/"..r.key)) or r.value or r.default end
    host.sentinel.set("/sentinel/pipelines/Phage_Program/parameters/master",value(global.params[1])*value(rig.master))
end
return M
end
