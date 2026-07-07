// kidpix_stroke — the thick black "draw-on" brush stroke (right side). A round hard brush paints
// progressively along an authored sweeping hook/"7" path: the stroke GROWS from the leading tip,
// accumulating a thick round trail, then resets each loop. Not a rigid moving shape and not
// edge-jitter — the geometry grows. Implemented as an arc-length reveal of a fixed bezier path:
// a pixel is painted if it is within brush radius of the path AND its path-position <= the tip
// progress. Flat black, premultiplied RGBA. Self-animating on _Time.
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// quadratic bezier point
float2 bez(float2 a, float2 b, float2 c, float t){ return lerp(lerp(a,b,t), lerp(b,c,t), t); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;
    float2 p = uv * float2(aspect, 1.0);

    // authored path as 3 chained quadratic beziers forming a hook -> up -> "7" over on the right.
    // control points in canvas UV (x right, y down). offset by stroke_x / stroke_y.
    float2 O = float2(stroke_x, stroke_y);
    float2 A0 = O + float2(0.10, 0.30);   // bottom-left curl start
    float2 A1 = O + float2(0.02, 0.22);
    float2 A2 = O + float2(0.10, 0.12);   // hook top
    float2 B1 = O + float2(0.20, 0.02);
    float2 B2 = O + float2(0.34, 0.00);   // top ridge (the "7" top-left)
    float2 C1 = O + float2(0.30, 0.14);
    float2 C2 = O + float2(0.22, 0.34);   // descends to lower-right

    // progress of the drawing tip on a seamless loop (draw for ~85% then hold/reset)
    float ph = frac(_Time / loop_seconds);
    float prog = saturate(ph / max(draw_frac, 0.01));   // 0..1 tip travel, holds at 1

    float brush = brush_width;
    float best = 1e9; float paintT = 1e9;

    // sample the 3-bezier path; track nearest distance among the REVEALED portion
    const int NS = 48;
    [loop] for (int i = 0; i <= NS; i++)
    {
        float g = (float)i / (float)NS;            // 0..1 along whole path
        float2 sp;
        if (g < 0.4)      sp = bez(A0, A1, A2, g / 0.4);
        else if (g < 0.72) sp = bez(A2, B1, B2, (g - 0.4) / 0.32);
        else               sp = bez(B2, C1, C2, (g - 0.72) / 0.28);
        sp *= float2(aspect, 1.0);
        float d = length(p - sp);
        if (g <= prog && d < best) { best = d; paintT = g; }
    }

    // round brush cap at the moving tip gives the growing look; hard edge
    float aa = 1.2 / res.y;
    float cov = smoothstep(brush + aa, brush - aa, best);

    float3 black = float3(0.04, 0.04, 0.05);
    OutputUAV[px] = float4(black * cov, cov) * intensity;
}
