// KA_Robot / render.hlsl — the 3D solve, once, into buffer:beauty.
//
// PER-TILE ARM CULLING is what makes a cell of forty-eight machines affordable. Each 8x8 thread
// group covers a small pixel tile, which is a narrow view cone; the group's 64 threads
// cooperatively test all 48 arms against that cone and compact the survivors into a groupshared
// list. Typically one to four arms survive, so the inner marching loop iterates over three
// bounding cylinders rather than forty-eight. Without it the map function is 48 bound tests per
// step per pixel and the whole thing collapses.
//
// The ground is intersected ANALYTICALLY rather than being a plane in the SDF. A ray skimming a
// distance-field plane takes its step count from the plane, not from the subject, and a floor is
// exactly the surface rays skim along.
//
// Alpha carries linear view depth so the scope pass can depth-test its marks against real
// geometry without solving anything a second time.
#include "arm.hlsli"

StructuredBuffer<KaRec>  Cell  : register(t0);
StructuredBuffer<KaPose> Pose  : register(t1);
StructuredBuffer<KaBall> Rally : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

#define KM_BALL 6.0

groupshared uint gCount;
groupshared uint gList[48];
// THE BALL GETS A CULL VOTE OF ITS OWN.
//
// The march used to be gated on `gCount > 0` — at least one ARM surviving this tile's cone test.
// The ball is in the distance field, but a tile of empty sky contains no arms, so those tiles
// skipped marching entirely and the ball simply stopped existing above the machines. It read as
// the ball clipping through an invisible ceiling, and the "ceiling" was exactly the top of the
// arms' bounding cylinders.
//
// The lesson generalises past this bug: a culling scheme is a claim about EVERYTHING the field
// can contain, so anything added to the field later has to be added to the cull too, or it
// silently exists only where something else already does.
groupshared uint gBall;

float2 mapScene(float3 p)
{
    float2 best = float2(1e9, KM_BODY);
    uint n = min(gCount, KA_MAX_ARMS);
    for (uint i = 0u; i < n; i++)
    {
        uint a = gList[i];
        float2 d = ka_arm(p, Cell[KA_ARM_0 + a], Pose[KA_ARM_0 + a], cable_dress, ka_toolDrawR(Rally[KA_STATS]));
        if (d.x < best.x) best = d;
    }
    // The ball is one sphere, so it is never worth culling — and it must be IN the field rather
    // than composited, because its shadow on the floor is the only cue that says how high it is.
    KaBall b = Rally[KA_HEADER];
    if (b.role != KA_PLAY_IDLE)
    {
        float d = length(p - b.pos) - b.radius;
        if (d < best.x) best = float2(d, KM_BALL);
    }
    return best;
}
float mapD(float3 p) { return mapScene(p).x; }

// tetrahedron normal: four taps instead of six
float3 calcNormal(float3 p, float e)
{
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * mapD(p + k.xyy * e) +
                     k.yyx * mapD(p + k.yyx * e) +
                     k.yxy * mapD(p + k.yxy * e) +
                     k.xxx * mapD(p + k.xxx * e));
}

float softShadow(float3 ro, float3 rd, float tmin, float tmax, float k, int steps)
{
    if (steps <= 0) return 1.0;
    float res = 1.0;
    float t = tmin;
    for (int i = 0; i < steps; i++)
    {
        float h = mapD(ro + rd * t);
        res = min(res, k * h / max(t, 1e-3));
        t += clamp(h, 0.015, 0.55);
        if (res < 0.004 || t > tmax) break;
    }
    return saturate(res);
}

float calcAO(float3 p, float3 n, int samples)
{
    if (samples <= 0) return 1.0;
    float occ = 0.0, sca = 1.0;
    for (int i = 0; i < samples; i++)
    {
        float hr = 0.012 + 0.11 * (float)i / max((float)samples, 1.0);
        float dd = mapD(p + n * hr);
        occ += (hr - dd) * sca;
        sca *= 0.80;
    }
    return saturate(1.0 - 2.4 * occ);
}

// ---------------------------------------------------------------------------
// look
// ---------------------------------------------------------------------------
float3 liveryColour()
{
    int l = (int)livery;
    if (l == 1) return float3(0.150, 0.155, 0.168);
    if (l == 2) return float3(0.905, 0.660, 0.045);
    if (l == 3) return float3(0.800, 0.760, 0.685);
    if (l == 4) return float3(0.085, 0.245, 0.470);
    return float3(0.855, 0.290, 0.040);          // KUKA orange
}

// The beach ball's panels. Six gores alternating white with three colours, which is the thing
// that makes the object instantly readable as a beach ball rather than as a sphere — and the
// gores rotating is the only cue that says it is spinning.
float3 ballPanel(float3 p)
{
    KaBall b = Rally[KA_HEADER];
    float3 l = normalize(p - b.pos);

    float ang = length(b.spin);
    if (ang > 1e-4)
    {
        float3 ax = b.spin / ang;
        float c = cos(ang), s = sin(ang);
        l = l * c + cross(ax, l) * s + ax * dot(ax, l) * (1.0 - c);
    }

    float a = atan2(l.z, l.x) / KA_TAU + 0.5;
    float g = a * 6.0;
    int gi = ((int)g) % 6;
    float3 col = float3(0.86, 0.86, 0.85);            // the white gores
    if (gi == 1) col = float3(0.80, 0.10, 0.09);      // red
    if (gi == 3) col = float3(0.88, 0.66, 0.05);      // yellow
    if (gi == 5) col = float3(0.07, 0.30, 0.62);      // blue

    // seams, and the darker moulded caps at the poles
    float seam = 1.0 - smoothstep(0.0, 0.05, min(frac(g), 1.0 - frac(g)));
    col *= 1.0 - seam * 0.55;
    col *= 1.0 - smoothstep(0.86, 0.99, abs(l.y)) * 0.45;
    return col;
}

void materialOf(float mat, float3 p, out float3 alb, out float rough, out float spec)
{
    int m = (int)(mat + 0.5);
    if (m == 6)      { alb = ballPanel(p); rough = 0.42; spec = 0.30; }
    else if (m == 1) { alb = float3(0.048, 0.048, 0.052); rough = 0.78; spec = 0.16; }
    else if (m == 2) { alb = float3(0.115, 0.120, 0.130); rough = 0.22; spec = 0.85; }
    else if (m == 3) { alb = float3(0.040, 0.048, 0.066); rough = 0.55; spec = 0.30; }
    else if (m == 4) { alb = float3(0.030, 0.030, 0.033); rough = 0.62; spec = 0.24; }
    else if (m == 5) { alb = float3(0.068, 0.070, 0.076); rough = 0.48; spec = 0.35; }
    else
    {
        alb = liveryColour();
        rough = 0.34; spec = 0.44;
        // cast texture: a fine sand grain in the paint, kept very low so it reads as surface
        // rather than as noise
        float g = frac(sin(dot(floor(p * 260.0), float3(12.99, 78.23, 37.71))) * 43758.545);
        alb *= 1.0 + (g - 0.5) * 0.10 * wear;
    }
}

void lightRig(out float3 kd, out float3 kc, out float3 fd, out float3 fc,
              out float3 rd2, out float3 rc, out float amb)
{
    int r = (int)light_rig;
    if (r == 1)      // Hard Key
    {
        kd = normalize(float3(0.62, 0.58, -0.42)); kc = float3(3.10, 2.95, 2.75);
        fd = normalize(float3(-0.70, 0.30, 0.55)); fc = float3(0.16, 0.18, 0.24);
        rd2 = normalize(float3(-0.20, 0.35, -0.90)); rc = float3(0.30, 0.30, 0.36);
        amb = 0.16;
    }
    else if (r == 2) // Rim Cage
    {
        kd = normalize(float3(0.10, 0.75, 0.30)); kc = float3(0.55, 0.55, 0.60);
        fd = normalize(float3(-0.88, 0.22, -0.42)); fc = float3(1.35, 1.20, 1.00);
        rd2 = normalize(float3(0.86, 0.26, -0.46)); rc = float3(0.95, 1.05, 1.35);
        amb = 0.10;
    }
    else if (r == 3) // Overcast
    {
        kd = normalize(float3(-0.12, 0.94, 0.30)); kc = float3(1.25, 1.26, 1.30);
        fd = normalize(float3(0.60, 0.30, 0.60)); fc = float3(0.42, 0.44, 0.50);
        rd2 = normalize(float3(-0.55, 0.28, -0.70)); rc = float3(0.30, 0.31, 0.36);
        amb = 0.52;
    }
    else             // Studio
    {
        kd = normalize(float3(-0.42, 0.82, 0.48)); kc = float3(2.25, 2.18, 2.08);
        fd = normalize(float3(0.72, 0.34, 0.42)); fc = float3(0.52, 0.55, 0.62);
        rd2 = normalize(float3(0.16, 0.30, -0.92)); rc = float3(0.46, 0.48, 0.56);
        amb = 0.34;
    }
}

float3 backdrop(float3 rd)
{
    int g = (int)ground_kind;
    float h = saturate(rd.y * 1.7 + 0.30);
    if (g == 0) return lerp(float3(1.00, 0.995, 0.985), float3(0.760, 0.775, 0.815), h);
    if (g == 1) return lerp(float3(0.052, 0.055, 0.064), float3(0.016, 0.018, 0.024), h);
    if (g == 2) return lerp(float3(0.040, 0.044, 0.055), float3(0.010, 0.011, 0.016), h);
    return lerp(float3(0.020, 0.020, 0.024), float3(0.005, 0.005, 0.007), h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint3 Gid : SV_GroupID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    float2 res = float2(W, H);
    uint lin = GTid.y * 8u + GTid.x;

    if (lin == 0u) { gCount = 0u; gBall = 0u; }
    GroupMemoryBarrierWithGroupSync();

    float3 ro = _CameraPos;

    // ---- the tile's view cone ----
    float2 t0 = float2(Gid.xy) * 8.0;
    float3 axis = float3(0, 0, 0);
    float3 corner[4];
    {
        float2 cs[4] = { t0, t0 + float2(8.0, 0.0), t0 + float2(0.0, 8.0), t0 + float2(8.0, 8.0) };
        for (int i = 0; i < 4; i++)
        {
            float2 su = cs[i] / res;
            float2 ndc = float2(su.x * 2.0 - 1.0, 1.0 - su.y * 2.0);
            float4 nw = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
            float4 fw = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
            nw /= nw.w; fw /= fw.w;
            corner[i] = normalize(fw.xyz - nw.xyz);
            axis += corner[i];
        }
        axis = normalize(axis);
    }
    float cosHalf = 1.0;
    for (int ci = 0; ci < 4; ci++) cosHalf = min(cosHalf, dot(axis, corner[ci]));
    float angCone = acos(clamp(cosHalf, -1.0, 1.0)) + 0.010;

    // ---- cooperative cull: 64 threads, 48 arms, one test each ----
    if (lin < KA_MAX_ARMS)
    {
        KaRec r = Cell[KA_ARM_0 + lin];
        KaPose q = Pose[KA_ARM_0 + lin];
        if (r.active > 0.5 && q.live > 0.5)
        {
            KaSpec sp = ka_spec(r.kind, r.size.x);
            float rise = ka_rise(sp, r.size.y);
            float reach = ka_reach(sp);
            float3 c = float3(r.pos.x, rise * 0.5, r.pos.y);
            float R = length(float2(reach, rise * 0.5)) * 1.06;
            float3 v = c - ro;
            float L = length(v);
            bool keep = false;
            if (L < R + 0.25) keep = true;
            else if (L - R < max_dist)
            {
                float angA = acos(clamp(dot(v / L, axis), -1.0, 1.0));
                float angR = asin(saturate(R / L));
                keep = (angA - angR) <= angCone;
            }
            if (keep)
            {
                uint slot;
                InterlockedAdd(gCount, 1u, slot);
                if (slot < 48u) gList[slot] = lin;
            }
        }
    }
    // the ball, tested against the same cone by one thread
    if (lin == 1u)
    {
        KaBall bh = Rally[KA_HEADER];
        if (bh.role != KA_PLAY_IDLE)
        {
            float R = bh.radius * 1.10;
            float3 v = bh.pos - ro;
            float L = length(v);
            bool keep = false;
            if (L < R + 0.25) keep = true;
            else if (L - R < max_dist)
            {
                float angA = acos(clamp(dot(v / L, axis), -1.0, 1.0));
                float angR = asin(saturate(R / L));
                keep = (angA - angR) <= angCone;
            }
            if (keep) gBall = 1u;
        }
    }
    GroupMemoryBarrierWithGroupSync();

    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;

    // ---- primary ray, from the injected internal camera with the DirectX Y flip ----
    float2 screenUV = ((float2)pixel + 0.5) / res;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);
    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w; farW /= farW.w;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float maxD = max_dist;
    bool hasGround = ((int)ground_kind != 3);
    float tGround = (hasGround && rd.y < -1e-4 && ro.y > 0.0) ? (-ro.y / rd.y) : 1e9;
    float tLimit = min(maxD, tGround);

    // ---- march the arms ----
    int steps = (int)march_steps;
    float t = 0.02;
    float2 hit = float2(-1.0, 0.0);
    if (gCount > 0u || gBall != 0u)
    {
        for (int i = 0; i < steps; i++)
        {
            float3 p = ro + rd * t;
            float2 d = mapScene(p);
            // relative epsilon: a machine forty metres away does not deserve millimetre steps
            if (d.x < 0.00085 * t + 0.0009) { hit = float2(t, d.y); break; }
            t += d.x * 0.92;
            if (t > tLimit) break;
        }
    }

    float3 kd, kc, fd, fc, rdir, rc; float amb;
    lightRig(kd, kc, fd, fc, rdir, rc, amb);

    float3 col;
    float depth;

    if (hit.x > 0.0)
    {
        float3 p = ro + rd * hit.x;
        float3 n = calcNormal(p, max(0.0006 * hit.x, 0.0009));
        float3 alb; float rough, spec;
        materialOf(hit.y, p, alb, rough, spec);

        float sh = softShadow(p + n * 0.012, kd, 0.02, 14.0, 11.0, (int)shadow_steps);
        float ao = calcAO(p, n, (int)ao_samples);

        float3 lit = alb * amb * ao * lerp(float3(0.72, 0.76, 0.86), float3(1, 1, 1), 0.4);
        lit += alb * kc * max(dot(n, kd), 0.0) * sh;
        lit += alb * fc * max(dot(n, fd), 0.0) * 0.60;
        lit += alb * rc * max(dot(n, rdir), 0.0) * 0.45;

        // one specular lobe per light, cheap Blinn
        float shin = lerp(6.0, 128.0, 1.0 - rough);
        float3 v = -rd;
        lit += kc * spec * pow(max(dot(n, normalize(kd + v)), 0.0), shin) * sh * 0.55;
        lit += rc * spec * pow(max(dot(n, normalize(rdir + v)), 0.0), shin) * 0.35;

        // fresnel rim against the backdrop keeps a dark casting from dissolving into a dark set
        float fres = pow(saturate(1.0 - max(dot(n, v), 0.0)), 4.0);
        lit += backdrop(reflect(rd, n)) * fres * lerp(0.10, 0.55, 1.0 - rough);

        col = lit;
        depth = hit.x;
    }
    else if (hasGround && tGround < maxD)
    {
        float3 p = ro + rd * tGround;
        float3 n = float3(0, 1, 0);
        int g = (int)ground_kind;

        float3 alb = float3(0.90, 0.90, 0.905);
        float gloss = 0.06;
        if (g == 1) { alb = float3(0.055, 0.058, 0.066); gloss = 0.38; }
        if (g == 2)
        {
            alb = float3(0.045, 0.048, 0.058);
            float2 gr = abs(frac(p.xz + 0.5) - 0.5);
            float2 gr5 = abs(frac(p.xz / 5.0 + 0.5) - 0.5) * 5.0;
            float line1 = 1.0 - smoothstep(0.006, 0.020, min(gr.x, gr.y));
            float line5 = 1.0 - smoothstep(0.012, 0.034, min(gr5.x, gr5.y));
            alb += float3(0.030, 0.034, 0.044) * line1 + float3(0.075, 0.082, 0.100) * line5;
            gloss = 0.20;
        }

        float sh = softShadow(p + n * 0.010, kd, 0.02, 16.0, 9.0, (int)shadow_steps);
        float ao = calcAO(p, n, min((int)ao_samples, 4));

        float3 lit = alb * amb * ao;
        lit += alb * kc * max(dot(n, kd), 0.0) * sh * 0.85;
        lit += alb * fc * max(dot(n, fd), 0.0) * 0.30;
        float fres = pow(saturate(1.0 - max(dot(n, -rd), 0.0)), 4.0);
        lit += backdrop(reflect(rd, n)) * fres * gloss * 2.2;

        // Fade the floor into the backdrop instead of drawing a horizon line. A studio sweep
        // has no horizon, and neither should this.
        float fade = saturate((tGround - maxD * 0.30) / max(maxD * 0.62, 1e-3));
        col = lerp(lit, backdrop(rd), fade * fade);
        depth = tGround;
    }
    else
    {
        col = backdrop(rd);
        depth = maxD * 4.0;
    }

    OutputUAV[pixel] = float4(col, depth);
}
