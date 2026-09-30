--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local M=get("static_rig")
local Catalog=get("attribute_catalog")
local A: any={choice_epoch=0}
local counts_status: any=nil
local counts_revision: number?=nil
local counts: {[string]:number}={}
local kinds: {[string]:{[number]:boolean}}={}
function A.count(key: string): number
    -- Accepted native replies replace status atomically. The fixture capability
    -- catalog is fixed for this Runtime, so counts stay valid for that reply.
    if counts_status~=M.status or counts_revision~=M.status.revision then
        counts={};kinds={}
        local selected={}
        for _,id in ipairs(M.status.selection) do selected[id]=true end
        for i,f in ipairs(M.fixtures) do if selected[f.id] then
            for attribute in pairs(M.groups[i]) do
                counts[attribute]=(counts[attribute] or 0)+1
                kinds[attribute]=kinds[attribute] or {};kinds[attribute][f.kind]=true
            end
        end end
        counts_status=M.status
        counts_revision=M.status.revision
    end
    return counts[key] or 0
end
-- LOOK codes mean different things per fixture kind: name them for the kinds actually selected.
function A.choice(key: string,attr: any,value: number): string
    local v=math.floor(value+.5)
    if key=="look" then
        A.count(key)
        local k=kinds[key] or {}
        local movers=k[0] or k[3]
        if k[1] and not k[2] and not movers then
            return attr.strobe_choices[v+1] or (if v>=16 and v<48 then attr.choices[v+1] else "PULSE")
        elseif k[2] and not k[1] and not movers then return attr.choices[math.min(v,15)+1]
        elseif movers and not k[1] and not k[2] then return if v<16 then "NO FX" else (attr.choices[v+1] or "?") end
        return "LOOK "..v
    end
    return attr.choices[v+1] or "?"
end
function A.bank(): any
    local bank=Catalog.banks[M.editor_bank.value or 1]
    if #M.status.selection==0 then return bank end
    -- One supported attribute is sufficient. This is called for every readout
    -- and tile; scanning the remaining attributes cannot change the result.
    for _,key in ipairs(bank.attributes) do if A.count(key)>0 then return bank end end
    if #M.status.selection>0 then
        for i,b in ipairs(Catalog.banks) do for _,key in ipairs(b.attributes) do if A.count(key)>0 then M.editor_bank.value=i;return b end end end
    end
    return bank
end
function A.next_bank()
    A.choice_epoch+=1
    local current=M.editor_bank.value or 1
    for offset=1,#Catalog.banks do
        local index=(current+offset-1)%#Catalog.banks+1
        local bank=Catalog.banks[index]
        for _,key in ipairs(bank.attributes) do if A.count(key)>0 or #M.status.selection==0 then
            M.editor_bank.value=index;M.message="BANK: "..bank.label;return
        end end
    end
end
function A.toggle_mode()
    M.editor_absolute.value=1-(M.editor_absolute.value or 0)
    M.message=if M.editor_absolute.value==1 then "ABSOLUTE: same value on selected fixtures" else "RELATIVE: preserve fixture differences"
end
function A.menu(): any
    local items={}
    local descriptions={position="Aim / spread",beam="Zoom / softness",gobo="Pattern / rotation",output="Level / shutter"}
    for index,bank in ipairs(Catalog.banks) do
        table.insert(items,{label=bank.label,description=descriptions[bank.id],
            enabled=function()
                if #M.status.selection==0 then return true end
                for _,key in ipairs(bank.attributes) do if A.count(key)>0 then return true end end
                return false
            end,
            is_selected=function() return A.bank().id==bank.id end,
            on_select=function() A.choice_epoch+=1;M.editor_bank.value=index;M.message="BANK: "..bank.label end})
    end
    return {title="RIG ATTRIBUTE BANK",items=items}
end
function A.encoders(): {any}
    local records={}
    for slot=1,6 do
        local rec: any={key="attribute_encoder_"..slot,label="--",min=0,max=1,default=0,persist="none",fine_step=.1}
        local choice_accum=0
        local choice_context=""
        local function resolve(): (string?,any)
            local key=A.bank().attributes[slot]
            return key,if key then Catalog.attributes[key] else nil
        end
        rec.on_delta=function(delta: number)
            if A.bank().id=="output" and slot==5 then
                if M.reset_held then
                    if not M.reset_used then M.set_colors(1);M.reset_used=true end
                else M.set_colors(math.clamp((M.colors.value or 0)+math.sign(delta),0,1)) end
                return
            end
            local key,attr=resolve()
            if not key or A.count(key)==0 then
                if M.reset_held then M.reset_used=true;M.message="No matching selected attributes" end
                return
            end
            local absolute=M.editor_absolute.value==1 or not attr.relative or A.bank().id=="strobe"
            if M.reset_held then
                choice_accum=0
                if not M.reset_used then
                    local reset=if attr.min<=0 and attr.max>=0 then 0 else attr.default
                    M.request(if absolute then "set" else "reset_selected",{attribute=key,value=reset})
                    M.reset_used=true
                end
                return
            end
            if attr.choices then
                local context=key..":"..A.choice_epoch..":"..table.concat(M.status.selection,",")
                if context~=choice_context or choice_accum*delta<0 then choice_accum=0 end
                choice_context=context
                choice_accum+=delta
                local threshold=attr.choice_ticks or 12
                if math.abs(choice_accum)<threshold then return end
                delta=math.sign(choice_accum)
                choice_accum=math.sign(choice_accum)*math.min(math.abs(choice_accum)-threshold,threshold-1)
            else choice_accum=0;choice_context="" end
            M.request("encoder",{attribute=key,absolute=absolute,value=delta,gesture="attr:"..key,discrete=attr.choices~=nil})
        end
        rec.format=function(): string
            if A.bank().id=="output" and slot==5 then
                rec.label="COLOR SOURCE";rec.no_acceleration=true;rec.fine_step=1
                return if M.colors.value==1 then "GROUPS" else "PALETTE"
            end
            local key,attr=resolve()
            if not key or not attr then rec.label="--";return "--" end
            local count=A.count(key)
            rec.label=attr.label.." "..count.."/"..#M.status.selection
            if A.bank().id=="strobe" then
                rec.label=if key=="width" then "BURST LENGTH" else if key=="spread" then "STAGGER" else attr.label
            end
            rec.min=attr.min;rec.max=attr.max;rec.fine_step=attr.fine;rec.no_acceleration=attr.step~=nil
            if count==0 then return "--" end
            local relative=M.editor_absolute.value~=1 and attr.relative and A.bank().id~="strobe"
            local lo,hi=M.range(key,relative)
            if lo==nil or hi==nil then return "--" end
            if attr.choices then return if math.abs(lo-hi)>.01 then "MIXED" else A.choice(key,attr,lo) end
            if attr.unit=="ratio" or attr.unit=="cycle" then lo*=100;hi*=100 end
            if math.abs(lo)<.00001 then lo=0 end;if math.abs(hi)<.00001 then hi=0 end
            local suffix=if attr.unit=="ratio" or attr.unit=="cycle" then "%" else ""
            return (if math.abs(lo-hi)<.05 then string.format(if relative then "%+.1f" else "%.1f",lo) else string.format("%.1f..%.1f",lo,hi))..suffix
        end
        table.insert(records,rec)
    end
    table.insert(records,M.pitch);table.insert(records,M.master)
    return records
end
return A

end
