// focal — publishes a single focal point (world coords) as control outputs x/y,
// so multiple nodes (the bespoke hud_gauge hero + the pg_hero ring halo) can be
// driven from ONE source and moved together as a unit. Drag `pos` to move it all.

struct FocalData { float x; float y; float pad0; float pad1; };
RWStructuredBuffer<FocalData> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FocalData f;
    f.x = pos.x; f.y = pos.y; f.pad0 = 0.0; f.pad1 = 0.0;
    OutputBuffer[0] = f;
}
