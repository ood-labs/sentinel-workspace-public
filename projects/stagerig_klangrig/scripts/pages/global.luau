--!strict
return function(host,get)
local C=get("conventions")
local M=get("static_rig")
local Side=get("side_fx")
local Camera=get("camera_orbit")
local Transport=get("transport_keys")
local root=""

local page={name="GLOBAL",params={},top={},top_labels={"BLACKOUT","CAM 1s","CAM IN","CAM OUT","CAM HOME","CAM SAVE","CAM RESET","-"},records=Camera.records}
local specs={{"master","MASTER",0,1,1},{"exposure","EXPOSURE",0,5,1},{"bloom","BLOOM",0,1,.12},
    {"sensor_white_start","WHITE START",.1,20,2},{"sensor_white_response","WHITE RESP",0,2,.16},
    {"streak_strength","STREAK",0,1,.005},{"streak_length","STREAK LEN",0,.5,.08},{"haze","HAZE",0,1,.03}}
page.blackout=false
for _,s in ipairs(specs) do table.insert(page.params,{key="global_"..s[1],label=s[2],min=s[3],max=s[4],default=s[5],persist="bank",fmt="%.3f"}) end
page.top[2]={kind="trigger",on_press=Camera.step_time,is_lit=function() return Camera.time_label()~="CUT" end}
page.top[3]={kind="trigger",on_press=function() Camera.step("in") end}
page.top[4]={kind="trigger",on_press=function() Camera.step("out") end}
page.top[5]={kind="trigger",on_press=Camera.go_home,is_lit=function() return Camera.moving() end}
page.top[6]={kind="trigger",on_press=Camera.save,is_lit=function() return Camera.is_saved(Camera.col,Camera.row) end}
page.top[7]={kind="trigger",on_press=Camera.reset}
page.top[1]={kind="momentary",on_press=function() page.blackout=true end,on_release=function() page.blackout=false end,is_lit=function() return page.blackout end}
page.render=function(ctx)
    C.text(12,ctx.cy+10,"KLANGRIG / GLOBAL",20,0x67D4C0)
    C.text(12,ctx.cy+43,if page.blackout or Side.blackout then "BLACKOUT HELD" else "SIDE: BOTTOM BLACKOUT / ABOVE STROBE / HOLD",12,0xE3EAF1)
    C.text(12,ctx.cy+66,M.message,10,0xA0ACBC)
    C.text(400,ctx.cy+10,"CAMERA: ARROWS JUMP ROUND THE RIG",12,0x77B9FF)
    C.text(400,ctx.cy+30,"TOP 2 MOVE "..Camera.time_label().." / 3-4 ZOOM / 5 HOME / 6 SAVE (OR CLIP) / 7 RESET",10,0xE3EAF1)
end
page.on_leave=function() page.blackout=false end
page.on_bind=function(boundRoot) root=boundRoot;Side.bind();Camera.bind();Transport.bind() end
page.on_frame=function(dt)
    Side.tick(dt)
    Camera.frame(dt)
    Transport.tick(dt)
    page.top_labels[2]="CAM "..Camera.time_label()
    -- Keep serialized records aligned with live native edits and look recalls.
    for _,r in ipairs(page.params) do
        local value=tonumber(host.state.get(root.."/"..r.key))
        if value then r.value=value end
    end
end
page.on_stop=function() page.on_leave();Side.stop();Transport.stop() end
return page
end
