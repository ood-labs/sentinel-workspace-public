--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
local state=host.state
-- Sequencer bank records share the panel's existing persistence engine.
-- Four 16-bit masks per track retain all 64 steps even when length is reduced.
local Pe = get("persist")
local Model = get("sequence_model")
local M = {}

function M.records(): { any }
    local out = {}
    for i = 1, #Model.TRACK_KEYS do
        for word = 1, 4 do
            table.insert(out, { key = "seq_t" .. i .. "_mask" .. word,
                min = 0, max = 65535, default = 0, persist = "bank" })
        end
        table.insert(out, { key = "seq_t" .. i .. "_length", min = 1,
            max = 64, default = 16, persist = "bank" })
        table.insert(out, { key = "seq_t" .. i .. "_mute", min = 0,
            max = 1, default = 0, persist = "bank" })
    end
    return out
end

function M.read(records: { any }, root: string, model: any)
    for i, track in ipairs(model.tracks) do
        for j = 1, 6 do
            local rec = records[(i - 1) * 6 + j]
            local v = tonumber(state.get(root .. "/" .. rec.key)) or rec.default
            v = math.clamp(math.floor(v + 0.5), rec.min, rec.max)
            rec.value = v
            if j <= 4 then track.masks[j] = v
            elseif j == 5 then track.length = v
            else track.muted = v == 1 end
        end
    end
end

function M.write(records: { any }, model: any, track_index: number, now: number)
    local track = model.tracks[track_index]
    for j = 1, 6 do
        local rec = records[(track_index - 1) * 6 + j]
        local v = if j <= 4 then track.masks[j]
            elseif j == 5 then track.length else (if track.muted then 1 else 0)
        if rec.value ~= v then
            rec.value = v
            Pe.publish(rec, now)
        end
    end
end

return M

end
