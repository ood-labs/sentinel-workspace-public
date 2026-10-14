--!strict
-- The 17 programmer attributes of a PHAGE program row, in Phage_Program's f<row>_<attribute> order, and the layers
-- that read them. Each fixture type is programmed as layers (studio_rig's layered programmer), one program row each:
--   Halo Beam       MOVE (its base row), BEAM, HALO
--   Linear Strobe   TUBE (its base row), PLATES
--   Pixel Batten    PIXELS (its base row), CHASE
-- plus the truss axes. A layer's knobs are named for what they drive (BEAM is the beam's dimmer, HALO the halo's),
-- views onto the program fields they live in, so every knob does one thing; the command seam may still name the
-- fields ("level", "ring", "look"), which reach the layer whose knob drives that field.
-- Lanes 1-3 are the rhythm lanes (REPEAT or STEPS), 4 BUILD ramps from the last effects/full-look
-- recall over the Show's build length, 5 PHRASE turns once per phrase.
return function()
    local a={}
    local function add(key,label,lo,hi,default,fine,unit,choices)
        a[key]={label=label,min=lo,max=hi,default=default,fine=fine,unit=unit,
            relative=choices==nil,choices=choices,step=if choices then 1 else nil}
    end
    local function alias(key,label,field,lo,hi,default,fine,unit,choices)
        add(key,label,lo,hi,default,fine,unit,choices);a[key].field=field
    end
    local lanes={"OFF","KICK","SNARE","HI-HAT","BUILD","PHRASE"}
    add("pan","PAN",-270,270,0,.1,"deg")
    add("tilt","TILT",-135,135,0,.1,"deg")
    add("level","LEVEL",0,1,1,.005,"ratio")
    add("ring","RING / PLATE",0,1,.6,.005,"ratio")
    alias("beam","BEAM","level",0,1,1,.005,"ratio")             -- Halo Beam BEAM row: the beam's dimmer
    alias("halo","HALO","ring",0,1,.6,.005,"ratio")             -- Halo Beam HALO row: the 24-cell ring's dimmer
    alias("tube","TUBE","level",0,1,0,.005,"ratio")             -- Linear Strobe TUBE row: the white tube
    alias("plates","PLATES","ring",0,1,.35,.005,"ratio")        -- Linear Strobe PLATES row: the two colour plates
    alias("bar","BAR LEVEL","level",0,1,1,.005,"ratio")         -- Pixel Batten PIXELS row: the content's level
    alias("depth","CHASE DEPTH","level",0,1,1,.005,"ratio")     -- Pixel Batten CHASE row: how far its chase dips
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
    alias("glide","GLIDE","width",.01,1,.5,.005,"cycle")        -- MOVE rows: how much of a GLIDE step a move takes
    -- Truss axes: FRONT holds the axis's pan (capsid spin, body yaw, leg swing) at 0 whatever the pose and effects do;
    -- the beam shapes aimed with the capsid facing front set it on the capsid.
    alias("heading","HEADING","level",0,1,1,1,"",{"FRONT","FREE"})
    -- LOOK: the program field every layer reads its own way. Each layer has its own LOOK knob below (MOVE FX, BEAM FX,
    -- TUBE FX...) with its own vocabulary and knob order; the raw field still takes any code 0-63 (the command seam's
    -- `look`, stored banks).
    local pixels={"SOLID","CHASE","PULSE","SEGMENTS","SCATTER","COMET","TWIN","FILL",
        "SCANNER","BARCODE","PLASMA","SPARKLE","HEARTBEAT","CLIMB","STROBE","RIPPLE"}
    local function fxName(code,prefix,moving)
        local fx=code-16
        local name=prefix.." x"..(2^(fx%4))
        if bit32.band(fx,4)~=0 then name..=" RND" end
        if moving and bit32.band(fx,8)~=0 then name..=" JMP" end
        if moving and bit32.band(fx,16)~=0 then name..=" STEP" end
        return name
    end
    local looks=table.clone(pixels)
    for code=16,47 do table.insert(looks,fxName(code,"MOV",true)) end
    for _,rate in ipairs({"1/4","1/2","1","2"}) do table.insert(looks,"SPIN "..rate) end
    -- GLIDE 52-63: eased moves between positions, a new one every lane cycle x1-x8; the five-point figure, a random
    -- position per head (RND) or one per group (GROUP).
    local function glideName(code)
        local fx=code-52
        local name="GLIDE x"..(2^(fx%4))
        if bit32.band(fx,8)~=0 then name..=" GROUP" elseif bit32.band(fx,4)~=0 then name..=" RND" end
        return name
    end
    for code=52,63 do table.insert(looks,glideName(code)) end
    add("look","LOOK",0,63,0,1,"",looks)
    a.look.strobe_choices={"PULSE","STROBE","SPARKLE","BLINDER","GLOW","OFF"}
    local function names(map) local t={};for code,name in pairs(map) do t[code+1]=name end;return t end
    local function lookAlias(key,label,map,sequence)
        local hi=0;for code in pairs(map) do hi=math.max(hi,code) end
        alias(key,label,"look",0,hi,0,1,"",names(map))
        a[key].sequence=sequence
    end
    -- MOVE FX (Halo Beam MOVE rows and the truss axes): the move lane's circle (a sweep or a nod with one size at 0),
    -- GLIDE (eased moves between positions, rippling through a group), the repeats, JMP (random points), STEP (the
    -- five-point sequence) and SPIN.
    local move={[0]="CIRCLE"}
    for code=16,47 do move[code]=fxName(code,"MOV",true) end
    for n,rate in ipairs({"1/4","1/2","1","2"}) do move[47+n]="SPIN "..rate end
    for code=52,63 do move[code]=glideName(code) end
    local moveSeq={0};for code=52,63 do table.insert(moveSeq,code) end;for code=16,51 do table.insert(moveSeq,code) end
    lookAlias("move_fx","MOVE FX",move,moveSeq)
    -- BEAM FX and HALO FX: the chase lane's pulse, repeated x1-x8, and RND (a random third of the fixtures each pulse).
    -- A layer upgraded from a look stored before the layers keeps its mover's code (16-51); the knob names those by
    -- what the layer does with them (the JMP and STEP bits move the head, not the light).
    -- HOLD x1-x8 (24-27): a window open for WIDTH of each lane cycle from OFFSET, closed otherwise.
    local pulse={[0]="PULSE"};local pulseSeq={0}
    for code=16,47 do pulse[code]=fxName(code,"PULSE",false) end
    for code=24,27 do pulse[code]="HOLD x"..(2^(code-24)) end
    for code=48,51 do pulse[code]="PULSE" end
    for code=16,27 do table.insert(pulseSeq,code) end
    lookAlias("beam_fx","BEAM FX",pulse,pulseSeq)
    lookAlias("halo_fx","HALO FX",table.clone(pulse),pulseSeq)
    -- TUBE FX and PLATES FX (Linear Strobe): the strobe looks. GLOW darkens the tube and lets the plates follow the
    -- chase; OFF darkens the layer.
    local strobe={[0]="PULSE",[1]="STROBE",[2]="SPARKLE",[3]="BLINDER",[4]="GLOW",[5]="OFF"}
    for code=16,47 do strobe[code]=fxName(code,"PULSE",false) end
    for code=24,27 do strobe[code]="HOLD x"..(2^(code-24)) end
    lookAlias("tube_fx","TUBE FX",strobe,{5,4,0,1,2,3,24,25,26,27})
    lookAlias("plates_fx","PLATES FX",table.clone(strobe),{5,4,0,1,2,3,24,25,26,27})
    -- PIXEL FX (Pixel Batten PIXELS rows): the 16 contents, once per lane cycle (0-15) or x2, x4, x8 (16-63).
    local px={};local pxSeq={}
    for speed=0,3 do for i,name in ipairs(pixels) do
        local code=speed*16+i-1
        px[code]=if speed==0 then name else name.." x"..(2^speed);table.insert(pxSeq,code)
    end end
    lookAlias("pixel_fx","PIXEL FX",px,pxSeq)
    -- CHASE FX (Pixel Batten CHASE rows): a pulse that dips the content on the chase lane, x1-x8 and RND, STROBE
    -- flashes at the show's strobe clock, BLINDER a hit that decays over the lane cycle, HOLD x1-x8 (24-27) shows
    -- the content for WIDTH of each cycle from OFFSET and nothing else (the window CHASE pads hand from group to group).
    local chase={[0]="PULSE",[1]="STROBE",[3]="BLINDER"};local chaseSeq={0}
    for code=16,23 do chase[code]=fxName(code,"PULSE",false);table.insert(chaseSeq,code) end
    for code=24,27 do chase[code]="HOLD x"..(2^(code-24));table.insert(chaseSeq,code) end
    table.insert(chaseSeq,1);table.insert(chaseSeq,3)
    lookAlias("chase_fx","CHASE FX",chase,chaseSeq)
    add("order","ORDER",0,7,0,1,"",{"AROUND","MIRROR","OUT","UP","FRONT","SIDE","SHUFFLE","LEG"})
    -- Show-level strobe clock (Phage_Show strobe_rate / strobe_duty), edited with a layer selected that runs on it.
    add("strobe_rate","RATE /BEAT",1,24,4,.25,"rate")
    add("strobe_duty","DUTY",.05,.95,.3,.01,"ratio")
    a.strobe_rate.relative=false;a.strobe_duty.relative=false
    -- Which attributes each kind (a fixture's layer, static_rig row kinds) carries; the rest stay at their defaults.
    local kinds={
        [0]={"pan","tilt","move_lane","pan_amp","tilt_amp","spread","offset","reverse","move_fx","order","glide"},  -- MOVE
        [4]={"beam","beam_palette","int_lane","color_lane","width","spread","offset","reverse","beam_fx","order"},  -- BEAM
        [5]={"halo","ring_palette","int_lane","color_lane","width","spread","offset","reverse","halo_fx","order"},  -- HALO
        [1]={"tube","int_lane","width","spread","offset","reverse","tube_fx","order","strobe_rate","strobe_duty"},  -- TUBE
        [6]={"plates","beam_palette","int_lane","color_lane","width","spread","offset","reverse","plates_fx","order"},  -- PLATES
        [2]={"bar","beam_palette","ring_palette","int_lane","color_lane","spread","width","offset","reverse","pixel_fx",
            "order","strobe_rate","strobe_duty"},                                                                 -- PIXELS
        [7]={"depth","int_lane","width","spread","offset","reverse","chase_fx","order","strobe_rate","strobe_duty"},  -- CHASE
        [3]={"pan","tilt","heading","move_lane","pan_amp","tilt_amp","spread","offset","reverse","move_fx","order",
            "glide"},                                                                                             -- axes
    }
    local look_of={[0]="move_fx",[4]="beam_fx",[5]="halo_fx",[1]="tube_fx",[6]="plates_fx",[2]="pixel_fx",[7]="chase_fx",
        [3]="move_fx"}
    local layer_names={[0]="MOVE",[4]="BEAM",[5]="HALO",[1]="TUBE",[6]="PLATES",[2]="PIXELS",[7]="CHASE",[3]="AXIS"}
    return {attributes=a,kinds=kinds,look_of=look_of,layer_names=layer_names,
        fields={"pan","tilt","level","ring","beam_palette","ring_palette","move_lane","int_lane","color_lane",
            "pan_amp","tilt_amp","spread","width","offset","reverse","look","order"},
        static={"pan","tilt","level","ring","beam_palette","ring_palette"},
        effects={"move_lane","int_lane","color_lane","pan_amp","tilt_amp","spread","width","offset","reverse","look","order"},
        banks={{id="position",label="POSITION",attributes={"pan","tilt","heading"}},
            {id="levels",label="LEVELS",attributes={"beam","halo","tube","plates","bar","depth"}},
            {id="color",label="COLOR",attributes={"beam_palette","ring_palette","color_lane"}},
            {id="movement",label="MOVE FX",attributes={"move_lane","pan_amp","tilt_amp","spread","offset","glide"}},
            {id="chase",label="CHASE / COLOR FX",attributes={"int_lane","width","spread","offset","reverse","color_lane"}},
            {id="look",label="LOOK / ORDER",attributes={"move_fx","beam_fx","halo_fx","tube_fx","plates_fx","pixel_fx",
                "chase_fx","order"}},
            {id="strobe",label="STROBE CLOCK",attributes={"strobe_rate","strobe_duty","width","spread","int_lane","reverse"}}}}
end
