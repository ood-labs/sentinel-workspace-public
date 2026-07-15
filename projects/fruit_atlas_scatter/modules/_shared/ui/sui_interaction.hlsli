#ifndef SENTINEL_SUI_INTERACTION_HLSLI
#define SENTINEL_SUI_INTERACTION_HLSLI

static const uint SUI_FLAG_HOVERED = 1u;
static const uint SUI_FLAG_DOWN = 2u;

struct SuiInteraction {
    uint flags;
    bool hovered;
    bool down;
};

uint suiPackedControlFlags(uint controlIndex) {
    uint4 packed = _ViewportControlFlags[controlIndex / 4u];
    uint lane = controlIndex & 3u;
    if (lane == 0u) return packed.x;
    if (lane == 1u) return packed.y;
    if (lane == 2u) return packed.z;
    return packed.w;
}

SuiInteraction suiInteraction(uint controlIndex) {
    SuiInteraction state;
    state.flags = suiPackedControlFlags(controlIndex);
    state.hovered = (state.flags & SUI_FLAG_HOVERED) != 0u;
    state.down = (state.flags & SUI_FLAG_DOWN) != 0u;
    return state;
}

SuiInteraction suiInteractionNone() {
    SuiInteraction state;
    state.flags = 0u;
    state.hovered = false;
    state.down = false;
    return state;
}

#endif

