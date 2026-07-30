// ---------------------------------------------------------------------------
// CLOTH LAB - viewport interaction.
//
// Reduces the ordered viewport event stream ONCE per cook into a small durable
// state record that the solver consumes. This is the architecture the module
// docs prescribe for events: a dispatch:[1,1,1] reduction pass owning all event
// logic, with the heavy passes reading only derived state.
//
// The pick is a ray cast built from the same internal camera matrices the
// renderer draws with, so what you click is what you see. Finding the nearest
// vertex to that ray is a parallel min-reduction across the whole group; only
// the event bookkeeping afterwards is single-threaded.
//
// Handle ownership: the grabbed vertex and its ray depth are latched on drag
// begin and held until release. Re-picking every frame would drop the handle
// during fast pointer motion or on any cook that carries no events.
// ---------------------------------------------------------------------------

#include "cloth_common.hlsli"
#include "../_shared/viewport/pick3d.hlsli"

StructuredBuffer<ClothPoint>       Cloth : register(t0);
RWStructuredBuffer<InteractState>  Out   : register(u0);

#define PICK_GROUP 1024u

groupshared float gKey[PICK_GROUP];
groupshared uint  gWho[PICK_GROUP];
groupshared float gDepth[PICK_GROUP];

[numthreads(1024, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID)
{
    uint t = gtid.x;

    // ---- ray from the pointer through the internal camera -----------------
    float3 ro, rd;
    vp_ray_from_pointer(_ViewportPointerPosition, _InvViewProjMatrix, _CameraPos, ro, rd);

    // ---- nearest vertex to the ray ----------------------------------------
    // Composite key: candidates within the pick cylinder sort by distance ALONG
    // the ray so the near face wins; everything else sorts far away by
    // perpendicular distance, which keeps a fallback when nothing is under the
    // cursor.
    float pickR = max(pick_radius, 0.01);

    float bestKey = 1e30;
    uint  bestWho = 0u;
    float bestDepth = 0.0;

    [loop]
    for (uint s = 0u; s < PER_THREAD; ++s)
    {
        uint i = t + s * PICK_GROUP;
        float along;
        float key = vp_pick_key(Cloth[i].position, ro, rd, pickR, along);
        if (key < bestKey) { bestKey = key; bestWho = i; bestDepth = along; }
    }

    gKey[t] = bestKey;
    gWho[t] = bestWho;
    gDepth[t] = bestDepth;
    GroupMemoryBarrierWithGroupSync();

    [loop]
    for (uint stride = PICK_GROUP / 2u; stride > 0u; stride >>= 1u)
    {
        if (t < stride)
        {
            if (gKey[t + stride] < gKey[t])
            {
                gKey[t]   = gKey[t + stride];
                gWho[t]   = gWho[t + stride];
                gDepth[t] = gDepth[t + stride];
            }
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (t != 0u) return;

    // ---- single-threaded event bookkeeping --------------------------------
    InteractState st = Out[0];

    // First run: the buffer is zeroed, which would read as tool Grab with a
    // zero radius and a valid index 0.
    if (st.radius <= 0.0)
    {
        st.radius = max(pick_radius, 0.01) * 3.0;
        st.index = -1.0;
        st.active = 0.0;
        st.tool = (float)TOOL_GRAB;
        st.resetRequest = 0.0;
        st.grabs = 0.0;
        st.hover = -1.0;
        st.strikeArmed = 0.0;
        st.strikeIndex = -1.0;
        st.strikeSign = 1.0;
        st.lastKick = 0.0;
        st.strikeCount = 0.0;
    }

    bool hit = gKey[0] < VP_PICK_MISS;   // something actually under the cursor
    uint picked = gWho[0];
    float pickedDepth = gDepth[0];

    uint n = min(_ViewportEventCount, 64u);
    [loop]
    for (uint e = 0u; e < n; ++e)
    {
        ViewportEvent ev = _ViewportEvents[e];

        // Acquire ONLY on a real left-button press edge.
        //
        // The drag GESTURE (type 5, code 3) carries no button identity, so an
        // RMB camera-fly drag is indistinguishable from a left drag and used to
        // grab the cloth while flying. Raw button events do carry `code`, so
        // left press/release is unambiguous. Gesture end is still honoured as a
        // safety release in case a release edge is ever missed.
        bool acquire = (ev.type == 2u && ev.code == 0u && ev.phase == 1u);
        bool release = (ev.type == 2u && ev.code == 0u && ev.phase == 3u) ||
                       (ev.type == 5u && ev.code == 3u && (ev.phase == 7u || ev.phase == 8u));

        if (acquire && st.active < 0.5 && hit)
        {
            st.active = 1.0;
            st.index = (float)picked;
            st.depth = pickedDepth;
            st.target = vp_ray_at(ro, rd, pickedDepth);
            st.grabs += 1.0;
        }
        else if (release)
        {
            st.active = 0.0;
            st.index = -1.0;
        }

        // Alt+wheel only. Plain wheel belongs to the host camera (orbit dolly /
        // fly speed); reading it here too meant one scroll did two jobs at once.
        if (ev.type == 3u && (ev.modifiers & VIEWPORT_MODIFIER_ALT) != 0u)
            st.radius = clamp(st.radius * pow(1.15, ev.value), 0.02, 3.0);

        if (ev.type == 4u && ev.phase == 1u)     // key edges
        {
            if (ev.code == 7u)  st.tool = (float)TOOL_GRAB;   // G
            if (ev.code == 24u) st.tool = (float)TOOL_CUT;    // X
            if (ev.code == 18u) st.resetRequest += 1.0;       // R
            // Keyboard brush sizing, guaranteed to work even if the host also
            // consumes Alt+wheel for the camera.
            if (ev.code == 26u) st.radius = clamp(st.radius * 0.85, 0.02, 3.0);  // Z
            if (ev.code == 22u) st.radius = clamp(st.radius * 1.18, 0.02, 3.0);  // V
        }
    }

    // While a handle is held, track the pointer every cook rather than only on
    // event-carrying cooks: the drag stays smooth even when the module cooks
    // faster than events arrive.
    if (st.active > 0.5)
    {
        // A blade must follow the pointer, so Cut re-picks every cook. Grab
        // keeps its latched vertex - that is the whole point of a handle.
        if ((uint)st.tool == TOOL_CUT && hit)
        {
            st.index = (float)picked;
            st.depth = pickedDepth;
        }
        st.target = vp_ray_at(ro, rd, st.depth);
    }

    // Hover pick is published unconditionally so the renderer can draw a brush
    // cursor on the surface before anything is grabbed.
    st.hover = hit ? (float)picked : -1.0;

    // ---- audio strike -----------------------------------------------------
    // `kick_count_in` is driven by an expression from the analyser's monotonic
    // kick counter. A COUNTER is the right signal, not the envelope: it gives an
    // unambiguous edge with no threshold of our own to tune and no risk of
    // re-firing while the envelope decays.
    //
    // strikeArmed is set for exactly one cook. That is safe without a latch in
    // the solver because `interact` runs BEFORE `solve` in the same cook, which
    // is the only pass handoff direction the module system orders explicitly.
    st.strikeArmed = 0.0;
    if (strike_enabled != 0)
    {
        float kicks = floor(max(kick_count_in, 0.0));
        if (kicks != st.lastKick)
        {
            // Fresh cursor: adopt the count without firing, so enabling the
            // strike or loading a project does not discharge a burst.
            if (st.lastKick > 0.0 || kicks == 1.0)
            {
                st.strikeCount += 1.0;
                st.strikeArmed = 1.0;

                // Random interior vertex, seeded off the strike index so each hit
                // lands somewhere new. Inset from the border so a strike never
                // starts on a pinned corner, where it would be swallowed.
                float seed = st.strikeCount;
                float r1 = hash21(float2(seed, 11.7));
                float r2 = hash21(float2(seed, 43.1));
                float r3 = hash21(float2(seed, 71.3));

                uint sx = 3u + (uint)(saturate(r1) * (float)(GRID_W - 7u));
                uint sy = 3u + (uint)(saturate(r2) * (float)(GRID_H - 7u));
                st.strikeIndex = (float)clothIndex(sx, sy);
                st.strikeSign = (r3 < 0.5) ? -1.0 : 1.0;
            }
            st.lastKick = kicks;
        }
    }

    Out[0] = st;
}
