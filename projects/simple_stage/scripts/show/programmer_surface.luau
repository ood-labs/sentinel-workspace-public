--!strict
return function(host,get)
local M=get("static_rig")
local Windows=get("rig_windows")
local C=get("conventions")
local Titles: any=require("@show/preset_titles")
local UI={}
function UI.lit(cell) return M.is_lit(cell.kind,cell.slot) end
-- A sequence pad's name: the operator's (stored from the Push), else the generator's (tools/ss_looks.py).
local function fx_name(kind,slot)
    return M.fx_names[kind.." "..slot] or (Titles[kind] and Titles[kind][slot])
end
function UI.label(cell)
    if M.FX_FAMILIES[cell.kind]~=nil then
        local name=fx_name(cell.kind,cell.slot)
        return if name then string.sub(name,1,10) else string.format("%02d",cell.slot)
    end
    local title=Titles[cell.kind] and Titles[cell.kind][cell.slot]
    return if title then string.format("%02d %s",cell.slot,string.sub(title,1,5)) else string.format("%02d",cell.slot)
end
-- Pad pages: Octave Up / Down step the pads between page 1, the looks (STATIC, EFFECTS, COLOR, FULL), and page 2, the
-- SEQUENCES (RIG, BEAMS, STROBES, BATTENS). Each page has its own windows; the other page's windows claim no pads,
-- draw nothing and take no presses. A sequence bank has 16 slots, as many as its 4 x 4 window holds: empty slots show
-- the bank's dim colour, stored ones its bright colour, the live one bright white.
local colors={static=0x67D4C0,effects=0xB889EF,color=0xF1AE60,complete=0x77B9FF,
    sequence=0x77B9FF,seq_heads=0x67D4C0,seq_strobes=0xB889EF,seq_battens=0xE8C46A}
local velocities={static={13,14},effects={24,25},color={9,10},complete={41,45},
    sequence={41,45},seq_heads={13,14},seq_strobes={24,25},seq_battens={9,10}}
local names={complete="FULL LOOKS",sequence="RIG SEQUENCES",seq_heads="BEAMS SEQ",seq_strobes="STROBES SEQ",
    seq_battens="BATTENS SEQ"}
local PAGES={"PADS 1: LOOKS","PADS 2: SEQUENCES (RIG = every type; the same slot on each is the same moment)"}
local LIVE=122                              -- bright white: the fixture preset running now
-- A sequence bank's bottom-right pad (slot 16) blacks its types out: red (palette 127) like the desk's BLACKOUT, white
-- while it is up. Only while the slot holds the generated BLACKOUT, not a pad stored over it.
local BLACKOUT={color=0xE5554F,off=127,on=LIVE}
UI.windows={}
function UI.bank(id,root,col,kind,row,width,height,padPage)
    local count=16
    local cells={}
    for slot=1,count do
        table.insert(cells,{slot=slot,kind=kind})
    end
    local w=Windows.make({id=id,name=names[kind] or string.upper(kind),color=colors[kind],off=velocities[kind][1],
            on=velocities[kind][2],row=row,col=col,width=width,height=height,cells=cells},
        root,UI.lit,function(cell,pressed) if pressed then M.preset_kind=cell.kind;M.recall(cell.slot) end end,
        function(cell)
            if cell.slot==16 and M.FX_STATIC[cell.kind] then
                local dark=M.fx_names[cell.kind.." 16"]==nil and Titles[cell.kind] and Titles[cell.kind][16]=="BLACKOUT"
                cell.color=if dark then BLACKOUT.color else nil
                if dark then return if UI.lit(cell) then BLACKOUT.on else BLACKOUT.off end
            end
            if cell.on then return if UI.lit(cell) then cell.on else cell.off end
            if M.FX_FAMILIES[cell.kind]==nil then return nil end
            if UI.lit(cell) then return LIVE end
            return if fx_name(cell.kind,cell.slot) then velocities[cell.kind][2] else velocities[cell.kind][1]
        end)
    w.pad_page=padPage or 1
    -- The sequence page's window geometry is session-only: a new durable record would make push2os refuse every saved
    -- Surface snapshot that predates it (SNAPSHOT_RECORD_MISSING / BANK_RECORD_MISSING), losing the operator's state.
    -- The records live in memory, marked dirty so the desktop's per-frame read from state never resets them.
    if w.pad_page~=1 then
        for _,rec in ipairs({w.width,w.height,w.row,w.col,w.pin,w.z}) do rec.persist="none";rec.value=rec.default;rec.dirty=true end
    end
    local refresh=w.refresh
    w.refresh=function()
        if M.FX_FAMILIES[kind]~=nil then
            -- Auto size: the stored slots plus at least one free one, in rows of 4.
            local top=0
            for n in pairs(Titles[kind] or {}) do top=math.max(top,n) end
            for name in pairs(M.fx_names) do
                local k,n=string.match(name,"^([%a_]+) (%d+)$")
                if k==kind then top=math.max(top,tonumber(n) or 0) end
            end
            w.spec.height=math.clamp(math.ceil((top+1)/4),1,4)
        end
        refresh()
        if w.pad_page~=M.pad_page then w.rect=nil;w.pixels={};w.mapping={} end
    end
    table.insert(UI.windows,w)
    return w
end
function UI.visible()
    local out={};for _,w in ipairs(UI.windows) do if w.pad_page==M.pad_page then table.insert(out,w) end end
    return out
end
function UI.set_page(n)
    M.pad_page=math.clamp(n,1,#PAGES)
    M.message=PAGES[M.pad_page]
end
local OCT_DOWN,OCT_UP=54,55
-- Lit bright while there is a page that way.
function UI.lights()
    local out={{kind="cc",channel=1,data1=OCT_UP,data2=if M.pad_page<#PAGES then 127 else 16},
               {kind="cc",channel=1,data1=OCT_DOWN,data2=if M.pad_page>1 then 127 else 16}}
    pcall(host.midi.send_many,C.MIDI.out_port,out)
end
function UI.bind()
    if UI.bound then return end;UI.bound=true
    host.midi.on("*Ableton Push 2*","cc",function(ev)
        if ev.channel==1 and ev.pressed and (ev.data1==OCT_UP or ev.data1==OCT_DOWN) then
            UI.set_page(M.pad_page+(if ev.data1==OCT_UP then 1 else -1));UI.lights()
        end
    end)
    UI.lights()
end
function UI.status(ctx) C.text(12,ctx.cy+72,#(M.status.fixtures or {}).." selected in LIGHTING / "..M.message,10,0xE3EAF1) end
return UI
end
