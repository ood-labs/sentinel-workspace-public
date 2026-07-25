// CRYOGRAM / SPECIMEN — authored marks, reduced from real viewport input.
//
// This preview IS the editor. Event positions arrive in the same normalized
// space as a full-resolution pass's uv, so a click on the specimen is literally
// a field coordinate — no fitted-stage remap, no unprojection.
//
//   left click / drag -> place a probe of the current kind
//   right press       -> ANNEAL, always, without changing the current kind
//   wheel             -> probe radius
//   C                 -> cycle SEED / ANNEAL / ANCHOR
//   X                 -> clear
//
// Header record (index 32) publishes the control outputs.

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

Probe emptyProbe() {
    Probe p;
    p.pos = float2(0.0, 0.0);
    p.radius = 0.0; p.strength = 0.0; p.kind = 0.0;
    p.age = 0.0; p.id = 0.0; p.active = 0.0;
    return p;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    Probe hdr = Prev[MAXP];
    float nextId = hdr.pos.x;
    float kind   = hdr.pos.y;
    float brush  = hdr.radius;
    float last   = hdr.age;

    if (brush <= 0.0) { nextId = 1.0; kind = 0.0; brush = 0.075; }

    float dt = _Time - last;
    if (dt < 0.0 || dt > 0.5) dt = 1.0 / 60.0;

    [loop] for (uint i = 0u; i < MAXP; ++i) {
        Probe p = Prev[i];
        if (p.active > 0.5) {
            p.age += dt;
            if (probe_lifetime > 0.5 && p.age > probe_lifetime) p = emptyProbe();
        }
        Out[i] = p;
    }

    brush = clamp(brush * (1.0 + _ViewportWheelDelta * 0.10), 0.012, 0.40);

    bool clearAll = false;
    uint count = min(_ViewportEventCount, 64u);

    [loop] for (uint e = 0u; e < count; ++e) {
        ViewportEvent ev = _ViewportEvents[e];

        if (ev.type == 4u && ev.phase == 1u && ev.code == 24u) { clearAll = true; continue; }
        if (ev.type == 4u && ev.phase == 1u && ev.code == 3u)  { kind = fmod(kind + 1.0, 3.0); continue; }

        bool leftClick = (ev.type == 5u && ev.code == 1u);
        bool leftDrag  = (ev.type == 5u && ev.code == 3u && ev.phase != 8u);
        bool rightDown = (ev.type == 2u && ev.code == 1u && ev.phase == 1u);
        if (!(leftClick || leftDrag || rightDown)) continue;

        float2 at = saturate(ev.position);
        float useKind = rightDown ? 1.0 : kind;

        // painting must not stack probes on top of each other
        bool tooClose = false;
        [loop] for (uint q = 0u; q < MAXP; ++q) {
            if (Out[q].active < 0.5) continue;
            if (distance(Out[q].pos, at) < brush * 0.5) { tooClose = true; break; }
        }
        if (tooClose && !leftClick) continue;

        uint slot = 0xFFFFFFFFu;
        [loop] for (uint s = 0u; s < MAXP; ++s) if (Out[s].active < 0.5) { slot = s; break; }
        if (slot == 0xFFFFFFFFu) {
            float oldest = -1.0;
            [loop] for (uint s2 = 0u; s2 < MAXP; ++s2)
                if (Out[s2].age > oldest) { oldest = Out[s2].age; slot = s2; }
        }

        Probe np = emptyProbe();
        np.pos = at;
        np.radius = brush;
        np.strength = 1.0;
        np.kind = useKind;
        np.id = nextId;
        np.active = 1.0;
        nextId += 1.0;
        if (nextId > 99000.0) nextId = 1.0;
        Out[slot] = np;
    }

    if (clearAll) [loop] for (uint z = 0u; z < MAXP; ++z) Out[z] = emptyProbe();

    float live = 0.0;
    [loop] for (uint c = 0u; c < MAXP; ++c) if (Out[c].active > 0.5) live += 1.0;

    Probe h = emptyProbe();
    h.pos = float2(nextId, kind);
    h.radius = brush;
    h.strength = live;
    h.kind = 0.0;
    h.age = _Time;
    h.id = live;
    h.active = 0.0;
    Out[MAXP] = h;
}
