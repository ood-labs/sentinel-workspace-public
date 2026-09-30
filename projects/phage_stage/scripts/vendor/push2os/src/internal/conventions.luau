--!strict
-- Private per-runtime factory; canonical source after initial extraction.
return function(host: any, get: any, config: any)
local display = host.display
-- Push 2 OS conventions. Every constant the library and the pages agree on
-- lives here and nowhere else, so a layout change is one edit.
--
-- This module has no host-binding calls at its top level. A required module
-- is cached once and shared by every requirer, so a top-level side effect
-- would belong to whichever root required it first (host Phase 19.1a).

local M = {}
M.INK = get("theme").ink

-- Where an encoder's value goes. Exactly one `kind` per record.
type Sink = {
    kind: string,               -- "sentinel" | "state" | "script"
    paths: { string }?,         -- sentinel: one write per path
    path: string?,              -- state: relative to the panel root
    fn: ((value: number) -> ())?, -- script
}

-- One encoder slot. Every field past `key` is optional because a record is
-- one of several shapes: continuous (min/max/fmt), detented (threshold/step),
-- enum (values), or parked (stage only). One shared type keeps a page's
-- eight-slot array homogeneous, which is what lets the analyzer check it.
type Param = {
    key: string?,
    label: string?,
    min: number?,
    max: number?,
    step: number?,
    fmt: string?,
    values: { string }?,
    threshold: number?,
    default: number?,
    sink: Sink?,
    readback: string?,
    persist: string?,           -- "none" | "snapshot" | "state" | "bank"
    stage: string?,             -- "parked" for an unused slot
    -- The live value, written onto the record by the param engine's `bind`
    -- and by every turn after it. Declared here because a page may read it:
    -- a record is the truth about its own value, and a page that caches a
    -- copy shows a stale one after a snapshot restore, which flushes no sink.
    -- Nil until the record has been bound, so read it with a default.
    value: number?,
}

-- A top-button verb. Every field past `kind` is optional, because the five
-- kinds use different subsets: `trigger` and `toggle` want `on_press`,
-- `hold` wants `hold_s` / `on_fire` / `on_release`, and any of them may
-- report `is_lit`. Declaring one shared shape keeps a page's `top` array
-- homogeneous, which is what the analyzer needs to check it at all.
type Verb = {
    kind: string,
    hold_s: number?,
    on_press: ((slot: number) -> ())?,
    on_fire: ((slot: number) -> ())?,
    on_release: ((slot: number) -> ())?,
    is_lit: (() -> boolean)?,
}

-- Layout bands, in panel pixels. The panel is 960x160.
M.W = 960
M.H = 160
M.TOP_Y = 0
M.TOP_H = 16
M.PAGE_Y = 18
M.PAGE_H = 124
M.BOTTOM_Y = 144
M.BOTTOM_H = 16
M.CELL_W = 120
M.CELLS = 8

-- The readout strip sits at the bottom of the content band, above the tabs.
-- Three rows measured from this top edge: a 6 px bar, then the label, then
-- the value. With `TEXT.label` 9 and `TEXT.value` 17 the value ends at
-- READOUT_Y + 36, which is PAGE_Y + 122, two pixels clear of the bottom of
-- the content band. Any lower and the value glyphs touch the tab labels.
M.READOUT_Y = M.PAGE_Y + 86
M.READOUT_BAR_DY = 0
M.READOUT_LABEL_DY = 8
M.READOUT_VALUE_DY = 19

-- How much of the content band a page may use before the strip starts. A page
-- that draws below this is drawing on the readout.
M.PAGE_CONTENT_H = M.READOUT_Y - M.PAGE_Y

-- Pad LED velocities. Only 0, 1, 122 and 127 are hardware-verified; the rest
-- are provisional until someone has looked at the glass. Do not treat an
-- unverified value as correct because a table somewhere says so.
M.LED = {
    off       = 0,
    dim       = 1,
    armed     = 18,
    alt       = 73,
    releasing = 96,
    active    = 122,
    held      = 127,
}
M.LED_VERIFIED = { [0] = true, [1] = true, [122] = true, [127] = true }

-- Encoder feel. A continuous encoder moves a fraction of the record's own
-- range per detent, so one knob crosses a 0.1 to 3.0 exposure and a 0 to 0.12
-- haze in the same number of turns; an absolute step cannot serve both.
--
-- Acceleration reads how fast detents are ARRIVING, not one event's magnitude.
-- That is forced by the hardware. A Push 2 encoder sends CC 71..78 with data2
-- 1 or 127, meaning plus or minus one detent, and never anything else however
-- hard it is spun. Captured off the wire: sixty consecutive encoder events
-- during a fast spin and a slow creep were all val=1 or val=127. So a curve
-- keyed to magnitude, which is what the LaserViz panel uses, is a constant on
-- this device: its `0.15 * mag + 0.075 * mag * (mag - 1)` is 0.15 for every
-- event the Push 2 can send. That panel has no acceleration at all, which is
-- exactly why it feels controlled, and it is the feel this is anchored to.
--
-- The rate is measured from the MIDI event's own timestamp, not from the tick
-- clock. The host ticks at 240 Hz and encoder events arrive in bursts far
-- tighter than that, two of them 28 microseconds apart in the same capture.
-- Measured against the tick clock every event after the first in a tick reads
-- as an infinitely fast turn and pins the curve at its ceiling, which is what
-- made a small nudge jump the value.
--
-- Acceleration is ON and calibrated from two measured populations, not from
-- an idea of how fast a hand moves. Both were captured with `ctrl_midi
-- list_recent_events` and both live in `capture_spec.luau` as literal gap
-- arrays, so the calibration is checked rather than remembered.
--
--   ordinary turns   estimator reads 30, 56, 104 Hz
--   fast spins       estimator peaks 175 to 234 Hz, seven runs
--
-- The knee sits at 120, above the fastest ordinary turn and below the slowest
-- fast spin, so everything a hand does while adjusting a value is exactly
-- `fine_frac` and only a spin meant as a spin accelerates. The ceiling is 8x
-- and is reached near 230, the top of the captured spins.
--
-- The ramp WIDTH matters as much as the ceiling, and it is what was wrong on
-- the first calibrated attempt. A narrow ramp puts a cliff just above the
-- knee: at `accel_ref_hz` 23 the curve was already 4x by 160, which is a
-- medium turn, so the knob went from precise to unusable across a few detents
-- of extra speed. At 42 that same 160 is 1.9x and the climb is gradual enough
-- to steer with.
--
--   rate    140    160    200    234
--   before  1.8x   4.0x  13.1x  16.0x   (ref 23, ceiling 16)
--   now     1.2x   1.9x   4.6x   8.0x   (ref 42, ceiling 8)
--
-- Replaying the captured spins through the engine: 37 detents covers 12% of a
-- range, 45 covers 22%, 67 covers 20%, while every captured ordinary turn
-- stays at exactly 1.0x. That is deliberately less reach than the steeper
-- curve gave. The operator felt both and chose steerability over reach.
--
-- Getting here took three attempts and the first two failed for the same
-- reason, which is worth stating so it is not repeated. Acceleration was keyed
-- to the gap between the last two events. That gap peaks past 1200 Hz inside
-- EVERY turn a hand makes, including a deliberately slow one, because the
-- Push 2 emits pairs of events microseconds apart. So the signal could not
-- separate a hand from a flick at all, and both attempts shipped a panel where
-- a tenth of a revolution crossed a quarter of a range. `rate_window_s` and
-- the estimator in `params.luau` are the fix: count detents in a decaying
-- window, which is what actually describes a hand.
--
-- To recalibrate: capture both populations again, add them to
-- `capture_spec.luau`, and move the knee to sit between them. Never pick these
-- numbers by reasoning. This hardware is faster than it feels.
--
-- A detented encoder ignores all of this and counts raw units per step.
M.ENCODER = {
    fine_frac      = 0.0015,
    accel_knee_hz  = 120.0,
    accel_ref_hz   = 42.0,
    accel_power    = 2.0,
    accel_gain     = 1.0,
    accel_max      = 8.0,
    rate_window_s  = 0.1,
    detent_default = 3,
    detent_palette = 12,
    detent_slot    = 12,
    detent_enum    = 24,
}

-- Push 2 wire facts. Semantic ids come from the controller profile; the raw
-- numbers are here because the LED batch is sent raw.
M.MIDI = {
    out_port     = config.midi_output_port,
    pad_note_base = 36,          -- note = 36 + row * 8 + col
    top_cc_base   = 102,         -- top.0 .. top.7
    bottom_cc_base = 20,         -- bottom.0 .. bottom.7
    pad_channel    = 1,
    button_channel = 1,
}

-- The frame gate. The host ticks at 240 Hz; the panel publishes at 60.
M.TICK_HZ = 240
M.FRAME_HZ = 60
M.FRAME_INTERVAL = 1.0 / 60.0

-- Verb kinds a top button may declare. `release` events route only to `hold`.
M.VERB_KINDS = {
    trigger = true,
    toggle  = true,
    hold    = true,
    subtab  = true,
    stepper = true,
}

-- The panel's face. Everything on the glass is Blend2D vector text through
-- `display.text_vector`, not the 8x8 bitmap atlas `display.text` draws from.
--
-- The atlas only has integer scale 1, 2 and 3, so its advance is a flat 8, 16
-- or 24 px with no kerning at any of them. That is what made the first panel
-- look like a debug overlay. Vector text takes a real pixel height anywhere in
-- 6..127, so a size can be chosen to fit a band rather than a band widened to
-- fit a bucket.
--
-- JetBrains Mono because the readout row carries live numbers. In a
-- proportional face a value jitters sideways as its digits change width while
-- an encoder is turning; in a monospace face the column stands still. It also
-- makes clipping exact, which the next constant depends on.
M.FONT = {
    face = "jetbrains_mono",
    -- Advance as a fraction of the pixel height. Measured on the panel, not
    -- taken from the font's metadata: twenty capital M were rendered at 12,
    -- 14, 17, 22 and 26 px, the frame captured, and the ink span read off the
    -- image. The five ratios landed on 0.5958, 0.5964, 0.5971, 0.5977 and
    -- 0.5962, each one short of the true pitch by the last glyph's right side
    -- bearing. That is the 0.6 em advance JetBrains Mono documents.
    --
    -- `measure_text` is still deferred host work, so the widget kit clips by
    -- character count. A monospace face is what makes one constant enough.
    advance = 0.6,
}

-- Both text paths truncate at 60 characters at the call boundary
-- (`kTextInlineCap` in the host). Anything that might be longer (an error
-- message, a path) must be trimmed by the caller, tail-first, or the useful
-- end is the part that gets cut.
M.TEXT_MAX = 60

-- Text sizes in real pixels. Five roles rather than three buckets, because
-- the readout row wants a label and a value at different weights and neither
-- is the body size.
M.TEXT = {
    band  = 10,   -- the two 16 px label bands
    label = 9,    -- readout column label
    body  = 14,   -- page body copy
    value = 17,   -- readout column value
    large = 26,   -- page header
}

-- One text call for the whole panel. Nothing outside this module calls
-- `display.text_vector` directly, so the face is chosen in one place and a
-- page cannot accidentally ship in the atlas font.
--
-- This is a host-binding call inside a function, which is allowed. What is
-- forbidden is touching a host binding at module top level, because a
-- required module is cached and shared by every requirer.
function M.text(x: number, y: number, s: string, size: number, rgb: number)
    display.text_vector(x, y, s, size, rgb, M.FONT.face :: any)
end

-- How many characters of `size` fit in `width` pixels.
function M.fits(size: number, width: number): number
    local advance = size * M.FONT.advance
    if advance <= 0 or width <= 0 then
        return 0
    end
    return math.floor(width / advance)
end

-- Clip a string to `width` pixels at `size`, and to the host's own 60
-- character call-boundary limit. Nothing in the kit draws text without going
-- through here.
function M.clip(s: string, size: number, width: number): string
    local n = math.min(M.fits(size, width), M.TEXT_MAX)
    if #s <= n then
        return s
    end
    return string.sub(s, 1, n)
end

function M.cell_x(index: number): number
    return index * M.CELL_W
end

-- Characters of band text that fit one cell. A 120 px cell inset by 6 leaves
-- 114, and at `TEXT.band` the advance is 6 px flat, so 19 fit. Clamped to 14
-- so a long name stops short of the next cell's edge rather than touching it.
-- The atlas advance at the old band size was 8 px, which is why this used to
-- be 8.
M.BAND_CHARS = 14

-- Tab and verb labels are clamped so a long name cannot bleed into the next
-- cell.
function M.clamp_label(s: string, n: number?): string
    local limit = n or M.BAND_CHARS
    if #s <= limit then
        return s
    end
    return string.sub(s, 1, limit)
end

return M

end
