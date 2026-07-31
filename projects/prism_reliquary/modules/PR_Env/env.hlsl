// PR_Env / env.hlsl — the studio, as a lat-long HDR panorama.
//
// The reference is a black-room product shot. Everything that makes it read as one physical
// place — the chrome balls agreeing with each other, the fur catching one key from the same
// side, the glass edges picking up the same two strip lights — comes from all of those
// surfaces sampling ONE environment. So the environment is a node, with a preview you can
// look at, rather than a pile of constants buried in the marcher.
//
// Equirectangular: u -> azimuth about +Y, v -> polar angle from +Y. The renderer samples it
// with pr_env_uv() from _shared/relic.hlsli, so the two cannot disagree about the mapping.

#include "../_shared/relic.hlsli"

StructuredBuffer<CastRec> Cast : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// Soft rectangular emitter around direction `c`, with angular half-sizes (ax, ay) and a
// soft edge. A round blob reflects as a round blob; the reference's speculars are clearly
// rectangular softboxes, and that shape is most of the "studio" read.
float softbox(float3 d, float3 c, float ax, float ay, float soft)
{
    float3 up = abs(c.y) > 0.95 ? float3(0, 0, 1) : float3(0, 1, 0);
    float3 tx = normalize(cross(up, c));
    float3 ty = cross(c, tx);

    // reject the whole back hemisphere
    float front = dot(d, c);
    if (front <= 0.0) return 0.0;

    // gnomonic projection onto the emitter plane
    float2 e = float2(dot(d, tx), dot(d, ty)) / max(front, 1e-3);
    float2 q = abs(e) - float2(ax, ay);
    float  m = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    return 1.0 - smoothstep(-soft, soft, m);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float phi   = (uv.x - 0.5) * PR_TAU;
    float theta = uv.y * PR_PI;
    float st    = sin(theta);
    float3 d    = float3(st * cos(phi), cos(theta), st * sin(phi));

    // The backdrop lift is a STAGE decision and belongs to the plan authority, so it is
    // read off the record rather than duplicated as a local parameter.
    CastRec stage = Cast[SLOT_STAGE];
    float   lift  = stage.active > 0.5 ? stage.dims.z : 0.26;

    // ---- the room ----------------------------------------------------------
    // A black cyclorama: dark ceiling, a wall that lifts very slightly toward the horizon,
    // and a floor that is darker still. Almost all of this is near zero on purpose.
    float h = d.y;                                   // -1 floor .. +1 ceiling
    float3 col = lerp(wall_color, ceiling_color, saturate(h * 1.4));
    col = lerp(col, floor_color, saturate(-h * 1.8));

    // faint horizon band — the wall/floor seam of a real cyc
    col += wall_color * lift * 2.2 * exp(-abs(h) * 9.0);

    // ---- key softbox -------------------------------------------------------
    float ka = radians(key_azimuth), ke = radians(key_elevation);
    float3 kd = normalize(float3(cos(ke) * cos(ka), sin(ke), cos(ke) * sin(ka)));
    float  kb = softbox(d, kd, key_size * 0.42, key_size * 0.62, key_softness * 0.35 + 0.02);
    col += key_color * key_gain * kb;
    // its spill
    col += key_color * key_gain * 0.055 * pow(saturate(dot(d, kd)), 3.0);

    // ---- rim strips --------------------------------------------------------
    // Two narrow verticals behind the subject. These are what draw the bright chromatic
    // edges down the glyph and the outline on the fur.
    // One strip behind-left, one well round to the front-right, so objects get a rim on
    // BOTH shoulders. Two strips a few degrees apart just read as one fat strip.
    float ra  = radians(rim_azimuth);
    float ra2 = radians(rim_azimuth + rim_opposition);
    float3 r0 = normalize(float3(cos(ra),  0.16, sin(ra)));
    float3 r1 = normalize(float3(cos(ra2), 0.10, sin(ra2)));
    col += rim_color * rim_gain * softbox(d, r0, 0.035, 0.85, 0.05);
    col += rim_color * rim_gain * 0.62 * softbox(d, r1, 0.026, 0.70, 0.05);

    // ---- horizon strip -----------------------------------------------------
    // The band the big chrome sphere wears across its equator. It must NOT be a continuous
    // ring: an unbroken equator reflects as a perfect stripe and reads as a CG default.
    // Gaps in azimuth are what make the reflection look like a real room.
    float band = exp(-pow((h - horizon_height * 0.35) * 11.0, 2.0));
    float gaps = saturate(0.5 + 0.5 * cos(phi * 2.0 + 0.9));
    col += rim_color * strip_gain * band * gaps * gaps;

    // ---- fill --------------------------------------------------------------
    float fa = radians(fill_azimuth);
    float3 fd = normalize(float3(cos(fa), 0.30, sin(fa)));
    col += fill_color * fill_gain * pow(saturate(dot(d, fd)) , 2.0);

    // ---- floor bounce ------------------------------------------------------
    col += floor_color * bounce_gain * saturate(-h) * 1.5;

    // A very slight cool-shadow / warm-key split. Not a grade: it is the reason the
    // unlit sides of the chrome read blue-grey instead of flat black.
    col *= lerp(float3(0.92, 0.96, 1.06), float3(1.06, 1.00, 0.94), saturate(dot(d, kd) * 0.5 + 0.5));

    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
