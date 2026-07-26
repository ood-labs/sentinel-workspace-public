RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float heightAt(float2 uv)
{
    float3 c = _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
    float l = luminance(c);
    // Preserve the entire engraving as a continuous height field. Negative
    // space is composed downstream with explicit geometry, never by deleting
    // low-luminance source information here.
    float shaped = pow(saturate(l * height_gain), height_curve);
    return shaped * relief_depth;
}

float3 surfaceNormal(float2 uv, float2 texel, float2 halfExtent)
{
    float hL = heightAt(uv - float2(texel.x, 0.0));
    float hR = heightAt(uv + float2(texel.x, 0.0));
    float hU = heightAt(uv - float2(0.0, texel.y));
    float hD = heightAt(uv + float2(0.0, texel.y));

    float dhdx = (hR - hL) / max(4.0 * halfExtent.x * texel.x, 0.00001);
    float dhdy = -(hD - hU) / max(4.0 * halfExtent.y * texel.y, 0.00001);
    return normalize(float3(-dhdx * normal_gain, -dhdy * normal_gain, 1.0));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 screenUV = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);
    ndc.x *= _Resolution.x / max(_Resolution.y, 1.0);

    float az = camera_azimuth;
    float el = camera_elevation;
    float3 ro = float3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * camera_distance;
    float3 target = float3(0.0, 0.0, relief_depth * 0.22);
    float3 forward = normalize(target - ro);
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), forward));
    float3 up = cross(forward, right);
    float3 rd = normalize(forward + ndc.x * right * lens + ndc.y * up * lens);

    float2 halfExtent = float2(plate_scale * 1.7777778, plate_scale);
    float denom = min(rd.z, -0.0001);
    float tNear = (relief_depth - ro.z) / denom;
    float tFar = (0.0 - ro.z) / denom;
    float hitT = -1.0;
    float previousT = tNear;
    float2 hitUV = 0.0;
    float3 hitP = 0.0;

    [loop]
    for (int i = 0; i < 88; ++i)
    {
        float f = ((float)i + 0.5) / 88.0;
        float t = lerp(tNear, tFar, f);
        float3 p = ro + rd * t;
        float2 uv = float2(p.x / (2.0 * halfExtent.x) + 0.5,
                           0.5 - p.y / (2.0 * halfExtent.y));
        bool inside = all(uv >= 0.0) && all(uv <= 1.0);
        float h = inside ? heightAt(uv) : -1.0;
        if (inside && p.z <= h)
        {
            float lowT = previousT;
            float highT = t;
            [unroll]
            for (int refine = 0; refine < 5; ++refine)
            {
                float midT = (lowT + highT) * 0.5;
                float3 midP = ro + rd * midT;
                float2 midUV = float2(midP.x / (2.0 * halfExtent.x) + 0.5,
                                      0.5 - midP.y / (2.0 * halfExtent.y));
                bool midInside = all(midUV >= 0.0) && all(midUV <= 1.0);
                float midHeight = midInside ? heightAt(midUV) : -1.0;
                if (midInside && midP.z <= midHeight) highT = midT;
                else lowT = midT;
            }
            hitT = highT;
            hitP = ro + rd * hitT;
            hitUV = float2(hitP.x / (2.0 * halfExtent.x) + 0.5,
                           0.5 - hitP.y / (2.0 * halfExtent.y));
            break;
        }
        previousT = t;
    }

    float radial = length(ndc * float2(0.55, 0.82));
    float3 background = float3(0.0012, 0.0014, 0.0015);
    background += (1.0 - smoothstep(0.2, 1.25, radial)) * float3(0.003, 0.0035, 0.0032);
    float3 col = background;

    if (hitT > 0.0)
    {
        float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
        float3 source = _Tex0.SampleLevel(LinearSampler, hitUV, 0).rgb;
        float sourceLum = luminance(source);
        float h = heightAt(hitUV);
        float3 n = surfaceNormal(hitUV, texel * 1.75, halfExtent);

        float3 lightDir = normalize(float3(-0.42, 0.68, 0.60));
        float diffuse = saturate(dot(n, lightDir));
        float grazing = pow(1.0 - saturate(dot(n, -rd)), 3.0);
        float cavity = 1.0 - saturate(length(n.xy) * 0.42);
        float contour = 1.0 - smoothstep(0.035, 0.15,
            abs(frac(h * contour_density / max(relief_depth, 0.001)) - 0.5));

        float3 metal = lerp(float3(0.075, 0.078, 0.073),
                            float3(0.72, 0.75, 0.70), sourceLum);
        float3 lit = metal * (0.075 + diffuse * 0.92);
        lit += grazing * float3(0.34, 0.36, 0.33) * rim_gain;
        lit *= 0.74 + 0.26 * cavity;
        lit += contour * sourceLum * float3(0.055, 0.060, 0.054);

        float warmEvidence = saturate(source.r - max(source.g, source.b) * 1.08);
        float3 warm = float3(0.92, 0.13, 0.025) * warmEvidence * warm_material;
        col = lit + warm;

        float edgeX = min(hitUV.x, 1.0 - hitUV.x);
        float edgeY = min(hitUV.y, 1.0 - hitUV.y);
        float plateEdge = smoothstep(0.0, 0.007, min(edgeX, edgeY));
        col *= 0.42 + 0.58 * plateEdge;
    }

    col = 1.0 - exp(-col * exposure);
    col = pow(saturate(col), 1.0 / 1.12);
    OutputUAV[pixel] = float4(col, 1.0);
}
