struct PosterPixel {
    float4 color;
    float4 meta;
};
RWStructuredBuffer<PosterPixel> OutputBuffer : register(u0);
StructuredBuffer<float4> PaintState : register(t3);
StructuredBuffer<PosterPixel> PreviousPoster : register(t4);

static const uint PC_WIDTH = 1080u;
static const uint PC_HEIGHT = 1350u;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= PC_WIDTH || id.y >= PC_HEIGHT) return;
    uint index = id.y * PC_WIDTH + id.x;
    float2 uv = ((float2)id.xy + 0.5) / float2(PC_WIDTH, PC_HEIGHT);
    float4 ctrl = PaintState[0];
    float4 meta = PaintState[18];
    PosterPixel pixel = PreviousPoster[index];
    bool fresh = abs(ctrl.x - pixel.meta.x) > 0.25;
    float4 canvas = pixel.color;
    if (fresh && meta.x > 0.5) {
        canvas = 0.0;
        pixel.meta.y = 0.0;
    }
    if (fresh && meta.x <= 0.5) {
        uint queueCount = min((uint)round(meta.z), 16u);
        [loop] for (uint q = 0u; q < queueCount; ++q) {
            float4 stamp = PaintState[2u + q];
            if (abs(stamp.w - ctrl.x) > 0.25) continue;
            float2 p = (uv - stamp.xy) * float2((float)PC_WIDTH / (float)PC_HEIGHT, 1.0);
            // Sampling uses the inverse transform: negate the requested screen-space
            // angle so positive rotation and stroke tangents rotate the visible stamp
            // in the same direction as the control.
            float a = radians(-stamp.z);
            p = mul(float2x2(cos(a), -sin(a), sin(a), cos(a)), p);
            float2 local = p / max(ctrl.y * float2(brush_aspect, 1.0), 0.0001) + subject_anchor;
            if (all(local >= 0.0) && all(local <= 1.0)) {
                float3 subject = _Tex0.SampleLevel(LinearSampler, local, 0).rgb;
                float3 matteRgb = _Tex1.SampleLevel(LinearSampler, local, 0).rgb;
                float matte = max(matteRgb.r, max(matteRgb.g, matteRgb.b));
                float border = 1.0 - max(abs(local.x - 0.5) * 2.0, abs(local.y - 0.5) * 2.0);
                float edge = smoothstep(0.0, max(feather, 0.001), border);
                float alpha = saturate(matte * edge * opacity);
                float3 premul = subject * alpha;
                canvas.rgb = premul + canvas.rgb * (1.0 - alpha);
                canvas.a = alpha + canvas.a * (1.0 - alpha);

                float sourceDepth = _Tex2.SampleLevel(LinearSampler, local, 0).r;
                float shapedDepth = saturate(
                    lerp(depth_value, sourceDepth, depth_source_mix)
                    * depth_gain + depth_offset);
                if (depth_blend_mode == 0) {
                    pixel.meta.y = lerp(pixel.meta.y, shapedDepth, alpha);
                } else if (depth_blend_mode == 1) {
                    pixel.meta.y = max(pixel.meta.y, shapedDepth * alpha);
                } else {
                    pixel.meta.y = saturate(pixel.meta.y + shapedDepth * alpha);
                }
            }
        }
    }
    pixel.color = canvas;
    pixel.meta.x = ctrl.x;
    OutputBuffer[index] = pixel;
}
