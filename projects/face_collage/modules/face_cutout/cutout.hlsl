// face_cutout — cuts an elliptical patch of the LIVE face (_Tex0 = Face_DS) around each tracked
// eye/mouth anchor and stamps it at a stepped-jittered position, output as a straight-alpha layer
// for the Accum feedback canvas to bake. Every `stamp_rate` seconds the jitter steps to a new
// spot near the feature, so imprints scatter and pile up instead of stacking in place.
// _Tex0 = face; _Data0 = Face_Stitch anchors. Draw pass, one quad per anchor.

static const uint MAX_NODES = 16;

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight;
    float group; float kind; float seed; float active;
};

struct VS_OUT {
    float4 Position : SV_POSITION;
    float2 SampleUV : TEXCOORD0;
    float2 LocalUV  : TEXCOORD1;
    float  Valid    : TEXCOORD2;
};

static const float2 QUAD_OFFSETS[6] = {
    float2(-1,-1), float2(1,-1), float2(1,1),
    float2(-1,-1), float2(1,1), float2(-1,1)
};
static const float2 QUAD_UVS[6] = {
    float2(0,0), float2(1,0), float2(1,1),
    float2(0,0), float2(1,1), float2(0,1)
};

float2 hash2(float2 p){
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return frac(sin(p) * 43758.5453);
}

VS_OUT VSMain(uint vid : SV_VertexID)
{
    VS_OUT o;
    uint rec = vid / 6u;
    uint corner = vid % 6u;

    PNode n = _Data0[min(rec, MAX_NODES - 1u)];
    if (rec >= MAX_NODES || rec >= (uint)_Data0_Count || n.active < 0.5)
    {
        o.Position = float4(0, 0, -999, 1);
        o.SampleUV = 0; o.LocalUV = 0; o.Valid = 0;
        return o;
    }

    float outAspect = _Resolution.x / max(1.0, _Resolution.y);
    float2 aspect = float2(1.0 / outAspect, 1.0);
    float hw = max(0.03, n.weight) * stamp_scale;

    // stepped jitter: a new scatter position every 1/stamp_rate seconds
    float step = floor(_Time * stamp_rate);
    float2 j = (hash2(float2(step, n.seed * 3.7 + 1.0)) - 0.5) * spread;

    float2 drawCenter = n.pos + j;
    float2 local = QUAD_OFFSETS[corner] * aspect * hw;
    float2 ndc = drawCenter + local;

    // sample the face at the feature's REAL location (image uv, y-down)
    float2 featUV = float2(n.pos.x * 0.5 + 0.5, 0.5 - n.pos.y * 0.5);
    float2 win = float2(hw * aspect.x, hw) * sample_scale;
    o.SampleUV = featUV + (QUAD_UVS[corner] - 0.5) * win * float2(1.0, -1.0);

    o.Position = float4(ndc, 0.0, 1.0);
    o.LocalUV = QUAD_UVS[corner];
    o.Valid = 1.0;
    return o;
}

float4 PSMain(VS_OUT i) : SV_TARGET
{
    if (i.Valid < 0.5) discard;
    float2 d = (i.LocalUV - 0.5) * 2.0;
    float mask = smoothstep(1.0, 1.0 - edge_soft, length(d));   // soft ellipse
    if (mask <= 0.01) discard;
    float3 col = _Tex0.SampleLevel(LinearSampler, saturate(i.SampleUV), 0).rgb;
    return float4(col, mask);
}
