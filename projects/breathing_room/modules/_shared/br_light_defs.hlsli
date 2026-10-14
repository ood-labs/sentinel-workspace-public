// br_light_defs.hlsli -- BR_Light's record layout and the light maths both its canvas and the
// renderer use, so the sun the chart shows is the sun the room is lit by.
//
// LIGHT BUFFER (32 records)
//   0        SUN    head (ROLE_SUN, 1, 0, 0)
//                   dims (direction toward the sun xyz, intensity)
//                   look (sky gain, softness, wind, canopy density)
//                   meta (time of day h, day of year, latitude deg, compass deg)
//   1..8     LAMP   head (ROLE_LAMP, furniture slot, on, kind)       one per lamp role
//                   dims (power, colour temperature K, flicker, 0)
//                   look (linear colour rgb, 1)
//                   meta (0)
//   9        FIRE   head (ROLE_LAMP, LIGHT_FIRE_SLOT, on, 0)
//                   dims (power, 1800 K, flicker, flame height)
//                   look (linear colour rgb, 1)
//   12       RULES  head (ROLE_LIGHT_ED, 1, 0, 0) dims (sunrise h, sunset h, golden start h, golden end h)
//   14       EDITOR / 15 FROZEN / 16..31 DELTAS   (BR_Light private)
#ifndef BR_LIGHT_DEFS_HLSLI
#define BR_LIGHT_DEFS_HLSLI

#define LIGHT_RECORDS   32
#define LIGHT_SUN       0
#define LIGHT_LAMP0     1
#define LIGHT_LAMP_N    8
#define LIGHT_FIRE      9
#define LIGHT_RULES     12
#define LIGHT_EDITOR    14
#define LIGHT_FROZEN    15
#define LIGHT_DELTA0    16
#define LIGHT_FIRE_SLOT 99      // a furniture slot no piece uses

// Approximate black-body colour (normalised to unit luminance), 1000..12000 K.
float3 brKelvin(float K)
{
    float t = clamp(K, 1000.0, 12000.0) / 100.0;
    float r = (t <= 66.0) ? 1.0 : saturate(1.292936 * pow(t - 60.0, -0.1332047));
    float g = (t <= 66.0) ? saturate(0.3900816 * log(t) - 0.6318414) : saturate(1.1298909 * pow(t - 60.0, -0.0755148));
    float b = (t >= 66.0) ? 1.0 : ((t <= 19.0) ? 0.0 : saturate(0.5432068 * log(t - 10.0) - 1.1962541));
    float3 c = pow(max(float3(r, g, b), 0.0), 2.2);          // the fit is sRGB-ish: to linear
    return c / max(dot(c, float3(0.2126, 0.7152, 0.0722)), 1e-4);
}

// Solar position (NOAA's simplified equations). Returns elevation and azimuth in radians; azimuth
// is clockwise from north. `tod` is local solar time in hours.
float2 brSolarPosition(float tod, float doy, float latDeg)
{
    float lat = radians(latDeg);
    float dcl = radians(23.44) * sin(6.2831853 * (284.0 + doy) / 365.0);
    float H = radians(15.0 * (tod - 12.0));
    float sinEl = sin(lat) * sin(dcl) + cos(lat) * cos(dcl) * cos(H);
    float el = asin(clamp(sinEl, -1.0, 1.0));
    float cosAz = (sin(dcl) - sinEl * sin(lat)) / max(cos(el) * cos(lat), 1e-4);
    float az = acos(clamp(cosAz, -1.0, 1.0));
    if (H > 0.0) az = 6.2831853 - az;              // afternoon: west of south
    return float2(el, az);
}

// Hour of sunrise / sunset for the day (elevation crossing -0.833 deg).
float2 brSunriseSunset(float doy, float latDeg)
{
    float lat = radians(latDeg);
    float dcl = radians(23.44) * sin(6.2831853 * (284.0 + doy) / 365.0);
    float c = (sin(radians(-0.833)) - sin(lat) * sin(dcl)) / max(cos(lat) * cos(dcl), 1e-4);
    float H = degrees(acos(clamp(c, -1.0, 1.0))) / 15.0;
    return float2(12.0 - H, 12.0 + H);
}

// World direction toward the sun. World: +Z north, +X east. `compass` rotates the building
// (degrees clockwise) -- the room's +Z faces that bearing.
float3 brSunDir(float el, float az, float compassDeg)
{
    float a = az - radians(compassDeg);
    return normalize(float3(sin(a) * cos(el), sin(el), cos(a) * cos(el)));
}

// The floor parallelogram P0 + u E1 + v E2 (u, v in 0..1) the sun paints through a rectangular
// opening of a wall T thick: the interior face clipped by the street face seen along the sun, then
// projected down the sun ray onto y = 0. `a`, `w`, `sill`, `h` are the opening's along-wall
// centre, width, sill and height; `n2` its wall's inward normal, `along` the wall's along-axis.
bool brSunPatch(float2 p0, float2 n2, float2 along, float a, float w, float sill, float h, float T,
                float3 s, out float3 P0, out float3 E1, out float3 E2)
{
    P0 = 0; E1 = 0; E2 = 0;
    float sn = s.x * n2.x + s.z * n2.y;
    if (sn > -0.02 || s.y < 0.03) return false;
    float k = T / -sn;
    float da = (s.x * along.x + s.z * along.y) * k, dy = s.y * k;
    float hw = w * 0.5;
    float a0 = max(a - hw, a - hw - da), a1 = min(a + hw, a + hw - da);
    float y0 = max(sill, sill - dy), y1 = min(sill + h, sill + h - dy);
    if (a1 - a0 < 0.02 || y1 - y0 < 0.02) return false;
    float2 c = p0 + along * a0;
    float3 C = float3(c.x, y0, c.y);
    P0 = C - s * (y0 / s.y);
    E1 = float3(along.x, 0.0, along.y) * (a1 - a0);
    E2 = -float3(s.x, 0.0, s.z) * ((y1 - y0) / s.y);
    return true;
}

#endif
