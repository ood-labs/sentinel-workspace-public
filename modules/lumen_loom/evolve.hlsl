RWTexture2D<float4> OutputUAV : register(u0);

float2 rotate2(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - center) * float2(aspect, 1.0);

    float2 noiseP = p * (1.7 + density * 2.6) + float2(_Time * 0.037 * speed, -_Time * 0.029 * speed);
    float n = fbm2D(noiseP, 5);
    float angle = n * 6.2831853 * curl + sin(_Time * 0.13 * speed + length(p) * 8.0) * 0.35;
    float2 drift = rotate2(normalize(p + float2(0.001, 0.0)), 1.5707963 + angle) * (0.0012 + speed * 0.0017);
    float2 prevUv = frac(uv - drift / float2(aspect, 1.0));
    float4 prev = _Tex0.SampleLevel(LinearSampler, prevUv, 0);

    float ringPhase = length(p) * (18.0 + density * 24.0) - _Time * (1.4 + speed * 2.1) + n * 7.0;
    float filaments = pow(saturate(0.5 + 0.5 * sin(ringPhase)), 12.0);
    float cells = smoothstep(0.62, 0.90, fbm2D(p * (5.0 + density * 8.0) + n * 2.0, 4));
    float pointer = 0.0;
    if (_Mouse.z > 0.0) {
        float2 md = (uv - _Mouse.xy) * float2(aspect, 1.0);
        pointer = exp(-dot(md, md) * 180.0) * 1.8;
    }

    float inject = filaments * (0.20 + cells * 0.90) + pointer;
    float keep = pow(saturate(feedback), _DeltaTime * 60.0);
    float energy = prev.r * keep + inject * _DeltaTime * (7.0 + speed * 3.0);
    float phase = frac(prev.g + _DeltaTime * (0.025 + speed * 0.045) + inject * 0.002);
    float eps = 1.5 / max(_Resolution.y, 1.0);
    float edgeNow = abs(fbm2D(noiseP + float2(eps, 0.0), 5) - n) + abs(fbm2D(noiseP + float2(0.0, eps), 5) - n);
    float edge = lerp(prev.b, edgeNow * 18.0, saturate(_DeltaTime * 8.0));
    OutputUAV[id.xy] = float4(min(energy, 5.0), phase, edge, 1.0);
}
