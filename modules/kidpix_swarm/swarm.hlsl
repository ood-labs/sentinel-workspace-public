// kidpix_swarm — stamps the Kid Pix rubber-stamp icon atlas at each PNode placement, with a
// per-instance high-frequency stepped JITTER (the buzzing rubber-stamp look). Consumes a PNode
// placement stream (data:0, from pl_grid Scatter -> pl_spawn Jitter) and the icon atlas (input:0).
// Each node -> an atlas cell (hashed from its seed) drawn upright with a small size. Hard-edged
// flat color from the atlas, premultiplied-alpha output. Self-animating jitter on _Time.
//   _Tex0 = stamp atlas (rgb=color, a=coverage, 4x4 grid)   _Data0 = PNode placements

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWTexture2D<float4> OutputUAV : register(u0);

float h11(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float2 h22(float p){ return float2(h11(p*1.7), h11(p*3.1+5.0)); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;

    uint cnt = min((uint)_Data0_Count, 256u);
    // jitter stepped WITHIN the loop so the buzz repeats seamlessly each cycle
    float jstep = floor(frac(_Time / loop_seconds) * jit_steps);

    float3 col = 0.0; float aAcc = 0.0;

    [loop] for (uint i = 0u; i < 256u; i++)
    {
        if (i >= cnt) break;
        PNode n = _Data0[i];
        if (n.active < 0.5) continue;

        // node pos -> canvas uv (pos in ~[-1,1]); scale about canvas center + offset
        float2 base = float2(0.5 + n.pos.x * 0.5, 0.5 - n.pos.y * 0.5);
        float2 cuv = (base - 0.5) * place_scale + 0.5 + float2(place_offset_x, place_offset_y);

        // per-instance stepped jitter (a few px)
        float2 jit = (h22(jstep * 0.013 + n.seed * 7.0) - 0.5) * jitter_amt;
        cuv += jit;

        // size (small), with slight per-instance variation
        float hs = h11(n.seed * 2.17 + 1.3);
        float sz = stamp_size * (1.0 + size_var * (hs - 0.5) * 2.0);
        float2 half2 = float2(sz / aspect, sz);      // keep square on screen

        float2 d = uv - cuv;
        float2 lp = d / max(half2, 1e-5);            // local [-1,1]
        if (abs(lp.x) >= 1.0 || abs(lp.y) >= 1.0) continue;

        // choose atlas cell from seed
        int k = (int)(h11(n.seed * 3.9 + 0.2) * 16.0);
        int ac = k & 3, ar = (k >> 2) & 3;
        float2 luv = clamp(lp * 0.5 + 0.5, 0.001, 0.999);
        float2 auv = (float2((float)ac, (float)ar) + luv) / 4.0;
        float4 s = _Tex0.SampleLevel(LinearSampler, auv, 0);
        if (s.a <= 0.01) continue;

        // premultiplied over accumulation (paint stamps are opaque; later = on top)
        col = s.rgb * s.a + col * (1.0 - s.a);
        aAcc = s.a + aAcc * (1.0 - s.a);
    }

    OutputUAV[px] = float4(col, aAcc) * intensity;
}
