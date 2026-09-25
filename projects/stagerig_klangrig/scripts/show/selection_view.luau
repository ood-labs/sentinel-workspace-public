--!strict
return function(host,get)
local C=get("conventions")
local M=get("static_rig")
local V={offset={key="rig_view_offset",default=0,min=0,max=0,persist="snapshot"}}
function V.browse() end
function V.render(ctx)
    C.text(8,ctx.cy+4,"KLANGRIG / "..string.upper(M.preset_kind).." / "..#M.status.selection.." SELECTED",12,0x67D4C0)
    for _,f in ipairs(M.fixtures) do if f.mover and M.active_fixture(f) then
        local x=if f.wing==0 then 30+f.local_index*8.8 else 75+(f.bay-1)*280+f.local_index*11
        local y=ctx.cy+(if f.wing==0 then 43 else if f.upper then (if f.left then 24 else 61) else (if f.left then 32 else 69))
        host.display.rect(x,y,if f.wing==0 then 5 else 7,4,if M.is_selected(f.id) then 0xFFCF76 else 0x3B6774,true)
    end end
    C.text(8,ctx.cy+77,M.message,9,0xA0ACBC)
end
return V
end
