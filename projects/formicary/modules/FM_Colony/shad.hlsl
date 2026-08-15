// FM_Colony / shad.hlsl — the contact shadow field.
//
// WHY THIS PASS EXISTS, AND WHY IT IS HERE RATHER THAN IN THE RENDERER.
//
// The shadows used to be computed per pixel in FM_Render's pixel shader: for every shaded point
// on the sweep, loop the population, project each body along the light onto the plane, and take
// the darkest. At 64 ants that is 59 M iterations over a 1280 x 720 frame — expensive but
// payable. At 1024 ants it is 943 MILLION iterations per frame, each one loading a 96-byte
// record. That is not a slow frame, it is a hung one.
//
// The fix is not to make the loop cheaper. It is to notice that the answer does not depend on
// the camera at all: a contact shadow on a flat ground plane is a property of the arena, and it
// is being recomputed from scratch for every pixel that happens to look at the same square
// millimetre. So it is computed ONCE, into a field over the arena, by the node that already
// owns the bucket grid that makes the query local — and the renderer samples it.
//
// What that costs: shadow detail is now texel-limited rather than pixel-limited. At full module
// scale the field is 1200 x 820 over a 260 x 180 mm arena, which is 0.22 mm a texel against a
// tarsus a fraction of a millimetre across. The foot shadows were always a suggestion at this
// scale and they still read as one.
//
// What it buys, besides the frame: the shadows are now correct in the FM_Scope overlay and in
// any other consumer, instead of being a thing only the beauty pass knew how to compute.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<FmCell> Grid  : register(t1);
StructuredBuffer<FmRec>  PlanB : register(t2);
StructuredBuffer<FmAnt>  Ants  : register(t3);
StructuredBuffer<FmFoot> Feet  : register(t4);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint fw, fh;
    OutputUAV.GetDimensions(fw, fh);
    if (DTid.x >= fw || DTid.y >= fh) return;
    uint2 tc = DTid.xy;

    FmRec arena = PlanB[FM_ARENA];
    FmRec lightR = PlanB[FM_LIGHT];

    // SCALED PASS. The extent comes from GetDimensions, never from _Resolution — using the root
    // resolution for a scaled target is the documented way to make one corner of the domain the
    // only part that works.
    float2 uv = ((float2)tc + 0.5) / float2(fw, fh);
    float2 w = fmFieldUVToWorld(uv, arena);
    float2 ahalf = fmArenaHalf(arena);

    float3 Ldir = normalize(lightR.pos);
    float soften = max(lightR.p2, 0.05);

    // The ground-plane projection along the light. Guarded at a low elevation, or a light near
    // the horizon throws every shadow to infinity and the field fills solid.
    float2 proj = -Ldir.xz / max(Ldir.y, 0.15);

    float shadow = 0.0;

    int2 c0 = fmGridCell(w, ahalf);
    // Reach is CLAMPED to what a 3x3 cell query covers. A body shadow wants about six body
    // lengths when the light is low; letting it ask for more than the neighbourhood provides
    // would truncate it in one direction and not the other, which draws a faint rectangular
    // grid across the sweep at the bucket spacing and looks like a lighting artefact.
    float reach = fmGridCellSpan(ahalf);

    for (int dz = -1; dz <= 1; dz++)
    for (int dx = -1; dx <= 1; dx++)
    {
        int2 c = c0 + int2(dx, dz);
        if (c.x < 0 || c.y < 0 || c.x >= (int)FM_GRID_X || c.y >= (int)FM_GRID_Z) continue;

        uint gi = fmGridIndex(c);
        uint m = (uint)clamp(Grid[gi].count, 0.0, (float)FM_CELL_CAP);

        for (uint j = 0u; j < m; j++)
        {
            float L = max(Grid[gi].a[j].size, 0.05);
            float pres = saturate(Grid[gi].a[j].fade);

            // Cheap reject on the grid's own copy, before the full record is ever touched.
            float lim = min(6.0 * L, reach);
            float2 d0 = w - Grid[gi].a[j].pos;
            if (dot(d0, d0) > lim * lim) continue;

            uint ai = (uint)(Grid[gi].a[j].idx + 0.5);
            if (ai >= FM_MAX_ANTS) continue;
            FmAnt a = Ants[ai];

            // An ant still emerging is partly underground and casts proportionally less.
            float amp = pres;

            // Measured in a frame stretched along the heading, because an ant is three times
            // longer than it is wide and a round shadow under a long body is wrong at a glance.
            float2 cc = a.pos.xz + proj * a.pos.y;
            float2 F = normalize(a.dir.xz + float2(1e-5, 0));
            float2 Rt = float2(F.y, -F.x);
            float2 lp = float2(dot(w - cc, Rt), dot(w - cc, F));

            float blur = soften * (0.30 + a.pos.y / max(L, 1e-3) * 0.55);
            float2 rad = float2(0.24 * L, 0.50 * L) + blur * 0.5;
            shadow = max(shadow, (1.0 - smoothstep(0.50, 1.30, length(lp / rad))) * 0.80 * amp);

            if (foot_shadows > 0.5)
            {
                for (uint lg = 0u; lg < FM_LEGS; lg++)
                {
                    FmFoot ft = Feet[ai * FM_LEGS + lg];
                    // Only PLANTED feet. A swinging tarsus is in the air, and casting a contact
                    // shadow from it would defeat the whole point of publishing stance.
                    if (ft.stance < 0.5) continue;
                    float2 fc = ft.pos.xz + proj * ft.pos.y;
                    // Tight and FAINT. The body is the mass; a tarsus is a fraction of a
                    // millimetre across and its shadow is a suggestion, not a dark spot.
                    float fr = 0.050 * L + blur * 0.10;
                    shadow = max(shadow, (1.0 - smoothstep(fr * 0.4, fr * 1.5, length(w - fc))) * 0.42 * amp);
                }
            }
        }
    }

    OutputUAV[tc] = float4(shadow, 0.0, 0.0, 1.0);
}
