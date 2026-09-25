--!strict
return function()
    local a={}
    local function add(key,label,lo,hi,default,fine,unit,choices)
        a[key]={label=label,min=lo,max=hi,default=default,fine=fine,unit=unit,
            relative=choices==nil,choices=choices,step=if choices then 1 else nil}
    end
    add("pan","PAN",-270,270,0,.1,"deg")
    add("tilt","TILT",-135,135,0,.1,"deg")
    add("level","BEAM",0,1,1,.005,"ratio")
    add("ring","RING",0,1,1,.005,"ratio")
    add("beam_palette","BEAM COLOR",0,2,0,1,"",{"A","B","C"})
    add("ring_palette","RING COLOR",0,2,1,1,"",{"A","B","C"})
    add("move_lane","MOVE LANE",0,3,0,1,"",{"OFF","KICK","SNARE","HI-HAT"})
    add("int_lane","CHASE LANE",0,3,1,1,"",{"OFF","KICK","SNARE","HI-HAT"})
    add("color_lane","COLOR LANE",0,3,0,1,"",{"OFF","KICK","SNARE","HI-HAT"})
    add("pan_amp","PAN SIZE",-180,180,0,.1,"deg")
    add("tilt_amp","TILT SIZE",-90,90,0,.1,"deg")
    add("spread","SPREAD",0,.95,.45,.005,"cycle")
    add("width","WIDTH",.01,1,.5,.005,"cycle")
    add("offset","OFFSET",-1,1,0,.005,"cycle")
    add("reverse","DIRECTION",0,1,0,1,"",{"FORWARD","REVERSE"})
    -- 0-15 LED content; 16-47 mover FX (chase repeats x1-x8, RND gate, JMP random positions, STEP point sequence).
    add("led_pattern","LED LOOK",0,47,2,1,"",{"SOLID","OUTLINES","CHASE","PULSE","SCATTER",
        "COMET","TWIN SPIN","FILL","SCANNER","BARCODE","PLASMA","SPARKLE","HEARTBEAT","EDGE HOP","CHEVRON","RIPPLE",
        "MOV x1","MOV x2","MOV x4","MOV x8","MOV x1 RND","MOV x2 RND","MOV x4 RND","MOV x8 RND","MOV x1 JMP","MOV x2 JMP","MOV x4 JMP","MOV x8 JMP","MOV x1 RND JMP","MOV x2 RND JMP","MOV x4 RND JMP","MOV x8 RND JMP","MOV x1 STEP","MOV x2 STEP","MOV x4 STEP","MOV x8 STEP","MOV x1 RND STEP","MOV x2 RND STEP","MOV x4 RND STEP","MOV x8 RND STEP","MOV x1 JMP STEP","MOV x2 JMP STEP","MOV x4 JMP STEP","MOV x8 JMP STEP","MOV x1 RND JMP STEP","MOV x2 RND JMP STEP","MOV x4 RND JMP STEP","MOV x8 RND JMP STEP"})
    add("strobe_rate","RATE /BEAT",1,24,6,.25,"rate")
    add("strobe_duty","DUTY",.05,.95,.35,.01,"ratio")
    a.strobe_rate.relative=false;a.strobe_duty.relative=false
    return {attributes=a,static={"pan","tilt","level","ring","beam_palette","ring_palette"},
        effects={"move_lane","int_lane","color_lane","pan_amp","tilt_amp","spread","width","offset","reverse","led_pattern"},
        banks={{id="position",label="POSITION",attributes={"pan","tilt"}},
            {id="levels",label="LIGHT / COLOR",attributes={"level","ring","beam_palette","ring_palette"}},
            {id="movement",label="MOVE FX",attributes={"move_lane","pan_amp","tilt_amp","spread","offset","reverse"}},
            {id="chase",label="CHASE / COLOR FX",attributes={"int_lane","width","spread","offset","reverse","color_lane"}},
            {id="led",label="LED FX",attributes={"led_pattern","int_lane","width","spread","offset","reverse"}},
            {id="strobe",label="LED STROBE",attributes={"strobe_rate","strobe_duty","width","spread","int_lane","reverse"}}}}
end
