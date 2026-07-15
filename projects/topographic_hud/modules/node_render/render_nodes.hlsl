// node_render — glowing data-point nodes with bloom-bright cores + optional star
// rays, drawn from the Nodes data port (data:0 -> _Data0 / _Data0_Count).

struct NodeRecord
{
    float2 pos; float radius; float intensity;
    float color_mix; float kind; float seed; float active;
};

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    float3 col = float3(0.0, 0.0, 0.0);
    float aAcc = 0.0;

    uint cnt = min((uint)_Data0_Count, 128u);
    [loop]
    for (uint i = 0u; i < 128u; i++)
    {
        if (i >= cnt) break;
        NodeRecord n = _Data0[i];
        if (n.active < 0.5) continue;

        float pulse = 1.0 + pulse_amount * sin(_Time * pulse_speed + n.seed * 1.7);
        float2 d = (uv - n.pos) * float2(asp, 1.0);
        float dist = length(d);
        float rr = max(n.radius, 1e-4);

        float core = exp(-dist * dist / max(core_size * core_size * rr * rr, 1e-7));
        float glow = exp(-dist / max(glow_radius * rr, 1e-4));

        float rays = 0.0;
        if (star_rays != 0)
        {
            float ang = atan2(d.y, d.x);
            float spikes = pow(abs(cos(ang * (float)ray_count * 0.5)), 30.0);
            rays = spikes * exp(-dist / max(ray_length * rr, 1e-4));
        }

        float3 tint = lerp(white_color, orange_color, n.color_mix);
        float b = (core + glow * glow_falloff + rays * 0.7) * n.intensity * pulse;
        col += tint * b;
        aAcc = max(aAcc, saturate(b));
    }

    OutputUAV[pixel] = float4(col * intensity, saturate(aAcc));
}
