--!strict
local Session=require("./session")
local Restore=require("./restore")
local M={}
local REQUIRED={"push2.session.v1","push2.complete_frame.v1","preset.restore_barrier.v1","preset.merge_save.v1"}

-- The root explicitly supplies native namespaces; no host work at import time.
function M.native(bindings: any): any
    return bindings
end

function M.create(config: any, native: any): any
    if typeof(native)~="table" then return {ok=false,code="INVALID_ADAPTER"} end
    for _,name in ipairs({"surface","display","state","midi","preset","log","sentinel"}) do
        if typeof(native[name])~="table" then return {ok=false,code="INVALID_ADAPTER",namespace=name} end
    end
    local active=false
    local stopped=false
    local token=nil
    local hooks=nil
    local saved=nil
    local prepared=nil
    local elapsed=0
    local nextRestore=0
    local pressed:any={}
    local status:any={ok=false,outcome="pending",code="NOT_STARTED"}
    local host:any={}
    -- Guard all framework host work. Only the startup coordinator reads native
    -- capabilities/banks before activation. Captured MIDI callbacks become inert
    -- immediately on stop even if another session later claims the device.
    for name,namespace in pairs(native) do
        if typeof(namespace)~="table" then host[name]=namespace;continue end
        local proxy={}
        for key,fn in pairs(namespace) do
            if typeof(fn)~="function" then proxy[key]=fn;continue end
            proxy[key]=function(...)
                -- Construct diagnostics only on failure; this wraps every draw
                -- and StateTree call on the performance surface.
                if not active then error("Runtime host access before restore or after stop: "..name.."."..key) end
                if name=="midi" and key=="on" then
                    local args=table.pack(...)
                    local callback=args[args.n]
                    local id=args[1]
                    args[args.n]=function(...)
                        if active and not stopped then
                            local ev=...
                            if typeof(ev)=="table" and ev.pressed==true then
                                pressed[id]={callback=callback,event=table.clone(ev)}
                            elseif typeof(ev)=="table" and ev.pressed==false then pressed[id]=nil end
                            return callback(...)
                        end
                    end
                    return fn(table.unpack(args,1,args.n))
                end
                if name=="state" and key=="register" and prepared then
                    local args=table.pack(...)
                    local value=prepared.initial[args[1]]
                    if value~=nil then args[2]=value end
                    assert(args[2]~=nil,"Missing prepared initial value: "..tostring(args[1]))
                    return fn(args[1],args[2])
                end
                return fn(...)
            end
        end
        host[name]=proxy
    end
    local session=Session.compose(config,host)
    if not session.ok then return session end
    local runtime:any={ok=true,code="RUNTIME_CREATED",api=session.api,pages=session.pages}
    local function stop()
        if stopped then return false end
        stopped=true
        for _,held in pairs(pressed) do
            held.event.pressed=false
            pcall(held.callback,held.event)
        end
        table.clear(pressed)
        if hooks then pcall(hooks.on_stop) end
        if active then pcall(native.display.abort_frame) end
        active=false
        if token then native.surface.stop(token);token=nil end
        if status.ok then status={ok=true,outcome="stopped",code="STOPPED"} end
        return true
    end
    local function start()
        if stopped or active then return end
        local caps=native.surface and native.surface.capabilities and native.surface.capabilities()
        for _,cap in ipairs(REQUIRED) do
            if not caps or not caps.capabilities or caps.capabilities[cap]~=true then
                status={ok=false,outcome="incompatible",code="HOST_CAPABILITY_MISSING",capability=cap}
                stopped=true;return
            end
        end
        local ok,bank=pcall(native.preset.read_snapshot,config.persistence.group,config.persistence.preset)
        if not ok then status={ok=false,outcome="failed",code="BANK_READ_FAILED",message=tostring(bank)};return end
        status=Restore.prepare(session.config,session.pages,bank,saved)
        if not status.ok then return end
        prepared=status
        prepared.initial={}
        local claim=native.surface.claim()
        if not claim.ok then status={ok=false,outcome="failed",code=claim.code};return end
        token=claim.token
        for _,entry in ipairs(prepared.records) do
            local rec=entry.record
            rec.value=entry.value
            local rel=if rec.sink and rec.sink.kind=="state" then rec.sink.path
                else rec.state_path or rec.key or rec.id
            if entry.lifetime=="state" or entry.lifetime=="bank" or (rec.sink and rec.sink.kind=="state") then
                prepared.initial[rel]=entry.value
            end
        end
        session.config.restore_prepared=true
        session.config.restored_page_id=prepared.page_id
        active=true
        local started,value=pcall(function() return session._get("core").start(session.config) end)
        if not started then
            status={ok=false,outcome="failed",code="START_FAILED",message=tostring(value)}
            if native.log and native.log.error then native.log.error("[push2os] "..status.code..": "..status.message) end
            stop();return
        end
        hooks=value
        for _,entry in ipairs(prepared.records) do
            if entry.needs_bank_save then session._get("persist").publish(entry.record,0) end
        end
        status={ok=true,outcome="restored",code="RUNNING",new_empty=prepared.new_empty}
    end
    runtime.stop=stop
    runtime.status=function() return status end
    runtime.callbacks={
        on_start=start,
        on_deserialize=function(data: any)
            assert(not active,"Deserialize must precede activation")
            saved=data
        end,
        on_tick=function(dt: number)
            if stopped then return end
            if not active then
                elapsed+=dt
                return
            end
            hooks.on_tick(dt)
        end,
        on_render=function()
            -- Deferred restore includes bank reads and full host registration.
            -- Service it on the existing UI callback, like durable bank saves,
            -- rather than inside the musical tick's tighter callback budget.
            if not stopped and not active and elapsed>=nextRestore then
                nextRestore=elapsed+0.5
                start()
                return
            end
            if active and not stopped and hooks then hooks.on_render() end
        end,
        on_stop=stop,
        on_serialize=function()
            if not active or not prepared then return saved end
            local values={}
            for _,entry in ipairs(prepared.records) do
                if entry.lifetime~="none" then values[entry.id]=entry.record.value end
            end
            local legacy:any=hooks.on_serialize()
            return {version=2,show_id=config.id,page_id=session.pages[legacy.page+1].id,values=values}
        end,
    }
    return runtime
end

return M
