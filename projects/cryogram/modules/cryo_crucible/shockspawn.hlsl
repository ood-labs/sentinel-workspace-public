// CRYOGRAM / SPECIMEN — spawn one shock per accepted snare onset.
//
// Triggered on the detector's snare COUNTER, not on an envelope threshold.
// An envelope has to decay back below its threshold before it can arm again,
// which silently swallows hits at speed — the same defect that made the kick
// swells miss. A counter increments exactly once per onset.

struct Shock {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

StructuredBuffer<Shock> Prev : register(t0);
RWStructuredBuffer<Shock> Out : register(u0);

static const uint MAXSHOCK = 8u;

Shock emptyShock() {
    Shock s;
    s.center = float2(0.5, 0.5);
    s.birth = -1000.0;
    s.strength = 0.0;
    s.seed = 0.0;
    s.active = 0.0;
    s.pad = float2(0.0, 0.0);
    return s;
}

uint shockHash(uint v) {
    v = v * 747796405u + 2891336453u;
    v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
    return (v >> 22u) ^ v;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    [loop] for (uint i = 0u; i < MAXSHOCK; ++i) {
        Shock s = Prev[i];
        if (s.active > 0.5 && (_Time - s.birth) > shock_life) s = emptyShock();
        Out[i] = s;
    }

    Shock hdr = Prev[MAXSHOCK];
    float prevCount = hdr.center.x;
    float nextIdx = hdr.center.y;
    float initFlag = hdr.strength;

    float delta = snare_count_in - prevCount;
    bool resync = (initFlag < 0.5) || (delta < 0.0) || (delta > 16.0);
    bool fire = !resync && (delta >= 1.0);

    if (fire) {
        uint idx = (uint)max(nextIdx, 0.0);
        uint h = shockHash(idx * 2246822519u + 7919u);

        float2 c = float2((float)(h & 0xFFFFu) / 65535.0,
                          (float)((h >> 16u) & 0xFFFFu) / 65535.0);
        c = 0.5 + (c - 0.5) * 0.88;             // keep clear of the extreme edge

        Shock ns = emptyShock();
        ns.center = saturate(c);
        ns.birth = _Time;
        ns.strength = clamp(snare_level_in * shock_strength_gain,
                            shock_min_strength, 1.0);
        ns.seed = (float)(h & 0xFFFu) / 4095.0;
        ns.active = 1.0;
        Out[idx % MAXSHOCK] = ns;

        nextIdx = nextIdx + 1.0;
        if (nextIdx > 1.0e6) nextIdx = 0.0;
    }

    Shock nh = emptyShock();
    nh.center = float2(snare_count_in, nextIdx);
    nh.strength = 1.0;                          // init marker
    nh.active = 0.0;
    Out[MAXSHOCK] = nh;
}
