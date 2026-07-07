// blob_layout preview — front-view (X-Y) MAP of the arrangement: every active part drawn
// as a disc at its world position, sized by scale, tinted by its palette gradient, nearest-z
// wins. So the node preview shows the layout you're authoring, not a debug strip.
#include "../_shared/palette.hlsli"

struct BlobPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};

StructuredBuffer<BlobPart> Parts : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float2 W_MIN = float2(-2.6, -3.9);
static const float2 W_MAX = float2(2.6, 3.9);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 w = lerp(W_MIN, W_MAX, float2(uv.x, 1.0 - uv.y));   // y-up
    float pxw = (W_MAX.x - W_MIN.x) / _Resolution.x;

    float3 col = str_studio(float2(uv.x, 1.0 - uv.y)) * 0.6;   // dim studio backdrop

    float bestZ = -1e9;
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        BlobPart d = Parts[i];
        if (d.active < 0.5) continue;
        float rad = max(d.sc_xy.x, d.sc_xy.y) * 0.85;
        float dist = length(w - d.pos_xy);
        float edge = smoothstep(rad + pxw, rad - pxw, dist);
        if (edge > 0.01 && d.pos_z > bestZ)
        {
            bestZ = d.pos_z;
            float3 c;
            if ((int)d.mat == 2)      c = str_palette(STR_LIME);       // checker
            else if ((int)d.mat == 1) c = float3(0.6, 0.6, 0.62);      // chrome
            else c = str_grad((int)d.colA, (int)d.colB, 0.5);
            float shade = 0.72 + 0.28 * saturate(d.pos_z * 0.6 + 0.5);
            float ring = smoothstep(rad - pxw * 2.0, rad, dist);
            c = lerp(c * shade, c * 0.45, ring);
            col = lerp(col, c, edge);
        }
    }
    OutputUAV[px] = float4(col, 1.0);
}
