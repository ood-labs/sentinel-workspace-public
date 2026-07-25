// AUTOPSIA — specimen field evolution.
// Runs at the `field` buffer extent (scale 0.5), NOT at _Resolution. All bounds
// and UVs derive from the real feedback texture per scaled-pass discipline.
#include "types.hlsli"

StructuredBuffer<float4> Clock : register(t1);
StructuredBuffer<StimulusRecord> Stim : register(t2);
RWTexture2D<float4> FieldOut : register(u0);

float loadDensity(int2 px, int2 limit) {
    return _Tex0.Load(int3(clamp(px, int2(0, 0), limit), 0)).r;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint fw, fh;
    _Tex0.GetDimensions(fw, fh);
    if (tid.x >= fw || tid.y >= fh) return;

    int2 px = int2(tid.xy);
    int2 limit = int2(fw, fh) - 1;
    float2 fieldSize = float2(fw, fh);
    float2 uv = ((float2)px + 0.5) / fieldSize;
    float aspect = fieldSize.x / max(fieldSize.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float phaseA = frac(Clock[0].x + phase);
    float phaseB = frac(Clock[0].y + phase * 0.5);
    float tA = phaseA * 6.2831853;
    float tB = phaseB * 6.2831853;

    // ---- analytic target: discrete specimens on an empty plate --------------
    // A low-frequency OCCUPANCY envelope decides where tissue exists at all.
    // Everything outside it stays true black, so the observing Features node
    // receives discrete masses instead of an all-over terrain.
    float2 q = p * max(mass_scale, 0.05);
    float2 warp = float2(
        au_fbm(q * warp_scale + float2(0.0, sin(tA) * 0.35), 4),
        au_fbm(q * warp_scale + float2(5.21, 1.37 + cos(tB) * 0.31), 4)
    );
    float2 qw = q + (warp - 0.5) * (warp_amount * 2.0);

    float macro = au_fbm(qw * 0.78 + float2(sin(tA * 0.5) * 0.16, cos(tB * 0.63) * 0.16), 3);
    float detail = au_fbm(qw * 1.05 + 11.7, 4);
    float ridged = 1.0 - abs(au_fbm(qw * 2.05 + 3.11, 3) * 2.0 - 1.0);

    // plate framing: the specimen sits in the field of view, edges fall away
    // Bias the envelope itself toward frame centre so the specimen is COMPOSED,
    // not merely faded at the edges.
    float2 fp = (uv - 0.5) * float2(1.28, 1.82);
    float frameFall = 1.0 - smoothstep(0.48, 1.28, length(fp));
    float shaped = macro - (1.0 - frameFall) * saturate(framing) * 0.38;
    float occ = smoothstep(occupancy, occupancy + 0.155, shaped);

    // Baseline deliberately low: if the tissue floor sits near 1.0 the cells
    // clip into a flat plateau and merge back into one connected component.
    // Keeping the floor down lets each nucleus stand as a separate peak.
    float interior = (detail - 0.5) * max(contrast, 0.1) + 0.30;
    interior += (ridged - 0.5) * ridge_gain;

    // cellular nucleation — the specimen's countable structure
    float cells = au_nuclei(qw * max(cell_density, 0.5) + float2(tB * 0.04, -tA * 0.03),
                            cell_sharp);
    interior += cells * cell_amp;

    float target = occ * max(interior, 0.0);

    // ---- operator stimuli ---------------------------------------------------
    float heatIn = 0.0;
    [unroll] for (uint i = 0u; i < 16u; ++i) {
        StimulusRecord s = Stim[i];
        if (!stimulusActive(s)) continue;
        float2 sp = (s.position - 0.5) * float2(aspect, 1.0);
        float2 d = p - sp;
        float r = max(s.radius, 0.012);
        float dist = length(d);
        float core = exp(-dot(d, d) / max(r * r * 1.1, 1e-5));
        float ring = exp(-pow((dist - r * 1.15) / max(r * 0.30, 0.005), 2.0));
        float vortex = saturate(s.mode);
        // mass stimuli swell the field; incision stimuli carve a ring trench
        target += core * s.strength * stim_gain * (1.0 - vortex);
        target -= ring * s.strength * stim_gain * vortex * 0.9;
        target += core * s.strength * stim_gain * vortex * 0.35;
        heatIn += (core + ring * 0.6) * s.strength;
    }
    target = saturate(target);

    // ---- relax + diffuse ----------------------------------------------------
    float4 prev = _Tex0.Load(int3(px, 0));
    float previous = prev.r;
    float dt = min(_DeltaTime, 0.05);

    float lap = loadDensity(px + int2(1, 0), limit)
              + loadDensity(px + int2(-1, 0), limit)
              + loadDensity(px + int2(0, 1), limit)
              + loadDensity(px + int2(0, -1), limit)
              - previous * 4.0;

    float relax = 1.0 - exp(-max(reaction, 0.01) * dt * 60.0);
    float density = lerp(previous, target, relax);
    density = saturate(density + lap * diffusion * dt * 60.0);

    // ---- gradient (from settled neighbourhood, one-frame lag is fine) -------
    float2 grad = float2(
        loadDensity(px + int2(1, 0), limit) - loadDensity(px + int2(-1, 0), limit),
        loadDensity(px + int2(0, 1), limit) - loadDensity(px + int2(0, -1), limit)
    ) * 0.5;

    float heat = prev.a * pow(0.90, dt * 60.0) + heatIn * dt * 3.0;

    FieldOut[tid.xy] = float4(density, grad.x, grad.y, saturate(heat));
}
