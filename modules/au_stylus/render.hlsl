// AUTOPSIA — stylus surface. The operator's working plate: registration field,
// every live stimulus with its mode and remaining strength, and a live cursor
// showing exactly what the next deposit will be.
#include "types.hlsli"
#include "../_shared/au_hud/au_text.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<StimulusRecord> Stim : register(t1);

float seg2(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-7));
    return length(p - (a + ab * h));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float2 tp = uv * _Resolution.xy;

    float3 col = float3(0.006, 0.0065, 0.007);

    // ---- registration field --------------------------------------------------
    float2 g = uv * float2(32.0, 18.0);
    float2 gi = min(frac(g), 1.0 - frac(g));
    float ticks = saturate((1.0 - smoothstep(0.0, 0.02, gi.x)) * (1.0 - smoothstep(0.06, 0.14, gi.y))
                         + (1.0 - smoothstep(0.0, 0.02, gi.y)) * (1.0 - smoothstep(0.06, 0.14, gi.x)));
    col += float3(0.055, 0.057, 0.054) * ticks;

    StimulusRecord ctrl = Stim[CTRL_SLOT];
    float3 ink = float3(0.88, 0.885, 0.86);
    float3 dim = float3(0.42, 0.425, 0.41);

    // ---- deposited stimuli ---------------------------------------------------
    float live = 0.0;
    [loop] for (uint i = 0u; i < STIM_SLOTS; ++i) {
        StimulusRecord s = Stim[i];
        if (!stimActive(s)) continue;
        live += 1.0;

        float2 sp = (s.position - 0.5) * float2(aspect, 1.0);
        float2 d = p - sp;
        float dist = length(d);
        float r = max(s.radius, 0.008);
        float str = saturate(s.strength);

        // outer boundary: solid for mass, dashed for incision
        float ang = atan2(d.y, d.x);
        float dash = (s.mode > 0.5) ? step(0.5, frac(ang * 2.2)) : 1.0;
        float ring = (1.0 - smoothstep(px.y * 0.5, px.y * 1.7, abs(dist - r))) * dash;

        // strength is drawn as a filled arc of the ring, so it is readable
        float arcT = frac(ang / 6.2831853 + 0.5);
        float arc = (1.0 - smoothstep(px.y * 1.2, px.y * 3.0, abs(dist - r * 0.86)))
                  * step(arcT, str);

        float core = 1.0 - smoothstep(px.y * 1.0, px.y * 2.6, dist);
        float2 dir = normalize(s.direction + float2(1e-5, 1e-5));
        float leader = 1.0 - smoothstep(px.y * 0.5, px.y * 1.5,
                                        seg2(p, sp, sp + dir * r * 1.5));

        float3 tone = (s.mode > 0.5) ? accent_color : ink;
        col += tone * (ring * 0.85 + arc * 0.55 + core * 0.8 + leader * 0.35) * (0.35 + 0.65 * str);
    }

    // ---- live cursor: exactly what the next deposit will be -----------------
    float2 cp = (_ViewportPointerPosition - 0.5) * float2(aspect, 1.0);
    float cd = length(p - cp);
    float cr = max(ctrl.radius, 0.008);
    float cursor = 1.0 - smoothstep(px.y * 0.4, px.y * 1.4, abs(cd - cr));
    float cdash = (ctrl.mode > 0.5) ? step(0.5, frac(atan2(p.y - cp.y, p.x - cp.x) * 2.2)) : 1.0;
    float cross = (1.0 - smoothstep(px.y * 0.4, px.y * 1.3, abs(p.x - cp.x))) * step(abs(p.y - cp.y), 0.020)
                + (1.0 - smoothstep(px.y * 0.4, px.y * 1.3, abs(p.y - cp.y))) * step(abs(p.x - cp.x), 0.020);
    float3 cursorTone = (ctrl.mode > 0.5) ? accent_color : float3(0.70, 0.705, 0.68);
    col += cursorTone * (cursor * cdash * 0.65 + saturate(cross) * 0.55);

    // ---- labels --------------------------------------------------------------
    col += ink * auText(tp, float2(18.0, 20.0), 2.0, G_S,G_T,G_Y,G_L,G_U,G_S, 0,0,0,0,0,0);
    col += dim * auText(tp, float2(18.0, 42.0), 1.0,
        G_L,G_M,G_B,G_SP,G_M,G_A,G_S,G_S, 0,0,0,0);
    col += dim * auText(tp, float2(18.0, 54.0), 1.0,
        G_R,G_M,G_B,G_SP,G_C,G_U,G_T, 0,0,0,0,0);
    col += dim * auText(tp, float2(18.0, 66.0), 1.0,
        G_X,G_SP,G_C,G_L,G_E,G_A,G_R, 0,0,0,0,0);

    col += dim * auText(tp, float2(_Resolution.x - 190.0, 20.0), 1.0,
        G_L,G_I,G_V,G_E, 0,0,0,0,0,0,0,0);
    col += ink * auNum(tp, float2(_Resolution.x - 140.0, 20.0), 1.0, (int)live, 2);
    col += dim * auText(tp, float2(_Resolution.x - 190.0, 34.0), 1.0,
        G_R,G_A,G_D, 0,0,0,0,0,0,0,0,0);
    col += ink * auFixed(tp, float2(_Resolution.x - 148.0, 34.0), 1.0, ctrl.radius);
    col += dim * auText(tp, float2(_Resolution.x - 190.0, 48.0), 1.0,
        G_M,G_O,G_D,G_E, 0,0,0,0,0,0,0,0);
    if (ctrl.mode > 0.5)
        col += accent_color * auText(tp, float2(_Resolution.x - 140.0, 48.0), 1.0,
            G_C,G_U,G_T, 0,0,0,0,0,0,0,0,0);
    else
        col += ink * auText(tp, float2(_Resolution.x - 140.0, 48.0), 1.0,
            G_M,G_A,G_S,G_S, 0,0,0,0,0,0,0,0);

    // frame
    float4 fr = float4(0.008, 0.012, 0.992, 0.988);
    float inner = step(fr.x + px.x, uv.x) * step(uv.x, fr.z - px.x)
                * step(fr.y + px.y, uv.y) * step(uv.y, fr.w - px.y);
    float outer = step(fr.x, uv.x) * step(uv.x, fr.z) * step(fr.y, uv.y) * step(uv.y, fr.w);
    col += float3(0.26, 0.265, 0.25) * (outer - inner);

    Out[tid.xy] = float4(saturate(col), 1.0);
}
