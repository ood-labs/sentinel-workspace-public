// BR_Lens / glow.hlsl -- one level of the bloom, made STRAIGHT from BR_Render's image.
//
// This build hands a pass another pass's buffer a cook late, per hop. The old pyramid -- a bright
// pass, three steps down, three up -- put the glow seven cooks behind the picture, and every
// lamp's halo trailed it across the screen whenever the camera moved. Here every level is ONE hop
// from the source, so the grade sees it a single cook late, and reprojects that one cook away.
//
// A level texel is a tent over the source as wide as two of its own texels, so neighbours overlap
// and a highlight crossing a texel boundary fades across instead of popping. The tent is summed
// from bilinear taps placed on source-pixel corners (each tap a 2x2 average), soft-thresholded
// per tap. Four passes run this shader at 1/2, 1/4, 1/8 and 1/16 of the source, about 0.9 M taps
// each.
//
// The half-resolution level also carries the camera of the image it was made from (texels
// (0..19, 0), br_camtexels.hlsli); the grade reprojects every level through it.
#include "../_shared/br_camtexels.hlsli"
RWTexture2D<float4> OutputUAV : register(u0);

// the soft-knee bright pass (in exposed units): only genuinely bright light -- lamps, flames, sun
// patches -- feeds the glow
float3 softKnee(float3 c)
{
    float l = max(c.r, max(c.g, c.b));
    float knee = bloom_threshold * 0.5;
    float soft = clamp(l - bloom_threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contrib = max(soft, l - bloom_threshold) / max(l, 1e-4);
    return min(c * contrib, 200.0);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    uint SW, SH, lv;
    _Tex0.GetDimensions(0, SW, SH, lv);
    int r = max((int)round((float)SW / (float)W), 1);          // source pixels per level texel
    // the half-resolution level carries the camera: a verbatim copy of the source's header
    if (r <= 2 && isCamTexel(int2(tid.xy))) { OutputUAV[tid.xy] = _Tex0.Load(int3(tid.xy, 0)); return; }
    float2 src = float2(SW, SH);
    float2 c = (float2(tid.xy) + 0.5) * float2(r, r);            // this texel's centre, source pixels
    float gain = exp2(exposure);
    float3 acc = 0;
    float wsum = 0.0;
    // r quads per axis on source-pixel corners, covering [c - r, c + r]
    [loop] for (int j = 0; j < r; j++)
    {
        float py = c.y - (float)r + 1.0 + 2.0 * (float)j;
        float wy = 1.0 - abs(py - c.y) / (float)r;
        [loop] for (int i = 0; i < r; i++)
        {
            float px = c.x - (float)r + 1.0 + 2.0 * (float)i;
            float wx = 1.0 - abs(px - c.x) / (float)r;
            // never read the source's own camera texels as light
            float2 p = float2(px, (px < (float)CAM_TEXELS + 3.0) ? max(py, 2.0) : py);
            float3 s = _Tex0.SampleLevel(LinearSampler, p / src, 0).rgb;
            float w = wx * wy;
            acc += softKnee(s * gain) * w;
            wsum += w;
        }
    }
    OutputUAV[tid.xy] = float4(acc / max(wsum, 1e-6), 1.0);
}
