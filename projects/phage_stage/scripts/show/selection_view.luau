--!strict
-- Push 2 RIG page strip: the rig in plan (x across, z down the page), one mark per live fixture,
-- selected fixtures in the accent. Kinds read by shape: movers squares, strobes bars, pixel bars dots.
return function(host,get)
local C=get("conventions")
local M=get("static_rig")
local V={offset={key="rig_view_offset",default=0,min=0,max=0,persist="snapshot"}}
local ACCENT,IDLE,AXIS,TEXT=0xFFCF76,0x3B6774,0x24384D,0xA0ACBC
function V.browse() end
function V.render(ctx)
    C.text(8,ctx.cy+4,"PHAGE / "..string.upper(M.preset_kind).." / "..#M.status.selection.." SELECTED",12,0x67D4C0)
    -- Plan +-19 m across 300 px, +-17 m down 64 px (the Push strip is wide and short).
    local cx,cz,sx,sz=480,ctx.cy+46,300/38,56/34
    for _,f in ipairs(M.fixtures) do if M.active_fixture(f) then
        local x,y=cx+f.x*sx,cz+f.z*sz
        local col=if M.is_selected(f.id) then ACCENT elseif f.kind==3 then AXIS else IDLE
        if f.kind==0 then host.display.rect(x-2,y-2,4,4,col,true)
        elseif f.kind==1 then host.display.rect(x-3,y-1,6,2,col,true)
        elseif f.kind==2 then host.display.rect(x-1,y-1,2,2,col,true)
        else host.display.rect(x-3,y-3,6,6,col,false) end
    end end
    C.text(8,ctx.cy+77,M.message,9,TEXT)
end
return V
end
