struct ClockSignals
{
    float phase;
    float envelope;
    float pulse;
    float playing;
    float rate_value;
    float scrub_active;
    float cycle_sin;
    float cycle_cos;
};

StructuredBuffer<ClockSignals> _Signals : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float envelopeAt(float p)
{
    float attack = smoothstep(0.0, 0.10, p);
    float release = 1.0 - smoothstep(0.34, 0.94, p);
    float shoulder = 0.72 + 0.28 * smoothstep(0.10, 0.22, p);
    return saturate(attack * release * shoulder);
}

float lineMask(float value, float target, float width)
{
    return 1.0 - smoothstep(width, width * 2.0, abs(value - target));
}

float rectMask(float2 uv, float4 r, float feather)
{
    float2 lo = smoothstep(r.xy, r.xy + feather, uv);
    float2 hi = 1.0 - smoothstep(r.zw - feather, r.zw, uv);
    return lo.x * lo.y * hi.x * hi.y;
}

float borderMask(float2 uv, float4 r, float width)
{
    float outer = rectMask(uv, r, width);
    float inner = rectMask(uv, r + float4(width, width, -width, -width), width);
    return saturate(outer - inner);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float px = 1.0 / max(_Resolution.y, 1.0);
    ClockSignals s = _Signals[0];

    float3 background = float3(0.006, 0.007, 0.006);
    float3 neutral = float3(0.70, 0.72, 0.69);
    float3 bright = float3(0.96, 0.97, 0.93);
    float3 warm = float3(1.0, 0.34, 0.08);
    float3 col = background;

    float4 scope = float4(0.055, 0.12, 0.945, 0.73);
    float border = borderMask(uv, scope, px * 1.2);
    col = lerp(col, neutral * 0.42, border);

    float inScope = rectMask(uv, scope, px);
    float2 q = (uv - scope.xy) / (scope.zw - scope.xy);
    float grid = 0.0;
    grid += lineMask(frac(q.x * 8.0), 0.0, px * 1.5 * aspect);
    grid += lineMask(frac(q.y * 4.0), 0.0, px * 1.5);
    col += neutral * 0.065 * saturate(grid) * inScope;

    float expected = envelopeAt(saturate(q.x));
    float waveformY = 0.88 - expected * 0.68;
    float curve = lineMask(q.y, waveformY, px * 1.75 / max(scope.w - scope.y, 0.01));
    col = lerp(col, bright, curve * inScope);

    float playhead = lineMask(q.x, s.phase, px * 1.5 * aspect / max(scope.z - scope.x, 0.01));
    col = lerp(col, warm, playhead * inScope);

    float2 markerP = float2(s.phase, 0.88 - s.envelope * 0.68);
    float2 markerD = (q - markerP) * float2(aspect * (scope.z - scope.x), scope.w - scope.y);
    float marker = 1.0 - smoothstep(px * 4.0, px * 7.0, length(markerD));
    col = lerp(col, warm, marker * inScope);

    float4 playRect = float4(0.055, 0.79, 0.205, 0.93);
    float4 resetRect = float4(0.225, 0.79, 0.375, 0.93);
    float4 scrubRect = float4(0.395, 0.79, 0.585, 0.93);
    float4 sliderRect = float4(0.61, 0.79, 0.945, 0.93);

    float playFill = rectMask(uv, playRect, px) * (s.playing > 0.5 ? 0.22 : 0.04);
    float scrubFill = rectMask(uv, scrubRect, px) * (s.scrub_active > 0.5 ? 0.22 : 0.04);
    col += warm * playFill + warm * scrubFill;
    col = lerp(col, neutral * 0.55, saturate(
        borderMask(uv, playRect, px) +
        borderMask(uv, resetRect, px) +
        borderMask(uv, scrubRect, px) +
        borderMask(uv, sliderRect, px)));

    float2 playCenter = float2(0.13, 0.86);
    float2 pp = (uv - playCenter) * float2(aspect, 1.0);
    float triMask = smoothstep(0.018, 0.012, max(abs(pp.y) - 0.035 + pp.x * 0.55, -pp.x - 0.025));
    float pauseBars = rectMask(uv, float4(0.116, 0.825, 0.126, 0.895), px) +
                      rectMask(uv, float4(0.136, 0.825, 0.146, 0.895), px);
    float playIcon = s.playing > 0.5 ? pauseBars : triMask;
    col = lerp(col, bright, saturate(playIcon));

    float2 rc = (uv - float2(0.30, 0.86)) * float2(aspect, 1.0);
    float ring = lineMask(length(rc), 0.035, px * 1.7);
    float resetStem = rectMask(uv, float4(0.267, 0.823, 0.284, 0.852), px);
    col = lerp(col, bright, saturate(ring + resetStem));

    float scrubGlyph = lineMask(uv.x, 0.447, px * aspect * 2.0) *
                       rectMask(uv, float4(0.425, 0.825, 0.565, 0.895), px);
    scrubGlyph += lineMask(uv.x, 0.533, px * aspect * 2.0) *
                  rectMask(uv, float4(0.425, 0.825, 0.565, 0.895), px);
    col = lerp(col, bright, saturate(scrubGlyph));

    float sliderTrack = rectMask(uv, float4(0.635, 0.854, 0.92, 0.868), px);
    float sliderFill = rectMask(uv, float4(0.635, 0.854, lerp(0.635, 0.92, scrub_phase), 0.868), px);
    col = lerp(col, neutral * 0.42, sliderTrack);
    col = lerp(col, warm, sliderFill);
    float thumb = 1.0 - smoothstep(px * 5.0, px * 8.0,
        length((uv - float2(lerp(0.635, 0.92, scrub_phase), 0.861)) * float2(aspect, 1.0)));
    col = lerp(col, bright, thumb);

    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
