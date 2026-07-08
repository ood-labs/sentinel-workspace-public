// face_stitch preview — overlays the emitted anchors (buffer:nodes) as colored dots + a short
// direction tick over the base face (input:0), so you can see the eye/mouth/nose/brow anchors
// land on the real features. _Tex0 = face; Nodes = PNode buffer.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight;
    float group; float kind; float seed; float active;
};
StructuredBuffer<PNode> Nodes : register(t1);   // t0 = _Tex0 (face video)
RWTexture2D<float4> OutputUAV : register(u0);

float3 groupCol(int g)
{
    if (g == 0) return float3(0.2, 1.0, 0.5);   // eyes
    if (g == 1) return float3(1.0, 0.5, 0.2);   // mouth
    if (g == 2) return float3(0.4, 0.7, 1.0);   // nose
    if (g == 3) return float3(1.0, 0.9, 0.3);   // brows
    return float3(1.0, 0.3, 0.8);               // cheeks
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 uv = ((float2)px + 0.5) / res;

    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * 0.75;

    [loop] for (uint i = 0u; i < 16u; i++)
    {
        PNode n = Nodes[i];
        if (n.active < 0.5) continue;
        float2 pUV = float2(n.pos.x * 0.5 + 0.5, 0.5 - n.pos.y * 0.5);
        float2 dpx = (uv - pUV) * res;
        float dist = length(dpx);
        float3 gc = groupCol((int)n.group);
        // weight ring (shows stamp footprint) + solid center dot
        float ringR = n.weight * 0.5 * res.x;
        col = lerp(col, gc, smoothstep(2.0, 0.0, abs(dist - ringR)) * 0.5);
        col = lerp(col, gc, smoothstep(9.0, 4.0, dist));
        // direction tick
        float2 tp = pUV + n.dir * 0.06 * float2(1.0, -1.0);
        float2 tdpx = (uv - tp) * res;
        col = lerp(col, float3(1,1,1), smoothstep(5.0, 2.0, length(tdpx)));
    }

    OutputUAV[px] = float4(col, 1.0);
}
