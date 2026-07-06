// widget_render — stamps the primitive atlas per Widget instance from TWO
// generator buffers (data:0 layout, data:1 detail), projected through a drifting
// camera so depth becomes real parallax + fog. Additive glow accumulation.
//   _Tex0  = primitive atlas (R=body, G=core)
//   _Data0 = layout widgets   _Data1 = detail widgets

struct Widget {
    float2 pos; float depth; float rot;
    float2 scale; float kind; float value;
    float2 p01; float2 p23;
    float tier; float active; float group; float seed;
};

RWTexture2D<float4> OutputUAV : register(u0);

static const float WX = 1.78;

float2 worldToUv(float2 wp){ return float2(0.5 + wp.x / (2.0*WX), 0.5 - wp.y * 0.5); }

void accum(Widget w, float2 uv, float2 camDrift, inout float3 col, inout float aAcc)
{
    if (w.active < 0.5) return;
    float z = saturate(w.depth);

    // camera parallax: far & near shift opposite around the mid plane
    float2 par = camDrift * (z - 0.5) * parallax;
    float dScale = lerp(1.0 - depth_scale, 1.0 + depth_scale, z);
    float2 cuv = worldToUv(w.pos + par);
    float2 half2 = max(w.scale * dScale, 1e-4);

    // pixel delta in world units
    float2 pw = uv - cuv;
    float2 dwrld = float2(pw.x * 2.0 * WX, -pw.y * 2.0);

    // cheap bbox reject
    float maxH = max(half2.x, half2.y) * 1.7;
    if (dot(dwrld, dwrld) > maxH * maxH) return;

    // rotate into instance local space
    float cs = cos(-w.rot), sn = sin(-w.rot);
    float2 rp = float2(dwrld.x*cs - dwrld.y*sn, dwrld.x*sn + dwrld.y*cs);
    float2 lp = rp / half2;
    if (abs(lp.x) >= 1.0 || abs(lp.y) >= 1.0) return;

    int kind = (int)(w.kind + 0.5);
    int ccol = kind & 7;
    int crow = (kind >> 3) & 3;
    float2 luv = clamp(lp * 0.5 + 0.5, 0.004, 0.996);
    float2 auv = (float2((float)ccol, (float)crow) + luv) / float2(8.0, 4.0);
    float2 s = _Tex0.SampleLevel(LinearSampler, auv, 0).rg;   // r=body, g=core
    if (s.r + s.g <= 0.001) return;

    float fog = lerp(depth_fog, 1.0, z);
    float tw = w.tier;
    float bodyAmt = (tw < 1.0) ? lerp(0.45, 1.0, saturate(tw)) : 1.0;
    float coreAmt = saturate(tw - 1.0);

    float b = s.r * fog * bodyAmt;
    float c = (s.g + s.r * coreAmt * 0.7) * fog;

    col += body_color * b * body_gain + core_color * c;
    aAcc = max(aAcc, saturate(b + c));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float2 camDrift = float2(sin(_Time * cam_speed), cos(_Time * cam_speed * 0.8)) * cam_amp;

    float3 col = float3(0,0,0);
    float aAcc = 0.0;

    uint c0 = min((uint)_Data0_Count, 128u);
    [loop]
    for (uint i = 0u; i < 128u; i++) { if (i >= c0) break; accum(_Data0[i], uv, camDrift, col, aAcc); }

    uint c1 = min((uint)_Data1_Count, 256u);
    [loop]
    for (uint j = 0u; j < 256u; j++) { if (j >= c1) break; accum(_Data1[j], uv, camDrift, col, aAcc); }

    OutputUAV[pixel] = float4(col * intensity, saturate(aAcc));
}
