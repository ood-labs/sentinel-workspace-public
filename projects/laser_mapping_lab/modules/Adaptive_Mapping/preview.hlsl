// Adaptive_Mapping / preview - the Mapped Path canvas, the DRAWING only: the field plate, the
// scanner's +-1 reach with its half and centre lines, and the path the draw pass rasterized in each
// record's own colour (screen preview gain only; scan data and physical intensity are untouched).
// The words, readouts, trace, hover inspector and verb are recorded by layout.hlsl and drawn over
// this by the shared UI kit (ui.hlsl). The rects come from am_view.hlsli.
#include "../_shared/ui/il_core.hlsli"
#include "am_view.hlsli"
StructuredBuffer<float4> S:register(t1);
float4 main(VS_OUTPUT i):SV_TARGET0
{
    float2 R = _Resolution.xy;
    float2 P = i.Uv * R;
    AMLayout L = amLayout(R);
    float3 c = IL_FIELD;
    ilOver(c, IL_PANEL, ilFill(ilSdBox(P, L.field, IL_RADIUS * L.s)));
    // the scanner's reach: an inset well with a line every half field unit, the centre a step up
    float k = amFieldScale(L);
    float2 o = amFieldPx(L, float2(0.0, 0.0));
    float2 d = P - o;
    float4 sq = float4(o - k, o + k);
    if (ilIn(P, sq))
    {
        c = IL_WELL;
        ilOver(c, IL_GRID, max(ilGridLine(d.x, 0.5 * k, 1.0), ilGridLine(d.y, 0.5 * k, 1.0)));
        ilOver(c, IL_EDGE, max(saturate(1.0 - abs(d.x)), saturate(1.0 - abs(d.y))));
    }
    ilOver(c, IL_RULE, ilBorder(ilSdBox(P, ilInset(sq, -1.0), 0.0), 1.0));
    // the path, each record in its own colour pulled toward the instrument (edges keep their AA)
    float3 raw = _Tex0.SampleLevel(LinearSampler, i.Uv, 0).rgb * 8.0;
    float m = max(raw.r, max(raw.g, raw.b));
    if (m > 1e-4) ilOver(c, ptSampleColour(raw / m), saturate(m));
    return float4(c, 1.0);
}
