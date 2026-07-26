// AUTOPSIA — specimen clock. Integrates drift phase; never multiplies a live rate by absolute time.
RWStructuredBuffer<float4> ClockOut : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 c = ClockOut[0];
    if (c.w < 0.5 || isnan(c.x)) {
        c = float4(0.0, 0.0, 0.0, 1.0);
    }
    float dt = min(_DeltaTime, 0.05);
    c.x = frac(c.x + max(drift_speed, 0.0) * dt);          // primary drift phase
    c.y = frac(c.y + max(drift_speed, 0.0) * dt * 0.371);  // slow secondary phase
    c.z += dt;                                             // absolute elapsed seconds
    ClockOut[0] = c;
}
