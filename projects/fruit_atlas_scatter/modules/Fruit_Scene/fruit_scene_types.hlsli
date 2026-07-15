#ifndef FRUIT_SCENE_TYPES_HLSLI
#define FRUIT_SCENE_TYPES_HLSLI

static const float FRUIT_TWO_PI = 6.28318530718;

struct CardOverride {
    float3 offset;
    float rotation;
    float scale;
    uint object_id;
    float marker;
    float pad;
};

struct CardEditState {
    float mode;
    float active_id;
    float dragging;
    float command;
    float2 pointer;
    float2 start_pointer;
    float3 snapshot_offset;
    float snapshot_rotation;
    float snapshot_scale;
    float3 pad;
};

float hash1(float n) { return frac(sin(n * 91.713 + scatter_seed * 17.13) * 43758.5453); }
float signedHash(float n) { return hash1(n) * 2.0 - 1.0; }

float fruitLife(uint index, float sequence, uint liveSlots) {
    float stagger = ((float)index + hash1(sequence + 2.0) * 0.35) / max((float)liveSlots, 1.0);
    return frac(phase + _Time * spawn_rate + stagger);
}

float3 fruitTrajectory(uint index, float life, float ageRank) {
    float xSeed = signedHash(index + 1.3);
    float ySeed = signedHash(index + 9.7);
    float zSeed = signedHash(index + 17.1);
    float energy = max(0.05, motion_energy);
    uint mode = (uint)clamp(scene_mode, 0, 2);

    if (mode == 0u) {
        float z = lerp(tunnel_depth, -3.15 + camera_push * 0.55, life);
        float radius = 1.55 + hash1(index + 3.0) * 3.15;
        float laneAngle = index * 2.39996 + signedHash(index + 27.0) * 0.22;
        float drift = sin(life * FRUIT_TWO_PI + index * 1.73) * 0.08 * energy;
        float x = cos(laneAngle + drift) * radius;
        float y = sin(laneAngle + drift) * radius * 0.60 + ySeed * 0.35;
        x += wind * sin(life * 3.14159265) * 0.45;
        return float3(x, y, z);
    }

    if (mode == 1u) {
        float floorY = -2.65 + ageRank * 0.035;
        float y = lerp(5.5 + hash1(index) * 2.0, floorY, life);
        float impact = saturate((life - 0.66) / 0.34);
        float bounceArc = abs(sin(impact * 3.5 * FRUIT_TWO_PI)) * exp(-impact * 4.0) * bounce * 2.2;
        y = max(y, floorY + bounceArc);
        float x = xSeed * 4.8 + wind * life * life * 2.0;
        float z = zSeed * 3.0 - 1.5 + camera_push * sin(life * FRUIT_TWO_PI);
        return float3(x, y, z);
    }

    float angle = life * FRUIT_TWO_PI * (0.35 + spin) + index * 2.39996;
    float ring = 2.0 + hash1(index + 7.0) * 3.2;
    float3 p = float3(cos(angle) * ring, sin(angle * 1.17) * ring * 0.45, sin(angle) * ring - 2.0);
    p.x += wind * sin(angle * 2.0);
    return p;
}

float fruitScale(uint slot, float life, CardOverride edit) {
    float perspectiveScale = scene_mode == 0 ? 1.0 : lerp(0.72, 1.18, life);
    float sizeJitter = lerp(0.76, 1.20, hash1(slot + 31.0));
    return card_scale * sizeJitter * perspectiveScale * max(edit.scale, 0.05);
}

float2 fruitProject(float3 world) {
    float4 clip = mul(_ViewProjMatrix, float4(world, 1.0));
    if (abs(clip.w) < 1e-5) return float2(-1000.0, -1000.0);
    float2 ndc = clip.xy / clip.w;
    return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

#endif
