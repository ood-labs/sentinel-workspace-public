--!strict
-- Control Atoms - four signal generators on the 240 Hz control clock, and a desk to play them.
--
-- Out  lfo   (Signal) 0..1  oscillator: shape, rate, depth. The phase is integrated, so turning the
--                           rate bends the wave and never jumps it
--      env   (Signal) 0..1  ADSR envelope. Gated by the desk's Gate pad (hold it), and by the LFO
--                           while LFO Gate is on (high while the wave is above its midline)
--      sh    (Signal) 0..1  sample and hold: a new value on its own clock, of noise or of the LFO
--      slew  (Signal) 0..1  the S&H through a slew limiter (rise and fall: seconds per full scale)
--      gate  (Signal) 0/1   the envelope's gate
--
-- Every output publishes at /sentinel/pipelines/<node>/control_outputs/<name>. A ref() expression
-- reads it once per frame, which is how the Scope's probes (and any parameter) follow it.
--
-- Control window: one knob per shaping value (Alt drags fine, double-click resets), pads for the
-- discrete choices, and a drawn preview of what the knobs define - one LFO cycle, the ADSR
-- contour and the slew response - with a marker riding each at its live position.

local SHAPES = { "Sine", "Triangle", "Saw", "Square" }
local SOURCES = { "Noise", "LFO" }

local IDLE, ATTACK, DECAY, SUSTAIN, RELEASE = 0, 1, 2, 3, 4
local HOLD_SHOWN_S = 0.4 -- the sustain segment's width in the ADSR preview

local script = {}
script.manifest = {
	name = "Control Atoms",
	outputs = {
		{ name = "lfo", type = "signal" },
		{ name = "env", type = "signal" },
		{ name = "sh", type = "signal" },
		{ name = "slew", type = "signal" },
		{ name = "gate", type = "signal" },
	},
	params = {
		{ name = "lfo_shape", type = "enum", values = SHAPES, default = "Sine" },
		{ name = "lfo_rate", type = "float", default = 0.5, min = 0.05, max = 6 },
		{ name = "lfo_depth", type = "float", default = 1, min = 0, max = 1 },
		{ name = "lfo_gate", type = "bool", default = true },
		{ name = "env_attack", type = "float", default = 0.08, min = 0.002, max = 2 },
		{ name = "env_decay", type = "float", default = 0.35, min = 0.01, max = 2 },
		{ name = "env_sustain", type = "float", default = 0.55, min = 0, max = 1 },
		{ name = "env_release", type = "float", default = 0.5, min = 0.01, max = 4 },
		{ name = "sh_source", type = "enum", values = SOURCES, default = "Noise" },
		{ name = "sh_rate", type = "float", default = 2, min = 0.1, max = 20 },
		{ name = "slew_rise", type = "float", default = 0.3, min = 0, max = 2 },
		{ name = "slew_fall", type = "float", default = 0.8, min = 0, max = 2 },
	},
}

local function indexOf(list: { string }, v: any): number
	if type(v) == "number" then
		return math.clamp(math.floor(v) + 1, 1, #list)
	end
	for i, s in ipairs(list) do
		if s == v then
			return i
		end
	end
	return 1
end

-- one cycle, phase 0..1 -> 0..1
local function wave(shape: number, ph: number): number
	if shape == 1 then
		return 0.5 + 0.5 * math.sin(2 * math.pi * ph)
	elseif shape == 2 then
		return 1 - math.abs(2 * ((ph + 0.25) % 1) - 1)
	elseif shape == 3 then
		return ph
	end
	return if ph < 0.5 then 1 else 0
end

-- xorshift32: the same noise after every reload, no shared global state
local function rand(st): number
	local x = st.seed
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	st.seed = x
	return x / 4294967296
end

function script.init(node)
	local st = node.state
	st.phase, st.raw, st.lfo = 0, 0.5, 0.5
	st.level, st.stage, st.stageT, st.gate, st.pad = 0, IDLE, 0, false, false
	st.shPhase, st.sh, st.slew = 0, 0.5, 0.5
	st.seed = 0x2545F491
	st.preview = table.create(48)
	for i = 1, 48 do
		st.preview[i] = { 0, 0 }
	end
	st.contour = table.create(40)
	for i = 1, 40 do
		st.contour[i] = { 0, 0 }
	end
end

-- the desk's pads, applied on the control tick
local function drainEdges(node)
	local st = node.state
	while true do
		local id, kind = ui.next_edge()
		if not id then
			break
		end
		if id == "gate" then
			st.pad = kind == "press"
		elseif kind == "press" then
			local shape = tonumber(string.match(id, "^shape(%d)$"))
			local source = tonumber(string.match(id, "^src(%d)$"))
			if shape then
				node.params.lfo_shape = SHAPES[shape]
			elseif source then
				node.params.sh_source = SOURCES[source]
			elseif id == "lfogate" then
				node.params.lfo_gate = not node.params.lfo_gate
			end
		end
	end
end

function script.control_process(node, ctx)
	drainEdges(node)
	local p, st = node.params, node.state
	local dt = ctx.dt

	-- LFO
	st.phase = (st.phase + p.lfo_rate * dt) % 1
	st.raw = wave(indexOf(SHAPES, p.lfo_shape), st.phase)
	st.lfo = 0.5 + (st.raw - 0.5) * p.lfo_depth

	-- ADSR: attack is a linear ramp, decay and release are exponential (about 98% done in their
	-- time); a new gate restarts the attack from the current level, so retriggers never click
	local gate = st.pad or (p.lfo_gate and st.raw >= 0.5)
	if gate and not st.gate then
		st.stage, st.stageT = ATTACK, 0
	elseif not gate and st.gate and st.stage ~= IDLE then
		st.stage, st.stageT = RELEASE, 0
	end
	st.gate = gate
	st.stageT += dt
	if st.stage == ATTACK then
		st.level += dt / p.env_attack
		if st.level >= 1 then
			st.level, st.stage, st.stageT = 1, DECAY, 0
		end
	elseif st.stage == DECAY then
		st.level = p.env_sustain + (st.level - p.env_sustain) * math.exp(-4 * dt / p.env_decay)
		if math.abs(st.level - p.env_sustain) < 1e-3 then
			st.stage, st.stageT = SUSTAIN, 0
		end
	elseif st.stage == SUSTAIN then
		st.level = p.env_sustain
	elseif st.stage == RELEASE then
		st.level *= math.exp(-4 * dt / p.env_release)
		if st.level < 1e-4 then
			st.level, st.stage, st.stageT = 0, IDLE, 0
		end
	end

	-- sample and hold
	st.shPhase += p.sh_rate * dt
	if st.shPhase >= 1 then
		st.shPhase %= 1
		st.sh = if indexOf(SOURCES, p.sh_source) == 2 then st.lfo else rand(st)
	end

	-- slew limiter: at most one full scale per rise (or fall) seconds
	local up, down = dt / math.max(p.slew_rise, 1e-4), dt / math.max(p.slew_fall, 1e-4)
	st.slew = if st.sh > st.slew then math.min(st.sh, st.slew + up) else math.max(st.sh, st.slew - down)

	node.outputs.lfo:set(st.lfo)
	node.outputs.env:set(st.level)
	node.outputs.sh:set(st.sh)
	node.outputs.slew:set(st.slew)
	node.outputs.gate:set(if gate then 1 else 0)
end

-- ---------------------------------------------------------------------------------------------
-- control window
-- The lab's instrument greys (modules/_shared/plan_theme.hlsli) packed 0xAABBGGRR. Amber marks only
-- live positions: where each atom is right now.
local INK, MID, DIM, RULE = { 230, 231, 224 }, { 153, 154, 148 }, { 97, 98, 94 }, { 56, 57, 55 }
local WELL, ACCENT = { 22, 22, 23 }, { 255, 107, 23 }
local function c(rgb: { number }, a: number?): number
	local A = math.floor(math.clamp(a or 1, 0, 1) * 255 + 0.5)
	return A * 16777216 + rgb[3] * 65536 + rgb[2] * 256 + rgb[1]
end

-- Layout. Widgets (knobs, pads, grid cells) and text are scaled with the UI; draw positions are raw
-- pixels, and a script cannot read the scale. So the two never share a row, and drawn text never
-- sits beside other drawn text. The drawn monitor band comes first; a spacer grid of the same height
-- (in widget units) pushes the widgets below it: exact at 100% scale, a gap above that. A pad in a
-- grid cell takes the cell's width.
local BAND_H = 150
local PY, PH = 26, 92 -- preview boxes
local BOX = { lfo = { 0, 220 }, env = { 236, 556 }, sh = { 572, 812 } }
local CELL, GAP = 58, 6 -- 10 columns: LFO 1-2, envelope 3-6, S&H 7-8, slew 9-10

local function box(b: { number }, title: string, value: string)
	ui.rect_filled(b[1], PY, b[2], PY + PH, c(WELL))
	ui.text_at(b[1] + 8, PY + 5, c(DIM), title)
	ui.text_at(b[1] + 2, PY + PH + 5, c(MID), value) -- under its own box
end

function script.render(node, ui)
	local p, st = node.params, node.state
	if not st.preview then
		return
	end
	local shape = indexOf(SHAPES, p.lfo_shape)
	local source = indexOf(SOURCES, p.sh_source)
	local top, bottom = PY + 30, PY + PH - 8
	local function ly(v: number): number
		return bottom - (bottom - top) * v
	end

	ui.text_at(0, 0, c(MID), "CONTROL ATOMS  -  four signals on the 240 Hz control clock")

	-- LFO: one cycle at the current shape and depth; the marker rides the live phase
	local b = BOX.lfo
	box(b, "LFO", string.format("lfo %.2f", st.lfo))
	local x0, x1 = b[1] + 8, b[2] - 8
	ui.line(x0, ly(0.5), x1, ly(0.5), c(RULE), 1)
	local pts = st.preview
	for i = 1, 48 do
		local ph = (i - 1) / 47
		pts[i][1], pts[i][2] = x0 + (x1 - x0) * ph, ly(0.5 + (wave(shape, ph) - 0.5) * p.lfo_depth)
	end
	ui.polyline(pts, c(MID), 1.5)
	ui.circle_filled(x0 + (x1 - x0) * st.phase, ly(st.lfo), 4, c(ACCENT))

	-- ADSR: attack, decay, a held sustain, release - to time scale; the marker is the live stage
	b = BOX.env
	box(b, "ENVELOPE", string.format("env %.2f   %s", st.level, if st.gate then "gate on" else "gate off"))
	x0, x1 = b[1] + 8, b[2] - 8
	local A, D, S, R = p.env_attack, p.env_decay, p.env_sustain, p.env_release
	local T = A + D + HOLD_SHOWN_S + R
	local function tx(tt: number): number
		return x0 + (x1 - x0) * tt / T
	end
	local k = st.contour
	k[1][1], k[1][2] = tx(0), ly(0)
	k[2][1], k[2][2] = tx(A), ly(1)
	for i = 0, 15 do
		local tt = D * i / 15
		k[3 + i][1], k[3 + i][2] = tx(A + tt), ly(S + (1 - S) * math.exp(-4 * tt / D))
	end
	k[19][1], k[19][2] = tx(A + D + HOLD_SHOWN_S), ly(S)
	for i = 0, 15 do
		local tt = R * i / 15
		k[20 + i][1], k[20 + i][2] = tx(A + D + HOLD_SHOWN_S + tt), ly(S * math.exp(-4 * tt / R))
	end
	for i = 36, 40 do
		k[i][1], k[i][2] = k[35][1], k[35][2]
	end
	ui.polyline(k, c(MID), 1.5)
	if st.stage ~= IDLE then
		local at = if st.stage == ATTACK then A * st.level
			elseif st.stage == DECAY then A + math.min(st.stageT, D)
			elseif st.stage == SUSTAIN then A + D + 0.5 * HOLD_SHOWN_S
			else A + D + HOLD_SHOWN_S + math.min(st.stageT, R)
		ui.circle_filled(tx(at), ly(st.level), 4, c(ACCENT))
	end

	-- S&H into slew: the held value (ring) and the limited value chasing it (dot) on one scale,
	-- beside the limiter's full-scale step response
	b = BOX.sh
	box(b, "S&H > SLEW", string.format("s&h %.2f   slew %.2f", st.sh, st.slew))
	local gx = b[1] + 20
	ui.line(gx, top, gx, bottom, c(RULE), 1)
	ui.circle(gx, ly(st.sh), 5, c(INK), 1.5)
	ui.circle_filled(gx, ly(st.slew), 4, c(ACCENT))
	local r0, r1 = b[1] + 44, b[2] - 8
	local span = p.slew_rise + p.slew_fall + 0.5
	local function rx(tt: number): number
		return r0 + (r1 - r0) * tt / span
	end
	ui.polyline({ { rx(0), ly(0) }, { rx(p.slew_rise), ly(1) }, { rx(p.slew_rise + 0.5), ly(1) },
		{ rx(p.slew_rise + 0.5 + p.slew_fall), ly(0) } }, c(MID), 1.5)

	-- the widgets, below the band
	ui.grid_begin("band", 1, 1, 8, BAND_H, 0, 0)
	ui.grid_cell(1, 1)
	ui.text("band_spacer", " ")
	ui.grid_end()

	ui.grid_begin("heads", 10, 1, CELL, 18, GAP, 0)
	ui.grid_cell(1, 1)
	ui.text("h_lfo", "LFO")
	ui.grid_cell(3, 1)
	ui.text("h_env", "ENVELOPE")
	ui.grid_cell(7, 1)
	ui.text("h_sh", "S&H")
	ui.grid_cell(9, 1)
	ui.text("h_slew", "SLEW")
	ui.grid_end()

	ui.grid_begin("knobs", 10, 1, CELL, 92, GAP, 0)
	local function knob(col: number, id: string, label: string, name: string, default: number, lo: number, hi: number)
		ui.grid_cell(col, 1) -- cells are 1-based
		local changed, v = ui.knob(id, label, (p :: any)[name], default, lo, hi, 46)
		if changed then
			(node.params :: any)[name] = v
		end
	end
	knob(1, "k_rate", "Rate Hz", "lfo_rate", 0.5, 0.05, 6)
	knob(2, "k_depth", "Depth", "lfo_depth", 1, 0, 1)
	knob(3, "k_a", "Attack s", "env_attack", 0.08, 0.002, 2)
	knob(4, "k_d", "Decay s", "env_decay", 0.35, 0.01, 2)
	knob(5, "k_s", "Sustain", "env_sustain", 0.55, 0, 1)
	knob(6, "k_r", "Release s", "env_release", 0.5, 0.01, 4)
	knob(7, "k_shrate", "Rate Hz", "sh_rate", 2, 0.1, 20)
	knob(9, "k_rise", "Rise s", "slew_rise", 0.3, 0, 2)
	knob(10, "k_fall", "Fall s", "slew_fall", 0.8, 0, 2)
	ui.grid_end()

	-- pads under their atoms: the LFO's four shapes as a 2 x 2 block
	ui.grid_begin("pads", 10, 2, CELL, 26, GAP, 4)
	for i = 1, 4 do
		ui.grid_cell(1 + (i - 1) % 2, 1 + (i - 1) // 2)
		ui.pad("shape" .. i, SHAPES[i], "radio", if i == shape then "selected" else "loaded", "neutral")
	end
	ui.grid_cell(3, 1)
	ui.pad("gate", "Gate", "momentary", if st.pad then "active" else "loaded", "go")
	ui.grid_cell(4, 1)
	ui.pad("lfogate", "by LFO", "toggle", if p.lfo_gate then "active" else "loaded", "link")
	for i = 1, 2 do
		ui.grid_cell(6 + i, 1)
		ui.pad("src" .. i, SOURCES[i], "radio", if i == source then "selected" else "loaded", "neutral")
	end
	ui.grid_end()
end

return script
