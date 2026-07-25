#ifndef AU_STABILIZER_TYPES_HLSLI
#define AU_STABILIZER_TYPES_HLSLI

// AUTOPSIA — persistent agent. 64 bytes. Frozen contract consumed by
// au_topology and every downstream renderer.
//
// A raw Features corner is an anonymous, flickering, per-frame observation.
// An Agent is a THING the instrument believes in: it has identity that survives
// across frames, a velocity, an age, and a confidence that must be earned and
// can be lost. Everything expressive downstream depends on that persistence.
struct Agent {
    float2 position;      // normalized plate coordinates
    float2 velocity;      // normalized units / second
    float scale;          // 0..1, from corner response
    float confidence;     // 0..1, earned by repeated association
    float angle;          // heading, radians
    float age;            // seconds since spawn
    uint stable_id;       // survives across frames; slot * 4096 + respawn count
    uint kind;            // 0 = nucleus
    uint source_index;    // observation index this frame, 0xFFFFFFFF if coasting
    uint flags;           // bit0 = active, bit1 = matched this frame
    float4 aux;           // x respawn count, y peak confidence, z path length, w colony
};

#define AGENT_ACTIVE  1u
#define AGENT_MATCHED 2u
#define AGENT_SLOTS   64u

bool agentActive(Agent a)  { return (a.flags & AGENT_ACTIVE) != 0u; }
bool agentMatched(Agent a) { return (a.flags & AGENT_MATCHED) != 0u; }

Agent emptyAgent() {
    Agent a;
    a.position = float2(0.5, 0.5);
    a.velocity = float2(0.0, 0.0);
    a.scale = 0.0;
    a.confidence = 0.0;
    a.angle = 0.0;
    a.age = 0.0;
    a.stable_id = 0u;
    a.kind = 0u;
    a.source_index = 0xFFFFFFFFu;
    a.flags = 0u;
    a.aux = float4(0.0, 0.0, 0.0, 0.0);
    return a;
}

#endif
