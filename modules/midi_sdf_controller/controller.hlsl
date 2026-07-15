#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float motionPhase() { return _Data0_Count > 0 ? _Data0[0].phase : 0.0; }
float motionLoop() { return _Data0_Count > 0 ? _Data0[0].loop_seconds : 4.0; }
float motionPadEnergy() { return _Data0_Count > 0 ? _Data0[0].pad_energy : 1.0; }
float motionKnobEnergy() { return _Data0_Count > 0 ? _Data0[0].knob_energy : 1.0; }
float motionSweep() { return _Data0_Count > 0 ? _Data0[0].sweep : 1.0; }
float3 sceneAccent()
{
    int mode = _Data0_Count > 0 ? (int)round(_Data0[0].palette) : 0;
    float3 preset = mode == 1 ? float3(1.0, 0.04, 0.55) : (mode == 2 ? float3(0.68, 1.0, 0.03) : float3(0.02, 0.82, 1.0));
    return lerp(accent_color, preset, 0.72);
}

float2 matMin(float2 a, float2 b) { return a.x < b.x ? a : b; }

float padPulse(int idx)
{
    float delay = an_stagger_index((float)idx, 16.0, 0.72);
    float localPhase = frac(motionPhase() - delay + 1.0);
    float t = localPhase * max(motionLoop(), 0.1);
    float rise = an_spring(t, AN_BOUNCY.x, AN_BOUNCY.y, AN_BOUNCY.z);
    float fall = an_spring(max(t - 0.34, 0.0), AN_SMOOTH.x, AN_SMOOTH.y, AN_SMOOTH.z);
    return saturate((rise - fall) * motionPadEnergy());
}

float2 sceneMap(float3 p)
{
    float2 res = float2(p.y + 0.02, 0.0);

    // Main chassis and inset top plate.
    float body = sd_rbox(p - float3(0.0, 0.19, 0.0), float3(2.28, 0.20, 1.48), 0.16);
    res = matMin(res, float2(body, 1.0));
    float plate = sd_rbox(p - float3(0.0, 0.405, -0.01), float3(2.14, 0.035, 1.34), 0.10);
    res = matMin(res, float2(plate, 2.0));

    // 4x4 velocity-pad bank. Each pad has a spring-driven lift and emissive rim.
    [unroll]
    for (int i = 0; i < 16; ++i)
    {
        int col = i % 4;
        int row = i / 4;
        float pulse = padPulse(i);
        float3 c = float3(-1.52 + col * 0.48, 0.50 + pulse * 0.11, -0.70 + row * 0.48);
        float3 q = p - c;
        float pad = sd_rbox(q, float3(0.185, 0.055, 0.185), 0.045);
        res = matMin(res, float2(pad, pulse > 0.08 ? 4.0 : 3.0));
        float rim = max(sd_rbox(q, float3(0.205, 0.040, 0.205), 0.055), -sd_rbox(q, float3(0.176, 0.070, 0.176), 0.035));
        res = matMin(res, float2(rim, 4.0));
    }

    // Six rotary encoders with animated indicator ticks.
    [unroll]
    for (int k = 0; k < 6; ++k)
    {
        int kc = k % 3;
        int kr = k / 3;
        float3 c = float3(0.72 + kc * 0.58, 0.54, -0.62 + kr * 0.72);
        float knob = sd_cyl(p - c, 0.10, 0.17);
        res = matMin(res, float2(knob, 3.0));

        float ang = motionPhase() * AN_TAU * (0.35 + 0.08 * k) * motionKnobEnergy() + k * 0.72;
        float2 dir = float2(cos(ang), sin(ang));
        float3 tickC = c + float3(dir.x * 0.10, 0.115, dir.y * 0.10);
        float3 tq = p - tickC;
        tq.xz = sd_rot2(tq.xz, -ang);
        float tick = sd_rbox(tq, float3(0.072, 0.018, 0.022), 0.012);
        res = matMin(res, float2(tick, 4.0));
    }

    // Eight transport/step buttons across the top edge.
    [unroll]
    for (int b = 0; b < 8; ++b)
    {
        float on = pow(saturate(sin((motionPhase() * 8.0 - b) * AN_TAU) * 0.5 + 0.5), 10.0);
        float3 c = float3(-1.72 + b * 0.48, 0.495, -1.08);
        float d = sd_rbox(p - c, float3(0.14, 0.045, 0.075), 0.026);
        res = matMin(res, float2(d, on > 0.32 ? 4.0 : 3.0));
    }

    // Animated horizontal touch strip/playhead on the right.
    float strip = sd_rbox(p - float3(1.30, 0.492, 0.94), float3(0.77, 0.028, 0.105), 0.045);
    res = matMin(res, float2(strip, 3.0));
    float headX = 0.62 + motionPhase() * 1.36;
    float head = sd_rbox(p - float3(headX, 0.535, 0.94), float3(0.035 + motionSweep() * 0.02, 0.028, 0.12), 0.015);
    res = matMin(res, float2(head, 4.0));

    return res;
}

float3 calcNormal(float3 p)
{
    float e = 0.0025;
    float2 h = float2(e, 0.0);
    return normalize(float3(sceneMap(p + h.xyy).x - sceneMap(p - h.xyy).x,
                            sceneMap(p + h.yxy).x - sceneMap(p - h.yxy).x,
                            sceneMap(p + h.yyx).x - sceneMap(p - h.yyx).x));
}

float softShadow(float3 ro, float3 rd)
{
    float shade = 1.0;
    float t = 0.04;
    [loop]
    for (int i = 0; i < 28; ++i)
    {
        float h = sceneMap(ro + rd * t).x;
        shade = min(shade, 10.0 * h / t);
        t += clamp(h, 0.025, 0.22);
        if (h < 0.001 || t > 8.0) break;
    }
    return saturate(shade);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);
    float3 ro; float3 rd;
    if (cam_mode == 0)   // Fly: Sentinel's native WASD + right-drag camera.
    {
        float2 ndcv = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndcv, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndcv, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        ro = _CameraPos;
        rd = normalize(farW.xyz - nearW.xyz);
    }
    else                 // Orbit: deterministic framing for review and capture.
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);
    }

    float t = 0.0;
    float mat = -1.0;
    [loop]
    for (int step = 0; step < 128; ++step)
    {
        if (step >= ray_steps) break;
        float2 hit = sceneMap(ro + rd * t);
        if (hit.x < 0.0015) { mat = hit.y; break; }
        t += hit.x * 0.82;
        if (t > 20.0) break;
    }

    float3 bg = lerp(float3(0.007, 0.012, 0.028), float3(0.035, 0.012, 0.050), uv.y);
    float3 col = bg;
    if (mat >= 0.0)
    {
        float3 pos = ro + rd * t;
        float3 n = calcNormal(pos);
        float3 lightDir = normalize(float3(-0.55, 0.82, -0.35));
        float diff = saturate(dot(n, lightDir));
        float rim = pow(1.0 - saturate(dot(n, -rd)), 3.0);
        float sha = mat < 0.5 ? 1.0 : softShadow(pos + n * 0.01, lightDir);
        float3 albedo = body_color;
        if (mat > 1.5) albedo = panel_color;
        if (mat > 2.5) albedo = float3(0.035, 0.045, 0.065);
        if (mat > 3.5) albedo = sceneAccent() * (2.2 + 1.4 * motionPadEnergy());
        if (mat < 0.5) albedo = float3(0.018, 0.022, 0.035);
        col = albedo * (0.16 + diff * 0.92 * sha) + rim * sceneAccent() * 0.35;
        if (mat > 3.5) col += sceneAccent() * 2.1;
        col += pow(saturate(dot(reflect(rd, n), lightDir)), 42.0) * 0.45;
    }
    float fog = 1.0 - exp(-max(t - 3.0, 0.0) * 0.06);
    col = lerp(col, bg, fog);
    col = col / (1.0 + col);
    col = pow(saturate(col), 0.78);
    OutputUAV[pixel] = float4(col, 1.0);
}
