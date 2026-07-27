RWTexture2D<float4> OutputUAV : register(u0);

float boxDistance(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sceneDistance(float3 p)
{
    float2 cell = floor(p.xz / 0.92 + 0.5);
    float2 local = p.xz - cell * 0.92;
    float insideGrid = step(max(abs(cell.x), abs(cell.y)), 2.1);
    float tau = 6.28318530718;
    float sequence = 0.5 + 0.5 * sin(dot(cell, float2(1.73, 2.41)) + master_phase * tau);
    float towerHeight = (0.42 + sequence * 1.28) * tower_scale;
    float slabPeriod = max(slab_gap, 0.08);
    float slabY = frac((p.y + 0.04) / slabPeriod) * slabPeriod - slabPeriod * 0.5;
    float3 slabPoint = float3(local.x, slabY, local.y);
    float slab = boxDistance(slabPoint, float3(0.285, slabPeriod * 0.33, 0.285));
    float verticalGate = max(-p.y, p.y - towerHeight);
    float tower = max(slab, verticalGate);
    tower = lerp(10.0, tower, insideGrid);

    float plinth = boxDistance(float3(p.x, p.y + 0.065, p.z), float3(2.55, 0.06, 2.55));
    return min(tower, plinth);
}

float3 sceneNormal(float3 p)
{
    float e = 0.0025;
    float2 h = float2(e, 0.0);
    return normalize(float3(
        sceneDistance(p + h.xyy) - sceneDistance(p - h.xyy),
        sceneDistance(p + h.yxy) - sceneDistance(p - h.yxy),
        sceneDistance(p + h.yyx) - sceneDistance(p - h.yyx)));
}

float lineMask(float value, float width)
{
    return 1.0 - smoothstep(width, width * 2.0, abs(value));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 screen = (uv * 2.0 - 1.0) * float2(aspect, -1.0);
    float tau = 6.28318530718;
    float angle = master_phase * tau;

    float radius = 4.35;
    float3 ro = float3(
        sin(angle) * radius,
        2.05 + 0.42 * sin(angle * 1.5 + 0.7),
        cos(angle) * radius);
    float3 target = float3(0.0, 0.72 + 0.18 * master_envelope, 0.0);
    float3 forward = normalize(target - ro);
    float3 right = normalize(cross(forward, float3(0.0, 1.0, 0.0)));
    float3 up = normalize(cross(right, forward));
    float3 rd = normalize(forward + screen.x * right * 0.72 + screen.y * up * 0.72);

    float travel = 0.0;
    float distanceValue = 0.0;
    float hit = 0.0;
    float3 hitPoint = 0.0;
    [loop]
    for (int stepIndex = 0; stepIndex < 92; ++stepIndex)
    {
        float3 position = ro + rd * travel;
        distanceValue = sceneDistance(position);
        if (distanceValue < 0.0015)
        {
            hit = 1.0;
            hitPoint = position;
            break;
        }
        travel += distanceValue * 0.78;
        if (travel > 12.0) break;
    }

    float3 col = float3(0.0035, 0.004, 0.0035);
    float3 warm = accent;
    float3 neutral = float3(0.88, 0.90, 0.86);

    if (hit > 0.5)
    {
        float3 normal = sceneNormal(hitPoint);
        float3 lightDir = normalize(float3(-0.45, 0.82, -0.28));
        float diffuse = saturate(dot(normal, lightDir));
        float rim = pow(1.0 - saturate(dot(normal, -rd)), 2.5);
        float facing = 0.16 + 0.72 * diffuse + 0.42 * rim;
        col += neutral * facing;

        float slice = min(frac(hitPoint.y / max(slab_gap, 0.08)),
                          1.0 - frac(hitPoint.y / max(slab_gap, 0.08)));
        float seam = 1.0 - smoothstep(0.028, 0.075, slice);
        col = lerp(col, neutral, seam * 0.72);

        float scanPosition = lerp(-2.35, 2.35, master_phase);
        float scan = lineMask(hitPoint.x - scanPosition, 0.035 + 0.035 * master_pulse);
        col = lerp(col, warm, scan);

        float cellMark = min(abs(frac(hitPoint.x / 0.92 + 0.5) - 0.5),
                             abs(frac(hitPoint.z / 0.92 + 0.5) - 0.5));
        float registryEdge = 1.0 - smoothstep(0.015, 0.045, cellMark);
        col = lerp(col, warm * 0.7, registryEdge * 0.35);
    }
    else if (rd.y < -0.001)
    {
        float planeTravel = (-0.13 - ro.y) / rd.y;
        if (planeTravel > 0.0)
        {
            float3 planePoint = ro + rd * planeTravel;
            float2 gridUv = planePoint.xz / 0.92;
            float2 gridCell = abs(frac(gridUv + 0.5) - 0.5);
            float gridLine = 1.0 - smoothstep(0.478, 0.498, max(gridCell.x, gridCell.y));
            float fade = saturate(1.0 - length(planePoint.xz) / 6.0);
            col += neutral * gridLine * 0.11 * fade;
        }
    }

    float horizon = lineMask(uv.y - 0.54, 1.0 / max(_Resolution.y, 1.0));
    col += neutral * horizon * 0.09;
    float vignette = saturate(1.0 - 0.26 * dot(screen / float2(aspect, 1.0), screen / float2(aspect, 1.0)));
    col *= vignette;
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
