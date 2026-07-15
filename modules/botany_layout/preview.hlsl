// botany_layout preview — front-view (X-Y) map of the arrangement: every active part drawn as a
// disc at its world position, sized by scale, tinted by kind. Nearest-z wins. Shows the layout.
struct Part {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};
StructuredBuffer<Part> Parts : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float2 W_MIN = float2(-1.4, -0.6);
static const float2 W_MAX = float2( 1.4,  2.0);

float3 kindCol(int k){
    if (k==0) return float3(0.95,0.45,0.10);   // blade
    if (k==1) return float3(0.95,0.35,0.55);   // petal
    if (k==2) return float3(0.95,0.70,0.15);   // cone
    if (k==3) return float3(0.62,0.68,0.80);   // berry
    if (k==4) return float3(0.10,0.08,0.16);   // wire
    return float3(1.0,0.86,0.10);              // stamen
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 w = lerp(W_MIN, W_MAX, float2(uv.x, 1.0-uv.y));   // y-up

    float3 col = float3(0.42,0.28,0.75);                     // violet backdrop
    float bestZ = -1e9;
    uint n = min((uint)_Resolution.x, 128u); n = 128u;
    [loop] for (uint i=0u;i<128u;i++){
        Part p = Parts[i];
        if (p.active < 0.5) continue;
        float2 c = p.pos_xy;
        float r = max(p.sc_xy.x, p.sc_xy.y) * 0.5;
        if (length(w-c) < r && p.pos_z > bestZ){
            bestZ = p.pos_z;
            col = kindCol((int)p.kind);
        }
    }
    OutputUAV[px] = float4(col, 1.0);
}
