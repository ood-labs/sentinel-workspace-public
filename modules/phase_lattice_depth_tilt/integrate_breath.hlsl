struct BreathState
{
    float breath_phase;
    float asymmetry_phase;
    float rupture_phase;
    float drift_phase;
    float valid;
    float eclipse_phase;
    float pad1;
    float pad2;
};

StructuredBuffer<BreathState> Previous : register(t0);
RWStructuredBuffer<BreathState> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    BreathState prior = Previous[0];
    float breathPhase = prior.valid > 0.5 ? prior.breath_phase : 0.0;
    breathPhase = frac(
        breathPhase + max(breath_rate, 0.0) * max(_DeltaTime, 0.0));
    float asymmetryPhase = prior.valid > 0.5 ? prior.asymmetry_phase : 0.37;
    asymmetryPhase = frac(
        asymmetryPhase + max(asymmetry_rate, 0.0) * max(_DeltaTime, 0.0));
    float rupturePhase = prior.valid > 0.5 ? prior.rupture_phase : 0.08;
    rupturePhase = frac(
        rupturePhase + max(rupture_rate, 0.0) * max(_DeltaTime, 0.0));
    float driftPhase = prior.valid > 0.5 ? prior.drift_phase : 0.62;
    driftPhase = frac(
        driftPhase + max(drift_rate, 0.0) * max(_DeltaTime, 0.0));
    float eclipsePhase = prior.valid > 0.5 ? prior.eclipse_phase : 0.18;
    eclipsePhase = frac(
        eclipsePhase + max(eclipse_rate, 0.0) * max(_DeltaTime, 0.0));

    BreathState current;
    current.breath_phase = breathPhase;
    current.asymmetry_phase = asymmetryPhase;
    current.rupture_phase = rupturePhase;
    current.drift_phase = driftPhase;
    current.valid = 1.0;
    current.eclipse_phase = eclipsePhase;
    current.pad1 = 0.0;
    current.pad2 = 0.0;
    OutputBuffer[0] = current;
}
