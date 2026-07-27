// Shared layout for bands_demo.
//
// The pool is written by `spawn` and read by `render`, so both need the same
// index constants. Anything either pass invents privately is a bug waiting to
// happen the next time one of them is edited alone.

#ifndef BANDS_DEMO_HLSLI
#define BANDS_DEMO_HLSLI

static const uint DM_RINGS    = 32u;   // pool[0..31]  kick rings
static const uint DM_HDR      = 32u;   // (last_kick, last_snare, last_hat, write)
static const uint DM_SNR      = 33u;   // (y_target, y_prev, jump_time, spare)
static const uint DM_INI      = 34u;   // (initialised, spare, spare, spare)

// At most this many rings spawn from one cook.
static const float DM_MAX_SPAWN = 3.0;

// Largest counter jump that can be a real burst of hits rather than a
// bookkeeping event. Refractory caps the fastest lane near 25 hits a second, so
// at any sane frame rate a genuine delta is 0 or 1 and never remotely this
// large. Anything bigger means the drivers just connected, the analyser
// reloaded, or a project was opened — adopt it silently instead of firing it.
//
// This is a THRESHOLD rather than a settling delay on purpose. A delay was
// tried first and does not work: the counts arrive through expressions that
// evaluate whenever they evaluate, comfortably later than any window worth
// waiting, so every load fired one phantom hit on all three lanes.
static const float DM_ADOPT_JUMP = 8.0;

float dmHash(float n) {
    return frac(sin(n * 12.9898) * 43758.5453);
}

// UI unit, same idea as the analyser: one number that every pixel size is a
// multiple of, so this reads correctly whether it is a node preview or a panel.
float dmUI(float H) { return clamp(floor(H / 360.0), 1.0, 4.0); }

#endif
