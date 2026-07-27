RWTexture2D<float4> OutputUAV : register(u0);

float lineMask(float value, float width)
{
    float d = min(frac(value), 1.0 - frac(value));
    return 1.0 - smoothstep(width, width * 2.0, d);
}

float segmentDistance(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= (uint)_Resolution.x || DTid.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)DTid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float phase = master_phase * 6.2831853;
    float seamX = 0.12 * sin(p.y * 5.0 - phase * 0.35) + fault_offset;
    float side = step(seamX, p.x);
    float faultShift = side * (0.72 + master_envelope * 0.65);

    float fold = sin((p.x + side * 0.11) * 4.6 + phase * 0.22);
    fold += 0.42 * sin(p.x * 11.0 - p.y * 3.2 - phase * 0.15);
    float strataField = p.y * (float)layer_count + fold * section_warp + faultShift;

    float contour = lineMask(strataField, 0.035 + contour_width * 0.045);
    float majorContour = lineMask(strataField * 0.2, 0.017);

    float seam = 1.0 - smoothstep(0.002, 0.012, abs(p.x - seamX));
    float registration = 0.0;
    [unroll] for (int i = 0; i < 7; ++i)
    {
        float y = -0.42 + (float)i * 0.14;
        float2 a = float2(seamX - 0.055, y);
        float2 b = float2(seamX + 0.055, y);
        registration = max(registration, 1.0 - smoothstep(0.0015, 0.0045, segmentDistance(p, a, b)));
    }

    float plate = smoothstep(0.94, 0.82, abs(p.x) / max(aspect * 0.5, 0.001));
    plate *= smoothstep(0.49, 0.43, abs(p.y));

    float3 black = float3(0.004, 0.004, 0.005);
    float3 gray = float3(0.16, 0.165, 0.17);
    float3 white = float3(0.91, 0.92, 0.92);
    float3 warm = float3(0.96, 0.43, 0.11);

    float bandFill = 0.025 + 0.035 * step(0.5, frac(strataField * 0.5));
    float3 color = black + gray * bandFill;
    color = lerp(color, white, saturate(contour * 0.82 + majorContour));
    float accent = saturate((seam * (0.45 + master_envelope * 0.55) + registration * master_pulse) * accent_gain);
    color = lerp(color, warm, accent);

    float frame = 1.0 - smoothstep(0.0015, 0.004, abs(max(abs(p.x) - aspect * 0.47, abs(p.y) - 0.45)));
    color = lerp(color, white, frame * 0.55);
    color *= plate;

    float playLamp = smoothstep(0.024, 0.020, length(p - float2(-aspect * 0.44, -0.415)));
    color = lerp(color, master_play > 0.5 ? warm : gray, playLamp);

    OutputUAV[DTid.xy] = float4(saturate(color), 1.0);
}
