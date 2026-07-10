struct SceneGlobals { float phase; float pulse_a; float pulse_b; float pulse_c; float pulse_d; float2 drift; float active; };
RWStructuredBuffer<SceneGlobals> SceneOut : register(u0);

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float p = frac(phase + _Time * animation_speed / max(loop_seconds, 0.1));
    if (paused != 0) p = frac(phase);
    float a = p * 6.28318530718;
    SceneGlobals s;
    s.phase = p;
    s.pulse_a = 0.5 + 0.5 * sin(a);
    s.pulse_b = 0.5 + 0.5 * sin(a * 2.0 + 1.2);
    s.pulse_c = 0.5 + 0.5 * sin(a * 3.0 + 2.4);
    s.pulse_d = 0.5 + 0.5 * cos(a);
    s.drift = float2(sin(a), cos(a * 2.0)) * drift_amount;
    s.active = 1.0;
    SceneOut[0] = s;
}
