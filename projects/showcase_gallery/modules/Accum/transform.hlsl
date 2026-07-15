// accum transform — per-frame steer of the accumulated canvas (StreamDiff-style feedback move).
// Reads the persistent canvas, resamples it through scale + pan, writes to a scratch buffer that
// the paint pass then composites new stamps onto. acc_scale>1 zooms in, pan drifts left/right/up/down.
// Identity (scale 1, pan 0) = pure accumulation. Ping-pong (canvas -> canvas_prev) avoids RW races.

StructuredBuffer<float4>   Canvas     : register(t0);   // input: buffer:canvas (last frame)
RWStructuredBuffer<float4> CanvasPrev : register(u0);   // output: buffer:canvas_prev

float4 fetchC(int2 ij)
{
    int W = (int)_Resolution.x, H = (int)_Resolution.y;
    ij = clamp(ij, int2(0, 0), int2(W - 1, H - 1));
    return Canvas[ij.y * W + ij.x];
}

float4 sampleC(float2 uv)
{
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0, 0, 0, 0);
    float2 p = uv * _Resolution.xy - 0.5;
    float2 f = frac(p);
    int2 i = (int2)floor(p);
    float4 a = lerp(fetchC(i + int2(0, 0)), fetchC(i + int2(1, 0)), f.x);
    float4 b = lerp(fetchC(i + int2(0, 1)), fetchC(i + int2(1, 1)), f.x);
    return lerp(a, b, f.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;
    uint idx = px.y * W + px.x;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    // pan pad is 0..1 with neutral at 0.5,0.5 -> remap to a signed per-frame velocity.
    float2 pv = (pan - 0.5) * 2.0 * move_speed;   // -move_speed .. +move_speed
    float sc = 1.0 + zoom * move_speed;           // gentle per-frame zoom around 1
    float2 srcUV = (uv - 0.5) / max(0.01, sc) + 0.5 - pv;
    CanvasPrev[idx] = sampleC(srcUV);
}
