// abstract_shape_render: consumes ShapeRecord placement data and draws poster objects.

RWTexture2D<float4> OutputUAV : register(u0);

struct ShapeRecord {
    float4 p0;
    float4 p1;
    float4 color;
    float4 style;
};

StructuredBuffer<ShapeRecord> Shapes : register(t0);

float2 rot2(float2 v, float a)
{
    float s = sin(a);
    float c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float rectMask(float2 q)
{
    float2 d = abs(q) - 1.0;
    float outside = length(max(d, 0.0));
    float inside = min(max(d.x, d.y), 0.0);
    float sd = outside + inside;
    return 1.0 - smoothstep(0.0, 0.012, sd);
}

float segDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}

float3 shadeSphere(float2 uv, float2 center, float r, float3 base, float aspect)
{
    float2 q = (uv - center) * float2(aspect, 1.0) / max(r, 1e-4);
    float z = sqrt(saturate(1.0 - dot(q, q)));
    float3 n = normalize(float3(q.x, -q.y, z));
    float3 l = normalize(float3(-0.45, -0.55, 0.75));
    float diff = 0.44 + 0.56 * saturate(dot(n, l));
    float spec = pow(saturate(dot(reflect(-l, n), float3(0, 0, 1))), 32.0);
    float rim = pow(saturate(1.0 - z), 2.0);
    return base * diff + float3(1.0, 0.96, 0.86) * spec * 0.7 + rim * 0.08;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float3 col = 0.0;
    float alpha = 0.0;

    [loop]
    for (uint i = 0; i < _Data0_Count; ++i)
    {
        ShapeRecord r = Shapes[i];
        if (r.style.z < 0.5 || r.color.a <= 0.0) continue;

        int kind = (int)round(r.p0.w);
        float2 center = r.p0.xy;
        float2 scale = max(r.p1.xy, float2(0.0001, 0.0001));
        float rot = r.p1.z + _Time * motion * 0.05 * step(2.5, (float)kind);
        float3 base = r.color.rgb;
        float a = r.color.a;
        float mask = 0.0;
        float3 sCol = base;

        if (kind == 0)
        {
            float2 q = rot2((uv - center) / scale, -rot);
            mask = rectMask(q);
        }
        else if (kind == 1)
        {
            float d = length((uv - center) * float2(aspect, 1.0));
            float rr = scale.x;
            mask = 1.0 - smoothstep(rr, rr + 0.006, d);
            sCol = shadeSphere(uv, center, rr, base, aspect);
        }
        else if (kind == 2)
        {
            float2 q = rot2((uv - center) * float2(aspect, 1.0), -rot) / scale;
            float d = abs(length(q) - 1.0);
            mask = 1.0 - smoothstep(r.style.y, r.style.y + 0.006, d);
        }
        else if (kind == 3)
        {
            float d = length((uv - center) * float2(aspect, 1.0));
            float rr = scale.x;
            float w = max(r.style.y, 0.004);
            mask = 1.0 - smoothstep(w, w + 0.006, abs(d - rr));
            sCol = lerp(float3(0.04, 0.04, 0.045), base, 0.65 + 0.35 * sin(atan2(uv.y - center.y, (uv.x - center.x) * aspect) * 4.0 + _Time * motion));
        }
        else if (kind == 4)
        {
            float2 q = rot2((uv - center) * float2(aspect, 1.0), -rot) / scale;
            mask = 1.0 - smoothstep(1.0, 1.035, length(q));
            float stripe = step(frac(q.x * r.style.x + q.y * 1.8), 0.46);
            sCol = lerp(float3(0.10, 0.10, 0.105), base, stripe);
        }
        else if (kind == 5)
        {
            float d = segDist(uv, r.p0.xy, r.p1.xy);
            mask = 1.0 - smoothstep(r.p1.z, r.p1.z + 0.004, d);
            sCol = base;
        }
        else if (kind == 6)
        {
            float d = segDist(uv, r.p0.xy, r.p1.xy);
            mask = 1.0 - smoothstep(r.p1.z, r.p1.z + 0.002, d);
        }

        float aa = saturate(mask * a * intensity);
        col = lerp(col, sCol * intensity, aa);
        alpha = max(alpha, aa);
    }

    OutputUAV[pixel] = float4(saturate(col), saturate(alpha));
}
