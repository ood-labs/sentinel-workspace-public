--!strict
-- Project-owned migration seam. Own state stays local; foreign state is a
-- subscribed snapshot. Missing services remain missing, never simulated.
return function(localState: any, bridge: any)
    local root=localState.root()
    -- A stalled render thread can temporarily fill the owner's publication
    -- queue. Retain only the latest value per path, and retry on control ticks.
    local pending: {[string]: any}={}
    local function write(target: string,value: any): boolean
        if localState.get(target)==value then pending[target]=nil;return true end
        local ok,err=pcall(localState.set,target,value)
        if ok then pending[target]=nil;return true end
        if not string.find(tostring(err),"state.set: owner queue full",1,true) then error(err,0) end
        pending[target]=value
        return false
    end
    local function resolve(path: string): string?
        local id,tail=string.match(path,"^/ctrl/script/([^/]+)/(.*)$")
        if id=="10_stagerig_push2_panel" then return root.."/"..tail end
        if string.sub(path,1,10)=="/sentinel/" then return path end
        return nil
    end
    local function own(path: string): boolean
        return string.sub(path,1,#root+1)==root.."/"
    end
    return {
        register=localState.register, root=localState.root,
        flush=function()
            local count=0
            for target,value in pairs(pending) do
                if not write(target,value) then break end
                count+=1
                if count>=32 then break end
            end
        end,
        get=function(path: string): any
            local target=resolve(path)
            if not target then return nil end
            if own(target) then
                if pending[target]~=nil then return pending[target] end
                return localState.get(target)
            end
            bridge.subscribe(target)
            return bridge.get(target)
        end,
        set=function(path: string,value: any)
            local target=resolve(path)
            assert(target,"No native state route for "..path)
            if own(target) then write(target,value);return end
            return bridge.set(target,value)
        end,
    }
end
