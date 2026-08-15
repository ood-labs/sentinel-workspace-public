// FM_Render / depth_out.hlsl — publish LINEAR eye depth, in millimetres.
//
// A straight extract of the alpha the scene pass already wrote. See the long note in
// scene.hlsl for why the depth does not come from the hardware depth buffer: `source: "depth"`
// declares no dependency on the draw that fills it, so the reader is free to run first and
// sample a buffer still cleared to 1.0 — which it did, reporting the far plane for every pixel
// and making FM_Post blur the whole frame at every aperture.
//
// Reading `pass:scene` is a real dependency, so this pass cannot be scheduled before the
// geometry that produced the value.
RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the scene pass target: rgb is the beauty, alpha is eye depth in millimetres.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float eye = _Tex0.SampleLevel(PointSampler, uv, 0).a;

    // Anything the geometry never covered reports the far distance, so a scope mark or a
    // defocus tap behind nothing is treated by the same test as one behind an ant.
    if (!(eye > 0.0)) eye = _CameraFar;

    OutputUAV[pixel] = float4(eye, eye, eye, 1.0);
}
