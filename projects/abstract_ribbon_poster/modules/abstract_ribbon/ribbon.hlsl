// abstract_ribbon_render: shades a folded ribbed ribbon around a data-driven PNode path.

RWTexture2D<float4> OutputUAV : register(u0);

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

StructuredBuffer<PNode> Path : register(t0);

static const float TAU_LOCAL = 6.2831853;

float segDistParam(float2 p, float2 a, float2 b, out float h)
{
    float2 pa = p - a;
    float2 ba = b - a;
    h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float wrapDist(float a, float b)
{
    float d = abs(a - b);
    return min(d, 1.0 - d);
}

float3 ribbonPalette(float u, float fold)
{
    float3 cream = warm_color;
    float3 orange = orange_color;
    float3 magenta = magenta_color;
    float3 wine = lerp(float3(0.38, 0.06, 0.18), magenta_color * 0.48, 0.4);
    float3 mint = mint_color;
    float3 blue = dark_color;

    float3 col = cream;
    col = lerp(col, orange, smoothstep(0.08, 0.28, u) * (1.0 - smoothstep(0.34, 0.48, u)));
    col = lerp(col, magenta, smoothstep(0.22, 0.43, u) * (1.0 - smoothstep(0.62, 0.78, u)));
    col = lerp(col, wine, smoothstep(0.38, 0.57, u) * 0.75);
    col = lerp(col, mint, smoothstep(0.62, 0.82, u) * (1.0 - smoothstep(0.88, 0.99, u)));
    col = lerp(col, blue, fold * fold_darkness);

    if (palette_mode == 1)
    {
        col = lerp(cream, float3(0.96, 0.18, 0.40), smoothstep(0.12, 0.78, u));
        col = lerp(col, blue, fold * 0.95);
    }
    else if (palette_mode == 2)
    {
        col = lerp(float3(0.92, 0.82, 0.58), float3(0.10, 0.18, 0.55), smoothstep(0.0, 1.0, u));
        col = lerp(col, orange, exp(-pow((u - 0.18) * 5.0, 2.0)));
    }
    else if (palette_mode == 3)
    {
        col = lerp(float3(0.76, 0.90, 0.84), float3(0.08, 0.06, 0.38), smoothstep(0.0, 1.0, u));
        col = lerp(col, magenta, smoothstep(0.35, 0.70, u) * 0.35);
    }

    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = float2((uv.x - 0.5) * asp, 0.5 - uv.y);

    float tAnim = _Time * motion;
    p += float2(0.004 * sin(tAnim * 0.7 + uv.y * 5.0), -0.003 * sin(tAnim * 0.43 + uv.x * 4.0)) * shimmer;

    float bestD = 999.0;
    float bestH = 0.0;
    float bestU = 0.0;
    float bestW = 0.035;
    float bestFold = 0.0;
    float2 bestA = 0.0;
    float2 bestB = 0.0;

    uint cnt = min((uint)_Data0_Count, 160u);
    [loop]
    for (uint i = 0u; i < 160u; ++i)
    {
        if (i + 1u >= cnt) break;
        PNode a = Path[i];
        PNode b = Path[i + 1u];
        if (a.active < 0.5 || b.active < 0.5) continue;
        float h = 0.0;
        float d = segDistParam(p, a.pos, b.pos, h);
        if (d < bestD)
        {
            bestD = d;
            bestH = h;
            bestU = lerp(a.u, b.u, h);
            bestW = lerp(a.weight, b.weight, h);
            bestFold = lerp(a.kind, b.kind, h);
            bestA = a.pos;
            bestB = b.pos;
        }
    }

    float w = max(bestW * width_gain, 0.001);
    float nrm = bestD / w;
    float mask = 1.0 - smoothstep(0.98, 1.045, nrm);

    float2 tangent = normalize(bestB - bestA + 1e-5);
    float2 normal = float2(-tangent.y, tangent.x);
    float side = sign(dot(p - lerp(bestA, bestB, bestH), normal));
    float signedN = side * nrm;

    float foldGate = bestFold * (1.0 - smoothstep(0.05, 0.80, abs(signedN - fold_side)));
    float3 baseCol = ribbonPalette(bestU, foldGate);

    float ribsCoord = (signedN * 0.5 + 0.5) * rib_count + bestU * rib_slant + rib_phase * rib_count + tAnim * 0.035;
    float ribs = 1.0 - smoothstep(0.0, rib_width, abs(frac(ribsCoord) - 0.5));
    ribs *= 1.0 - smoothstep(0.93, 1.02, nrm);

    float sideLight = 0.72 + 0.28 * smoothstep(-0.95, 0.75, signedN);
    float3 col = baseCol * sideLight;
    col = lerp(col, col * 0.52, ribs * line_strength);

    float rim = smoothstep(0.70, 0.99, nrm);
    col += float3(1.0, 0.78, 0.50) * rim * rim_gain;

    float lower = exp(-pow(wrapDist(bestU, 0.38) * 5.0, 2.0)) * (1.0 - smoothstep(0.45, 1.0, nrm));
    col += lower * orange_color * lower_glow;

    float hU = exp(-pow(wrapDist(bestU, highlight_pos) * 4.0, 2.0));
    float hSide = exp(-pow(signedN - highlight_side, 2.0) * 22.0);
    col += hU * hSide * float3(0.72, 0.95, 0.90) * 0.42;

    OutputUAV[pixel] = float4(saturate(col) * mask * intensity, saturate(mask));
}
