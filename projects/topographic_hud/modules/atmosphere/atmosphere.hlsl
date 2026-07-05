// atmosphere — teal depth haze + dust particulate + twinkling stars. The dark
// backdrop the whole scene sits on.

RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0) * 2.0;
    float r = length(p);

    // teal depth haze — soft central glow
    float depth = exp(-r * r * depth_gradient);
    float3 col = haze_color * depth * haze_strength;

    float2 drift = float2(_Time * drift_speed, _Time * drift_speed * 0.6);

    // stars (sparse, twinkling)
    float2 sc = (uv + drift * 0.2) * float2(asp, 1.0) * star_density;
    float2 cell = floor(sc);
    float2 f = frac(sc);
    float rnd = hash21(cell);
    if (rnd > 0.984)
    {
        float d = length(f - 0.5);
        float tw = 0.5 + 0.5 * sin(_Time * twinkle + rnd * 40.0);
        float s = smoothstep(0.08, 0.0, d) * tw;
        col += lerp(float3(0.7, 0.85, 1.0), float3(1.0, 0.7, 0.4), step(0.6, hash21(cell + 3.1))) * s;
    }

    // dust (denser, dimmer)
    float2 dc = (uv + drift) * float2(asp, 1.0) * dust_density;
    float dn = hash21(floor(dc));
    float dust = step(0.93, dn) * dust_brightness * (0.4 + 0.6 * hash21(floor(dc) + 7.7));
    col += haze_color * 2.0 * dust;

    OutputUAV[pixel] = float4(col * intensity, 1.0);
}
