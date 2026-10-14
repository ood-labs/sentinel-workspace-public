// still.hlsli - Still Life's contract: the object record, the scene's distance field, the camera
// ray, and the gizmo's geometry.
//
// ONE FIELD, ONE GIZMO. The pick pass, the march and the selection outline march the same field;
// the pick pass, the reducer and the overlay hit-test the same gizmo. What is drawn is what is
// picked, and what is picked is what drags.
//
// Included twice by every pass: once for the record alone, then - after the pass has declared its
// object buffer and named it SL_OBJECTS - for the functions (the reducer reads its own
// read-write copy, everyone else a read-only input):
//
//     #define SL_RECORD_ONLY
//     #include "still.hlsli"
//     #undef SL_RECORD_ONLY
//     StructuredBuffer<SlObject> Objs : register(t0);
//     #define SL_OBJECTS Objs
//     #include "still.hlsli"
#ifndef STILL_RECORD_HLSLI
#define STILL_RECORD_HLSLI

#define SL_MAX    8u             // object records 1..8 (record 0 is the header)
#define SL_MAGIC  357662u        // header marker: the arrangement has been seeded (exact in float)

#define K_EMPTY 0u
#define K_VASE  1u
#define K_ORB   2u
#define K_RING  3u
#define K_BLOCK 4u
#define K_CONE  5u

// Gizmo handles: the pick pass returns one as sub_element_id, the reducer drags by it.
#define G_NONE    0u
#define G_MOVE_X  1u
#define G_MOVE_Y  2u
#define G_MOVE_Z  3u
#define G_TURN_X  4u
#define G_TURN_Y  5u
#define G_TURN_Z  6u
#define G_BODY    7u             // a selected object's body: slide it along the table

#define SL_GIZMO_PX 96.0         // arrow length in ui px
#define SL_RING     0.78         // ring radius as a fraction of the arrow
#define SL_RING_SEG 48u

// The durable record (state_buffers: objects). 64 bytes.
struct SlObject
{
    float3 pos;   uint kind;     // pivot = the object's centre, in metres
    float4 rot;                  // unit quaternion (x, y, z, w)
    float  scale; uint id; float colour; uint flags;    // id: the host object id; colour: rgb24 as an exact float
    float4 spare;
};
#endif // STILL_RECORD_HLSLI

#ifndef SL_RECORD_ONLY
#ifndef STILL_HLSLI
#define STILL_HLSLI

#ifndef SL_OBJECTS
#error declare the object buffer and define SL_OBJECTS before the second include of still.hlsli
#endif

// ---------------------------------------------------------------- quaternions
float4 qMul(float4 a, float4 b) { return float4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz)); }
float3 qRot(float4 q, float3 v) { float3 t = 2.0 * cross(q.xyz, v); return v + q.w * t + cross(q.xyz, t); }
float4 qConj(float4 q) { return float4(-q.xyz, q.w); }
float4 qAxis(float3 axis, float angle) { float h = 0.5 * angle; return float4(axis * sin(h), cos(h)); }
float4 qNorm(float4 q) { float l = length(q); return (l > 1e-6) ? q / l : float4(0.0, 0.0, 0.0, 1.0); }
// Heading (rotation about +y) in degrees, for readouts.
float qYawDeg(float4 q) { float3 f = qRot(q, float3(1.0, 0.0, 0.0)); return degrees(atan2(-f.z, f.x)); }

float3 slAxis(uint i) { return (i == 0u) ? float3(1.0, 0.0, 0.0) : ((i == 1u) ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0)); }

// ---------------------------------------------------------------- the room: a photo sweep
#define SL_WALL_Z   0.85
#define SL_SWEEP_R  0.55
// Positive in the air: the floor (y = 0) curves up into the back wall (+z) through a fillet.
float sdRoom(float3 p)
{
    float a = SL_WALL_Z - p.z, b = p.y;
    if (a < SL_SWEEP_R && b < SL_SWEEP_R) return SL_SWEEP_R - length(float2(SL_SWEEP_R - a, SL_SWEEP_R - b));
    return min(a, b);
}

// ---------------------------------------------------------------- the objects (local, unit scale)
float sminK(float a, float b, float k) { float h = saturate(0.5 + 0.5 * (b - a) / k); return lerp(b, a, h) - k * h * (1.0 - h); }

float sdVase(float3 p)
{
    float body = length(p - float3(0.0, -0.060, 0.0)) - 0.100;
    float2 nq = float2(length(p.xz) - 0.034, abs(p.y - 0.065) - 0.065);
    float neck = min(max(nq.x, nq.y), 0.0) + length(max(nq, 0.0));
    float2 lq = float2(length(p.xz) - 0.044, p.y - 0.140);
    float lip = length(lq) - 0.012;
    float d = sminK(sminK(body, neck, 0.040), lip, 0.012);
    return max(d, -(p.y + 0.160));                 // a flat foot
}
float sdOrb(float3 p) { return length(p) - 0.090; }
float sdRing(float3 p) { float2 q = float2(length(p.xy) - 0.095, p.z); return length(q) - 0.030; }
float sdBlock(float3 p)
{
    float3 q = abs(p) - (float3(0.085, 0.065, 0.085) - 0.012);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - 0.012;
}
float sdCone(float3 p)
{
    const float h = 0.120, r1 = 0.090, r2 = 0.008;
    float2 q = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, h);
    float2 k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * saturate(dot(k1 - q, k2) / dot(k2, k2));
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

float slKindSd(uint kind, float3 p)
{
    [branch] switch (kind)
    {
        case K_VASE:  return sdVase(p);
        case K_ORB:   return sdOrb(p);
        case K_RING:  return sdRing(p);
        case K_BLOCK: return sdBlock(p);
        default:      return sdCone(p);
    }
}
// Local half extents (the resting pivot height is .y), and the radius of the sphere about the
// pivot that holds the whole shape - measured per kind from the distance functions above (the
// corner of the box would oversize the orb and the ring) - for culling and the gizmo's clearance.
float3 slBounds(uint kind)
{
    return (kind == K_VASE) ? float3(0.100, 0.160, 0.100) : ((kind == K_ORB) ? float3(0.090, 0.090, 0.090) :
           ((kind == K_RING) ? float3(0.125, 0.125, 0.030) : ((kind == K_BLOCK) ? float3(0.085, 0.065, 0.085) : float3(0.090, 0.120, 0.090))));
}
float slRadius(uint kind)
{
    return (kind == K_VASE) ? 0.165 : ((kind == K_ORB) ? 0.092 : ((kind == K_RING) ? 0.127 : ((kind == K_BLOCK) ? 0.139 : 0.152)));
}

// ---------------------------------------------------------------- the field
// Nearest surface; `rec` is the object record (1..8) or 0 for the room. Objects are culled by
// their bounding sphere first - the exact distance can only be larger than the bound.
float slField(float3 p, out uint rec)
{
    float d = sdRoom(p);
    rec = 0u;
    [loop] for (uint i = 1u; i <= SL_MAX; i++)
    {
        SlObject o = SL_OBJECTS[i];
        if (o.kind == K_EMPTY) continue;
        float3 v = p - o.pos;
        if (length(v) - slRadius(o.kind) * o.scale > d) continue;
        float di = slKindSd(o.kind, qRot(qConj(o.rot), v) / o.scale) * o.scale;
        if (di < d) { d = di; rec = i; }
    }
    return d;
}
float slField(float3 p) { uint r; return slField(p, r); }

// Host selection, as the shader sees it.
bool slSelected(uint id)
{
    uint n = min(_ViewportSelectionMeta.x, 64u);
    [loop] for (uint i = 0u; i < n; i++)
        if (_ViewportSelectionIds[i >> 2][i & 3u] == id) return true;
    return false;
}
// The active object's record (the gizmo's owner), or 0.
uint slActive()
{
    uint want = _ViewportSelectionMeta.y;
    if (want == 0u && _ViewportSelectionMeta.x > 0u) want = _ViewportSelectionIds[0].x;
    [loop] for (uint i = 1u; i <= SL_MAX; i++)
        if (SL_OBJECTS[i].kind != K_EMPTY && SL_OBJECTS[i].id == want && want != 0u) return i;
    return 0u;
}

// ---------------------------------------------------------------- camera
// The internal camera's ray through a normalized (top-down) image position - the DirectX Y flip
// of internal-camera-template.md, nothing local.
void slRay(float2 uv, out float3 ro, out float3 rd)
{
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 n = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 f = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    n /= n.w;
    f /= f.w;
    ro = _CameraPos;
    rd = normalize(f.xyz - n.xyz);
}
// Pixel position and clip w (w <= 0: behind the camera).
float3 slProject(float3 p, float2 res)
{
    float4 c = mul(_ViewProjMatrix, float4(p, 1.0));
    if (c.w <= 1e-5) return float3(-1e5, -1e5, -1.0);
    float2 ndc = c.xy / c.w;
    return float3(float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5) * res, c.w);
}

bool slMarch(float3 ro, float3 rd, uint steps, out float t, out uint rec)
{
    t = 0.0;
    rec = 0u;
    [loop] for (uint i = 0u; i < steps; i++)
    {
        uint r;
        float d = slField(ro + rd * t, r);
        if (d < 0.0004 * (1.0 + t)) { rec = r; return true; }
        t += d * 0.96;
        if (t > 40.0) break;
    }
    return false;
}

bool slPlaneHit(float3 ro, float3 rd, float3 p0, float3 n, out float3 hit)
{
    float den = dot(rd, n);
    hit = p0;
    if (abs(den) < 1e-4) return false;
    float t = dot(p0 - ro, n) / den;
    hit = ro + rd * t;
    return t > 0.0;
}

// ---------------------------------------------------------------- the gizmo
// A constant screen size - L is the world length that projects to SL_GIZMO_PX ui px at the pivot -
// grown when the object is near, so the rings always clear its silhouette (its bounding sphere,
// projected) and the handles sit over the room instead of over the body they move. Every pass
// builds it the same way from the same record, so what is drawn is what is hit.
struct SlGizmo { float3 pivot; float L; float ringPx; bool valid; };

SlGizmo slGizmo(float3 pivot, float radius, float2 res, float s)
{
    SlGizmo g;
    g.pivot = pivot;
    float3 vd = normalize(pivot - _CameraPos);
    float3 side = cross(vd, float3(0.0, 1.0, 0.0));
    side = (dot(side, side) > 1e-6) ? normalize(side) : float3(1.0, 0.0, 0.0);
    float3 a = slProject(pivot, res);
    float3 b = slProject(pivot + side * 0.1, res);
    float ppu = max(length(b.xy - a.xy) / 0.1, 1e-3);      // pixels per metre at the pivot
    g.valid = a.z > 0.0 && ppu > 1e-3;
    g.ringPx = clamp(radius * ppu + 14.0 * s, SL_GIZMO_PX * SL_RING * s, 0.42 * res.y);
    g.L = g.ringPx / (SL_RING * ppu);
    return g;
}
SlGizmo slGizmoOf(SlObject o, float2 res, float s) { return slGizmo(o.pos, slRadius(o.kind) * o.scale, res, s); }
float3 slArrowTip(SlGizmo g, uint i)  { return g.pivot + slAxis(i) * g.L; }
float3 slArrowBase(SlGizmo g, uint i) { return g.pivot + slAxis(i) * g.L * 0.20; }
float3 slRingPoint(SlGizmo g, uint r, float t)
{
    float3 u = slAxis((r + 1u) % 3u), v = slAxis((r + 2u) % 3u);
    return g.pivot + (u * cos(t) + v * sin(t)) * g.L * SL_RING;
}

// A ring point is a hidden line when it lies farther from the eye than the pivot.
bool slRingBack(SlGizmo g, float3 p) { return length(p - _CameraPos) > length(g.pivot - _CameraPos); }

// The handle under pixel px (arrows win over rings). Only the solid, front half of a ring can be
// grabbed: the dashed half behind the pivot usually crosses the object's own body, where a press
// means "slide".
uint slGizmoHit(float2 px, SlGizmo g, float2 res, float s)
{
    if (!g.valid) return G_NONE;
    uint h = G_NONE;
    float best = 9.0 * s;
    [unroll] for (uint i = 0u; i < 3u; i++)
    {
        float3 e = slProject(slArrowTip(g, i), res);
        float3 b = slProject(slArrowBase(g, i), res);
        if (e.z <= 0.0 || b.z <= 0.0) continue;
        float d = min(ilSdSeg(px, b.xy, e.xy), length(px - e.xy) - 4.0 * s);
        if (d < best) { best = d; h = G_MOVE_X + i; }
    }
    if (h != G_NONE) return h;
    best = 7.0 * s;
    [loop] for (uint r = 0u; r < 3u; r++)
    {
        float3 wPrev = slRingPoint(g, r, 0.0);
        float3 prev = slProject(wPrev, res);
        [loop] for (uint k = 1u; k <= SL_RING_SEG; k++)
        {
            float3 wCur = slRingPoint(g, r, (float)k * (IL_TAU / (float)SL_RING_SEG));
            float3 cur = slProject(wCur, res);
            bool back = slRingBack(g, 0.5 * (wPrev + wCur));
            wPrev = wCur;
            if (!back && prev.z > 0.0 && cur.z > 0.0)
            {
                float d = ilSdSeg(px, prev.xy, cur.xy);
                if (d < best) { best = d; h = G_TURN_X + r; }
            }
            prev = cur;
        }
    }
    return h;
}

// ---------------------------------------------------------------- the seeded arrangement
float slPackRgb(float3 c) { uint3 q = (uint3)round(saturate(c) * 255.0); return (float)(q.x | (q.y << 8) | (q.z << 16)); }
float3 slUnpackRgb(float f) { uint v = (uint)f; return float3(v & 255u, (v >> 8) & 255u, (v >> 16) & 255u) / 255.0; }

SlObject slDefault(uint i)
{
    SlObject o = (SlObject)0;
    o.rot = float4(0.0, 0.0, 0.0, 1.0);
    o.scale = 1.0;
    o.id = i;
    float3 c = float3(0.5, 0.5, 0.5);
    float yaw = 0.0;
    if (i == 1u)      { o.kind = K_VASE;  o.pos = float3(0.34, 0.0, -0.02); c = float3(0.84, 0.80, 0.72); }
    else if (i == 2u) { o.kind = K_ORB;   o.pos = float3(0.08, 0.0, -0.24); c = float3(0.74, 0.30, 0.16); }
    else if (i == 3u) { o.kind = K_RING;  o.pos = float3(-0.13, 0.0, 0.06); c = float3(0.05, 0.05, 0.055); yaw = 28.0; }
    else if (i == 4u) { o.kind = K_BLOCK; o.pos = float3(-0.38, 0.0, -0.16); c = float3(0.26, 0.34, 0.43); yaw = -22.0; }
    else if (i == 5u) { o.kind = K_CONE;  o.pos = float3(0.02, 0.0, 0.34); c = float3(0.38, 0.46, 0.33); }
    if (o.kind != K_EMPTY) o.pos.y = slBounds(o.kind).y;          // resting on the floor
    o.rot = qAxis(float3(0.0, 1.0, 0.0), radians(yaw));
    o.colour = slPackRgb(c);
    return o;
}

#endif // STILL_HLSLI
#endif // SL_RECORD_ONLY
