// abstract_accents: ultramarine bars, black square, thin orbit lines, and glass capsules.

RWTexture2D<float4> OutputUAV : register(u0);

float rectMask(float2 uv, float2 mn, float2 mx, float feather)
{
    float2 a = smoothstep(mn, mn + feather, uv);
    float2 b = 1.0 - smoothstep(mx - feather, mx, uv);
    return a.x * a.y * b.x * b.y;
}

float segDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float capsuleMask(float2 uv, float2 a, float2 b, float r)
{
    return 1.0 - smoothstep(r, r + 0.004, segDist(uv, a, b));
}

float ellipseStroke(float2 p, float2 c, float2 radii, float rot, float w)
{
    float s = sin(rot);
    float co = cos(rot);
    float2 q = p - c;
    q = float2(co * q.x - s * q.y, s * q.x + co * q.y);
    float2 e = q / radii;
    return 1.0 - smoothstep(0.0, w, abs(length(e) - 1.0));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(asp, 1.0);

    float3 blue = float3(0.02, 0.00, 0.92) * blue_gain;
    float3 col = 0.0;
    float alpha = 0.0;

    float vbar = rectMask(uv, float2(0.198, 0.145), float2(0.252, 0.337), 0.0015);
    col = lerp(col, blue, vbar);
    alpha = max(alpha, vbar);

    float black = rectMask(uv, float2(0.165, 0.244), float2(0.236, 0.313), 0.0015);
    col = lerp(col, float3(0.012, 0.011, 0.012), black);
    alpha = max(alpha, black);

    float hbar = rectMask(uv, float2(0.600, 0.650), float2(0.878, 0.659), 0.0010);
    col = lerp(col, blue, hbar);
    alpha = max(alpha, hbar);

    float whiteBlock = rectMask(uv, float2(0.175, 0.725), float2(0.353, 0.812), 0.006);
    col = lerp(col, float3(0.92, 0.92, 0.88) * 0.65, whiteBlock * 0.38);
    alpha = max(alpha, whiteBlock * 0.35);

    float2 ringC = (float2(0.338, 0.708) - 0.5) * float2(asp, 1.0);
    float orbit = ellipseStroke(p, ringC, float2(0.168, 0.045), -1.16, 0.028);
    orbit += ellipseStroke(p, ringC + float2(-0.04, 0.00), float2(0.228, 0.027), -1.32, 0.020) * 0.55;
    col += orbit * float3(0.25, 0.25, 0.24) * 0.55;
    alpha = max(alpha, saturate(orbit * 0.38));

    float glass0 = capsuleMask(uv, float2(0.552, 0.092), float2(0.552, 0.125), 0.007);
    float glass1 = capsuleMask(uv, float2(0.578, 0.133), float2(0.578, 0.164), 0.007);
    float glass2 = capsuleMask(uv, float2(0.143, 0.891), float2(0.176, 0.891), 0.006);
    float glass3 = capsuleMask(uv, float2(0.126, 0.916), float2(0.161, 0.916), 0.006);
    float glass = saturate(glass0 + glass1 + glass2 + glass3);
    float rim = saturate(glass * 1.2 - rectMask(uv, float2(0.0, 0.0), float2(1.0, 1.0), 0.0) * 0.0);
    col += glass * float3(0.96, 0.98, 0.96) * 0.55;
    col += rim * float3(0.62, 0.70, 0.68) * 0.22;
    alpha = max(alpha, glass * 0.65);

    float fine = 1.0 - smoothstep(0.0, 0.0012, segDist(uv, float2(0.392, 0.635), float2(0.755, 0.475)));
    fine += (1.0 - smoothstep(0.0, 0.0011, segDist(uv, float2(0.745, 0.120), float2(0.745, 0.705)))) * 0.25;
    col += fine * float3(0.78, 0.72, 0.66) * 0.34;
    alpha = max(alpha, saturate(fine * 0.24));

    OutputUAV[pixel] = float4(saturate(col), saturate(alpha));
}
