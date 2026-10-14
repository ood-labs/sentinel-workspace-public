// Variant_Switcher_UI / switcher_view - the panel geometry in output pixels, for both passes that
// draw it: render.hlsl puts the Mux program on the stage, layout.hlsl frames and captions it.
//
// The header is the top 13 % of the panel (it holds the host controls, whose manifest rects are
// the hit test), a keycap footer strip runs along the bottom, and the stage is the program fitted,
// aspect-correct, into what is left between them.
#ifndef SWITCHER_VIEW_HLSLI
#define SWITCHER_VIEW_HLSLI

static const float SW_HEADER = 0.13;    // of the panel height, as the controls are laid out

// The ui scale: 1 at 1280 x 720, never so small that type drops under ~9 px.
float swScale(float2 res) { return clamp(min(res.x / 1280.0, res.y / 720.0), 0.9, 2.4); }
float swFooterH(float2 res) { return 30.0 * swScale(res); }

// The area the stage may use, and the stage: the input's aspect, centred in it.
float4 swContainer(float2 res)
{
    float s = swScale(res);
    return float4(0.02 * res.x, SW_HEADER * res.y + 6.0 * s, 0.98 * res.x, res.y - swFooterH(res));
}
float4 swStage(float2 res, float2 input)
{
    float4 c = swContainer(res);
    float2 size = max(c.zw - c.xy, float2(1.0, 1.0));
    float inputAspect = input.x / max(input.y, 1.0);
    float4 st = c;
    if (size.x / size.y > inputAspect)
    {
        float w = size.y * inputAspect, cx = 0.5 * (c.x + c.z);
        st.x = cx - 0.5 * w;
        st.z = cx + 0.5 * w;
    }
    else
    {
        float h = size.x / inputAspect, cy = 0.5 * (c.y + c.w);
        st.y = cy - 0.5 * h;
        st.w = cy + 0.5 * h;
    }
    return st;
}

#endif
