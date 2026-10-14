--!strict
-- Pattern Bus - hits sent ahead by the GPU become notes placed exactly in time.
--
-- In   hits   (Event)  Hit records from the Pattern module's EventOut "Hits", each sent 100 ms
--                      BEFORE it is due:  payload = {lane * 128 + note, velocity 1..127, due in s,
--                      ratchet index}
-- Out  notes  (Event)  NoteOn / NoteOff for MIDI Out, stamped with the hit's own due time
--      rate   (Signal) notes per second over the last 4 s, counted
--
-- A frame is 16.7 ms and a sixteenth at 96 bpm is 156 ms: placed on frames, a groove would wobble by
-- a tenth of a step. So the module sends each hit early with how long until it is due, this script
-- turns that into an absolute time (the record's host timestamp + due in), and MIDI Out holds the
-- note until exactly then (+ its fixed latency). The window shows the proof: every note's lead -
-- how far ahead of its due time it arrived - which must stay above zero.
--
-- Control window (open the node's Window): the lead of every note over the last 4 s against the
-- 100 ms the module sends ahead, the lanes with their notes and counts, and Mute.

local EV_NOTEON, EV_NOTEOFF, EV_HIT = 2, 3, 9
local LANES = 6
local RING = 96 -- notes remembered for the window
local WINDOW_S = 4
local LOOKAHEAD_MS = 100 -- what the Pattern module sends ahead (pt.hlsli PT_LOOKAHEAD)
local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local script = {}
script.manifest = {
	name = "Pattern Bus",
	inputs = { { name = "hits", type = "event" } },
	outputs = {
		{ name = "notes", type = "event" },
		{ name = "rate", type = "signal" },
	},
	params = {
		{ name = "gate_ms", type = "float", default = 220, min = 20, max = 2000 },
		{ name = "transpose", type = "int", default = 0, min = -24, max = 24 },
		{ name = "mute", type = "bool", default = false },
	},
}

local function noteName(n: number): string
	return NAMES[n % 12 + 1] .. tostring(math.floor(n / 12) - 1)
end

function script.init(node)
	node.state.offs = {} -- pending note-offs: {note, due (ctx.time s), stamp ns, gen}
	node.state.gen = {} -- per-note retrigger generation
	node.state.held = {} -- notes sounding now
	node.state.rate = 0
	node.state.laneNote = table.create(LANES, -1)
	node.state.laneCount = table.create(LANES, 0)
	node.state.late = 0
	-- every note for the window: arrival (ctx.time), lead ms, lane, velocity; preallocated
	node.state.ring = table.create(RING)
	for i = 1, RING do
		node.state.ring[i] = { t = -1e9, lead = 0, lane = 0, vel = 0, due = -1e9 }
	end
	node.state.ringAt = 0
end

local function drainEdges(node)
	while true do
		local id, kind = ui.next_edge()
		if not id then
			break
		end
		if kind == "press" and id == "mute" then
			node.params.mute = not node.params.mute
		end
	end
end

function script.control_process(node, ctx)
	drainEdges(node)
	local p, st = node.params, node.state
	for _, e in node.inputs.hits:read_events() do
		if e.event_type == EV_HIT and e.payload and not p.mute then
			local code = math.floor(e.payload[1] + 0.5)
			local lane = math.floor(code / 128)
			local note = math.clamp(code % 128 + p.transpose, 0, 127)
			local vel = math.clamp(math.floor(e.payload[2] + 0.5), 1, 127)
			local dueIn = math.max(e.payload[3], 0)
			local at = e.timestamp_ns + dueIn * 1e9 -- when it is due, on the host's clock
			-- a retrigger ends the still-sounding note first (at the new note's time); the generation
			-- makes the old pending off a no-op, so it cannot cut the new note short
			local gen = (st.gen[note] or 0) + 1
			st.gen[note] = gen
			if st.held[note] then
				node.outputs.notes:emit({ event_type = EV_NOTEOFF, timestamp_ns = at, payload = { note, 0 } })
			end
			node.outputs.notes:emit({ event_type = EV_NOTEON, timestamp_ns = at, payload = { note, vel } })
			st.held[note] = true
			table.insert(st.offs, { note, ctx.time + dueIn + p.gate_ms / 1000, at + p.gate_ms * 1e6, gen })
			if lane >= 0 and lane < LANES then
				st.laneNote[lane + 1] = note
				st.laneCount[lane + 1] += 1
			end
			-- the lead: how long before its time the note left here (late if not above zero)
			local lead = dueIn * 1000
			if lead <= 0 then
				st.late += 1
			end
			local k = st.ringAt % RING + 1
			st.ringAt = k
			local r = st.ring[k]
			r.t, r.lead, r.lane, r.vel, r.due = ctx.time, lead, lane, vel, ctx.time + dueIn
		end
	end

	-- note-offs that fell due; one whose note was retriggered since is dropped
	local offs = st.offs
	local i = 1
	while i <= #offs do
		local o = offs[i]
		if ctx.time >= o[2] then
			if st.gen[o[1]] == o[4] then
				node.outputs.notes:emit({ event_type = EV_NOTEOFF, timestamp_ns = o[3], payload = { o[1], 0 } })
				st.held[o[1]] = false
			end
			table.remove(offs, i)
		else
			i += 1
		end
	end

	-- the rate: notes that arrived in the last WINDOW_S, counted from the ring (an average of
	-- played / dt drifts with the tick rate); over the ring's own span once it is full
	local count, oldest = 0, ctx.time
	for k = 1, RING do
		local t = st.ring[k].t
		if ctx.time - t < WINDOW_S then
			count += 1
			oldest = math.min(oldest, t)
		end
	end
	local span = if count >= RING then math.max(ctx.time - oldest, 1e-3) else WINDOW_S
	st.rate = count / span
	node.outputs.rate:set(st.rate)
end

-- ---------------------------------------------------------------------------------------------
-- control window
-- The lab's instrument greys (modules/_shared/plan_theme.hlsli) packed 0xAABBGGRR; amber for the
-- live readings (a note sounding now), red only for a late note.
local INK, MID, DIM, RULE = { 230, 231, 224 }, { 153, 154, 148 }, { 97, 98, 94 }, { 56, 57, 55 }
local WELL, ACCENT, ALARM = { 22, 22, 23 }, { 255, 107, 23 }, { 230, 56, 46 }
local function c(rgb: { number }, a: number?): number
	local A = math.floor(math.clamp(a or 1, 0, 1) * 255 + 0.5)
	return A * 16777216 + rgb[3] * 65536 + rgb[2] * 256 + rgb[1]
end

local Y0 = 74 -- below the title and the pad
local W = 640
local X0, X1 = 56, W - 16 -- time: the last WINDOW_S seconds, now at the right
local LY0, LY1 = Y0 + 186, Y0 + 26 -- lead: 0 .. 125 ms
local LANE_Y = LY0 + 44

function script.render(node, ui)
	local p, st = node.params, node.state
	if not st.ring then
		return
	end
	local now = time.now()
	ui.text("title", "PATTERN BUS  -  hits sent ahead, notes placed on time")
	ui.pad("mute", "Mute", "toggle", if p.mute then "active" else "loaded", "kill", nil, nil, 64, 28)

	-- the lead of every note: how far ahead of its time it arrived
	local function tx(t: number): number
		return X1 - (X1 - X0) * math.clamp((now - t) / WINDOW_S, 0, 1)
	end
	local function ly(lead: number): number
		return LY0 + (LY1 - LY0) * math.clamp(lead / 125, -0.1, 1)
	end
	ui.rect_filled(0, Y0, W, LY0 + 26, c(WELL))
	ui.line(X0, LY0, X1, LY0, c(RULE), 1)
	ui.line(X0, ly(LOOKAHEAD_MS), X1, ly(LOOKAHEAD_MS), c(RULE), 1)
	ui.text_at(4, ly(LOOKAHEAD_MS) - 8, c(DIM), "100 ms")
	ui.text_at(4, LY0 - 8, c(DIM), "due")
	ui.text_at(X0 + 6, LY1 - 20, c(DIM), "lead: how long before its time each note left (late below the line)")
	ui.text_at(X1 - 120, LY0 + 8, c(DIM), string.format("last %d s, now ->", WINDOW_S))
	local lo, hi, sum, n = 1e9, -1e9, 0, 0
	for i = 1, RING do
		local r = st.ring[i]
		local age = now - r.t
		if age >= 0 and age < WINDOW_S then
			local x, y = tx(r.t), ly(r.lead)
			local sounding = now >= r.due and now - r.due < 0.12
			local col = if r.lead <= 0 then c(ALARM) elseif sounding then c(ACCENT) else c(INK, 1 - 0.6 * age / WINDOW_S)
			ui.circle_filled(x, y, 2 + 2.5 * r.vel / 127, col)
			lo, hi, sum, n = math.min(lo, r.lead), math.max(hi, r.lead), sum + r.lead, n + 1
		end
	end

	-- the lanes: their notes and how many each has played
	local cw = W / LANES
	for l = 1, LANES do
		local x = (l - 1) * cw
		local note = st.laneNote[l]
		ui.rect_filled(x + 2, LANE_Y, x + cw - 2, LANE_Y + 40, c(WELL))
		ui.text_at(x + 8, LANE_Y + 4, c(DIM), string.format("lane %d", l))
		ui.text_at(x + 8, LANE_Y + 20, c(if note >= 0 then INK else DIM), if note >= 0 then string.format("%s  x%d", noteName(note), st.laneCount[l]) else "-")
	end
	if n > 0 then
		ui.text_at(0, LANE_Y + 52, c(MID), string.format("lead  min %.1f   mean %.1f   max %.1f ms     late %d     %.1f notes/s     gate %d ms",
			lo, sum / n, hi, st.late, st.rate or 0, p.gate_ms))
	else
		ui.text_at(0, LANE_Y + 52, c(DIM), "no hits yet: press PLAY on the Pattern")
	end
end

return script
