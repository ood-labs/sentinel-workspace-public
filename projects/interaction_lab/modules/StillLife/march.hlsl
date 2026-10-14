// Still Life / march - the 3D solve, ONCE: five glazed ceramics on a paper sweep, under a soft
// key, a cool fill and a rim, through the renderer's internal camera.
//
// Writes buffer:beauty = display colour + linear ray distance in alpha. `program` blits it (the
// clean output); `outline` reads it to draw the selection with a depth test. No overlay, no
// selection tint here: the program image never knows it is being edited.
#include "../_shared/ui/il_core.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
StructuredBuffer<SlObject> Objs : register(t0);
#define SL_OBJECTS Objs
#include "still.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 slNormal(float3 p)
{
    const float2 k = float2(1.0, -1.0) * 0.0006;
    return normalize(k.xyy * slField(p + k.xyy) + k.yyx * slField(p + k.yyx) + k.yxy * slField(p + k.yxy) + k.xxx * slField(p + k.xxx));
}

float softShadow(float3 ro, float3 rd, uint steps, float k)
{
    float res = 1.0, t = 0.012;
    [loop] for (uint i = 0u; i < steps; i++)
    {
        float h = slField(ro + rd * t);
        res = min(res, k * h / t);
        if (res < 0.002 || t > 3.0) break;
        t += clamp(h, 0.008, 0.12);
    }
    return smoothstep(0.0, 1.0, saturate(res));
}

float ambientOcc(float3 p, float3 n, uint taps)
{
    float occ = 0.0, sca = 1.0;
    [loop] for (uint i = 0u; i < taps; i++)
    {
        float h = 0.012 + 0.07 * (float)i / 4.0;
        occ += (h - slField(p + n * h)) * sca;
        sca *= 0.82;
    }
    return saturate(1.0 - 2.6 * occ);
}

float3 acesFit(float3 x) { return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)); }

// One camera ray: display colour (tonemapped, gamma) and the linear ray distance.
float4 shade(float2 uv, uint marchSteps, uint shadowSteps, uint aoTaps)
{
    float3 ro, rd;
    slRay(uv, ro, rd);
    float t; uint rec;
    bool hit = slMarch(ro, rd, marchSteps, t, rec);

    float3 keyDir = normalize(float3(-0.82, 0.78, -0.12));      // a soft box high on the left
    float3 keyCol = float3(1.00, 0.96, 0.90) * key_light;
    float3 fillDir = normalize(float3(0.60, 0.35, -0.75));
    float3 fillCol = float3(0.52, 0.60, 0.72) * 0.32;
    float3 rimDir = normalize(float3(0.15, 0.55, 0.82));        // from behind, off the sweep

    float3 col;
    if (!hit)
    {
        col = float3(0.30, 0.29, 0.28) * (0.6 + 0.4 * uv.y);           // past the sweep: dim paper
        t = 60.0;
    }
    else
    {
        float3 p = ro + rd * t;
        float3 n = slNormal(p);
        float3 albedo;
        float f0, shin;                                  // reflectance at normal incidence, gloss
        if (rec == 0u)
        {
            // paper: warm mid grey, falling off away from the set
            albedo = float3(0.27, 0.255, 0.235) * (0.84 + 0.16 * saturate(1.0 - length(p.xz) * 0.55));
            f0 = 0.02; shin = 6.0;
        }
        else
        {
            SlObject o = Objs[rec];
            albedo = pow(slUnpackRgb(o.colour), 2.2);         // stored as a picked (display) colour
            f0 = (o.kind == K_RING) ? 0.08 : ((o.kind == K_VASE || o.kind == K_CONE) ? 0.045 : 0.03);
            shin = (o.kind == K_RING) ? 160.0 : ((o.kind == K_VASE || o.kind == K_CONE) ? 48.0 : 14.0);
        }
        float3 pp = p + n * 0.002;
        float sh = (shadowSteps > 0u) ? softShadow(pp, keyDir, shadowSteps, 9.0) : 1.0;
        float occ = ambientOcc(p, n, aoTaps);
        float3 h = normalize(keyDir - rd);
        float dk = max(dot(n, keyDir), 0.0);
        float fres = f0 + (1.0 - f0) * pow(1.0 - saturate(dot(n, -rd)), 5.0);
        float3 diffuse = albedo * (1.0 - fres);
        col  = diffuse * keyCol * dk * sh;
        col += keyCol * (f0 * 6.0) * pow(max(dot(n, h), 0.0), shin) * dk * sh;
        col += diffuse * fillCol * max(dot(n, fillDir), 0.0) * occ;
        col += diffuse * float3(0.30, 0.31, 0.33) * (0.55 + 0.45 * n.y) * occ * ambient;
        if (rec != 0u)
        {
            float rim = pow(saturate(1.0 + dot(rd, n)), 3.0) * max(dot(n, rimDir), 0.0);
            col += float3(1.0, 0.95, 0.88) * rim * 0.35 * occ;
            // glaze reflects the room (a vertical-gradient environment), strongest at grazing angles
            float3 rf = reflect(rd, n);
            float3 env = lerp(float3(0.10, 0.10, 0.10), float3(0.62, 0.60, 0.57), saturate(rf.y * 0.6 + 0.45));
            col += fres * env * occ * ((shin > 100.0) ? 1.0 : 0.45);
        }
    }

    col = acesFit(col * exposure);
    return float4(pow(col, 1.0 / 2.2), t);
}

// The quality ladder. Draft / Live / Beauty trade steps for shadow and occlusion quality; Hero is
// Beauty with four rotated-grid rays per pixel, for captures only - it is what clears the stair-
// stepped silhouettes and the specular sparkle on the ring, at four times the cost.
[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    if (id.x >= (uint)res.x || id.y >= (uint)res.y) return;
    uint q = (uint)clamp(quality, 0, 3);
    uint marchSteps = (q == 0u) ? 72u : ((q == 1u) ? 110u : 180u);
    uint shadowSteps = (q == 0u) ? 0u : ((q == 1u) ? 28u : 56u);
    uint aoTaps = (q == 0u) ? 2u : 5u;
    float2 px = float2(id.xy) + 0.5;
    if (q < 3u) { OutputUAV[id.xy] = shade(px / res, marchSteps, shadowSteps, aoTaps); return; }
    // RGSS: resolve the colour in display space, keep the nearest distance for the depth test
    static const float2 k[4] = { float2(0.125, 0.375), float2(0.375, -0.125), float2(-0.125, -0.375), float2(-0.375, 0.125) };
    float4 acc = float4(0.0, 0.0, 0.0, 1e9);
    [loop] for (uint i = 0u; i < 4u; i++)
    {
        float4 c = shade((px + k[i]) / res, marchSteps, shadowSteps, aoTaps);
        acc.rgb += c.rgb * 0.25;
        acc.a = min(acc.a, c.a);
    }
    OutputUAV[id.xy] = acc;
}
