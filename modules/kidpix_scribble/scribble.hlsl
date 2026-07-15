// kidpix_scribble — thin pink & black spiky star-burst line clusters (lower-right). Each cluster is
// a set of thin straight spikes radiating from a center; clusters slowly rotate and the spike tips
// jitter a few px every frame. Razor-thin hard lines, premultiplied RGBA. Self-animating on _Time.
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;
float h11(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float2 h22(float p){ return float2(h11(p * 1.7), h11(p * 3.1 + 5.0)); }
float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
void over(inout float3 rgb, inout float cov, float3 c, float a)
{ rgb = c * a + rgb * (1.0 - a); cov = a + cov * (1.0 - a); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;
    float2 p = uv * float2(aspect, 1.0);

    int NCl = clamp((int)cluster_count, 1, 10);
    int NSp = clamp((int)spikes, 3, 18);
    float aa = 1.1 / res.y;
    float w = line_width;

    float3 rgb = 0.0; float cov = 0.0;

    // jitter index stepped WITHIN the loop so it repeats seamlessly each cycle
    float lp = frac(_Time / loop_seconds);
    float jstep = floor(lp * jit_steps);

    [loop] for (int c = 0; c < 10; c++)
    {
        if (c >= NCl) break;
        float fc = (float)c;
        // cluster center in lower-right region
        float2 ctr = float2(cluster_cx, cluster_cy) * float2(aspect, 1.0)
                   + (h22(fc * 5.1) - 0.5) * float2(0.35 * aspect, 0.30) * spread;
        float rad = (0.05 + h11(fc * 2.3) * 0.06) * cluster_size;
        // loop-synced rotation: an integer number of turns per loop -> seamless seam
        float dir = (h11(fc * 7.7) > 0.5 ? 1.0 : -1.0);
        float rot = lp * TAU * spin_turns * dir + h11(fc) * TAU;
        bool pink = h11(fc * 3.9) > 0.45;
        float3 col = pink ? float3(0.93, 0.20, 0.72) : float3(0.05, 0.05, 0.06);

        [loop] for (int s = 0; s < 18; s++)
        {
            if (s >= NSp) break;
            float ang = ((float)s / (float)NSp) * TAU + rot;
            float len = rad * (0.6 + 0.8 * h11(fc * 9.1 + (float)s));
            // stepped tip jitter
            float2 jit = (h22(jstep * 0.017 + fc * 13.0 + (float)s * 2.7) - 0.5) * 0.010;
            float2 tip = ctr + float2(cos(ang), sin(ang)) * len + jit;
            float d = sdSeg(p, ctr, tip);
            float strk = smoothstep(w + aa, w, d);
            over(rgb, cov, col, strk);
        }
    }

    OutputUAV[px] = float4(rgb, cov) * intensity;
}
