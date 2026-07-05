// link_render — draw connector vectors + orbit arc from the Links data port (data:0).
// Straight or cubic strokes, with along-length draw-on and optional dashing.

struct LinkRecord
{
    float2 a; float2 b; float2 c; float2 d;
    float width; float group_id; float style; float intensity;
    float progress; float active; float curve; float pad0;
};

RWTexture2D<float4> OutputUAV : register(u0);

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float2 bez(float2 a, float2 c, float2 d, float2 b, float t)
{
    float2 ab = lerp(a, c, t), cd = lerp(c, d, t), db = lerp(d, b, t);
    float2 x = lerp(ab, cd, t), y = lerp(cd, db, t);
    return lerp(x, y, t);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float asp = _Resolution.x / _Resolution.y;
    float2 P = (((float2)pixel + 0.5) / _Resolution.xy) * float2(asp, 1.0);

    float3 col = float3(0.0, 0.0, 0.0);
    float aAcc = 0.0;

    uint cnt = min((uint)_Data0_Count, 192u);
    [loop]
    for (uint i = 0u; i < 192u; i++)
    {
        if (i >= cnt) break;
        LinkRecord L = _Data0[i];
        if (L.active < 0.5) continue;

        float2 A = L.a * float2(asp, 1.0);
        float2 B = L.b * float2(asp, 1.0);
        float d;
        if (L.curve > 0.5)
        {
            float best = 1e9; float2 prev = A;
            [loop]
            for (int s = 1; s <= 10; s++)
            {
                float t = (float)s / 10.0;
                float2 pt = bez(L.a, L.c, L.d, L.b, t) * float2(asp, 1.0);
                best = min(best, sdSeg(P, prev, pt));
                prev = pt;
            }
            d = best;
        }
        else
        {
            d = sdSeg(P, A, B);
        }

        float tproj = saturate(dot(P - A, B - A) / max(dot(B - A, B - A), 1e-6));
        float w = L.width * width_scale;
        float m = 1.0 - smoothstep(w, w + softness, d);
        m *= step(tproj, L.progress);
        if (L.style > 0.5)
            m *= step(0.5, frac(tproj * dash_count - dash_offset - _Time * dash_speed));

        float3 tint = (L.pad0 > 0.5) ? orbit_color : link_color;
        float b = m * L.intensity;
        col = max(col, tint * b);
        aAcc = max(aAcc, m);
    }

    OutputUAV[pixel] = float4(col * intensity * (1.0 + glow), saturate(aAcc));
}
