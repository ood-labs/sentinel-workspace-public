--!strict
-- Native-host diagnostic. This is not the framework Runtime acceptance example.
local Session=require("@push2os/session")
local root="/ctrl/script/01_surface_lifecycle"
local session=Session.compose({
    id="native-lifecycle",root=root,midi_output_port="Ableton Push 2 1",
    persistence={group="native_probe",preset="current",schema_version=1},
    pages={function() return {id="diagnostic",render=function() end} end},
},{display=display})
assert(session.ok,session.message)
local C=session.api.conventions
local token=0
local stage=0
local elapsed=0
local frame_time=0
local events=0
local function publish_resources()
    local r=surface.resources()
    state.set(root.."/subscriptions",#r.subscriptions)
    state.set(root.."/handlers",#r.midi+#r.semantic_midi)
    state.set(root.."/mappings",#r.mappings)
end
local function begin()
    local result=surface.claim()
    assert(result.ok,result.code)
    token=result.token
    stage+=1
    events=0
    for key,value in pairs({stage=stage,token=token,command=0,input=0,mapped=0,events=0,
        subscriptions=0,handlers=0,mappings=0,stop_verified=false,stale_stop_refused=false}) do
        state.register(key,value)
    end
    state.set(root.."/stage",stage)
    state.set(root.."/token",token)
    midi.on("push2.encoder.0","encoder_relative",function(ev: any)
        events+=1
        state.set(root.."/input",math.clamp((tonumber(state.get(root.."/input")) or 0)+ev.delta,0,127))
        state.set(root.."/events",events)
    end)
    midi.on("push2.button.top.0","momentary",function(ev: any)
        if ev.pressed then state.set(root.."/command",1) end
    end)
    sentinel.subscribe("/sentinel/version",function() end)
    mapping.create({id="native_session_probe",source={kind="state.path",path=root.."/input"},
        sink={kind="state.path",path=root.."/mapped"}})
    publish_resources()
end
return {
    on_start=begin,
    on_tick=function(dt: number)
        elapsed+=dt
        if state.get(root.."/command")==1 then
            local old=token
            assert(surface.stop(old))
            local cleared=surface.resources()
            assert(#cleared.midi==0 and #cleared.semantic_midi==0 and #cleared.subscriptions==0 and #cleared.mappings==0)
            begin()
            assert(not surface.stop(old))
            state.set(root.."/stop_verified",true)
            state.set(root.."/stale_stop_refused",true)
            publish_resources()
        end
        frame_time+=dt
        if frame_time<1/60 then return end
        frame_time%=1/60
        display.clear(0x101014)
        display.rect(0,0,960,18,0x273A38,true)
        C.text(8,2,"RESTART SESSION",12,0xFFFFFF)
        C.text(8,32,"NATIVE SESSION "..stage,18,0xFFFFFF)
        C.text(8,60,"KNOB 1  "..tostring(state.get(root.."/input")),16,0x80C8B8)
        C.text(280,60,"MAPPED  "..tostring(state.get(root.."/mapped")),16,0x80C8B8)
        C.text(8,92,"EVENTS "..events.."  TOKEN "..token,12,0xAAAAAA)
        C.text(8,119,"TOP LEFT: RESTART / VERIFY RESOURCE CLEANUP",12,0xAAAAAA)
        display.rect(0,144,960,16,0x273A38,true)
        C.text(8,145,"PHASE 20 LIFECYCLE DIAGNOSTIC",11,0xFFFFFF)
    end,
    on_stop=function()
        if token~=0 then surface.stop(token);token=0 end
    end,
}
