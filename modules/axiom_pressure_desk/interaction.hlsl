#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

RWStructuredBuffer<GestureField> OutputBuffer : register(u0);

GestureField makeField(float2 position, float2 vectorValue, float radius, float strength, float mode, float active)
{
    GestureField field;
    field.position = position;
    field.direction = vectorValue;
    field.radius = radius;
    field.strength = strength;
    field.mode = mode;
    field.active = active;
    return field;
}

void initializeState(out GestureField fields[4])
{
    fields[0] = makeField(float2(0.31, 0.40), float2(1.0, 0.0), default_radius * 1.12, touch_strength * 0.78, 0.0, 1.0);
    fields[1] = makeField(float2(0.69, 0.43), normalize(float2(0.8, -0.6)), default_radius * 0.92, touch_strength * 0.66, 1.0, 1.0);
    fields[2] = makeField(float2(0.52, 0.70), float2(0.0, -1.0), default_radius * 1.28, -touch_strength * 0.84, 2.0, 1.0);
    fields[3] = makeField(float2(0.50, 0.50), float2(1.0, 0.0), default_radius, touch_strength, 0.0, 1.0);
}

void setMode(inout GestureField controller, float mode)
{
    controller.mode = mode;
    controller.active = 1.0;
}

void clearAuthoredFields(inout GestureField fields[4])
{
    fields[0].active = 0.0;
    fields[1].active = 0.0;
    fields[2].active = 0.0;
}

void applyPointer(inout GestureField fields[4], float2 panelPosition, bool drag)
{
    float4 stage = pressureStageRect(_Resolution.xy);
    if (!insidePressureStage(panelPosition, stage)) return;

    GestureField controller = fields[3];
    uint index = (uint)clamp(round(controller.mode), 0.0, 2.0);
    float2 stagePosition = panelToStage(panelPosition, stage);
    float2 delta = stagePosition - controller.position;
    float deltaLength = length(delta);
    float2 direction = deltaLength > 1e-4 ? delta / deltaLength : fields[index].direction;

    fields[index].position = stagePosition;
    fields[index].direction = direction;
    fields[index].radius = controller.radius;
    fields[index].strength = index == 2u ? -abs(touch_strength) : abs(touch_strength);
    if (index == 1u && drag) fields[index].strength *= 1.15;
    fields[index].mode = (float)index;
    fields[index].active = 1.0;
    fields[3].position = stagePosition;
    fields[3].direction = direction;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    GestureField fields[4];
    [unroll]
    for (uint i = 0u; i < 4u; ++i) fields[i] = OutputBuffer[i];
    if (abs(fields[3].mode) > 2.1 || fields[3].radius <= 0.0 || fields[3].radius > 1.0)
    {
        initializeState(fields);
    }

    fields[3].radius = clamp(fields[3].radius * (1.0 + _ViewportWheelDelta * 0.11), 0.025, 0.35);
    fields[3].strength = touch_strength;

    uint down = (suiInteraction(UI_INDEX_PRESS_MODE).down ? 1u : 0u)
              | (suiInteraction(UI_INDEX_SHEAR_MODE).down ? 2u : 0u)
              | (suiInteraction(UI_INDEX_VOID_MODE).down ? 4u : 0u)
              | (suiInteraction(UI_INDEX_CLEAR_FIELDS).down ? 8u : 0u);
    uint previousDown = (uint)round(fields[3].active) >> 1u;
    uint pressed = down & ~previousDown;
    fields[3].active = 1.0 + (float)(down << 1u);
    if ((pressed & 1u) != 0u) setMode(fields[3], 0.0);
    if ((pressed & 2u) != 0u) setMode(fields[3], 1.0);
    if ((pressed & 4u) != 0u) setMode(fields[3], 2.0);
    if ((pressed & 8u) != 0u) clearAuthoredFields(fields);

    uint count = min(_ViewportEventCount, 64u);
    [loop]
    for (uint i = 0u; i < count; ++i)
    {
        ViewportEvent eventRecord = _ViewportEvents[i];
        if (eventRecord.type == 4u && eventRecord.phase == 1u)
        {
            if (eventRecord.code == 16u) setMode(fields[3], 0.0); // P
            if (eventRecord.code == 19u) setMode(fields[3], 1.0); // S
            if (eventRecord.code == 22u) setMode(fields[3], 2.0); // V
            if (eventRecord.code == 24u) clearAuthoredFields(fields); // X
        }

        bool click = eventRecord.type == 5u && eventRecord.code == 1u && eventRecord.phase == 7u;
        bool drag = eventRecord.type == 5u && eventRecord.code == 3u && eventRecord.phase != 8u;
        bool pressEvent = eventRecord.type == 2u && eventRecord.phase == 1u && eventRecord.code == 0u;
        if (click || drag || pressEvent) applyPointer(fields, eventRecord.position, drag);
    }

    [unroll]
    for (uint i = 0u; i < 4u; ++i) OutputBuffer[i] = fields[i];
}
