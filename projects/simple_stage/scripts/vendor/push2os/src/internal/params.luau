--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local sentinel = host.sentinel
local state = host.state
-- Push 2 OS param engine. One record per encoder slot; the engine owns the
-- delta model, the sinks, the readback, and the readout strip.
--
-- A record:
--   key       string, unique within the page
--   label     string, shown in the readout column
--   min, max  number, clamped range (continuous records)
--   step      number, units per detent (detented records)
--   fine_step number, optional unaccelerated continuous units per input tick
--   fmt       string, string.format spec for the value, e.g. "%.2f"
--   values    { string }, present makes the record an enum over indices
--   threshold number, present makes the record detented
--   default   number
--   sink      { kind = "sentinel"|"state"|"script", ... }
--   readback  string, one Sentinel path to poll back
--   persist   "none"|"snapshot"|"state"|"bank"
--   stage     "parked" for an unused slot
--
-- No host-binding work at module top level: `bind` is called from the core,
-- which the root calls from `on_start`.

local C = get("conventions")
local Pe = get("persist")
local W = get("widgets")

local M = {}

local root_prefix = ""
local slots: { any } = {}
local sink_writes = 0

-- `state.register` belongs to `on_start`. `bind` also runs on every tab
-- switch, so a path is registered once per session and remembered here.
local registered: { [string]: boolean } = {}

-- An encoder that is being turned owns its value. An external write is
-- ignored until the turn has been quiet for this long, otherwise a poll that
-- lags the OSC write snaps the value backwards under the operator's hand.
local SNAPBACK_QUIET_S = 0.2

local function path(rel: string): string
    return root_prefix .. "/" .. rel
end

-- Continuous feel. `rate_hz` is how fast detents are arriving and `span` is
-- the record's own max minus min, so the same curve gives an exposure and a
-- haze the same number of turns end to end. See the `ENCODER` comment in
-- `conventions.luau` for why the curve reads a rate rather than a magnitude,
-- and why it has a knee.
--
-- Below the knee the step is exactly `fine_frac` of the range, which is the
-- unaccelerated feel a deliberate hand turn gets. Only the excess over the
-- knee accelerates.
local function scaled_delta(delta: number, rate_hz: number, span: number): number
    local E = C.ENCODER
    local over = math.max(rate_hz - E.accel_knee_hz, 0.0) / E.accel_ref_hz
    local accel = math.min(1.0 + (over ^ E.accel_power) * E.accel_gain,
                           E.accel_max)
    return delta * E.fine_frac * accel * span
end

-- How fast this record's encoder is being turned, in detents per second.
--
-- `event_t` is the event's own timestamp, not the tick clock. The host ticks
-- at 240 Hz and encoder events arrive in bursts far tighter than one tick, so
-- measuring against tick time makes every event after the first in a tick look
-- infinitely fast.
--
-- This is a leaky counter, not a smoothed gap. Each event adds one to a
-- density that decays with time constant `rate_window_s`, and the rate is that
-- density over the window. It is the difference between asking "how far apart
-- were the last two events" and "how many events happened recently", and only
-- the second describes a hand.
--
-- The gap version is what made the first two attempts unusable. The Push 2
-- emits pairs of events tens of microseconds apart even inside a slow turn, so
-- instantaneous gaps peak past 1200 Hz in every captured run regardless of how
-- the knob was actually moving, while the mean rates separate cleanly at 36,
-- 94 and 123. Here one anomalous pair adds one to a density of about nineteen,
-- which is a few percent, instead of pinning the curve.
local function delta_rate_hz(rec: any, event_t: number): number
    local tau = C.ENCODER.rate_window_s
    local last = rec.last_event_t
    local gap = if last ~= nil then event_t - last else -1.0
    if gap <= 0.0 or gap > 2.0 then
        -- A first touch, a knob returned to after a pause, or a clock that
        -- went backwards. One event in the window and nothing before it.
        rec.density = 1.0
    else
        rec.density = (rec.density or 0.0) * math.exp(-gap / tau) + 1.0
    end

    -- `density / tau` is the obvious reading and it is biased high wherever
    -- the gap is an appreciable fraction of the window: a steady 20 Hz turn
    -- reads 25. Inverting the steady state exactly removes that. For a stream
    -- at rate R the density settles at `1 / (1 - exp(-1 / (R * tau)))`, so
    -- solving back for R is one logarithm and costs nothing.
    --
    -- A density of exactly 1 is a single event with nothing before it, which
    -- is a rate of zero rather than a slow turn.
    local d = rec.density
    if d <= 1.0 then
        return 0.0
    end
    return -1.0 / (tau * math.log(1.0 - 1.0 / d))
end

local function format_value(rec: any): string
    if rec.format then return rec.format() end
    if rec.values ~= nil then
        local idx = math.floor(rec.value + 0.5)
        return rec.values[idx + 1] or "?"
    end
    return string.format(rec.fmt or "%.2f", rec.value)
end

-- `math.clamp` raises when max is below min, and a malformed record reaches
-- here from `bind` inside `on_start` and from a snapshot restore. A record
-- that is wrong should render as 0 or as its own floor, not take the panel
-- down at boot, so both degenerate ranges are handled rather than trusted.
local function clamp_record(rec: any)
    if rec.values ~= nil then
        local hi = #rec.values - 1
        if hi < 0 then
            rec.value = 0            -- an empty enum has no valid index
            return
        end
        rec.value = math.clamp(math.floor(rec.value + 0.5), 0, hi)
    else
        local lo = rec.min or 0.0
        local hi = rec.max or 1.0
        if hi < lo then
            rec.value = lo           -- inverted or half-declared range
            return
        end
        rec.value = math.clamp(rec.value, lo, hi)
    end
end

-- Push the record's value at whatever it drives. Called from the 60 Hz
-- service, never from the input handler, so a fast spin costs one write per
-- frame rather than one per MIDI event.
local function flush(rec: any)
    local sink = rec.sink
    if sink == nil then return end

    if sink.kind == "sentinel" then
        for _, p in ipairs(sink.paths) do
            sentinel.set(p, rec.value)
            sink_writes += 1
        end
    elseif sink.kind == "state" then
        state.set(path(sink.path), rec.value)
    elseif sink.kind == "script" and typeof(sink.fn) == "function" then
        pcall(sink.fn, rec.value)
    end
end

-- Start a panel session: one root, no registrations, a fresh write counter.
-- Called once from `on_start` before any page is registered. Within one root
-- the counter stays monotonic, which is what makes it a sink-rate probe.
function M.reset(root: string)
    root_prefix = root
    registered = {}
    sink_writes = 0
    slots = {}
    Pe.reset(root)
end

-- Register the host-side paths and subscriptions one page's records need,
-- without binding them. Runs for EVERY page from inside `on_start`, so no
-- path appears under the panel root later than the first read of it and no
-- readback subscription waits for a tab press.
function M.register_page(page_id: string, records: { any }, root: string)
    root_prefix = root
    for _, rec in ipairs(records) do
        if rec.stage ~= "parked" then
            if rec.sink ~= nil and rec.sink.kind == "state"
               and not registered["reg:" .. rec.sink.path] then
                state.register(rec.sink.path, rec.value)
                registered["reg:" .. rec.sink.path] = true
            end
            -- Subscribe once. The poll cache is what `sentinel.get` reads each
            -- frame; without the subscription it stays empty.
            if rec.readback ~= nil and not registered["sub:" .. rec.readback] then
                sentinel.subscribe(rec.readback, function() end)
                registered["sub:" .. rec.readback] = true
            end
        end
    end
    if not registered["reg:sink_writes"] then
        state.register("sink_writes", 0)
        registered["reg:sink_writes"] = true
    end
    Pe.register_page(page_id, records, root)
end

-- Bind a page's eight records. Runs on every tab switch, so it must be
-- idempotent: a record that already holds a value keeps it, or switching away
-- and back would reset the operator's exposure to the default under their
-- hand. Registration is not repeated here; `register_page` did it at boot.
function M.bind(records: { any }, root: string)
    root_prefix = root
    slots = {}

    for i = 1, C.CELLS do
        local rec = records[i]
        if rec == nil or rec.stage == "parked" then
            slots[i] = { stage = "parked" }
        else
            if rec.value == nil then
                rec.value = rec.default or rec.min or 0.0
            end
            rec.accum = 0.0
            rec.dirty = false
            rec.last_delta_t = -1000.0
            clamp_record(rec)
            slots[i] = rec
        end
    end
    return slots
end

-- One encoder tick. Accumulates only; the write happens on the frame gate.
--
-- Two clocks, deliberately. `now` is the tick clock and drives the snapback
-- window, because that is compared against the frame service. `event_t` is the
-- MIDI event's own timestamp and drives acceleration, because tick resolution
-- is far coarser than the gaps between encoder events. When a caller has no
-- event time, the tick clock stands in and the turn reads as unaccelerated,
-- which errs towards the fine step rather than towards a jump.
function M.on_delta(slot: number, delta: number, now: number, event_t: number?)
    local rec = slots[slot + 1]
    if rec == nil or rec.stage == "parked" then return end

    if rec.threshold ~= nil then
        -- Detented: bank raw units until a full detent is crossed, then step
        -- once. This is what makes an enum land on exactly one value per
        -- click instead of sliding through several.
        rec.accum += delta
        -- A threshold of zero or less never decreases the accumulator, so
        -- both loops below would spin until the host's call budget cut the
        -- handler and latched a module error. Treat it as one raw unit.
        local t = rec.threshold
        if t <= 0 then
            t = 1
        end
        while rec.accum >= t do
            rec.accum -= t
            rec.value += (rec.step or 1)
        end
        while rec.accum <= -t do
            rec.accum += t
            rec.value -= (rec.step or 1)
        end
    else
        local span = (rec.max or 1.0) - (rec.min or 0.0)
        local et = event_t or now
        local feel_span=if rec.fine_step then rec.fine_step/C.ENCODER.fine_frac else span
        local amount=if rec.no_acceleration then delta*(rec.fine_step or 1) else scaled_delta(delta, delta_rate_hz(rec, et), feel_span)
        if rec.on_delta then
            rec.on_delta(amount)
            rec.last_event_t=et
            rec.last_delta_t=now
            return
        end
        rec.value += amount
        rec.last_event_t = et
    end

    clamp_record(rec)
    rec.dirty = true
    rec.last_delta_t = now
end

-- Called once per published frame. Flushes dirty sinks (the 60 Hz gate) and
-- applies readback to records the operator is not currently turning.
function M.service(now: number)
    local wrote = false
    for _, rec in ipairs(slots) do
        if rec.stage ~= "parked" then
            if rec.dirty then
                flush(rec)
                Pe.publish(rec, now)
                rec.dirty = false
                wrote = true
            elseif rec.readback ~= nil
                   and (now - rec.last_delta_t) > SNAPBACK_QUIET_S then
                -- Sentinel reports a float parameter as the JSON string
                -- "1.200000", so the host poll cache hands back a Luau string.
                -- A `typeof(v) == "number"` guard here silently discards every
                -- readback and the column never tracks an external write.
                local v = tonumber(sentinel.get(rec.readback))
                if v ~= nil then
                    rec.value = v
                    clamp_record(rec)
                end
            elseif rec.sink ~= nil and rec.sink.kind == "state"
                   and (now - rec.last_delta_t) > SNAPBACK_QUIET_S then
                -- Presets, cues and other StateTree writers share this path.
                -- Follow them after the encoder quiet period so the displayed
                -- value, next turn and reload snapshot agree with the target.
                local v = state.get(path(rec.sink.path))
                if typeof(v) == "number" and v == v and math.abs(v) < math.huge
                   and v ~= rec.value then
                    local previous = rec.value
                    rec.value = v
                    clamp_record(rec)
                    if rec.value == v then
                        -- State sinks have no mirror: this schedules durability
                        -- without echoing a second write back to the target.
                        Pe.publish(rec, now)
                    else
                        rec.value = previous
                    end
                end
            end
        end
    end
    if wrote then
        state.set(path("sink_writes"), sink_writes)
    end
    Pe.service(now)
end

-- One column per slot: label, formatted value, and a fill bar for records
-- that have a range to show. The drawing itself is the widget kit's, so a
-- page building its own strip in the content band gets identical geometry
-- rather than a second implementation that drifts.
function M.draw_strip()
    local cells: { any } = {}
    for i = 1, C.CELLS do
        local rec = slots[i]
        if rec ~= nil and rec.stage ~= "parked" then
            -- An enum has no range to show, so it gets no bar rather than a
            -- bar over an index nobody reads as a proportion.
            local frac = nil
            if rec.values == nil then
                local lo = rec.min or 0.0
                local hi = rec.max or 1.0
                local span = hi - lo
                frac = span > 0 and ((rec.value - lo) / span) or 0.0
            end
            cells[i] = {
                label = rec.label or rec.key,
                value = format_value(rec),
                frac = frac,
            }
        end
    end
    W.strip(C.READOUT_Y, cells)
end

-- Durability belongs to the persistence module, which derives it from each
-- record's `persist` field. These forwards exist so the core and the root
-- keep talking to one engine about one page's slots.
function M.snapshot(): { [string]: any }
    return Pe.snapshot()
end

function M.flush_bank()
    Pe.flush_ready()
end

function M.restore(saved: { [string]: any })
    Pe.restore(saved, clamp_record)
end

-- Exposed for the offline spec, which cannot reach the host bindings.
M.scaled_delta = scaled_delta
M.delta_rate_hz = delta_rate_hz
M.format_value = format_value

return M

end
