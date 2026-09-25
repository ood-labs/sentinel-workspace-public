--!strict
-- Push 2 arrows jump Klang_Camera between authored points round the rig, from the camera's own point
-- of view, on every page: left/right step one of 8 orbit positions (the camera moves to its
-- left/right), up/down step through 5 heights (wrapping). Each point has its own aim so the
-- mirror-symmetric rig still gives 40 different pictures; the lens is fitted to the rig per point.
-- Moves cut or glide (eased, round the orbit); taps during a glide stack. GLOBAL top buttons:
-- 2 transition, 3/4 zoom the lens in/out one step, 5 home, 6 save, 7 reset.
-- Operator overrides: fly to a point, adjust the camera by hand in the viewport, press Clip on
-- the Push (or GLOBAL top 6) to save the live camera as that point; top 7 restores the authored one.
return function(host,get)
local M={held={},shown=0,last=nil,glide=nil,col=0,row=2,zoom=2}
M.records={{key="cam_transition",default=3,min=1,max=5,persist="snapshot"},
    -- Saved points: "col.row=x,y,z,tx,ty,tz,fov;..." (fov at zoom 1).
    {key="cam_points",default="",persist="snapshot",value_type="string"}}
local timeR,pointsR=M.records[1],M.records[2]
M.times={0,.5,1,2,4}
-- Camera positions sit on an ellipse inside the hall (36 x 56 m; walls and columns start ~16 m out).
M.RX,M.RZ=15.5,26.5
-- Rows bottom -> top: camera height, share of the ellipse reach, aim height.
M.ROWS={
    {name="UNDER",y=2.2,reach=.5,ty=8.2},   -- under the truss among the crowd, looking up
    {name="LOW",y=3.2,reach=1,ty=6.8},      -- just over heads at the edge of the room
    {name="MID",y=5.6,reach=1,ty=7},        -- below the rig's midline so the spine reads in depth
    {name="HIGH",y=9.8,reach=1,ty=5},       -- below the roof ribs, looking down
    {name="TOP",y=11.8,reach=1,ty=1.5}}     -- from the room edge up in the roof, steeply down into the crowd
-- Columns: orbit angle (0 = front, +z), where on the rig it aims (tx, tz), and small reach/height
-- offsets, so mirrored positions give different pictures: sides look down the length, the back
-- looks toward the front off-centre, diagonals alternate close/low and wide/high.
M.COLS={
    {name="F",az=0,tx=0,tz=0,reach=1,dy=0},
    {name="FL",az=45,tx=-2,tz=4,reach=.85,dy=-.4},
    {name="L",az=90,tx=0,tz=11,reach=1,dy=.5},
    {name="BL",az=135,tx=2,tz=-9,reach=.9,dy=0},
    {name="B",az=180,tx=2.5,tz=10,reach=1,dy=.6},
    {name="BR",az=225,tx=-3,tz=-2,reach=.75,dy=-.3},
    {name="R",az=270,tx=0,tz=-11,reach=1,dy=.3},
    {name="FR",az=315,tx=1.5,tz=8,reach=.95,dy=.2}}
M.ZOOMS={1.3,1,.8,.64,.5}             -- lens multipliers (index 2 = fitted framing)
-- Rig bounding box corners used for lens fitting.
local RIG={}
for _,x in ipairs({-7,7}) do for _,y in ipairs({2.3,11.4}) do for _,z in ipairs({-16.5,16.5}) do
    table.insert(RIG,{x,y,z}) end end end
local ASPECT,MARGIN,FOV_MIN,FOV_MAX=16/9,1.0,34,60  -- tighter lens; near rig ends may crop
local function value(r) return r.value or r.default end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end

-- Point parameters for a cell; glides interpolate these (angle the short way round).
function M.cell(col,row)
    local c,r=M.COLS[col%8+1],M.ROWS[row+1]
    -- UNDER stays between heads and truss (2.2 m): column height offsets only apply to other rows.
    local y=if row==0 then r.y else math.clamp(r.y+c.dy,2,11.9)
    return {az=c.az,reach=r.reach*c.reach,y=y,ty=r.ty,tx=c.tx,tz=c.tz}
end
-- Lens that fits the rig from pos toward target (corners behind the camera are allowed to crop).
function M.fitfov(pos,tgt)
    local f={tgt[1]-pos[1],tgt[2]-pos[2],tgt[3]-pos[3]};local n=math.sqrt(dot(f,f))
    f={f[1]/n,f[2]/n,f[3]/n}
    local h=math.sqrt(f[1]^2+f[3]^2);local r={f[3]/h,0,-f[1]/h}
    local u={r[2]*f[3]-r[3]*f[2],r[3]*f[1]-r[1]*f[3],r[1]*f[2]-r[2]*f[1]}
    local need=0
    for _,p in ipairs(RIG) do
        local v={p[1]-pos[1],p[2]-pos[2],p[3]-pos[3]};local z=dot(v,f)
        if z>1 then need=math.max(need,math.abs(dot(v,u))/z,math.abs(dot(v,r))/z/ASPECT) end
    end
    return math.clamp(2*math.deg(math.atan(need*MARGIN)),FOV_MIN,FOV_MAX)
end
-- Authored camera for a cell, as a resolved pose {ang, rad, y, tx, ty, tz, fov} (fov at zoom 1).
local function authored(col,row)
    local p=M.cell(col,row);local a=math.rad(p.az)
    local pos={math.sin(a)*M.RX*p.reach,p.y,math.cos(a)*M.RZ*p.reach}
    local tgt={p.tx,p.ty,p.tz}
    return {ang=p.az,rad=math.sqrt(pos[1]^2+pos[3]^2),y=pos[2],tx=tgt[1],ty=tgt[2],tz=tgt[3],fov=M.fitfov(pos,tgt)}
end
local cache,cachedText={},nil
function M.saved()
    local text=pointsR.value or pointsR.default
    if text~=cachedText then
        cache={};cachedText=text
        for _,entry in ipairs(string.split(text,";")) do
            local key,vals=string.match(entry,"^(%d+%.%d+)=(.+)$")
            if key then
                local v={};for _,n in ipairs(string.split(vals,",")) do table.insert(v,tonumber(n)) end
                if #v==7 then cache[key]=v end
            end
        end
    end
    return cache
end
local function keyOf(col,row) return col.."."..row end
-- The pose used for a point: the operator's saved camera if there is one, else the authored one.
function M.resolve(col,row)
    local v=M.saved()[keyOf(col,row)]
    if not v then return authored(col,row) end
    return {ang=math.deg(math.atan2(v[1],v[3])),rad=math.sqrt(v[1]^2+v[3]^2),y=v[2],tx=v[4],ty=v[5],tz=v[6],fov=v[7]}
end
function M.camera(p,zoom)
    local a=math.rad(p.ang)
    local pos={math.sin(a)*p.rad,p.y,math.cos(a)*p.rad}
    local dx,dy,dz=p.tx-pos[1],p.ty-pos[2],p.tz-pos[3]
    return {camera_pos_x=pos[1],camera_pos_y=pos[2],camera_pos_z=pos[3],
        camera_target_x=p.tx,camera_target_y=p.ty,camera_target_z=p.tz,
        camera_yaw=math.atan2(dx,dz),camera_pitch=math.atan2(dy,math.sqrt(dx*dx+dz*dz)),
        camera_fov=math.clamp(p.fov*zoom,15,90)}
end
local function param(key) return "/sentinel/pipelines/stagerig_klangrig_Camera/parameters/"..key end
local function write(c)
    for key,v in pairs(c) do host.sentinel.set(param(key),v) end
    M.last=c
end
local function ease(t) return t*t*(3-2*t) end
function M.current()
    local g=M.glide
    if not g then return M.resolve(M.col,M.row),M.ZOOMS[M.zoom] end
    local k=ease(math.min(1,g.t/math.max(g.dur,1e-3)));local p={}
    for key,a in pairs(g.from) do p[key]=a+(g.to[key]-a)*k end
    return p,g.fz+(g.tz-g.fz)*k
end
-- Pick up a camera moved by hand: nearest orbit position and height.
function M.sync()
    local function num(k) return tonumber(host.sentinel.get(param(k))) end
    local x,y,z=num("camera_pos_x"),num("camera_pos_y"),num("camera_pos_z")
    if not (x and y and z) then return end
    if M.last and math.abs(M.last.camera_pos_x-x)+math.abs(M.last.camera_pos_y-y)+math.abs(M.last.camera_pos_z-z)<1e-3 then return end
    local az=math.deg(math.atan2(x/M.RX,z/M.RZ))
    M.col=math.round(((az%360)/45))%8
    local best=0
    for i,r in ipairs(M.ROWS) do if math.abs(r.y-y)<math.abs(M.ROWS[best+1].y-y) then best=i-1 end end
    M.row=best
end
-- Glide (or cut) to the current point from the pose the camera was at before the step changed it.
local function move(fromP,fromZ)
    local toP=M.resolve(M.col,M.row)
    toP.ang=fromP.ang+((toP.ang-fromP.ang+180)%360-180)
    M.shown=1.5
    local dur=M.times[value(timeR)]
    if dur<=0 then M.glide=nil;write(M.camera(M.resolve(M.col,M.row),M.ZOOMS[M.zoom]))
    else M.glide={t=0,dur=dur,from=fromP,to=toP,fz=fromZ,tz=M.ZOOMS[M.zoom]} end
end
-- One arrow / zoom / home step. Steps stack on the pending goal so quick taps add up.
-- A camera adjusted by hand (not yet saved) is re-synced to its nearest point first.
function M.step(dir)
    if not M.glide then M.sync() end
    local fromP,fromZ=M.current()                      -- where the camera is now (mid-glide included)
    if dir=="left" then M.col=(M.col+1)%8              -- left-handed renderer: left = +azimuth
    elseif dir=="right" then M.col=(M.col-1)%8
    elseif dir=="up" then M.row=(M.row+1)%#M.ROWS
    elseif dir=="down" then M.row=(M.row-1)%#M.ROWS
    elseif dir=="in" then M.zoom=math.min(#M.ZOOMS,M.zoom+1)
    elseif dir=="out" then M.zoom=math.max(1,M.zoom-1)
    elseif dir=="home" then M.col,M.row,M.zoom=0,2,2 end
    move(fromP,fromZ)
end
function M.go_home() M.step("home") end
local function store(map)
    local keys={};for k in pairs(map) do table.insert(keys,k) end;table.sort(keys)
    local out={}
    for _,k in ipairs(keys) do
        local cells={}
        for _,n in ipairs(map[k]) do table.insert(cells,string.format("%.3f",n)) end
        table.insert(out,k.."="..table.concat(cells,","))
    end
    pointsR.value=table.concat(out,";")
end
-- Save the live camera (however it was adjusted) as the current point. Its aim is stored as a
-- target 15 m along the view direction; the lens is stored at zoom 1.
function M.save()
    local function num(k) return tonumber(host.sentinel.get(param(k))) end
    local x,y,z=num("camera_pos_x"),num("camera_pos_y"),num("camera_pos_z")
    local yaw,pitch,fov=num("camera_yaw"),num("camera_pitch"),num("camera_fov")
    if not (x and y and z and yaw and pitch and fov) then M.message="CAMERA NOT READY";M.shown=2;return end
    M.glide=nil
    local d={math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)}
    local map=table.clone(M.saved())
    map[keyOf(M.col,M.row)]={x,y,z,x+d[1]*15,y+d[2]*15,z+d[3]*15,fov/M.ZOOMS[M.zoom]}
    store(map)
    M.last={camera_pos_x=x,camera_pos_y=y,camera_pos_z=z}   -- this is now the point: no re-sync
    M.message="SAVED "..M.label();M.shown=2
end
-- Forget the saved camera for the current point and go back to the authored framing.
function M.reset()
    local fromP,fromZ=M.current()
    local map=table.clone(M.saved());map[keyOf(M.col,M.row)]=nil;store(map)
    move(fromP,fromZ);M.message="RESET "..M.label();M.shown=2
end
function M.is_saved(col,row) return M.saved()[keyOf(col,row)]~=nil end
function M.step_time() timeR.value=value(timeR)%#M.times+1 end
function M.time_label()
    local t=M.times[value(timeR)]
    return if t==0 then "CUT" else (if t<1 then string.format("%.1fs",t) else string.format("%ds",t))
end
function M.label() return M.ROWS[M.row+1].name.." "..M.COLS[M.col+1].name end
function M.moving() return M.glide~=nil end
function M.tick(dt)
    local g=M.glide
    if not g then return end
    g.t+=dt
    local p,z=M.current();write(M.camera(p,z))
    if g.t>=g.dur then M.glide=nil end
end

-- The Push 2 profile has no arrow controls, so listen to their raw CCs (channel 1).
local ARROWS={[46]="up",[47]="down",[44]="left",[45]="right"}
local CAPTURE=113                       -- Push 2 "Clip" button (right side, above the arrows): save the camera point
local RETIRED=88                        -- Duplicate, the old save button: keep its LED dark
local DIM,BRIGHT=16,127
local function lights()
    local C=get("conventions");local out={}
    for cc,dir in pairs(ARROWS) do table.insert(out,{kind="cc",channel=1,data1=cc,data2=if M.held[dir] then BRIGHT else DIM}) end
    table.insert(out,{kind="cc",channel=1,data1=CAPTURE,data2=if M.held.capture then BRIGHT else DIM})
    table.insert(out,{kind="cc",channel=1,data1=RETIRED,data2=0})
    pcall(host.midi.send_many,C.MIDI.out_port,out)
end
function M.bind()
    -- Reads of the live camera (hand adjustments) need subscriptions, like other bridge reads.
    for _,key in ipairs({"camera_pos_x","camera_pos_y","camera_pos_z","camera_yaw","camera_pitch","camera_fov"}) do
        pcall(host.sentinel.subscribe,param(key))
    end
    host.midi.on("*Ableton Push 2*","cc",function(ev)
        local dir=ARROWS[ev.data1] or (if ev.data1==CAPTURE then "capture" else nil)
        if dir=="capture" and ev.channel==1 then
            M.held.capture=ev.pressed==true or nil
            if ev.pressed then M.save() end
            lights()
        elseif dir and ev.channel==1 then
            M.held[dir]=ev.pressed==true or nil
            if ev.pressed then M.step(dir) end
            lights()
        end
    end)
    lights()
end
function M.frame(dt)
    M.tick(dt)
    if M.message and M.shown<=0 then M.message=nil end
    if M.moving() or next(M.held)~=nil then M.shown=1.5 elseif M.shown>0 then M.shown-=dt end
end

-- Push 2 only: an orbit panel over the right quarter of the page area (the FULL LOOKS window on
-- RIG), above the encoder readouts, while the camera moves and ~1.5 s after a tap.
local INK,BLUE,DIM_INK,TXT=0x05080C,0x77B9FF,0x24384D,0xE3EAF1
function M.overlay(ctx)
    if M.shown<=0 then return end
    local d,C=host.display,get("conventions")
    local x0,y0,w,h=720,ctx.cy,240,86
    d.rect(x0,y0,w,h,INK,true);d.rect(x0,y0,w,h,BLUE,false)
    local p,z=M.current();local cam=M.camera(p,z)
    -- plan: hall 36 x 56 m, spine, wing bars, the 8 orbit points, camera and its view cone
    local px,py,pw,ph=x0+5,y0+4,52,78
    local function map(x,zz) return px+pw/2+x*pw/36,py+ph/2-zz*ph/56 end
    d.rect(px,py,pw,ph,DIM_INK,false)
    local ax,ay=map(0,16);local bx,by=map(0,-16);d.line(ax,ay,bx,by,TXT,1)
    for _,wx in ipairs({-6,6}) do for _,wz in ipairs({-10,0,10}) do local cx,cy=map(wx,wz);d.line(cx,cy-3,cx,cy+3,TXT,1) end end
    for i=1,#M.COLS do
        local r=M.resolve(i-1,M.row);local a=math.rad(r.ang);local qx,qy=map(math.sin(a)*r.rad,math.cos(a)*r.rad)
        d.rect(qx-1,qy-1,3,3,if i-1==M.col then BLUE else TXT,true)
        if M.is_saved(i-1,M.row) then d.rect(qx-3,qy-3,7,7,BLUE,false) end
    end
    local cx,cy=map(cam.camera_pos_x,cam.camera_pos_z)
    local half=math.atan(math.tan(math.rad(cam.camera_fov/2))*ASPECT)
    for _,s in ipairs({-1,1}) do
        local yaw=cam.camera_yaw+s*half
        local ex,ey=map(cam.camera_pos_x+math.sin(yaw)*14,cam.camera_pos_z+math.cos(yaw)*14)
        d.line(cx,cy,ex,ey,BLUE,1)
    end
    d.rect(cx-2,cy-2,5,5,BLUE,true)
    -- side view: floor, rig block, the 5 heights, camera line to its aim
    local sx,sy,sw,sh=x0+64,y0+4,70,78
    d.rect(sx,sy,sw,sh,DIM_INK,false)
    local function side(hd,y) return sx+6+hd*(sw-12)/28,sy+sh-5-y*(sh-10)/13 end
    local g1x,g1y=side(0,0);local g2x,g2y=side(28,0);d.line(g1x,g1y,g2x,g2y,DIM_INK,1)
    local rx,ry=side(0,11.4);local rx2,ry2=side(1.5,2.3);d.rect(rx,ry,math.max(2,rx2-rx),ry2-ry,TXT,false)
    for i,r in ipairs(M.ROWS) do
        local qx,qy=side(math.min(28,r.reach*M.RZ*.9),r.y)
        d.rect(qx-1,qy-1,3,3,if i-1==M.row then BLUE else TXT,true)
    end
    local flat=math.sqrt(cam.camera_pos_x^2+cam.camera_pos_z^2)
    local camx,camy=side(math.min(28,flat),cam.camera_pos_y);local tx,ty=side(0,cam.camera_target_y)
    d.line(camx,camy,tx,ty,BLUE,1);d.rect(camx-2,camy-2,5,5,BLUE,true)
    -- readout
    local lx=x0+142
    C.text(lx,y0+4,"CAMERA",10,BLUE)
    C.text(lx,y0+20,M.label()..(if M.is_saved(M.col,M.row) then " *" else ""),8,TXT)
    C.text(lx,y0+32,string.format("HEIGHT %2dm",math.floor(cam.camera_pos_y+.5)),8,TXT)
    C.text(lx,y0+44,string.format("LENS %3d",math.floor(cam.camera_fov+.5)),8,TXT)
    C.text(lx,y0+56,string.format("ZOOM %d/%d",M.zoom,#M.ZOOMS),8,TXT)
    local saved=0;for _ in pairs(M.saved()) do saved+=1 end
    C.text(lx,y0+70,M.message or ("MOVE "..M.time_label().."  "..saved.."/40"),8,if M.message then BLUE else TXT)
end
return M
end
