--!strict
-- Show-owned per-Runtime factory; Phase 5 compatibility conversion.
return function(host: any,get: any,config: any)
-- Musical pattern and playback only. No hardware, layout, or host bindings.
local M = {}
M.TRACK_NAMES = { "KICK", "SNARE", "HI-HAT", "TOM", "CLAP", "PERC 1", "PERC 2", "AUX" }
M.TRACK_KEYS = { "kick", "snare", "hihat", "tom", "clap", "perc1", "perc2", "aux" }

function M.new(): any
    local tracks = {}
    for i, name in ipairs(M.TRACK_NAMES) do
        tracks[i] = { name = name, length = 16, muted = false,
            masks = { 0, 0, 0, 0 }, step = 0, gate = 0, env = 0, hits = 0 }
    end
    return { tracks = tracks, last_tick = nil, last_beat = nil, rate = nil,
        running = false, track_count = 3, skipped = 0 }
end

function M.enabled(track: any, step: number): boolean
    if step < 0 or step >= 64 then return false end
    local word = math.floor(step / 16) + 1
    return bit32.band(track.masks[word], bit32.lshift(1, step % 16)) ~= 0
end

function M.toggle(track: any, step: number): boolean
    if step < 0 or step >= track.length or step % 1 ~= 0 then return false end
    local word = math.floor(step / 16) + 1
    track.masks[word] = bit32.bxor(track.masks[word], bit32.lshift(1, step % 16))
    return true
end

-- beat is TempoClock's continuous quarter-note count. Editing or relayout
-- cannot retrigger the current step. Backward seeks/rate changes re-anchor;
-- long stalls skip old hits rather than emitting an unbounded burst.
function M.advance(model: any, beat: number, running: boolean, rate: number,
                   dt: number, decay: number)
    local tick = math.floor(math.max(0, beat) * rate + 1e-7)
    local changed_rate = model.rate ~= nil and model.rate ~= rate
    local backwards = model.last_beat ~= nil and beat < model.last_beat - 1e-7
    local first = model.last_tick == nil
    local delta = if first then 0 else tick - model.last_tick
    if backwards or changed_rate then model.last_trigger_tick = nil end
    local ticks = {}
    if running then
        if (first and beat * rate % 1 < 1e-6) or backwards or changed_rate then
            table.insert(ticks, tick)
        elseif delta > 0 and delta <= 8 then
            for at = model.last_tick + 1, tick do table.insert(ticks, at) end
        elseif delta > 8 then
            model.skipped += delta - 1
            table.insert(ticks, tick)
        elseif not model.running and beat * rate % 1 < 1e-6
            and model.last_trigger_tick ~= tick then
            table.insert(ticks, tick)
        end
    end
    for i, track in ipairs(model.tracks) do
        track.step = tick % track.length
        track.gate = 0
        if not running or track.muted or i > model.track_count then
            track.env = 0
        else
            track.env = math.max(0, track.env - dt / math.max(decay, 0.01))
            for _, at in ipairs(ticks) do
                if M.enabled(track, at % track.length) then
                    track.hits += 1
                    local age_beats = math.max(0, beat - at / rate)
                    -- A caught-up hit counts but is not presented as a fresh
                    -- full-level hit. The page supplies seconds per beat.
                    local age = age_beats * (model.seconds_per_beat or 0.5)
                    track.env = math.max(track.env, math.max(0, 1 - age / decay))
                    if at == tick then track.gate = 1 end
                end
            end
        end
    end
    model.last_tick = tick
    model.last_beat = beat
    model.rate = rate
    model.running = running
    if #ticks > 0 then model.last_trigger_tick = tick end
end

return M

end
