// FM_Colony / pher.hlsl — the chemical memory of the colony.
//
// This is the pass that makes them ants instead of boids. A flock steers on its neighbours; a
// colony steers on what previous ants LEFT BEHIND, and the trail is not a path anyone planned
// but a standing wave in a substance that is being laid down and evaporating at the same time.
// Everything characteristic falls out of that one mechanism: trails that sharpen with use, that
// fade when the food runs out, and that shortcut a detour on their own.
//
// Deposit is a GATHER: each texel asks which ants are near it, rather than each ant scattering
// into texels. It needs no atomics and has no write ordering to get wrong.
//
// It asks the BUCKET GRID, not the population. At 64 ants over a 300 x 205 field, asking every
// ant was 3.9 M distance tests and free. At 1024 ants over a 600 x 410 field it would be 252 M,
// which is not free by any measure — and the answer is identical, because the deposit radius is
// a couple of millimetres and every ant beyond one grid cell contributes exactly zero.
//
// SCALED PASS. This buffer is a fraction of the root resolution, so every extent here comes
// from GetDimensions and never from _Resolution — using the root resolution for a quarter-scale
// field is the documented way to make only one corner of the domain effective.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 (the previous field, slot 0) is auto-declared by the compiler for a non-structured
// texture buffer. Declaring it here would be an X3003 redefinition.
StructuredBuffer<FmCell> Grid : register(t1);
StructuredBuffer<FmRec> PlanB : register(t2);
StructuredBuffer<FmCtl> Ctl   : register(t3);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint fw, fh;
    OutputUAV.GetDimensions(fw, fh);
    if (DTid.x >= fw || DTid.y >= fh) return;
    uint2 tc = DTid.xy;

    FmRec arena = PlanB[FM_ARENA];
    FmCtl ctl = Ctl[0];
    float dt = clamp(ctl.dt, 0.0, 0.05);

    float2 uv = ((float2)tc + 0.5) / float2(fw, fh);
    float2 w = fmFieldUVToWorld(uv, arena);

    float4 c = _Tex0[tc];

    // A persistent buffer is not guaranteed to arrive zeroed, and a non-finite value copied
    // forward every cook poisons the field for the lifetime of the project. Tested as a
    // magnitude comparison rather than isnan(), so it catches infinity too and cannot be
    // optimised away as a tautology.
    if (!(dot(c, c) < 1e12)) c = float4(0, 0, 0, 0);
    if (field_reset > 0.5) c = float4(0, 0, 0, 0);

    // --- DIFFUSION. A five-tap Laplacian. Real trail pheromone spreads by evaporation into
    // still air and re-adsorption, which at this scale is a slow isotropic blur; without it a
    // trail is a one-texel scratch that no ant standing beside it can smell, and the whole
    // recruiting mechanism silently does nothing.
    float4 n0 = _Tex0[uint2(min(tc.x + 1u, fw - 1u), tc.y)];
    float4 n1 = _Tex0[uint2(max((int)tc.x - 1, 0), tc.y)];
    float4 n2 = _Tex0[uint2(tc.x, min(tc.y + 1u, fh - 1u))];
    float4 n3 = _Tex0[uint2(tc.x, max((int)tc.y - 1, 0))];
    if (!(dot(n0, n0) < 1e12)) n0 = 0.0;
    if (!(dot(n1, n1) < 1e12)) n1 = 0.0;
    if (!(dot(n2, n2) < 1e12)) n2 = 0.0;
    if (!(dot(n3, n3) < 1e12)) n3 = 0.0;

    float4 lap = (n0 + n1 + n2 + n3) * 0.25 - c;
    // Rate scaled by dt, because a module cooks far above the display rate and a per-cook
    // constant would make the diffusion speed depend on the frame rate.
    c += lap * saturate(diffuse * dt * 60.0);

    // --- EVAPORATION. The half-life is the single most important number in the whole system:
    // too long and every route the colony ever tried stays lit forever, so it can never change
    // its mind; too short and no trail survives long enough for a second ant to find it.
    float half_life = max(evaporate, 0.05);
    float decay = pow(0.5, dt / half_life);
    c.rg *= decay;
    c.a *= pow(0.5, dt / 0.35);        // occupancy is a short memory by definition

    // --- SUBSTRATE. Re-baked every cook rather than cached, because the user can drag an
    // obstacle at any moment and a stale mask would let ants walk through it.
    float od; float2 onrm;
    FM_OBST_QUERY(PlanB, arena, w, od, onrm)
    c.b = saturate(1.0 - smoothstep(-0.4, 0.9, od));

    // Pheromone cannot exist inside a solid, and letting it sit there makes an obstacle read as
    // an attractor to the gradient follower on the far side of it.
    float solid = step(od, 0.0);
    c.rg *= (1.0 - solid);

    // --- DEPOSIT, over the 3x3 cell neighbourhood of this texel.
    //
    // The radius is CLAMPED to what that neighbourhood is guaranteed to cover. Letting it run
    // past the guarantee would make the deposit quietly asymmetric — full strength toward the
    // middle of the cell block and truncated toward its edges — which lays a trail with a faint
    // rectangular grid pattern baked into it, at the grid's spacing, for no visible reason.
    float2 ahalf = fmArenaHalf(arena);
    float radius = min(max(deposit_radius, 0.2), fmGridCellSpan(ahalf));
    float inv2 = 1.0 / (radius * radius);

    float2 add = float2(0, 0);
    float occ = 0.0;

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
            float2 d = w - Grid[gi].a[j].pos;
            float q = dot(d, d) * inv2;
            if (q >= 1.0) continue;
            float fall = 1.0 - q;                   // finite support: exactly zero past the
                                                    // radius, so a thousand ants cannot fog the
                                                    // whole arena the way an inverse-square
                                                    // falloff would
            // An ant still emerging from an emitter is not yet fully present and does not lay a
            // full-strength trail; without this a burst writes its whole scent signature into
            // the field on the frame it fires, before anything has actually walked anywhere.
            float pres = saturate(Grid[gi].a[j].fade);
            occ = max(occ, fall * pres);

            float tsk = Grid[gi].a[j].task;
            // An OUTBOUND ant lays the weak home scent that marks the way back. A LADEN one
            // lays the strong food scent that recruits. That asymmetry is the entire
            // double-trail model, and it is why a route to real food gets reinforced and a
            // route to nothing does not.
            if (tsk >= 1.5 && tsk < 2.5) add.x += fall * pres * deposit_food * Grid[gi].a[j].load;
            else if (tsk < 0.5)          add.y += fall * pres * deposit_home;
        }
    }

    c.rg += add * dt;
    c.a = max(c.a, occ);

    // Saturation, not a clamp. A trail that has been walked a thousand times is not a thousand
    // times more attractive than one walked ten times — the receptors saturate, and without
    // that the first route found wins permanently and the colony can never re-route around a
    // new obstacle.
    c.r = c.r / (1.0 + c.r * saturate(saturation));
    c.g = c.g / (1.0 + c.g * saturate(saturation));
    c.rg = min(c.rg, 8.0);

    // Outside the arena there is no substrate at all.
    if (abs(w.x) > ahalf.x || abs(w.y) > ahalf.y) c.rgba = float4(0, 0, 1, 0);

    OutputUAV[tc] = float4(c.rgb, c.a);
}
