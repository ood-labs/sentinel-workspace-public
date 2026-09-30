--!strict
-- The 17 programmer attributes of a PHAGE slot, in Phage_Program's f<slot>_<attribute> order.
-- Lanes 1-3 are the rhythm lanes (REPEAT or STEPS), 4 BUILD ramps from the last effects/full-look
-- recall over the Show's build length, 5 PHRASE turns once per phrase.
return function()
    local a={}
    local function add(key,label,lo,hi,default,fine,unit,choices)
        a[key]={label=label,min=lo,max=hi,default=default,fine=fine,unit=unit,
            relative=choices==nil,choices=choices,step=if choices then 1 else nil}
    end
    local lanes={"OFF","KICK","SNARE","HI-HAT","BUILD","PHRASE"}
    add("pan","PAN",-270,270,0,.1,"deg")
    add("tilt","TILT",-135,135,0,.1,"deg")
    add("level","LEVEL",0,1,1,.005,"ratio")
    add("ring","RING / PLATE",0,1,.6,.005,"ratio")
    add("beam_palette","COLOR",0,2,0,1,"",{"A","B","C"})
    add("ring_palette","COLOR 2",0,2,1,1,"",{"A","B","C"})
    add("move_lane","MOVE LANE",0,5,0,1,"",lanes)
    add("int_lane","CHASE LANE",0,5,0,1,"",lanes)
    add("color_lane","COLOR LANE",0,5,0,1,"",lanes)
    add("pan_amp","PAN SIZE",-180,180,0,.1,"deg")
    add("tilt_amp","TILT SIZE",-90,90,0,.1,"deg")
    add("spread","SPREAD",0,.95,.45,.005,"cycle")
    add("width","WIDTH",.01,1,.5,.005,"cycle")
    add("offset","OFFSET",-1,1,0,.005,"cycle")
    add("reverse","DIRECTION",0,1,0,1,"",{"FORWARD","REVERSE"})
    -- LOOK: pixel bars 0-15; strobes 0-5 (see strobe_choices); movers and axes 16-47 movement FX
    -- (repeats x1-x8, RND gate, JMP random points, STEP point sequence) and 48-51 SPIN.
    local looks={"SOLID","CHASE","PULSE","SEGMENTS","SCATTER","COMET","TWIN","FILL",
        "SCANNER","BARCODE","PLASMA","SPARKLE","HEARTBEAT","CLIMB","STROBE","RIPPLE"}
    for code=16,47 do
        local fx=code-16
        local name="MOV x"..(2^(fx%4))
        if bit32.band(fx,4)~=0 then name..=" RND" end
        if bit32.band(fx,8)~=0 then name..=" JMP" end
        if bit32.band(fx,16)~=0 then name..=" STEP" end
        table.insert(looks,name)
    end
    for _,rate in ipairs({"1/4","1/2","1","2"}) do table.insert(looks,"SPIN "..rate) end
    add("look","LOOK",0,51,0,1,"",looks)
    a.look.strobe_choices={"PULSE","STROBE","SPARKLE","BLINDER","GLOW","OFF"}
    add("order","ORDER",0,7,0,1,"",{"AROUND","MIRROR","OUT","UP","FRONT","SIDE","SHUFFLE","LEG"})
    -- Show-level strobe clock (Phage_Show strobe_rate / strobe_duty), edited with strobes or bars selected.
    add("strobe_rate","RATE /BEAT",1,24,4,.25,"rate")
    add("strobe_duty","DUTY",.05,.95,.3,.01,"ratio")
    a.strobe_rate.relative=false;a.strobe_duty.relative=false
    -- Which attributes each fixture kind carries (the rest stay at their defaults in its row).
    local kinds={
        [0]={"pan","tilt","level","ring","beam_palette","ring_palette","move_lane","int_lane","color_lane",
            "pan_amp","tilt_amp","spread","width","offset","reverse","look","order"},
        [1]={"level","ring","beam_palette","int_lane","color_lane","spread","width","offset","reverse","look","order",
            "strobe_rate","strobe_duty"},
        [2]={"level","beam_palette","ring_palette","int_lane","color_lane","spread","width","offset","reverse","look","order",
            "strobe_rate","strobe_duty"},
        [3]={"pan","tilt","move_lane","pan_amp","tilt_amp","spread","offset","reverse","look","order"},
    }
    return {attributes=a,kinds=kinds,
        fields={"pan","tilt","level","ring","beam_palette","ring_palette","move_lane","int_lane","color_lane",
            "pan_amp","tilt_amp","spread","width","offset","reverse","look","order"},
        static={"pan","tilt","level","ring","beam_palette","ring_palette"},
        effects={"move_lane","int_lane","color_lane","pan_amp","tilt_amp","spread","width","offset","reverse","look","order"},
        banks={{id="position",label="POSITION",attributes={"pan","tilt"}},
            {id="levels",label="LEVEL / COLOR",attributes={"level","ring","beam_palette","ring_palette"}},
            {id="movement",label="MOVE FX",attributes={"move_lane","pan_amp","tilt_amp","spread","offset","reverse"}},
            {id="chase",label="CHASE / COLOR FX",attributes={"int_lane","width","spread","offset","reverse","color_lane"}},
            {id="look",label="LOOK / ORDER",attributes={"look","order","int_lane","width","spread","reverse"}},
            {id="strobe",label="STROBE CLOCK",attributes={"strobe_rate","strobe_duty","width","spread","int_lane","reverse"}}}}
end
