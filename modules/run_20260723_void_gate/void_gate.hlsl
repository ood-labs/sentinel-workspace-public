RWTexture2D<float4> OutputUAV : register(u0);

float vg_hash11(float n)
{
    return frac(sin(n * 91.3458 + 17.173) * 47453.5453);
}

float4 vg_program(float2 uv)
{
    float2 safeUv = saturate(uv);
    int2 coord = int2(safeUv * max(_Resolution.xy - 1.0, float2(1.0, 1.0)));
    return _Tex0.Load(int3(coord, 0));
}

float vg_mask(float2 uv)
{
    float2 safeUv = saturate(uv);
    int2 coord = int2(safeUv * max(_Resolution.xy - 1.0, float2(1.0, 1.0)));
    return _Tex1.Load(int3(coord, 0)).r;
}

float vg_box_line(float2 p, float2 center, float2 halfSize, float width)
{
    float2 d = abs(p - center) - halfSize;
    float signedDistance = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return 1.0 - smoothstep(width, width * 2.0, abs(signedDistance));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 gateCenter = gate_center * float2(aspect, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);

    float shiftedRow = uv.y * (float)slice_count + gate_phase * 1.37;
    float rowId = floor(shiftedRow);
    float rowLocal = frac(shiftedRow);
    float rowNoise = vg_hash11(rowId + 13.0);
    float rowSign = ((int)rowId & 1) == 0 ? -1.0 : 1.0;

    float centerShift = (rowNoise - 0.5) * stagger + rowSign * dislocation * 0.08;
    float localCenter = gateCenter.x + centerShift;
    float localWidth = aperture * aspect * (0.48 + rowNoise * 0.68);
    float left = localCenter - localWidth;
    float right = localCenter + localWidth;

    float xDistance = max(p.x - right, left - p.x);
    float xGate = 1.0 - smoothstep(-px * 2.0, px * 2.4, xDistance);
    float rowTrim = smoothstep(0.015, 0.05, rowLocal) * (1.0 - smoothstep(0.95, 0.985, rowLocal));
    float baseGate = xGate * rowTrim;

    float2 sourceUv = uv;
    sourceUv.x += rowSign * dislocation * (0.035 + rowNoise * 0.065);
    sourceUv.y += (rowNoise - 0.5) * dislocation * 0.028;
    if (mirror_fragments != 0 && rowNoise > 0.53)
    {
        sourceUv.x = 1.0 - sourceUv.x;
    }

    float maskValue = vg_mask(sourceUv);
    float structuralSelect = smoothstep(void_bias - 0.18, void_bias + 0.18, maskValue);
    float keep = baseGate * lerp(1.0, structuralSelect, mask_pull);

    float3 program = vg_program(sourceUv).rgb;
    float3 col = void_color;
    col = lerp(col, program, keep);

    float gateEdge = 1.0 - smoothstep(px * (1.0 + edge_weight * 2.0), px * (2.3 + edge_weight * 4.0), abs(xDistance));
    gateEdge *= rowTrim;
    float rowEdge = max(
        1.0 - smoothstep(px, px * 3.0, abs(rowLocal - 0.04) / max((float)slice_count, 1.0)),
        1.0 - smoothstep(px, px * 3.0, abs(rowLocal - 0.96) / max((float)slice_count, 1.0))
    );
    rowEdge *= xGate;

    float maskDx = abs(vg_mask(sourceUv + float2(px / aspect, 0.0)) - vg_mask(sourceUv - float2(px / aspect, 0.0)));
    float maskDy = abs(vg_mask(sourceUv + float2(0.0, px)) - vg_mask(sourceUv - float2(0.0, px)));
    float maskEdge = saturate((maskDx + maskDy) * 2.4) * keep;
    float accent = saturate(gateEdge * 0.82 + rowEdge * 0.36 + maskEdge * mask_trace);
    col = lerp(col, accent_color, accent * accent_weight);

    float2 railCenter = gateCenter + float2(0.0, -0.38);
    float rail = vg_box_line(p, railCenter, float2(aperture * aspect * 0.82, 0.018), px * 1.2);
    float railNotch = vg_box_line(p, railCenter + float2(aperture * aspect * 0.32, 0.0), float2(0.006, 0.043), px);
    col = max(col, (rail + railNotch).xxx * rail_color * rail_strength);

    float outside = 1.0 - smoothstep(0.0, px * 2.0, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    col = max(col, outside.xxx * rail_color * 0.5);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
