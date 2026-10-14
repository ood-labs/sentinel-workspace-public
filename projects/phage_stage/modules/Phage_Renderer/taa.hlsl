// Temporal anti-aliasing, the resolve: this frame's jittered image blended into the history the camera carried here.
// The history is reprojected through the depth (nearest's alpha, the distance from the camera, taken at the nearest
// sample of the 3x3 so an edge follows the foreground) and the previous frame's view-projection (taa_cam), then
// clipped to this frame's 3x3 colour range in YCoCg, so whatever moved or changed (a strobe, a chase, a panning head)
// cannot leave a trail. It blends tonemapped values, so a hot beam core cannot ring. A camera cut (more than 2 m in a
// frame) starts the history again.
StructuredBuffer<float4> Cam : register(t3);   // the previous frame: view-projection rows 0-3, camera position (w: set)
RWTexture2D<float4> OutputUAV : register(u0);

float3 toYCoCg(float3 c) { return float3(dot(c, float3(0.25, 0.5, 0.25)), dot(c, float3(0.5, 0.0, -0.5)), dot(c, float3(-0.25, 0.5, -0.25))); }
float3 fromYCoCg(float3 y) { return float3(y.x + y.y - y.z, y.x + y.z, y.x - y.y - y.z); }
float3 tonemap(float3 c) { return c / (1.0 + max(c.r, max(c.g, c.b))); }
float3 untonemap(float3 c) { return c / max(1.0 - max(c.r, max(c.g, c.b)), 1e-3); }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    int2 p = int2(id.xy);
    float3 raw = _Tex0[p].rgb;
    if (taa < 0.5) { OutputUAV[id.xy] = float4(raw, 1.0); return; }
    float2 res = float2(w, h), uv = (id.xy + 0.5) / res;
    float3 cur = tonemap(max(raw, 0.0));

    // The 3x3: colour mean and spread, and the nearest surface.
    float3 m1 = 0.0, m2 = 0.0;
    float nearest = 1e9;
    [unroll] for (int y = -1; y <= 1; y++)
    [unroll] for (int x = -1; x <= 1; x++)
    {
        int2 q = clamp(p + int2(x, y), int2(0, 0), int2(w, h) - 1);
        float3 c = toYCoCg(tonemap(max(_Tex0[q].rgb, 0.0)));
        m1 += c;
        m2 += c * c;
        float d = _Tex2[q].a;
        if (d > 0.0 && d < nearest) nearest = d;
    }
    m1 /= 9.0;
    float3 sd = sqrt(max(m2 / 9.0 - m1 * m1, 0.0));

    // Where this pixel was last frame.
    float depth = nearest < 1e8 ? nearest : _CameraFar;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 farW = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    float3 world = _CameraPos + normalize(farW.xyz / farW.w - _CameraPos) * depth;
    float4x4 prevVP = float4x4(Cam[0], Cam[1], Cam[2], Cam[3]);
    float4 q = mul(prevVP, float4(world, 1.0));
    float2 puv = float2(q.x, -q.y) / max(q.w, 1e-5) * 0.5 + 0.5;
    float4 hist = _Tex1.SampleLevel(LinearSampler, puv, 0);
    bool valid = Cam[4].w > 0.5 && hist.a > 0.5 && q.w > 0.0 && all(puv > 0.0) && all(puv < 1.0)
        && length(Cam[4].xyz - _CameraPos) < 2.0;

    // The history clipped into this frame's colour range, toward its mean.
    float3 hy = toYCoCg(tonemap(max(hist.rgb, 0.0)));
    float3 e = max(1.25 * sd, 1e-4), v = hy - m1, a = abs(v / e);
    float k = max(a.x, max(a.y, a.z));
    if (k > 1.0) hy = m1 + v / k;

    // More of this frame while the image moves under the pixel; all of it without history.
    float moved = length((puv - uv) * res);
    float alpha = valid ? lerp(1.0 - taa_feedback, 0.35, saturate(moved / 8.0)) : 1.0;
    OutputUAV[id.xy] = float4(untonemap(lerp(fromYCoCg(hy), cur, alpha)), 1.0);
}
