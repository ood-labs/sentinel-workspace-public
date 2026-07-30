#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

RWStructuredBuffer<DeckState> OutputBuffer : register(u0);

void deriveControls(inout DeckState state)
{
    state.energy = saturate(state.energy);
    state.warp = saturate(state.warp);
    state.topology = saturate(state.topology);
    state.relief = saturate(state.relief);
    state.memory = saturate(state.memory);
    state.archive = saturate(state.archive);
    state.glyphs = saturate(state.topology * 0.82 + state.relief * 0.18);
    state.signal_rate = state.energy;
    state.pulse_density = saturate(state.warp * 0.72 + state.energy * 0.28);
}

void applyPreset(inout DeckState state, uint preset)
{
    if (preset == 0u) // OBSERVE
    {
        state.energy = 0.28; state.warp = 0.18;
        state.topology = 0.42; state.relief = 0.34;
        state.memory = 0.18; state.archive = 0.15;
        state.quality = 0.0;
    }
    else if (preset == 1u) // SURGE
    {
        state.energy = 0.86; state.warp = 0.72;
        state.topology = 0.82; state.relief = 0.64;
        state.memory = 0.34; state.archive = 0.26;
        state.quality = 1.0;
    }
    else if (preset == 2u) // ARCHIVE
    {
        state.energy = 0.38; state.warp = 0.24;
        state.topology = 0.62; state.relief = 0.76;
        state.memory = 0.82; state.archive = 0.68;
        state.quality = 1.0;
    }
    else // RESET / BALANCED
    {
        state.energy = 0.48; state.warp = 0.28;
        state.topology = 0.58; state.relief = 0.54;
        state.memory = 0.30; state.archive = 0.24;
        state.quality = 1.0;
    }
    state.generation += 1.0;
}

void applyPointer(inout DeckState state, float2 p, uint pad)
{
    if (pad == 1u)
    {
        float2 v = padValue(p, energyPadRect());
        state.energy = v.x;
        state.warp = v.y;
    }
    else if (pad == 2u)
    {
        float2 v = padValue(p, structurePadRect());
        state.topology = v.x;
        state.relief = v.y;
    }
    else if (pad == 3u)
    {
        float2 v = padValue(p, memoryPadRect());
        state.memory = v.x;
        state.archive = v.y;
    }
    state.focus_x = p.x;
    state.focus_y = p.y;
    state.generation += 1.0;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    DeckState state = OutputBuffer[0];
    if (state.initialized < 0.5)
    {
        state.generation = 0.0;
        state.active_pad = 0.0;
        state.focus_x = 0.5;
        state.focus_y = 0.5;
        state.initialized = 1.0;
        applyPreset(state, 3u);
    }

    uint down = (suiInteraction(UI_INDEX_OBSERVE).down ? 1u : 0u)
              | (suiInteraction(UI_INDEX_SURGE).down ? 2u : 0u)
              | (suiInteraction(UI_INDEX_ARCHIVE).down ? 4u : 0u)
              | (suiInteraction(UI_INDEX_BALANCED).down ? 8u : 0u);
    uint previousDown = (uint)round(state.reserved);
    uint pressed = down & ~previousDown;
    state.reserved = (float)down;
    if ((pressed & 1u) != 0u) applyPreset(state, 0u);
    if ((pressed & 2u) != 0u) applyPreset(state, 1u);
    if ((pressed & 4u) != 0u) applyPreset(state, 2u);
    if ((pressed & 8u) != 0u) applyPreset(state, 3u);

    uint count = min(_ViewportEventCount, 64u);
    [loop]
    for (uint i = 0u; i < count; ++i)
    {
        ViewportEvent eventRecord = _ViewportEvents[i];
        if (eventRecord.type == 4u && eventRecord.phase == 1u)
        {
            if (eventRecord.code == 17u) applyPreset(state, 0u); // Q / OBSERVE
            if (eventRecord.code == 23u) applyPreset(state, 1u); // W / SURGE
            if (eventRecord.code == 5u)  applyPreset(state, 2u); // E / ARCHIVE
            if (eventRecord.code == 18u) applyPreset(state, 3u); // R / BALANCED
        }

        if (eventRecord.type != 5u || eventRecord.device != 0u) continue;
        float2 p = eventRecord.position;
        uint hoverPad = insideRect(p, energyPadRect()) ? 1u :
                        (insideRect(p, structurePadRect()) ? 2u :
                        (insideRect(p, memoryPadRect()) ? 3u : 0u));

        if (eventRecord.code == 1u && eventRecord.phase == 7u && hoverPad != 0u)
        {
            applyPointer(state, p, hoverPad);
        }
        if (eventRecord.code != 3u) continue;
        if (eventRecord.phase == 5u && hoverPad != 0u)
        {
            state.active_pad = (float)hoverPad;
            applyPointer(state, p, hoverPad);
        }
        else if ((eventRecord.phase == 6u || eventRecord.phase == 7u) && state.active_pad > 0.5)
        {
            applyPointer(state, p, (uint)round(state.active_pad));
            if (eventRecord.phase == 7u) state.active_pad = 0.0;
        }
        else if (eventRecord.phase == 8u)
        {
            state.active_pad = 0.0;
        }
    }

    deriveControls(state);
    if (state.generation > 100000.0) state.generation = 1.0;
    OutputBuffer[0] = state;
}
