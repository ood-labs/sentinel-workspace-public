// VC_Env / env.hlsl — the studio, authored as a lat-long HDR panorama.
//
// This node exists because in a refractive image the environment is not decoration: it is the
// SUBJECT. Every pixel of glass is a sample of this panorama bent through a stack of
// interfaces, so the shape, softness and separation of the sources here is what the finished
// picture is actually made of. A single directional light produces plastic; a studio with a
// large soft key, dark negative fill and a couple of hard strips produces glass.
//
// Output is a real HDR panorama: the key runs far above 1.0 so the speculars survive the
// march, the Fresnel weighting and the bloom downstream.
#include "../_shared/vitreous.hlsli"
#include "rig.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// Angular coordinates of a direction relative to a source axis, expressed in the source's own
// tangent frame so a rectangular softbox stays rectangular anywhere on the sphere.
float2 localAngles(float3 d, float az, float el)
{
    float ce = cos(el), se = sin(el);
    float3 fwd = float3(ce * sin(az), se, ce * cos(az));
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), fwd) + float3(1e-5, 0.0, 0.0));
    float3 up = cross(fwd, right);
    float3 l = float3(dot(d, right), dot(d, up), dot(d, fwd));
    // gnomonic: only valid on the forward hemisphere, which is all a source ever covers
    if (l.z <= 0.02) return float2(9.0, 9.0);
    return float2(l.x / l.z, l.y / l.z);
}

// Rectangular area source with a soft, separable falloff.
float areaSource(float3 d, float az, float el, float2 halfSize, float soft)
{
    float2 a = localAngles(d, az, el);
    if (a.x > 8.0) return 0.0;
    float2 q = abs(a) - halfSize;
    float s = max(soft, 1e-3);
    // separable so the corners round off instead of squaring up, which is what a real
    // diffusion panel does
    float fx = smoothstep(s, -s, q.x);
    float fy = smoothstep(s, -s, q.y);
    return fx * fy;
}

// Round source, used for the hot core inside the key.
float discSource(float3 d, float az, float el, float r, float soft)
{
    float2 a = localAngles(d, az, el);
    if (a.x > 8.0) return 0.0;
    return smoothstep(r + max(soft, 1e-3), r - max(soft, 1e-3), length(a));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 uv = ((float2)pix + 0.5) / float2(W, H);
    float3 d = vc_envDir(uv);

    // ---- cyclorama. A seamless sweep: darker toward the floor, a touch lifted toward the
    // ceiling, and warm-neutral throughout. Sampled by every ray that misses the sculpture,
    // so this IS the reference's backdrop.
    float up = d.y;
    float3 floorCol = backdrop_tint * backdrop_value * 0.42;
    float3 wallCol  = backdrop_tint * backdrop_value;
    float3 skyCol   = backdrop_tint * backdrop_value * lerp(1.0, 2.30, ceiling_lift);
    float3 col = lerp(floorCol, wallCol, smoothstep(-0.55, -0.02, up));
    col = lerp(col, skyCol, smoothstep(0.05, 0.85, up));

    // A soft horizon band. Refracted rays that graze horizontally pick this up, and it is
    // what gives long glass bars their internal horizontal streak.
    float band = exp(-pow(abs(up - horizon_height) * 9.0, 2.0));
    col += backdrop_tint * band * horizon_gain * backdrop_value;

    // ---- light rig. EXPLORATION AXIS: each rig is a different studio, and because the glass
    // is transporting these sources through many interfaces, changing the rig reorganises the
    // whole image rather than just its shading.
    int rig = (int)light_rig;
    float3 keyC = key_tint * key_gain;
    float3 fillC = fill_tint * fill_gain;

    // Key angles come from the SHARED rig definition, so rig.hlsl publishes exactly the
    // direction this pass lights from.
    float az, el;
    vcKeyAngles(rig, key_azimuth, key_elevation, az, el);

    if (rig == 0)
    {
        // Softbox — one large diffusion panel high and camera-left, a broad low fill opposite,
        // and one narrow hard strip behind for edge definition.
        col += keyC * areaSource(d, az, el, float2(key_width, key_height), key_soft);
        col += keyC * 2.4 * discSource(d, az, el, key_width * 0.30, key_soft * 0.8);
        col += fillC * areaSource(d, az + 2.30, el * 0.35, float2(0.62, 0.44), 0.30);
        col += rim_tint * rim_gain * areaSource(d, az + 3.05, 0.10, float2(0.030, 0.62), 0.035);
    }
    else if (rig == 1)
    {
        // Twin Strip — two narrow tall sources flanking the sculpture. Long vertical speculars
        // down every glass arris; the most "product photography" of the four.
        col += keyC * areaSource(d, az, el, float2(0.055, 0.70), 0.045);
        col += keyC * 0.75 * areaSource(d, az + 2.60, el, float2(0.055, 0.70), 0.045);
        col += fillC * areaSource(d, az + 1.30, 0.90, float2(0.75, 0.38), 0.40);
        col += rim_tint * rim_gain * 0.5 * areaSource(d, az + 3.14, 0.25, float2(0.46, 0.16), 0.20);
    }
    else if (rig == 2)
    {
        // Overhead Wash — a single broad ceiling source. Very even, low contrast; the glass
        // reads by silhouette and refraction rather than by highlight.
        col += keyC * 0.60 * areaSource(d, az, el, float2(0.95, 0.52), 0.45);
        col += fillC * 0.8 * areaSource(d, az + 3.14, 0.30, float2(0.80, 0.44), 0.45);
        col += rim_tint * rim_gain * 0.35 * areaSource(d, az + 1.57, -0.15, float2(0.60, 0.11), 0.16);
    }
    else
    {
        // Window — a hard-edged bright rectangle divided by mullions. The one rig whose SHAPE
        // survives refraction as a recognisable image, so the glass carries a picture of it.
        float w = areaSource(d, az, el, float2(key_width * 1.15, key_height * 1.15), key_soft * 0.14);
        float2 a = localAngles(d, az, el);
        float mull = 1.0;
        if (a.x < 8.0)
        {
            float bx = smoothstep(0.020, 0.030, abs(a.x));
            float by = smoothstep(0.020, 0.030, abs(a.y - key_height * 0.25));
            mull = min(bx, by);
        }
        col += keyC * 1.25 * w * mull;
        col += fillC * areaSource(d, az + 2.60, 0.20, float2(0.60, 0.40), 0.38);
        col += rim_tint * rim_gain * areaSource(d, az + 3.05, 0.35, float2(0.038, 0.55), 0.04);
    }

    // ---- negative fill. A dark card opposite the key. Without it the panorama's ambient
    // floor washes every interface to the same value and the glass loses its shoulders; a
    // real studio kills that light with black cloth, so this does too.
    // Placed on the flank OPPOSITE the fill, not opposite the key: a card wide enough to be
    // worth having is wide enough to swallow the fill source if the two share a bearing, and
    // the symptom is a fill control that appears to do nothing.
    float neg = areaSource(d, key_azimuth - 2.30, -0.10, float2(0.95, 0.85), 0.70);
    col *= lerp(1.0, saturate(1.0 - neg_fill), neg);

    OutputUAV[pix] = float4(max(col, 0.0), 1.0);
}
