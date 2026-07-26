RWTexture2D<float4> OutputUAV : register(u0);

static const float FL_PI = 3.14159265359;

float fl_hash11(float n)
{
    return frac(sin(n * 127.1 + 311.7) * 43758.5453123);
}

float2 fl_rotate(float2 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float fl_triangle(float x)
{
    return abs(frac(x) - 0.5) * 2.0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p = fl_rotate(p, fold_angle);

    float2 scar = scar_position * float2(aspect, 1.0);
    float2 rel = p - scar;
    float faultSide = rel.x + sin(rel.y * 4.0 + phase * FL_PI * 2.0) * (0.035 + rupture * 0.14);
    float faultGate = smoothstep(-0.035, 0.035, faultSide);

    float rowCoord = (p.y + 0.74) * (float)plate_count;
    float rowId = floor(rowCoord);
    float rowLocal = frac(rowCoord);
    float rowShift = (fl_hash11(rowId + 19.0) - 0.5) * fault_tension;
    float alternate = ((int)rowId & 1) == 0 ? -1.0 : 1.0;

    float2 q = p;
    q.x += rowShift + alternate * shear * 0.12;
    q.x += (faultGate - 0.5) * rupture * (0.12 + 0.08 * alternate);
    q.y += (fl_hash11(rowId + 43.0) - 0.5) * fault_tension * 0.025;

    if (symmetry_mode == 0)
    {
        q.x = abs(q.x + shear * 0.04);
    }
    else if (symmetry_mode == 2)
    {
        float2 quadrant = abs(q);
        q = float2(quadrant.x - quadrant.y, quadrant.x + quadrant.y) * 0.70710678;
    }

    float phaseWarp = phase * (1.0 + rupture * 2.0);
    float loomCoord = q.x * cell_scale + q.y * (2.2 + shear * 3.0) + phaseWarp;
    loomCoord += sin(q.y * (7.0 + cell_scale * 0.35) - phase * FL_PI * 2.0) * rupture * 0.34;

    float ridge = fl_triangle(loomCoord);
    float crossCoord = q.y * (cell_scale * 0.62 + 2.0) - q.x * (1.0 + shear * 2.0) - phaseWarp * 0.37;
    float crossRidge = fl_triangle(crossCoord);
    float weave = lerp(ridge, min(ridge, crossRidge), 0.28 + rupture * 0.34);

    float faultDistance = abs(faultSide) / sqrt(1.0 + rupture * rupture);
    float seam = saturate(1.0 - faultDistance * (22.0 + fault_tension * 28.0));
    float plateEdge = saturate(1.0 - min(rowLocal, 1.0 - rowLocal) * (28.0 + cell_scale));
    float region = fl_hash11(rowId + floor(q.x * 3.0) * 71.0 + 7.0);

    OutputUAV[pixel] = float4(saturate(weave), saturate(max(seam, plateEdge)), region, 1.0);
}
