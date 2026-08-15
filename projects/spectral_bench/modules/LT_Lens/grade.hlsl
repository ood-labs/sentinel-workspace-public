// LT_Lens / grade.hlsl — the print.
//
// Everything the camera does that the bench does not: halation around blown highlights, an
// anamorphic streak off hot points, the lens's own transverse chromatic error at the frame edge,
// a filmic roll-off, grain and a vignette.
//
// The order matters and it is the photographic one: add the optical artefacts in LINEAR light,
// THEN roll off. Tonemapping first and blooming afterwards produces a glow that is brightest
// where the image is already clipped, which is exactly backwards.
//
// One restraint worth naming: the aberration here is the LENS's, applied radially about the frame
// centre. The colour in the fan is not an artefact — it is the measurement — so nothing in this
// file is allowed to invent chroma anywhere near it.
RWTexture2D<float4> OutputUAV : register(u0);

float3 ltACES(float3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

float ltHash(float2 p)
{
    uint2 q = (uint2)(abs(p) * 1731.0);
    uint h = q.x * 0x9E3779B9u ^ (q.y * 0x85EBCA6Bu);
    h ^= h >> 15; h *= 0x2545F491u; h ^= h >> 13;
    return (float)(h & 0xFFFFFFu) / 16777216.0;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;

    float2 res = _Resolution.xy;
    float2 uv = ((float2)pix + 0.5) / res;
    float2 q = uv - 0.5;
    float r2 = dot(q, q);

    // Transverse chromatic aberration: the three channels focus at slightly different scales, so
    // it is a radial SCALE difference, not a translation. Zero at the centre by construction.
    float ca = aberration * 0.0030;
    float3 base;
    base.r = _Tex0.SampleLevel(LinearSampler, 0.5 + q * (1.0 + ca), 0).r;
    base.g = _Tex0.SampleLevel(LinearSampler, uv, 0).g;
    base.b = _Tex0.SampleLevel(LinearSampler, 0.5 + q * (1.0 - ca), 0).b;

    float3 bloom  = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    // A four-tap tent on the way up. The halation buffer is an eighth of the frame, and a single
    // bilinear tap still carries its texel grid into the final image as faint square structure.
    float2 wt = 0.75 / float2(160.0, 90.0);
    float3 wide = (_Tex2.SampleLevel(LinearSampler, uv + float2(-wt.x, -wt.y), 0).rgb
                +  _Tex2.SampleLevel(LinearSampler, uv + float2( wt.x, -wt.y), 0).rgb
                +  _Tex2.SampleLevel(LinearSampler, uv + float2(-wt.x,  wt.y), 0).rgb
                +  _Tex2.SampleLevel(LinearSampler, uv + float2( wt.x,  wt.y), 0).rgb) * 0.25;
    float3 streak = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;

    float3 col = base
               + bloom  * bloom_gain
               + wide   * halation_gain
               + streak * streak_gain * float3(1.0, 0.97, 1.06);   // faintly cool, like coated glass

    // Vignette, then the roll-off. A vignette applied after tonemapping crushes to grey rather
    // than to black and the room stops reading as a dark room.
    col *= 1.0 - vignette * saturate(r2 * 1.9);
    col *= exposure_stop;

    col = ltACES(col * 0.85);

    // Grain in the shadows only. A dark studio photograph is grainy where it is dark; grain in a
    // blown highlight is a video artefact and reads as noise rather than as film.
    float g = ltHash((float2)pix + floor(_Time * 24.0) * 71.3) - 0.5;
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col += g * grain * 0.06 * (1.0 - smoothstep(0.0, 0.55, lum));

    OutputUAV[pix] = float4(max(col, 0.0), 1.0);
}
