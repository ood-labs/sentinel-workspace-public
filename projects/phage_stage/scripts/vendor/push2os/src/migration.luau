--!strict
-- Public pure migration entry point. Caller preserves source bytes separately;
-- bank schema 1 is a no-op, while legacy reload snapshots become stable-ID v2.
local Restore=require("./restore")
local M={}

function M.prepare(config: any,pages: any,bank: any,saved: any): any
    local plan=Restore.prepare(config,pages,bank,saved)
    if not plan.ok then return plan end
    local values,mappings={},{}
    for _,entry in ipairs(plan.records) do
        if entry.lifetime~="none" then values[entry.id]=entry.value end
    end
    for _,page in ipairs(pages) do
        for _,records in ipairs({page.params or {},page.records or {}}) do
            for _,rec in ipairs(records) do
                if rec.stage=="parked" or (rec.persist or "none")=="none" then continue end
                table.insert(mappings,{from=(page.legacy_id or page.id).."/"..(rec.legacy_key or rec.key or rec.id),
                    to=page.id.."/"..(rec.id or rec.key),lifetime=rec.persist})
            end
        end
    end
    return {ok=true,code="MIGRATION_PREPARED",schema_version=2,
        snapshot={version=2,show_id=config.id,page_id=plan.page_id,values=values},
        report={bank_operation="preserve_original_bytes",bank_schema_version=config.persistence.schema_version,
            snapshot_operation=if saved and saved.version==1 then "legacy_to_stable_ids" else "stable_ids",
            mappings=mappings,backup_required=true}}
end

return M
