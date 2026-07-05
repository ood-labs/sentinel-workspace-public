// Wave Field — Ray-marched 3D wave isosurface with interconnected dot network
//
// Emitter points drift through 3D space creating expanding spherical waves.
// Their interference forms a complex isosurface rendered via ray marching.
// A constellation of floating dots is connected by luminous lines.
// Uses camera feature for WASD + right-click-drag fly controls.
// RGB = tonemapped color, Alpha = normalized depth (1=near, 0=far).

RWTexture2D<float4> OutputUAV : register(u0);

// ── Constants ────────────────────────────────────────────────────────────────
#define EMITTERS     8
#define DOTS        18
#define MAX_STEPS  100
#define MAX_DIST    20.0
#define PI          3.14159265
#define GOLDEN      2.39996323

// ── Color helpers ────────────────────────────────────────────────────────────
float3 hsv2rgb(float3 c)
{
    float3 p = abs(frac(c.xxx + float3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0);
    return c.z * lerp(float3(1,1,1), saturate(p - 1.0), c.y);
}

// ── Emitter positions (smooth Lissajous orbits) ─────────────────────────────
float3 emitterPos(uint i, float t)
{
    float fi  = float(i);
    float ph  = fi * GOLDEN;
    float st  = t * speed * 0.2;
    float r   = 2.8 + sin(ph * 0.618 + st * 0.7) * 1.2;
    return float3(
        r * cos(ph + st * 0.3 + fi * 0.1),
        sin(fi * 1.7 + st * 0.5) * 1.8 + cos(fi * 0.9 + st * 0.3) * 0.7,
        r * sin(ph * 1.1 + st * 0.4 + fi * 0.15)
    );
}

// ── Network dot positions (separate seeds) ───────────────────────────────────
float3 dotPosition(uint i, float t)
{
    float fi  = float(i) + 50.0;
    float ph  = fi * GOLDEN * 0.7;
    float st  = t * speed * 0.12;
    float r   = 4.0 + sin(fi * 0.6 + st * 0.8) * 1.8;
    return float3(
        r * cos(ph + st * 0.2),
        sin(fi * 0.8 + st * 0.35) * 2.8,
        r * sin(ph * 1.2 + st * 0.25)
    );
}

// ── Scalar wave field ────────────────────────────────────────────────────────
float waveField(float3 p, float t)
{
    float f = 0.0;
    for (uint i = 0; i < EMITTERS; i++)
    {
        float3 ep = emitterPos(i, t);
        float  d  = length(p - ep);
        float  blob = 1.0 / (1.0 + d * d * 0.3);
        float  wave = sin(d * wave_freq - t * speed * 2.5) * wave_amp;
        f += blob * (1.0 + wave);
    }
    return f;
}

// ── Ray march with bisection refinement ──────────────────────────────────────
float rayMarch(float3 ro, float3 rd, float t)
{
    float stepLen = 0.2;
    float prev    = waveField(ro + rd * 0.1, t) - iso_level;

    for (int s = 1; s <= MAX_STEPS; s++)
    {
        float dist = 0.1 + float(s) * stepLen;
        if (dist > MAX_DIST) break;

        float cur = waveField(ro + rd * dist, t) - iso_level;

        if (cur * prev < 0.0)
        {
            float a = dist - stepLen, b = dist;
            float va = prev;
            for (int j = 0; j < 10; j++)
            {
                float mid = (a + b) * 0.5;
                float vm  = waveField(ro + rd * mid, t) - iso_level;
                if (vm * va < 0.0) b = mid;
                else { a = mid; va = vm; }
            }
            return (a + b) * 0.5;
        }
        prev = cur;
    }
    return -1.0;
}

// ── Surface normal via central differences ───────────────────────────────────
float3 calcNormal(float3 p, float t)
{
    float e    = 0.005;
    float base = waveField(p, t);
    return normalize(float3(
        waveField(p + float3(e,0,0), t) - base,
        waveField(p + float3(0,e,0), t) - base,
        waveField(p + float3(0,0,e), t) - base
    ));
}

// ── Projection helpers (using camera feature matrices) ───────────────────────
float2 projectToScreen(float3 wp, float aspect)
{
    float4 clip = mul(_ViewProjMatrix, float4(wp, 1.0));
    if (clip.w < 0.01) return float2(-999.0, -999.0);
    float2 ndcPt = clip.xy / clip.w;
    return float2(ndcPt.x * aspect, ndcPt.y);
}

float projectDepthW(float3 wp)
{
    return length(wp - _CameraPos);
}

// ── Line-segment distance (2D) ──────────────────────────────────────────────
float segDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float  h  = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-8));
    return length(pa - ba * h);
}

// ── Main ─────────────────────────────────────────────────────────────────────
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float aspect = _Resolution.x / _Resolution.y;
    float t = _Time;

    // Screen UV [0,1] → NDC [-1,1] (Y-flipped for DX clip space)
    float2 screenUV = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

    // Aspect-corrected UV for visual distance calculations
    float2 uv = float2(ndc.x * aspect, ndc.y);

    // Ray from camera feature (WASD + mouse fly)
    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0, 1));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1, 1));
    nearW /= nearW.w;
    farW  /= farW.w;
    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float3 col = float3(0,0,0);
    float surfDepth = MAX_DIST;

    // ── Ray march the wave isosurface ────────────────────────────────────
    float hitDist = rayMarch(ro, rd, t);

    if (hitDist > 0.0)
    {
        float3 p = ro + rd * hitDist;
        float3 n = calcNormal(p, t);
        surfDepth = hitDist;
        float3 V = -rd;

        // Fresnel
        float fresnel = pow(1.0 - saturate(dot(n, V)), 4.0);

        // ── Animated rainbow coloring ────────────────────────────────────
        // Time-rotating color sweep creates moving rainbow across surface
        float3 colorDir = normalize(float3(sin(t * 0.3), cos(t * 0.2), sin(t * 0.15)));
        float posHue = frac(dot(p * 0.25, colorDir) + surface_hue);

        // Nearest emitter wave-phase modulation for color ripples
        float nearDist = 999.0;
        uint  nearIdx  = 0;
        for (uint ci = 0; ci < EMITTERS; ci++)
        {
            float d = length(p - emitterPos(ci, t));
            if (d < nearDist) { nearDist = d; nearIdx = ci; }
        }
        float wavePhase = sin(nearDist * wave_freq - t * speed * 2.5);
        float hue = frac(posHue + wavePhase * 0.1 * iridescence);

        // Normal-based accent for face-dependent color
        hue = frac(hue + dot(n, float3(0.1, 0.15, 0.08)) * iridescence * 0.15);
        float3 surfCol = hsv2rgb(float3(hue, 0.9, 1.0));

        // Fresnel iridescent shift (complementary edge color)
        float3 iriCol = hsv2rgb(float3(frac(hue + 0.4 + fresnel * 0.25), 0.95, 1.0));
        surfCol = lerp(surfCol, iriCol, fresnel * iridescence * 0.5);

        // ── Three-light shading ──────────────────────────────────────────
        float3 L1 = normalize(float3(1.0, 1.2, 0.6));
        float3 L2 = normalize(float3(-0.7, 0.4, -1.0));
        float3 L3 = normalize(float3(0.0, -0.5, -1.0));

        float diff1 = max(dot(n, L1), 0.0);
        float diff2 = max(dot(n, L2), 0.0) * 0.3;
        float diff3 = max(dot(n, L3), 0.0) * 0.15;

        float spec1 = pow(max(dot(n, normalize(L1 + V)), 0.0), 120.0) * 3.0;
        float spec2 = pow(max(dot(n, normalize(L2 + V)), 0.0), 60.0) * 1.0;

        float3 rimCol = hsv2rgb(float3(frac(surface_hue + 0.3), 0.6, 1.0));

        // Subsurface scattering approximation
        float sss = pow(saturate(dot(rd, L1)), 4.0) * 0.3;
        float3 sssCol = hsv2rgb(float3(frac(surface_hue + 0.1), 0.5, 1.0));

        col = surfCol * (diff1 + diff2 + diff3 + 0.04)
            + lerp(surfCol, float3(1,1,1), 0.5) * spec1  // tinted specular
            + lerp(surfCol, float3(0.7,0.85,1), 0.4) * spec2
            + rimCol * fresnel * 0.7
            + sssCol * sss;

        // Grid wireframe (marching-cubes aesthetic)
        if (grid_strength > 0.001)
        {
            float gridScale = 2.5;
            float3 gp   = frac(p * gridScale);
            float  wire = min(min(min(gp.x, 1.0 - gp.x),
                                  min(gp.y, 1.0 - gp.y)),
                              min(gp.z, 1.0 - gp.z));
            float wireA  = (1.0 - smoothstep(0.0, 0.04, wire)) * grid_strength;
            float3 wireC = hsv2rgb(float3(frac(surface_hue + 0.15), 0.3, 1.0));
            col = lerp(col, wireC, wireA);
        }

        // Emitter proximity glow on surface — finite range
        for (uint ei = 0; ei < EMITTERS; ei++)
        {
            float  ed   = length(p - emitterPos(ei, t));
            float  prox = max(0.0, 1.0 - ed * 0.4);
            float3 ec   = hsv2rgb(float3(frac(float(ei) * 0.125 + surface_hue), 0.7, 1.0));
            col += ec * prox * prox * 0.6;
        }
    }

    // ── Interconnected dot network ───────────────────────────────────────
    float2 dScr[DOTS];
    float  dZ[DOTS];
    bool   dVis[DOTS];

    for (uint di = 0; di < DOTS; di++)
    {
        float3 dp = dotPosition(di, t);
        dScr[di]  = projectToScreen(dp, aspect);
        dZ[di]    = projectDepthW(dp);
        dVis[di]  = (dZ[di] > 0.5 && dScr[di].x > -900.0);
    }

    // Connection lines
    float3 netAccum = float3(0,0,0);
    for (uint li = 0; li < DOTS; li++)
    {
        if (!dVis[li]) continue;
        for (uint lj = li + 1; lj < DOTS; lj++)
        {
            if (!dVis[lj]) continue;

            float wDist = length(dotPosition(li, t) - dotPosition(lj, t));
            if (wDist > connect_dist) continue;

            float ld    = segDist(uv, dScr[li], dScr[lj]);
            float lineW = 0.006;
            float alpha = smoothstep(lineW, lineW * 0.2, ld);
            alpha *= (1.0 - wDist / connect_dist) * connect_bright;

            float avgZ = (dZ[li] + dZ[lj]) * 0.5;
            if (avgZ > surfDepth) alpha *= 0.12;

            // Per-connection color from endpoint hues
            float lnHue = frac((float(li) + float(lj)) * 0.03 + surface_hue + 0.1);
            float3 lnCol = hsv2rgb(float3(lnHue, 0.5, 0.8));
            netAccum += lnCol * alpha;
        }
    }
    col += netAccum;

    // Dot glows — finite-range, larger cores
    for (uint gi = 0; gi < DOTS; gi++)
    {
        if (!dVis[gi]) continue;
        float  d2    = length(uv - dScr[gi]);
        float  halo  = max(0.0, 1.0 - d2 * 8.0);
        float  glow  = dot_glow * halo * halo * 0.6;
        float  core  = smoothstep(0.015, 0.004, d2) * 2.5;

        if (dZ[gi] > surfDepth) { glow *= 0.15; core *= 0.15; }

        float3 dc = hsv2rgb(float3(frac(float(gi) * 0.055 + surface_hue + 0.08), 0.4, 1.0));
        col += dc * (glow + core);
    }

    // Emitter core glows — finite-range, colorful
    for (uint egi = 0; egi < EMITTERS; egi++)
    {
        float3 ep = emitterPos(egi, t);
        float2 es = projectToScreen(ep, aspect);
        float  ez = projectDepthW(ep);
        if (es.x < -900.0) continue;

        float  d2    = length(uv - es);
        float  halo  = max(0.0, 1.0 - d2 * 7.0);
        float  glow  = dot_glow * halo * halo * 1.5;
        float  core  = smoothstep(0.015, 0.003, d2) * 3.0;

        if (ez > surfDepth) { glow *= 0.25; core *= 0.25; }

        float3 ec = hsv2rgb(float3(frac(float(egi) * 0.125 + surface_hue), 0.7, 1.0));
        col += ec * (glow + core);
    }

    // ── Tone map + gamma ─────────────────────────────────────────────────
    col = col / (1.0 + col);
    col = pow(max(col, 0.0), 1.0 / 2.2);

    // Subtle background gradient in sRGB (added AFTER gamma to stay dark)
    float3 bg = lerp(float3(0.015, 0.015, 0.03),
                     float3(0.03, 0.01, 0.05),
                     screenUV.y);
    col += bg;

    // Depth: 1 = near, 0 = far/background
    float depthVal = (surfDepth < MAX_DIST) ? 1.0 - saturate(surfDepth / MAX_DIST) : 0.0;

    OutputUAV[pixel] = float4(col, depthVal);
}
