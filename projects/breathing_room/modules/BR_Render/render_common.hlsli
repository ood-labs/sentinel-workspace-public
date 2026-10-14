// render_common.hlsli -- shared plumbing for every BR_Render pass that touches the scene.
//
// CONTRACT: a pass that includes this binds `buffer:scene` at input slot 0 (t0).
#ifndef BR_RENDER_COMMON_HLSLI
#define BR_RENDER_COMMON_HLSLI

#include "../_shared/br_records.hlsli"
StructuredBuffer<BRRec> SceneBuf : register(t0);
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_sky.hlsli"
#include "../_shared/br_floor.hlsli"
#include "../_shared/br_scene.hlsli"
#include "../_shared/br_light_defs.hlsli"
// the trip, as prep.hlsl copied it into the scene buffer
#define TRIP_REC(i) SceneBuf[SC_TRIP + (i)]
#define TRIP_EXTRA_REC SceneBuf[SC_TRIP + 13]
#include "../_shared/br_trip.hlsli"
// every image a pass hands on carries the camera it was rendered with
#include "../_shared/br_camtexels.hlsli"

// The beam buffers (fog, foghist) pack the transmittance and the length the beam march
// integrated (where its ray ended) into alpha: 10 bits of T, the length in 1/128 m up to 32 m.
// Exact in RGBA32F. The resolve needs that length to upsample the beams without bleeding across
// depth, and it must arrive with the beams it describes, not from a G-buffer of another cook.
float fogPack(float T, float tEnd) { return floor(saturate(T) * 1023.0 + 0.5) * 4096.0 + clamp(floor(tEnd * 128.0 + 0.5), 0.0, 4095.0); }
float2 fogUnpack(float a) { float q = floor(a / 4096.0 + 1e-4); return float2(q / 1023.0, (a - q * 4096.0) / 128.0); }

#define G_FLAG_EXTERIOR 1u
#define G_FLAG_BOXHIT   2u
#define G_FLAG_MISS     4u

// ---------------------------------------------------------------------------------------------
// frame + camera
float4 scFrame() { return SceneBuf[SC_FRAME].dims; }          // frame, jitter.x, jitter.y, staticFrames
float4 scFrameB() { return SceneBuf[SC_FRAME].look; }         // camMotion, warpMotion, dt, time

float4x4 scMatrix(int base)
{
    return float4x4(SceneBuf[base].dims, SceneBuf[base + 1].dims, SceneBuf[base + 2].dims, SceneBuf[base + 3].dims);
}

void camRayJ(float2 pix, float2 res, float2 jitter, out float3 ro, out float3 rd)
{
    float2 uv = (pix + 0.5 + jitter) / res;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 nw = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 fw = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nw /= nw.w; fw /= fw.w;
    ro = _CameraPos;
    rd = normalize(fw.xyz - nw.xyz);
}

// RENDER SCALE. gbuf and shade fill only the top-left render_scale part of their full-size
// buffers (each work group past it leaves at once); resolve.hlsl brings that image up to the full
// resolution of the history, sample by jittered sample, so a still frame converges to full
// resolution while each frame costs a fraction of it. Every pass that reads gbuf or hdr maps into
// that region. The camera header (br_camtexels.hlsli) stays at texels (0..19, 0) of the region.
float renderScale() { return clamp(render_scale, 0.35, 1.0); }
int2 renderRes(int2 full) { return max((int2)round(float2(full) * renderScale()), int2(64, 36)); }

// Angle subtended by one pixel (radians), from the real projection.
float pixelAngle(float2 res)
{
    float3 ro, a, b;
    camRayJ(res * 0.5, res, float2(0, 0), ro, a);
    camRayJ(res * 0.5 + float2(1, 0), res, float2(0, 0), ro, b);
    return length(a - b);
}

// ---------------------------------------------------------------------------------------------
// FURNITURE (render objects compacted by prep.hlsl from BR_Furnish)
//   head (kind, variant, matA + 32 matB, slot + 64 flags)   dims (x, z, yaw, y0)
//   look (w, h, d, seed)                                    meta (bound centre xyz, bound radius)
#include "../_shared/br_furniture.hlsli"
// the rug design BR_Rug published, as prep.hlsl copied it (rugFromRecs falls back to the default)
#define RUG_REC(i) SceneBuf[SC_RUG + (i)]
#include "../_shared/br_rug.hlsli"

int scObjCount() { return clamp((int)SceneBuf[SC_COUNTS].dims.x, 0, SC_OBJ_MAX); }

// The trip as the plants feel it (br_plants.hlsli): time, and the breathe / drift / geometry
// channels each times the dose envelope. Zero when no trip is linked.
float4 scPlantAnim()
{
    BRRec th = TRIP_REC(TRIP_HEADER);
    if (abs(th.head.x - ROLE_TRIP) > 0.5) return float4(0, 0, 0, 0);
    float dose = saturate(th.dims.x);
    float t = (abs(th.meta.x) < 1e6) ? th.meta.x : 0.0;
    // overdrive moves them further (capped: the snake plant's ripple shears its blades, and its
    // bound is widened for it in plantModel)
    float push = (abs(th.look.z) < 10.0) ? clamp(th.look.z, 0.0, 2.0) : 0.0;
    float amp = min(1.0 + 1.6 * push, 2.6);
    return float4(t, dose * saturate(th.dims.y) * amp, dose * saturate(th.dims.z) * amp, dose * saturate(th.look.x));
}

float3 objLocal(BRRec o, float3 x)
{
    float c = cos(o.dims.z), s = sin(o.dims.z);
    float3 d = x - float3(o.dims.x, o.dims.w, o.dims.y);
    return float3(d.x * c - d.z * s, d.y, d.x * s + d.z * c);
}
int objFlags(BRRec o) { return (int)(o.head.w + 0.5) / 64; }
int objSlot(BRRec o) { return (int)(o.head.w + 0.5) % 64; }

// `exact` evaluates every object whose bound is nearer than the current best; otherwise an object
// more than 25 cm away contributes its bounding-sphere distance (a safe step for marching rays,
// and too far to soften a sun shadow) without evaluating its model.
//
// The trip: each piece is evaluated in its WARPED local frame (prep.hlsl worked out this frame's
// breathe / slump / twist for it), and the model's distance is divided by the warp's stretch
// bound so the march can never step through a piece that is swelling toward it. The bound in
// meta.w already includes the warp's reach.
void furnMap(float3 x, bool exact, inout SHit h)
{
    int n = scObjCount();
    float roomH = SceneBuf[SC_ROOM].look.x;
    float tt = TRIP_REC(TRIP_HEADER).meta.x;
    float4 anim = scPlantAnim();
    [loop] for (int i = 0; i < n; i++)
    {
        BRRec o = SceneBuf[SC_OBJ0 + i];
        float db = length(x - o.meta.xyz) - o.meta.w;
        if (db <= h.d)
        {
            if (!exact && db > 0.25) h.d = db;
            else
            {
                BRRec wr = SceneBuf[SC_OWARP0 + i];
                float Lw = 1.0;
                float3 q = objLocal(o, x);
                if (wr.head.x + wr.head.w + abs(wr.dims.x) > 0.0)
                    q = tripObjectApply(q, o.look.xyz, o.look.w, wr.head, wr.dims.x, wr.dims.z, tt, Lw);
                int mp = (int)(o.head.z + 0.5);
                SHit hm = shit(h.d * Lw, h.mat, h.part, h.obj);
                furnitureModel(q, (int)(o.head.x + 0.5), (int)(o.head.y + 0.5), o.look.xyz, mp % 32, mp / 32, i,
                               o.look.w, roomH, o.dims.w, anim, hm);
                if (hm.d < h.d * Lw) { h = hm; h.d = hm.d / Lw; }
            }
        }
    }
}

// The GI probes see furniture as rounded blocks: the solid pieces only, cheap and good enough
// to shadow and colour the bounce (the red rug under the sun is the one that matters).
void furnProxy(float3 x, inout SHit h)
{
    int n = scObjCount();
    [loop] for (int i = 0; i < n; i++)
    {
        BRRec o = SceneBuf[SC_OBJ0 + i];
        if (length(x - o.meta.xyz) - o.meta.w > h.d) continue;
        int k = (int)(o.head.x + 0.5);
        bool solid = k == FK_SOFA || k == FK_CHAIR || k == FK_COFFEE || k == FK_SIDE || k == FK_SHELF || k == FK_CONSOLE || k == FK_RUG;
        if (!solid) continue;
        float3 q = objLocal(o, x);
        float3 S = o.look.xyz;
        float d;
        // shapes that leave the air a person sits in, or stands a lamp in, empty: a proxy that
        // filled a sofa's whole box put the probes above the seat "inside" and blacked the seat
        if (k == FK_SOFA || k == FK_CHAIR)
        {
            float base = sdRBox(q - float3(0, 0.22, 0), float3(S.x * 0.5, 0.22, S.z * 0.5), 0.05);
            float back = sdRBox(q - float3(0, (0.44 + S.y) * 0.5, -S.z * 0.5 + 0.11), float3(S.x * 0.5, (S.y - 0.44) * 0.5, 0.11), 0.05);
            d = min(base, back);
        }
        else if (k == FK_COFFEE || k == FK_SIDE)
            d = sdRBox(q - float3(0, S.y - 0.03, 0), float3(S.x * 0.5, 0.03, S.z * 0.5), 0.01);
        else d = sdRBox(q - float3(0, S.y * 0.5, 0), max(S * 0.5, 0.008), (k == FK_RUG) ? 0.004 : 0.03);
        hmin(h, d, (int)(o.head.z + 0.5) % 32, FPART(FP_BODY), i);
    }
}

// ---------------------------------------------------------------------------------------------
// LAMPS (prep.hlsl: one record per lit lamp)
//   head (role, kind, object index, variant)   dims (bulb position, power)   look (colour rgb, 1)
//   The FIRE is a lamp record too: head (role, LAMP_KIND_FIRE, fireplace opening, 0)
//   dims (flame centre, flickering power)   look (colour rgb, 1)   meta (mouth normal xz, flicker, steady power)
int scLampCount() { return clamp((int)SceneBuf[SC_COUNTS].dims.y, 0, SC_LAMP_MAX); }
// BR_Finish's selected material slot (prep copies it into SC_COUNTS.meta.x), -1 when none
int scFinishSel() { return (int)round(SceneBuf[SC_COUNTS].meta.x); }

// The light record lighting a lamp object (its shade and bulb glow in that light), or -1.
int lampOfObj(int obj)
{
    int nl = scLampCount();
    [loop] for (int i = 0; i < nl; i++)
    {
        BRRec lr = SceneBuf[SC_LAMP0 + i];
        if ((int)(lr.head.y + 0.5) != LAMP_KIND_FIRE && (int)(lr.head.z + 0.5) == obj) return i;
    }
    return -1;
}
// The fire's light record, or -1.
int scFireLamp()
{
    int nl = scLampCount();
    [loop] for (int i = 0; i < nl; i++)
        if ((int)(SceneBuf[SC_LAMP0 + i].head.y + 0.5) == LAMP_KIND_FIRE) return i;
    return -1;
}

// How much of the bulb's light leaves the fitting toward `dirFromBulb`: drum shades are open top
// and bottom and glow through their fabric to the side, domes throw a downward cone, an opal globe
// or a paper lantern lets it out everywhere.
float lampShadeFactor(BRRec lr, float3 dirFromBulb, float dist)
{
    int k = (int)(lr.head.y + 0.5), v = (int)(lr.head.w + 0.5);
    float dy = dirFromBulb.y;
    // the fire fills its own firebox; out in the room its light leaves through the mouth,
    // forward and down, not up the throat
    if (k == LAMP_KIND_FIRE)
    {
        float f = saturate(dot(dirFromBulb.xz, lr.meta.xy) * 1.25 + 0.1);
        return lerp(1.0, f * f * lerp(1.0, 0.3, saturate(dy * 1.5)), smoothstep(0.32, 0.55, dist));
    }
    if (k == FK_PENDANT && v != 2) return 0.8;
    if ((k == FK_FLOORLAMP && v == 0) || (k == FK_PENDANT && v == 2)) return lerp(0.04, 1.0, smoothstep(-0.12, -0.5, dy));
    return lerp(0.30, 1.0, smoothstep(0.42, 0.72, abs(dy)));
}

// A light's own size: a bulb in its shade is a few centimetres, a fire is a volume of flame
// ~40 cm across. Falloff is P / (d^2 + r^2), so nothing close to a source sees the 1/d^2 spike a
// point light would give (logs 5 cm from the flame centre lit 400x, mirrored in the hearth).
float lampRadius2(BRRec lr) { return ((int)(lr.head.y + 0.5) == LAMP_KIND_FIRE) ? 0.04 : 0.0025; }

// Unshadowed lamp irradiance at x for normal n (the GI probes and reflection hits use this).
float3 lampIrradiance(float3 x, float3 n)
{
    float3 E = 0;
    int nl = scLampCount();
    [loop] for (int i = 0; i < nl; i++)
    {
        BRRec lr = SceneBuf[SC_LAMP0 + i];
        float3 dl = lr.dims.xyz - x;
        float dd2 = max(dot(dl, dl), 1e-6);
        float3 l = dl * rsqrt(dd2);
        E += lr.dims.w * lr.look.rgb * lampShadeFactor(lr, -l, sqrt(dd2)) * saturate(dot(n, l)) / (dd2 + lampRadius2(lr));
    }
    return E;
}

// ---------------------------------------------------------------------------------------------
// the scene field (REST space today; BR_Trip's warp wraps this in the passes)
// Returns the closest DETAIL (everything but the room slabs) and the slab hit separately.
SHit mapSplit(float3 x, out SHit slab, bool exact)
{
    SHit h = shellMapSplit(x, true, slab);
    furnMap(x, exact, h);
    return h;
}
SHit mapFull(float3 x)
{
    SHit slab;
    SHit h = mapSplit(x, slab, false);
    if (slab.d < h.d) h = slab;
    return h;
}
SHit mapCoarse(float3 x)
{
    SHit h = shellMap(x, false);
    furnProxy(x, h);
    return h;
}

// ---------------------------------------------------------------------------------------------
// G-buffer: x = t, y = octahedral normal (2 x 16 bit), z = mat | part << 8 | (obj + 1) << 16,
//           w = steps | flags << 16
float2 octWrap(float2 v) { return (1.0 - abs(v.yx)) * float2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }
float2 octEncode(float3 n)
{
    n /= (abs(n.x) + abs(n.y) + abs(n.z) + 1e-8);
    float2 e = n.z >= 0.0 ? n.xy : octWrap(n.xy);
    return e * 0.5 + 0.5;
}
float3 octDecode(float2 f)
{
    f = f * 2.0 - 1.0;
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    float t = saturate(-n.z);
    n.xy += float2(n.x >= 0.0 ? -t : t, n.y >= 0.0 ? -t : t);
    return normalize(n);
}
// Every packed word carries bit 29 set and bit 30 clear, so as a float its exponent sits in
// 0x40..0x7F: never all-ones (a NaN or Inf the GPU may canonicalise on the way into a float
// texture) and never zero (a denormal it may flush). Raw 16-bit octahedral pairs can form those
// patterns, so this keeps the round trip bit-exact by construction.
#define G_SAFE (1u << 29)
float4 packG(float t, float3 n, int mat, int part, int obj, uint steps, uint flags)
{
    float2 e = octEncode(n);
    uint en = G_SAFE | ((uint)round(saturate(e.x) * 16383.0)) | (((uint)round(saturate(e.y) * 16383.0)) << 14);
    uint id = G_SAFE | ((uint)mat & 0xFFu) | (((uint)part & 0xFFu) << 8) | (((uint)(obj + 1) & 0xFFu) << 16);
    uint w = G_SAFE | (steps & 0xFFFFu) | ((flags & 0xFu) << 16);
    return float4(t, asfloat(en), asfloat(id), asfloat(w));
}
struct GSample { float t; float3 n; int mat; int part; int obj; uint steps; uint flags; };
GSample unpackG(float4 g)
{
    GSample s;
    s.t = g.x;
    uint en = asuint(g.y);
    s.n = octDecode(float2((float)(en & 0x3FFFu), (float)((en >> 14) & 0x3FFFu)) / 16383.0);
    uint id = asuint(g.z);
    s.mat = (int)(id & 0xFFu); s.part = (int)((id >> 8) & 0xFFu); s.obj = (int)((id >> 16) & 0xFFu) - 1;
    uint w = asuint(g.w);
    s.steps = w & 0xFFFFu; s.flags = (w >> 16) & 0xFu;
    return s;
}

// ---------------------------------------------------------------------------------------------
BRMat scMat(int slot) { return brMatFromRec(SceneBuf[SC_MAT0 + clamp(slot, 0, MAT_SLOTS - 1)]); }

BRSkyCtx scSkyCtx()
{
    BRRec s = SceneBuf[SC_SUN];
    BRSkyCtx S;
    S.sunDir = normalize(s.dims.xyz);
    S.sunRad = s.look.rgb;
    S.sunI = 1.0;          // the sky table is absolute radiance: intensity is already baked in
    S.wind = s.meta.y;
    S.canopy = s.meta.z;
    S.time = s.meta.w;
    BRRoom R = scRoom();
    S.building = float4(R.x0 - R.T, R.x1 + R.T, R.z0 - R.T, R.z1 + R.T);
    return S;
}
float scSunSoft() { return SceneBuf[SC_SUN].look.w; }

// ---------------------------------------------------------------------------------------------
// GI probe grid over the room interior. Spacing ~0.3 m, at most 32 x 16 x 32.
#define PROBE_MAX 16384
struct ProbeGrid { float3 origin; float3 spacing; int3 n; int count; };
ProbeGrid probeGrid()
{
    BRRoom R = scRoom();
    float3 lo = float3(R.x0, 0.0, R.z0), hi = float3(R.x1, R.H, R.z1);
    float3 ext = hi - lo;
    ProbeGrid g;
    g.n = int3(clamp((int)ceil(ext.x / 0.30), 4, 32), clamp((int)ceil(ext.y / 0.30), 4, 16), clamp((int)ceil(ext.z / 0.30), 4, 32));
    g.spacing = ext / (float3)g.n;
    g.origin = lo + g.spacing * 0.5;
    g.count = g.n.x * g.n.y * g.n.z;
    return g;
}
int probeIndex(ProbeGrid g, int3 c) { return c.x + g.n.x * (c.y + g.n.y * c.z); }
int3 probeCoord(ProbeGrid g, int i) { return int3(i % g.n.x, (i / g.n.x) % g.n.y, i / (g.n.x * g.n.y)); }
float3 probePos(ProbeGrid g, int3 c) { return g.origin + (float3)c * g.spacing; }

// Sun-occlusion volume over the room (sunvol.hlsl), ~14 cm cells, at most 64 x 32 x 64.
#define SUNVOL_MAX 131072
struct SunGrid { float3 origin; float3 spacing; int3 n; int count; };
SunGrid sunGrid()
{
    BRRoom R = scRoom();
    float3 lo = float3(R.x0, 0.0, R.z0), hi = float3(R.x1, R.H, R.z1);
    float3 ext = hi - lo;
    SunGrid g;
    g.n = int3(clamp((int)ceil(ext.x / 0.14), 4, 64), clamp((int)ceil(ext.y / 0.14), 4, 32), clamp((int)ceil(ext.z / 0.14), 4, 64));
    g.spacing = ext / (float3)g.n;
    g.origin = lo + g.spacing * 0.5;
    g.count = g.n.x * g.n.y * g.n.z;
    return g;
}
float sunVolAt(StructuredBuffer<float> V, float3 x)
{
    SunGrid g = sunGrid();
    float3 gc = (x - g.origin) / g.spacing;
    int3 c0 = clamp((int3)floor(gc), int3(0, 0, 0), g.n - 2);
    float3 f = saturate(gc - (float3)c0);
    float v = 0.0;
    [unroll] for (int k = 0; k < 8; k++)
    {
        int3 o = int3(k & 1, (k >> 1) & 1, k >> 2);
        int3 c = c0 + o;
        float3 w3 = lerp(1.0 - f, f, (float3)o);
        v += V[c.x + g.n.x * (c.y + g.n.y * c.z)] * w3.x * w3.y * w3.z;
    }
    return saturate(v);
}

// L1 spherical harmonics (per channel 4 coefficients). Probe record: R, G, B, meta.
struct ProbeRec { float4 r; float4 g; float4 b; float4 meta; };   // meta: validity, samples, nearDist, frame

float4 shBasis(float3 d) { return float4(0.282095, 0.488603 * d.y, 0.488603 * d.z, 0.488603 * d.x); }
// irradiance E(n) from radiance SH (cosine-lobe convolution: A0 = pi, A1 = 2pi/3)
float3 shIrradiance(ProbeRec p, float3 n)
{
    float4 b = float4(3.14159265 * 0.282095, 2.0943951 * 0.488603 * n.y, 2.0943951 * 0.488603 * n.z, 2.0943951 * 0.488603 * n.x);
    return max(float3(dot(p.r, b), dot(p.g, b), dot(p.b, b)), 0.0);
}

// The mean radiance around x (what isotropic haze scatters toward the eye): the probes' DC terms,
// trilinear. Dark corners and the inside of the firebox stay dark instead of milky.
float3 probeAvgRadiance(StructuredBuffer<ProbeRec> PB, float3 x)
{
    ProbeGrid g = probeGrid();
    float3 gc = (x - g.origin) / g.spacing;
    int3 c0 = clamp((int3)floor(gc), int3(0, 0, 0), g.n - 2);
    float3 f = saturate(gc - (float3)c0);
    float3 sum = 0; float ws = 0;
    [unroll] for (int k = 0; k < 8; k++)
    {
        int3 o = int3(k & 1, (k >> 1) & 1, k >> 2);
        float3 w3 = lerp(1.0 - f, f, (float3)o);
        ProbeRec pr = PB[probeIndex(g, c0 + o)];
        float w = w3.x * w3.y * w3.z * (saturate(pr.meta.x) * 0.97 + 0.03);
        if (!(abs(pr.r.x) < 1e5)) w = 0.0;
        sum += float3(pr.r.x, pr.g.x, pr.b.x) * 0.282095 * w; ws += w;
    }
    return (ws > 1e-4) ? max(sum / ws, 0.0) : 0.0;
}


// ---------------------------------------------------------------------------------------------
// Glass and sheer transmittance for a ray leaving the room from x through opening o (analytic:
// the sheer hangs on the plane 8.5 cm in front of the interior face, the glass sits in the frame
// plane). `op` is the sheer's opacity.
float veilTransmitOpening(float3 x, float3 L, BROpening o, BRRoom R, float op)
{
    float2 n2 = brWallNormal(o.wall);
    float ln = dot(L, float3(n2.x, 0.0, n2.y));
    if (ln > -1e-4) return 1.0;
    float3 l0 = openLocal(x, o, R);
    float hw = o.width * 0.5;
    float T = 1.0;
    if (o.curtains && (R.flags & ROOM_FLAG_CURTAINS) != 0)
    {
        float s = (0.085 - l0.z) / ln;
        if (s > 0.0)
        {
            float3 lq = openLocal(x + L * s, o, R);
            float ext = hw + 0.36;
            // a sheer s metres away casts a penumbra s x (sun radius) wide, and its pleats -- 8 cm
            // apart -- blur out a couple of metres from the window instead of printing stripes
            // across the room
            float pen = max(s * scSunSoft(), 0.002);
            float cL = saturate((lq.x + ext) / pen + 0.5) * saturate((-hw + 0.22 - lq.x) / pen + 0.5);
            float cR = saturate((lq.x - (hw - 0.22)) / pen + 0.5) * saturate((ext - lq.x) / pen + 0.5);
            float cy = saturate((lq.y + o.sill) / pen + 0.5) * saturate((o.height + 0.165 - lq.y) / pen + 0.5);
            float pleat = 0.78 + 0.22 * exp(-612.0 * pen * pen) * sin(lq.x * 70.0 + (float)o.slot);
            T *= 1.0 - op * saturate(cL + cR) * cy * pleat;
        }
    }
    float dc = -R.T + 0.075;
    float sg = (dc - l0.z) / ln;
    if (sg > 0.0)
    {
        float3 lq = openLocal(x + L * sg, o, R);
        if (abs(lq.x) < hw && lq.y > 0.0 && lq.y < o.height) T *= 0.88;
    }
    return T;
}
float sheerOpacity()
{
    BRMat sheer = scMat(MAT_SHEER);
    return saturate((1.0 - sheer.trans) * 0.9 + 0.08);
}

#endif
