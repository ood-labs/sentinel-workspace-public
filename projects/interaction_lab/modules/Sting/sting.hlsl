// Sting - the Timeline's title sting, rendered: the same layers and shading as the editor's stage
// (timeline.hlsli), with motion blur - the picture averaged over the shutter from the curves
// themselves, in linear light (averaging display values would darken every blurred edge).
//
// The shutter is cut into 32 instants; each 16x16 group evaluates all twenty channels at every
// instant once into groupshared memory (plus the shutter's centre, for the unblurred draft). A pixel
// averages `samples` of them, one from each equal stratum of the shutter, picked by a per-pixel
// offset (interleaved gradient noise): at low counts a blurred edge dithers finely instead of
// stepping into `samples` hard copies.
#define IL_TYPE_TEX _Tex1
#include "_labels.generated.hlsli"           // before il_text: it turns on the label functions
#include "../_shared/ui/il_text.hlsli"

StructuredBuffer<float4> M : register(t0);         // the Timeline's Motion (data input)
#define TL_BUF M
#include "../_shared/timeline.hlsli"
#include "../_shared/palette.hlsli"                // palToLinear / palToDisplay

RWTexture2D<float4> OutputUAV : register(u0);

#define INSTANTS 32u
groupshared float gsV[(INSTANTS + 1u) * TL_CH];    // instant i at i * TL_CH; the centre last

float ign(float2 p) { return frac(52.9829189 * frac(dot(p, float2(0.06711056, 0.00583715)))); }

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    bool valid = M[TL_PM].x == TL_MAGIC;
    float play = valid ? tlPlayhead() : 0.0;
    float open = clamp(shutter, 0.0, 360.0) / 360.0;    // the shutter, as a share of one frame
    [loop] for (uint j = gi; j < (INSTANTS + 1u) * TL_CH; j += 256u)
    {
        uint si = j / TL_CH;
        float t = (si < INSTANTS) ? ((float)si + 0.5) / (float)INSTANTS - 0.5 : 0.0;
        gsV[j] = valid ? tlValue(j % TL_CH, play + t * open) : 0.0;
    }
    GroupMemoryBarrierWithGroupSync();
    if (id.x >= W || id.y >= H) return;

    float2 res = float2(W, H);
    float2 p = float2(id.xy) + 0.5;
    float unit = res.y;                                  // the stage is one unit tall
    float2 q = float2((p.x - 0.5 * res.x) / unit, (0.5 * res.y - p.y) / unit);
    uint n = (uint)clamp(samples, 1, (int)INSTANTS);
    float3 col = TL_PAPER;
    if (valid)
    {
        float3 acc = 0.0;
        float r = ign(p);
        [loop] for (uint k = 0u; k < n; k++)
        {
            uint si = (n == 1u) ? INSTANTS : min((uint)(((float)k + r) * (float)INSTANTS / (float)n), INSTANTS - 1u);
            float4 xf[TL_LAYERS];
            float op[TL_LAYERS];
            [unroll] for (uint l = 0u; l < TL_LAYERS; l++)
            {
                uint c = si * TL_CH + l * TL_ATTRS;
                xf[l] = float4(gsV[c], gsV[c + 1u], gsV[c + 2u], gsV[c + 3u]);
                op[l] = saturate(gsV[c + 4u]);
            }
            acc += palToLinear(tlComposite(q, unit, xf, op));
        }
        col = palToDisplay(acc / (float)n);
    }

    // the slate: what this frame is (off by default; on for review)
    float k = res.y / 720.0;
    float3 ink = float3(0.30, 0.30, 0.31);
    float c = 0.0;
    if (!valid) c = ilLabel(p, 0.5 * res.x, 0.5 * res.y, 13.0 * k, LB_NOMOTION, IL_CENTER);
    else if (burn_in && p.y > res.y - 44.0 * k && p.x < 360.0 * k)
    {
        float y = res.y - 26.0 * k, x = 28.0 * k, sz = 12.0 * k;
        c = ilLabel(p, x, y, sz, LB_FRAME, IL_LEFT);
        x += ilLabelW(LB_FRAME, sz) + 6.0 * k;
        c = max(c, ilInt(p, x, y, sz, (int)round(play), 3, IL_LEFT));
        x += ilNumW(3u, sz) + 18.0 * k;
        c = max(c, ilLabel(p, x, y, sz, LB_SHUTTER, IL_LEFT));
        x += ilLabelW(LB_SHUTTER, sz) + 6.0 * k;
        c = max(c, ilNum(p, x, y, sz, shutter, 0, IL_LEFT));
        x += ilNumW(ilFormat(shutter, 0, 1, false).n, sz) + 4.0 * k;
        c = max(c, ilLabel(p, x, y, sz, LB_DEG, IL_LEFT));
        x += ilLabelW(LB_DEG, sz) + 18.0 * k;
        c = max(c, ilInt(p, x, y, sz, (int)n, 1, IL_LEFT));
        x += ilNumW(n >= 10u ? 2u : 1u, sz) + 4.0 * k;
        c = max(c, ilLabel(p, x, y, sz, LB_SAMPLES, IL_LEFT));
    }
    col = lerp(col, ink, c);
    OutputUAV[id.xy] = float4(col, 1.0);
}
