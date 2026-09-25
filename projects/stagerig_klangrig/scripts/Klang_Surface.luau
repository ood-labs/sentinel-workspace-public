--!strict
local script={manifest={name="Klang Push 2",
    inputs={{name="panel",type="event"}},
    outputs={{name="display",type="display"},{name="running",type="signal"},{name="desk_feedback",type="event"}}}}
local runtime: any=nil
local incoming: any=nil
local elapsed=0
local restoring=true
local root=""
local lastCode=""
local lastMessage=""
local lastRigMessage=""
local lastRigRevision=-1
local lastRigSelection=-1
local encoderSlot=1
local view=1
local deskBound=false
local serviceTick=0
local rigUI: any=nil
local nativeState: any=nil
local function publishRig()
    local rig=runtime.rig()
    if not rig then return end
    if rig.message~=lastRigMessage then nativeState.set(root.."/programmer_message",rig.message);lastRigMessage=rig.message end
    local revision=rig.status.revision or 0
    if revision~=lastRigRevision then nativeState.set(root.."/programmer_revision",revision);lastRigRevision=revision end
    local selection=#rig.status.selection
    if selection~=lastRigSelection then nativeState.set(root.."/programmer_selection_count",selection);lastRigSelection=selection end
end
function script.deserialize(node: any,saved: any) incoming=saved.package end
function script.init(node: any)
    rigUI=require("@show/native_rig_ui")
    state.begin_restore(true)
    root=state.root()
    nativeState=require("@show/native_state")(state,sentinel)
    local clock=require("@show/native_tempo")({sentinel=sentinel,time=time},"stagerig_klangrig_Clock")
    runtime=require("@show/surface")({surface=surface,display=display,state=nativeState,
        midi=midi,preset=preset,windows_audio=windows_audio,log=log,sentinel=sentinel,time=time,tempo=clock,
        panel=panel},
        {root=root,midi_output_port="Ableton Push 2",guest_port="",
         preset=preset.active("stagerig_klangrig_push2") or "current"})
    assert(runtime.ok,tostring(runtime.code)..": "..tostring(runtime.message))
    if incoming then
        -- Upgrade only records introduced by this show; keep strict vendor validation.
        if incoming.version==2 and incoming.show_id=="stagerig_klangrig" then
            if incoming.values["rig_static/full_looks_origin_row"]==nil then
                incoming.values["rig_static/color_presets_window_width"]=4
                incoming.values["rig_static/color_presets_height"]=4
                incoming.values["rig_static/color_presets_origin_row"]=3
                incoming.values["rig_static/color_presets_origin_col"]=0
            end
            incoming.values["rig_static/selected_fixtures"]=incoming.values["rig_static/selected_fixtures"] or ""
            for _,page in ipairs(runtime.pages) do if page.id=="rig_static" then
                for _,rec in ipairs(page.records) do
                    if (string.match(rec.key,"^full_looks_") or string.match(rec.key,"^color_presets_") or string.match(rec.key,"^led_strobe_")) and incoming.values["rig_static/"..rec.key]==nil then
                        incoming.values["rig_static/"..rec.key]=rec.default
                    end
                end
            end end
            for _,page in ipairs(runtime.pages) do if page.id=="global" then
                -- Camera records come and go with the camera controls: add new ones, drop retired ones.
                local declared={}
                for _,rec in ipairs(page.records or {}) do
                    declared["global/"..rec.key]=true
                    if string.match(rec.key,"^cam_") and incoming.values["global/"..rec.key]==nil then
                        incoming.values["global/"..rec.key]=rec.default
                    end
                end
                for key in pairs(incoming.values) do
                    if string.match(key,"^global/cam_") and not declared[key] then incoming.values[key]=nil end
                end
            end end
            for _,rec in ipairs(runtime.color().records) do
                if string.match(rec.key,"^pal%d[abc]$") and incoming.values["color/"..rec.key]==nil then
                    incoming.values["color/"..rec.key]=state.get(root.."/"..rec.key) or rec.default
                end
            end
        end
        runtime.callbacks.on_deserialize(incoming)
    end
    state.register("runtime_status","NOT_STARTED")
    state.register("runtime_message","")
    state.register("programmer_message","")
    state.register("programmer_revision",0)
    state.register("programmer_selection_count",0)
    local profile="/sentinel/controllers/push2-user-mode/"
    sentinel.set(profile.."enabled",false)
    sentinel.set(profile.."device_in","Ableton Push 2")
    sentinel.set(profile.."device_out","Ableton Push 2")
    runtime.callbacks.on_start()

end
function script.control_process(node: any,ctx: any)
    if nativeState then nativeState.flush() end
    elapsed+=ctx.dt
    serviceTick+=1
    if runtime and runtime.status().code=="RUNNING" then
        local rig=runtime.rig()
        if serviceTick%4==0 or rig.job or rig.fast_pending then
            local ok,err=pcall(rig.service)
            if not ok then rig.message="ERROR: "..tostring(err) end
        end
        -- Klang_Desk Module panel: clicks in, lit/state feedback out.
        local desk=runtime.desk_panel()
        if not deskBound then desk.bind(root);deskBound=true end
        local ok,err=pcall(desk.service,node,ctx.dt)
        if not ok then log.warn("desk panel: "..tostring(err)) end
    end
    node.outputs.running:set(if runtime and runtime.status().code=="RUNNING" then 1 else 0)
end
function script.restore()
    if not runtime then return end
    local dt=elapsed;elapsed=0
    runtime.callbacks.on_tick(dt)
    runtime.callbacks.on_render()
    publishRig()
    local status=runtime.status()
    local rig=runtime.rig()
    if restoring and status.code=="RUNNING" and rig and rig.status.revision then
        state.complete_restore();restoring=false
        sentinel.set("/sentinel/controllers/push2-user-mode/enabled",true)
    end
    local message=tostring(status.message or status.capability or "").." "..tostring(status.context and status.context.id or "")
    if lastCode~=status.code then state.set(root.."/runtime_status",status.code);lastCode=status.code end
    if lastMessage~=message then state.set(root.."/runtime_message",message);lastMessage=message end
end
function script.render_display(node: any,d: any)
    d:skip()
    if not runtime or restoring then return end
    local dt=elapsed;elapsed=0
    runtime.callbacks.on_tick(dt)
    runtime.callbacks.on_render()
    publishRig()
end
function script.render(node: any,ui: any)
    local status=runtime and runtime.status() or {code="NOT_STARTED"}
    ui.text("runtime","Push 2: "..status.code)
    ui.text("message",tostring(status.message or status.capability or ""))
    if runtime and status.code=="RUNNING" then
        -- DESK plays the show without a Push 2; ADVANCED holds the Push page tools and the programmer.
        local changedView,newView=ui.combo("view","View",view,{"DESK","ADVANCED"})
        if changedView and newView then view=newView end
        if view==1 then runtime.desk().draw(ui);return end
        local changedTab,tab=ui.combo("page_tab","Push 2 page",(tonumber(state.get(root.."/page")) or 0)+1,
            {"SEQUENCE","GLOBAL","RIG","COLOR"})
        if changedTab then runtime.api.legacy_v1.pad_desktop.tab(tab-1,time.now()) end
        local changedSlot,slot=ui.combo("encoder_slot","Encoder",encoderSlot,{"1","2","3","4","5","6","7","8"})
        if changedSlot then encoderSlot=slot end
        local _,less=ui.button("encoder_less","Encoder -1")
        ui.same_line()
        local _,more=ui.button("encoder_more","Encoder +1")
        if less or more then runtime.api.legacy_v1.params.on_delta(encoderSlot-1,if less then -1 else 1,time.now()) end
    end
    local rig=runtime and runtime.rig()
    if rig then rigUI(ui,rig) end
    ui.text("migration","Klangrig | Static looks + effects + musical rhythm")
end
function script.serialize()
    if runtime and runtime.status().code=="RUNNING" then runtime.rig().flush_snapshot() end
    -- A failed or yielded boot has no complete package snapshot to serialize.
    return {package=if runtime and runtime.status().code=="RUNNING"
        then runtime.callbacks.on_serialize() else incoming}
end
function script.stop()
    if runtime and runtime.desk_panel() then pcall(runtime.desk_panel().stop) end
    if runtime then runtime.stop() end
end
return script
