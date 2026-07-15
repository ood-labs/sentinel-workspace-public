// face_guide — procedural frontal-face structure plate for StreamDiff img2img.
// Draws a skin-tone head with hair, eye sockets, brows, nose, and lips so the
// generated face lands its features in predictable spots (stable landmarks for
// downstream MediaPipe tracking). ps_5_0 fullscreen pass; injected VS_OUTPUT{Position,Uv}.

static const float ASPECT = 896.0 / 512.0;

float2 toFace(float2 uv)
{
    // aspect-correct around head center so circles stay circles
    return (uv - float2(head_x, head_y)) * float2(1.0, ASPECT);
}

float ellipse(float2 p, float2 c, float2 r, float soft)
{
    float2 q = (p - c) / max(r, 1e-4);
    float d = length(q);
    return 1.0 - smoothstep(1.0 - soft, 1.0 + soft, d);
}

float3 shadeSphere(float2 p, float2 c, float2 r, float3 base)
{
    float2 n = (p - c) / max(r, 1e-4);
    float nz = sqrt(saturate(1.0 - dot(n, n)));
    float3 normal = normalize(float3(n.x, -n.y, nz + 0.35));
    float3 L = normalize(float3(-0.35, 0.5, 0.85));
    float diff = saturate(dot(normal, L));
    return base * (0.45 + 0.6 * diff);
}

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float2 p = toFace(uv);

    // ---- background ----
    float3 col = float3(bg_r, bg_g, bg_b);

    // ---- hair mass (behind head, slightly larger, pushed up) ----
    float hairM = ellipse(p, float2(0.0, -0.06), float2(head_rx * 1.14, head_ry * 1.16), 0.05);
    col = lerp(col, float3(hair_r, hair_g, hair_b), hairM);

    // ---- head / skin ----
    float2 headR = float2(head_rx, head_ry);
    float headM = ellipse(p, float2(0.0, 0.0), headR, 0.03);
    float3 skin = shadeSphere(p, float2(0.0, 0.0), headR, float3(skin_r, skin_g, skin_b));
    // jaw taper: narrow lower half a touch
    col = lerp(col, skin, headM);

    // ---- neck ----
    float neckM = ellipse(p, float2(0.0, head_ry * 1.05), float2(head_rx * 0.42, head_ry * 0.5), 0.15) * (p.y > 0.0 ? 1.0 : 0.0);
    col = lerp(col, float3(skin_r, skin_g, skin_b) * 0.8, neckM * 0.9);

    // eye geometry
    float eyeY = -head_ry * 0.12;
    float eyeDX = head_rx * 0.42;
    float2 eyeR = float2(head_rx * 0.24, head_ry * 0.12);

    // ---- brows ----
    float3 browCol = float3(hair_r, hair_g, hair_b) * 0.7;
    float browM = ellipse(p, float2(-eyeDX, eyeY - eyeR.y * 2.4), float2(eyeR.x * 1.05, eyeR.y * 0.42), 0.4)
                + ellipse(p, float2( eyeDX, eyeY - eyeR.y * 2.4), float2(eyeR.x * 1.05, eyeR.y * 0.42), 0.4);
    col = lerp(col, browCol, saturate(browM) * headM);

    // ---- eyes: sclera + iris + pupil ----
    for (int e = 0; e < 2; e++)
    {
        float sx = (e == 0) ? -eyeDX : eyeDX;
        float2 ec = float2(sx, eyeY);
        float scleraM = ellipse(p, ec, eyeR, 0.25);
        col = lerp(col, float3(0.92, 0.90, 0.88), scleraM * headM);
        float irisM = ellipse(p, ec, float2(eyeR.y * 0.95, eyeR.y * 0.95), 0.3);
        col = lerp(col, float3(iris_r, iris_g, iris_b), irisM * headM);
        float pupM = ellipse(p, ec, float2(eyeR.y * 0.42, eyeR.y * 0.42), 0.4);
        col = lerp(col, float3(0.03, 0.03, 0.04), pupM * headM);
        // upper lid shadow
        float lidM = ellipse(p, ec + float2(0.0, -eyeR.y * 0.7), eyeR * float2(1.05, 0.7), 0.3);
        col = lerp(col, skin * 0.7, saturate(lidM - scleraM) * headM * 0.5);
    }

    // ---- nose: soft central ridge + shadow ----
    float noseM = ellipse(p, float2(0.0, head_ry * 0.16), float2(head_rx * 0.16, head_ry * 0.26), 0.4);
    float3 noseShade = skin * 0.82;
    col = lerp(col, noseShade, saturate(noseM) * headM * 0.55);
    float nostrM = ellipse(p, float2(-head_rx * 0.10, head_ry * 0.30), float2(head_rx * 0.05, head_ry * 0.04), 0.5)
                 + ellipse(p, float2( head_rx * 0.10, head_ry * 0.30), float2(head_rx * 0.05, head_ry * 0.04), 0.5);
    col = lerp(col, skin * 0.5, saturate(nostrM) * headM);

    // ---- lips ----
    float2 lipC = float2(0.0, head_ry * 0.52);
    float lipM = ellipse(p, lipC, float2(head_rx * 0.30, head_ry * 0.10), 0.3);
    float3 lipCol = float3(lip_r, lip_g, lip_b);
    col = lerp(col, lipCol, saturate(lipM) * headM);
    // lip line
    float lineM = ellipse(p, lipC, float2(head_rx * 0.30, head_ry * 0.012), 0.6);
    col = lerp(col, lipCol * 0.5, saturate(lineM) * headM);

    // subtle vignette
    float vig = 1.0 - 0.25 * smoothstep(0.4, 1.2, length((uv - 0.5) * float2(1.0, ASPECT)));
    col *= vig;

    return float4(col, 1.0);
}
