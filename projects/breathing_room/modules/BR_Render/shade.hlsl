// BR_Render / shade.hlsl -- everything that turns a G-buffer hit into radiance.
//
// Per pixel: evaluate the surface's material pattern, then run ONE job loop whose inner march is
// the only call site of the scene field (compile time is linear in call sites):
//     job 0       sun shadow       -- soft penumbra; once outside, glass x sheer x street trees
//     jobs 1..5   ambient occlusion taps, normalised so reach and strength stay separate
//     job 6       reflection ray   -- varnish, glass, brass, glaze; escapes show the street
//     jobs 7..10  reflection-hit normal taps
//     job 11      sun shadow at the reflection hit
// Diffuse bounce comes from the probe volume; the translucent layer (window glass, sheer
// curtains) is composited last by a short march of the veil field along the view ray.
#include "render_common.hlsli"

StructuredBuffer<float4> SkyLut : register(t1);
StructuredBuffer<ProbeRec> Probes : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float3 probeIrr(float3 x, float3 n)
{
    ProbeGrid g = probeGrid();
    float3 gc = (x + n * 0.12 - g.origin) / g.spacing;
    int3 c0 = clamp((int3)floor(gc), int3(0, 0, 0), g.n - 2);
    float3 f = saturate(gc - (float3)c0);
    float3 sum = 0; float ws = 0;
    [loop] for (int k = 0; k < 8; k++)
    {
        int3 o = int3(k & 1, (k >> 1) & 1, k >> 2);
        int3 c = c0 + o;
        float3 w3 = lerp(1.0 - f, f, (float3)o);
        ProbeRec pr = Probes[probeIndex(g, c)];
        float3 dir = normalize(probePos(g, c) - x + 1e-5);
        float back = saturate(dot(dir, n) * 0.5 + 0.5);
        // an invalid probe (inside a solid) keeps a sliver of weight, so a surface whose every
        // neighbour is invalid is dim, never black
        float w = w3.x * w3.y * w3.z * (saturate(pr.meta.x) * 0.97 + 0.03) * (back * back + 0.05);
        if (!(abs(pr.r.x) < 1e5)) w = 0.0;
        sum += shIrradiance(pr, n) * w; ws += w;
    }
    return (ws > 1e-4) ? sum / ws : 0.0;
}

// Glass x sheer transmittance for a sun ray leaving the room from x (all glazed openings).
float veilTransmit(float3 x, float3 L)
{
    BRRoom R = scRoom();
    float op = sheerOpacity();
    float T = 1.0;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        if (!o.active || !brOpenIsGlazed(o.kind)) continue;
        T *= veilTransmitOpening(x, L, o, R, op);
    }
    return T;
}

// A sun ray that reaches the interior face inside a glazed opening leaves the wall ANALYTICALLY,
// the way fog.hlsl's beams do: it must clear the sashes and muntins where it crosses the frame
// plane and the reveal where it reaches the street face. Marched instead, the 30 cm reveal past
// the sash bars cost ~20 steps; from the far side of the room the 48-step budget ran out and the
// late sun stopped along a ragged, pixel-noisy line across the skirting and the door. Each edge's
// distance also becomes penumbra (k h / t, the same law as the room march). Returns x = -1 when
// the opening is not glazed (keep marching), 0 when the ray is stopped, 1 when it is out, with
// y = its softness; tOut is the distance from xb to the street face.
float2 sunWindowExit(float3 xb, float3 L, float tB, float softK, out float tOut)
{
    BRRoom R = scRoom();
    float2 r = float2(-1.0, 0.0);
    tOut = 0.0;
    bool found = false;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = scOpen(i);
        float3 lq = openLocal(xb, o, R);
        float hw = o.width * 0.5;
        bool here = !found && o.active && abs(lq.z) < 0.02 && abs(lq.x) < hw && lq.y > 0.0 && lq.y < o.height;
        if (here)
        {
            found = true;
            float2 n2 = brWallNormal(o.wall);
            float ln = dot(L, float3(n2.x, 0.0, n2.y));
            if (brOpenIsGlazed(o.kind) && ln < -1e-4)
            {
                float tc = (-R.T + 0.075) / ln;                 // the frame plane
                tOut = -R.T / ln;                               // the street face
                float3 lc = openLocal(xb + L * tc, o, R);
                float3 lo = openLocal(xb + L * tOut, o, R);
                SHit fh = shit(1e9, 0, 0, -1);
                windowFrame(lc, o, R.T, fh, i);
                float eIn = min(hw - abs(lq.x), min(lq.y, o.height - lq.y));
                float eOut = min(hw - abs(lo.x), min(lo.y, o.height - lo.y));
                bool clear = eOut > 0.0 && fh.d > 0.0;
                float soft = softK * min(min(eIn / max(tB, 0.02), eOut / (tB + tOut)), fh.d / (tB + tc));
                r = clear ? float2(1.0, soft) : float2(0.0, 0.0);
            }
            else if (brOpenIsGlazed(o.kind)) r = float2(0.0, 0.0);
        }
    }
    return r;
}

float seedOf(int part, int obj, float3 p)
{
    return frac(sin((float)(part * 131 + obj * 977 + 7) * 12.9898) * 43758.5453);
}

// ---- watercolour, for the framed print ------------------------------------------------------
// A wash laid over c: the pigment's transmission `pig` raised to its density, pooled darker along
// the edge where the wash dried, granulating in the paper's tooth. `wob` scales the wandering of
// the edge (1 for a broad wash, small for a seed-sized dab). aw is the edge's anti-alias width.
float3 wcWash(float3 c, float sd, float3 pig, float amt, float2 p, float seed, float aw, float wob)
{
    float d = sd + wob * (brVN2(p * 70.0 + seed * 7.0) * 0.0030 + brVN2(p * 19.0 + seed * 3.1) * 0.0045);
    float cov = smoothstep(aw, -aw, d);
    float pool = 1.0 + 0.8 * exp(min(d, 0.0) / 0.0055);
    float gran = 1.0 + 0.30 * brVN2(p * 240.0 + seed * 11.0) * saturate(1.5 - aw * 400.0);
    return c * pow(max(pig, 1e-3), max(amt, 0.0) * pool * gran * cov);
}
// a sepia pen line along an outline, lifted where the pen skipped
float3 wcInk(float3 c, float sd, float w, float2 p, float seed, float aw)
{
    float on = smoothstep(-0.25, 0.15, brVN2(p * 22.0 + seed * 5.0));
    float l = smoothstep(w + aw, w - aw * 0.5, abs(sd)) * on;
    return lerp(c, c * brSrgbToLinear(float3(0.36, 0.26, 0.20)), l * 0.85);
}
// the branch: from below the sheet up to the bud at the top right (g_wcSway: the trip sways it)
static float2 g_wcSway = float2(0.0, 0.0);
float2 wcBranch(float t)
{
    float2 P0 = float2(0.14, 1.04), P1 = float2(0.04, 0.50);
    float2 P2 = float2(0.40, 0.17) + g_wcSway * float2(0.6, 0.3), P3 = float2(0.62, 0.05) + g_wcSway;
    float u = 1.0 - t;
    return u * u * u * P0 + 3.0 * u * u * t * P1 + 3.0 * u * t * t * P2 + t * t * t * P3;
}
float wcSeg(float2 p, float2 a, float2 b, float ra, float rb)
{
    float2 ab = b - a, ap = p - a;
    float h = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-8));
    return length(ap - ab * h) - lerp(ra, rb, h);
}

// Wall art. v1: an abstract landscape in oils on canvas. v0 (the framed print): a botanical
// study in watercolour -- a pomegranate branch with a hanging fruit, a cut half lying below and
// a scarlet bud, in washes that pool at their edges over a sepia pen line, on cream paper.
// fpU is the pixel's footprint in picture units: the edges and the paper's grain widen with it,
// so the picture holds still from across the room.
// THE TRIP paints in the picture instead of warping it: live = (trip seconds, sway, growth,
// ripening), live2 = (running paint, swelling). The print's branch sways and its leaves flutter,
// the fruit swells and ripens and fades, the bud opens into petals, and the washes run down the
// paper; the landscape's ridges roll, its sun sinks and rises, its brushwork drifts.
float3 artImage(float2 uv, float seed, int variant, float fpU, float4 live, float2 live2)
{
    float t = live.x, sway = live.y, grow = live.z, ripen = live.w, drip = live2.x, swell = live2.y;
    if (variant == 1)
    {
        // an abstract landscape in oils: a hazy evening sky over three soft ridges, a low sun
        // half behind the nearest, everything dragged sideways by a dry brush
        float3 skyHi = brSrgbToLinear(float3(0.80, 0.70, 0.58)), skyLo = brSrgbToLinear(float3(0.93, 0.74, 0.52));
        float3 sage = brSrgbToLinear(float3(0.55, 0.57, 0.45)), clay = brSrgbToLinear(float3(0.62, 0.42, 0.31));
        float3 deep = brSrgbToLinear(float3(0.30, 0.27, 0.24)), sunC = brSrgbToLinear(float3(0.98, 0.88, 0.70));
        // the paint runs: each column of the canvas read from a little higher up
        float y = uv.y - drip * 0.03 * (0.5 + 0.5 * brVN2(float2(uv.x * 8.0, 1.7))) * (0.6 + 0.4 * sin(t * 0.4 + uv.x * 4.0));
        float3 c = lerp(skyHi, skyLo, smoothstep(0.05, 0.55, y));
        float2 sp = float2(uv.x, y) - float2(0.34, 0.50 + 0.07 * grow * sin(t * 0.12));
        c = lerp(c, sunC, smoothstep(0.075, 0.060, length(sp * float2(1.0, 0.78))));
        float r1 = 0.53 + 0.05 * sin(uv.x * 5.0 + seed * 4.0) + 0.03 * brFbm2(float2(uv.x * 6.0, seed), 3, 0.0) + 0.025 * sway * sin(t * 0.50 + uv.x * 4.0);
        float r2 = 0.64 + 0.06 * sin(uv.x * 3.3 + 1.7 + seed * 2.0) + 0.03 * brFbm2(float2(uv.x * 7.0, seed + 3.0), 3, 0.0) + 0.030 * sway * sin(t * 0.37 + uv.x * 3.0 + 1.0);
        float r3 = 0.78 + 0.04 * sin(uv.x * 2.1 + 0.4) + 0.025 * brFbm2(float2(uv.x * 9.0, seed + 6.0), 3, 0.0) + 0.020 * sway * sin(t * 0.29 + uv.x * 5.0 + 2.0);
        c = lerp(c, sage, smoothstep(r1 - 0.004, r1 + 0.004, y));
        c = lerp(c, clay, smoothstep(r2 - 0.004, r2 + 0.004, y));
        c = lerp(c, deep, smoothstep(r3 - 0.004, r3 + 0.004, y));
        float drag = brVN2(float2(uv.x * 3.0 + t * 0.03 * sway, y * 70.0) + seed * 5.0) * 0.5 + 0.5;
        float bristle = brVN2(float2(uv.x * 60.0, y * 140.0) + seed) * 0.5 + 0.5;
        c *= 0.88 + 0.16 * drag + 0.06 * bristle;
        return c;
    }
    // the sheet is 0.70 wide by 1 tall in p (the mat's window); y runs down
    float aw = max(0.0010, fpU * 0.7);
    float2 p0 = float2(uv.x * 0.70, uv.y);
    float3 c = brSrgbToLinear(float3(0.955, 0.932, 0.872));
    c *= 1.0 + 0.022 * brVN2(p0 * 140.0 + seed * 3.0) * saturate(1.5 - aw * 300.0);
    // the paint runs (melt): the washes are read from a little higher up, in columns that each
    // run their own length; the paper itself stays put
    // (broad, gentle columns: narrow deep ones sliced the fruit into strips)
    float2 p = p0 - float2(0.0, drip * 0.020 * (0.5 + 0.5 * brVN2(float2(p0.x * 9.0, 4.3))) * (0.6 + 0.4 * sin(t * 0.4 + p0.x * 5.0)));
    // the branch sways (its tip most), the bud opens and closes, the fruit swells
    g_wcSway = sway * 0.025 * float2(sin(t * 0.6), 0.5 * sin(t * 0.6 + 0.8));
    float open = grow * (0.5 + 0.5 * sin(t * 0.25));
    float ripe = ripen * (0.5 + 0.5 * sin(t * 0.18));

    // leaves first: the fruit is painted over them. A sage wash, a darker glaze on the half
    // turned from the light, the midrib left pale, a pen outline.
    // (ripening turns the leaves toward autumn gold and back)
    float3 sage = lerp(brSrgbToLinear(float3(0.66, 0.74, 0.50)), brSrgbToLinear(float3(0.80, 0.70, 0.40)), ripe * 0.6);
    float3 olive = lerp(brSrgbToLinear(float3(0.42, 0.52, 0.30)), brSrgbToLinear(float3(0.62, 0.45, 0.22)), ripe * 0.6);
    [loop] for (int i = 0; i < 13; i++)
    {
        float tb = 0.06 + 0.07 * (float)i + 0.015 * frac(seed * 3.1 + (float)i * 0.37);
        float side = ((i & 1) == 0) ? 1.0 : -1.0;
        float2 b = wcBranch(tb);
        float2 tg = normalize(wcBranch(tb + 0.01) - wcBranch(tb - 0.01));
        // each leaf flutters on its own phase as the branch sways
        float2 dir = rot2(normalize(float2(-tg.y, tg.x) * side * 0.8 + tg * 0.6), sway * 0.22 * sin(t * 1.1 + (float)i * 0.9));
        float2 prp = float2(-dir.y, dir.x);
        float len = 0.10 + 0.055 * frac((float)i * 0.618 + seed * 1.7);
        float2 lp = p - b;
        float al = dot(lp, dir);
        float ac = dot(lp, prp) - 0.9 * al * al * side;
        float sd = plVesica(float2(ac, al - len * 0.5), len * 0.5, len * 0.22);
        c = wcWash(c, sd, sage, 0.9, p, seed + (float)i, aw, 1.0);
        c = wcWash(c, max(sd, 0.0015 - ac * side), olive, 0.8, p, seed + (float)i + 0.5, aw, 0.6);
        c = wcInk(c, sd, 0.0007, p, seed + (float)i, aw);
    }

    // the branch, tapering to the bud, and the twig the fruit hangs from
    float br = 1e9;
    float2 prev = wcBranch(0.0);
    [loop] for (int k = 1; k <= 12; k++)
    {
        float2 cur = wcBranch((float)k / 12.0);
        br = min(br, wcSeg(p, prev, cur, lerp(0.0105, 0.0032, (float)(k - 1) / 12.0), lerp(0.0105, 0.0032, (float)k / 12.0)));
        prev = cur;
    }
    br = min(br, wcSeg(p, wcBranch(0.40), float2(0.315, 0.545), 0.006, 0.0045));
    br = min(br, wcSeg(p, wcBranch(0.70), float2(0.455, 0.255), 0.0045, 0.0035));
    c = wcWash(c, br, brSrgbToLinear(float3(0.62, 0.48, 0.36)), 1.3, p, seed + 20.0, aw, 0.4);
    c = wcInk(c, br, 0.0008, p, seed + 21.0, aw);

    // a young fruit higher up, still green-gold blushing rose
    // (it grows as the bud opens, and blushes as it ripens)
    float2 cY = float2(0.482, 0.300) + g_wcSway * 0.7;
    float rY = 0.050 * (1.0 + 0.25 * open);
    float2 dY = p - cY;
    float sdY = length(dY) - rY;
    float2 nY = dY / rY;
    c = wcWash(c, sdY, brSrgbToLinear(float3(0.86, 0.80, 0.52)), 1.0, p, seed + 25.0, aw, 0.7);
    c = wcWash(c, sdY, brSrgbToLinear(float3(0.86, 0.42, 0.32)), (0.9 + 0.9 * ripe) * smoothstep(-0.3, 0.9, dot(nY, float2(0.6, 0.8)) + ripe * 0.6), p, seed + 26.0, aw, 0.5);
    float2 cy1 = cY + normalize(float2(0.45, 0.89)) * (rY + 0.014);
    float crY = min(wcSeg(p, cY + normalize(float2(0.45, 0.89)) * rY * 0.84, cy1, 0.007, 0.0055), length(p - cy1) - 0.0045);
    c = wcWash(c, crY, brSrgbToLinear(float3(0.62, 0.30, 0.20)), 1.1, p, seed + 27.0, aw, 0.2);
    c = wcInk(c, min(sdY, crY), 0.0007, p, seed + 28.0, aw);

    // the hanging fruit: a rose-ochre underwash, crimson glazed in toward the shadowed lower
    // right, a highlight left as bare paper, and the crown
    // (it swells with the breathing, and its crimson deepens and fades as it ripens)
    float2 cA = float2(0.37, 0.675) + g_wcSway * 0.4;
    float rA = 0.13 * (1.0 + 0.05 * swell * sin(t * 0.55));
    float2 dA = p - cA;
    float aA = (dot(dA, dA) > 1e-10) ? atan2(dA.y, dA.x) : 0.0;
    float sdA = length(dA) - rA * (1.0 + 0.022 * cos(aA * 5.0 + 0.6 + seed));
    float2 cd = normalize(float2(0.55, 0.83)), cx = float2(-cd.y, cd.x);
    float2 c1 = cA + cd * (rA + 0.032);
    float crown = wcSeg(p, cA + cd * rA * 0.86, c1, 0.012, 0.009);
    crown = min(crown, min(min(length(p - c1 - cx * 0.011), length(p - c1 + cx * 0.011)), length(p - c1 - cd * 0.004)) - 0.006);
    float body = min(sdA, crown);
    float2 nA = dA / rA;
    float lit = saturate(dot(nA, float2(-0.6, -0.8)) * 0.5 + 0.5);
    float hl = smoothstep(0.42, 0.12, length(nA - float2(-0.36, -0.40)));
    c = wcWash(c, body, brSrgbToLinear(float3(0.95, 0.66, 0.50)), 1.0 - hl * 0.85, p, seed + 30.0, aw, 1.0);
    c = wcWash(c, sdA, brSrgbToLinear(float3(0.80, 0.22, 0.20)), lerp(1.6, 0.35, lit) * (1.0 - hl) * (1.0 + 0.8 * ripe - 0.4 * ripen), p, seed + 31.0, aw, 0.7);
    // the core shadow, graded across the fruit rather than cut
    c = wcWash(c, sdA, brSrgbToLinear(float3(0.55, 0.12, 0.16)), 1.0 * smoothstep(0.05, 0.95, dot(nA, float2(0.6, 0.8))), p, seed + 32.0, aw, 1.0);
    c = wcWash(c, crown, brSrgbToLinear(float3(0.62, 0.20, 0.18)), 1.2, p, seed + 33.0, aw, 0.3);
    c = wcInk(c, body, 0.0008, p, seed + 34.0, aw);

    // the cut half lying below: a rind ring, pale membranes in six chambers, and the arils
    // packed into them, each with a glint
    float2 cB = float2(0.548, 0.868);
    float rB = 0.096;
    float2 dB = p - cB;
    float lB = length(dB);
    float aB = (dot(dB, dB) > 1e-10) ? atan2(dB.y, dB.x) : 0.0;
    float wav = 1.0 + 0.02 * cos(aB * 6.0 + 1.3);
    float sdB = lB - rB * wav;
    float sdI = lB - (rB - 0.014) * wav;
    c = wcWash(c, max(sdB, -sdI), brSrgbToLinear(float3(0.86, 0.36, 0.30)), 1.2, p, seed + 40.0, aw, 0.5);
    c = wcWash(c, sdI, brSrgbToLinear(float3(0.97, 0.88, 0.66)), 0.7, p, seed + 41.0, aw, 0.3);
    // the membranes wander (a pomegranate's chambers are irregular; straight spokes read as an
    // orange), and the arils are big, glossy and packed
    float2 dBw = rot2(dB, 0.35 * sin(lB * 55.0 + seed * 3.0));
    float sept = 1e9;
    [unroll] for (int s6 = 0; s6 < 5; s6++)
    {
        float a6 = (float)s6 * 1.2566 + 0.4 + 0.25 * sin((float)s6 * 2.1 + seed);
        float2 dv = float2(cos(a6), sin(a6));
        sept = min(sept, (dot(dBw, dv) > 0.0) ? abs(dBw.x * dv.y - dBw.y * dv.x) : lB);
    }
    float cellA = 0.0150;
    float2 g = rot2(dB, 0.3) / cellA;
    float2 gi = floor(g);
    float2 f = frac(g) - 0.5 - (float2(brH21(gi), brH21(gi + 17.0)) - 0.5) * 0.18;
    float aril = (length(f * float2(1.0, 1.15)) - 0.42) * cellA;
    aril = max(aril, max(sdI + 0.004, max(0.0050 - sept, 0.010 - lB)));
    float glint = smoothstep(0.16, 0.06, length(f - float2(-0.14, -0.17)));
    c = wcWash(c, aril, brSrgbToLinear(float3(0.80, 0.14, 0.22)), 1.25 * (1.0 - glint * 0.9), p, seed + 42.0, aw, 0.08);
    c = wcInk(c, sdB, 0.0008, p, seed + 43.0, aw);

    // the bud at the tip of the branch: a scarlet urn, deeper red toward its open lobes
    float2 b0 = wcBranch(0.985);
    float2 bd = normalize(float2(0.25, 1.0)), bx = float2(-bd.y, bd.x);
    float2 lq = float2(dot(p - b0, bx), dot(p - b0, bd));
    float bud = plUnevenCapsule(lq, 0.0045, 0.0125, 0.06);
    // its lobes part as it opens, and scarlet petals unfold out of it
    float sp2 = 0.010 + 0.012 * open;
    bud = min(bud, min(min(length(lq - float2(sp2, 0.072)), length(lq - float2(-sp2, 0.072))), length(lq - float2(0.0, 0.079 + 0.006 * open))) - 0.0055);
    // three petals unfold from the bud's mouth, each an ellipse rooted in it
    float pet = 1e9;
    [unroll] for (int pk = -1; pk <= 1; pk++)
    {
        float pa = (float)pk * (0.45 + 0.35 * open);
        float2 pdir = float2(sin(pa), cos(pa));
        float2 pq = lq - float2(0.0, 0.070) - pdir * (0.008 + 0.010 * open);
        float2 pl = float2(dot(pq, float2(pdir.y, -pdir.x)), dot(pq, pdir));
        pet = min(pet, length(pl / float2(0.006 + 0.004 * open, 0.010 + 0.012 * open)) - 1.0);
    }
    bud = min(bud, (open > 0.02) ? pet * 0.006 : 1e9);
    c = wcWash(c, bud, brSrgbToLinear(float3(0.96, 0.45, 0.25)), 1.2, p, seed + 50.0, aw, 0.3);
    c = wcWash(c, max(bud, 0.035 - lq.y), brSrgbToLinear(float3(0.80, 0.16, 0.12)), 1.0, p, seed + 51.0, aw, 0.3);
    c = wcInk(c, bud, 0.0007, p, seed + 52.0, aw);

    // a pencilled caption along the foot of the sheet
    float cap = abs(p0.y - 0.972 - 0.0022 * sin(p0.x * 620.0 + seed * 9.0)) - 0.0005;
    float words = step(0.0, sin(p0.x * 95.0 + 1.3)) * step(0.045, p0.x) * step(p0.x, 0.215);
    c = lerp(c, c * 0.78, smoothstep(aw, -aw, cap) * words * 0.6 * saturate(1.5 - aw * 600.0));
    return c;
}

// A leaf in its own frame: uv.x across (-1 .. 1), uv.y base to tip, up = +1 on the upper side.
// The finish board's leaf colour (m.base) is the mature leaf, its second tone (m.second) the young.
BRSurf plantLeafSurface(BRSurf s, BRMat m, int v, float2 uv, float up, float seed)
{
    float ax = abs(uv.x);
    if (v == 1)
    {
        // snake plant: dark green crossed by pale grey-green zigzag bands, a gold margin
        float t = uv.y;
        float zig = abs(frac(uv.x * 1.6 + 0.5) - 0.5) * 0.12;
        float band = frac(t * 15.0 + zig + brVN3(float3(uv.x * 2.0, t * 7.0, seed * 9.0)) * 0.10);
        float pale = smoothstep(0.30, 0.42, band) * smoothstep(0.82, 0.70, band);
        float3 dark = m.base * float3(0.42, 0.58, 0.44);
        float3 light = lerp(m.base, brSrgbToLinear(float3(0.58, 0.66, 0.52)), 0.6);
        float3 c = lerp(dark, light, pale * 0.85);
        c = lerp(c, brSrgbToLinear(float3(0.84, 0.76, 0.34)), smoothstep(0.80, 0.93, ax));
        s.albedo = c;
        s.rough = 0.36; s.coat = 0.3; s.coatRough = 0.28;
        return s;
    }
    if (v == 2)
    {
        // olive: grey-green above, silver beneath, a pale midrib
        float3 top = lerp(m.base, brSrgbToLinear(float3(0.45, 0.50, 0.38)), 0.55);
        float3 under = brSrgbToLinear(float3(0.70, 0.72, 0.64));
        float3 c = (up > 0.0) ? top : under;
        c = lerp(c, c * 1.3, smoothstep(0.12, 0.0, ax) * 0.6);
        s.albedo = c; s.rough = (up > 0.0) ? 0.45 : 0.75; s.sheen = (up > 0.0) ? 0.0 : 0.3;
        return s;
    }
    // fiddle-leaf fig: deep glossy green, a pale midrib, paired veins arching out toward the
    // margin, the youngest leaves lighter
    float young = saturate(frac(seed * 5.3) * 1.3 - 0.4);
    float3 leaf = lerp(m.base * float3(0.55, 0.80, 0.55), m.second, young * 0.45);
    float vz = uv.y - ax * 0.22 - ax * ax * 0.10;
    float vein = abs(frac(vz * 9.0) - 0.5) * 2.0;
    float vw = lerp(0.10, 0.04, ax);
    float vl = smoothstep(vw, vw * 0.4, vein) * smoothstep(0.92, 0.6, ax) * step(0.06, ax);
    float mid = smoothstep(0.06, 0.02, ax) * step(0.02, uv.y);
    float3 veinC = lerp(leaf, brSrgbToLinear(float3(0.78, 0.80, 0.56)), 0.7);
    float3 c = lerp(leaf, veinC, saturate(vl * 0.55 + mid));
    if (up < 0.0) c = lerp(c, brSrgbToLinear(float3(0.62, 0.70, 0.52)), 0.45);
    s.albedo = c;
    s.rough = (up > 0.0) ? 0.30 : 0.6;
    s.coat = (up > 0.0) ? 0.35 : 0.0; s.coatRough = 0.18;
    return s;
}

// `pS` is p read through the trip's texture swim (= p when the trip is off). Plaster, paint and
// fabrics are evaluated there, so they shimmer in place at the trip's swim scale. Everything with
// an identity of its own gets a trip TAILORED to it instead of being dragged by the swim:
//   the parquet crawls along its columns, its grain streaming along each slat, a tone chasing it
//   the rug's ornament comes alive (br_rug.hlsli: blooming, orbiting, a travelling border)
//   wood grain flows along each board
//   the pictures paint themselves (artImage: swaying, ripening, opening, running)
BRSurf surfaceAt(GSample g, float3 p, float3 pS, float3 n, float fp, out BRMat m)
{
    m = scMat(g.mat);
    BRPatternIn pin;
    pin.p = pS; pin.n = n; pin.axis = float3(0, 1, 0); pin.fp = fp;
    pin.seed = seedOf(g.part, g.obj, p); pin.edge = 1.0;
    BRRoom R = scRoom();
    // the trip's amounts for the tailored effects (travel and turning read the integrated clocks)
    BRTrip Tt = tripHeader();
    float tAmp = tripAmp(Tt);
    float tFlow = Tt.drift * Tt.dose * tAmp;
    float tGeom = Tt.geometry * Tt.dose * tAmp;
    // ---- furniture: patterns live in the piece's own frame, so they travel with it
    if (g.obj >= 0 && g.part >= PART_FURN)
    {
        BRRec o = SceneBuf[SC_OBJ0 + clamp(g.obj, 0, SC_OBJ_MAX - 1)];
        int kind = (int)(o.head.x + 0.5), var = (int)(o.head.y + 0.5);
        bool lit = (objFlags(o) & FF_LIT) != 0;
        int lp = g.part - PART_FURN;
        // the rug, the pictures and wood are read where they really are (their own trip comes
        // below); fabrics and the rest through the swim
        bool own = kind == FK_RUG || kind == FK_ART || m.family == FAM_WOOD;
        float3 q = objLocal(o, own ? p : pS);
        // a warped piece wears its texture in its REST frame, so the fabric rides the swell
        BRRec wr = SceneBuf[SC_OWARP0 + clamp(g.obj, 0, SC_OBJ_MAX - 1)];
        if (wr.head.x + wr.head.w + abs(wr.dims.x) > 0.0)
        {
            float Lw;
            q = tripObjectApply(q, o.look.xyz, o.look.w, wr.head, wr.dims.x, wr.dims.z, TRIP_REC(TRIP_HEADER).meta.x, Lw);
        }
        float yaw = o.dims.z;
        float3 rW = float3(cos(yaw), 0.0, -sin(yaw));
        float oseed = o.look.w;
        pin.p = q + oseed * float3(17.1, 3.7, 9.3);
        pin.axis = (lp == FP_LEG) ? float3(0, 1, 0) : rW;
        // wood: the grain flows along the board (each piece its own way), never twists
        if (m.family == FAM_WOOD) pin.p += pin.axis * (Tt.flowT * 0.012 * ((frac(oseed * 7.7) > 0.5) ? 1.0 : -1.0));
        pin.seed = frac(oseed * 13.7 + (float)lp * 0.173);
        if (lp >= FP_BOOK) pin.seed = frac((float)(lp - FP_BOOK) * 0.1373 + oseed * 7.1) * 0.998 + 0.001;
        if (kind == FK_RUG)
        {
            BRRugDesign RD = rugFromRecs();
            // the ornament comes alive (br_rug.hlsli); a little of the swim stays, at its scale
            RD.time = Tt.time; RD.flow = tFlow; RD.bloom = tGeom; RD.hue = Tt.colour * Tt.dose;
            RD.flowT = Tt.flowT; RD.bloomT = Tt.bloomT;
            float2 rq = lerp(q.xz, objLocal(o, pS).xz, 0.25);
            float pile;
            float3 rc = rugDesign(rq, o.look.xz * 0.5, RD, fp, pile);
            if (lp == FP_FRINGE) rc = RD.ivory * 0.92;
            BRSurf rs = brEvalSurface(m, pin, rc, true);
            rs.cavity *= lerp(0.72, 1.0, pile);
            rs.sheen *= lerp(0.5, 1.0, pile);
            return rs;
        }
        BRSurf s = brEvalSurface(m, pin, m.base, false);
        if (lp == FP_IMAGE)
        {
            float3 S = o.look.xyz;
            // u runs to the viewer's right, which is the piece's local -x (the camera is
            // left-handed: facing the wall, +x is on the left, and the print read mirrored)
            float2 uv = float2(0.5 - q.x / max(S.x, 0.05), 1.0 - q.y / max(S.y, 0.05));
            float fpU = fp / max(S.y, 0.05);
            if (var == 0)
            {
                // the print fills the mat's window
                float a, yb, yt;
                artWindow(S, a, yb, yt);
                uv = float2(0.5 - q.x / (2.0 * a), (yt - q.y) / (yt - yb));
                fpU = fp / (yt - yb);
            }
            // the picture paints itself (artImage): sway (drift), growth (geometry), ripening
            // (colour), running paint (melt), swelling (breathe)
            float4 live = float4(Tt.time, tFlow, min(tGeom, 1.5), Tt.colour * Tt.dose);
            float2 live2 = float2(min(Tt.melt * Tt.dose * tAmp, 2.0), Tt.breathe * Tt.dose * tAmp);
            s.albedo = artImage(saturate(uv), oseed, var, fpU, live, live2);
            s.rough = (var == 1) ? 0.72 : 0.85; s.metal = 0.0; s.f0 = 0.04; s.sheen = 0.0; s.bump = 0;
            // the print is glazed: a faint, sharp reflection of the room over it
            s.coat = (var == 1) ? 0.15 : 0.3; s.coatRough = (var == 1) ? 0.25 : 0.03;
        }
        else if (lp == FP_MAT)
        {
            // cream board under the same glass; the bevel cut shows its bright white core
            float cy = cos(o.dims.z), sy = sin(o.dims.z);
            float nz = n.x * sy + n.z * cy;
            float bevel = smoothstep(0.92, 0.80, nz);
            s.albedo = lerp(brSrgbToLinear(float3(0.92, 0.90, 0.84)), brSrgbToLinear(float3(0.985, 0.98, 0.96)), bevel);
            s.rough = 0.9; s.metal = 0.0; s.f0 = 0.04; s.sheen = 0.0; s.bump = 0;
            s.coat = 0.3 * (1.0 - bevel); s.coatRough = 0.03;
        }
        else if (lp == FP_MIRROR)
        {
            s.albedo = float3(0.92, 0.92, 0.90); s.f0 = float3(0.92, 0.92, 0.90); s.metal = 1.0;
            s.rough = 0.025; s.coat = 0.0; s.sheen = 0.0; s.bump = 0;
        }
        else if (lp == FP_BULB || lp == FP_SHADE)
        {
            // bulb and shade glow in the light BR_Light gave this lamp: its colour and its dimmer
            int li = lit ? lampOfObj(g.obj) : -1;
            float3 Lc = 0;
            if (li >= 0) Lc = SceneBuf[SC_LAMP0 + li].look.rgb * SceneBuf[SC_LAMP0 + li].dims.w;
            if (lp == FP_BULB)
            {
                if (li < 0) { s.emit = 0; s.albedo = 0.8; s.rough = 0.1; s.f0 = 0.04; }
                else s.emit = Lc * 9.0;
            }
            else s.emit = s.albedo * Lc * 2.6 * (0.6 + 0.4 * saturate(m.trans * 1.5));
        }
        else if (kind == FK_PLANT && lp >= FP_BOOK)
        {
            // a leaf, shaded in its own frame (br_plants.hlsli rebuilds it from the part id)
            float cy = cos(o.dims.z), sy = sin(o.dims.z);
            float3 nL = float3(n.x * cy - n.z * sy, n.y, n.x * sy + n.z * cy);
            float2 lu; float up;
            if (plantLeafCoords(var, o.look.xyz, oseed, scPlantAnim(), lp - FP_BOOK, q, nL, lu, up))
                s = plantLeafSurface(s, m, var, lu, up, pin.seed);
        }
        else if (kind == FK_SHELF && lp == FP_BACK)
        {
            // the bookcase's back board: matte, darker for the books' shade (a varnished back
            // mirrored the room, blocky, between the rows)
            s.coat = 0.0; s.rough = max(s.rough, 0.62); s.albedo *= 0.8;
        }
        else if (kind == FK_SHELF && lp >= FP_BOOK)
        {
            // THE TRIP: the spines ripple along each shelf like keys under a hand -- a slow wave
            // of brightness running along the rows (geometry)
            s.albedo *= 1.0 + 0.22 * tGeom * sin(6.2831853 * (q.x / 0.45 + q.y * 0.8 - Tt.time * 0.22));
        }
        else if (kind == FK_VASE && lp >= FP_BOOK)
        {
            // eucalyptus: glaucous blue-green under a waxy bloom, each coin its own tone
            float tone = frac(pin.seed * 7.3);
            s.albedo = lerp(brSrgbToLinear(float3(0.47, 0.58, 0.54)), brSrgbToLinear(float3(0.63, 0.69, 0.60)), tone)
                     * (0.9 + 0.1 * brVN3(q * 90.0 + oseed * 7.0));
            s.rough = 0.62; s.sheen = 0.3; s.sheenTint = float3(0.8, 0.88, 0.86); s.coat = 0.0; s.metal = 0.0;
        }
        else if (kind == FK_LOGS && lp == FP_BODY)
        {
            // charred toward the grate, and glowing in the cracks where the fire is hottest
            int fl = scFireLamp();
            // charred all over, darkest low down; embers glow in the checking cracks and on the
            // undersides that face the coal bed, never as a uniform skin
            float low = smoothstep(0.14, 0.02, q.y);
            s.albedo *= lerp(0.45, 0.12, low);
            s.rough = 0.95;
            if (fl >= 0)
            {
                BRRec fr = SceneBuf[SC_LAMP0 + fl];
                float2 cc = brCell2(float2(q.x * 22.0 + q.z * 7.0, q.y * 34.0 + q.z * 19.0));
                float crack = 1.0 - smoothstep(0.0, 0.025 + fp * 12.0, cc.y - cc.x);
                // only some of the bark has burnt through: patches, not a net
                float patch = smoothstep(0.15, 0.55, brVN3(q * 7.0 + oseed * 13.0));
                float under = saturate(-n.y * 1.5) * smoothstep(0.10, 0.03, q.y);
                float t = scFrameB().w;
                float breathe = 0.6 + 0.4 * brVN3(q * 9.0 + float3(0.0, t * 0.7, t * 0.4));
                float glow = (crack * patch * smoothstep(0.16, 0.05, q.y) + under * 0.6) * breathe;
                s.emit = brKelvin(1100.0) * glow * fr.dims.w * 2.4;
            }
        }
        return s;
    }
    float floorChase = 0.0;
    if (g.part == PART_FLOOR)
    {
        // THE TRIP: the parquet crawls slowly along its columns (world z: the herringbone's V
        // columns), rigidly, so every slat stays whole; the grain streams along each slat, the two
        // directions of slat streaming opposite ways; and a wave of tone chases up the columns
        float2 fxz = p.xz + float2(0.0, Tt.flowT * 0.022);
        BRSlat sl = brFloorSlat(fxz, R.floorPattern, R.plankW);
        pin.seed = frac((float)(sl.id & 0xFFFFFFu) / 16777216.0 + 0.137);
        float3 g3 = float3(sl.grainDir.x, 0.0, sl.grainDir.y);
        float gs = (sl.grainDir.x * sl.grainDir.y >= 0.0) ? 1.0 : -1.0;
        pin.p = float3(fxz.x, 0.0, fxz.y) + float3(pin.seed * 37.1, pin.seed * 5.3, pin.seed * 23.9) + g3 * (Tt.flowT * 0.015 * gs);
        pin.axis = g3;
        pin.edge = sl.edge;
        floorChase = 0.13 * tGeom * sin(6.2831853 * (sl.centre.y / 0.55 + sl.centre.x * 0.35 - Tt.time * 0.18));
    }
    else if (g.part == PART_SURROUND || g.part == PART_MANTEL || g.part == PART_HEARTH)
    {
        pin.seed = 0.3;
    }
    BRSurf s = brEvalSurface(m, pin, m.base, false);
    s.albedo *= 1.0 + floorChase;
    if (g.part == PART_FIREBOX)
    {
        // firebrick in running bond, blackened by soot toward the throat
        float3 an = abs(n);
        float2 uv = (an.y > 0.7) ? p.xz : ((an.x > an.z) ? p.zy : p.xy);
        float bh = 0.070, bw = 0.235;
        float row = floor(uv.y / bh);
        float bx = uv.x / bw + row * 0.5;
        float2 f = float2(frac(bx) * bw, frac(uv.y / bh) * bh);
        float edge = min(min(f.x, bw - f.x), min(f.y, bh - f.y));
        float mortar = 1.0 - smoothstep(0.003, 0.006 + fp, edge);
        float bid = frac(sin(dot(float2(floor(bx), row), float2(12.9898, 78.233))) * 43758.5453);
        float3 brick = brSrgbToLinear(float3(0.62, 0.46, 0.33)) * (0.7 + 0.45 * bid);
        float3 mort = brSrgbToLinear(float3(0.55, 0.52, 0.48));
        float soot = saturate(0.25 + p.y * 0.9 + brFbm3(p * 7.0, 3, fp * 7.0) * 0.35);
        s.albedo = lerp(lerp(brick, mort, mortar), float3(0.012, 0.010, 0.009), soot);
        s.rough = 0.92; s.metal = 0.0; s.f0 = 0.035; s.coat = 0.0; s.sheen = 0.0;
        s.cavity = 1.0 - mortar * 0.5;
        // the coal bed: ash and embers on the firebox floor under the grate
        int fl = scFireLamp();
        if (fl >= 0 && an.y > 0.7 && p.y < 0.06)
        {
            BRRec fr = SceneBuf[SC_LAMP0 + fl];
            float2 rq = float2(dot(p.xz - fr.dims.xz, float2(fr.meta.y, -fr.meta.x)), dot(p.xz - fr.dims.xz, fr.meta.xy));
            float bed = saturate(1.0 - length(rq / float2(0.30, 0.13)));
            float t = scFrameB().w;
            float2 cc = brCell2(p.xz * 55.0);
            float coal = smoothstep(0.02, 0.10, cc.y - cc.x);
            float pulse = 0.6 + 0.4 * brVN3(float3(p.xz * 14.0, t * 0.9));
            s.albedo = lerp(s.albedo, float3(0.05, 0.045, 0.04), bed);
            s.emit = brKelvin(1100.0) * bed * bed * coal * pulse * fr.dims.w * 3.0;
        }
    }
    return s;
}

// Normal of a veil hit without re-sampling the field: glass is the wall's own plane, a sheer is
// that plane tilted by the slope of its folds (the same fold function veilMap uses).
float3 veilNormal(float3 x, SHit vh)
{
    BRRoom R = scRoom();
    int i = clamp(-1 - vh.obj, 0, SHELL_OPEN_MAX - 1);
    BROpening o = scOpen(i);
    float2 n2 = brWallNormal(o.wall);
    float3 n3 = float3(n2.x, 0.0, n2.y);
    if (vh.mat == MAT_GLASS) return n3;
    float3 lq = openLocal(x, o, R);
    float hw = o.width * 0.5, ext = hw + 0.36;
    bool left = lq.x < 0.0;
    float x0 = left ? -ext : hw - 0.22, x1 = left ? -hw + 0.22 : ext;
    float seed = left ? (float)i : (float)i + 0.5;
    float k = 2.0 * 3.14159265 / max((x1 - x0) / 7.0, 0.02);
    float slope = 0.028 * k * cos(lq.x * k + seed * 3.0);
    float3 along = brWallAlongX(o.wall) ? float3(1, 0, 0) : float3(0, 0, 1);
    return normalize(n3 - along * slope);
}

float hash2(float2 p, float f) { return frac(sin(dot(p, float2(12.9898, 78.233)) + f * 0.6180339) * 43758.5453); }

// ---------------------------------------------------------------------------------------------
// THE FIRE: an emissive volume over the logs, marched only by rays that cross the firebox. At
// this scale flames are emission alone; their colour is the black body of their temperature,
// yellow-white in the cores and cooling to deep orange at the ragged tips.
float flameDensity(float3 lq, float fbw, float dep, float time, float flick)
{
    float y = lq.y - 0.08;                                    // out of the log pile
    if (y < -0.04) return 0.0;
    float zc = lq.z - (dep - 0.21);
    // turbulence carried UP the flame: the whole field is displaced by noise that rises
    float3 np = float3(lq.x * 6.0, y * 4.0 - time * 3.0, zc * 6.0);
    float n1 = brVN3(np), n2 = brVN3(np * 2.13 + float3(5.1, -time * 2.2, 1.7));
    float riseT = saturate(y / 0.5);
    float2 wob = float2(n1, n2) * (0.010 + 0.08 * riseT * riseT);
    // a continuous sheet along the top of the logs that the tongues rise out of
    float inside = 1.0;
    float sheetW = saturate(1.0 - abs(lq.x + wob.x) / (fbw * 0.78)) * saturate(1.0 - abs(zc + wob.y) / 0.13);
    float sheet = sheetW * smoothstep(0.13, 0.0, y) * (0.75 + 0.25 * n1);
    inside *= 1.0 - saturate(sheet);
    // six tongues, each with its own height, width, sway and flicker; merged, not maxed
    [unroll] for (int i = 0; i < 6; i++)
    {
        float fi = (float)i;
        float h1 = frac(sin(fi * 12.9898 + 4.1) * 43758.5453);
        float h2 = frac(sin(fi * 78.233 + 1.3) * 12345.678);
        float x0 = (fi - 2.5) / 2.5 * fbw * 0.62 + (h1 - 0.5) * 0.06;
        float H = (0.24 + 0.26 * h2) * (1.0 + flick * 0.38 * sin(time * (2.3 + h1 * 2.9) + fi * 1.7))
                * (1.0 + 0.25 * sin(time * (6.1 + h2 * 3.0) + fi));
        float w = 0.070 + 0.045 * h1;
        float sway = sin(time * (1.3 + h2) + fi * 2.3) * 0.04 * flick;
        float t = saturate(y / max(H, 0.05));
        float cx = x0 + sway * t * t;
        float2 q = float2(lq.x + wob.x - cx, zc + wob.y);
        float width = w * pow(saturate(1.0 - t), 0.6) + 0.004;
        float body = saturate(1.0 - length(q / float2(width, width * 1.3)));
        body *= smoothstep(1.0, 0.5, t);
        inside *= 1.0 - body;
    }
    float d = 1.0 - inside;
    // ragged, licking tips and a hot base
    d *= saturate(0.75 + 0.6 * n2 - riseT * 0.35);
    d *= smoothstep(-0.04, 0.02, y);
    return saturate(d * 1.3);
}

float3 fireFlames(float3 ro, float3 rd, float tEnd, float time, float jit, out float mask)
{
    mask = 0.0;
    int fl = scFireLamp();
    if (fl < 0) return 0;
    BRRec lr = SceneBuf[SC_LAMP0 + fl];
    BRRoom R = scRoom();
    BROpening o = scOpen(clamp((int)(lr.head.z + 0.5), 0, SHELL_OPEN_MAX - 1));
    float fbw = o.cols * 0.5, dep = o.depth;
    // the ray in firebox-local coordinates (openLocal only swaps and signs axes: a rigid map)
    float3 lo = openLocal(ro, o, R);
    float3 ld = openLocal(ro + rd, o, R) - lo;
    float3 bmin = float3(-fbw * 0.85, 0.04, dep - 0.40), bmax = float3(fbw * 0.85, min(o.rows, 0.62), dep - 0.01);
    float3 inv = 1.0 / (abs(ld) > 1e-6 ? ld : float3(1e-6, 1e-6, 1e-6));
    float3 t0 = (bmin - lo) * inv, t1 = (bmax - lo) * inv;
    float tn = max(max(min(t0.x, t1.x), min(t0.y, t1.y)), min(t0.z, t1.z));
    float tf = min(min(max(t0.x, t1.x), max(t0.y, t1.y)), max(t0.z, t1.z));
    tn = max(tn, 0.0); tf = min(tf, tEnd);
    if (tf <= tn) return 0;
    float flick = lr.meta.z;
    const int N = 20;
    float dt = (tf - tn) / (float)N;
    float3 acc = 0;
    [loop] for (int i = 0; i < N; i++)
    {
        float3 q = lo + ld * (tn + ((float)i + jit) * dt);
        float dn = flameDensity(q, fbw, dep, time, flick);
        if (dn <= 0.0) continue;
        // hottest in the cores: yellow-white there, orange through the body, red at the tips
        acc += brKelvin(lerp(1050.0, 2300.0, saturate(dn * 1.15))) * (dn * dn * (0.4 + dn)) * dt;
        mask = max(mask, dn);
    }
    // the flickering power drives the flames as well as the light they throw
    return acc * lr.dims.w * 150.0;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    int2 RR = renderRes(int2(W, H));              // the render region (render_common)
    if ((int)tid.x >= RR.x || (int)tid.y >= RR.y) return;
    float2 res = float2(RR);
    float4 fr = scFrame();
    // The G-buffer this pass is handed was cast a cook ago, by a camera the live one has already
    // left: rebuild its rays from the camera it carries (br_camtexels.hlsli). From the live camera,
    // every surface was lit a frame's motion away from where it was drawn.
    CamHdr gc = camHeader(_Tex3);
    if (!gc.ok) gc = camLive(_ViewProjMatrix, _InvViewProjMatrix, _CameraPos, fr.yz, fr.x);
    // ...and that camera travels on with this image, to the resolve
    if (isCamTexel(int2(tid.xy))) { OutputUAV[tid.xy] = camHeaderTexel(gc, (int)tid.x); return; }
    float3 ro, rd;
    camRay(gc, float2(tid.xy), res, gc.jit.xy, ro, rd);
    // material detail is filtered to the OUTPUT pixel, not the render region's: the resolve
    // accumulates jittered samples back to full resolution, so filtering to the coarser region
    // would blur what it can resolve
    float pa = pixelAngle(float2(W, H));
    GSample g = unpackG(_Tex3.Load(int3(tid.xy, 0)));
    BRSkyCtx S = scSkyCtx();
    float3 L = S.sunDir;
    bool exterior = (g.flags & (G_FLAG_EXTERIOR | G_FLAG_MISS)) != 0u;

    float3 col = 0;
    float3 diag = 0;
    float tEnd = g.t;
    // How far along the eye ray this pixel's IMAGE sits, where that is not the G-buffer's surface:
    // a sheer hanging in front of a window, the trees outside it, a mirror's virtual image. The
    // resolve pass reprojects history through it. Reprojected at the glass's 500 m stand-in, a sheer
    // 3 m away fetched last frame's colour from the wrong place on every step and smeared.
    float repD = -1.0;
    bool reflEscRep = false;
    // ONE exterior evaluation per pixel: either what the eye sees through an opening, or what a
    // reflection ray found when it left the building (weighted by that reflection's BRDF).
    bool extNeed = false;
    float3 extO = ro, extD = rd, extMul = 1.0;
    float extT = g.t;

    if (exterior)
    {
        extNeed = true;
    }
    else
    {
        float3 p = ro + rd * g.t;
        float3 n = g.n;
        if (dot(n, rd) > 0.0) n = -n;
        float3 v = -rd;
        float NoVg = max(dot(n, v), 0.15);
        float fp = g.t * pa / NoVg;
        BRMat m;
        BRTrip Tt = tripHeader();
        float3 pS = (Tt.dose > 0.0) ? tripSwim(p, n, Tt) : p;
        BRSurf s = surfaceAt(g, p, pS, n, fp, m);
        // the trip's geometry, emerging from the plain surfaces: the lattice tints the paint along
        // its lines and glows a little in proportion to the light already there (so it reads as
        // embedded in the plaster, not projected on it)
        float3 patGlow = 0;
        if (g.obj < 0 && (g.part == PART_SHELL || g.part == PART_CEILING || g.part == PART_BREAST || g.part == PART_REVEAL))
        {
            float gS = tripGeometryAt(p, Tt);
            if (gS > 0.002)
            {
                // an ISOTROPIC footprint (distance only): divided by N.V, a ceiling seen edge-on
                // faded its whole lattice away; TAA integrates the grazing compression instead
                // (overdrive packs the lattice finer)
                float3 pat = tripPattern(tripSurfaceUV(pS, n), Tt.time, Tt.motif, g.t * pa, 1.0 / tripFreq(Tt), 0.006);
                float3 tint = tripTint(pat.y);
                tint = lerp(dot(tint, float3(0.3, 0.6, 0.1)).xxx, tint, 0.35 + 0.65 * Tt.colour);
                s.albedo = lerp(s.albedo, saturate(s.albedo * tint * 2.0), pat.x * gS);
                s.albedo *= 1.0 + (pat.z - 0.5) * 0.08 * gS;
                patGlow = tint * pat.x * gS;
            }
        }
        float3 nS = normalize(n + s.bump);
        float NoV = max(dot(nS, v), 1e-3);

        bool doSun = S.sunDir.y > -0.03 && (dot(nS, L) > 0.0 || s.trans > 0.0) && sun_direct != 0;
        float roughR = (s.coat > 0.25) ? min(s.coatRough, s.rough) : s.rough;
        bool doRefl = refl_steps > 0 && (roughR < 0.42) && (s.metal > 0.5 || s.coat > 0.25 || roughR < 0.30);
        // The MIRROR direction, never a per-frame random draw. A jittered glossy lobe only averages
        // out under a long, still history; in motion it sparkled on every glossy surface (leather,
        // brass, the varnished floor). The lobe's width comes from glossBlend below instead: the
        // traced mirror image fades into the smooth probe radiance as the surface roughens.
        float3 Rm = reflect(-v, nS);
        float3 Rd = Rm;
        float glossBlend = smoothstep(0.10, 0.40, roughR);

        const float3 TET[4] = { float3(1, -1, -1), float3(-1, -1, 1), float3(-1, 1, -1), float3(1, 1, 1) };
        float aoR = ao_radius;
        float sunVis = 0.0, rSunVis = 0.0;
        float occ = 0.0, occN = 0.0;
        bool rHit = false, rEsc = false, rBox = false;
        float3 rP = 0, rN = 0;
        SHit rH = shit(1e9, 0, 0, -1);
        float rEscT = 0.0, rT = 0.0;
        float softK = 1.0 / max(scSunSoft(), 0.004);

        // lamps: every lit lamp unshadowed, and the one that matters most here gets a real
        // shadow ray (job 12) -- deterministic, so nothing to accumulate away
        int nLamp = scLampCount();
        float3 lampRest = 0, lampTopC = 0, lampTopPos = 0;
        float lampTopW = 0.0, lampTopDist = 1.0;
        [loop] for (int li = 0; li < nLamp; li++)
        {
            BRRec lr = SceneBuf[SC_LAMP0 + li];
            float3 dl = lr.dims.xyz - p;
            float d2 = max(dot(dl, dl), 1e-6);
            float dd = sqrt(d2);
            float3 l = dl / dd;
            if (dot(nS, l) <= 0.0 && s.trans <= 0.0) continue;
            float3 Il = lr.dims.w * lr.look.rgb * lampShadeFactor(lr, -l, dd) / (d2 + lampRadius2(lr));
            float3 ld, ls;
            brDirect(s, nS, v, l, ld, ls);
            float3 c = (ld * s.cavity + ls) * Il;
            if (s.trans > 0.0) c += brTransmit(s, nS, l) * Il;
            float w = dot(c, float3(0.3, 0.6, 0.1));
            if (w > lampTopW) { lampRest += lampTopC; lampTopW = w; lampTopC = c; lampTopPos = lr.dims.xyz; lampTopDist = dd; }
            else lampRest += c;
        }
        float lampVis = 1.0;

        [loop] for (int job = 0; job < 13; job++)
        {
            int kind = 0;
            bool active = false;
            float3 o = p, d = L;
            int maxS = 1;
            if (job == 0)      { kind = 0; active = doSun; o = p + n * 0.0035; d = L; maxS = shadow_steps; }
            // AO taps follow the GEOMETRIC normal: a bumped one jitters the taps across concave
            // mouldings and the crown cove came out in noisy moire slots
            else if (job <= 5) { kind = 1; active = ao_gain > 0.0; float k = (float)job; o = p + n * (aoR * k * k / 25.0 + 0.008); maxS = 1; }
            else if (job == 6) { kind = 2; active = doRefl; o = p + n * 0.0035; d = Rd; maxS = refl_steps; }
            else if (job <= 10){ kind = 3; active = rHit && !rBox; o = rP + TET[job - 7] * 0.0025; maxS = 1; }
            else if (job == 11){ kind = 4; active = rHit && dot(rN, L) > 0.0 && S.sunDir.y > -0.03; o = rP + rN * 0.004; d = L; maxS = max(shadow_steps / 2, 16); }
            else               { kind = 5; active = lampTopW > 1e-6; o = p + n * 0.004; d = normalize(lampTopPos - o); maxS = max(shadow_steps / 2, 24); }

            if (active)
            {
                bool hyb = (kind == 0 || kind == 2 || kind == 4) && insideRoomBox(o, 0.0);
                float3 fN = float3(0, 1, 0);
                float tB = hyb ? boxExit(o, d, fN) : 1e9;
                bool passed = !hyb;
                float t = 0.0, res = 1.0;
                bool jHit = false, jEsc = false, jBox = false;
                SHit jH = shit(1e9, 0, 0, -1);
                [loop] for (int st = 0; st < maxS; st++)
                {
                    float3 x = o + d * t;
                    SHit slab;
                    SHit det = mapSplit(x, slab, kind == 1 || kind == 3);     // AO and normal taps exact
                    float dFull = min(det.d, slab.d);
                    if (kind == 1)
                    {
                        float h = aoR * (float)(job * job) / 25.0 + 0.008;
                        float w = 1.0 / (float)job;
                        occ += max(h - dFull, 0.0) * w; occN += h * w;
                        break;
                    }
                    if (kind == 3) { rN += TET[job - 7] * dFull; break; }
                    float eps = 0.0004 + t * 0.0007;
                    bool skip = false;
                    if (!passed)
                    {
                        float toB = tB - t;
                        if (det.d < eps) { jHit = true; jH = det; break; }
                        if (toB < eps)
                        {
                            float3 xb = o + d * tB;
                            float tOut = 0.0;
                            float2 sw = (kind == 0 || kind == 4) ? sunWindowExit(xb, d, tB, softK, tOut) : float2(-1.0, 0.0);
                            if (sw.x > 0.5) { jEsc = true; res = min(res, sw.y); t = tB + tOut; break; }
                            else if (sw.x > -0.5) { jHit = true; jH = slab; t = tB; break; }
                            else if (boxFacePassable(xb)) { passed = true; t = tB + 0.003; skip = true; }
                            else { jHit = true; jBox = true; jH = slab; t = tB; break; }
                        }
                        if (!skip)
                        {
                            if (kind != 2) res = min(res, softK * det.d / max(t, 0.02));
                            t += min(det.d, toB);
                        }
                    }
                    else
                    {
                        // a lamp ray runs from a surface to a bulb, both inside the room box, so the
                        // room's slabs cannot block it: it steps by the detail alone instead of creeping
                        // away from the wall or floor it leaves at the slab's tiny distances (about 3 ms)
                        if (kind == 5) dFull = det.d;
                        if (dFull < eps) { jHit = true; if (slab.d < det.d) jH = slab; else jH = det; break; }
                        if (kind != 2) res = min(res, softK * dFull / max(t, 0.02));
                        t += dFull;
                        if (outsideBuilding(x)) { jEsc = true; break; }
                        // a sun ray from a recess (the door leaf, a reveal) that has come out into
                        // the room crosses it the cheap way too: hybrid march, analytic window exit
                        float3 xn = o + d * t;
                        if ((kind == 0 || kind == 4) && !hyb && insideRoomBox(xn, 0.0005))
                        {
                            hyb = true; passed = false;
                            tB = t + boxExit(xn, d, fN);
                        }
                    }
                    if (kind == 5 && t >= lampTopDist - 0.28) break;      // reached the lamp (its own shade excluded)
                    if (t > 30.0) { jEsc = (kind == 2); break; }
                }
                // A sun ray that ran out of steps was grazing an occluder (a chair's upholstery, a
                // table edge) and has already measured that penumbra in res. Finish it to the box
                // face analytically instead of calling it shadow: the old rule drew every terminator
                // as a ragged, pixel-noisy line on the far side of the room.
                if ((kind == 0 || kind == 4) && hyb && !passed && !jHit && !jEsc)
                {
                    float tOutX = 0.0;
                    float2 swX = sunWindowExit(o + d * tB, d, tB, softK, tOutX);
                    if (swX.x > 0.5) { jEsc = true; res = min(res, swX.y); t = tB + tOutX; }
                }
                if (kind == 0 || kind == 4)
                {
                    float vis = 0.0;
                    if (jEsc)
                    {
                        float3 xe = o + d * t;
                        vis = smoothstep(0.0, 1.0, saturate(res)) * veilTransmit(o, d) * brCanopyTransmitPen(xe, d, S, 0.0, t, scSunSoft());
                    }
                    if (kind == 0) sunVis = vis; else rSunVis = vis;
                }
                else if (kind == 2)
                {
                    if (jHit) { rHit = true; rH = jH; rP = o + d * t; rT = t; rBox = jBox; if (jBox) rN = fN; }
                    else if (jEsc) { rEsc = true; rEscT = t; }
                }
                else if (kind == 5)
                {
                    lampVis = jHit ? 0.0 : smoothstep(0.0, 1.0, saturate(res * 0.25));
                }
            }
            if (job == 10 && rHit && !rBox) rN = normalize(rN + 1e-9);
        }

        float ao = saturate(1.0 - ao_gain * occ / max(occN, 1e-4));
        // direct sun
        float3 dif, spe;
        brDirect(s, nS, v, L, dif, spe);
        float3 direct = (dif * s.cavity + spe) * S.sunRad * sunVis;
        if (s.trans > 0.0) direct += brTransmit(s, nS, L) * S.sunRad * sunVis;
        // lamps: the strongest shadowed, the rest damped by occlusion
        float ao0 = saturate(1.0 - ao_gain * occ / max(occN, 1e-4));
        direct += lampTopC * lampVis + lampRest * ao0 * ao0;
        // diffuse bounce
        float3 Egi = probeIrr(p, nS) * gi_gain;
        float3 indD = s.albedo * (1.0 - s.metal) * Egi * (1.0 / 3.14159265) * ao * s.cavity;
        // specular: traced where it matters, the probe volume otherwise
        float3 reflRad;
        if (rHit)
        {
            BRMat rm = scMat(rH.mat);
            float3 ra = rm.base;
            if (rm.family == FAM_PARQUET) ra = lerp(rm.second, rm.base, 0.6);
            float3 rE = probeIrr(rP, rN) * gi_gain + S.sunRad * saturate(dot(rN, L)) * rSunVis + lampIrradiance(rP, rN);
            reflRad = ra * rE * (1.0 / 3.14159265);
            if (rm.family == FAM_EMISSIVE) reflRad += rm.base * 4.0;
        }
        else if (rEsc)
        {
            reflRad = 0.0;
            extNeed = true; extO = p + n * 0.0035; extD = Rd; extT = rEscT;
        }
        else
        {
            reflRad = probeIrr(p, Rm) * gi_gain * (1.0 / 3.14159265);
        }
        // rough lobes: the sharp traced image blurs toward the probe radiance about the mirror
        // direction -- deterministic, so it holds still while the camera moves
        float3 envRad = probeIrr(p, Rm) * gi_gain * (1.0 / 3.14159265);
        if (rHit || rEsc) reflRad = lerp(reflRad, envRad, glossBlend);
        reflRad = min(reflRad, 60.0);
        float specOcc = saturate(pow(NoV + ao, exp2(-16.0 * roughR - 1.0)) - 1.0 + ao);
        float3 specK = brEnvBRDF(s.f0, s.rough, NoV) * specOcc * (1.0 - s.coat * 0.04)
                     + s.coat * (0.04 + 0.96 * pow(1.0 - NoV, 5.0)) * specOcc;
        if (rEsc) extMul = specK * (1.0 - glossBlend);
        float3 indS = reflRad * specK;
        col = s.emit + direct + indD + indS;
        col += patGlow * (0.04 + 0.30 * brLuma(direct + indD));
        // where a sharp reflection is most of the light (the mirror; a polished floor at a grazing
        // angle) the image moves as if it sat behind the surface, at the reflection's own distance
        if (glossBlend < 0.5 && brLuma(indS) > 0.5 * brLuma(col))
        {
            if (rHit) repD = g.t + rT;
            else if (rEsc) reflEscRep = true;
        }

        if (view == 1) diag = s.albedo;
        else if (view == 2) diag = nS * 0.5 + 0.5;
        else if (view == 3) diag = frac(g.t * 0.25).xxx;
        else if (view == 4) diag = lerp(float3(0.1, 0.2, 0.9), float3(1.0, 0.2, 0.1), saturate((float)g.steps / (float)max(march_steps, 1)));
        else if (view == 5) diag = frac(float3(g.mat * 0.37, g.mat * 0.61, g.mat * 0.83)) * 0.8 + 0.2;
        else if (view == 6) diag = sunVis.xxx;
        else if (view == 7) diag = Egi * (1.0 / 3.14159265) * 0.5;
        else if (view == 8) diag = ao.xxx;
        else if (view == 9) diag = reflRad;
        else if (view == 10) diag = frac(float3(g.part * 0.37, g.part * 0.61, g.part * 0.83)) * 0.8 + 0.2;
    }

    if (extNeed)
    {
        float dExt;
        float3 ext = min(brExteriorD(extO, extD, extT, S, SkyLut, true, dExt), exterior ? 1.0e6 : 80.0);
        col += ext * extMul;
        if (exterior) repD = dExt;
        else if (reflEscRep) repD = g.t + dExt;
        if (view == 9 && !exterior) diag = ext;
        if (exterior) diag = col;
    }

    // the fire: flames in front of whatever the ray hit inside the firebox
    float flameMask = 0.0;
    // the flame march's start offset: interleaved gradient noise advanced by the golden ratio,
    // stratified in space and time instead of re-rolled white noise
    float flameJit = frac(frac(52.9829189 * frac(dot(float2(tid.xy), float2(0.06711056, 0.00583715)))) + fr.x * 0.61803399);
    col += fireFlames(ro, rd, exterior ? 1e9 : tEnd, scFrameB().w, flameJit, flameMask);

    // translucent layer: window glass and sheer curtains, front to back, at most three layers.
    // The hit band is the PIXEL FOOTPRINT, not a fixed 0.7 mm: a 3 mm pleated sheet a few metres
    // away is thinner than a pixel, so a fixed band caught or missed each pleat depending on the
    // sub-pixel jitter and flashed whenever the camera moved. A third layer keeps a grazing pleat
    // from popping in and out of the two-layer budget.
    float vT = 1.0;
    float3 vAcc = 0;
    float vDomL = 0.0, vDomT = -1.0;          // the brightest veil layer, and where it hangs
    {
        BRMat sheer = scMat(MAT_SHEER);
        float tv = 0.0;
        int layers = 0;
        [loop] for (int i = 0; i < 112; i++)
        {
            if (tv >= tEnd - 0.002 || layers >= 3) break;
            float3 x = ro + rd * tv;
            SHit vh = veilMap(x);
            float vEps = max(0.0007, tv * pa * 0.5);
            if (vh.d < vEps)
            {
                float3 vn = veilNormal(x, vh);
                if (dot(vn, rd) > 0.0) vn = -vn;
                if (vh.mat == MAT_GLASS)
                {
                    float c = saturate(dot(vn, -rd));
                    float F = 0.04 + 0.96 * pow(1.0 - c, 5.0);
                    float3 refl = probeIrr(x, reflect(rd, vn)) * gi_gain * (1.0 / 3.14159265);
                    float3 add = vT * F * refl;
                    vAcc += add;
                    if (brLuma(add) > vDomL) { vDomL = brLuma(add); vDomT = tv; }
                    vT *= (1.0 - F) * 0.93;
                }
                else
                {
                    float op = saturate((1.0 - sheer.trans) * 0.9 + 0.08);
                    float3 alb = sheer.base;
                    float3 front = alb * probeIrr(x, vn) * gi_gain * (1.0 / 3.14159265);
                    // sunlight arriving from behind the fabric: the glow of a sheer at golden hour
                    float back = saturate(dot(-vn, L));
                    float sunT = (S.sunDir.y > -0.03) ? 0.88 * brCanopyTransmitPen(x, L, S, 0.0, 0.0, scSunSoft()) : 0.0;
                    float3 glow = alb * S.sunRad * back * sunT * (1.0 / 3.14159265) * 0.9;
                    float3 add = vT * op * (front + glow);
                    vAcc += add;
                    if (brLuma(add) > vDomL) { vDomL = brLuma(add); vDomT = tv; }
                    vT *= (1.0 - op);
                }
                layers++;
                tv += max(0.006, vEps * 3.0);
            }
            else
            {
                tv += max(vh.d, 0.0012);
            }
        }
    }
    // a veil layer brighter than everything behind it carries the pixel: it moves with the fabric
    if (vDomT > 0.0 && vDomL > brLuma(vT * col)) repD = vDomT;
    col = vAcc + vT * col;
    // only the views drawn here (1..10) replace the shaded colour: Raw Shade (11) shows it as is,
    // the TAA probe (13) clips against it, and Scope (17) greys it -- a blanket `view != 0` sent
    // all three a black frame
    if (view >= 1 && view <= 10) col = diag;
    col = max(col, 0.0);
    if (!(col.r < 1e6 && col.g < 1e6 && col.b < 1e6)) col = 0.0;
    // alpha for the resolve pass: the distance along the eye ray this pixel's IMAGE moves with (the
    // surface, or repD above), so the resolve never needs the G-buffer -- which reaches it a cook
    // later than this image does. NEGATIVE marks moving emission (the flames): keep it responsive.
    float dRep = clamp((repD > 0.0) ? repD : (exterior ? 450.0 : g.t), 0.02, 480.0);
    float aOut = (flameMask > 0.05) ? -dRep : dRep;
    OutputUAV[tid.xy] = float4(col, aOut);
}
