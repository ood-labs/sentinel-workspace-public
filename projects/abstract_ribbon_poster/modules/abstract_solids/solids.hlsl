// abstract_solids: shaded spheres, striped oval insert, and chrome ring.

RWTexture2D<float4> OutputUAV : register(u0);

static const float PI_LOCAL = 3.14159265;

float2 aspectPoint(float2 uv)
{
    return (uv - 0.5) * float2(_Resolution.x / _Resolution.y, 1.0);
}

float circleMask(float2 p, float2 c, float r, float feather)
{
    return 1.0 - smoothstep(r - feather, r + feather, length(p - c));
}

float ellipseMask(float2 p, float2 c, float2 radii, float feather)
{
    float2 q = (p - c) / radii;
    return 1.0 - smoothstep(1.0 - feather, 1.0 + feather, length(q));
}

float3 shadeSphere(float2 p, float2 c, float r, float3 base, float light)
{
    float2 q = (p - c) / r;
    float z = sqrt(saturate(1.0 - dot(q, q)));
    float3 n = normalize(float3(q.x, -q.y, z));
    float3 l = normalize(float3(-0.45, -0.55, 0.72));
    float diff = saturate(dot(n, l)) * 0.55 + 0.45;
    float rim = pow(saturate(1.0 - z), 2.2);
    float spec = pow(saturate(dot(reflect(-l, n), float3(0.0, 0.0, 1.0))), 28.0);
    return base * diff + float3(1.0, 0.96, 0.88) * spec * light + rim * 0.08;
}

float ringStroke(float2 p, float2 c, float r, float w)
{
    return 1.0 - smoothstep(0.0, w, abs(length(p - c) - r));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = aspectPoint(uv);
    float phaseT = _Time * motion;

    float3 col = 0.0;
    float alpha = 0.0;

    float2 ringC = (float2(0.338, 0.710) - 0.5) * float2(asp, 1.0);
    float r1 = ringStroke(p, ringC, 0.124, 0.005);
    float r2 = ringStroke(p, ringC, 0.102, 0.0025);
    float arcGate = smoothstep(-1.8, -0.6, atan2(p.y - ringC.y, p.x - ringC.x)) * (1.0 - smoothstep(1.55, 2.4, atan2(p.y - ringC.y, p.x - ringC.x)));
    float chrome = (r1 * (0.65 + 0.35 * sin(atan2(p.y - ringC.y, p.x - ringC.x) * 4.0 + phaseT)) + r2 * 0.65) * arcGate;
    col += chrome * float3(0.90, 0.89, 0.84);
    col += r1 * 0.30 * float3(0.05, 0.05, 0.06);
    alpha = max(alpha, saturate(chrome + r1 * 0.5));

    float2 ovalC = (float2(0.445, 0.452) - 0.5) * float2(asp, 1.0);
    float2 ovalR = float2(0.122, 0.048);
    float oval = ellipseMask(p, ovalC, ovalR, 0.018);
    float2 oq = (p - ovalC) / ovalR;
    float stripeCoord = oq.x * 8.0 + oq.y * 1.8;
    float stripe = step(frac(stripeCoord + 0.15 * sin(phaseT)), 0.46);
    float3 ovalCol = lerp(float3(0.10, 0.10, 0.105), float3(0.94, 0.92, 0.88), stripe);
    ovalCol *= 0.84 + 0.16 * smoothstep(-0.9, 0.9, -oq.y);
    col = lerp(col, ovalCol, oval);
    alpha = max(alpha, oval);

    float2 blackC = (float2(0.330, 0.735) - 0.5) * float2(asp, 1.0);
    float blackM = circleMask(p, blackC, 0.049, 0.004);
    float3 blackCol = shadeSphere(p, blackC, 0.049, float3(0.05, 0.045, 0.047), 0.6);
    col = lerp(col, blackCol, blackM);
    alpha = max(alpha, blackM);

    float2 s0 = (float2(0.510, 0.615) - 0.5) * float2(asp, 1.0);
    float2 s1 = (float2(0.575, 0.612) - 0.5) * float2(asp, 1.0);
    float2 s2 = (float2(0.692, 0.898) - 0.5) * float2(asp, 1.0);
    float2 s3 = (float2(0.382, 0.334) - 0.5) * float2(asp, 1.0);

    float m0 = circleMask(p, s0, 0.056, 0.004);
    float m1 = circleMask(p, s1, 0.061, 0.004);
    float m2 = circleMask(p, s2, 0.034, 0.003);
    float m3 = circleMask(p, s3, 0.014, 0.002);
    col = lerp(col, shadeSphere(p, s0, 0.056, float3(0.94, 0.92, 0.87), 0.75), m0);
    col = lerp(col, shadeSphere(p, s1, 0.061, float3(0.96, 0.94, 0.89), 0.8), m1);
    col = lerp(col, shadeSphere(p, s2, 0.034, float3(0.95, 0.93, 0.88), 0.65), m2);
    col = lerp(col, shadeSphere(p, s3, 0.014, float3(0.96, 0.92, 0.88), 0.8), m3);
    alpha = max(alpha, max(max(m0, m1), max(m2, m3)));

    OutputUAV[pixel] = float4(col * solids_gain, saturate(alpha));
}
