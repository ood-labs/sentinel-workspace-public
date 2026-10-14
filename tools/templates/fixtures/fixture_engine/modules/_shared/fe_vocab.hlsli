// The fixture engine's vocabulary and caps: the functions a DMX range selects (fn), the attribute kinds a state slot
// holds, the view, colour system, emitter and cell layout codes, and the most of each thing a type may have. These
// are the ids the Fixture Rig node's FixtureRender port carries (gdtf_render.hlsli, layout version 1) and
// scripts/fe_vocab.py lists. They are append-only: never renumber one.
#ifndef FE_VOCAB_HLSLI
#define FE_VOCAB_HLSLI

#define FE_FN_NONE 0
#define FE_FN_VALUE 1
#define FE_FN_CLOSED 2
#define FE_FN_OPEN 3
#define FE_FN_STROBE 4
#define FE_FN_PULSE 5
#define FE_FN_RANDOM 6
#define FE_FN_RAMP_UP 7
#define FE_FN_RAMP_DOWN 8
#define FE_FN_RAMP_UPDOWN 9
#define FE_FN_LIGHTNING 10
#define FE_FN_SPIKES 11
#define FE_FN_SLOT 12
#define FE_FN_SPLIT 13
#define FE_FN_SHAKE 14
#define FE_FN_ROTATE 15
#define FE_FN_RANDOM_SLOT 16
#define FE_FN_STOP 17
#define FE_FN_CONTROL 18
#define FE_FN_INDEX 19
#define FE_FN_SPEED 20
#define FE_FN_KELVIN 21
#define FE_FN_DUV 22
#define FE_FN_MODE 23
#define FE_FN_FADE_TIME 24
#define FE_FN_WAKE_TIME 25

#define FE_KIND_DIMMER 0
#define FE_KIND_RED 1
#define FE_KIND_GREEN 2
#define FE_KIND_BLUE 3
#define FE_KIND_WHITE 4
#define FE_KIND_COOL_WHITE 5
#define FE_KIND_CYAN 6
#define FE_KIND_MAGENTA 7
#define FE_KIND_YELLOW 8
#define FE_KIND_CCT 9
#define FE_KIND_TINT 10
#define FE_KIND_SHUTTER 11
#define FE_KIND_STROBE_RATE 12
#define FE_KIND_STROBE_DURATION 13
#define FE_KIND_STROBE_EFFECT 14
#define FE_KIND_COLOR_WHEEL 15
#define FE_KIND_COLOR_MACRO 16
#define FE_KIND_MACRO 17
#define FE_KIND_MACRO_SPEED 18
#define FE_KIND_FADE 19
#define FE_KIND_FROST 20
#define FE_KIND_ZOOM 21
#define FE_KIND_IRIS 22
#define FE_KIND_FOCUS 23
#define FE_KIND_GOBO 24
#define FE_KIND_GOBO_ROTATE 25
#define FE_KIND_PRISM 26
#define FE_KIND_PRISM_ROTATE 27
#define FE_KIND_PAN 28
#define FE_KIND_TILT 29
#define FE_KIND_FX 30
#define FE_KIND_FX_ADJUST 31
#define FE_KIND_FX_SYNC 32
#define FE_KIND_LAYER_SELECT 33
#define FE_KIND_LAYER_EFFECT 34
#define FE_KIND_LAYER_SPEED 35
#define FE_KIND_LAYER_FADE 36
#define FE_KIND_LAYER_TRANSITION 37
#define FE_KIND_PIXEL_MIX 38
#define FE_KIND_PWM 39
#define FE_KIND_CONTROL 40

#define FE_VIEW_STATIC 0
#define FE_VIEW_DYNAMIC 1

#define FE_COLOUR_RGB 0
#define FE_COLOUR_RGBW 1
#define FE_COLOUR_W 2
#define FE_COLOUR_CW 3
#define FE_COLOUR_CMY_WHITE 4

#define FE_EMITTER_WASH 1
#define FE_EMITTER_BEAM 2
#define FE_EMITTER_STROBE 3
#define FE_EMITTER_BACKLIGHT 4

#define FE_LAYOUT_GRID 0
#define FE_LAYOUT_LINE 1
#define FE_LAYOUT_RING 2
#define FE_LAYOUT_SINGLE 3

// A binding or pan and tilt slot: a state slot, | FE_SLOT_CELLED when it holds one value per emission cell, or
// FE_SLOT_NONE when unbound.
#define FE_SLOT_NONE 65535u
#define FE_SLOT_CELLED 32768u

// The engine's caps, the FixtureRender port's FR_MAX_* (gdtf_render.hlsli): buffer layouts are sized by them, and the
// port's own counts are at most these.
#define FE_EMITTERS_CAP 8u        // emitter records per type
#define FE_CELLS_CAP 128u         // emission cells per fixture
#define FE_PARTS_CAP 4u           // DMX breaks per fixture
#define FE_STATE_CAP 1024u        // state slots per fixture
#define FE_MAX_BODY_PARTS 8u      // body parts per type

#endif
