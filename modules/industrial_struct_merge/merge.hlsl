// industrial_struct_merge - compacts up to four StructPart streams and applies
// one global scene transform.

struct StructPart {
    float3 center; float3 axis; float3 up; float3 half_extents;
    float length; float radius; float kind; float material;
    float seed; float group; float active; float spare;
};

RWStructuredBuffer<StructPart> Out : register(u0);

float2 rot2(float2 v, float a)
{
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

StructPart transformPart(StructPart p)
{
    p.center *= global_scale;
    p.center.xz = rot2(p.center.xz, global_yaw);
    p.center += global_offset;
    p.axis.xz = rot2(p.axis.xz, global_yaw);
    p.up.xz = rot2(p.up.xz, global_yaw);
    p.half_extents *= global_scale;
    p.length *= global_scale;
    p.radius *= global_scale;
    return p;
}

StructPart emptyPart(uint i)
{
    StructPart p;
    p.center = 0; p.axis = float3(0,0,1); p.up = float3(0,1,0);
    p.half_extents = float3(0.01,0.01,0.01); p.length = 0.02; p.radius = 0.02;
    p.kind = 0; p.material = 1; p.seed = (float)i; p.group = 0; p.active = 0; p.spare = 0;
    return p;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 1024u) return;
    StructPart p = emptyPart(i);
    uint src = i;
    uint c0 = min((uint)_Data0_Count, 512u);
    uint c1 = min((uint)_Data1_Count, 512u);
    uint c2 = min((uint)_Data2_Count, 512u);
    uint c3 = min((uint)_Data3_Count, 512u);
    if (src < c0) p = _Data0[src];
    else
    {
        src -= c0;
        if (src < c1) p = _Data1[src];
        else
        {
            src -= c1;
            if (src < c2) p = _Data2[src];
            else
            {
                src -= c2;
                if (src < c3) p = _Data3[src];
            }
        }
    }
    if (debug_kind_filter >= 0 && (int)floor(p.kind + 0.5) != debug_kind_filter) p.active = 0.0;
    if ((int)p.kind == 0 && enable_columns == 0) p.active = 0.0;
    if (((int)p.kind == 1 || (int)p.kind == 2) && enable_beams == 0) p.active = 0.0;
    if ((int)p.kind == 3 && enable_braces == 0) p.active = 0.0;
    if ((int)p.kind == 4 && enable_decks == 0) p.active = 0.0;
    if ((int)p.kind == 6 && enable_pipes == 0) p.active = 0.0;
    if ((int)p.kind == 7 && enable_ladders == 0) p.active = 0.0;
    if ((int)p.kind == 9 && enable_rooflights == 0) p.active = 0.0;
    Out[i] = transformPart(p);
}
