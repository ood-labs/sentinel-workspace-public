// TP_Caustics / resolve.hlsl — turn photon counts into an irradiance atlas.
//
// A raw bin count is not a brightness. A floor bin and a wall bin stand for different world
// areas, and irradiance is energy per unit AREA — so every count is divided by the world area
// its own bin actually subtends, which the shared atlas helper reports per region. Skip that
// and the walls come out several times too bright for no visible reason.
//
// The normalisation constant is chosen so that a perfectly flat surface resolves to exactly
// 1.0 everywhere. That makes the output a real multiplier the renderer can apply directly, and
// it makes "is my caustic pass correct" a question with a numeric answer: still the water and
// the atlas should read 1.0.
#include "../_shared/tessera.hlsli"

StructuredBuffer<uint> Acc : register(t0);
StructuredBuffer<TpRec> Plan : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

#define TP_FIX 65536.0

// Read the half the splat filled THIS cook. The other half is already wiped and waiting for the
// next one — see the header of splat.hlsl for why the accumulator is halved rather than cleared.
static uint gBase = 0u;

float fetch(int2 b, uint n)
{
    b = clamp(b, int2(0, 0), int2((int)n - 1, (int)n - 1));
    return (float)Acc[gBase + (uint)b.y * n + (uint)b.x] * (1.0 / TP_FIX);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    uint n = (uint)atlas_size;
    // Which half the splat filled, as stated by the splat itself. See its header.
    gBase = (Acc[2u * n * n] & 1u) * n * n;
    float2 uv = ((float2)tid.xy + 0.5) / float2(W, H);

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);

    float worldArea, atlasArea;
    int region = tpAtlasRegion(uv, half3, worldArea, atlasArea);

    float e = 0.0;

    if (region >= 0)
    {
        if ((int)method == 0)
        {
            // --- photon: gather the bins with a small tent, which is the reconstruction
            // filter for a splatted estimate rather than a cosmetic blur.
            float2 fp = uv * (float)n - 0.5;
            int2 b = int2(floor(fp));
            int r = clamp((int)blur_radius, 0, 3);
            float sum = 0.0, wsum = 0.0;
            for (int dy = -3; dy <= 3; dy++)
            {
                for (int dx = -3; dx <= 3; dx++)
                {
                    if (abs(dx) <= r && abs(dy) <= r)
                    {
                        float w = (1.0 + (float)r - abs((float)dx)) * (1.0 + (float)r - abs((float)dy));
                        sum += fetch(b + int2(dx, dy), n) * w;
                        wsum += w;
                    }
                }
            }
            float count = sum / max(wsum, 1e-4);

            // Flat-surface normalisation. N photons spread over the footprint; a bin covering
            // `binWorld` of world area would then receive N * binWorld / footprintWorld.
            float stride = max((float)sample_step, 1.0);
            float N = ((float)sample_grid / stride) * ((float)sample_grid / stride);
            float bins = atlasArea * (float)n * (float)n;
            float binWorld = worldArea / max(bins, 1.0);
            float footWorld = 4.0 * half3.x * half3.z;
            float expected = N * binWorld / max(footWorld, 1e-5);

            e = count / max(expected, 1e-5);
        }
        else if (region == TP_FACE_FLOOR)
        {
            // --- divergence: the cheap estimate. Assume the light arrives vertically and each
            // floor point is lit by the surface directly above it, then brightness is the
            // reciprocal of how much that mapping stretches. Smooth, atomics-free, and
            // fundamentally incapable of a cusp — which is why it is the DRAFT rung and not
            // the default.
            float2 fuv = float2((uv.x - TP_A_C0) / (TP_A_C1 - TP_A_C0), (uv.y - TP_A_C0) / (TP_A_C1 - TP_A_C0));
            float2 texel = 1.0 / float2(W, H) * ((TP_A_C1 - TP_A_C0) > 0.0 ? 1.0 / (TP_A_C1 - TP_A_C0) : 1.0);

            float2 gL = _Tex2.SampleLevel(LinearSampler, fuv - float2(texel.x, 0), 0).zw;
            float2 gR = _Tex2.SampleLevel(LinearSampler, fuv + float2(texel.x, 0), 0).zw;
            float2 gD = _Tex2.SampleLevel(LinearSampler, fuv - float2(0, texel.y), 0).zw;
            float2 gU = _Tex2.SampleLevel(LinearSampler, fuv + float2(0, texel.y), 0).zw;

            float2 world = 2.0 * float2(half3.x, half3.z) * texel;
            float k = half3.y * (1.0 / 1.333) * slope_gain;
            float dxx = 1.0 + k * (gR.x - gL.x) / (2.0 * world.x);
            float dzz = 1.0 + k * (gU.y - gD.y) / (2.0 * world.y);
            float dxz = k * (gU.x - gD.x) / (2.0 * world.y);
            float dzx = k * (gR.y - gL.y) / (2.0 * world.x);

            e = 1.0 / max(abs(dxx * dzz - dxz * dzx), 0.04);
        }
    }

    float raw = (region >= 0 && (int)method == 0) ? fetch(int2(uv * (float)n), n) : 0.0;

    // Diagnostic: what the OTHER half of the accumulator holds at this bin. If photons are
    // landing but the parity is out of step, this is where they will show up.
    uint otherBase = (gBase == 0u) ? (n * n) : 0u;
    int2 ob = clamp(int2(uv * (float)n), int2(0, 0), int2((int)n - 1, (int)n - 1));
    float other = (float)Acc[otherBase + (uint)ob.y * n + (uint)ob.x] * (1.0 / TP_FIX);

    e = pow(max(e, 0.0), max(contrast, 0.05)) * max(gain, 0.0);

    // .g carries the raw per-cook photon count so the instrument view can show it without
    // needing its own copy of the accumulator or its own idea of what a count means.
    OutputUAV[tid.xy] = float4(e, raw, other, 1.0);
}
