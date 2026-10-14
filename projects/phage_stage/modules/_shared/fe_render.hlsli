// Shared by the FE_Renderer passes. Include after fe_tables.hlsli and fe_rig.hlsli.
#ifndef FE_RENDER_HLSLI
#define FE_RENDER_HLSLI

// Per-instance pose, written by the prep pass: fixture frame -> right-handed world is R * p + t.
struct FePose
{
    float4 r0, r1, r2;   // rows of R; .w = t
    float4 pt;           // pan deg, tilt deg, active (1, or -1 for a placeholder), type
    float4 pipeA;        // truss pipe segment start (world), radius
    float4 pipeB;        // segment end, has pipe
};

float3 feRotate(FePose p, float3 v) { return float3(dot(p.r0.xyz, v), dot(p.r1.xyz, v), dot(p.r2.xyz, v)); }
float3 feToWorld(FePose p, float3 v) { return feRotate(p, v) + float3(p.r0.w, p.r1.w, p.r2.w); }

// The prep pass writes one buffer of float4: per instance the 6 pose rows, then up to FE_CELLS_CAP cells of
// linear radiance (cell = FE_CELL_BASE_AT(type * feMaxEmitters() + emitter) + cell in that emitter). The sources
// buffer has FE_CELLS_CAP slots per instance the same way.
#define FE_FRAME_STRIDE 134u
#define FE_FRAME_EMIT 6u
#define FE_LOAD_POSE(buf, inst, p) { uint b_ = (inst) * FE_FRAME_STRIDE; p.r0 = buf[b_]; p.r1 = buf[b_ + 1u];     p.r2 = buf[b_ + 2u]; p.pt = buf[b_ + 3u]; p.pipeA = buf[b_ + 4u]; p.pipeB = buf[b_ + 5u]; }

// Approximate blackbody colour, normalised so `ref` kelvin is white.
float3 feKelvinRgb(float k)
{
    k = clamp(k, 1000.0, 40000.0) / 100.0;
    float r = k <= 66.0 ? 1.0 : saturate(1.29293618606 * pow(k - 60.0, -0.1332047592));
    float g = k <= 66.0 ? saturate(0.39008157876 * log(k) - 0.63184144378) : saturate(1.12989086089 * pow(k - 60.0, -0.0755148492));
    float b = k >= 66.0 ? 1.0 : (k <= 19.0 ? 0.0 : saturate(0.54320678911 * log(k - 10.0) - 1.19625408914));
    float3 c = float3(r, g, b);
    return c * c;   // to linear-ish
}
float3 feKelvinTint(float k, float ref)
{
    float3 a = feKelvinRgb(k), b = feKelvinRgb(ref);
    float3 t = a / max(b, 1e-3);
    return t / max(max(t.r, max(t.g, t.b)), 1e-3);
}

float feHash11(float x) { return frac(sin(x * 127.1 + 311.7) * 43758.5453); }

uint feDeckHash(int2 p)
{
    uint h = asuint(p.x) * 0x8da6b343u ^ asuint(p.y) * 0xd8163841u;
    h ^= h >> 15; h *= 0x2c1b3c6du; h ^= h >> 12;
    return h;
}

float feDeckNoise(float2 p)
{
    int2 i = (int2)floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = (float)(feDeckHash(i) & 0xFFFFu), b = (float)(feDeckHash(i + int2(1, 0)) & 0xFFFFu);
    float c = (float)(feDeckHash(i + int2(0, 1)) & 0xFFFFu), d = (float)(feDeckHash(i + int2(1, 1)) & 0xFFFFu);
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y) / 65535.0;
}

// The stage deck's albedo relative to floor_albedo at a point (x, z): black-painted 4 x 8 ft sheets laid in
// staggered rows, each sheet a slightly different shade, worn paler where traffic runs, dark at the joints.
// Every pass that lights the deck multiplies by it, so the boards read under light as well as at rest.
float feDeckAlbedo(float2 xz)
{
    float2 s = float2(1.2192, 2.4384);
    float row = floor(xz.y / s.y);
    float2 g = float2(xz.x / s.x + 0.5 * frac(row * 0.5), xz.y / s.y);
    float2 cell = floor(g), f = abs(frac(g) - 0.5) * s;
    float joint = 1.0 - smoothstep(0.0, 0.006, min(0.5 * s.x - f.x, 0.5 * s.y - f.y));
    float shade = 0.85 + 0.3 * (float)(feDeckHash((int2)cell) & 0xFFu) / 255.0;
    float wear = 0.8 + 0.45 * feDeckNoise(xz * 0.35) * feDeckNoise(xz * 1.7 + 11.3);
    return shade * wear * (1.0 - 0.6 * joint);
}

#endif
