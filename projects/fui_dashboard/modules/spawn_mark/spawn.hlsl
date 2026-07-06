// pl_spawn — placement distributor/decorator. Transforms a PNode stream: jitter
// positions, decimate by fraction, offset (branch) perpendicular to the path
// tangent, and re-weight. 1:1 transform, PNode -> PNode. Optional chain stage
// between pl_grid/pl_path and pl_style.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWStructuredBuffer<PNode> Out : register(u0);
float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }
float2 h22(float p){ return float2(h11(p*1.7), h11(p*3.1+5.0)); }

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 256u) return;

    PNode n;
    n.pos = float2(0,0); n.dir = float2(1,0); n.depth = 0.6;
    n.u = 0; n.v = 0; n.weight = 1; n.group = 0; n.kind = 0; n.seed = (float)i; n.active = 0;

    uint cnt = min((uint)_Data0_Count, 256u);
    if (i < cnt)
    {
        n = _Data0[i];
        if (n.active > 0.5)
        {
            float hs = h11(n.seed * 1.37 + 0.7);

            if (mode == 1 || mode == 3) {                 // Jitter / Branch
                float2 r = h22(n.seed * 2.13) - 0.5;
                float2 perp = float2(-n.dir.y, n.dir.x);
                if (mode == 3) n.pos += perp * (hs - 0.5) * 2.0 * amount;   // Branch: perp offset
                else           n.pos += r * amount;                        // Jitter: iso
            }
            if (mode == 2) {                              // Decimate
                if (hs > keep_frac) n.active = 0.0;
            }
            n.weight = saturate(n.weight * lerp(1.0, hs * 2.0, weight_jitter));
            n.depth = saturate(n.depth + (hs - 0.5) * depth_jitter);
        }
    }

    Out[i] = n;
}
