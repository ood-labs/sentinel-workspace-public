// Projection: exactly the strokes the laser draws, in the projector's 16:9 frame. Scan space and
// pixels share one mapping (p = uv*2-1, scanner +y up), the same one Alignment Grid uses, so the
// projected picture and the mapped laser land on each other.
struct Scan { float4 endpoints, color0, color1, timing, meta; };
StructuredBuffer<Scan> A : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float segDist(float2 p, float2 a, float2 b)
{
    float2 d = b - a;
    float t = saturate(dot(p - a, d) / max(dot(d, d), 1e-12));
    return length(p - (a + d * t));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (any(id.xy >= (uint2)_Resolution)) return;
    float2 half_res = _Resolution * 0.5;
    float2 p = ((id.xy + 0.5) / _Resolution * 2 - 1) * float2(1, -1);   // scan space
    float2 q = p * half_res;                                             // same point in pixels

    uint n = min((uint)A[0].endpoints.x, 1023u);
    float3 col = 0;
    [loop] for (uint i = 1; i <= n; i++)
    {
        Scan r = A[i];
        if (r.timing.w < 0.5)   // lit strokes only; blank travel is not part of the picture
        {
            float d = segDist(q, r.endpoints.xy * half_res, r.endpoints.zw * half_res);
            col = max(col, r.color0.rgb * saturate(line_width * 0.5 + 0.5 - d));
        }
    }
    OutputUAV[id.xy] = float4(col, 1);
}
