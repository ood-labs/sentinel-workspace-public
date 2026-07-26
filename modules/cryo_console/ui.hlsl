// CRYOGRAM / CONSOLE — the authored instrument surface.
//
// Plan view, deliberately. The relief is the performance image, but you cannot
// place a point on a perspective landscape without unprojecting it, so editing
// happens on the specimen in plan where a click IS a field coordinate. The 3D
// consequence is shown live in the witness thumbnail instead of guessed at.
//
// Nothing here duplicates a Properties slider. Numeric shaping stays in
// Properties; this surface owns placement, painting, and the coupled gate.

#include "layout.hlsli"
#include "../_shared/ui/sui_core.hlsli"
#include "../_shared/ui/sui_typography.hlsli"

struct Probe {
    float2 pos;
    float radius;
    float strength;
    float kind;
    float age;
    float id;
    float active;
};

StructuredBuffer<Probe> Probes : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const uint MAXP = 32u;
static const float3 INK   = float3(0.93, 0.93, 0.94);
static const float3 DIM   = float3(0.34, 0.34, 0.37);
static const float3 FAINT = float3(0.17, 0.17, 0.19);
static const float3 AMBER = float3(1.00, 0.66, 0.22);

float3 texBilinear(Texture2D<float4> tex, float2 uv) {
    uint w, h;
    tex.GetDimensions(w, h);
    if (w == 0u || h == 0u) return float3(0, 0, 0);
    float2 t = saturate(uv) * float2(w, h) - 0.5;
    int2 b = (int2)floor(t);
    float2 f = t - (float2)b;
    int2 mx = int2(w, h) - 1;
    float3 c00 = tex.Load(int3(clamp(b + int2(0, 0), int2(0, 0), mx), 0)).rgb;
    float3 c10 = tex.Load(int3(clamp(b + int2(1, 0), int2(0, 0), mx), 0)).rgb;
    float3 c01 = tex.Load(int3(clamp(b + int2(0, 1), int2(0, 0), mx), 0)).rgb;
    float3 c11 = tex.Load(int3(clamp(b + int2(1, 1), int2(0, 0), mx), 0)).rgb;
    return lerp(lerp(c00, c10, f.x), lerp(c01, c11, f.x), f.y);
}

float cryoStr(SuiContext c, float2 atPx, SuiTextStyle st, int codes[10], int n) {
    float cov = 0.0;
    float adv = 6.0 * st.scalePx + st.trackingPx;
    [loop] for (int i = 0; i < n; ++i) {
        cov = max(cov, suiGlyph(c, (atPx + float2((float)i * adv, 0.0)) * c.invResolution, st, codes[i]));
    }
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    SuiContext c = suiContext(id.xy, _Resolution.xy);
    ConsoleLayout L = cryoLayout(_Resolution.xy);
    float2 P = c.pixel;
    float2 inv = c.invResolution;

    SuiTextStyle body = suiTextStyleTracked(1.5, 0.0, -1.5);
    SuiTextStyle small = suiTextStyleTracked(1.0, 0.0, -1.0);

    Probe hdr = Probes[MAXP];
    float gateX = hdr.strength;
    float gateY = hdr.kind;

    // probe state is owned by the specimen and arrives as a data input
    float kind = 0.0, brush = 0.075;
    int probeN = 0;
    if (_Data2_Count > 32u) {
        kind = _Data2[32].pos.y;
        brush = _Data2[32].radius;
        probeN = (int)_Data2[32].id;
    }

    float3 col = float3(0.005, 0.005, 0.006);

    // ================= header ==============================================
    {
        int T[10] = { 67, 82, 89, 79, 71, 82, 65, 77, 32, 32 };   // CRYOGRAM
        suiComposite(col, INK, cryoStr(c, float2(L.margin, L.headerH * 0.34), body, T, 8));
        int S[10] = { 67, 79, 78, 83, 79, 76, 69, 32, 32, 32 };   // CONSOLE
        suiComposite(col, DIM, cryoStr(c, float2(L.margin + 9.0 * 7.5, L.headerH * 0.34), body, S, 7));
        suiComposite(col, FAINT, suiLinePx(c, float2(0.0, L.headerH) * inv,
                                              float2(_Resolution.x, L.headerH) * inv, 1.0));
    }

    // ================= stage: plan view of the specimen =====================
    bool inStage = cryoInRect(P, L.stage);
    if (inStage) {
        float2 sUv = (P - L.stage.xy) / max(L.stage.zw - L.stage.xy, float2(1.0, 1.0));
        col = texBilinear(_Tex1, sUv) * plan_exposure;

        // --- measured bonds, in the same plan coordinates -------------------
        uint fCount = min(_Data1_Count, 160u);
        [loop] for (uint fi = 0u; fi < fCount; ++fi) {
            if (_Data1[fi].weight <= 0.0) continue;
            float2 pa = L.stage.xy + _Data1[fi].a * (L.stage.zw - L.stage.xy);
            float2 pb = L.stage.xy + _Data1[fi].b * (L.stage.zw - L.stage.xy);
            float2 lo = min(pa, pb) - 4.0, hi = max(pa, pb) + 4.0;
            if (P.x < lo.x || P.x > hi.x || P.y < lo.y || P.y > hi.y) continue;
            float2 ab = pb - pa;
            float t = saturate(dot(P - pa, ab) / max(dot(ab, ab), 1e-6));
            float d = length(P - (pa + ab * t));
            float cov = 1.0 - smoothstep(0.7, 1.8, d);
            suiComposite(col, INK, cov * 0.75 * overlay_gain);
        }

        // --- tracked identities ---------------------------------------------
        uint tCount = min(_Data0_Count, 97u);
        [loop] for (uint ti = 0u; ti < tCount; ++ti) {
            if (_Data0[ti].active < 0.5) continue;
            float2 tp = L.stage.xy + _Data0[ti].position * (L.stage.zw - L.stage.xy);
            if (distance(P, tp) > 14.0) continue;
            bool conf = _Data0[ti].confidence >= 0.90;
            float r = 3.0 + 4.0 * saturate(_Data0[ti].confidence);
            float ring = 1.0 - smoothstep(0.7, 1.8, abs(length(P - tp) - r));
            suiComposite(col, conf ? AMBER : DIM, ring * (conf ? 1.0 : 0.5) * overlay_gain);
        }

        // --- probes authored on the specimen, echoed in plan ------------------
        uint pCount = min(_Data2_Count, MAXP);
        [loop] for (uint pi = 0u; pi < pCount; ++pi) {
            Probe pr = _Data2[pi];
            if (pr.active < 0.5) continue;
            float2 pp = L.stage.xy + pr.pos * (L.stage.zw - L.stage.xy);
            float rr = pr.radius * (L.stage.z - L.stage.x);
            if (distance(P, pp) > rr + 12.0) continue;

            float3 pc = (pr.kind < 0.5) ? AMBER : ((pr.kind < 1.5) ? float3(0.86, 0.30, 0.26) : INK);
            float dr = abs(length(P - pp) - rr);

            // SEED solid ring, ANNEAL dashed, ANCHOR bracketed
            float ring = 1.0 - smoothstep(0.8, 2.0, dr);
            if (pr.kind > 0.5 && pr.kind < 1.5) {
                float a = atan2(P.y - pp.y, P.x - pp.x);
                ring *= step(0.45, frac(a * 3.2));
            }
            suiComposite(col, pc, ring * 0.95);

            float2 e1 = float2(5.0, 0.0), e2 = float2(0.0, 5.0);
            suiComposite(col, pc, suiLinePx(c, (pp - e1) * inv, (pp + e1) * inv, 1.0) * 0.9);
            suiComposite(col, pc, suiLinePx(c, (pp - e2) * inv, (pp + e2) * inv, 1.0) * 0.9);
            suiComposite(col, pc, (1.0 - smoothstep(rr * 0.0, rr, length(P - pp))) * 0.10);
        }

    }

    // stage frame + corner registration
    {
        float4 sr = L.stage / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, DIM, suiStrokeRect(c, sr, 1.0) * 0.85);
        float2 fp[4] = { L.stage.xy, float2(L.stage.z, L.stage.y),
                         float2(L.stage.x, L.stage.w), L.stage.zw };
        [unroll] for (int k = 0; k < 4; ++k) {
            suiComposite(col, INK, suiLinePx(c, (fp[k] - float2(8.0, 0.0)) * inv, (fp[k] + float2(8.0, 0.0)) * inv, 1.0) * 0.9);
            suiComposite(col, INK, suiLinePx(c, (fp[k] - float2(0.0, 8.0)) * inv, (fp[k] + float2(0.0, 8.0)) * inv, 1.0) * 0.9);
        }
    }

    // ================= footer: tension pad ==================================
    {
        float4 pr = L.pad / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, FAINT, suiFillRect(c, pr) * 0.55);
        suiComposite(col, DIM, suiStrokeRect(c, pr, 1.0));
        if (cryoInRect(P, L.pad)) {
            float2 g = float2(L.pad.x + gateX * (L.pad.z - L.pad.x),
                              L.pad.w - gateY * (L.pad.w - L.pad.y));
            suiComposite(col, FAINT, suiGridPx(c, max((L.pad.z - L.pad.x) / 4.0, 4.0), 1.0) * 0.5);
            suiComposite(col, AMBER, suiLinePx(c, float2(L.pad.x, g.y) * inv, float2(L.pad.z, g.y) * inv, 1.0) * 0.55);
            suiComposite(col, AMBER, suiLinePx(c, float2(g.x, L.pad.y) * inv, float2(g.x, L.pad.w) * inv, 1.0) * 0.55);
            suiComposite(col, AMBER, (1.0 - smoothstep(2.4, 4.0, length(P - g))));
        }
        int G[10] = { 71, 65, 84, 69, 32, 32, 32, 32, 32, 32 };  // GATE
        suiComposite(col, DIM, cryoStr(c, float2(L.pad.x, L.pad.y - 12.0), small, G, 4));
    }

    // ================= footer: probe kind selector ==========================
    {
        float bw = (L.kinds.z - L.kinds.x) / 3.0;
        [unroll] for (int b = 0; b < 3; ++b) {
            float4 rr = float4(L.kinds.x + bw * b + 2.0, L.kinds.y, L.kinds.x + bw * (b + 1) - 2.0, L.kinds.w);
            float4 rn = rr / float4(_Resolution.xy, _Resolution.xy);
            bool on = ((int)kind == b);
            suiComposite(col, on ? float3(0.14, 0.14, 0.15) : float3(0.035, 0.035, 0.04), suiFillRect(c, rn));
            suiComposite(col, on ? AMBER : DIM, suiStrokeRect(c, rn, 1.0));

            float2 ta = float2(rr.x + 8.0, (rr.y + rr.w) * 0.5 - 4.0);
            if (b == 0) { int A[10] = { 83, 69, 69, 68, 32, 32, 32, 32, 32, 32 };
                          suiComposite(col, on ? INK : DIM, cryoStr(c, ta, small, A, 4)); }
            if (b == 1) { int A[10] = { 65, 78, 78, 69, 65, 76, 32, 32, 32, 32 };
                          suiComposite(col, on ? INK : DIM, cryoStr(c, ta, small, A, 6)); }
            if (b == 2) { int A[10] = { 65, 78, 67, 72, 79, 82, 32, 32, 32, 32 };
                          suiComposite(col, on ? INK : DIM, cryoStr(c, ta, small, A, 6)); }
        }
    }

    // ================= footer: telemetry ====================================
    {
        int liveT = 0, confT = 0, bonds = 0;
        uint tc = min(_Data0_Count, 97u);
        [loop] for (uint i = 0u; i < tc; ++i) {
            if (_Data0[i].active < 0.5) continue;
            liveT++;
            if (_Data0[i].confidence >= 0.90) confT++;
        }
        uint fc = min(_Data1_Count, 160u);
        [loop] for (uint j = 0u; j < fc; ++j) if (_Data1[j].weight > 0.0) bonds++;

        float ty = L.kinds.y - 30.0;
        float tx = L.kinds.x;
        int LT[10] = { 84, 82, 75, 32, 32, 32, 32, 32, 32, 32 };
        int LC[10] = { 67, 78, 70, 32, 32, 32, 32, 32, 32, 32 };
        int LB[10] = { 66, 78, 68, 32, 32, 32, 32, 32, 32, 32 };
        int LP[10] = { 80, 82, 66, 32, 32, 32, 32, 32, 32, 32 };
        float step_ = max((L.kinds.z - L.kinds.x) / 4.0, 50.0);

        suiComposite(col, DIM, cryoStr(c, float2(tx, ty), small, LT, 3));
        suiComposite(col, INK, suiInteger(c, float2(tx + 24.0, ty) * inv, small, liveT, 3));
        suiComposite(col, DIM, cryoStr(c, float2(tx + step_, ty), small, LC, 3));
        suiComposite(col, AMBER, suiInteger(c, float2(tx + step_ + 24.0, ty) * inv, small, confT, 3));
        suiComposite(col, DIM, cryoStr(c, float2(tx + step_ * 2.0, ty), small, LB, 3));
        suiComposite(col, INK, suiInteger(c, float2(tx + step_ * 2.0 + 24.0, ty) * inv, small, bonds, 3));
        suiComposite(col, DIM, cryoStr(c, float2(tx + step_ * 3.0, ty), small, LP, 3));
        suiComposite(col, AMBER, suiInteger(c, float2(tx + step_ * 3.0 + 24.0, ty) * inv, small, probeN, 3));
    }

    // ================= footer: live 3D witness ==============================
    {
        if (cryoInRect(P, L.witness)) {
            float2 wUv = (P - L.witness.xy) / max(L.witness.zw - L.witness.xy, float2(1.0, 1.0));
            col = texBilinear(_Tex2, wUv) * witness_exposure;
        }
        float4 wr = L.witness / float4(_Resolution.xy, _Resolution.xy);
        suiComposite(col, DIM, suiStrokeRect(c, wr, 1.0));
        int W[10] = { 51, 68, 32, 32, 32, 32, 32, 32, 32, 32 };   // "3D"
        suiComposite(col, DIM, cryoStr(c, float2(L.witness.x, L.witness.y - 12.0), small, W, 2));
    }

    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
