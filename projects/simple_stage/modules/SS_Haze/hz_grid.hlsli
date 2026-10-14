// SS_Haze / hz_grid.hlsli — the room's air and haze as a real fluid, the layout every pass shares.
//
// After the volumetrics a friend of the project built for his own show on this stage (EmberGen's method:
// Stable Fluids on a staggered grid, MacCormack advection with Selle's limiter, Boussinesq buoyancy,
// vorticity confinement and a multigrid pressure projection; Vassvik's notes, Selle et al. 2008,
// Fedkiw, Stam & Jensen 2001). The physics is his; the storage is rebuilt for this host and this room.
//
// THE GRIDS. The air is 88 x 40 x 120 cells (0.25 m in the 22 x 30 m hall, up to 10 m high), its faces
// carrying velocity and its centre the temperature above ambient. The haze rides on a grid twice as fine
// (176 x 80 x 240, 1/8 m). The grid's size in cells is fixed; its cell size follows the hall the Venue
// publishes (the largest of width / 88, length / 120, height / 40), so a bigger hall gets coarser air
// rather than a grid that stops at a wall. Cells outside the hall are solid.
//
// THE STORAGE. Structured buffers, read and written in place by the pass that owns each region: a pass
// touches only its own cells, where a texture would have to be copied whole by every pass. Wherever a
// pass reads neighbours of what it writes, it reads one region and writes another (advection writes NEW,
// forces read NEW and write U), and the haze ping-pongs between two slots by the frame's parity.
#ifndef SS_HZ_GRID_HLSLI
#define SS_HZ_GRID_HLSLI

// The grids' sizes, the domain and the Haze Field's layout are the contract with the renderer: ss_haze.hlsli.
#include "../_shared/ss_haze.hlsli"
// ---- the air
#define AX HZ_AX
#define AY HZ_AY
#define AZ HZ_AZ
#define AN 422400u                 // AX * AY * AZ
// ---- the haze, twice as fine
#define FX HZ_FX
#define FY HZ_FY
#define FZ HZ_FZ
#define FN 3379200u                // FX * FY * FZ

// hzA (float4): [U] faces u v w on each cell's -x -y -z face + temperature at its centre
//               [HAT] MacCormack forward estimate   [NEW] advected air   [CURL] vorticity (xyz, |w|)
//               [MG] multigrid cells of all four levels: x pressure, y right-hand side, z solid, w residual
#define RA_U    0u
#define RA_HAT  AN
#define RA_NEW  (2u * AN)
#define RA_CURL (3u * AN)
#define RA_MG   (4u * AN)
#define MG_N    482625u            // 422400 + 52800 + 6600 + 825
#define RA_END  (RA_MG + MG_N)
static const uint MG_OFF[4] = { 0u, 422400u, 475200u, 481800u };
// hzD (float): two haze slots (this frame's source and destination swap by parity), the forward estimate
#define RD_HAT  (2u * FN)
#define RD_END  (3u * FN)

// hzT (float4): [0] tick, time, fresh (1 on the frames the field is (re)seeded), dt
//               [1] grid origin xyz, cell size   [2] hall width, length, height, floor
//               [3] hall centre z, time of the last all-together burst, layout version, last BUILD ramp
#define HZ_VERSION 3.1

#define HZ_AMBIENT_K 293.0
#define HZ_BETA (9.81 / HZ_AMBIENT_K)  // Boussinesq buoyancy per kelvin, m/s^2
#define HZ_MACHINES 4

// NaN / inf -> 0. The fields are warm-started forever, so one bad value would otherwise live forever.
float fin(float x) { return (asuint(x) & 0x7f800000u) == 0x7f800000u ? 0.0 : x; }
float4 fin4(float4 v) { return float4(fin(v.x), fin(v.y), fin(v.z), fin(v.w)); }

uint aIdx(int3 c) { return ((uint)c.z * AY + (uint)c.y) * AX + (uint)c.x; }
int3 aCoord(uint i) { return int3(i % AX, (i / AX) % AY, i / (AX * AY)); }
bool aIn(int3 c) { return all(c >= 0) && c.x < AX && c.y < AY && c.z < AZ; }
uint fIdx(int3 c) { return ((uint)c.z * FY + (uint)c.y) * FX + (uint)c.x; }
int3 fCoord(uint i) { return int3(i % FX, (i / FX) % FY, i / (FX * FY)); }

// ---- the domain, as hzclock last published it (HzDomain, hzInHall: ss_haze.hlsli)
HzDomain hzDomain(float4 t1, float4 t2, float4 t3)
{
    HzDomain d;
    d.lo = t1.xyz; d.h = max(t1.w, 0.05);
    d.W = t2.x; d.L = t2.y; d.Ht = t2.z; d.floorY = t2.w; d.zc = t3.x;
    return d;
}
float3 aCentre(HzDomain d, int3 c) { return d.lo + ((float3)c + 0.5) * d.h; }
float3 fCentre(HzDomain d, int3 c) { return d.lo + ((float3)c + 0.5) * (0.5 * d.h); }
bool inHall(HzDomain d, float3 p) { return hzInHall(d, p); }

// ---- noise for the drafts and the seed
float hzHash(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}
float hzNoise(float3 p)
{
    float3 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hzHash(i), b = hzHash(i + float3(1, 0, 0)), c = hzHash(i + float3(0, 1, 0)), e = hzHash(i + float3(1, 1, 0));
    float g = hzHash(i + float3(0, 0, 1)), k = hzHash(i + float3(1, 0, 1)), m = hzHash(i + float3(0, 1, 1)), n = hzHash(i + float3(1, 1, 1));
    return lerp(lerp(lerp(a, b, f.x), lerp(c, e, f.x), f.y), lerp(lerp(g, k, f.x), lerp(m, n, f.x), f.y), f.z);
}
float hzHash1(float n) { return frac(sin(n * 12.9898 + 4.1414) * 43758.5453); }

// ---- what the air goes round: outside the hall, the stage deck (ss_stage.hlsli SS_DECK: 8 x 4.5 m, 1 m high,
// centred on the origin) and the DJ's booth (SS_BOOTH, with its top). hzsolid marks the air's cells with it; the
// haze passes keep no haze inside it.
#define HZ_DECK_HW 4.0
#define HZ_DECK_HD 2.25
#define HZ_DECK_TOP 1.0
bool hzInBox(float3 p, float3 c, float3 h) { return all(abs(p - c) <= h); }
bool hzSolidAt(HzDomain d, float3 p)
{
    if (!inHall(d, p)) return true;
    if (hzInBox(p, float3(0.0, d.floorY + 0.5 * HZ_DECK_TOP, 0.0), float3(HZ_DECK_HW, 0.5 * HZ_DECK_TOP, HZ_DECK_HD))) return true;
    if (hzInBox(p, float3(0.0, d.floorY + 1.525, 1.15), float3(1.2, 0.525, 0.4))) return true;
    return false;
}

// ---- the hazers. Two upstage on the deck behind the DJ, throwing forward and up through the back row;
// two at the deck's downstage corners, throwing in across the front of the booth.
void hzMachine(uint m, float floorY, out float3 pos, out float3 dir)
{
    float side = (m & 1u) ? 1.0 : -1.0;
    if (m < 2u) { pos = float3(side * HZ_DECK_HW * 0.62, floorY + HZ_DECK_TOP + 0.3, -HZ_DECK_HD + 0.9); dir = normalize(float3(-side * 0.12, 0.3, 1.0)); }
    else        { pos = float3(side * (HZ_DECK_HW - 0.4), floorY + HZ_DECK_TOP + 0.2, HZ_DECK_HD - 0.6); dir = normalize(float3(-side * 0.55, 0.18, 1.0)); }
}
// all four together, full for two seconds after Hazers Full lets go or the drop lands, gone a second later
// (hzclock keeps that time in T[3].y)
float hzBurstAll(float t, float pressed) { float a = t - pressed; return (a >= 0.0 && a < 3.0) ? 1.0 - smoothstep(2.0, 3.0, a) : 0.0; }
// A hazer's output now: each runs its own cycle, a burst of ~2 s every 6-12 s over a low trickle, and all four
// go together on the drop, the way an operator hits them.
float hzOutput(uint m, float t, float pump, float burstAll)
{
    float period = 6.0 + 6.0 * hzHash1((float)m + 1.7);
    float local = fmod(t + hzHash1((float)m + 5.3) * period, period);
    float burst = smoothstep(0.0, 0.35, local) * (1.0 - smoothstep(1.6, 2.4, local));
    return pump * (0.08 + burst + 1.4 * burstAll);
}

#endif
