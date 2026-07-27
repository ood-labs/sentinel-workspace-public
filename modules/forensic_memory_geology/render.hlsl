RWTexture2D<float4> OutputUAV : register(u0);

float stroke(float d, float width)
{
    float px = 1.3 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + px, d);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float4 memory = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 program = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float pressure = _Tex2.SampleLevel(LinearSampler, uv, 0).r;
    float4 ctrl = _Tex3.Load(int3(0, 0, 0));

    float energy = memory.r;
    float age = memory.g;
    float scar = memory.b;
    float strataPhase = energy * strata_density + age * age_drift;
    float strata = smoothstep(0.72, 0.96, 0.5 + 0.5 * sin(strataPhase * 6.2831853));
    float excavation = smoothstep(0.08, 0.32, energy) * (1.0 - smoothstep(2.6, 5.0, energy));
    float liveLuma = dot(program, float3(0.2126, 0.7152, 0.0722));

    float3 black = float3(0.003, 0.0035, 0.0035);
    float3 paper = float3(0.78, 0.81, 0.79);
    float3 graphite = float3(0.14, 0.15, 0.145);
    float3 current = current_color;
    float3 col = black;

    col += graphite * excavation * memory_gain;
    col += paper * strata * excavation * strata_gain;
    col += paper * smoothstep(0.24, 0.68, liveLuma) * live_gain;
    col += current * scar * scar_display_gain;
    col *= 0.55 + 0.65 * (1.0 - pressure * pressure_erosion);

    // Microscopic contour register.
    float contour = stroke(abs(frac(energy * 0.5) - 0.5), 0.015);
    col += graphite * contour * excavation * 0.45;
    float2 grid = abs(frac(uv * float2(32.0, 18.0) + 0.5) - 0.5);
    float registration = 1.0 - smoothstep(0.012, 0.026, min(grid.x, grid.y));
    col += graphite * registration * 0.08;

    if (ViewportButtonDown(0))
    {
        float2 d = (uv - _ViewportPointerPosition) * float2(aspect, 1.0);
        float ring = stroke(abs(length(d) - ctrl.r * 0.42), 0.002);
        col += (ctrl.b > 0.5 ? paper : current) * ring;
    }

    float frame = stroke(abs(max(abs(p.x) - aspect * 0.477, abs(p.y) - 0.447)), 0.0015);
    col += paper * frame * 0.52;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
