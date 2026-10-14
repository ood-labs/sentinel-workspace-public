--!strict
-- Global transport keys on every page, sharing the SEQUENCE page's tempo adapter (and its tap history):
-- Play (bottom left) toggles start/pause and stays lit while running; Shift+Play stops and returns to beat 0; Tap Tempo (top left) always taps
-- and pulses on the beat; Metronome, to its right, is SYNC (resync to beat 0).
-- Play is in the Push 2 profile; Tap Tempo and Metronome are not, so they are read as raw CCs.
return function(host,get)
local C=get("conventions")
local tempo=host.tempo
local PLAY,TAP,SYNC=85,3,9
local DIM,BRIGHT=16,127
local M={held={},shift=false,last=nil,refresh=0}
local function run(fn)
    local ok,err=pcall(fn)
    if not ok and host.log then host.log.warn("transport key: "..tostring(err)) end
    return ok,err
end
-- Each action also returns (ok, err) so rig_commands and the DESK can report failures.
function M.play()
    return run(function() assert(if tempo.status().running then tempo.pause() else tempo.start(),"Transport write failed") end)
end
function M.stop_transport() return run(function() assert(tempo.stop(),"Stop failed") end) end
function M.tap() return run(function() assert(tempo.tap(),"Tap failed") end) end
function M.sync() return run(function() assert(tempo.resync(0),"Sync failed") end) end
function M.bind()
    host.midi.on("push2.transport.play","momentary",function(ev)
        M.held.play=ev.pressed==true or nil
        if ev.pressed then if M.shift then M.stop_transport() else M.play() end end
    end)
    -- The framework also handles Shift; every matching handler receives the event.
    host.midi.on("push2.button.shift","momentary",function(ev) M.shift=ev.pressed==true end)
    host.midi.on("*Ableton Push 2*","cc",function(ev)
        if ev.channel~=1 then return end
        if ev.data1==TAP then
            M.held.tap=ev.pressed==true or nil
            if ev.pressed then M.tap() end
        elseif ev.data1==SYNC then
            M.held.sync=ev.pressed==true or nil
            if ev.pressed then M.sync() end
        end
    end)
end
function M.tick(dt)
    M.refresh+=dt or 0
    local st=tempo.status()
    local play=if M.held.play or st.running then C.LED.active else C.LED.dim
    local tap=if M.held.tap or (st.running and st.beat_phase<.15) then BRIGHT else DIM
    local sync=if M.held.sync then BRIGHT else DIM
    local signature=play..":"..tap..":"..sync
    if M.last==signature and M.refresh<1 then return end
    local result=host.midi.send_many(C.MIDI.out_port,{
        {kind="cc",channel=1,data1=PLAY,data2=play},
        {kind="cc",channel=1,data1=TAP,data2=tap},
        {kind="cc",channel=1,data1=SYNC,data2=sync}})
    if typeof(result)=="table" and (result.failed_count or 0)>0 then M.last=nil;return end
    M.last=signature;M.refresh=0
end
function M.stop() M.held={};M.shift=false;M.last=nil end
return M
end
