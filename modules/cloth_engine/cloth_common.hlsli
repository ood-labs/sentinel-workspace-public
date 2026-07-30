// ---------------------------------------------------------------------------
// CLOTH LAB - shared record layout and grid topology.
//
// The sim grid is small enough (2048 particles) that the whole cloth fits in
// one D3D11 thread group's shared memory, which is what lets the solver run
// every substep and every graph-coloured constraint sweep inside a SINGLE
// dispatch with real GroupMemoryBarrierWithGroupSync() between colours.
// Nothing here may grow past that budget without moving to multi-dispatch.
// ---------------------------------------------------------------------------

#ifndef CLOTH_COMMON_INCLUDED
#define CLOTH_COMMON_INCLUDED

#define GRID_W       64u
#define GRID_H       32u
#define PCOUNT       (GRID_W * GRID_H)   // 2048
#define SOLVE_GROUP  1024u
#define PER_THREAD   (PCOUNT / SOLVE_GROUP)

// flags bits
#define CF_INIT      0x00000001u
#define CF_BROKEN_H  0x00000100u   // edge (x,y)-(x+1,y)
#define CF_BROKEN_V  0x00000200u   // edge (x,y)-(x,y+1)
#define CF_BROKEN_D  0x00000400u   // edge (x,y)-(x+1,y+1)
#define CF_BROKEN_A  0x00000800u   // edge (x,y+1)-(x+1,y)
#define CF_BROKEN_ALL 0x00000F00u

// 48 bytes. Matches manifest buffers.element_size and the state_buffers schema.
struct ClothPoint
{
    float3 position;   //  0
    float  invMass;    // 12   0 = pinned
    float3 velocity;   // 16
    float  strain;     // 28   smoothed local strain, for shading
    uint   flags;      // 32
    float  tearHeat;   // 36   fresh-tear glow, decays
    float2 pad;        // 40
};

// Interaction state, written by the events pass and read by the solver in the
// SAME cook (producer pass ordered before consumer pass in the manifest, which
// is the only handoff direction the pass system guarantees).
#define TOOL_GRAB 0u
#define TOOL_CUT  1u

struct InteractState
{
    float3 target;      //  0  world-space grab target
    float  active;      // 12  1 while a drag owns the handle
    float  index;       // 16  picked vertex, -1 when none
    float  depth;       // 20  ray parameter locked at pick time
    float  radius;      // 24  brush radius, rest-space units
    float  tool;        // 28
    float  resetRequest;// 32  monotonic counter bumped by the reset key
    float  grabs;       // 36  monotonic count of acquired handles
    float  hover;       // 40  vertex under the cursor, -1 when none

    // --- strike (audio-driven impulse) ---
    // Only the VERTEX is stored, not a position or direction: the solver already
    // has the grid in groupshared, so it can derive the rest position and the
    // surface normal itself. Keeps the record small and keeps one source of truth.
    float  strikeArmed; // 44  1 on the single cook a strike fires
    float  strikeIndex; // 48  struck vertex
    float  strikeSign;  // 52  which face the impulse punches from
    float  lastKick;    // 56  last kick count consumed, for edge detection
    float  strikeCount; // 60  monotonic strikes fired; also the RNG seed
};

// Constraint families. Each is 2-colourable on the grid, so every family costs
// exactly two barrier-separated sweeps.
// Distance families only. Bending is NOT a distance constraint here (a 2-away
// distance is satisfied by an inverted fold and locks creases) - it is a
// 3-colour curvature constraint, see sweepBending() in solve.hlsl.
#define FAM_H     0u   // structural  (i, i+1)
#define FAM_V     1u   // structural  (i, i+W)
#define FAM_D     2u   // shear       (i, i+W+1)
#define FAM_A     3u   // shear       (i+W, i+1)
#define FAM_COUNT 4u

uint clothX(uint i) { return i % GRID_W; }
uint clothY(uint i) { return i / GRID_W; }
uint clothIndex(uint x, uint y) { return y * GRID_W + x; }

// Shared by the solver (pin targets, long-range reference geometry, brush
// weighting) and the renderer (brush cursor), so both agree on rest space.
//
// Two rest orientations: a banner hanging in the XY plane, and a flat sheet in
// the XZ plane for the classic drape-onto-a-collider test.
float3 restPosition(uint i)
{
    float2 t = float2((float)clothX(i) / (float)(GRID_W - 1u),
                      (float)clothY(i) / (float)(GRID_H - 1u));

    if (spawn_plane == 0)
        return float3((t.x - 0.5) * cloth_width, -t.y * cloth_height, 0.0);

    return float3((t.x - 0.5) * cloth_width, spawn_height, (t.y - 0.5) * cloth_height);
}

#endif // CLOTH_COMMON_INCLUDED
