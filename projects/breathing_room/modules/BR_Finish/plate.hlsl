// BR_Finish / plate.hlsl -- the finish schedule's samples, per pixel.
//
// Every slot is a sample shaded with the SAME pattern families and BRDF the renderer uses
// (br_shade.hlsli), under a fixed three-light studio: balls for objects and fabrics, a flat
// grazing-lit tile for the parquet, whose identity is its layout. The board is an instrument, so
// each sample goes through ptInset: real colour, pulled back so the readouts stay readable. This
// is the content background the shared UI kit draws the cards' edges, captions and numbers over
// (ui.hlsl, from layout.hlsl's draw list).
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_floor.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "finish_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<BRRec> FinishBuf : register(t0);

// studio environment for reflections: dark warm floor, soft grey cyc, one large softbox
float3 studioEnv(float3 d)
{
    float up = d.y;
    float3 c = lerp(float3(0.035, 0.030, 0.026), float3(0.16, 0.16, 0.17), smoothstep(-0.25, 0.6, up));
    float2 box = float2(d.x + 0.45, d.y - 0.55);
    float soft = exp(-dot(box * float2(2.2, 3.0), box * float2(2.2, 3.0)) * 3.0) * step(0.0, d.z + 0.3);
    return c + float3(2.4, 2.2, 1.95) * soft;
}

float3 shadeSample(BRSurf s, float3 n, float3 v, float3 pPattern, bool glass, BRMat m)
{
    float3 Lk = normalize(float3(-0.55, 0.62, 0.56)), Lf = normalize(float3(0.85, 0.18, 0.50)), Lr = normalize(float3(0.25, 0.55, -0.80));
    float3 Ck = float3(1.00, 0.93, 0.82) * 3.1, Cf = float3(0.66, 0.76, 1.00) * 0.75, Cr = float3(1.0, 0.98, 0.95) * 1.9;
    n = normalize(n + s.bump);
    if (glass)
    {
        float NoV = saturate(dot(n, v));
        float F = 0.04 + 0.96 * pow(1.0 - NoV, 5.0);
        float3 refr = refract(-v, n, 1.0 / 1.5);
        return studioEnv(refr) * m.base * (1.0 - F) * 0.9 + studioEnv(reflect(-v, n)) * F + pow(saturate(dot(reflect(-Lk, n), v)), 400.0) * Ck * 0.5;
    }
    float3 c = 0;
    float3 d, sp;
    brDirect(s, n, v, Lk, d, sp); c += (d * s.cavity + sp) * Ck;
    brDirect(s, n, v, Lf, d, sp); c += (d * s.cavity + sp) * Cf;
    brDirect(s, n, v, Lr, d, sp); c += (d * s.cavity + sp) * Cr;
    float3 amb = lerp(float3(0.05, 0.045, 0.04), float3(0.20, 0.21, 0.23), n.y * 0.5 + 0.5);
    c += s.albedo * (1.0 - s.metal) * amb * s.cavity;
    float NoV = saturate(dot(n, v));
    float3 R = reflect(-v, n);
    c += studioEnv(R) * brEnvBRDF(s.f0, s.rough, NoV) * lerp(1.0, 0.35, s.rough);
    if (s.coat > 0.0) c += studioEnv(R) * s.coat * (0.04 + 0.96 * pow(1.0 - NoV, 5.0));
    if (s.trans > 0.0) c += brTransmit(s, n, Lr) * Cr * 1.5 + brTransmit(s, n, -v) * 0.3;
    c += s.emit;
    return c;
}

float3 tonemap(float3 c)
{
    // max-channel filmic shoulder (keeps saturated colours from chalking)
    float l = max(c.r, max(c.g, c.b));
    float k = (1.0 - exp(-l * 1.15)) / max(l, 1e-4);
    return brLinearToSrgb(c * k);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    float2 res = float2(W, H);
    float2 P = float2(tid.xy) + 0.5;
    FinishLayout L = finishLayout(res);
    float3 col = IL_FIELD;

    int i = finishCellAt(L, P);
    if (i >= 0)
    {
        float4 cr = finishCellRect(L, i);
        float cs = L.cell;
        // the card (layout.hlsl draws its edge: a value step under the pointer, the accent when selected)
        float dc = ilSdBox(P, finishCardRect(L, i), IL_RADIUS * L.s);
        ilOver(col, IL_WELL, ilFill(dc));
        float2 c = float2((cr.x + cr.z) * 0.5, cr.y + cs * 0.40);
        float R = cs * 0.29;
        BRMat m = brMatFromRec(FinishBuf[i]);
        if (m.family == FAM_PARQUET)
        {
            // flat tile, top view, grazing key so the grooves and the varnish read
            float2 q = (P - c) / R;
            if (abs(q.x) <= 1.0 && abs(q.y) <= 1.0)
            {
                float2 xz = float2(q.x, -q.y) * 0.32;            // a 64 cm tile
                BRSlat sl = brFloorSlat(xz, FLOOR_HERRINGBONE, 0.085);
                BRPatternIn pin;
                pin.p = float3(xz.x, 0.0, xz.y); pin.n = float3(0, 1, 0);
                pin.axis = float3(sl.grainDir.x, 0, sl.grainDir.y);
                pin.fp = 0.64 / (2.0 * R); pin.seed = frac((float)(sl.id & 0xFFFFu) / 65536.0 + 0.13); pin.edge = sl.edge;
                BRSurf s = brEvalSurface(m, pin, 0, false);
                // view the tile from above-front; light grazes from the upper left
                float3 n = normalize(float3(0, 1, 0) + s.bump);
                float3 v = normalize(float3(0.0, 0.9, 0.45));
                float3 Lk = normalize(float3(-0.75, 0.42, 0.50));
                float3 d, sp;
                brDirect(s, n, v, Lk, d, sp);
                float3 cc = (d * s.cavity + sp) * float3(1.0, 0.93, 0.82) * 3.4;
                cc += s.albedo * float3(0.16, 0.16, 0.17) * s.cavity;
                cc += studioEnv(reflect(-v, n).xzy * float3(1, 1, -1)) * (brEnvBRDF(s.f0, s.rough, dot(n, v)) + s.coat * 0.06);
                col = ptInset(tonemap(cc));
            }
        }
        else
        {
            float2 q = (P - c) / R;
            float r2 = dot(q, q);
            // contact shadow on the card under the ball
            float2 sh = (P - (c + float2(0.0, R * 0.98))) / float2(R * 0.95, R * 0.20);
            col *= 1.0 - 0.55 * exp(-dot(sh, sh) * 1.6);
            if (r2 <= 1.0)
            {
                float3 n = float3(q.x, -q.y, sqrt(saturate(1.0 - r2)));
                float3 v = float3(0, 0, 1);
                BRPatternIn pin;
                pin.p = n * 0.11 + float3(0.31, 0.17, 0.07) * (float)i;
                pin.n = n; pin.axis = normalize(float3(1.0, 0.25, 0.0));
                pin.fp = 0.22 / (2.0 * R); pin.seed = 0.37 + (float)i * 0.113; pin.edge = 1.0;
                if (i == MAT_PAPER) pin.seed = 0.0;
                BRSurf s = brEvalSurface(m, pin, m.base, false);
                float3 sampleCol = shadeSample(s, n, v, pin.p, m.family == FAM_GLASS, m);
                // a 1 px antialiased rim; the sample alone goes through ptInset
                float edgeAA = saturate((1.0 - sqrt(r2)) * R);
                col = lerp(col, ptInset(tonemap(sampleCol)), edgeAA);
            }
        }
    }
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
