// hud_orbits — 2D tilted elliptical orbital rings (gyroscope/atom look) plus a
// wireframe globe (latitude + longitude ellipses). Slow independent rotation.
// Technique: procedural ellipse strokes. Transport: render node (alpha=luminance).

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.2831853;

// stroke coverage for an ellipse centred at origin (aspect-corrected space `q`),
// semi-axes (a,b), rotated by `rot`. Width `w` is in field units.
float ellipseStroke(float2 q, float a, float b, float rot, float w)
{
    float cs = cos(-rot), sn = sin(-rot);
    float2 r = float2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
    float f = length(float2(r.x / a, r.y / b)) - 1.0;
    // normalise the implicit-field gradient roughly by min axis so width is even
    float scale = min(a, b);
    return 1.0 - smoothstep(0.0, w / scale, abs(f));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    float body = 0.0;
    float core = 0.0;

    // ========================= ORBITAL RINGS (top-centre) =====================
    {
        float2 c = orbit;
        float2 q = (uv - c) * float2(asp, 1.0);
        float t = _Time * orbit_speed;
        float R = orbit_radius;
        float w = 0.0016;
        // three crossing ellipses, different tilt + eccentricity, slow precession
        body = max(body, ellipseStroke(q, R,        R * 0.42, 0.5 + t,        w));
        body = max(body, ellipseStroke(q, R * 0.92, R * 0.30, -0.4 - t * 0.7, w));
        body = max(body, ellipseStroke(q, R * 0.55, R * 0.98, 1.1 + t * 0.5,  w));
        // a bright travelling node on the outer orbit
        {
            float a = 0.5 + t;
            float2 pos = float2(cos(t * 1.7) * R, sin(t * 1.7) * R * 0.42);
            float cs = cos(a), sn = sin(a);
            float2 wp = float2(pos.x * cs - pos.y * sn, pos.x * sn + pos.y * cs);
            core = max(core, 1.0 - smoothstep(0.0, 0.010, length(q - wp)));
        }
        // small hub ring at the centre
        body = max(body, (1.0 - smoothstep(0.0, 0.0016, abs(length(q) - R * 0.10))));
    }

    // ============================ WIREFRAME GLOBE (top-left) ==================
    {
        float2 c = globe;
        float2 q = (uv - c) * float2(asp, 1.0);
        float R = globe_radius;
        float rr = length(q);
        float spin = _Time * globe_speed;
        float w = 0.0013;

        // outer limb
        body = max(body, (1.0 - smoothstep(0.0, 0.0015, abs(rr - R))));

        // latitudes: horizontal ellipses foreshortened in y
        [loop]
        for (int i = 1; i < 6; i++)
        {
            float lat = ((float)i / 6.0) * 1.6 - 0.8;          // -0.8..0.8
            float yc = R * sin(lat);
            float ax = R * cos(lat);
            float band = 1.0 - smoothstep(0.0, w * 2.2, abs(length(float2(q.x / ax, (q.y - yc) / (ax * 0.30))) - 1.0));
            band *= step(rr, R * 1.02);
            body = max(body, band);
        }

        // longitudes: vertical meridian ellipses, precessing with spin
        [loop]
        for (int j = 0; j < 5; j++)
        {
            float phi = ((float)j / 5.0) * 3.14159 + spin;
            float ax = R * abs(cos(phi)) + 0.004;
            float band = 1.0 - smoothstep(0.0, w * 2.2, abs(length(float2(q.x / ax, q.y / R)) - 1.0));
            band *= step(rr, R * 1.02);
            body = max(body, band);
        }
        // hot pole/centre
        core = max(core, (1.0 - smoothstep(0.0, R * 0.06, rr)) * 0.7);
    }

    float3 col = orbit_color * body + core_color * core;
    col *= intensity;
    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
