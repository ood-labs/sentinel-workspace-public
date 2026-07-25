// AUTOPSIA — temporal association. One 64-lane group; one lane per agent slot.
//
// Phase 1  each active agent looks for its nearest observation inside a gate
// Phase 2  conflicts resolve in favour of the closest agent (no double claims)
// Phase 3  matched agents are pulled toward their observation and gain
//          confidence; unmatched agents coast on velocity and lose it
// Phase 4  lane 0 spawns fresh agents on strong unclaimed observations
//
// _Tex0 = analysis image (used only for its extent, so observation pixel
//         coordinates normalize correctly regardless of proxy resolution)
// _Data0 = Corners   _Data1 = Blobs
#include "types.hlsli"

RWStructuredBuffer<Agent> Agents : register(u0);

groupshared uint gClaim[64];
groupshared uint gActive[64];

[numthreads(64, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID) {
    uint i = gtid.x;

    uint aw, ah;
    _Tex0.GetDimensions(aw, ah);
    float2 inv = 1.0 / float2(max((float)aw, 1.0), max((float)ah, 1.0));

    float dt = min(_DeltaTime, 0.1);
    uint nCorners = min(_Data0_Count, 64u);
    uint nBlobs = min(_Data1_Count, 16u);

    gClaim[i] = 0u;
    GroupMemoryBarrierWithGroupSync();

    Agent a = Agents[i];
    if (isnan(a.position.x) || isnan(a.confidence)) {
        a = emptyAgent();
    }
    bool active = agentActive(a);

    // ---- phase 1 + 2: association (reads only; no writes before the barrier)
    int best = -1;
    float bestD = max(assoc_radius, 0.001);
    if (active) {
        [loop] for (uint c = 0u; c < nCorners; ++c) {
            float2 op = float2(_Data0[c].x, _Data0[c].y) * inv;
            float d = distance(a.position, op);
            if (d < bestD) { bestD = d; best = (int)c; }
        }
        if (best >= 0) {
            float2 op = float2(_Data0[best].x, _Data0[best].y) * inv;
            [loop] for (uint j = 0u; j < AGENT_SLOTS; ++j) {
                if (j == i) continue;
                Agent o = Agents[j];
                if (!agentActive(o)) continue;
                if (distance(o.position, op) < bestD) { best = -1; break; }
            }
        }
    }

    // every lane has finished reading the agent buffer
    GroupMemoryBarrierWithGroupSync();

    // ---- phase 3: update -----------------------------------------------------
    if (active && best >= 0) {
        uint dummy;
        InterlockedOr(gClaim[best], 1u, dummy);

        float2 op = float2(_Data0[best].x, _Data0[best].y) * inv;
        float resp = _Data0[best].response;

        float follow = saturate(max(track_stiffness, 0.01) * dt * 6.0);
        float2 delta = op - a.position;
        a.velocity = lerp(a.velocity, delta / max(dt, 1e-4), follow);
        a.position += delta * follow;
        a.scale = lerp(a.scale, saturate(resp / max(response_norm, 0.01)), saturate(dt * 6.0));
        a.confidence = saturate(a.confidence + dt * confirm_rate);
        a.flags |= AGENT_MATCHED;
        a.source_index = (uint)best;
    } else if (active) {
        a.position += a.velocity * dt * coast;
        a.confidence -= dt * decay_rate;
        a.flags &= ~AGENT_MATCHED;
        a.source_index = 0xFFFFFFFFu;
        if (a.confidence <= 0.0) {
            a.flags &= ~AGENT_ACTIVE;
            a.confidence = 0.0;
        }
    }

    if (agentActive(a)) {
        a.age += dt;
        if (length(a.velocity) > 1e-5) a.angle = atan2(a.velocity.y, a.velocity.x);
        a.aux.y = max(a.aux.y, a.confidence);
        a.aux.z += length(a.velocity) * dt;

        // colony membership: which macro region (blob) contains this nucleus
        uint colony = 0u;
        [loop] for (uint b = 0u; b < nBlobs; ++b) {
            float2 lo = float2(_Data1[b].x1, _Data1[b].y1) * inv;
            float2 hi = float2(_Data1[b].x2, _Data1[b].y2) * inv;
            if (all(a.position >= lo) && all(a.position <= hi)) { colony = b + 1u; break; }
        }
        a.aux.w = (float)colony;
    }

    Agents[i] = a;
    gActive[i] = agentActive(a) ? 1u : 0u;
    GroupMemoryBarrierWithGroupSync();

    // ---- phase 4: spawn on unclaimed observations ---------------------------
    if (i == 0u) {
        uint slot = 0u;
        [loop] for (uint c = 0u; c < nCorners; ++c) {
            if (gClaim[c] != 0u) continue;
            if (_Data0[c].response < spawn_response) continue;
            [loop] while (slot < AGENT_SLOTS && gActive[slot] != 0u) slot++;
            if (slot >= AGENT_SLOTS) break;

            float respawn = Agents[slot].aux.x + 1.0;
            Agent n = emptyAgent();
            n.position = float2(_Data0[c].x, _Data0[c].y) * inv;
            n.scale = saturate(_Data0[c].response / max(response_norm, 0.01));
            n.confidence = saturate(spawn_confidence);
            n.stable_id = slot * 4096u + (uint)respawn;
            n.source_index = c;
            n.flags = AGENT_ACTIVE | AGENT_MATCHED;
            n.aux = float4(respawn, saturate(spawn_confidence), 0.0, 0.0);
            Agents[slot] = n;
            gActive[slot] = 1u;
        }
    }
}
