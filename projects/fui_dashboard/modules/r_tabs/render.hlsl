// pl_render — the previewable cloner renderer: takes a PNode placement stream
// (data:0) + the primitive atlas (input:0) and renders THIS chain's widgets to a
// full texture. Combines pl_style's mapping (kind/scale/tier/rot modes) with the
// atlas stamp + depth-camera projection. Because each chain owns a pl_render, its
// node preview shows exactly what that chain draws — edit it and watch it.
//   _Tex0 = primitive atlas (R=body, G=core)   _Data0 = PNode placement

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWTexture2D<float4> OutputUAV : register(u0);

static const float WX = 1.78;
float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }
float2 worldToUv(float2 wp){ return float2(0.5 + wp.x / (2.0*WX), 0.5 - wp.y * 0.5); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float2 camDrift = float2(sin(_Time * cam_speed), cos(_Time * cam_speed * 0.8)) * cam_amp;
    int kset[4] = { kind0, kind1, kind2, kind3 };
    int setN = max(min(set_size, 4), 1);

    float3 col = float3(0,0,0);
    float aAcc = 0.0;

    uint cnt = min((uint)_Data0_Count, 256u);

    // optional boundary frame: bounding box of THIS chain's active point cloud
    float2 bbmin = float2(1e9, 1e9), bbmax = float2(-1e9, -1e9);
    float bbZsum = 0.0; int bbN = 0;
    if (boundary > 0.5)
    {
        [loop]
        for (uint bi = 0u; bi < 256u; bi++)
        {
            if (bi >= cnt) break;
            PNode bn = _Data0[bi];
            if (bn.active < 0.5) continue;
            if (h11(bn.seed * 0.913 + 0.1) > density) continue;
            bbmin = min(bbmin, bn.pos); bbmax = max(bbmax, bn.pos);
            bbZsum += bn.depth; bbN++;
        }
    }

    [loop]
    for (uint i = 0u; i < 256u; i++)
    {
        if (i >= cnt) break;
        PNode n = _Data0[i];
        if (n.active < 0.5) continue;
        if (h11(n.seed * 0.913 + 0.1) > density) continue;

        float hs = h11(n.seed * 2.17 + 1.3);

        // ---- style mapping (pl_style logic) ----
        int kind;
        if (kind_mode == 0)      kind = (int)(n.kind + 0.5);
        else if (kind_mode == 1) kind = fixed_kind;
        else if (kind_mode == 2) kind = kset[(int)i % setN];
        else if (kind_mode == 3) kind = kset[(int)(hs * (float)setN)];
        else                     kind = kset[(int)(n.group + 0.5) % setN];

        float sf;
        if (scale_mode == 0)      sf = 1.0;
        else if (scale_mode == 1) sf = lerp(0.4, 1.0, n.weight);
        else if (scale_mode == 2) sf = lerp(0.6, 1.0, n.depth);
        else                      sf = lerp(0.5, 1.0, hs);
        float2 scl = float2(scale_base * scale_aspect, scale_base) * (1.0 + scale_var * (hs - 0.5) * 2.0) * sf;

        float tier;
        if (tier_mode == 0)      tier = fixed_tier;
        else if (tier_mode == 1) tier = (n.weight > 0.66) ? 2.0 : 1.0;
        else if (tier_mode == 2) tier = (fmod(n.group, 2.0) < 0.5) ? 2.0 : 1.0;
        else                     tier = (hs < 0.3) ? 2.0 : 1.0;

        float rot;
        if (rot_mode == 0)      rot = atan2(n.dir.y, n.dir.x) + rot_offset;
        else if (rot_mode == 1) rot = fixed_rot;
        else                    rot = hs * 6.2831853;

        // ---- atlas stamp + depth camera (widget_render logic) ----
        float z = saturate(n.depth);
        float2 par = camDrift * (z - 0.5) * parallax;
        float dScale = lerp(1.0 - depth_scale, 1.0 + depth_scale, z);
        float2 cuv = worldToUv(n.pos + par);
        float2 half2 = max(scl * dScale, 1e-4);

        float2 pw = uv - cuv;
        float2 dwrld = float2(pw.x * 2.0 * WX, -pw.y * 2.0);
        float maxH = max(half2.x, half2.y) * 1.7;
        if (dot(dwrld, dwrld) > maxH * maxH) continue;

        float cs = cos(-rot), sn = sin(-rot);
        float2 rp = float2(dwrld.x*cs - dwrld.y*sn, dwrld.x*sn + dwrld.y*cs);
        float2 lp = rp / half2;
        if (abs(lp.x) >= 1.0 || abs(lp.y) >= 1.0) continue;

        int ccol = kind & 7;
        int crow = (kind >> 3) & 3;
        float2 luv = clamp(lp * 0.5 + 0.5, 0.004, 0.996);
        float2 auv = (float2((float)ccol, (float)crow) + luv) / float2(8.0, 4.0);
        float2 s = _Tex0.SampleLevel(LinearSampler, auv, 0).rg;
        if (s.r + s.g <= 0.001) continue;

        float fog = lerp(depth_fog, 1.0, z);
        float bodyAmt = (tier < 1.0) ? lerp(0.45, 1.0, saturate(tier)) : 1.0;
        float coreAmt = saturate(tier - 1.0);
        float b = s.r * fog * bodyAmt;
        float c = (s.g + s.r * coreAmt * 0.7) * fog;

        col += body_color * b * body_gain + core_color * c;
        aAcc = max(aAcc, saturate(b + c));
    }

    // draw the boundary frame around the padded point-cloud bounds
    if (boundary > 0.5 && bbN > 0 && bbmax.x > bbmin.x)
    {
        float avgZ = bbZsum / (float)bbN;
        float2 par = camDrift * (avgZ - 0.5) * parallax;   // track the layer's parallax
        float2 lo = bbmin - boundary_pad, hi = bbmax + boundary_pad;
        float2 pwrld = float2((uv.x - 0.5) * 2.0 * WX, (0.5 - uv.y) * 2.0) - par;
        float bw = boundary_width;
        bool spanY = pwrld.y > lo.y - bw && pwrld.y < hi.y + bw;
        bool spanX = pwrld.x > lo.x - bw && pwrld.x < hi.x + bw;
        float onV = (min(abs(pwrld.x - lo.x), abs(pwrld.x - hi.x)) < bw && spanY) ? 1.0 : 0.0;
        float onH = (min(abs(pwrld.y - lo.y), abs(pwrld.y - hi.y)) < bw && spanX) ? 1.0 : 0.0;
        float frame = saturate(onV + onH);
        col += body_color * frame * boundary_intensity * body_gain;
        aAcc = max(aAcc, frame);
    }

    OutputUAV[pixel] = float4(col * intensity, saturate(aAcc));
}
