// br_sky.hlsli -- atmosphere, sun and the world outside the windows.
//
// SKY. Physically based single scattering (Rayleigh + Mie over an exponential atmosphere), so a
// low sun turns orange on its own and the anti-sun horizon goes rose without anyone painting it.
// It is evaluated once per frame into a 64x32 lat-long table (BR_Render's sky pass) and looked up
// bilinearly everywhere else; brSunColour() gives the transmitted sun with the same model.
//
// EXTERIOR. The room is on an upper floor. Rays that leave through an opening meet, in order:
// street trees (a volumetric canopy whose gaps are what dapple the sunlight on the floor), a far
// skyline of low rooftops, the street, and the sky. The SAME canopy density is sampled by sun
// shadow rays after they leave the building, so the leaf pattern on the floor and the trees
// seen through the glass are one object.
#ifndef BR_SKY_HLSLI
#define BR_SKY_HLSLI

#define SKY_W 64
#define SKY_H 32
#define BR_STREET_Y (-3.6)

static const float RE_ = 6360.0e3;
static const float RA_ = 6460.0e3;
static const float3 BETA_R = float3(5.802e-6, 13.558e-6, 33.100e-6);
static const float BETA_M = 3.996e-6;
static const float BETA_ME = 4.40e-6;
static const float H_R = 8000.0;
static const float H_M = 1200.0;

float2 brRaySphere(float3 ro, float3 rd, float R)
{
    float b = dot(ro, rd);
    float c = dot(ro, ro) - R * R;
    float h = b * b - c;
    if (h < 0.0) return float2(-1.0, -1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

float3 brAtmoTransmittance(float3 p, float3 dir)
{
    float t1 = brRaySphere(p, dir, RA_).y;
    if (brRaySphere(p, dir, RE_).x > 0.0) return 0.0;      // the planet is in the way
    float ds = t1 / 6.0;
    float odR = 0.0, odM = 0.0;
    [loop] for (int i = 0; i < 6; i++)
    {
        float3 x = p + dir * ((float)i + 0.5) * ds;
        float h = length(x) - RE_;
        odR += exp(-h / H_R) * ds;
        odM += exp(-h / H_M) * ds;
    }
    return exp(-(BETA_R * odR + BETA_ME * odM));
}

// Transmitted sun colour at ground level (multiply by sun intensity).
float3 brSunColour(float3 sunDir)
{
    return brAtmoTransmittance(float3(0, RE_ + 60.0, 0), normalize(sunDir + float3(0, 0.002, 0)));
}

// Single-scattered sky radiance for direction rd (sunIntensity applied by the caller).
float3 brSkyIntegrate(float3 rd, float3 sunDir)
{
    float3 ro = float3(0, RE_ + 60.0, 0);
    float3 d = rd;
    if (d.y < 0.0) d = normalize(float3(d.x, max(d.y, -0.02) * 0.0 + 0.0, d.z) + float3(0, 0.0005, 0)); // below horizon: mirror the horizon band
    float t1 = brRaySphere(ro, d, RA_).y;
    float ds = t1 / 16.0;
    float odR = 0.0, odM = 0.0;
    float3 sumR = 0, sumM = 0;
    [loop] for (int i = 0; i < 16; i++)
    {
        float3 x = ro + d * ((float)i + 0.5) * ds;
        float h = length(x) - RE_;
        float dR = exp(-h / H_R) * ds, dM = exp(-h / H_M) * ds;
        odR += dR; odM += dM;
        float3 tv = exp(-(BETA_R * odR + BETA_ME * odM));
        float3 ts = brAtmoTransmittance(x, sunDir);
        sumR += dR * tv * ts;
        sumM += dM * tv * ts;
    }
    float mu = dot(d, sunDir);
    float pR = 3.0 / (16.0 * 3.14159265) * (1.0 + mu * mu);
    float g = 0.76;
    float pM = 3.0 / (8.0 * 3.14159265) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(max(1.0 + g * g - 2.0 * g * mu, 1e-4), 1.5));
    // Single scattering alone leaves a clear sky at ~3% of the sun's illuminance; a real one is
    // 10-20%. Higher orders are close to isotropic and track the single-scattered colour, so they
    // are folded in as a gain (and a little extra blue-white haze toward the horizon).
    float3 ss = sumR * BETA_R * pR + sumM * BETA_M * pM;
    float horizon = 1.0 - saturate(d.y * 3.0);
    return ss * (2.6 + 0.8 * horizon);
}

// Lat-long mapping for the table. Azimuth from +Z (north) clockwise toward +X (east); elevation
// is square-rooted so the horizon band, where all the colour is, gets most of the rows.
float2 brSkyUV(float3 d)
{
    // atan2(0, 0) is NaN on this hardware: the zenith (and nadir) have no azimuth, pick one
    float az = (abs(d.x) + abs(d.z) > 1e-7) ? atan2(d.x, d.z) : 0.0;     // -pi..pi
    float u = frac(az / (2.0 * 3.14159265) + 1.0);
    float el = asin(clamp(d.y, -1.0, 1.0));
    float v = sqrt(saturate((el + 0.08) / (1.5708 + 0.08)));
    return float2(u, v);
}
float3 brSkyDir(float2 uv)
{
    float az = uv.x * 2.0 * 3.14159265;
    float el = uv.y * uv.y * (1.5708 + 0.08) - 0.08;
    return float3(sin(az) * cos(el), sin(el), cos(az) * cos(el));
}

// ---------------------------------------------------------------------------------------------
// EXTERIOR
struct BRSkyCtx
{
    float3 sunDir;      // toward the sun
    float3 sunRad;      // sun radiance (transmitted colour x intensity), for lighting
    float sunI;         // sky intensity scale
    float time;         // wind phase for the canopy
    float wind;         // 0..1 leaf motion
    float canopy;       // 0..1 tree density
    float4 building;    // outer box of the building in xz (x0, x1, z0, z1)
};

// Street trees on a 7 m hashed grid, kept off the building footprint.
bool brTreeAt(float2 cell, BRSkyCtx S, out float3 crownC, out float crownR)
{
    float2 h = frac(sin(float2(dot(cell, float2(127.1, 311.7)), dot(cell, float2(269.5, 183.3)))) * 43758.5453);
    float2 base = (cell + 0.25 + h * 0.5) * 7.0;
    crownR = 2.6 + h.x * 1.1;
    crownC = float3(base.x, 4.4 + h.y * 1.4, base.y);
    // street trees stand at the kerb, a pavement's width from the facade
    float2 bmin = S.building.xz - 4.5, bmax = S.building.yw + 4.5;
    bool inside = base.x > bmin.x && base.x < bmax.x && base.y > bmin.y && base.y < bmax.y;
    return !inside && (frac(h.x * 13.1 + h.y * 7.7) < S.canopy);
}

// Leaf density at world point x (0 = air, 1 = solid foliage), as a SHADOW sees it from `pen`
// metres of penumbra away. The sun is a disk: a leaf d metres from the surface it shades is
// smeared over d x (the sun's angular radius), so a wall across the room sees the street trees
// through ~10 cm of blur. Octaves finer than the blur average out and the clip that cuts the gaps
// between clusters widens into a ramp: distant trees throw soft dapples, a sunlit patch by the
// window keeps crisp ones. pen = 0 is the canopy as the eye sees it.
float brCanopyDensityPen(float3 x, BRSkyCtx S, float pen)
{
    // a disk of radius pen passes an octave of f cycles/m by about exp(-4.93 (f pen)^2)
    float a1 = exp(-17.8 * pen * pen), a2 = exp(-109.0 * pen * pen);
    float ramp = 18.0 * pen;
    float2 c0 = floor(x.xz / 7.0);
    float dens = 0.0;
    [loop] for (int k = 0; k < 9; k++)
    {
        int i = k % 3 - 1, j = k / 3 - 1;
        float3 cc; float cr;
        if (!brTreeAt(c0 + float2(i, j), S, cc, cr)) continue;
        float3 q = (x - cc) * float3(1.0, 1.25, 1.0);
        float r = length(q);
        if (r > cr + 0.6) continue;
        float sway = S.wind * 0.18 * sin(S.time * 0.9 + cc.x * 0.3) ;
        float3 w = x + float3(sway, 0, sway * 0.6);
        float fine = (a2 > 0.02) ? brVN3(w * 4.7) : 0.0;
        float leaves = brVN3(w * 1.9 + float3(S.time * 0.05 * S.wind, 0, 0)) * 0.6 * a1 + fine * 0.4 * a2;
        float shell = smoothstep(cr + 0.4, cr - 0.9, r);
        // leaf clusters with real gaps between them: a crown lets ~30% of the sun through in flecks
        float v = shell * 1.3 + leaves * 1.6 - 0.75;
        dens = max(dens, saturate((v + ramp * 0.5) / (1.0 + ramp)));
    }
    return dens;
}
float brCanopyDensity(float3 x, BRSkyCtx S) { return brCanopyDensityPen(x, S, 0.0); }

// Fraction of sunlight that survives the canopy along a ray that has left the building. `d0` is
// how far the receiver sits behind `ro` and `sunR` the sun's angular radius: together they set
// each sample's penumbra (brCanopyDensityPen). sunR = 0 gives the sharp canopy.
float brCanopyTransmitPen(float3 ro, float3 rd, BRSkyCtx S, float t0, float d0, float sunR)
{
    float T = 1.0;
    [loop] for (int i = 0; i < 10; i++)
    {
        float t = t0 + 1.0 + (float)i * 1.6;
        float3 x = ro + rd * t;
        if (x.y > 9.0 || x.y < BR_STREET_Y) break;
        T *= 1.0 - brCanopyDensityPen(x, S, (d0 + t) * sunR) * 0.62;
        if (T < 0.02) break;
    }
    return T;
}
float brCanopyTransmit(float3 ro, float3 rd, BRSkyCtx S, float t0) { return brCanopyTransmitPen(ro, rd, S, t0, 0.0, 0.0); }

float3 brSkyLookup(StructuredBuffer<float4> lut, float3 d)
{
    float2 uv = brSkyUV(d);
    float2 st = uv * float2(SKY_W, SKY_H) - 0.5;
    int2 i0 = (int2)floor(st);
    float2 f = st - (float2)i0;
    int x0 = (i0.x % SKY_W + SKY_W) % SKY_W, x1 = (x0 + 1) % SKY_W;
    int y0 = clamp(i0.y, 0, SKY_H - 1), y1 = clamp(i0.y + 1, 0, SKY_H - 1);
    float3 a = lut[y0 * SKY_W + x0].rgb, b = lut[y0 * SKY_W + x1].rgb;
    float3 c = lut[y1 * SKY_W + x0].rgb, e = lut[y1 * SKY_W + x1].rgb;
    return lerp(lerp(a, b, f.x), lerp(c, e, f.x), f.y);
}

// Radiance seen along a ray that has left the room at distance t0. `withSun` adds the disk.
// `dep` is how far along the ray that radiance sits: where the canopy turns more than half
// opaque, else the skyline, the street or the sky. The renderer reprojects its history through
// it, so a view out of a window moves with the trees across the street, not with infinity.
float3 brExteriorD(float3 ro, float3 rd, float t0, BRSkyCtx S, StructuredBuffer<float4> lut, bool withSun, out float dep)
{
    float3 col = 0;
    float T = 1.0;
    dep = 450.0;
    bool depSet = false;
    // 1. canopy, front to back, on slices parallel to the facade the ray leaves through. Slices
    // fixed in the world hold still while the camera moves. Samples spaced from t0 -- wherever the
    // caller's march happened to notice it was outside -- slid through the leaves with every step
    // the camera took, and the trees churned.
    float4 B = S.building;                                       // x0, x1, z0, z1
    bool inB = ro.x > B.x && ro.x < B.y && ro.z > B.z && ro.z < B.w;
    float tx = (abs(rd.x) > 1e-5) ? (((rd.x > 0.0) ? B.y : B.x) - ro.x) / rd.x : 1e9;
    float tz = (abs(rd.z) > 1e-5) ? (((rd.z > 0.0) ? B.w : B.z) - ro.z) / rd.z : 1e9;
    float tFace = inB ? min(tx, tz) : t0;
    // a grazing exit would space the slices metres apart along the ray: floor the slope
    float stepK = inB ? 1.0 / max((tx < tz) ? abs(rd.x) : abs(rd.z), 0.35) : 1.0;
    [loop] for (int i = 0; i < 14; i++)
    {
        float t = tFace + (0.5 + (float)i * 1.15) * stepK;
        float3 x = ro + rd * t;
        if (x.y > 9.5 || x.y < BR_STREET_Y) break;
        float dens = brCanopyDensity(x, S);
        if (dens > 0.001)
        {
            float a = saturate(dens * 0.9);
            float3 n = normalize(x - float3(floor(x.x / 7.0) * 7.0 + 3.5, 4.8, floor(x.z / 7.0) * 7.0 + 3.5));
            // self-shadowing from where the sample sits in its crown (no nested march)
            float lit = saturate(dot(n, S.sunDir) * 0.75 + 0.25) * (0.35 + 0.65 * (1.0 - dens));
            float3 leaf = float3(0.050, 0.080, 0.030) * (0.55 + 0.45 * brVN3(x * 3.3));
            float3 L = leaf * (S.sunRad * lit * 0.35 + brSkyLookup(lut, float3(0, 1, 0)) * S.sunI * 0.9)
                     + float3(0.10, 0.14, 0.03) * S.sunRad * pow(saturate(dot(rd, S.sunDir)), 6.0) * 0.08 * a;  // backlit glow
            col += T * a * L;
            if (!depSet && T * (1.0 - a) < 0.5) { dep = t; depSet = true; }
            T *= 1.0 - a;
            if (T < 0.01) break;
        }
    }
    if (T < 0.01) return col;
    // 2. far skyline: low rooftops 60-140 m out, a little haze
    float az = (abs(rd.x) + abs(rd.z) > 1e-7) ? atan2(rd.x, rd.z) : 0.0;
    float bldg = floor(az * 9.0);
    float hb = frac(sin(bldg * 91.7) * 4375.85);
    float roofEl = 0.020 + hb * 0.055 + step(0.85, hb) * 0.05;
    float el = asin(clamp(rd.y, -1.0, 1.0));
    float3 haze = brSkyLookup(lut, normalize(float3(rd.x, 0.02, rd.z))) * S.sunI;
    if (el < roofEl && el > -0.06)
    {
        float facing = saturate(dot(normalize(float3(rd.x, 0, rd.z)), -S.sunDir) * 0.5 + 0.5);
        float3 brick = lerp(float3(0.30, 0.20, 0.15), float3(0.55, 0.50, 0.45), frac(hb * 7.3));
        // a facade is sunlit when it faces away from the viewer toward the sun -- looking into a
        // low sun, the far side of the street is a backlit silhouette
        float3 wallC = brick * (S.sunRad * 0.25 * facing * facing + haze * 0.5);
        float winRow = step(0.55, frac(el * 220.0)) * step(0.5, frac(az * 160.0 + hb));
        wallC = lerp(wallC, haze * 0.35, winRow * 0.6);
        float fog = 0.55;
        col += T * lerp(wallC, haze, fog);
        if (!depSet) dep = 100.0;
        return col;
    }
    // 3. street below
    if (rd.y < 0.0)
    {
        float tg = (BR_STREET_Y - ro.y) / rd.y;
        float3 g = ro + rd * tg;
        if (!depSet) dep = clamp(tg, 1.0, 400.0);
        float lane = step(0.97, frac(g.x * 0.25 + g.z * 0.02));
        float3 asphalt = float3(0.07, 0.07, 0.075) * (0.85 + 0.15 * brVN2(g.xz * 0.7)) + lane * 0.25;
        float sh = brCanopyTransmitPen(g, S.sunDir, S, 0.0, 0.0, 0.0047);     // the real sun's radius
        float3 gc = asphalt * (S.sunRad * saturate(S.sunDir.y) * sh + brSkyLookup(lut, float3(0, 1, 0)) * S.sunI * 2.2);
        float fogG = saturate(tg / 220.0);
        col += T * lerp(gc, haze, fogG);
        return col;
    }
    // 4. sky + sun disk
    float3 sky = brSkyLookup(lut, rd) * S.sunI;
    if (withSun)
    {
        float cosS = dot(rd, S.sunDir);
        float disk = smoothstep(0.99996, 0.99999, cosS);
        float limb = 0.6 + 0.4 * saturate((cosS - 0.99996) / 0.00003);
        sky += S.sunRad * disk * limb * 2.0e4;
        sky += S.sunRad * pow(saturate(cosS), 1200.0) * 6.0;      // aureole
    }
    col += T * sky;
    return col;
}
float3 brExterior(float3 ro, float3 rd, float t0, BRSkyCtx S, StructuredBuffer<float4> lut, bool withSun)
{
    float dep;
    return brExteriorD(ro, rd, t0, S, lut, withSun, dep);
}

#endif
