// FM_Colony / field_out.hlsl — publish everything about the colony that lives in ARENA SPACE.
//
//   rgb   the pheromone field, straight through. FM_Render stains the substrate where the
//         traffic actually was and FM_Scope draws the gradient the ants steer on; both need the
//         field itself rather than a picture of it, so there is no ramp, no gain and no colour
//         here. Anything that dressed it up would force the two consumers to undo the dressing,
//         and they would undo it differently.
//
//   a     THE LIVE COLONY, as oriented ticks. Baked here rather than drawn by the consumer, for
//         exactly the reason the contact shadows are: FM_Stage's plan view would otherwise loop
//         the population for every pixel of a 1280x720 frame, which at 1024 ants is 943 MILLION
//         record loads a frame. That is the identical mistake the shadows made, and the fix is
//         identical — compute it once, in the node that owns the bucket grid that makes the
//         query local, and let everyone downstream sample it.
//
// Carried in the ALPHA of an output that already exists, deliberately. A new output would have
// renumbered this node's data pins and silently re-resolved four downstream links by index,
// which has already cost this project one debugging session.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the pheromone buffer, auto-declared.
StructuredBuffer<FmCell> Grid  : register(t1);
StructuredBuffer<FmRec>  PlanB : register(t2);
StructuredBuffer<FmAnt>  Ants  : register(t3);

// Distance from a point to a segment, in world millimetres. Named locally: `fmSegDist` already
// exists in the shared headers and redefining it is an X3003.
float foSegDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6)));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    // Bilinear on purpose: the field is a fraction of this pass's resolution, and a point sample
    // would hand the renderer a blocky trail whose texel grid is visible in the final image.
    float4 f = _Tex0.SampleLevel(LinearSampler, uv, 0);

    // ---- the ant layer, over the 3x3 cell neighbourhood of this texel.
    FmRec arena = PlanB[FM_ARENA];
    float2 ahalf = fmArenaHalf(arena);
    float2 w = fmFieldUVToWorld(uv, arena);

    // World millimetres per texel of THIS pass, so a tick keeps a floor thickness in texels and
    // does not thin into nothing when the arena is made large.
    float mmPerTexel = (2.0 * ahalf.x) / max(_Resolution.x, 1.0);

    float tick = 0.0;

    if (abs(w.x) <= ahalf.x && abs(w.y) <= ahalf.y)
    {
        int2 c0 = fmGridCell(w, ahalf);
        for (int dz = -1; dz <= 1; dz++)
        for (int dx = -1; dx <= 1; dx++)
        {
            int2 cc = c0 + int2(dx, dz);
            if (cc.x < 0 || cc.y < 0 || cc.x >= (int)FM_GRID_X || cc.y >= (int)FM_GRID_Z) continue;

            uint gi = fmGridIndex(cc);
            uint m = (uint)clamp(Grid[gi].count, 0.0, (float)FM_CELL_CAP);

            for (uint j = 0u; j < m; j++)
            {
                float2 ap = Grid[gi].a[j].pos;
                float  L  = max(Grid[gi].a[j].size, 0.05);
                float  pres = saturate(Grid[gi].a[j].fade);

                // Cheap reject on the grid's own copy, before the full record is touched.
                float2 d0 = w - ap;
                if (dot(d0, d0) > (L * 1.2) * (L * 1.2)) continue;

                uint ai = (uint)(Grid[gi].a[j].idx + 0.5);
                if (ai >= FM_MAX_ANTS) continue;

                // ORIENTED, not a dot. A dot says where an ant is and throws away where it is
                // going, and where it is going is the whole thing a station changes — a plan
                // view of dots cannot show you that your attractor turned the column.
                float2 dir = normalize(Ants[ai].dir.xz + float2(1e-5, 0.0));
                float2 a0 = ap - dir * L * 0.45;
                float2 a1 = ap + dir * L * 0.45;

                float halfW = max(L * 0.16, mmPerTexel * 0.8);
                float cov = 1.0 - smoothstep(halfW, halfW + mmPerTexel, foSegDist(w, a0, a1));

                // A LADEN ant reads brighter. It is the one thing about an ant's task that a
                // top-down tick can carry without spending a hue on it.
                float weight = (Grid[gi].a[j].load > 0.5) ? 1.0 : 0.62;
                tick = max(tick, cov * pres * weight);
            }
        }
    }

    OutputUAV[pixel] = float4(f.rgb, tick);
}
