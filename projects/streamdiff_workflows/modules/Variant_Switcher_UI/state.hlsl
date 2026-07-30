#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

struct SwitcherState
{
    float selected;
    float elapsed;
    float auto_latch;
    float one_latch;
    float two_latch;
    float three_latch;
    float cycle_pulse;
    float reserved;
};

RWStructuredBuffer<SwitcherState> OutputState : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    SwitcherState prior = OutputState[0];
    SwitcherState next = prior;

    float oneDown = suiInteraction(UI_INDEX_SELECT_1).down ? 1.0 : 0.0;
    float twoDown = suiInteraction(UI_INDEX_SELECT_2).down ? 1.0 : 0.0;
    float threeDown = suiInteraction(UI_INDEX_SELECT_3).down ? 1.0 : 0.0;
    bool chooseOne = oneDown > 0.5 && prior.one_latch <= 0.5;
    bool chooseTwo = twoDown > 0.5 && prior.two_latch <= 0.5;
    bool chooseThree = threeDown > 0.5 && prior.three_latch <= 0.5;
    bool autoActive = auto_mode != 0;
    bool autoStarted = autoActive && prior.auto_latch <= 0.5;

    next.one_latch = oneDown;
    next.two_latch = twoDown;
    next.three_latch = threeDown;
    next.auto_latch = autoActive ? 1.0 : 0.0;
    next.cycle_pulse *= pow(0.08, min(max(_DeltaTime, 0.0), 0.1) * 60.0);

    if (chooseOne)
    {
        next.selected = 0.0;
        next.elapsed = 0.0;
    }
    else if (chooseTwo)
    {
        next.selected = 1.0;
        next.elapsed = 0.0;
    }
    else if (chooseThree)
    {
        next.selected = 2.0;
        next.elapsed = 0.0;
    }

    if (autoStarted)
        next.elapsed = 0.0;

    if (autoActive)
    {
        float dt = min(max(_DeltaTime, 0.0), 0.1);
        next.elapsed += dt;
        float interval = max(cycle_seconds, 0.25);
        if (next.elapsed >= interval)
        {
            next.elapsed = fmod(next.elapsed, interval);
            next.selected = fmod(floor(next.selected + 0.5) + 1.0, 3.0);
            next.cycle_pulse = 1.0;
        }
    }
    else
    {
        next.elapsed = 0.0;
    }

    next.selected = clamp(floor(next.selected + 0.5), 0.0, 2.0);
    OutputState[0] = next;
}
