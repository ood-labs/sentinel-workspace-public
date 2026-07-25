// CRYOGRAM / CONSOLE — event reduction for the tension gate.
//
// Probe authoring lives on the specimen preview, where a click is already a
// field coordinate. What remains here is the one interaction the console is
// genuinely better at: a coupled two-axis gate over the lattice, where bond
// radius and eligibility are chosen TOGETHER against a visible field. Two
// separate Properties sliders cannot express that trade-off.
//
// Header (index 32) carries gate state and publishes the control outputs.

#include "layout.hlsli"

struct Probe {
    float2 pos;
    float radius;
    float strength;
    float kind;
    float age;
    float id;
    float active;
};

StructuredBuffer<Probe> Prev : register(t0);
RWStructuredBuffer<Probe> Out : register(u0);

static const uint MAXP = 32u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    ConsoleLayout L = cryoLayout(_Resolution.xy);

    Probe hdr = Prev[MAXP];
    float gateX = hdr.strength;
    float gateY = hdr.kind;
    float init  = hdr.radius;

    if (init <= 0.0) { gateX = 0.42; gateY = 0.70; }

    uint count = min(_ViewportEventCount, 64u);
    [loop] for (uint e = 0u; e < count; ++e) {
        ViewportEvent ev = _ViewportEvents[e];
        bool click = (ev.type == 5u && ev.code == 1u);
        bool drag  = (ev.type == 5u && ev.code == 3u && ev.phase != 8u);
        bool press = (ev.type == 2u && ev.code == 0u && ev.phase == 1u);
        if (!(click || drag || press)) continue;

        float2 pix = ev.position * _Resolution.xy;
        if (!cryoInRect(pix, L.pad)) continue;

        gateX = saturate((pix.x - L.pad.x) / max(L.pad.z - L.pad.x, 1.0));
        gateY = saturate(1.0 - (pix.y - L.pad.y) / max(L.pad.w - L.pad.y, 1.0));
    }

    [loop] for (uint i = 0u; i < MAXP; ++i) Out[i] = Prev[i];

    Probe h = hdr;
    h.pos = float2(0.0, 0.0);
    h.radius = 1.0;              // init marker
    h.strength = gateX;
    h.kind = gateY;
    h.age = _Time;
    h.id = 0.0;
    h.active = 0.0;
    Out[MAXP] = h;
}
