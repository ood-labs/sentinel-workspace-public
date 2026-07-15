// dada_scatter preview — front-view (X-Y) MAP of the scattered accent field: every
// active accent drawn as a disc at its world position, sized by scale, tinted by
// material, depth-shaded by z.

struct DadaPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float p0; float p1; float p2; float active;
};

StructuredBuffer<DadaPart> Parts : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float2 W_MIN = float2(-3.7, -0.4);
static const float2 W_MAX = float2(3.7, 9.8);

float3 previewCol(float mat, int k)
{
    if (mat < 2.5)  return float3(0.10, 0.10, 0.12);
    if (mat < 3.5)  return float3(0.92, 0.92, 0.90);
    if (mat < 10.5) return float3(0.86, 0.16, 0.12);
    if (mat < 11.5) return float3(0.95, 0.78, 0.12);
    if (mat < 14.5) return float3(0.55, 0.55, 0.57);
    if (mat < 15.5) return float3(0.12, 0.12, 0.14);
    if (mat < 16.5) return float3(0.95, 0.95, 0.92);
    return float3(0.85, 0.66, 0.24);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 w = lerp(W_MIN, W_MAX, float2(uv.x, 1.0 - uv.y));
    float pxw = (W_MAX.x - W_MIN.x) / _Resolution.x;

    float3 col = lerp(float3(0.09, 0.10, 0.13), float3(0.15, 0.14, 0.12), uv.y);
    col = lerp(col, float3(0.30, 0.26, 0.20), smoothstep(pxw * 1.5, 0.0, abs(w.y)));

    float bestZ = -1e9;
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        DadaPart d = Parts[i];
        if (d.active < 0.5) continue;
        float rad = max(max(d.sc_xy.x, d.sc_xy.y), 0.05);
        float dist = length(w - d.pos_xy);
        float edge = smoothstep(rad + pxw, rad - pxw, dist);
        if (edge > 0.01 && d.pos_z > bestZ)
        {
            bestZ = d.pos_z;
            float3 c = previewCol(d.mat, (int)d.kind);
            float shade = 0.72 + 0.28 * saturate(d.pos_z * 0.5 + 0.5);
            col = lerp(col, c * shade, edge);
        }
    }
    OutputUAV[px] = float4(col, 1.0);
}
