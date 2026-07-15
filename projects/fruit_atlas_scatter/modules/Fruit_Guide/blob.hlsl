float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float aspect = 896.0 / 512.0;
    float2 p = (uv - float2(center_x, center_y)) * float2(1.0, aspect);
    p.y /= max(0.25, squash);
    float d = length(p);
    float m = 1.0 - smoothstep(radius - softness, radius + softness, d);

    float2 n = p / max(radius, 1e-4);
    float nz = sqrt(saturate(1.0 - dot(n, n)));
    float3 normal = normalize(float3(n.x, -n.y, nz));
    float3 lightDir = normalize(float3(-0.35, 0.55, 0.75));
    float diff = saturate(dot(normal, lightDir));

    float3 base = float3(color_r, color_g, color_b);
    float3 col = base * (0.2 + 0.8 * diff);
    float spec = pow(saturate(dot(normal, normalize(lightDir + float3(0.0, 0.0, 1.0)))), 24.0);
    col += spec * 0.45;

    return float4(col * m, 1.0);
}
