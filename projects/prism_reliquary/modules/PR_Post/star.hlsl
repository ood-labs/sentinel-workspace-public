// PR_Post / star.hlsl — the cross sparkle.
//
// The reference has one unmistakable anamorphic cross flare sitting on the membrane, plus
// shorter spikes on the brightest chips. That is a lens artefact, so it belongs here rather
// than in the renderer: it is drawn from the bright pass, along fixed arms, with geometric
// decay — the same way a real aperture produces it.

#include "../_shared/prmath.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv  = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 asp = float2(1.0 / _Resolution.x, 1.0 / _Resolution.y);

    int   arms = (star_arms < 0.5) ? 4 : 6;
    float step = star_length / 16.0;

    float3 s = 0.0;
    [loop] for (int a = 0; a < arms; a++)
    {
        // 4 arms give the reference's upright cross; 6 give a starburst.
        float ang = (arms == 4) ? ((PR_PI * 0.5) * (float)a + radians(star_rotate))
                                : (PR_TAU / 6.0 * (float)a + radians(star_rotate));
        float2 dir = float2(cos(ang), sin(ang)) * step;

        float w = 1.0;
        [loop] for (int i = 1; i <= 16; i++)
        {
            w *= star_decay;
            float2 o = dir * (float)i * asp * _Resolution.y;
            // slight per-arm chromatic separation, as a real flare has
            float3 t;
            t.r = _Tex0.SampleLevel(LinearSampler, uv + o * 1.03, 0).r;
            t.g = _Tex0.SampleLevel(LinearSampler, uv + o, 0).g;
            t.b = _Tex0.SampleLevel(LinearSampler, uv + o * 0.97, 0).b;
            s += t * w;
        }
    }

    OutputUAV[pixel] = float4(s / (float)arms, 1.0);
}
