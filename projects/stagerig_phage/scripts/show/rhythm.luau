--!strict
return function(host,get)
local Pe=get("persist")
local M={records={},lanes={},root="",now=0}
local specs={{"mode",0,1,0},{"cycle",.0625,64,4},{"rest",0,64,0},{"offset",-64,64,0}}
-- Lane timing out of the box: KICK every beat, SNARE on 2 and 4, HI-HAT on the offbeat.
local DEFAULTS={{cycle=1,rest=0,offset=0},{cycle=1,rest=1,offset=1},{cycle=.5,rest=.5,offset=.5}}
for i=1,3 do
    local lane={last_hit=0,start=nil,phase=0,active=false,trigger=0}
    for _,s in ipairs(specs) do
        local r={key="rhythm_"..i.."_"..s[1],default=DEFAULTS[i][s[1]] or s[4],min=s[2],max=s[3],persist="bank"}
        lane[s[1]]=r;table.insert(M.records,r)
    end
    M.lanes[i]=lane
end
function M.bind(root)
    M.root=root
    for i=1,3 do for _,key in ipairs({"phase","active","trigger","envelope"}) do host.state.register("lane_"..i.."_"..key,0) end end
end
function M.step(beat,running,tracks,now)
    M.now=now
    for i,lane in ipairs(M.lanes) do
        for _,s in ipairs(specs) do
            local r=lane[s[1]];r.value=tonumber(host.state.get(M.root.."/"..r.key)) or r.default
        end
        local cycle=lane.cycle.value;local rest=lane.rest.value
        local tr=tracks[i];local mode=lane.mode.value
        if lane.last_beat and beat<lane.last_beat then lane.start=nil;lane.last_hit=tr.hits end
        local ph=0;local active=false
        if mode<.5 then
            local t=(beat-lane.offset.value)%(cycle+rest)
            ph=math.min(1,t/cycle);active=t<cycle
            local epoch=math.floor((beat-lane.offset.value)/(cycle+rest))
            if running and lane.epoch~=epoch then lane.trigger+=1 end;lane.epoch=epoch
        else
            if tr.hits~=lane.last_hit then lane.start=beat+lane.offset.value;lane.trigger+=1 end
            if lane.start then local age=beat-lane.start;ph=math.clamp(age/cycle,0,1);active=age>=0 and age<cycle end
        end
        lane.last_hit=tr.hits;lane.last_beat=beat
        lane.phase=ph;lane.active=active and running and not tr.muted
        local values={phase=ph,active=if lane.active then 1 else 0,trigger=lane.trigger,
            envelope=if lane.active then 1-ph else 0}
        for key,v in pairs(values) do host.state.set(M.root.."/lane_"..i.."_"..key,v) end
    end
end
function M.encoder(key,label,selected)
    local r={key="rhythm_edit_"..key,label=label,default=0,min=-64,max=64,persist="none",fine_step=.0625}
    r.on_delta=function(delta)
        local rec=M.lanes[selected()][key]
        rec.value=math.clamp((rec.value or rec.default)+delta,rec.min,rec.max)
        if key=="mode" then rec.value=math.floor(rec.value+.5) end
        Pe.publish(rec,M.now)
    end
    r.format=function()
        local rec=M.lanes[selected()][key];r.min=rec.min;r.max=rec.max
        r.fine_step=if key=="mode" then 1 else .0625;r.no_acceleration=key=="mode"
        return if key=="mode" then (if (rec.value or 0)<.5 then "REPEAT" else "STEPS") else string.format("%.3g beats",rec.value or rec.default)
    end
    return r
end
return M
end
