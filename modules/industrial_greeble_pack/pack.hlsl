// industrial_greeble_pack - merges up to four GreeblePart streams.

struct GreeblePart {
    float3 anchor; float3 normal; float3 tangent; float2 uv; float3 size;
    float kind; float material; float parent_id; float seed; float active; float spare;
};

RWStructuredBuffer<GreeblePart> Out : register(u0);

GreeblePart emptyG(uint i)
{
    GreeblePart g;
    g.anchor = 0; g.normal = float3(0,1,0); g.tangent = float3(1,0,0); g.uv = 0;
    g.size = float3(0.01,0.01,0.01); g.kind = 0; g.material = 1; g.parent_id = 0;
    g.seed = (float)i; g.active = 0; g.spare = 0;
    return g;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 4096u) return;
    GreeblePart g = emptyG(i);
    uint src = i;
    uint c0 = min((uint)_Data0_Count, 2048u);
    uint c1 = min((uint)_Data1_Count, 2048u);
    uint c2 = min((uint)_Data2_Count, 2048u);
    uint c3 = min((uint)_Data3_Count, 2048u);
    if (src < c0) g = _Data0[src];
    else
    {
        src -= c0;
        if (src < c1) g = _Data1[src];
        else
        {
            src -= c1;
            if (src < c2) g = _Data2[src];
            else
            {
                src -= c2;
                if (src < c3) g = _Data3[src];
            }
        }
    }
    if (debug_greeble_kind >= 0 && (int)floor(g.kind + 0.5) != debug_greeble_kind) g.active = 0;
    if ((int)g.kind == 0 && enable_bolts == 0) g.active = 0;
    if (((int)g.kind == 2 || (int)g.kind == 4 || (int)g.kind == 5 || (int)g.kind == 7) && enable_panels == 0) g.active = 0;
    if (((int)g.kind == 6 || (int)g.kind == 8) && enable_conduit == 0) g.active = 0;
    if ((int)g.kind == 9 && enable_welds == 0) g.active = 0;
    if ((int)g.kind == 10 && enable_stains == 0) g.active = 0;
    if ((int)i >= max_greebles) g.active = 0;
    Out[i] = g;
}
