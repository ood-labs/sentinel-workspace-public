// AUTOPSIA — compositor clock. Integrates phase so changing the rate never
// retroactively rescales the band's history.
RWStructuredBuffer<float4> Clock : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 c = Clock[0];
    if (c.w < 0.5 || isnan(c.x)) c = float4(0.0, 0.0, 0.0, 1.0);
    float dt = min(_DeltaTime, 0.05);
    c.x = frac(c.x + max(sweep_rate, 0.0) * dt);
    c.y += dt;
    Clock[0] = c;
}
