// SS_Haze / hzden — the haze itself, on the fine grid (176 x 80 x 240, half an air cell), carried by the air.
// hzdfwd (HZ_DEN_PASS 1: source -> HAT) and hzdcorr (2: source, HAT -> destination): MacCormack advection
// exactly as for the air (hzadv.hlsli), with exact texel loads for the density (hardware filter weights are
// 8-bit: a slow drift of a few hundredths of a cell per frame would stall or creep) and the air's velocity
// from the start-of-frame atlas (pass:hzvpack). The two haze slots swap by the tick's parity, so the
// correction never overwrites what a neighbouring thread is still reading.
//
// Units: Haze units. 1 = the haze the renderer's Haze control describes; clear air sits at Haze Base.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
Texture2D<float4> Vel : register(t1);
RWStructuredBuffer<float> D : register(u0);

static HzDomain gD;
float3 velAt(float3 x) { return atlasSample(Vel, LinearSampler, (x - gD.lo) / gD.h - 0.5, AX, AY, AZ, 0u).xyz; }
float3 trace(float3 p, float dt)
{
    float3 mid = p - 0.5 * dt * velAt(p);
    return p - dt * velAt(mid);
}
// exact trilinear of the haze region at `base` at x, with the range of its 8 texels
float denAt(uint base, float3 x, out float mn, out float mx)
{
    float hf = 0.5 * gD.h;
    float3 g = clamp((x - gD.lo) / hf - 0.5, 0.0, float3(FX - 1, FY - 1, FZ - 1) - 1e-3);
    int3 c0 = min((int3)floor(g), int3(FX - 2, FY - 2, FZ - 2));
    float3 f = g - (float3)c0;
    float s[8];
    [unroll] for (uint k = 0; k < 8u; k++) s[k] = D[base + fIdx(c0 + int3(k & 1u, (k >> 1) & 1u, k >> 2))];
    mn = min(min(min(s[0], s[1]), min(s[2], s[3])), min(min(s[4], s[5]), min(s[6], s[7])));
    mx = max(max(max(s[0], s[1]), max(s[2], s[3])), max(max(s[4], s[5]), max(s[6], s[7])));
    return lerp(lerp(lerp(s[0], s[1], f.x), lerp(s[2], s[3], f.x), f.y), lerp(lerp(s[4], s[5], f.x), lerp(s[6], s[7], f.x), f.y), f.z);
}
// a hall the hazers have been working for a while: lumps of haze, thicker up under the roof and upstage
float seedAt(float3 x)
{
    float n = hzNoise(x / 3.2 + 3.7) * 0.7 + hzNoise(x / 1.4 + 11.1) * 0.3;
    float yb = (x.y - gD.floorY) / max(gD.Ht, 1.0);
    float layer = lerp(0.55, 1.4, smoothstep(0.06, 0.95, yb)) * lerp(1.3, 0.8, saturate((x.z - gD.zc + 0.5 * gD.L) / gD.L));
    return haze_base + 1.2 * smoothstep(0.38, 0.75, n) * layer;
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= FN) return;
    gD = hzDomain(T[1], T[2], T[3]);
    float4 t0 = T[0];
    uint par = (uint)t0.x & 1u;
    uint SRC = par * FN, DST = (1u - par) * FN;
    int3 c = fCoord(i);
    float3 x = fCentre(gD, c);
    if (t0.z > 0.5)
    {
        float s0 = hzSolidAt(gD, x) ? (inHall(gD, x) ? haze_base : 0.0) : seedAt(x);
#if HZ_DEN_PASS == 1
        D[RD_HAT + i] = s0;
#else
        D[DST + i] = s0;
#endif
        return;
    }
    float dt = t0.w;
    float mn, mx;
#if HZ_DEN_PASS == 1
    D[RD_HAT + i] = denAt(SRC, trace(x, dt), mn, mx);
#else
    float hat = D[RD_HAT + i];
    float now = D[SRC + i];
    denAt(SRC, trace(x, dt), mn, mx);
    float m0, m1;
    float chk = denAt(RD_HAT, trace(x, -dt), m0, m1);
    float d = hat + 0.5 * (now - chk);
    if (d < mn || d > mx) d = hat;
    // the hazers: fresh haze out of each nozzle, carried off by its own jet (hzforce)
    float burst = hzBurstAll(t0.y, T[3].y);
    [unroll] for (uint m = 0; m < HZ_MACHINES; m++)
    {
        float3 p, dir;
        hzMachine(m, gD.floorY, p, dir);
        // ~18 haze m^3 a second at full output, over a 0.3 m kernel (2.4 haze cells) the jet clears at 4.5 m/s
        float3 r = x - (p + dir * 0.3);
        d += dt * 120.0 * hzOutput(m, t0.y, haze_pump, burst) * exp(-dot(r, r) / (0.3 * 0.3));
    }
    // the haze settles out and is extracted over minutes, back toward the hall's base level
    d = haze_base + (d - haze_base) * exp(-dt / max(haze_life, 1.0));
    // none kept inside a solid (the deck, the booth): the air there never moves, so it would only pile up
    D[DST + i] = inHall(gD, x) ? (hzSolidAt(gD, x) ? haze_base : clamp(fin(d), 0.0, 40.0)) : 0.0;
#endif
}
