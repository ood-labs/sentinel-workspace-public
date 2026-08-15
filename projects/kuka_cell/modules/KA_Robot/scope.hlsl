// KA_Robot / scope.hlsl — the annotated view.
//
// A SECOND PASS IN THE RENDERER, not a downstream node, and a second OUTPUT rather than a
// second image path. It receives exactly the same injected camera state as the march pass, so
// its marks cannot drift out of registration at any distance or speed — which a following node
// mirroring camera parameters cannot promise past a hundred units.
//
// It depth-tests against the linear depth the march pass published in alpha, so a mark behind a
// machine ghosts instead of drawing straight through it.
#include "../_shared/cell.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "../_shared/glyphs.hlsli"

StructuredBuffer<KaRec>  Cell  : register(t1);
StructuredBuffer<KaPose> Pose  : register(t2);
StructuredBuffer<KaBall> Rally : register(t3);
StructuredBuffer<KaUi>   Ui    : register(t4);
RWTexture2D<float4> OutputUAV : register(u0);

float segD(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
// Every stroke in this file goes through here, so Mark Weight is one multiplier in one place
// rather than forty hand-tuned pixel widths. Ring and arrow marks call strokeAA too, so they
// thicken with everything else and the diagram stays internally consistent at any weight.
float strokeAA(float d, float w)
{
    float ww = w * max(scope_weight, 0.05);
    return 1.0 - smoothstep(ww - 0.7, ww + 0.7, d);
}
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float ringAA(float2 p, float2 c, float r, float w) { return strokeAA(abs(length(p - c) - r), w); }
float txtAt(float2 p, float2 org, float h, uint2 packed, uint count)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    return mf_text((p - org) / float2(cw * (float)count, h), packed, count);
}
float numAt(float2 p, float2 org, float h, uint v, uint digits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    return mf_num((p - org) / float2(cw * (float)digits, h), v, digits);
}
float txtW(float h, uint count) { return h * (5.0 / 7.0) * 1.2 * (float)count; }
float dec1At(float2 p, float2 org, float h, float v, uint intDigits)
{
    float cw = txtW(h, 1u);
    float x = org.x;
    float g = (v < 0.0) ? txtAt(p, float2(x, org.y), h, uint2(MF_DASH, 0u), 1u) : 0.0;
    x += cw;
    uint tenths = (uint)min(abs(v) * 10.0 + 0.5, 99999.0);
    g = max(g, numAt(p, float2(x, org.y), h, tenths / 10u, intDigits));
    x += cw * (float)intDigits;
    g = max(g, txtAt(p, float2(x, org.y), h, uint2(MF_DOT, 0u), 1u));
    x += cw;
    return max(g, numAt(p, float2(x, org.y), h, tenths % 10u, 1u));
}

// ---------------------------------------------------------------------------
// Mark colour
// ---------------------------------------------------------------------------
// Hue is assigned by WHAT A MARK MEANS, never by which line happened to need drawing next, so a
// palette swap re-skins the instrument without shuffling what anything stands for:
//
//   FUTURE   the predicted arc — where the ball is going to be
//   NOW      the velocity vector — how fast it is going right now
//   SUBJECT  the ball itself, and its plumb line
//   DECIDE   the contact and the elected striker. Keeps the accent in every palette, because it
//            is the single thing the whole diagram exists to show being decided.
//
// Every mark passes through scMark(), which blends from the project's grey-and-amber instrument
// theme toward that hue. At Mark Colour 0 the blend does nothing and the scope is the monochrome
// instrument the rest of the project is drawn in; the dial is the whole range in between.
struct ScopePal { float3 future, now, subject, decide, arm, alarm; };

ScopePal scopePalette()
{
    ScopePal p;
    p.alarm = PT_ALARM;
    int k = (int)scope_palette;
    if (k == 0)          // Pure — solid RGB primaries, for reading marks off a bright render
    {
        p.future  = float3(0.10, 1.00, 0.20);
        p.now     = float3(0.15, 0.45, 1.00);
        p.subject = float3(1.00, 1.00, 1.00);
        p.decide  = float3(1.00, 0.10, 0.10);
        p.arm     = float3(0.00, 0.90, 1.00);
        // DECIDE takes red here, which is alarm's colour everywhere else in the project, so
        // alarm moves to magenta rather than letting the two states become indistinguishable.
        // The rule that matters is that they differ, not which hue each one holds.
        p.alarm   = float3(1.00, 0.10, 0.85);
    }
    else if (k == 2)     // Chalk — soft pastels, for bright grounds where saturated ink glares
    {
        p.future  = float3(0.62, 0.93, 0.68);
        p.now     = float3(0.99, 0.86, 0.55);
        p.subject = float3(0.95, 0.93, 0.90);
        p.decide  = float3(1.00, 0.72, 0.42);
        p.arm     = float3(0.72, 0.84, 0.95);
    }
    else if (k == 3)     // Blueprint — cool and technical, hue carried by the cyans
    {
        p.future  = float3(0.35, 0.95, 0.80);
        p.now     = float3(0.55, 0.80, 1.00);
        p.subject = float3(0.86, 0.94, 1.00);
        p.decide  = float3(1.00, 0.78, 0.30);
        p.arm     = float3(0.40, 0.62, 0.88);
    }
    else                 // Signal — saturated and separable, the loudest of the three
    {
        p.future  = float3(0.16, 0.96, 0.42);
        p.now     = float3(0.30, 0.72, 1.00);
        p.subject = float3(1.00, 0.97, 0.92);
        p.decide  = float3(1.00, 0.58, 0.10);
        p.arm     = float3(0.52, 0.72, 1.00);
    }
    return p;
}

float3 scMark(float3 theme, float3 hue) { return lerp(theme, hue, saturate(scope_hue)); }

bool projectPt(float3 w, float2 res, out float2 sp, out float vz)
{
    sp = float2(-1e6, -1e6); vz = 1e9;
    float4 c = mul(_ViewProjMatrix, float4(w, 1.0));
    if (c.w <= 1e-4) return false;
    float3 n = c.xyz / c.w;
    sp = float2((n.x * 0.5 + 0.5) * res.x, (1.0 - (n.y * 0.5 + 0.5)) * res.y);
    vz = length(w - _CameraPos);
    return true;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;
    float2 res = float2(W, H);
    float2 P = (float2)pixel + 0.5;

    uint bw, bh;
    _Tex0.GetDimensions(bw, bh);
    float4 src = _Tex0.Load(int3(clamp(int2(pixel), int2(0, 0), int2(bw, bh) - 1), 0));

    // THE UNDERLAY IS THE PROGRAM IMAGE, graded by the identical path program.hlsl uses, and
    // taken all the way to display space before anything is drawn on it.
    //
    // It used to be its own thing: a Reinhard curve where the Program pass runs ACES plus
    // contrast. That is why no combination of the dim and saturation sliders could ever produce
    // "the render with marks on it" — the two passes were tone-mapping differently, so the scope
    // was always a different picture rather than the same picture annotated. Underlay Level and
    // Underlay Colour now pull AWAY from the true render, and at their 1.0 defaults they do
    // nothing at all: what you get is exactly the Program output with marks laid over it.
    float3 g = src.rgb * exp2(exposure);
    float3 ga = g * (2.51 * g + 0.03);
    float3 gb = g * (2.43 * g + 0.59) + 0.14;
    g = saturate(ga / gb);
    g = saturate((g - 0.5) * contrast + 0.5);
    g = pow(max(g, 0.0), 1.0 / 2.2);                       // display space from here on

    float3 col = lerp(dot(g, float3(0.2126, 0.7152, 0.0722)).xxx, g, scope_sat) * scope_dim;
    float sceneZ = src.a;

    // SPACE toggles this output between the Program image and the instrument, so one preview can
    // be flown in and interrogated without reaching for the output selector. The state comes from
    // the ui pass, which owns it — the Scope checkbox and the key are two ways to say the same
    // thing and only one of them is allowed to be the authority.
    //
    // When it is off this returns the Program grade EXACTLY, not the dimmed underlay: the whole
    // point of the toggle is that pressing Space twice puts you back where you were, and a view
    // that comes back darker than it left is not a toggle, it is a third state.
    if (Ui[0].shown < 0.5)
    {
        float3 c = src.rgb * exp2(exposure);
        float3 ta = c * (2.51 * c + 0.03);
        float3 tb = c * (2.43 * c + 0.59) + 0.14;
        c = saturate(ta / tb);
        c = saturate((c - 0.5) * contrast + 0.5);
        OutputUAV[pixel] = float4(pow(max(c, 0.0), 1.0 / 2.2), 1.0);
        return;
    }

    ScopePal PAL = scopePalette();

    uint liveN = 0u, alarmN = 0u;

    for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaRec r = Cell[KA_ARM_0 + i];
        KaPose q = Pose[KA_ARM_0 + i];
        if (r.active < 0.5 || q.live < 0.5) continue;
        liveN++;
        uint al = (uint)q.alarm;
        if (al != 0u) alarmN++;

        bool isSel = ((uint)r.flags & KF_SELECTED) != 0u;
        float3 idc = ptId((int)q.chan);

        float2 sb, se, st; float zb, ze, zt;
        bool okB = projectPt(float3(r.pos.x, 0.02, r.pos.y), res, sb, zb);
        bool okT = projectPt(q.tool, res, st, zt);

        if (okB)
        {
            float vis = (zb < sceneZ + 0.15) ? 1.0 : 0.22;
            float m = ringAA(P, sb, 6.0, 1.0);
            m = max(m, strokeAA(segD(P, sb - float2(10, 0), sb - float2(6, 0)), 0.8));
            m = max(m, strokeAA(segD(P, sb + float2(6, 0), sb + float2(10, 0)), 0.8));
            col = lerp(col, isSel ? PT_ACCENT : idc * 1.55, m * vis);
            if (isSel)
                col = lerp(col, PT_ACCENT, ringAA(P, sb, 11.0, 1.0) * vis);
        }

        if (okT)
        {
            float vis = (zt < sceneZ + 0.15) ? 1.0 : 0.20;
            bool bad = al != 0u;
            float3 tc = bad ? PT_ALARM : (isSel ? PT_ACCENT : idc * 1.55);
            col = lerp(col, tc, discAA(P, st, bad ? 3.4 : 2.6) * vis);
            if (bad) col = lerp(col, PT_ALARM, ringAA(P, st, 7.5, 1.0) * vis);
        }

        // the selected machine gets its whole chain drawn, which is the only readout that
        // says which physical arm the plan's inspector is talking about
        if (isSel)
        {
            bool okE = projectPt(q.elbow, res, se, ze);
            if (okB && okE) col = lerp(col, scMark(PT_ACCENT, PAL.arm), strokeAA(segD(P, sb, se), 0.8) * 0.55);
            if (okE && okT) col = lerp(col, scMark(PT_ACCENT, PAL.arm), strokeAA(segD(P, se, st), 0.8) * 0.55);
            if (okB)
                col = lerp(col, PT_ACCENT, numAt(P, sb + float2(13.0, -4.0), 9.0, i, 2u));
        }
    }

    // ---- the rally: who is on the ball, and where they are going to meet it ----
    {
        KaBall bh = Rally[KA_HEADER];
        int striker = (int)bh.strikerIdx;
        if (bh.role != KA_PLAY_IDLE)
        {
            // ---- THE PREDICTED FLIGHT ----
            //
            // Drawn from the SAME trajectory records the election ran on, not re-integrated here.
            // A scope that solves its own arc is drawing a second opinion: it would diverge from
            // the one the arms are playing exactly when the two disagree, which is the moment the
            // diagram most needs to be trusted.
            //
            // Grey, not accent. It is context — where the ball is headed — and the accent belongs
            // to the one thing being decided, which is the contact.
            {
                float m = 0.0;
                float2 prevS = float2(-1e6, -1e6);
                bool havePrev = false;
                for (uint w = 0u; w < KA_TRAJ_N; w++)
                {
                    KaBall s = Rally[KA_TRAJ_0 + w];
                    if (s.role < 0.5) { havePrev = false; continue; }
                    float2 ss; float sz;
                    if (!projectPt(s.pos, res, ss, sz)) { havePrev = false; continue; }
                    if (havePrev) m = max(m, strokeAA(segD(P, prevS, ss), 0.7));
                    prevS = ss; havePrev = true;
                }
                // DASHED, because the velocity arrow leaves the ball in the same direction and a
                // second solid line beside it just reads as a thick one. Dashes say "this is
                // where it WILL be" against the arrow's solid "this is how fast it is going".
                m *= step(frac((P.x + P.y) * 0.055), 0.55);
                col = lerp(col, scMark(PT_INK, PAL.future), m * 0.75);
            }

            // ---- THE VELOCITY VECTOR ----
            //
            // Scaled by a fixed seconds-of-travel rather than normalised, so the arrow's LENGTH
            // is the speed: it is where the ball would be in a third of a second if nothing
            // touched it and nothing pulled on it. A normalised arrow shows direction and throws
            // away the more interesting half of the reading.
            {
                float spd = length(bh.vel);
                if (spd > 0.2)
                {
                    float3 tipW = bh.pos + bh.vel * 0.33;
                    float2 a0, a1; float za, zt;
                    if (projectPt(bh.pos, res, a0, za) && projectPt(tipW, res, a1, zt))
                    {
                        float2 d = a1 - a0;
                        float dl = max(length(d), 1e-4);
                        float2 u = d / dl;
                        float2 n2 = float2(-u.y, u.x);
                        float m = strokeAA(segD(P, a0 + u * 13.0, a1), 0.7);
                        // an open arrowhead, sized in pixels so it survives any camera distance
                        m = max(m, strokeAA(segD(P, a1, a1 - u * 7.0 + n2 * 4.0), 0.7));
                        m = max(m, strokeAA(segD(P, a1, a1 - u * 7.0 - n2 * 4.0), 0.7));
                        col = lerp(col, scMark(PT_INK, PAL.now), m * 0.85);
                        // the number, off the head so it never sits under the arrow
                        float g = dec1At(P, a1 + n2 * 7.0 + u * 4.0, 9.0, spd, 2u);
                        col = lerp(col, scMark(PT_INK, PAL.now), g * 0.9);
                    }
                }
            }

            float2 sb; float zb;
            if (projectPt(bh.pos, res, sb, zb))
            {
                float vis = (zb < sceneZ + 0.35) ? 1.0 : 0.28;
                // alarm stays alarm at every palette and every strength — the one state that
                // means the composition is broken is not a thing to restyle
                float3 bc = (bh.dropFlag > 0.5) ? scMark(PT_ALARM, PAL.alarm)
                                                : scMark(PT_INK, PAL.subject);
                col = lerp(col, bc, ringAA(P, sb, 13.0, 1.0) * vis * 0.9);
                // plumb line to the floor: without it a ball in a wide shot has no height
                float2 sf; float zf;
                if (projectPt(float3(bh.pos.x, 0.0, bh.pos.z), res, sf, zf))
                    col = lerp(col, bc * 0.8, strokeAA(segD(P, sb, sf), 0.5) *
                                              step(frac(P.y * 0.10), 0.5) * vis * 0.8);
            }
            if (striker >= 0)
            {
                KaBall sa = Rally[KA_ARM_0 + (uint)striker];
                float2 cp; float zc;
                if (projectPt(sa.pos, res, cp, zc))
                {
                    // the contact: where the tool and the ball are going to be at the same time
                    float m = ringAA(P, cp, 10.0, 1.0);
                    m = max(m, strokeAA(segD(P, cp - float2(16, 0), cp - float2(11, 0)), 0.9));
                    m = max(m, strokeAA(segD(P, cp + float2(11, 0), cp + float2(16, 0)), 0.9));
                    col = lerp(col, scMark(PT_ACCENT, PAL.decide), m * 0.95);
                }
                float2 bs; float zs;
                if (projectPt(float3(Cell[KA_ARM_0 + (uint)striker].pos.x, 0.05,
                                     Cell[KA_ARM_0 + (uint)striker].pos.y), res, bs, zs))
                    col = lerp(col, scMark(PT_ACCENT, PAL.decide), ringAA(P, bs, 14.0, 1.2) * 0.9);
            }
        }
    }

    // The Point At target, in the world, at its real height — and ONLY when something is
    // actually aiming at it.
    //
    // It used to draw unconditionally, so during a rally a cross-hair floated in mid-air
    // belonging to a pattern no arm was running. A mark that does not describe anything on screen
    // is worse than no mark: it is read as meaning something, and then it does not.
    //
    // An arm that the rally has claimed carries a rally role; one left on its channel pattern
    // does not. So if every live arm is on the ball, the target has no client and is not drawn.
    // It still appears the moment a channel goes back to a pattern, or whenever it is selected
    // for editing.
    bool targetHasClient = ((uint)Cell[KA_TARGET].flags & KF_SELECTED) != 0u;
    for (uint tc = 0u; tc < KA_MAX_ARMS && !targetHasClient; tc++)
    {
        if (Cell[KA_ARM_0 + tc].active < 0.5) continue;
        if (Rally[KA_ARM_0 + tc].role == KA_ROLE_NONE) targetHasClient = true;
    }
    if (targetHasClient)
    {
        KaRec t = Cell[KA_TARGET];
        float3 tp = ka_targetPos(t);
        float2 sp; float vz;
        if (projectPt(tp, res, sp, vz))
        {
            float vis = (vz < sceneZ + 0.15) ? 1.0 : 0.25;
            float3 tc = (((uint)t.flags & KF_SELECTED) != 0u) ? PT_ACCENT : PT_INK;
            float m = ringAA(P, sp, 9.0, 1.0);
            m = max(m, discAA(P, sp, 2.2));
            m = max(m, strokeAA(segD(P, sp - float2(16, 0), sp - float2(11, 0)), 0.9));
            m = max(m, strokeAA(segD(P, sp + float2(11, 0), sp + float2(16, 0)), 0.9));
            m = max(m, strokeAA(segD(P, sp - float2(0, 16), sp - float2(0, 11)), 0.9));
            m = max(m, strokeAA(segD(P, sp + float2(0, 11), sp + float2(0, 16)), 0.9));
            col = lerp(col, tc, m * vis);
            // plumb line to the floor, so the mark has a place rather than floating
            float2 sf; float vf;
            if (projectPt(float3(tp.x, 0.0, tp.z), res, sf, vf))
                col = lerp(col, PT_RULE * 1.2,
                           strokeAA(segD(P, sp, sf), 0.5) * step(frac(P.y * 0.11), 0.5) * vis * 0.8);
        }
    }

    // ---- readout ----
    {
        float h = 11.0, y = 12.0, x = 16.0;
        float ink = txtAt(P, float2(x, y), h, uint2(mf_pack1(LK, LU, LK, LA, 0u), 0u), 4u);
        ink = max(ink, txtAt(P, float2(x + txtW(h, 5u), y), h, uint2(mf_pack1(LC, LE, LL, LL, 0u), 0u), 4u));
        col = lerp(col, PT_INK, ink);

        float rx = res.x - 16.0;
        float g = 0.0;
        rx -= txtW(h, 3u); g = max(g, numAt(P, float2(rx, y), h, alarmN, 2u));
        rx -= txtW(h, 6u); g = max(g, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LA, LL, LA, LR, LM), 0u), 5u));
        col = lerp(col, (alarmN > 0u) ? PT_ALARM : PT_DIM, g);
        float g2 = 0.0;
        rx -= txtW(h, 3u); g2 = max(g2, numAt(P, float2(rx, y), h, liveN, 2u));
        rx -= txtW(h, 5u); g2 = max(g2, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LA, LR, LM, LS, 0u), 0u), 4u));
        col = lerp(col, PT_DIM, g2);

        // the rally count is the score, so it goes on the image
        KaBall bh2 = Rally[KA_HEADER];
        if (bh2.role != KA_PLAY_IDLE)
        {
            float g4 = 0.0;
            rx -= txtW(h, 4u); g4 = max(g4, numAt(P, float2(rx, y), h, (uint)bh2.rallyCount, 3u));
            rx -= txtW(h, 6u); g4 = max(g4, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LR, LA, LL, LL, LY), 0u), 5u));
            col = lerp(col, (bh2.dropFlag > 0.5) ? PT_ALARM : PT_ACCENT, g4);
        }

        // camera station, so a composed pose can be read off the image and typed back in
        float h2 = 9.0, by = res.y - 20.0;
        col = lerp(col, PT_DIM, txtAt(P, float2(16.0, by), h2, uint2(mf_pack1(LC, LA, LM, 0u, 0u), 0u), 3u));
        float cx = 16.0 + txtW(h2, 4u);
        col = lerp(col, PT_MID, dec1At(P, float2(cx, by), h2, _CameraPos.x, 3u)); cx += txtW(h2, 7u);
        col = lerp(col, PT_MID, dec1At(P, float2(cx, by), h2, _CameraPos.y, 3u)); cx += txtW(h2, 7u);
        col = lerp(col, PT_MID, dec1At(P, float2(cx, by), h2, _CameraPos.z, 3u));
    }

    // No gamma here. The underlay was already brought all the way to display space before a
    // single mark was drawn, precisely so the marks are laid onto the FINISHED image — a mark
    // composited in linear and then gamma-corrected comes out a different colour than the one
    // that was asked for, which is why a "pure green" arc used to arrive olive.
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
