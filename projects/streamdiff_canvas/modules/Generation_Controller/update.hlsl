RWStructuredBuffer<float4> State : register(u0);

float wrapPrompt(float value)
{
    float count = max((float)prompt_count, 1.0);
    float relative = value - prompt_start;
    return prompt_start + relative - floor(relative / count) * count;
}

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 outputState = State[0];
    float4 timingState = State[1];
    float4 modeState = State[2];
    float4 stampState = State[3];

    bool initialized = modeState.x > 0.5;
    float currentMode = clamp(round(mode), 0.0, 2.0);
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    if (!initialized) {
        outputState = float4(1.0, prompt_start, 0.0, 0.0);
        timingState = float4(0.0, 0.0, generate != 0 ? 1.0 : 0.0,
                            next_prompt != 0 ? 1.0 : 0.0);
        modeState = float4(1.0, currentMode, transport_run != 0 ? 1.0 : 0.0,
                           1.0 / max(stamp_rate, 0.5));
        stampState = float4(0.0, link_stamps != 0 ? 1.0 : 0.0, 0.0, 0.0);
    }

    bool generateValue = generate != 0;
    bool nextValue = next_prompt != 0;
    bool generateEdge = generateValue != (timingState.z > 0.5);
    bool nextEdge = nextValue != (timingState.w > 0.5);
    bool modeChanged = abs(currentMode - modeState.y) > 0.25;

    outputState.z = 0.0;
    if (modeChanged) {
        timingState.x = 0.0;
        timingState.y = 0.0;
    }

    if (nextEdge) {
        outputState.y = wrapPrompt(outputState.y + prompt_step);
        timingState.y = max(render_window, 0.02);
        if (link_stamps != 0) stampState.w = 1.0;
        outputState.z = 1.0;
        outputState.w += 1.0;
    }
    if (generateEdge) {
        timingState.y = max(render_window, 0.02);
        if (link_stamps != 0) stampState.w = 1.0;
        outputState.z = 1.0;
        outputState.w += 1.0;
    }

    bool running = transport_run != 0;
    if (currentMode < 0.5) {
        timingState.x = 0.0;
        timingState.y = max(timingState.y - dt, 0.0);
        outputState.x = timingState.y > 0.0 ? 0.0 : 1.0;
    }
    else if (currentMode < 1.5) {
        if (running) {
            timingState.x += dt;
            float interval = 1.0 / max(prompt_rate, 0.05);
            if (timingState.x >= interval) {
                float elapsedCycles = floor(timingState.x / interval);
                timingState.x -= elapsedCycles * interval;
                outputState.y = wrapPrompt(outputState.y + prompt_step * elapsedCycles);
                timingState.y = max(render_window, 0.02);
                if (link_stamps != 0) stampState.w = 1.0;
                outputState.z = 1.0;
                outputState.w += elapsedCycles;
            }
        }
        timingState.y = max(timingState.y - dt, 0.0);
        outputState.x = timingState.y > 0.0 ? 0.0 : 1.0;
    }
    else {
        timingState.x = 0.0;
        timingState.y = 0.0;
        if (running) {
            outputState.y = wrapPrompt(outputState.y + prompt_rate * dt);
            if (link_stamps != 0) {
                stampState.z += dt;
                float stampSeconds = 1.0 / max(stamp_rate, 0.5);
                if (stampState.z >= stampSeconds) {
                    float stampCount = floor(stampState.z / stampSeconds);
                    stampState.z -= stampCount * stampSeconds;
                    stampState.x += stampCount;
                }
            }
        }
        outputState.x = running ? 0.0 : 1.0;
    }

    if (currentMode < 1.5 && stampState.w > 0.5 && timingState.y <= 0.0) {
        stampState.x += 1.0;
        stampState.w = 0.0;
    }
    if (link_stamps == 0) {
        stampState.z = 0.0;
        stampState.w = 0.0;
    }

    outputState.y = wrapPrompt(outputState.y);
    timingState.z = generateValue ? 1.0 : 0.0;
    timingState.w = nextValue ? 1.0 : 0.0;
    modeState = float4(1.0, currentMode, running ? 1.0 : 0.0,
                       1.0 / max(stamp_rate, 0.5));
    stampState.y = link_stamps != 0 ? 1.0 : 0.0;

    State[0] = outputState;
    State[1] = timingState;
    State[2] = modeState;
    State[3] = stampState;
}
