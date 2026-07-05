// LFO Display — oscilloscope-style waveform panel

RWTexture2D<float4> OutputUAV : register(u0);

struct LFOData { float lfo1, lfo2, lfo3, lfo4; };
StructuredBuffer<LFOData> _LFOValues : register(t0);

#define PI      3.14159265
#define LANES   4
#define MARGIN  8.0
#define GAP     6.0

// ── Per-lane accessors (avoids HLSL local array init issues) ────────────────
float getSpeed(int i) {
    if (i == 0) return lfo1_speed;
    if (i == 1) return lfo2_speed;
    if (i == 2) return lfo3_speed;
    return lfo4_speed;
}
float getAmp(int i) {
    if (i == 0) return lfo1_amp;
    if (i == 1) return lfo2_amp;
    if (i == 2) return lfo3_amp;
    return lfo4_amp;
}
float getShape(int i) {
    if (i == 0) return lfo1_shape;
    if (i == 1) return lfo2_shape;
    if (i == 2) return lfo3_shape;
    return lfo4_shape;
}
float getVal(LFOData d, int i) {
    if (i == 0) return d.lfo1;
    if (i == 1) return d.lfo2;
    if (i == 2) return d.lfo3;
    return d.lfo4;
}

// ── Waveform evaluation ─────────────────────────────────────────────────────
float evalWave(float phase, float shapeF)
{
    float p = frac(phase);
    if (shapeF < 0.5) return sin(phase * 2.0 * PI) * 0.5 + 0.5;
    if (shapeF < 1.5) return 1.0 - abs(p * 2.0 - 1.0);
    if (shapeF < 2.5) return p;
    return step(0.5, p);
}

// ── HSV to RGB ──────────────────────────────────────────────────────────────
float3 hsv2rgb(float3 c) {
    float3 p = abs(frac(c.xxx + float3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * lerp(float3(1,1,1), saturate(p - 1.0), c.y);
}

// ── Rounded rect SDF ────────────────────────────────────────────────────────
float roundRect(float2 p, float2 center, float2 halfSize, float radius) {
    float2 d = abs(p - center) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 px = (float2)pixel + 0.5;
    float  W  = _Resolution.x;
    float  H  = _Resolution.y;
    float  t  = _Time;

    LFOData vals = _LFOValues[0];

    // Lane colors: cyan, magenta, green, orange
    float3 laneCol0 = hsv2rgb(float3(0.52, 0.85, 1.0));
    float3 laneCol1 = hsv2rgb(float3(0.83, 0.85, 1.0));
    float3 laneCol2 = hsv2rgb(float3(0.35, 0.85, 1.0));
    float3 laneCol3 = hsv2rgb(float3(0.08, 0.85, 1.0));

    float3 col = float3(0.06, 0.06, 0.08);

    float laneH  = (H - MARGIN * 2.0 - GAP * (LANES - 1)) / LANES;
    float waveX0 = MARGIN + 40.0;
    float waveX1 = W - MARGIN;
    float waveW  = waveX1 - waveX0;

    for (int i = 0; i < LANES; i++)
    {
        float laneY0 = MARGIN + float(i) * (laneH + GAP);
        float laneY1 = laneY0 + laneH;
        if (px.y < laneY0 - 2.0 || px.y > laneY1 + 2.0) continue;

        float3 lc = (i == 0) ? laneCol0 : (i == 1) ? laneCol1 : (i == 2) ? laneCol2 : laneCol3;
        float spd   = getSpeed(i);
        float amp   = getAmp(i);
        float shape = getShape(i);
        float val   = getVal(vals, i);

        // Lane background
        float laneSDF = roundRect(px, float2((waveX0+waveX1)*0.5, (laneY0+laneY1)*0.5),
                                  float2(waveW*0.5, laneH*0.5), 4.0);
        if (laneSDF < 0.0)
        {
            col = float3(0.04, 0.04, 0.055);
            float gridX = frac((px.x - waveX0) / waveW * 8.0);
            float gridY = frac((px.y - laneY0) / laneH * 4.0);
            float gridLine = min(smoothstep(0.02, 0.0, abs(gridX - 0.5) - 0.48), 0.15)
                           + min(smoothstep(0.04, 0.0, abs(gridY - 0.5) - 0.46), 0.1);
            col += float3(0.08, 0.08, 0.12) * gridLine;
            float centerY = lerp(laneY1, laneY0, 0.5);
            col += float3(0.06, 0.06, 0.08) * smoothstep(1.0, 0.0, abs(px.y - centerY));
        }

        // Color indicator bar
        float barSDF = roundRect(px, float2(MARGIN + 16.0, (laneY0+laneY1)*0.5),
                                 float2(12.0, laneH*0.4), 3.0);
        if (barSDF < 0.0)
        {
            float fillNorm = saturate(val / max(amp, 0.001));
            float fillY = lerp(laneY1, laneY0, fillNorm * 0.8 + 0.1);
            col = lc * ((px.y > fillY) ? 0.25 : 1.0);
        }

        // Waveform trace
        if (px.x >= waveX0 && px.x <= waveX1 && px.y >= laneY0 && px.y <= laneY1)
        {
            float xNorm = (px.x - waveX0) / waveW;
            float phase = xNorm * 2.0;
            float waveY = evalWave(phase, shape);

            float padY = laneH * 0.08;
            float drawH = laneH - padY * 2.0;
            float targetY = laneY1 - padY - waveY * drawH;

            float dist = abs(px.y - targetY);
            col = lerp(col, lc, smoothstep(2.0, 0.5, dist) * 0.9);
            col += lc * smoothstep(8.0, 1.0, dist) * 0.15;

            // Playhead
            float currentPhase = frac(t * spd);
            float playheadX = waveX0 + (currentPhase / 2.0) * waveW;
            float phDist = abs(px.x - playheadX);
            col += lc * smoothstep(2.0, 0.5, phDist) * 0.4;

            // Current value dot
            float dotY = laneY1 - padY - evalWave(currentPhase, shape) * drawH;
            float dotDist = length(px - float2(playheadX, dotY));
            col = lerp(col, float3(1,1,1), smoothstep(6.0, 2.0, dotDist));
            col += lc * smoothstep(10.0, 4.0, dotDist) * 0.5;
        }

        // Lane separator
        if (i < LANES - 1)
        {
            float sepY = laneY1 + GAP * 0.5;
            col += float3(0.08, 0.08, 0.1) * smoothstep(1.0, 0.0, abs(px.y - sepY));
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
