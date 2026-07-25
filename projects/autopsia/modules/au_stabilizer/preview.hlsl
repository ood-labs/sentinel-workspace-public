// AUTOPSIA — the stabilizer's own inspection preview.
// Every encoded field is one the downstream graph actually depends on:
//   ring size        = scale (corner response)
//   ring brightness  = confidence
//   solid vs dashed  = matched this frame vs coasting on velocity
//   leader line      = velocity
//   rotating tick    = age
//   amber            = confidence above the significance threshold
//   faint boxes      = colony regions from the Blobs channel
#include "types.hlsli"

RWTexture2D<float4> Preview : register(u0);
StructuredBuffer<Agent> Agents : register(t1);

float segDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-6));
    return length(p - (a + ab * t));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);   // one pixel in plate units

    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * 0.30;

    // ---- colony regions ------------------------------------------------------
    uint nb = min(_Data1_Count, 16u);
    uint aw, ah;
    _Tex0.GetDimensions(aw, ah);
    float2 inv = 1.0 / float2(max((float)aw, 1.0), max((float)ah, 1.0));
    [loop] for (uint b = 0u; b < nb; ++b) {
        float2 lo = (float2(_Data1[b].x1, _Data1[b].y1) * inv - 0.5) * float2(aspect, 1.0);
        float2 hi = (float2(_Data1[b].x2, _Data1[b].y2) * inv - 0.5) * float2(aspect, 1.0);
        float2 c = (p - (lo + hi) * 0.5) / max((hi - lo) * 0.5, 1e-5);
        float onEdge = step(max(abs(c.x), abs(c.y)), 1.0) - step(max(abs(c.x), abs(c.y)), 1.0 - px * 2.0 / max((hi.y - lo.y) * 0.5, 1e-5));
        // dashed region boundary so it never competes with agent geometry
        float dash = step(0.45, frac((p.x + p.y) * 60.0));
        col += float3(0.20, 0.205, 0.195) * saturate(onEdge) * dash;
    }

    // ---- agents --------------------------------------------------------------
    float activeCount = 0.0;
    [loop] for (uint i = 0u; i < AGENT_SLOTS; ++i) {
        Agent a = Agents[i];
        if (!agentActive(a)) continue;
        activeCount += 1.0;

        float2 ap = (a.position - 0.5) * float2(aspect, 1.0);
        float2 d = p - ap;
        float dist = length(d);

        float r = 0.010 + a.scale * 0.022;
        float conf = saturate(a.confidence);
        bool matched = agentMatched(a);

        // ring, dashed while coasting
        float ringBand = 1.0 - smoothstep(px * 0.6, px * 1.7, abs(dist - r));
        float dash = matched ? 1.0 : step(0.5, frac(atan2(d.y, d.x) * 1.9099 + 0.5));
        float ring = ringBand * dash;

        // centre mark
        float core = 1.0 - smoothstep(px * 1.0, px * 2.2, dist);

        // velocity leader
        float2 lead = a.velocity * lead_scale;
        float leader = (1.0 - smoothstep(px * 0.5, px * 1.5, segDist(p, ap, ap + lead)))
                     * step(0.0008, length(lead));

        // age hand: a tick on the ring whose angle encodes elapsed lifetime
        float handAngle = a.age * 0.9;
        float2 handDir = float2(cos(handAngle), sin(handAngle));
        float hand = 1.0 - smoothstep(px * 0.5, px * 1.6,
                                      segDist(p, ap + handDir * r * 0.55, ap + handDir * r * 1.35));

        float3 ink = float3(0.72, 0.725, 0.70) * (0.32 + 0.68 * conf);
        col += ink * (ring * 0.9 + core * 0.75 + leader * 0.55 + hand * 0.6);

        // Significance is EARNED, not merely current: an agent counts as
        // established only once it has been held with high confidence for a
        // sustained period. Marked with a thin reticle bracket, never a glow —
        // amber has to stay rare enough to still mean something.
        if (conf >= significance && a.age >= establish_time && matched) {
            float bracket = 0.0;
            [unroll] for (uint k = 0u; k < 4u; ++k) {
                float sx = (k & 1u) != 0u ? 1.0 : -1.0;
                float sy = (k & 2u) != 0u ? 1.0 : -1.0;
                float2 cpt = ap + float2(sx, sy) * r * 1.55;
                bracket += 1.0 - smoothstep(px * 0.5, px * 1.4,
                                            segDist(p, cpt, cpt - float2(sx, 0.0) * r * 0.60));
                bracket += 1.0 - smoothstep(px * 0.5, px * 1.4,
                                            segDist(p, cpt, cpt - float2(0.0, sy) * r * 0.60));
            }
            col += accent_color * saturate(bracket) * 0.85;
        }
    }

    // ---- population readout --------------------------------------------------
    float4 bar = float4(0.020, 0.940, 0.480, 0.968);
    float inBar = step(bar.x, uv.x) * step(uv.x, bar.z) * step(bar.y, uv.y) * step(uv.y, bar.w);
    if (inBar > 0.5) {
        float frac_ = (uv.x - bar.x) / (bar.z - bar.x);
        float fill = activeCount / (float)AGENT_SLOTS;
        col = float3(0.030, 0.032, 0.031);
        col += float3(0.66, 0.665, 0.64) * step(frac_, fill);
        // slot ticks every 8 agents
        col += float3(0.18, 0.185, 0.175) * step(0.90, frac(frac_ * 8.0));
    }

    float2 cc = min(uv, 1.0 - uv);
    float corner = step(cc.x, 0.045) * step(cc.y, 0.005) + step(cc.y, 0.045) * step(cc.x, 0.005);
    col += float3(0.55, 0.555, 0.53) * saturate(corner);

    Preview[tid.xy] = float4(saturate(col), 1.0);
}
