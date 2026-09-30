--!strict
-- Pure preflight. Build a complete initialization plan before touching records
-- or calling host bindings. The Runtime applies it only after ownership claim.
local M = {}

local function result(outcome: string, code: string, context: any?): any
    return {ok=false,outcome=outcome,code=code,context=context or {}}
end

local function valid(rec: any, value: any): boolean
    local kind=rec.value_type or "number"
    if typeof(value)~=kind then return false end
    if kind~="number" then return kind=="string" or kind=="boolean" end
    if value~=value or value==math.huge or value==-math.huge then return false end
    local lo=rec.min or 0
    local hi=rec.max or 1
    if rec.values then lo=0;hi=#rec.values-1 end
    if value<lo or value>hi then return false end
    if rec.values and value%1~=0 then return false end
    return true
end

function M.prepare(config: any, pages: any, bank: any, saved: any): any
    if typeof(bank)~="table" then return result("failed","INVALID_BANK_RESPONSE") end
    if bank.outcome=="pending" then return result("pending",bank.code or "SCAN_PENDING") end
    local newEmpty=config.persistence.new_empty==true and bank.outcome=="absent"
        and bank.code=="GROUP_ABSENT"
    if not newEmpty and (bank.outcome~="restored" or bank.ok~=true) then
        return result(bank.outcome or "failed",bank.code or "BANK_NOT_RESTORED",bank)
    end
    if not newEmpty and (bank.schema_version~=config.persistence.schema_version
        or typeof(bank.values)~="table" or typeof(bank.paths)~="table") then
        return result("incompatible","BANK_SCHEMA_MISMATCH")
    end
    local savedValues, legacy = {}, false
    if saved~=nil then
        if typeof(saved)~="table" then return result("incompatible","SNAPSHOT_INVALID") end
        if saved.version==2 then
            if saved.show_id~=config.id or typeof(saved.values)~="table" then
                return result("incompatible","SNAPSHOT_IDENTITY_MISMATCH")
            end
            savedValues=saved.values
        elseif saved.version==1 and typeof(saved.params)=="table"
            and saved.params.version==1 and typeof(saved.params.values)=="table" then
            savedValues=saved.params.values
            legacy=true
        else
            return result("incompatible","SNAPSHOT_SCHEMA_UNSUPPORTED")
        end
    end
    local plan, claimed, declared = {}, {}, {}
    for _,path in ipairs(bank.paths or {}) do declared[path]=true end
    local selected = pages[1].id
    if saved and not legacy then
        local found=false
        for _,page in ipairs(pages) do if page.id==saved.page_id then found=true;selected=page.id end end
        if not found then return result("incompatible","SNAPSHOT_PAGE_UNKNOWN") end
    elseif saved and legacy then
        -- Legacy page indices require an explicit original order, never the
        -- current descriptor order (which may have changed during adoption).
        local order=config.persistence.legacy_page_ids
        if typeof(order)~="table" or typeof(saved.page)~="number" or saved.page%1~=0 then
            return result("incompatible","LEGACY_PAGE_MAP_REQUIRED")
        end
        selected=order[saved.page+1]
        local found=false
        for _,page in ipairs(pages) do if page.id==selected then found=true end end
        if not found then return result("incompatible","LEGACY_PAGE_UNKNOWN") end
    end
    for _,page in ipairs(pages) do
        for _,records in ipairs({page.params or {},page.records or {}}) do
            for _,rec in ipairs(records) do
                if rec.stage=="parked" then continue end
                local id=page.id.."/"..(rec.id or rec.key)
                local oldId=(page.legacy_id or page.id).."/"..(rec.legacy_key or rec.key or rec.id)
                local lifetime=rec.persist or "none"
                if lifetime~="none" and lifetime~="snapshot" and lifetime~="state" and lifetime~="bank" then
                    return result("incompatible","RECORD_LIFETIME_UNKNOWN",{id=id})
                end
                local value=rec.default
                local bankValue=nil
                if value==nil then value=rec.min or 0 end
                if lifetime=="bank" and not newEmpty then
                    local relative=if rec.sink and rec.sink.kind=="state" then rec.sink.path
                        else rec.state_path or rec.key or rec.id
                    local path=config.root.."/"..relative
                    if not declared[path] or bank.values[path]==nil then
                        return result("incompatible","BANK_RECORD_MISSING",{id=id,path=path})
                    end
                    value=bank.values[path]
                    bankValue=value
                end
                -- Reload snapshots cover in-memory durable edits, including
                -- bank edits inside the save debounce. Legacy snapshots only
                -- carried the snapshot class and never override bank values.
                local key=if legacy then oldId else id
                if saved and lifetime~="none" and (not legacy or lifetime=="snapshot")
                    and savedValues[key]==nil then
                    return result("incompatible","SNAPSHOT_RECORD_MISSING",{id=key})
                end
                if lifetime~="none" and (not legacy or lifetime=="snapshot")
                    and savedValues[key]~=nil then
                    value=savedValues[key]
                    claimed[key]=true
                end
                if not valid(rec,value) then
                    return result("incompatible","RECORD_VALUE_INVALID",{id=id,value=value})
                end
                table.insert(plan,{record=rec,id=id,value=value,lifetime=lifetime,
                    needs_bank_save=lifetime=="bank" and not newEmpty and bankValue~=value})
            end
        end
    end
    for key in pairs(savedValues) do
        if not claimed[key] then return result("incompatible","SNAPSHOT_RECORD_UNKNOWN",{id=key}) end
    end
    return {ok=true,outcome=if newEmpty then "absent" else "restored",code="RESTORE_PLAN_READY",
        records=plan,page_id=selected,new_empty=newEmpty}
end

return M
