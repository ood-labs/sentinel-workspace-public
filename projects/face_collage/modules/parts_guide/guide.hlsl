// parts_guide — centered single-element STRUCTURE plate on pure black for SD_Parts.
// Draws a crude but crisp-edged version of one face element (selected by `shape`) so
// ControlNet (canny) locks the element's position/scale while high denoise makes it
// photoreal, and the black surround lets matting cut it cleanly.
// ps_5_0 fullscreen pass; injected VS_OUTPUT{Position,Uv}. shape enum drives which element.

static const float ASPECT = 896.0 / 512.0;

float ell(float2 p, float2 r, float soft)
{
    float2 q = p / max(r, 1e-4);
    return 1.0 - smoothstep(1.0 - soft, 1.0 + soft, length(q));
}

// distance to a horizontal-ish arc band (for brows / lips lines)
float band(float2 p, float halfW, float curve, float thick)
{
    float yline = curve * (p.x / max(halfW, 1e-4)) * (p.x / max(halfW, 1e-4)); // parabola
    float dy = abs(p.y - yline);
    float inX = 1.0 - smoothstep(halfW * 0.92, halfW, abs(p.x));
    float inY = 1.0 - smoothstep(thick * 0.7, thick, dy);
    return inX * inY;
}

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float2 p = (uv - float2(blob_x, blob_y)) * float2(1.0, ASPECT);
    float s = blob_scale;
    p /= max(0.2, s);

    float3 col = float3(0.0, 0.0, 0.0);
    float3 skin = float3(blob_r, blob_g, blob_b);
    int shape = (int)shape_id;

    if (shape == 0 || shape == 7) // EYE
    {
        // almond sclera
        float2 e = p / float2(0.20, 0.105);
        float d = length(e);
        float almond = (1.0 - smoothstep(0.92, 1.03, d));
        // pinch corners into an almond
        almond *= smoothstep(0.0, 0.25, 0.20 - abs(p.x) * 0.0) ; // keep simple
        col = lerp(col, float3(0.92, 0.90, 0.88), almond);
        // iris + pupil
        float iris = ell(p, float2(0.072, 0.072), 0.08) * step(0.4, almond + 0.6);
        float3 irisCol = float3(iris_r, iris_g, iris_b);
        col = lerp(col, irisCol, saturate(iris));
        float pupil = ell(p, float2(0.032, 0.032), 0.1);
        col = lerp(col, float3(0.02, 0.02, 0.03), saturate(pupil));
        // upper lid crease
        float crease = band(p - float2(0.0, -0.11), 0.19, 0.35, 0.012);
        col = lerp(col, skin * 0.55, saturate(crease));
        // lower lash line
        float lash = band(p - float2(0.0, 0.10), 0.19, -0.25, 0.010);
        col = lerp(col, float3(0.08, 0.06, 0.06), saturate(lash));
    }
    else if (shape == 1) // LIPS
    {
        float3 lip = float3(lip_r, lip_g, lip_b);
        // lower lip (fuller)
        float lower = ell(p - float2(0.0, 0.045), float2(0.17, 0.062), 0.06);
        // upper lip (two bumps via parabola band with thickness)
        float upperBand = band(p - float2(0.0, -0.02), 0.17, -0.9, 0.05);
        float upperbow = band(p - float2(0.0, -0.035), 0.055, 2.2, 0.03); // cupid dip
        float upper = saturate(upperBand - upperbow);
        float lips = saturate(lower + upper);
        col = lerp(col, lip, lips);
        // mouth line
        float mline = band(p - float2(0.0, 0.005), 0.17, 0.0, 0.008);
        col = lerp(col, lip * 0.35, saturate(mline) * lips);
    }
    else if (shape == 2) // BROW
    {
        float3 brow = float3(0.14, 0.09, 0.07);
        float arch = band(p, 0.19, -0.55, 0.028);
        col = lerp(col, brow, saturate(arch));
    }
    else if (shape == 3) // NOSE
    {
        // bridge (tall) + tip + nostrils
        float bridge = ell(p - float2(0.0, -0.02), float2(0.055, 0.16), 0.12);
        float tip = ell(p - float2(0.0, 0.12), float2(0.075, 0.06), 0.15);
        float form = saturate(bridge + tip);
        col = lerp(col, skin, form);
        // shading on sides
        col = lerp(col, skin * 0.7, saturate(ell(p - float2(-0.06, 0.08), float2(0.03, 0.08), 0.2) + ell(p - float2(0.06, 0.08), float2(0.03, 0.08), 0.2)) * 0.6);
        // nostrils
        float nos = ell(p - float2(-0.045, 0.145), float2(0.022, 0.016), 0.2) + ell(p - float2(0.045, 0.145), float2(0.022, 0.016), 0.2);
        col = lerp(col, float3(0.05, 0.03, 0.03), saturate(nos));
    }
    else if (shape == 4) // EAR
    {
        // outer ear ellipse ring
        float outer = ell(p, float2(0.12, 0.17), 0.05);
        float inner = ell(p - float2(0.015, 0.0), float2(0.075, 0.11), 0.08);
        float ring = saturate(outer - inner * 0.85);
        col = lerp(col, skin, saturate(outer));
        col = lerp(col, skin * 0.6, saturate(inner));
        col = lerp(col, skin, saturate(ring));
        // gold earring dot at lobe
        float earring = ell(p - float2(-0.02, 0.16), float2(0.02, 0.02), 0.2);
        col = lerp(col, float3(0.85, 0.65, 0.2), saturate(earring));
    }
    else // 5,6,8 PATCH / FRECKLED SKIN
    {
        float patch = ell(p, float2(0.17, 0.15), 0.12);
        float2 n = p / float2(0.17, 0.15);
        float nz = sqrt(saturate(1.0 - dot(n, n)));
        col = lerp(col, skin * (0.6 + 0.5 * nz), saturate(patch));
        // a few freckle dots
        float fr = 0.0;
        fr += ell(p - float2(-0.05, -0.02), float2(0.012, 0.012), 0.3);
        fr += ell(p - float2(0.04, 0.03), float2(0.010, 0.010), 0.3);
        fr += ell(p - float2(0.0, -0.06), float2(0.011, 0.011), 0.3);
        fr += ell(p - float2(0.06, -0.04), float2(0.010, 0.010), 0.3);
        col = lerp(col, skin * 0.45, saturate(fr) * patch);
    }

    return float4(col, 1.0);
}
