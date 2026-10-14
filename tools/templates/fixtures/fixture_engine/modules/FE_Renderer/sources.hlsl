// Light sources for the atmosphere and the floor, one slot per emitter cell: a beam emitter (a mover's lens, a
// strobe's narrow white cells) or a wash of 22 degrees or less gives a narrow source per cell from that cell's lens; a
// wider wash or a strobe emitter gives one broad source from its face, carried on its first cell's slot, with its cells'
// mean output. Photometry comes from each emitter's documented peak intensity: a beam carries its Gaussian flux per
// cell (klm), a wide source its peak (kcd) and the cos^m exponent of its beam angle (s2.w = 1 + m). Narrow beams start
// at their cells' GDTF positions projected onto the emitting face and point along their GDTF beams.
// Two merges keep dense rigs inside the tile lists: an emitter's parallel beams merge into one when its cells lie under
// beam_lod pixels apart on screen, and wide emitters of one fixture sharing a face, area and optics merge into one wide
// source (exactly). Slots past a fixture's own cells are left alone (the tile pass reads only its cells).
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/fe_render.hlsli"

StructuredBuffer<float4> Frame : register(t0);
RWStructuredBuffer<float4> Sources : register(u0);   // per (instance, cell): (pos, lens radius), (dir, tan field), (flux rgb, tan beam)

// Where cell c of a narrow emitter starts its beam (its GDTF position on the emitting face, where the face draws the
// lens) in the world, and the way it points (the face normal unless the cell has its own beam direction).
void narrowCell(FePose pose, uint type, uint c, float3 fcp, float3 rt, float3 up, uint space, float3 faceN,
                out float3 p, out float3 n)
{
    float3 d = feCellPos(type, c).xyz - fcp;
    p = fcp + rt * dot(d, rt) + up * dot(d, up);
    n = faceN;
    float3 cd = feCellDir(type, c);
    if (dot(cd, cd) > 0.25) n = normalize(feRotate(pose, fePoseVector(space, normalize(cd), pose.pt.x, pose.pt.y)));
    p = feToWorld(pose, fePosePoint(type, space, p, pose.pt.x, pose.pt.y));
}

// A wide emitter: one broad source from its face (wash or strobe, not a backlight, not a narrow wash).
bool isWide(uint4 em, float4 opt)
{
    return em.x != 0u && em.x != FE_EMITTER_BEAM && em.x != FE_EMITTER_BACKLIGHT
        && !(em.x == FE_EMITTER_WASH && opt.x <= 22.0);
}

// Wide emitters a and b of one type light the haze and deck alike per unit of output: same face, area and optics.
bool sameWide(uint type, uint me, uint a, uint b)
{
    uint4 ea = FE_EMITTER_AT(type * me + a), eb = FE_EMITTER_AT(type * me + b);
    float4 oa = FE_EMITTER_OPT_AT(type * me + a), ob = FE_EMITTER_OPT_AT(type * me + b);
    float4 da = FE_DRAW_AT((type * me + a) * 3u + 1u), db = FE_DRAW_AT((type * me + b) * 3u + 1u);
    return isWide(ea, oa) && isWide(eb, ob) && abs(da.w - db.w) < 0.5 && all(abs(da.xy - db.xy) < 1e-4)
        && all(abs(oa.xyw - ob.xyw) <= 1e-4 * max(abs(oa.xyw), 1.0));
}

// The mean output of emitter e's cells.
float3 meanOutput(uint inst, uint type, uint me, uint e)
{
    uint4 em = FE_EMITTER_AT(type * me + e);
    uint f0 = FE_CELL_BASE_AT(type * me + e);
    float3 sum = 0.0;
    for (uint c = 0u; c < em.w; c++) sum += Frame[inst * FE_FRAME_STRIDE + FE_FRAME_EMIT + f0 + c].rgb;
    return sum / (float)max(em.w, 1u);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint inst = id.x / FE_CELLS_CAP, k = id.x % FE_CELLS_CAP;
    if (inst >= FE_N_MAX) return;
    float4 s0 = 0.0, s1 = 0.0, s2 = 0.0;
    FePose pose;
    FE_LOAD_POSE(Frame, inst, pose);
    if (pose.pt.z > 0.5)
    {
        uint type = (uint)(pose.pt.w + 0.5);
        if (k >= feTypeCells(type)) return;
        uint me = feMaxEmitters();
        uint e = 0xFFu, cell = 0u, first = 0u;
        for (uint i = 0u; i < me; i++)
        {
            uint4 em = FE_EMITTER_AT(type * me + i);
            uint f0 = FE_CELL_BASE_AT(type * me + i);
            bool hit = em.x != 0u && k >= f0 && k < f0 + em.w && e == 0xFFu;
            e = hit ? i : e;
            cell = hit ? k - f0 : cell;
            first = hit ? f0 : first;
        }
        if (e != 0xFFu)
        {
            uint4 em = FE_EMITTER_AT(type * me + e);
            float4 opt = FE_EMITTER_OPT_AT(type * me + e);
            float4 d0 = FE_DRAW_AT((type * me + e) * 3u), d1 = FE_DRAW_AT((type * me + e) * 3u + 1u);
            uint face = (uint)(d1.w + 0.5);
            float4 fc = FE_FACE_G_AT(face * 4u);
            float3 nrm = FE_FACE_G_AT(face * 4u + 1u).xyz, rt = FE_FACE_G_AT(face * 4u + 2u).xyz, up = FE_FACE_G_AT(face * 4u + 3u).xyz;
            uint space = (uint)(fc.w + 0.5);
            float3 n = normalize(feRotate(pose, fePoseVector(space, nrm, pose.pt.x, pose.pt.y)));
            float tanBeam = tan(radians(0.5 * max(opt.x, 0.05)));
            float tanField = tan(radians(0.5 * max(opt.y, opt.x)));
            // A wash no wider than 22 degrees throws a cone as a beam does: its cells are narrow sources, each with its
            // share of the emitter's peak as Gaussian flux (I0 pi (beam / 2)^2 / ln 2, klm from kcd).
            bool narrowWash = em.x == FE_EMITTER_WASH && opt.x <= 22.0;
            bool narrow = em.x == FE_EMITTER_BEAM || narrowWash;
            float halfBeam = radians(0.5 * max(opt.x, 0.05));
            float cellFlux = narrowWash ? opt.z / (float)max(em.w, 1u) * 3.14159265 * halfBeam * halfBeam / 0.69314718 : opt.z;
            if (narrow)
            {
                // Level of detail: the parallel beams of one emitter whose cells lie under beam_lod pixels apart on
                // screen read as one shaft (the beam pass never draws a core under 5 cm), so the emitter's first cell
                // carries them as one beam: their summed flux from their centroid, its core widened by their spread.
                // The other cells carry nothing. Nearer, every cell keeps its own beam.
                bool merge = false;
                if (beam_lod > 0.0 && em.w > 1u)
                {
                    float3 dir0 = feCellDir(type, first);
                    bool parallel = true;
                    for (uint c = 1u; c < em.w; c++)
                    {
                        float3 dc = feCellDir(type, first + c);
                        parallel = parallel && (dot(dir0, dir0) > 0.25) == (dot(dc, dc) > 0.25)
                                && (dot(dir0, dir0) <= 0.25 || dot(normalize(dir0), normalize(dc)) > 0.99985);
                    }
                    float pitch = sqrt(max(d1.x * d1.y, 1e-6) / (float)em.w);
                    float3 at = feToWorld(pose, fePosePoint(type, space, fc.xyz, pose.pt.x, pose.pt.y));
                    float dist = max(length(at - feView(_CameraPos)), 0.01);
                    float resY = _Resolution.y > 0.5 ? _Resolution.y : 720.0;
                    float fov = _CameraFOV > 1e-3 ? _CameraFOV : 1.0;   // radians
                    float px = pitch / dist * 0.5 * resY / tan(0.5 * fov);
                    merge = parallel && px < beam_lod;
                }
                float lens = max(0.5 * d0.y, 0.004);
                if (!merge)
                {
                    float3 p, cn;
                    narrowCell(pose, type, k, fc.xyz, rt, up, space, n, p, cn);
                    float3 rad = Frame[inst * FE_FRAME_STRIDE + FE_FRAME_EMIT + k].rgb;
                    s0 = float4(p + cn * 0.002, lens);
                    s1 = float4(cn, tanField);
                    s2 = float4(rad * cellFlux, tanBeam);
                }
                else if (cell == 0u)
                {
                    float3 centre = 0.0, flux = 0.0, cn = n;
                    for (uint c = 0u; c < em.w; c++)
                    {
                        float3 p, dn;
                        narrowCell(pose, type, first + c, fc.xyz, rt, up, space, n, p, dn);
                        centre += p;
                        cn = c == 0u ? dn : cn;
                        flux += Frame[inst * FE_FRAME_STRIDE + FE_FRAME_EMIT + first + c].rgb;
                    }
                    centre /= (float)em.w;
                    float spread = 0.0;
                    for (uint c2 = 0u; c2 < em.w; c2++)
                    {
                        float3 p, dn;
                        narrowCell(pose, type, first + c2, fc.xyz, rt, up, space, n, p, dn);
                        float3 o = p - centre;
                        spread += dot(o, o);
                    }
                    // The half-maximum radius of a Gaussian with the cells' mean square spread (0.832 x rms radius).
                    float rms = sqrt(spread / (float)em.w);
                    s0 = float4(centre + cn * 0.002, sqrt(lens * lens + 0.6922 * rms * rms));
                    s1 = float4(cn, tanField);
                    s2 = float4(flux * cellFlux, tanBeam);
                }
            }
            else if (cell == 0u && em.x != FE_EMITTER_BACKLIGHT)
            {
                // Wide emitters of one fixture on the same face with the same area and optics light the haze and deck
                // alike per unit of output, so the first of them carries them all as one wide source (exactly).
                bool leader = true;
                float3 sum = meanOutput(inst, type, me, e) * opt.z;
                for (uint o = 0u; o < me; o++)
                {
                    if (o == e || !sameWide(type, me, e, o)) continue;
                    leader = leader && o > e;
                    sum += meanOutput(inst, type, me, o) * FE_EMITTER_OPT_AT(type * me + o).z;
                }
                if (leader)
                {
                    float3 p = feToWorld(pose, fePosePoint(type, space, fc.xyz, pose.pt.x, pose.pt.y));
                    s0 = float4(p + n * 0.02, 0.5 * max(d1.x, d1.y));
                    s1 = float4(n, tanField);
                    s2 = float4(sum, 1.0 + opt.w);
                }
            }
        }
    }
    Sources[id.x * 3u] = s0;
    Sources[id.x * 3u + 1u] = s1;
    Sources[id.x * 3u + 2u] = s2;
}
