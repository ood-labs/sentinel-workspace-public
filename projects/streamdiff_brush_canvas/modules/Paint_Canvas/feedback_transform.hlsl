struct PosterPixel {
    float4 color;
    float4 meta;
};

StructuredBuffer<PosterPixel> Poster : register(t0);
StructuredBuffer<float4> PaintState : register(t1);
StructuredBuffer<float4> KickEnvelope : register(t2);
RWStructuredBuffer<PosterPixel> OutputBuffer : register(u0);

static const uint PC_WIDTH = 1080u;
static const uint PC_HEIGHT = 1350u;

int2 pcClampPixel(int2 pixel)
{
    return clamp(pixel, int2(0, 0), int2((int)PC_WIDTH - 1, (int)PC_HEIGHT - 1));
}

PosterPixel pcReadPoster(int2 pixel)
{
    int2 safePixel = pcClampPixel(pixel);
    return Poster[(uint)safePixel.y * PC_WIDTH + (uint)safePixel.x];
}

PosterPixel pcLerpPoster(PosterPixel a, PosterPixel b, float t)
{
    PosterPixel result;
    result.color = lerp(a.color, b.color, t);
    result.meta = lerp(a.meta, b.meta, t);
    return result;
}

PosterPixel pcSamplePoster(float2 uv)
{
    float2 pixelPosition = uv * float2(PC_WIDTH, PC_HEIGHT) - 0.5;
    int2 basePixel = int2(floor(pixelPosition));
    float2 fraction = frac(pixelPosition);
    PosterPixel p00 = pcReadPoster(basePixel);
    PosterPixel p10 = pcReadPoster(basePixel + int2(1, 0));
    PosterPixel p01 = pcReadPoster(basePixel + int2(0, 1));
    PosterPixel p11 = pcReadPoster(basePixel + int2(1, 1));
    return pcLerpPoster(
        pcLerpPoster(p00, p10, fraction.x),
        pcLerpPoster(p01, p11, fraction.x),
        fraction.y);
}

float pcMirrorCoordinate(float value)
{
    float wrapped = frac(value * 0.5) * 2.0;
    return 1.0 - abs(wrapped - 1.0);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= PC_WIDTH || id.y >= PC_HEIGHT) return;
    uint index = id.y * PC_WIDTH + id.x;

    if (feedback_enabled == 0) {
        OutputBuffer[index] = Poster[index];
        return;
    }

    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float2 uv = ((float2)id.xy + 0.5) / float2(PC_WIDTH, PC_HEIGHT);
    float aspect = (float)PC_WIDTH / (float)PC_HEIGHT;
    float2 pivot = feedback_pivot;
    float2 position = float2((uv.x - pivot.x) * aspect, uv.y - pivot.y);
    float kickAmount = saturate(KickEnvelope[0].x);
    float kick = lerp(1.0, max(feedback_kick, 1.0), kickAmount);
    float gain = max(feedback_control_gain, 0.0) * kick;

    position -= float2(feedback_pan.x * aspect, feedback_pan.y)
        * (dt * gain);

    float angle = radians(feedback_rotation_speed) * dt * kick;
    float cs = cos(angle);
    float sn = sin(angle);
    position = float2(
        cs * position.x + sn * position.y,
        -sn * position.x + cs * position.y);

    float master = max(feedback_control_gain, 0.0);
    float zoomRate = feedback_zoom_speed * master * kick
        + kick_zoom * kickAmount * master;
    float zoomFactor = exp2(zoomRate * 2.0 * dt);
    position /= max(zoomFactor, 0.0001);

    float2 sampleUv = pivot + float2(position.x / aspect, position.y);
    float inside = step(0.0, sampleUv.x) * step(sampleUv.x, 1.0)
        * step(0.0, sampleUv.y) * step(sampleUv.y, 1.0);

    int edgeMode = clamp(feedback_edge_mode, 0, 3);
    if (edgeMode == 1) {
        sampleUv = saturate(sampleUv);
    } else if (edgeMode == 2) {
        sampleUv = frac(sampleUv);
    } else if (edgeMode == 3) {
        sampleUv = float2(
            pcMirrorCoordinate(sampleUv.x),
            pcMirrorCoordinate(sampleUv.y));
    }

    PosterPixel transformed = pcSamplePoster(saturate(sampleUv));
    if (edgeMode == 0) {
        transformed.color *= inside;
        transformed.meta.y *= inside;
    }

    float colorDecay = exp(-max(feedback_fade, 0.0) * dt);
    float depthDecay = exp(-max(depth_fade, 0.0) * dt);
    transformed.color *= colorDecay;
    transformed.meta.y *= depthDecay;
    OutputBuffer[index] = transformed;
}
