// botany_frame — the translucent crop "box" that drifts across the frame (ref motion). Premultiplied
// -alpha plate: translucent lighter-violet fill + dark border + tiny caption ticks; transparent
// elsewhere. Drifts L<->R seamlessly; amplitude/speed driveable from botany_control (frame_drift).
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float3 FRAME_VIOLET = float3(0.56, 0.20, 0.94);
static const float3 LINE = float3(0.05, 0.03, 0.12);

void paintP(inout float4 acc, float3 c, float a){ a=saturate(a); acc.rgb = c*a + acc.rgb*(1.0-a); acc.a = a + acc.a*(1.0-a); }

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float aa = 1.4 / _Resolution.y;

    float period = max(loop_period, 0.001);
    float dx = frame_drift * drift_amp * an_loop_harmonic(_Time, period, 1.0, 0.0);
    float dy = frame_drift * drift_amp * 0.35 * an_loop_harmonic(_Time, period, 2.0, 1.3);

    float fx0 = frame_x0 + dx, fx1 = frame_x1 + dx;
    float fy0 = frame_y0 + dy, fy1 = frame_y1 + dy;

    float4 acc = float4(0,0,0,0);

    float inX = smoothstep(fx0-aa, fx0+aa, uv.x) * smoothstep(fx1+aa, fx1-aa, uv.x);
    float inY = smoothstep(fy0-aa, fy0+aa, uv.y) * smoothstep(fy1+aa, fy1-aa, uv.y);
    paintP(acc, FRAME_VIOLET, inX*inY*frame_fill);

    float db = min(min(abs(uv.x-fx0), abs(uv.x-fx1)), min(abs(uv.y-fy0), abs(uv.y-fy1)));
    float onX = step(fx0-0.008, uv.x)*step(uv.x, fx1+0.008);
    float onY = step(fy0-0.008, uv.y)*step(uv.y, fy1+0.008);
    paintP(acc, LINE, smoothstep(0.0026,0.0,db) * onX * onY);

    [loop] for (int t=0;t<9;t++){
        float2 cpos = float2(fx0 + 0.014 + t*0.007, fy1 - 0.020);
        float2 cd = abs(uv - cpos);
        paintP(acc, LINE, step(cd.x, 0.0018)*step(cd.y, 0.006));
    }

    OutputUAV[px] = acc;
}
