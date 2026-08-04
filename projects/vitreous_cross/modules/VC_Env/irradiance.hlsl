// VC_Env / irradiance.hlsl — the studio, cosine-convolved.
//
// The opaque surfaces in this show (the plates inside the glass, and the cyclorama the contact
// shadow lands on) need the DIFFUSE response of the studio, not its sharp image. Gathering
// that at shading time from a handful of taps does not work here: this panorama is almost
// entirely black with two small very bright sources, which is precisely the distribution a
// sparse gather aliases into visible banding.
//
// So it is convolved once, here, at 64x32 — a resolution chosen because a cosine lobe cannot
// carry higher frequency than that anyway. Every diffuse lookup downstream is then a single
// bilinear tap of an already-correct answer.
#include "../_shared/vitreous.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

#define SRC_X 64
#define SRC_Y 32

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    // SCALED PASS: this target is a fraction of the module's root resolution, so its extent
    // comes from the texture itself and never from _Resolution.
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float3 n = vc_envDir(((float2)pix + 0.5) / float2(W, H));

    float3 sum = float3(0, 0, 0);
    float wsum = 0.0;

    [loop]
    for (int y = 0; y < SRC_Y; y++)
    {
        float v = ((float)y + 0.5) / (float)SRC_Y;
        // solid-angle weight of a lat-long row
        float sw = sin(v * 3.14159265);
        for (int x = 0; x < SRC_X; x++)
        {
            float2 suv = float2(((float)x + 0.5) / (float)SRC_X, v);
            float3 d = vc_envDir(suv);
            float c = max(dot(n, d), 0.0);
            if (c > 0.0)
            {
                float w = c * sw;
                sum += _Tex0.SampleLevel(LinearSampler, suv, 0).rgb * w;
                wsum += w;
            }
        }
    }

    OutputUAV[pix] = float4(sum / max(wsum, 1e-5), 1.0);
}
