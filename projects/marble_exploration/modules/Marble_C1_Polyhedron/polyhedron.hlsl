// c1_polyhedron: ray-traced icosahedron whose triangular faces stellate into a metallic star.
RWTexture2D<float4> OutputUAV : register(u0);

static const float PI = 3.14159265359;
static const float PHI = 1.61803398875;

struct Hit
{
    float t;
    float3 n;
    float3 pos;
    float3 bc;
    int face;
    int side;
};

float3 rotX(float3 p, float a)
{
    float s = sin(a), c = cos(a);
    return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

float3 rotY(float3 p, float a)
{
    float s = sin(a), c = cos(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

float3 rotZ(float3 p, float a)
{
    float s = sin(a), c = cos(a);
    return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

float3 getVert(int i)
{
    float3 v = float3(0.0, 0.0, 0.0);
    if (i == 0) v = float3(-1,  PHI, 0);
    if (i == 1) v = float3( 1,  PHI, 0);
    if (i == 2) v = float3(-1, -PHI, 0);
    if (i == 3) v = float3( 1, -PHI, 0);
    if (i == 4) v = float3(0, -1,  PHI);
    if (i == 5) v = float3(0,  1,  PHI);
    if (i == 6) v = float3(0, -1, -PHI);
    if (i == 7) v = float3(0,  1, -PHI);
    if (i == 8) v = float3( PHI, 0, -1);
    if (i == 9) v = float3( PHI, 0,  1);
    if (i == 10) v = float3(-PHI, 0, -1);
    if (i == 11) v = float3(-PHI, 0,  1);
    return normalize(v);
}

int3 getFace(int i)
{
    int3 f = int3(0, 0, 0);
    if (i == 0) f = int3(0, 11, 5);
    if (i == 1) f = int3(0, 5, 1);
    if (i == 2) f = int3(0, 1, 7);
    if (i == 3) f = int3(0, 7, 10);
    if (i == 4) f = int3(0, 10, 11);
    if (i == 5) f = int3(1, 5, 9);
    if (i == 6) f = int3(5, 11, 4);
    if (i == 7) f = int3(11, 10, 2);
    if (i == 8) f = int3(10, 7, 6);
    if (i == 9) f = int3(7, 1, 8);
    if (i == 10) f = int3(3, 9, 4);
    if (i == 11) f = int3(3, 4, 2);
    if (i == 12) f = int3(3, 2, 6);
    if (i == 13) f = int3(3, 6, 8);
    if (i == 14) f = int3(3, 8, 9);
    if (i == 15) f = int3(4, 9, 5);
    if (i == 16) f = int3(2, 4, 11);
    if (i == 17) f = int3(6, 2, 10);
    if (i == 18) f = int3(8, 6, 7);
    if (i == 19) f = int3(9, 8, 1);
    return f;
}

float triIntersect(float3 ro, float3 rd, float3 a, float3 b, float3 c, out float3 bc)
{
    float3 e1 = b - a;
    float3 e2 = c - a;
    float3 p = cross(rd, e2);
    float det = dot(e1, p);
    if (abs(det) < 1e-5) { bc = 0; return -1.0; }
    float invDet = 1.0 / det;
    float3 tv = ro - a;
    float u = dot(tv, p) * invDet;
    if (u < 0.0 || u > 1.0) { bc = 0; return -1.0; }
    float3 q = cross(tv, e1);
    float v = dot(rd, q) * invDet;
    if (v < 0.0 || u + v > 1.0) { bc = 0; return -1.0; }
    float t = dot(e2, q) * invDet;
    bc = float3(1.0 - u - v, u, v);
    return t;
}

void testTri(inout Hit best, float3 ro, float3 rd, float3 a, float3 b, float3 c, int face, int side)
{
    float3 bc;
    float t = triIntersect(ro, rd, a, b, c, bc);
    if (t > 0.01 && t < best.t)
    {
        best.t = t;
        best.pos = ro + rd * t;
        best.n = normalize(cross(b - a, c - a));
        if (dot(best.n, rd) > 0.0) best.n = -best.n;
        best.bc = bc;
        best.face = face;
        best.side = side;
    }
}

float3 envColor(float3 r, float3 n, int face)
{
    float sky = saturate(0.5 + 0.5 * r.y);
    float pink = pow(saturate(dot(r, normalize(float3(-0.65, 0.2, 0.72)))), 2.0);
    float green = pow(saturate(dot(r, normalize(float3(0.42, 0.75, -0.48)))), 2.2);
    float white = pow(saturate(dot(r, normalize(float3(-0.15, 0.82, 0.55)))), 10.0);
    float id = frac((float)face * 0.173);

    float3 col = lerp(float3(0.025, 0.018, 0.026), float3(0.64, 0.61, 0.70), sky);
    col += float3(0.95, 0.40, 0.58) * pink * (0.55 + 0.35 * id);
    col += float3(0.44, 0.72, 0.40) * green * (0.35 + 0.25 * (1.0 - id));
    col += float3(1.0, 0.96, 0.91) * white * 1.25;
    col *= 0.56 + 0.44 * saturate(n.y * 0.75 + 0.55);
    return col;
}

float3 shade(Hit h, float3 rd, float compact)
{
    float3 n = normalize(h.n);
    float3 v = normalize(-rd);
    float3 l = normalize(float3(-0.35, 0.68, 0.62));
    float3 r = reflect(rd, n);
    float ndl = saturate(dot(n, l));
    float fres = pow(1.0 - saturate(dot(n, v)), 4.0);
    float spec = pow(saturate(dot(reflect(-l, n), v)), 70.0);
    float edge = min(h.bc.x, min(h.bc.y, h.bc.z));
    float edgeLine = smoothstep(0.035, 0.0, edge);

    float3 metal = envColor(r, n, h.face);
    float centerPink = pow(saturate(dot(n, normalize(float3(-0.08, 0.18, 0.98)))), 4.0);
    float radius = length(h.pos);
    float tipDark = smoothstep(0.30, 1.05, radius);
    float hub = exp(-dot(h.pos, h.pos) * 3.2);

    float3 col = metal * (0.30 + 0.70 * ndl);
    col += float3(1.0, 0.92, 0.88) * spec * (1.4 + gloss);
    col += float3(0.95, 0.36, 0.54) * centerPink * (0.32 + 0.65 * (1.0 - compact));
    col += float3(1.0, 0.86, 0.58) * hub * (0.52 + 0.28 * (1.0 - compact));

    float rimGreen = pow(saturate(dot(n, normalize(float3(0.0, 0.94, -0.34)))), 5.0);
    col += float3(0.55, 0.90, 0.45) * rimGreen * 0.36;
    col = lerp(col, col * 0.16, saturate((-n.z - 0.1) * 1.1));
    col = lerp(col, col * 0.35, tipDark * (0.50 + 0.30 * (1.0 - compact)));
    col += float3(0.95, 0.45, 0.62) * (1.0 - tipDark) * (1.0 - compact) * 0.20;
    float shadowFacet = smoothstep(0.55, 0.05, ndl);
    float awayFacet = smoothstep(0.30, -0.18, n.z);
    float idDark = step(0.62, frac((float)h.face * 0.37 + (float)h.side * 0.19));
    float darkAmt = saturate(max(shadowFacet * 0.72, awayFacet * 0.86) + idDark * 0.16);
    col = lerp(col, float3(0.018, 0.014, 0.020) + col * 0.10, darkAmt);
    col += edgeLine * edge_brightness * lerp(float3(0.98, 0.88, 0.96), float3(0.72, 0.95, 0.64), frac((float)h.face * 0.31));
    col = pow(saturate(col), 1.18);
    return saturate(col * exposure * 0.92);
}

void traceScene(float2 uv, out float4 outCol)
{
    float animTime = (phase_manual >= 0.0) ? phase_manual : (_Time + phase_offset);
    float loopT = animTime / loop_seconds;
    float cycleT = frac(animTime / cycle_seconds);
    float pulse = 0.5 - 0.5 * cos(cycleT * 2.0 * PI);
    pulse = pow(saturate(pulse), pulse_shape);

    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p -= float2(center_x, center_y);

    float3 ro = float3(0.0, 0.0, cam_dist);
    float3 rd = normalize(float3(p / focal, -1.0));

    float yaw = loopT * 2.0 * PI * yaw_turns + yaw_offset;
    float pitch = 0.35 + sin(loopT * 2.0 * PI * pitch_turns + 0.4) * pitch_amp;
    float roll = -0.18 + sin(loopT * 2.0 * PI * roll_turns + 1.1) * roll_amp;

    Hit best;
    best.t = 1e9;
    best.n = float3(0.0, 0.0, 1.0);
    best.pos = 0;
    best.bc = 0;
    best.face = 0;
    best.side = 0;

    float scale = object_scale;
    float extrude = lerp(compact_extrude, max_extrude, pulse);
    float baseKeep = smoothstep(0.92, 0.10, pulse);

    [loop]
    for (int i = 0; i < 20; ++i)
    {
        int3 fi = getFace(i);
        float3 a = getVert(fi.x);
        float3 b = getVert(fi.y);
        float3 c = getVert(fi.z);
        float3 cen = normalize((a + b + c) / 3.0);
        float3 fn = normalize(cross(b - a, c - a));
        if (dot(fn, cen) < 0.0) fn = -fn;
        float3 cen0 = (a + b + c) / 3.0;
        float inset = lerp(0.62, 0.36, pulse);
        float3 ta = lerp(a, cen0, inset) + fn * extrude;
        float3 tb = lerp(b, cen0, inset) + fn * extrude;
        float3 tc = lerp(c, cen0, inset) + fn * extrude;

        a *= scale; b *= scale; c *= scale;
        ta *= scale; tb *= scale; tc *= scale;
        a = rotZ(rotX(rotY(a, yaw), pitch), roll);
        b = rotZ(rotX(rotY(b, yaw), pitch), roll);
        c = rotZ(rotX(rotY(c, yaw), pitch), roll);
        ta = rotZ(rotX(rotY(ta, yaw), pitch), roll);
        tb = rotZ(rotX(rotY(tb, yaw), pitch), roll);
        tc = rotZ(rotX(rotY(tc, yaw), pitch), roll);

        testTri(best, ro, rd, a, b, c, i, 0);

        testTri(best, ro, rd, ta, tb, tc, i, 4);
        testTri(best, ro, rd, a, b, tb, i, 1);
        testTri(best, ro, rd, a, tb, ta, i, 1);
        testTri(best, ro, rd, b, c, tc, i, 2);
        testTri(best, ro, rd, b, tc, tb, i, 2);
        testTri(best, ro, rd, c, a, ta, i, 3);
        testTri(best, ro, rd, c, ta, tc, i, 3);
    }

    if (best.t < 1e8)
    {
        float compact = 1.0 - pulse;
        float3 col = shade(best, rd, compact);
        outCol = float4(col, 1.0);
    }
    else
    {
        outCol = float4(0.0, 0.0, 0.0, 0.0);
    }
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    float4 acc = 0.0;
    if (aa_samples <= 1)
    {
        traceScene(uv, acc);
    }
    else
    {
        float2 texel = 1.0 / _Resolution.xy;
        float4 c0, c1, c2, c3;
        traceScene(uv + texel * float2(-0.25, -0.25), c0);
        traceScene(uv + texel * float2( 0.25, -0.25), c1);
        traceScene(uv + texel * float2(-0.25,  0.25), c2);
        traceScene(uv + texel * float2( 0.25,  0.25), c3);
        acc = (c0 + c1 + c2 + c3) * 0.25;
    }

    OutputUAV[px] = float4(saturate(acc.rgb), saturate(acc.a));
}
