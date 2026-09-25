--!strict
-- Conductor owns musical time. This adapter never integrates a second clock.
return function(host: any, pipeline: string)
    local base="/sentinel/pipelines/"..pipeline
    local values={
        bpm=base.."/parameters/bpm", running=base.."/parameters/transport_run",
        mode=base.."/parameters/transport_mode", beats_per_bar=base.."/parameters/beats_per_bar",
        beat=base.."/control_outputs/total_beats",
    }
    local taps: {number}={}
    local api: any={}
    for _,path in pairs(values) do host.sentinel.subscribe(path) end
    local function number(key: string, fallback: number): number
        return tonumber(host.sentinel.get(values[key])) or fallback
    end
    local function finite(value: number): boolean
        return typeof(value)=="number" and value==value and math.abs(value)<math.huge
    end
    function api.status(): any
        local beat=number("beat",0)
        local beats=math.max(1,number("beats_per_bar",4))
        local running=host.sentinel.get(values.running)
        local ready=host.sentinel.get(values.beat)~=nil and host.sentinel.get(values.bpm)~=nil
        return {ready=ready,bpm=number("bpm",124),beat=beat,beats_per_bar=beats,
            running=running==true or running=="true" or running==1,
            bar=beat/beats,beat_phase=beat%1,bar_phase=(beat%beats)/beats,
            tap_count=#taps,last_tap_age_ms=if #taps>0 then (host.time.now()-taps[#taps])*1000 else -1,
            loop_enabled=false,loop_start_beats=0,loop_length_beats=16,
            loop_position_beats=beat%16,loop_phase=(beat%16)/16}
    end
    function api.set_bpm(bpm: number): boolean
        assert(finite(bpm) and bpm>=30 and bpm<=300,"Tempo BPM must be in 30..300")
        return host.sentinel.set(values.bpm,bpm)
    end
    function api.start(): boolean return host.sentinel.set(values.running,true) end
    function api.pause(): boolean return host.sentinel.set(values.running,false) end
    function api.resync(beat: number): boolean
        assert(finite(beat) and beat>=0 and beat<=1e9,"Resync beat must be in 0..1000000000")
        assert(number("mode",0)==0,"Resync requires Conductor beat mode")
        return host.sentinel.invoke(base.."/actions/resync",{beat=beat})
    end
    function api.stop(): boolean
        if not api.pause() then return false end
        return api.resync(0)
    end
    function api.tap(): boolean
        local now=host.time.now()
        if #taps>0 then
            local gap=now-taps[#taps]
            if gap<60/240 or gap>60/30 then table.clear(taps) end
        end
        table.insert(taps,now)
        if #taps>5 then table.remove(taps,1) end
        if not api.status().running and not api.start() then return false end
        if #taps<2 then return true end
        local gaps={}
        for i=2,#taps do table.insert(gaps,taps[i]-taps[i-1]) end
        table.sort(gaps)
        local mid=math.floor(#gaps/2)+1
        local interval=if #gaps%2==0 then (gaps[mid-1]+gaps[mid])/2 else gaps[mid]
        return api.set_bpm(math.clamp(60/interval,30,240))
    end
    return api
end
