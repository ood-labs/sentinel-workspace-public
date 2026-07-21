StructuredBuffer<float4> InteractionState : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float SM_PI = 3.14159265359;
static const float SM_TAU = 6.28318530718;

float smRoundBox(float2 p, float2 bounds, float radius)
{
    float2 q = abs(p) - bounds + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float smCapsule(float2 p, float halfLength, float radius)
{
    p.x -= clamp(p.x, -halfLength, halfLength);
    return length(p) - radius;
}

float smTriangle(float2 p)
{
    const float k = 1.7320508;
    p.x = abs(p.x) - 1.0;
    p.y += 0.5773503;
    if (p.x + k * p.y > 0.0)
        p = float2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y);
}

float smStar(float2 p, float points, float inset)
{
    float angleValue = atan2(p.y, p.x);
    float wave = 0.5 + 0.5 * cos(angleValue * points);
    float radius = lerp(inset, 1.0, pow(wave, 2.4));
    return length(p) - radius;
}

float smShapeDistance(float2 p)
{
    int mode = clamp(shape_mode, 0, 5);
    if (mode == 0) {
        float exponentValue = lerp(2.0, 7.0, character_a);
        float superellipse = pow(pow(abs(p.x), exponentValue) + pow(abs(p.y), exponentValue), 1.0 / exponentValue);
        return superellipse - lerp(0.78, 1.0, character_b);
    }
    if (mode == 1)
        return smRoundBox(p, float2(0.82, 0.82), lerp(0.04, 0.76, character_a));
    if (mode == 2)
        return smCapsule(p, lerp(0.10, 0.74, character_a), lerp(0.30, 0.72, character_b));
    if (mode == 3) {
        float triangleDistance = smTriangle(p * lerp(0.92, 1.18, character_a));
        return triangleDistance - lerp(0.0, 0.10, character_b);
    }
    if (mode == 4)
        return smStar(p, floor(lerp(4.0, 11.99, character_a)), lerp(0.20, 0.72, character_b));

    float angleValue = atan2(p.y, p.x);
    float lobes = floor(lerp(3.0, 10.99, character_a));
    float wobble = lerp(0.04, 0.34, character_b);
    float radius = 0.84 + wobble * (0.68 * sin(angleValue * lobes + 1.7) + 0.32 * sin(angleValue * (lobes + 3.0) - 0.8));
    return length(p) - radius;
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;

    float2 uv = ((float2)id.xy + 0.5) / float2(width, height);
    float4 interaction = InteractionState[0];
    float2 effectiveCenter = interaction.xy;
    float effectiveSize = interaction.z;
    float2 q = uv - effectiveCenter;
    float rotationValue = radians(rotation);
    float2x2 shapeRotation = float2x2(cos(rotationValue), -sin(rotationValue), sin(rotationValue), cos(rotationValue));
    q = mul(shapeRotation, q);
    q.x /= max(aspect, 0.05);
    q /= max(effectiveSize, 0.01);

    float distanceValue = smShapeDistance(q);
    float phase = interaction.w;
    float displacementRotation = radians(pattern_angle);
    float2 displacementDirection = float2(cos(displacementRotation), sin(displacementRotation));
    float2 displacementAcross = float2(-displacementDirection.y, displacementDirection.x);
    float2 displacementPoint = float2(dot(q, displacementDirection), dot(q, displacementAcross));
    float frequency = max(displacement_scale, 0.01);
    float displacement = 0.0;
    int displacementType = clamp(displacement_mode, 0, 3);
    if (displacementType == 0)
        displacement = sin(SM_TAU * (displacementPoint.x * frequency * 0.22 - phase));
    else if (displacementType == 1)
        displacement = sin(atan2(displacementPoint.y, displacementPoint.x) * frequency - phase * SM_TAU);
    else if (displacementType == 2)
        displacement = sin(SM_TAU * (length(displacementPoint) * frequency * 0.20 - phase));
    else
        displacement = 0.62 * sin(displacementPoint.x * frequency + phase * SM_TAU)
                     + 0.38 * sin(displacementPoint.y * frequency * 1.37 - phase * SM_TAU * 0.73);
    distanceValue += displacement * displacement_amount;

    float softness = max(edge_softness / max(effectiveSize, 0.01), 0.0005);
    float mask = smoothstep(softness, -softness, distanceValue);
    float inside = saturate(-distanceValue * 1.5);

    float depth = inside;
    int profile = clamp(depth_profile, 0, 2);
    if (profile == 0) depth = sqrt(inside);
    else if (profile == 1) depth = smoothstep(0.0, 0.55, inside);
    else depth = inside * inside;
    depth = saturate(depth * depth_strength) * mask;

    float guide = mask;
    OutputUAV[id.xy] = float4(guide.xxx, depth);
}
