// spline_render — draws PNode paths (data:0) as glowing strokes: connects
// consecutive same-group records (pl_path emits them in order) with sdSegment,
// optional dashes + end-node dots. Data-driven replacement for hud_leaders.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWTexture2D<float4> OutputUAV : register(u0);

static const float WX = 1.78;
float2 worldToUv(float2 wp){ return float2(0.5 + wp.x / (2.0*WX), 0.5 - wp.y * 0.5); }

float sdSeg(float2 p, float2 a, float2 b, out float t)
{
    float2 pa = p - a, ba = b - a;
    t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = uv * float2(asp, 1.0);

    float lineC = 0.0;
    float dotC = 0.0;
    float w = width * 0.5;

    uint cnt = min((uint)_Data0_Count, 512u);
    [loop]
    for (uint i = 0u; i + 1u < 512u; i++)
    {
        if (i + 1u >= cnt) break;
        PNode a = _Data0[i];
        PNode b = _Data0[i + 1u];
        if (a.active < 0.5 || b.active < 0.5) continue;
        if ((int)(a.group + 0.5) != (int)(b.group + 0.5)) continue;   // same path only

        float2 ua = worldToUv(a.pos) * float2(asp, 1.0);
        float2 ub = worldToUv(b.pos) * float2(asp, 1.0);
        float t;
        float d = sdSeg(p, ua, ub, t);
        float seg = 1.0 - smoothstep(0.0, w, d);
        if (dash > 0.5)
        {
            float phase = frac((a.u + (b.u - a.u) * t) * dash_count);
            seg *= step(phase, 0.6);
        }
        lineC = max(lineC, seg);
    }

    // end-node dots at path endpoints (u==0 or u near 1)
    [loop]
    for (uint j = 0u; j < 512u; j++)
    {
        if (j >= cnt) break;
        PNode n = _Data0[j];
        if (n.active < 0.5) continue;
        if (n.u > 0.02 && n.u < 0.98) continue;
        float2 up = worldToUv(n.pos) * float2(asp, 1.0);
        dotC = max(dotC, 1.0 - smoothstep(0.0, w * 2.2, length(p - up)));
    }

    float3 col = line_color * lineC + node_color * dotC;
    col *= intensity;
    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
