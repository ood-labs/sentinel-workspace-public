--!strict
-- Klang_Desk Module panel: clicks arrive as `panel` Event records, run through the
-- rig_commands seam, and lit/state feedback goes back on `desk_feedback`.
-- Panel records: event_type 1 press, 2 release; payload {control_index, value, 0}.
-- Feedback records: 10 lit, 11 value, 12 color, 13 state; payload {control_index, value}.
return function(host,get)
local Layout=require("@show/desk_layout")
local PRESS,RELEASE=1,2
local LIT,STATE=10,13
local LOADED,ACTIVE=1,2
local M={desk="",sent={},labels={},refresh=0,held={}}
local index={}
for i,c in pairs(Layout) do index[c.id]=i end
M.index=index
local function run(...: string): (boolean,any)
    return get("rig_commands").execute(get("static_rig"),{"desk",...})
end
-- The desk pipeline sits beside the Surface: <show>_Surface -> <show>_Desk.
function M.bind(root: string)
    local surface=string.match(root,"/sentinel/pipelines/([^/]+)/state") or "stagerig_klangrig_Surface"
    M.desk=string.gsub(surface,"_Surface$","_Desk")
end
function M.handle(records: {any})
    for _,r in ipairs(records) do
        local i=r.payload and r.payload[1]
        local c=i and Layout[math.floor(i+.5)]
        if c and c.action then
            local down=r.event_type==PRESS
            if c.action[1]=="hold" then
                if down or r.event_type==RELEASE then
                    M.held[c.id]=down or nil
                    run("momentary",c.action[2],if down then "1" else "0")
                end
            elseif down then
                local ok,err=run(table.unpack(c.action))
                M.error=if ok then nil else tostring(err)
            end
        end
    end
end
-- Desired per-control feedback, from the same state the Push shows.
function M.desired(): {[number]: {[number]: number}}
    local rig=get("static_rig");local fx=get("side_fx");local t=host.tempo.status()
    local want={}
    local function set(id,kind,value) local i=index[id];if i then want[i]=want[i] or {};want[i][kind]=value end end
    for _,c in pairs(Layout) do
        local a=c.action
        if a and a[1]=="preset" then
            set(c.id,STATE,if rig.active_names and rig.active_names[a[3]]==a[3].." "..a[4] then ACTIVE else LOADED)
        end
    end
    set("play",STATE,if t.running then ACTIVE else LOADED)
    set("tap",LIT,if t.running and t.beat_phase<.15 then 1 else 0)
    set("blackout",STATE,if fx.blackout then ACTIVE else LOADED)
    set("strobe",STATE,if fx.strobe then ACTIVE else LOADED)
    return want
end
function M.labels_now(): {[string]: string}
    local t=host.tempo.status();local rig=get("static_rig")
    return {bpm=string.format("%.1f BPM",t.bpm),
        beat=string.format("BAR %d BEAT %d",math.floor(t.bar)+1,math.floor(t.beat%t.beats_per_bar)+1),
        status=string.upper(string.sub(if M.error then "ERROR: "..M.error else (rig.message or ""),1,40)),
        play=if t.running then "PAUSE" else "PLAY"}
end
-- Emit only changes; resend everything every 2 s so a reloaded Module relights.
function M.feedback(out: any,dt: number)
    M.refresh+=dt
    local full=M.refresh>2
    if full then M.refresh=0;M.labels={} end
    for i,kinds in pairs(M.desired()) do
        M.sent[i]=M.sent[i] or {}
        for kind,value in pairs(kinds) do
            if full or M.sent[i][kind]~=value then
                out:emit({event_type=kind,payload={i,value}})
                M.sent[i][kind]=value
            end
        end
    end
    if host.panel then
        for id,text in pairs(M.labels_now()) do
            if M.labels[id]~=text and host.panel.label(M.desk,id,text) then M.labels[id]=text end
        end
    end
end
function M.service(node: any,dt: number)
    local input=node.inputs.panel
    if input then M.handle(input:read_events()) end
    local out=node.outputs.desk_feedback
    if out then M.feedback(out,dt) end
end
function M.stop()
    for id in pairs(M.held) do
        local c=Layout[index[id]];if c then run("momentary",c.action[2],"0") end
    end
    M.held={};M.sent={};M.labels={}
end
return M
end
