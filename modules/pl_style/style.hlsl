// pl_style — maps PNode placement records (data:0) to Widget records for
// widget_render. Decouples WHERE (pl_grid/pl_path) from WHAT (primitive kind,
// scale, tier, rotation). Kind/scale/tier/rot each have a selectable mode.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

struct Widget {
    float2 pos; float depth; float rot;
    float2 scale; float kind; float value;
    float2 p01; float2 p23;
    float tier; float active; float group; float seed;
};

RWStructuredBuffer<Widget> Out : register(u0);

float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 256u) return;

    Widget w;
    w.pos = float2(0,0); w.depth = 0.5; w.rot = 0; w.scale = float2(0.05,0.05);
    w.kind = 0; w.value = value_base; w.p01 = float2(0,0); w.p23 = float2(0,0);
    w.tier = 1; w.active = 0; w.group = 0; w.seed = (float)i;

    uint cnt = min((uint)_Data0_Count, 256u);
    if (i < cnt)
    {
        PNode n = _Data0[i];
        if (n.active > 0.5 && h11(n.seed * 0.913 + 0.1) <= density)
        {
            float hs = h11(n.seed * 2.17 + 1.3);

            // kind — Cycle/Hash/ByGroup pick from an explicit 4-primitive set
            int kset[4] = { kind0, kind1, kind2, kind3 };
            int setN = max(min(set_size, 4), 1);
            int k;
            if (kind_mode == 0)      k = (int)(n.kind + 0.5);              // FromNode
            else if (kind_mode == 1) k = fixed_kind;                       // Fixed
            else if (kind_mode == 2) k = kset[(int)i % setN];             // Cycle
            else if (kind_mode == 3) k = kset[(int)(hs * (float)setN)];   // Hash
            else                     k = kset[(int)(n.group + 0.5) % setN]; // ByGroup

            // scale factor
            float sf;
            if (scale_mode == 0)      sf = 1.0;                       // Uniform
            else if (scale_mode == 1) sf = lerp(0.4, 1.0, n.weight); // ByWeight
            else if (scale_mode == 2) sf = lerp(0.6, 1.0, n.depth);  // ByDepth
            else                      sf = lerp(0.5, 1.0, hs);       // Hash
            float2 sc = float2(scale_base * scale_aspect, scale_base) * (1.0 + scale_var * (hs - 0.5) * 2.0) * sf;

            // tier
            float tier;
            if (tier_mode == 0)      tier = fixed_tier;                       // Fixed
            else if (tier_mode == 1) tier = (n.weight > 0.66) ? 2.0 : 1.0;    // ByWeight
            else if (tier_mode == 2) tier = (fmod(n.group, 2.0) < 0.5) ? 2.0 : 1.0; // GroupParity
            else                     tier = (hs < 0.3) ? 2.0 : 1.0;           // Hash

            // rotation
            float rot;
            if (rot_mode == 0)      rot = atan2(n.dir.y, n.dir.x) + rot_offset; // FromDir
            else if (rot_mode == 1) rot = fixed_rot;                           // Fixed
            else                    rot = hs * 6.2831853;                      // Hash

            w.pos = n.pos; w.depth = n.depth; w.rot = rot; w.scale = sc;
            w.kind = (float)k; w.value = value_base; w.tier = tier;
            w.group = n.group; w.seed = n.seed; w.active = 1.0;
        }
    }

    Out[i] = w;
}
