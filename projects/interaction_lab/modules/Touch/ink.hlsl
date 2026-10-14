// Touch / ink - the DOCUMENT reducer (one thread): strokes, brush, ink, fade.
//
// Owns the durable ink ring (a state_buffer, so strokes save with the project and ride undo and
// presets). Consumes the event stream exactly once with its own watermark - see touch.hlsli.
//
//   drag          lay ink: a point when the pointer has moved 2.5 px since the last one; leaving
//                 the surface lifts the pen at the edge, coming back starts a new stroke there
//   double-click  clear (the ring empties; stroke ids keep counting)
//   Backspace     undo the last stroke          C   clear
//   1..4          choose the ink                 Space  toggle fade (latched)
//   wheel         brush width, scaled by the notch amount
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "touch.hlsli"

RWStructuredBuffer<uint4> Ink : register(u0);

uint pointStroke(uint4 p) { return (uint)asfloat(p.z) >> 8; }

// Where the segment from a (on the surface) towards b crosses its edge, in ink units (0..1).
float2 edgeCrossing(float2 a, float2 b)
{
    float2 d = b - a;
    float t = 1.0;
    if (d.x > 0.0) t = min(t, (1.0 - a.x) / d.x); else if (d.x < 0.0) t = min(t, -a.x / d.x);
    if (d.y > 0.0) t = min(t, (1.0 - a.y) / d.y); else if (d.y < 0.0) t = min(t, -a.y / d.y);
    return saturate(a + d * saturate(t));
}

void lay(inout uint written, float2 uv, float code, float clock)
{
    Ink[INK_SLOT(written)] = uint4(asuint(uv.x), asuint(uv.y), asuint(code), asuint(clock));
    written++;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    ILCtx cx = ilCtx(res);
    TouchLayout L = touchLayout(res, cx.s);

    uint4 h0 = Ink[0];
    uint4 h1 = Ink[1];
    uint4 wk = Ink[T_INK_WORK];
    float brush = asfloat(h1.x);
    if (!(brush >= 1.0 && brush <= 48.0)) brush = 6.0;       // first cook (zeros) or garbage
    uint inkSel = h1.y & 3u;
    uint fade = h1.z & 1u;
    float clock = asfloat(h1.w);
    if (!(clock >= 0.0 && clock < 1e7)) clock = 0.0;
    clock += clamp(_DeltaTime, 0.0, 0.1);

    uint latch = wk.y;
    bool dragging = (latch & 0x100u) != 0u;
    bool onSurface = (latch & 0x200u) != 0u;                 // the pen is down on the surface
    float2 lastRaw = float2(asfloat(wk.z), asfloat(wk.w));   // last drag position, unclamped
    uint strokes = h0.z;
    uint written = h0.w;
    uint lastSeq = ilEvWatermark(wk.x);
    uint newest = lastSeq;

    uint n = ilEvCount();
    [loop] for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;          // rule 1: already consumed
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        float2 px = ilEvPx(e, res);
        bool inside = ilIn(px, L.ink);
        float2 raw = pxToInk(L, px);
        float2 uv = saturate(raw);

        if (ilIsPress(e, IL_BTN_LEFT)) lastRaw = raw;            // where the pen touched down
        else if (ilIsDrag(e))
        {
            // The stroke starts at the press, not where the drag was recognised. Off the surface
            // the pen lifts at the edge crossing; back on, a new stroke starts at the crossing - so
            // ink never crawls along the border or chords across the gap.
            float base = round(brush) + 64.0 * (float)inkSel;
            if (e.phase == IL_PH_BEGIN && inside)
            {
                strokes++; dragging = true; onSurface = true;
                float code = base + 256.0 * (float)(strokes & 0xFFFFu);
                bool pressOn = all(lastRaw >= 0.0) && all(lastRaw <= 1.0);
                if (pressOn && length((uv - lastRaw) * ilSize(L.ink)) >= 2.5) lay(written, lastRaw, code, clock);
                lay(written, uv, code, clock);
            }
            else if (dragging && (e.phase == IL_PH_UPDATE || e.phase == IL_PH_END))
            {
                if (inside && !onSurface)
                {
                    strokes++;
                    lay(written, edgeCrossing(raw, lastRaw), base + 256.0 * (float)(strokes & 0xFFFFu), clock);
                    lay(written, uv, base + 256.0 * (float)(strokes & 0xFFFFu), clock);
                }
                else if (!inside && onSurface)
                    lay(written, edgeCrossing(lastRaw, raw), base + 256.0 * (float)(strokes & 0xFFFFu), clock);
                else if (inside)
                {
                    float2 prev = written > 0u ? float2(asfloat(Ink[INK_SLOT(written - 1u)].x), asfloat(Ink[INK_SLOT(written - 1u)].y)) : uv;
                    if (length((uv - prev) * ilSize(L.ink)) >= 2.5 || e.phase == IL_PH_END)
                        lay(written, uv, base + 256.0 * (float)(strokes & 0xFFFFu), clock);
                }
                onSurface = inside;
            }
            lastRaw = raw;
            if (e.phase == IL_PH_END || e.phase == IL_PH_CANCEL) { dragging = false; onSurface = false; }
        }
        else if (ilIsDouble(e) && inside) written = 0u;
        else if (e.type == IL_EV_WHEEL)                          // rule 3: scale by notches
        {
            brush = clamp(brush * pow(1.12, ilWheel(e)), 1.0, 48.0);
        }
        else if (e.type == IL_EV_KEY && e.phase == IL_PH_PRESS && !ilRepeat(e))
        {
            if (e.code >= IL_KEY_0 + 1u && e.code <= IL_KEY_0 + 4u) inkSel = e.code - (IL_KEY_0 + 1u);
            if (e.code == IL_KEY_C) written = 0u;
            if (e.code == IL_KEY_BACKSPACE && written > 0u)
            {
                uint oldest = written > T_INK_N ? written - T_INK_N : 0u;
                uint target = pointStroke(Ink[INK_SLOT(written - 1u)]);
                [loop] for (uint k = 0u; k < T_INK_N && written > oldest; k++)
                {
                    if (pointStroke(Ink[INK_SLOT(written - 1u)]) != target) break;
                    written--;
                }
            }
        }
        bool held = (latch & 1u) != 0u;                          // rule 4: latch the toggle
        if (ilLatch(e, IL_KEY_SPACE, held)) fade ^= 1u;
        latch = (latch & ~1u) | (held ? 1u : 0u);
    }

    latch = (latch & ~0x300u) | (dragging ? 0x100u : 0u) | (onSurface ? 0x200u : 0u);
    Ink[0] = uint4(0u, 0u, strokes, written);
    Ink[T_INK_WORK] = uint4(newest, latch, asuint(lastRaw.x), asuint(lastRaw.y));
    Ink[1] = uint4(asuint(brush), inkSel, fade, asuint(clock));
    Ink[2] = uint4(asuint((float)strokes), asuint((float)min(written, T_INK_N)), asuint(brush), 0u);
}
