// Fixed-cadence scalar sampler. The display rate may vary; the trace does not.
RWStructuredBuffer<float4> Scope : register(u0);

static const uint CAPACITY = 256u;
static const float INTERVAL = 1.0 / 60.0;
static const float MAGIC = 53091.0;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 meta = Scope[0];
    float4 rangeState = Scope[1];
    float x = signal;
    float dt = min(max(_DeltaTime, 0.0), 0.05);

    if (meta.w != MAGIC || isnan(meta.x)) {
        meta = float4(0.0, 0.0, 0.0, MAGIC);
        rangeState = float4(x, x, x, 0.0);
    }

    rangeState.z = x;

    meta.z += dt;
    if (meta.z >= INTERVAL) {
        uint writeIndex = (uint)meta.x % CAPACITY;
        Scope[2u + writeIndex] = float4(x, 0.0, 0.0, 0.0);
        meta.x = (float)((writeIndex + 1u) % CAPACITY);
        meta.y = min(meta.y + 1.0, (float)CAPACITY);
        meta.z = fmod(meta.z, INTERVAL);

        // Exact retained-window bounds. Releasing extrema made the vertical
        // range collapse toward the current sample; the next excursion then
        // clipped into a false flat plateau at the top or bottom.
        uint count = (uint)meta.y;
        float exactMin = x;
        float exactMax = x;
        [loop] for (uint i = 0u; i < count; ++i) {
            float v = Scope[2u + i].x;
            exactMin = min(exactMin, v);
            exactMax = max(exactMax, v);
        }
        rangeState.x = exactMin;
        rangeState.y = exactMax;
    }

    Scope[0] = meta;
    Scope[1] = rangeState;
}
