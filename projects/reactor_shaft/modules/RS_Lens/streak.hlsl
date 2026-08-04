// RS_Lens / streak.hlsl — the flare off the bright emitters.
//
// EXPLORATION AXIS. The reference's corner lamps throw long bright arms, and which arms a lens
// throws is a real creative choice rather than a grade tweak: it changes what the frame is shot
// ON. Anamorphic is the reference's read; the others are kept because each suits a different
// show and repairing a loser is cheaper than rediscovering it.
Texture2D<float4> Bright : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float3 arm(uint2 px, uint2 dim, float2 dir, float len, float decay, int taps)
{
    float3 acc = float3(0.0, 0.0, 0.0);
    float w = 1.0;
    float wsum = 0.0;
    [loop] for (int i = 1; i <= taps; i++)
    {
        w *= decay;
        float2 o = dir * len * (float)dim.y * (float)i / (float)taps;
        int2 a = clamp((int2)px + (int2)round(o), int2(0, 0), (int2)dim - 1);
        int2 b = clamp((int2)px - (int2)round(o), int2(0, 0), (int2)dim - 1);
        acc += (max(Bright[(uint2)a].rgb - flare_threshold, 0.0)
              + max(Bright[(uint2)b].rgb - flare_threshold, 0.0)) * w;
        wsum += 2.0 * w;
    }
    return acc / max(wsum, 1e-5);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (px.x >= W || px.y >= H) return;
    uint2 dim = uint2(W, H);

    int style = (int)flare_style;
    float len = max(flare_length, 0.0);
    float dec = clamp(flare_decay, 0.5, 0.99);
    int taps = clamp((int)flare_taps, 2, 32);

    float3 acc = float3(0.0, 0.0, 0.0);
    float ang = flare_angle * 0.0174533;
    float2 ax = float2(cos(ang), sin(ang));
    float2 ay = float2(-ax.y, ax.x);

    if (style == 0)
    {
        // ANAMORPHIC — one long horizontal arm, tinted cold. This is the reference's lamp.
        acc = arm(px, dim, ax, len, dec, taps) * float3(0.72, 0.88, 1.15);
    }
    else if (style == 1)
    {
        // STAR — four arms
        acc  = arm(px, dim, ax, len * 0.72, dec, taps);
        acc += arm(px, dim, ay, len * 0.72, dec, taps);
        float2 d1 = normalize(ax + ay), d2 = normalize(ax - ay);
        acc += arm(px, dim, d1, len * 0.48, dec, taps) * 0.6;
        acc += arm(px, dim, d2, len * 0.48, dec, taps) * 0.6;
        acc *= 0.45;
    }
    else if (style == 2)
    {
        // HALO — a soft ring rather than arms; reads as a dirty filter
        float2 uv = ((float2)px + 0.5) / float2(W, H);
        float2 c = uv - 0.5;
        float3 h = float3(0.0, 0.0, 0.0);
        [loop] for (int i = 0; i < 8; i++)
        {
            float a2 = (float)i * 0.7853982;
            float2 o = float2(cos(a2), sin(a2)) * len * (float)H * 0.75;
            int2 s = clamp((int2)px + (int2)round(o), int2(0, 0), (int2)dim - 1);
            h += max(Bright[(uint2)s].rgb - flare_threshold, 0.0);
        }
        acc = h * 0.125;
    }
    // style 3 = Off: bloom alone

    OutputUAV[px] = float4(acc, 1.0);
}
