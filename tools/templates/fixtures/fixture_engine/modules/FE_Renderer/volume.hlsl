// Haze from the washes and light on the deck, at half resolution, from the tile lists (the beams themselves
// render at full resolution in beams.hlsl).
//  - Washes: every wide source (strobe zones, bar pixels, wash faces) lights the smoke around it: equiangular
//    quadrature on fixed nodes (smooth, no dither) times its cos^m profile, the phase and the smoke density,
//    rolled off beyond wash_reach so the glow stays around its fixture (PHAGE's glow_range idea).
//  - Room bounce: an optional dim ray-march through the light grid (default off).
//  - Deck: illuminance from the tile's washes (beam pools are drawn sharp in beams.hlsl).
//  - Both fade out toward FE_WASH_RANGE, the reach the tile pass lists a wide source by.
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "../_shared/fe_fog.hlsli"
#include "../_shared/fe_tiles.hlsli"

StructuredBuffer<float4> Sources : register(t0);
StructuredBuffer<float4> Grid : register(t3);
StructuredBuffer<uint> Tiles : register(t4);
RWTexture2D<float4> OutputUAV : register(u0);

#define WASH_SAMPLES 4u

// A wide source reaches FE_WASH_RANGE, the radius the tile pass lists it by: its haze and deck light fade out over the
// last quarter, so a tile that does not list it would have drawn nothing of it either (no tile steps at the edge).
float washWindow(float d) { return 1.0 - smoothstep(0.75 * FE_WASH_RANGE, FE_WASH_RANGE, d); }

float3 washGlow(float4 s0, float4 s1, float4 s2, float3 ro, float3 rd, float limit)
{
    float3 p = s0.xyz;
    float delta = dot(p - ro, rd);
    float D = max(length(ro + rd * delta - p), max(0.15, 0.5 * s0.w));
    float tb = min(limit, 60.0);
    float thA = atan((0.0 - delta) / D), thB = atan((tb - delta) / D);
    float g = 0.0;
    [unroll] for (uint k = 0u; k < WASH_SAMPLES; k++)
    {
        float th = lerp(thA, thB, ((float)k + 0.5) / (float)WASH_SAMPLES);
        float t = delta + D * tan(th);
        float3 v = ro + rd * t - p;
        float3 dir = v * rsqrt(max(dot(v, v), 1e-6));
        g += feConeIntensity(s1, s2, dir) * fePhase(dot(dir, -rd)) * exp(-haze * t);
    }
    float tc = clamp(delta, 0.0, tb);
    float rr = D / max(wash_reach, 0.05);
    return s2.rgb * g / (1.0 + rr * rr) * lerp(1.0, feFogLite(ro + rd * tc), 0.5) * (thB - thA) / (D * (float)WASH_SAMPLES)
         * washWindow(D);
}

float3 gridLight(float3 x)
{
    float3 g = (x - FE_GRID_LO) / (FE_GRID_HI - FE_GRID_LO) * float3(FE_GRID_X, FE_GRID_Y, FE_GRID_Z) - 0.5;
    float3 lo = floor(g), f = g - lo;
    int3 i0 = (int3)lo;
    float3 E = 0.0;
    [unroll] for (uint k = 0u; k < 8u; k++)
    {
        int3 o = int3(k & 1u, (k >> 1) & 1u, (k >> 2) & 1u);
        int3 c = clamp(i0 + o, int3(0, 0, 0), int3(FE_GRID_X - 1, FE_GRID_Y - 1, FE_GRID_Z - 1));
        float wgt = (o.x ? f.x : 1.0 - f.x) * (o.y ? f.y : 1.0 - f.y) * (o.z ? f.z : 1.0 - f.z);
        E += Grid[(uint)c.x + FE_GRID_X * ((uint)c.y + FE_GRID_Y * (uint)c.z)].rgb * wgt;
    }
    float3 inside = step(FE_GRID_LO, x) * step(x, FE_GRID_HI);
    return E * inside.x * inside.y * inside.z;
}

// Illuminance (klx) a wide source puts on the deck point X: its cos^m intensity over the squared distance.
float3 floorLight(float4 s0, float4 s1, float4 s2, float3 X)
{
    float3 v = X - s0.xyz;
    float dd = max(dot(v, v), 0.25);
    float cosInc = max(0.0, -v.y) * rsqrt(dd);
    return s2.rgb * feConeIntensity(s1, s2, v * rsqrt(dd)) * cosInc / dd * washWindow(sqrt(dd));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (tid.x >= w || tid.y >= h) return;
    float2 uv = ((float2)tid.xy + 0.5) / float2(w, h);
    float4 nearW = mul(_InvViewProjMatrix, float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0));
    float4 farW = mul(_InvViewProjMatrix, float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 1.0, 1.0));
    float3 ro = feView(_CameraPos);
    float3 rd = normalize(feView(farW.xyz / farW.w) - feView(nearW.xyz / nearW.w));
    float depth = _Tex1.SampleLevel(PointSampler, uv, 0).a;
    float limit = depth > 0.0 ? depth : 60.0;
    uint2 tc = min(tid.xy / (FE_TILE / 2u), uint2(FE_TILES_X_MAX - 1u, FE_TILES_Y_MAX - 1u));
    uint base = (tc.y * FE_TILES_X_MAX + tc.x) * FE_TILE_STRIDE;
    uint counts = Tiles[base];
    uint nb = min(counts >> 16, FE_TILE_MAX_BROAD);

    float3 washes = 0.0;
    [loop] for (uint b = 0u; b < nb; b++)
    {
        uint2 kw = feBroadEntry(Tiles[base + 1u + FE_TILE_MAX_NARROW + b]);
        uint k = kw.x;
        washes += washGlow(Sources[k * 3u], Sources[k * 3u + 1u], Sources[k * 3u + 2u], ro, rd, limit) * asfloat(kw.y);
    }

    float3 smoke = 0.0;
    if (room_glow > 0.0)
    {
        float jitter = frac(52.9829189 * frac(dot((float2)tid.xy, float2(0.06711056, 0.00583715))));
        uint steps = (uint)clamp(volume_steps, 4, 64);
        float dt = min(limit, 48.0) / (float)steps;
        [loop] for (uint s = 0u; s < steps; s++)
        {
            float t = ((float)s + jitter) * dt;
            float3 x = ro + rd * t;
            smoke += gridLight(x) * feFogLite(x) * exp(-haze * t) * dt;
        }
    }

    // Deck light from the washes (the beams' pools are sharp, at full resolution, in beams.hlsl).
    float3 floorE = 0.0;
    float3 X = ro + rd * limit;
    if (depth > 0.0 && abs(X.y) < 0.01)
    {
        [loop] for (uint b2 = 0u; b2 < nb; b2++)
        {
            uint2 kw = feBroadEntry(Tiles[base + 1u + FE_TILE_MAX_NARROW + b2]);
            uint k = kw.x;
            floorE += floorLight(Sources[k * 3u], Sources[k * 3u + 1u], Sources[k * 3u + 2u], X) * asfloat(kw.y);
        }
    }
    float3 result = (washes * wash_gain + smoke * room_glow) * haze * beam_gain
                  + floorE * floor_albedo * feDeckAlbedo(X.xz) / 3.14159265 * surface_gain * exp(-haze * limit);
    OutputUAV[tid.xy] = float4(result, limit);
}
