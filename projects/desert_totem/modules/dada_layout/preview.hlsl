// dada_layout preview — a real front-view (X-Y) MAP of the arrangement you're
// authoring: every active part drawn as a disc at its world position, sized by scale,
// tinted by material, depth-shaded by z. So the node preview shows the layout, not a
// debug strip.

struct DadaPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float p0; float p1; float p2; float active;
};

StructuredBuffer<DadaPart> Parts : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// world extents shown in the map
static const float2 W_MIN = float2(-3.7, -0.4);
static const float2 W_MAX = float2(3.7, 9.8);

float3 previewCol(float mat, int k)
{
    if (k == 7)  return float3(0.30, 0.62, 0.52);   // beach ball
    if (k == 6)  return float3(0.85, 0.30, 0.72);   // rainbow lens
    if (k == 5)  return float3(0.96, 0.96, 0.97);   // crescent
    if (k == 10) return float3(0.92, 0.80, 0.16);   // harlequin
    if (mat < 2.5)  return float3(0.10, 0.10, 0.12);
    if (mat < 3.5)  return float3(0.92, 0.92, 0.90);
    if (mat < 10.5) return float3(0.86, 0.16, 0.12);
    if (mat < 11.5) return float3(0.95, 0.78, 0.12);
    if (mat < 12.5) return float3(0.90, 0.45, 0.10);
    if (mat < 13.5) return float3(0.50, 0.55, 0.28);
    if (mat < 14.5) return float3(0.55, 0.55, 0.57);
    if (mat < 15.5) return float3(0.12, 0.12, 0.14);
    if (mat < 16.5) return float3(0.95, 0.95, 0.92);
    return float3(0.85, 0.66, 0.24);                // gold
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 w = lerp(W_MIN, W_MAX, float2(uv.x, 1.0 - uv.y));   // y-up
    float pxw = (W_MAX.x - W_MIN.x) / _Resolution.x;           // world units per pixel

    // designer-canvas background + ground line
    float3 col = lerp(float3(0.10, 0.11, 0.14), float3(0.16, 0.15, 0.13), uv.y);
    col = lerp(col, float3(0.30, 0.26, 0.20), smoothstep(pxw * 1.5, 0.0, abs(w.y)));

    float bestZ = -1e9;
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        DadaPart d = Parts[i];
        if (d.active < 0.5) continue;
        float rad = max(d.sc_xy.x, d.sc_xy.y) * ((int)d.kind == 3 || (int)d.kind == 4 || (int)d.kind == 5 || (int)d.kind == 6 ? 1.0 : 0.9);
        float dist = length(w - d.pos_xy);
        float edge = smoothstep(rad + pxw, rad - pxw, dist);   // filled disc, AA edge
        if (edge > 0.01 && d.pos_z > bestZ)                    // nearest-z wins
        {
            bestZ = d.pos_z;
            float3 c = previewCol(d.mat, (int)d.kind);
            float shade = 0.72 + 0.28 * saturate(d.pos_z * 0.5 + 0.5);   // depth cue
            float ring = smoothstep(rad - pxw * 2.0, rad, dist);         // subtle outline
            c = lerp(c * shade, c * 0.5, ring);
            col = lerp(col, c, edge);
        }
    }
    OutputUAV[px] = float4(col, 1.0);
}
