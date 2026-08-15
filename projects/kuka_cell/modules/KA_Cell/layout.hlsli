// KA_Cell / layout.hlsli — the diagram's coordinate system.
//
// The pick test and the canvas both go through these functions, so what you can see is exactly
// what you can grab. Everything is in normalized uv against the module's own _Resolution.
//
// A PLAN over an ELEVATION, sharing the world X axis and — importantly — sharing ONE metres-
// per-pixel scale. Two strips at different scales are two drawings, not a plan and an elevation:
// a ring would not be round, and an arm would not be as tall as the plan says it is wide.
//
// The right-hand column is the INSPECTOR. It exists because an isotropic fit of a wide-ish cell
// into a wide strip always leaves horizontal slack, and slack spent on empty grid is slack not
// spent on the numbers for whatever is selected.
#ifndef KA_LAYOUT_HLSLI
#define KA_LAYOUT_HLSLI

#define KA_X0   0.034
#define KA_X1   0.716
#define KA_PY0  0.086
#define KA_PY1  0.628
#define KA_EY0  0.664
#define KA_EY1  0.940

#define KA_IX0  0.736
#define KA_IX1  0.966
#define KA_IY0  0.086
#define KA_IY1  0.940

struct KaMap
{
    float2 res;
    float  s;          // pixels per metre, shared by both strips
    float2 planC;      // uv centre of the plan strip
    float  elevY;      // uv y of the elevation floor line
};

// maxRise is scanned from the live records so the elevation always fits its tallest machine.
// Both passes pass the same value (the state pass computes it and republishes it in the header),
// which is what keeps the pick and the drawing on the same scale.
KaMap kaMap(float2 res, float cw, float cd, float maxRise)
{
    KaMap m;
    m.res = res;
    float sx = (KA_X1 - KA_X0) * res.x / max(cw, 0.5);
    float sz = (KA_PY1 - KA_PY0) * res.y / max(cd, 0.5);
    float sh = (KA_EY1 - KA_EY0 - 0.028) * res.y / max(maxRise * 1.10, 0.5);
    m.s = min(sx, min(sz, sh));
    m.planC = float2((KA_X0 + KA_X1) * 0.5, (KA_PY0 + KA_PY1) * 0.5);
    m.elevY = KA_EY1 - 0.016;
    return m;
}

float2 kaPlanUV(KaMap m, float2 w)
{
    return m.planC + float2(w.x * m.s / m.res.x, w.y * m.s / m.res.y);
}
float2 kaUVPlan(KaMap m, float2 uv)
{
    return float2((uv.x - m.planC.x) * m.res.x / m.s, (uv.y - m.planC.y) * m.res.y / m.s);
}
float2 kaElevUV(KaMap m, float x, float h)
{
    return float2(m.planC.x + x * m.s / m.res.x, m.elevY - h * m.s / m.res.y);
}
float kaUVElevX(KaMap m, float ux) { return (ux - m.planC.x) * m.res.x / m.s; }
float kaUVElevH(KaMap m, float uy) { return (m.elevY - uy) * m.res.y / m.s; }

// metres -> uv length, per axis
float kaLenX(KaMap m, float metres) { return metres * m.s / m.res.x; }
float kaLenY(KaMap m, float metres) { return metres * m.s / m.res.y; }

int kaStrip(float2 uv)
{
    if (uv.x < KA_X0 - 0.015 || uv.x > KA_X1 + 0.015) return 0;
    if (uv.y >= KA_PY0 && uv.y <= KA_PY1) return 1;
    if (uv.y >= KA_EY0 && uv.y <= KA_EY1) return 2;
    return 0;
}

#endif
