// touch.hlsli - Touch's contract: buffer layouts and the layout function, shared by the two
// reducers (hit testing) and the layout pass (drawing), so what is drawn is what is hit.
//
// TWO REDUCERS, ONE EVENT STREAM. Every pass of an events Module sees the same _ViewportEvents
// for a cook. `ink` owns the document (strokes); `observe` owns the diagnostics (log, counters,
// ripples). Each consumes the stream exactly once with ITS OWN watermark, so neither depends on
// the other's output (a later pass reads an earlier pass's buffer a cook late).
//
// Buffers are uint4 in their writers: integer state (sequence numbers, counters) never passes
// through a float register, and floats are stored as asuint() bit patterns, which consumers and
// control outputs read back as ordinary floats.
#ifndef TOUCH_HLSLI
#define TOUCH_HLSLI

#define T_LOG_N     40u
#define T_RIPPLE_N  12u
#define T_INK_N     1024u      // points in the durable ring
#define T_INK_HDR   3u         // header elements before the points
#define T_INK_WORK  (T_INK_HDR + T_INK_N)   // 1027: working state, past the saved range

// ink buffer header (the header and the points are the durable state a save, preset or undo carries)
//   [0] z strokes (monotonic id), w points written (monotonic)
//   [1] x brush px (float bits), y ink 0..3, z fade 0/1, w clock seconds (float bits)
//   [2] published floats (bits): x strokes, y live points, z brush px, w 0
// point i (ring slot): (u, v, code, birth) as float bits; code = width + 64*ink + 256*stroke
// [1027] x last event sequence, y latch bits - NOT saved: restoring an older watermark (a recalled
//        preset, an app undo) would replay every stroke drawn since
#define INK_SLOT(i) (T_INK_HDR + ((i) % T_INK_N))

// observe buffer
#define O_SEQ   0u     // x last sequence, y consumed, z stale skipped, w watermark resets
#define O_CNT   1u     // x pointer moves, y log head, z ripple head, w wheel notches (float bits)
#define O_PUB   2u     // published floats: x consumed, y last u, z last v, w clock
#define O_LOG   4u     // 2 elements per entry: (seq, type|phase<<8|code<<16, mods, value bits) (x bits, y bits, 0, 0)
#define O_RIP   (O_LOG + 2u * T_LOG_N)   // (u bits, v bits, age bits, kind)
#define O_SIZE  (O_RIP + T_RIPPLE_N)     // 96

struct TouchLayout {
    float4 head;
    float4 surface;     // the surface pane
    float4 ink;         // its body: ink coordinates are normalized to THIS rect
    float4 rail;        // the event log pane (when there is room)
    float4 hint;
    bool   hasRail;
};

TouchLayout touchLayout(float2 res, float s)
{
    TouchLayout L;
    float4 r = ilInset(float4(0.0, 0.0, res), 14.0 * s);
    L.head = ilCutTop(r, 34.0 * s);
    r.y += 6.0 * s;
    L.hint = ilCutBottom(r, 28.0 * s);
    r.w -= 8.0 * s;
    float w = r.z - r.x;
    L.hasRail = w > 820.0 * s;
    L.rail = float4(0.0, 0.0, 0.0, 0.0);
    if (L.hasRail)
    {
        L.rail = ilCutRight(r, clamp(0.36 * w, 330.0 * s, 470.0 * s));
        r.z -= 12.0 * s;
    }
    L.surface = r;
    L.ink = float4(r.x + 1.0, r.y + ilSnap(IL_HEADER * s), r.z - 1.0, r.w - 1.0);
    return L;
}

float2 inkToPx(TouchLayout L, float2 uv) { return L.ink.xy + uv * ilSize(L.ink); }
float2 pxToInk(TouchLayout L, float2 px) { return (px - L.ink.xy) / max(ilSize(L.ink), 1.0); }

#endif
