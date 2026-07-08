// face_cutout draw — one quad per Clone. With history_on, copies >=1 sample the face DELAY LINE:
// the frame from `copyIdx*delay_time` seconds ago (interpolated between captured frames) at the
// clone's already-delayed UV — so image and crop are delayed in tandem. Copy 0 stays current/sharp.
// _Tex0 = face, ClonesIn = clones, HistoryIn = face ring.
#include "cutout_common.hlsli"

StructuredBuffer<Clone>    ClonesIn  : register(t1);   // t0 = _Tex0 (face)
StructuredBuffer<float4>   HistoryIn : register(t2);

struct VS_OUT {
    float4 Position : SV_POSITION;
    float2 SampleUV : TEXCOORD0;
    float2 LocalUV  : TEXCOORD1;
    float  Valid    : TEXCOORD2;
    float  Htf      : TEXCOORD3;   // ring time to sample, or <0 for current _Tex0
};

static const float2 QUAD_OFFSETS[6] = {
    float2(-1,-1), float2(1,-1), float2(1,1),
    float2(-1,-1), float2(1,1), float2(-1,1)
};
static const float2 QUAD_UVS[6] = {
    float2(0,0), float2(1,0), float2(1,1),
    float2(0,0), float2(1,1), float2(0,1)
};

float3 fetchH(uint slot, int2 q)
{
    q = clamp(q, int2(0, 0), int2((int)HW - 1, (int)HH - 1));
    return HistoryIn[slot * HW * HH + (uint)q.y * HW + (uint)q.x].rgb;
}
float3 slotBil(uint slot, float2 uv)
{
    uv = saturate(uv);
    float2 fp = uv * float2((float)HW, (float)HH) - 0.5;
    int2 ip = (int2)floor(fp); float2 f = frac(fp);
    float3 a = lerp(fetchH(slot, ip + int2(0, 0)), fetchH(slot, ip + int2(1, 0)), f.x);
    float3 b = lerp(fetchH(slot, ip + int2(0, 1)), fetchH(slot, ip + int2(1, 1)), f.x);
    return lerp(a, b, f.y);
}
float3 sampleFaceRing(float htf, float2 uv)          // bilinear in space + linear in time
{
    float s0 = floor(htf); float fr = htf - s0;
    uint sA = ((uint)max(s0, 0.0)) % HF;
    uint sB = ((uint)max(s0, 0.0) + 1u) % HF;
    return lerp(slotBil(sA, uv), slotBil(sB, uv), fr);
}

VS_OUT VSMain(uint vid : SV_VertexID)
{
    VS_OUT o;
    uint inst = vid / 6u;
    uint corner = vid % 6u;

    Clone c = ClonesIn[min(inst, MAX_NODES * MAX_COPIES - 1u)];
    if (inst >= MAX_NODES * MAX_COPIES || c.active < 0.5)
    {
        o.Position = float4(0, 0, -999, 1);
        o.SampleUV = 0; o.LocalUV = 0; o.Valid = 0; o.Htf = -1;
        return o;
    }

    uint copyIdx = inst / MAX_NODES;
    o.Htf = (history_on != 0 && copyIdx >= 1u) ? ringTimeFor(copyIdx) : -1.0;

    float2 local = QUAD_OFFSETS[corner] * c.ext;
    float2 ndc = c.pos + local;
    o.SampleUV = c.uv + (QUAD_UVS[corner] - 0.5) * c.win * float2(1.0, -1.0);
    o.Position = float4(ndc, 0.0, 1.0);
    o.LocalUV = QUAD_UVS[corner];
    o.Valid = 1.0;
    return o;
}

float4 PSMain(VS_OUT i) : SV_TARGET
{
    if (i.Valid < 0.5) discard;
    float2 p = (i.LocalUV - 0.5) * 2.0;
    int shape = (int)edge_mode;

    float nd;
    if (shape == 1)       nd = max(abs(p.x), abs(p.y));
    else if (shape == 2)  nd = pow(pow(abs(p.x), 4.0) + pow(abs(p.y), 4.0), 0.25);
    else                  nd = length(p);

    float mask = smoothstep(1.0, 1.0 - edge_soft, nd);
    if (mask <= 0.01) discard;

    float3 col;
    if (i.Htf < 0.0) col = _Tex0.SampleLevel(LinearSampler, saturate(i.SampleUV), 0).rgb;
    else             col = sampleFaceRing(i.Htf, i.SampleUV);

    if (border_on != 0)
    {
        float be = smoothstep(1.0 - border_width - edge_soft, 1.0 - border_width, nd);
        col = lerp(col, border_color, be * border_alpha);
    }
    return float4(col, mask);
}
