// Beams in the haze at full resolution, from the tile's culled list, shaded the way PHAGE's renderer does:
// a Gaussian core at the beam angle with a crisp edge at the field angle (never thinner than 5 cm core / 7 cm
// field, nor than a pixel), integrated in closed form across the shaft at the ray's closest approach, with
// PHAGE's beam_falloff (density ~ (0.1 + d^2)^-falloff along the shaft, 1 = inverse square) so shafts read
// across the room. Flux is conserved across the beam, so a 3.5 degree beam is as much dimmer than a 0.4 degree
// beam as its photometry says. Drifting smoke and forward scattering modulate it; it runs to
// the deck at full strength.
// Where the pixel sees the deck, the same beams also land there (the pool each one throws, sharp at full
// resolution) and reflect in it: the deck ray's mirror direction is integrated through the same beams, each
// widened by the deck roughness with distance from the deck so the reflection blurs as it leaves the floor.
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"
#include "../_shared/fe_fog.hlsli"
#include "../_shared/fe_tiles.hlsli"

StructuredBuffer<float4> Sources : register(t0);
StructuredBuffer<uint> Tiles : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

// In-scatter of one beam along a ray from ro. t0 is how far the light already travelled to reach ro (a deck
// reflection), spread how much wider the beam reads per metre of the ray (the deck's roughness blur).
float3 beamInScatter(float4 s0, float4 s1, float4 s2, float3 ro, float3 rd, float limit, float pixAng, float t0, float spread)
{
    float3 p = s0.xyz, a = s1.xyz;
    float reach = feBeamReach(p, a);
    float3 w0 = ro - p;
    float b = dot(rd, a), d = dot(rd, w0), e = dot(a, w0);
    float den = max(1.0 - b * b, 1e-5);
    float z = clamp((e - b * d) / den, 0.0, reach);
    float t = clamp(dot(p + a * z - ro, rd), 0.0, limit);
    z = clamp(dot(ro + rd * t - p, a), 0.0, reach);
    float3 onBeam = p + a * z;
    float dist = length(ro + rd * t - onBeam);
    float pixel = max(t + t0, 0.05) * pixAng + t * spread;
    float core = max(max(s0.w + z * s2.w, 0.05), pixel);
    float field = max(max(s0.w + z * s1.w, 0.07), 1.4 * pixel);
    float angular = exp(-0.69314718 * (dist / core) * (dist / core)) * (1.0 - smoothstep(0.8 * field, field, dist));
    // Gaussian (half max at core) area pi core^2 / ln2; width across it sqrt(pi / ln2) core.
    float across = angular * 2.1289 * core / (4.5324 * core * core) / sqrt(den);
    float falloff = pow(0.10 + z * z, -beam_falloff) * pow(1.1, beam_falloff);   // 1 at 1 m
    float start = smoothstep(0.0, 0.03, z);
    return s2.rgb * across * falloff * start * feFog(onBeam) * fePhase(dot(a, -rd)) * exp(-haze * t);
}

// Illuminance (klx) a beam puts on the deck point X: its Gaussian flux spread over pi core^2 / ln2.
float3 beamPool(float4 s0, float4 s1, float4 s2, float3 X)
{
    float3 v = X - s0.xyz;
    float z = dot(v, s1.xyz);
    if (z <= 0.0 || s1.y > -1e-3) return 0.0;
    float core = max(s0.w + z * s2.w, 0.05), field = max(s0.w + z * s1.w, 0.07);
    float r = length(v - s1.xyz * z);
    float ang = exp(-0.69314718 * (r / core) * (r / core)) * (1.0 - smoothstep(0.8 * field, field, r));
    return s2.rgb * ang / (4.5324 * core * core) * -s1.y;
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
    float pixAng = 2.0 * tan(0.5 * _CameraFOV) / (float)h * 0.7;   // _CameraFOV is in radians
    uint2 tc = tid.xy / FE_TILE;
    uint base = (tc.y * FE_TILES_X_MAX + tc.x) * FE_TILE_STRIDE;
    uint nn = min(Tiles[base] & 0xFFFFu, FE_TILE_MAX_NARROW);
    float3 X = ro + rd * limit;
    bool deck = depth > 0.0 && abs(X.y) < 0.01;
    bool mirror = deck && floor_gloss > 0.0;
    float3 rr = float3(rd.x, -rd.y, rd.z);
    float spread = floor_rough * floor_rough;
    float3 acc = 0.0, refl = 0.0, pool = 0.0;
    [loop] for (uint i = 0u; i < nn; i++)
    {
        uint k = Tiles[base + 1u + i];
        float4 s0 = Sources[k * 3u], s1 = Sources[k * 3u + 1u], s2 = Sources[k * 3u + 2u];
        acc += beamInScatter(s0, s1, s2, ro, rd, limit, pixAng, 0.0, 0.0);
        if (deck) pool += beamPool(s0, s1, s2, X);
        if (mirror) refl += beamInScatter(s0, s1, s2, X + float3(0.0, 0.002, 0.0), rr, 40.0, pixAng, limit, spread);
    }
    float through = exp(-haze * limit);
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(-rd.y), 5.0);
    float3 result = (acc + refl * fresnel * floor_gloss * (1.0 - 0.65 * floor_rough) * through) * haze * beam_gain
                  + pool * floor_albedo * feDeckAlbedo(X.xz) / 3.14159265 * surface_gain * through;
    OutputUAV[tid.xy] = float4(result, 1.0);
}
