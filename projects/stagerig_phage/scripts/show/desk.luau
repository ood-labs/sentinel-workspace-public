--!strict
-- DESK view of the Surface control window: play the show without a Push 2.
-- Every action is a rig_commands argument list, so the Push, the desk and automation share one path.
return function(host,get)
local Titles=require("@show/preset_titles")
local BANKS={{kind="complete",label="FULL LOOKS"},{kind="static",label="STATIC"},
    {kind="effects",label="EFFECTS"},{kind="color",label="COLOR"}}
local CAMERA={{"left","<"},{"right",">"},{"up","UP"},{"down","DOWN"},{"in","IN"},{"out","OUT"},{"home","HOME"}}
local M={error=""}
function M.run(...: string): boolean
    local ok,err=get("rig_commands").execute(get("static_rig"),{"desk",...})
    M.error=if ok then "" else tostring(err)
    return ok
end
function M.label(kind: string,slot: number): string
    local rig=get("static_rig")
    local title=(Titles[kind] or {})[slot] or ""
    local lit=rig.is_lit(kind,slot)
    local text=string.format("%02d %s",slot,title)
    return if lit then "> "..text.." <" else text
end
function M.draw(ui: any)
    local tempo=host.tempo.status()
    local _,tap=ui.button("desk_tap","TAP")
    if tap then M.run("tempo","tap") end
    ui.same_line()
    local _,play=ui.button("desk_play",if tempo.running then "PAUSE" else "PLAY")
    if play then M.run("tempo","play") end
    ui.same_line()
    local _,stop=ui.button("desk_stop","STOP")
    if stop then M.run("tempo","stop") end
    ui.same_line()
    local _,sync=ui.button("desk_sync","SYNC")
    if sync then M.run("tempo","sync") end
    ui.same_line()
    ui.text("desk_beat",string.format("%s  bar %d  beat %d",if tempo.beat_phase<.15 and tempo.running then "(*)" else "( )",
        math.floor(tempo.bar)+1,math.floor(tempo.beat%tempo.beats_per_bar)+1))
    local changedBpm,bpm=ui.slider_float("desk_bpm","BPM",tempo.bpm,60,200)
    if changedBpm and bpm then M.run("tempo","bpm",string.format("%.2f",bpm)) end
    for _,bank in ipairs(BANKS) do
        ui.separator()
        ui.text("desk_head_"..bank.kind,bank.label)
        for slot=1,16 do
            local _,pressed=ui.button("desk_"..bank.kind.."_"..slot,M.label(bank.kind,slot))
            if pressed then M.run("preset","recall",bank.kind,tostring(slot)) end
            if slot%8~=0 then ui.same_line() end
        end
    end
    ui.separator()
    local fx=get("side_fx")
    local changedBlack,black=ui.checkbox("desk_blackout","BLACKOUT",fx.blackout)
    if changedBlack then M.run("momentary","blackout",if black then "1" else "0") end
    ui.same_line()
    local changedStrobe,strobe=ui.checkbox("desk_strobe","STROBE",fx.strobe)
    if changedStrobe then M.run("momentary","strobe",if strobe then "1" else "0") end
    ui.same_line()
    ui.text("desk_camera_label","  CAMERA")
    for _,cam in ipairs(CAMERA) do
        ui.same_line()
        local _,pressed=ui.button("desk_cam_"..cam[1],cam[2])
        if pressed then M.run("camera",cam[1]) end
    end
    ui.text("desk_status",if M.error~="" then "ERROR: "..M.error else get("static_rig").message)
end
return M
end
