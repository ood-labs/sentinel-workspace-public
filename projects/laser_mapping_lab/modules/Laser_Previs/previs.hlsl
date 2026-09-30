// Laser_Previs / previs.hlsl: the warehouse bay in linear radiance, with the laser from Laser
// Lab's analytic scan simulation (laser_scan.hlsli) in the same world, occluded by the same
// geometry and landing on the same surfaces. (From BLINK_Previs; one laser, no projector.)
// Pass slots: _Data0/_Data1 laser world scan/fixtures, t4 tile lists, t6 fixture housing,
// t7 fog clock, _Tex8 the video projector's image (Projection input).
RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<uint> TilesA : register(t4);
Texture2D<float4> FixtureSurface : register(t6);
StructuredBuffer<float4> FogClock : register(t7);

#define FIX _Data1
#define FIX_COUNT _Data1_Count
#include "site.hlsli"
#include "laser_air.hlsli"

#define SCAN _Data0
#define SCAN_COUNT _Data0_Count
#define TILES TilesA
#define LASER_FN laserA
#include "laser_scan.hlsli"

// Integer-bit hash (frac(sin) biases at large inputs).
float hash(float3 p)
{
    uint3 q = asuint(floor(p) + 1024.0);
    uint h = q.x * 73856093u ^ q.y * 19349663u ^ q.z * 83492791u;
    h ^= h >> 13; h *= 0x5bd1e995u; h ^= h >> 15;
    return (h & 0xffffu) / 65535.0;
}

float3 projPos() { return float3(proj_x, proj_y, proj_z); }

// Angular distance between a view ray and a 3D segment, and the ray depth at the closest point.
float raySeg(float3 ro, float3 rd, float3 a, float3 b, out float tRay)
{
    float3 ab = b - a, w = ro - a;
    float bb = dot(rd, ab), cc = dot(ab, ab), dd = dot(rd, w), ee = dot(ab, w);
    float den = cc - bb * bb;
    float s = den > 1e-8 ? saturate((ee - bb * dd) / den) : 0;
    float3 q = a + s * ab;
    tRay = max(dot(q - ro, rd), 1e-3);
    return length(ro + rd * tRay - q) / tRay;
}

float3 projected(float2 uv)
{
    if (any(uv < 0) || any(uv > 1)) return 0;
    return _Tex8.SampleLevel(LinearSampler, uv, 0).rgb;
}

float boxEdge(float2 p, float2 c, float2 h) { float2 q = abs(p - c) - h; return abs(min(max(q.x, q.y), 0) + length(max(q, 0))); }

float3 drywallFace(float3 p)
{
    // Primer white, a slightly different paper tone per 1.2 m sheet.
    float sheet = floor((p.x + 2.4) / 1.2);
    float3 c = float3(0.80, 0.79, 0.76) * (0.985 + 0.03 * hash(float3(sheet, 3, 7)));
    // Mud-and-tape seams between sheets: a touch brighter and smoother.
    float seam = abs(frac((p.x + 2.4) / 1.2 + 0.5) - 0.5) * 1.2;
    if (seam < 0.06 && abs(p.x) < 2.35) c = lerp(c, float3(0.83, 0.82, 0.80), 1 - smoothstep(0.03, 0.06, seam));
    // Screw dimples on 406 mm studs, every 300 mm up.
    float2 s = float2(frac((p.x + 2.4) / 0.406 + 0.5) - 0.5, frac(p.y / 0.3 + 0.5) - 0.5) * float2(0.406, 0.3);
    if (length(s) < 0.006) c *= 0.82;
    return c;
}

float3 albedo(int mat, float3 p, float3 n)
{
    if (mat == 0)
    {
        if (n.z > 0.5) return drywallFace(p);
        if (n.z < -0.5)                       // back of the mock-up: bare studs over grey board
        {
            float stud = abs(frac((p.x + 2.4) / 0.406 + 0.5) - 0.5) * 0.406;
            return stud < 0.02 ? float3(0.42, 0.33, 0.22) : float3(0.55, 0.54, 0.52);
        }
        float core = abs(p.z + 0.0625);       // edges: board / stud / board layers
        return core < 0.046 ? float3(0.45, 0.35, 0.23) : float3(0.74, 0.73, 0.70);
    }
    if (mat == 2) return float3(0.30, 0.30, 0.29) * (0.92 + 0.08 * hash(floor(p * float3(2.5, 5, 2.5))));
    if (mat == 3) return float3(0.11, 0.12, 0.13);
    if (mat == 4)
    {
        return (p.y > 0.9 || p.y < 0.05) ? float3(0.55, 0.56, 0.57) : float3(0.035, 0.035, 0.037);
    }
    if (mat == 5) return float3(0.40, 0.30, 0.19) * (0.85 + 0.3 * hash(floor(p * float3(8, 1, 1))));
    if (mat == 6)
    {
        float3 c = float3(0.17, 0.17, 0.165) * (0.9 + 0.2 * hash(floor(p * 3)));
        float2 j = abs(frac(p.xz / 4.0 + 0.5) - 0.5) * 4.0;
        if (min(j.x, j.y) < 0.006) c *= 0.55;                           // saw-cut joints
        return c;
    }
    if (mat == 7) return float3(0.05, 0.05, 0.055);
    if (mat == 8) return float3(0.72, 0.71, 0.68);
    return 0.2;
}

// The video projector's beam in the haze: in-scatter along the camera ray inside the projector's
// cone (from the lens to the taped frame), each sample lit by the image pixel it lies on the way
// to, falling off with distance from the lens. Approximate on purpose: no occlusion, one colour
// lookup per sample. Enough to read as a projector throwing an image through the air.
float3 projectorAir(float3 ro, float3 rd, float surfaceT, float2 pixel)
{
    if (projector_haze <= 0 || projector_gain <= 0) return 0;
    float3 P = projPos();
    float t0 = 0, t1 = surfaceT;
    if (abs(rd.z) > 1e-5) { float ta = -ro.z / rd.z, tb = (P.z - ro.z) / rd.z; t0 = max(t0, min(ta, tb)); t1 = min(t1, max(ta, tb)); }
    else if (ro.z < 0 || ro.z > P.z) return 0;
    // Clip to the cone itself: the four planes from the lens through the taped frame's edges. Rays
    // that miss it (most of the screen) return here; the rest only sample the part inside it.
    float3 fc[4] = { float3(FRAME_C - FRAME_HALF, 0), float3(FRAME_C.x + FRAME_HALF.x, FRAME_C.y - FRAME_HALF.y, 0),
                     float3(FRAME_C + FRAME_HALF, 0), float3(FRAME_C.x - FRAME_HALF.x, FRAME_C.y + FRAME_HALF.y, 0) };
    float3 inside = float3(FRAME_C, 0) - P;
    [unroll] for (int k = 0; k < 4; k++)
    {
        float3 nrm = cross(fc[k] - P, fc[(k + 1) % 4] - P);
        if (dot(nrm, inside) < 0) nrm = -nrm;
        float num = dot(P - ro, nrm), den = dot(rd, nrm);
        if (abs(den) < 1e-9) { if (num > 0) return 0; }
        else { float th = num / den; if (den > 0) t0 = max(t0, th); else t1 = min(t1, th); }
    }
    if (t1 <= t0) return 0;
    // Interleaved-gradient dither rather than white noise, so the cone reads smooth, not grainy.
    const int N = 32;
    float dt = (t1 - t0) / N, jitter = frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
    float3 sum = 0;
    [loop] for (int i = 0; i < N; i++)
    {
        float3 q = ro + rd * (t0 + (i + jitter) * dt);
        if (q.z < P.z - 0.05)
        {
            float2 fuv = frameUV((P + (q - P) * (P.z / (P.z - q.z))).xy);
            if (all(fuv >= 0) && all(fuv <= 1))
            {
                float d = length(q - P);
                // A projector's black is never black: its whole cone glows faintly, the image rides on top.
                sum += (projected(fuv) + 0.06) * exp(-extinction * (d + t0 + i * dt)) / (d * d + 0.15);
            }
        }
    }
    return sum * dt * projector_gain * projector_haze * 0.12;
}

float3 shade(float2 pixel, float2 extent)
{
    float2 uv = pixel / extent;
    float3 ro = camPos(), rd = camRayAt(pixel);
    float3 n; int mat;
    float surfaceT = min(trace(ro, rd, n, mat), 1000);
    float4 fixture = FixtureSurface.Load(int3(min((uint2)pixel, (uint2)extent - 1), 0));
    bool fixtureHit = fixture.w < surfaceT;
    if (fixtureHit) surfaceT = fixture.w;
    float3 p = ro + rd * surfaceT;

    float3 sA;
    float3 air = laserA(ro, rd, uv, extent, surfaceT, p, fixtureHit, sA);

    float3 col;
    if (fixtureHit)
    {
        col = fixture.rgb * exp(-extinction * surfaceT);
    }
    else if (mat < 0)
    {
        col = 0;
    }
    else
    {
        float3 a = albedo(mat, p, n);
        float3 light = roomLight(p, n);

        // Video projector (from BLINK_Previs): the image pixel where the projector ray through p
        // meets the wall plane. Mapped onto the taped frame; anything in front of the wall catches
        // the image and casts a shadow, as on site.
        float3 P = projPos();
        float3 toP = P - p;
        if (projector_gain > 0 && p.z < P.z - 0.1 && dot(n, toP) > 0)
        {
            float3 w = P + (p - P) * (P.z / (P.z - p.z));
            float3 c = projected(frameUV(w.xy));
            if (max(max(c.r, c.g), c.b) > 0.0005 && !occluded(p + n * 0.02, P))
            {
                float lamb = saturate(dot(n, normalize(toP))) / max(normalize(toP).z, 0.2);
                light += c * projector_gain * lamb;
            }
        }
        // Laser Lab's surface term assumes a mid-grey room; weight it by the real albedo.
        col = a * (light + sA * 2) * exp(-extinction * surfaceT);
    }
    col += air;
    col += projectorAir(ro, rd, surfaceT, pixel);

    // Projector frustum edges to the taped frame, for placement checks.
    if (show_frustum > 0)
    {
        float3 P = projPos();
        float3 corners[4] = { float3(FRAME_C - FRAME_HALF, 0), float3(FRAME_C.x + FRAME_HALF.x, FRAME_C.y - FRAME_HALF.y, 0),
                              float3(FRAME_C + FRAME_HALF, 0), float3(FRAME_C.x - FRAME_HALF.x, FRAME_C.y + FRAME_HALF.y, 0) };
        [unroll] for (int k = 0; k < 4; k++)
        {
            float te;
            float d = raySeg(ro, rd, P, corners[k], te);
            if (te < surfaceT) col += float3(0.9, 0.8, 0.3) * show_frustum * exp(-pow(d / 0.0012, 2));
        }
    }
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h; OutputUAV.GetDimensions(w, h); if (id.x >= w || id.y >= h) return;
    float2 extent = float2(w, h); float3 col = 0;
    int samples = PIXEL_SAMPLES;
    [loop] for (int k = 0; k < samples; k++)
    {
        float2 jitter = float2(.5, .5);
        if (samples == 2) jitter = float2(.25 + .5 * k, .25 + .5 * k);
        else if (samples == 4) jitter = (float2(k % 2, k / 2) + .5) / 2;
        else if (samples == 8) jitter = (float2(k % 4, k / 4) + .5) / float2(4, 2);
        col += shade(id.xy + jitter, extent);
    }
    OutputUAV[id.xy] = float4(col / samples, 1);
}
