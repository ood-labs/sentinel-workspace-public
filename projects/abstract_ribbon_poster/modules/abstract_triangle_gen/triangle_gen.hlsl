// abstract_triangle_gen: emits one record per triangle cell for the right column.

struct TriangleRecord {
    float4 p0;     // xy = cell min uv, zw = cell size uv
    float4 p1;     // x = orientation, y = shade, z = active, w = id
    float4 color;  // rgb = tint, a = opacity
    float4 aux;    // xy = column min, zw = column max
};

RWStructuredBuffer<TriangleRecord> OutputBuffer : register(u0);

float hash11_local(float n)
{
    return frac(sin(n * 37.23 + 19.17) * 43758.5453);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= 128) return;

    TriangleRecord r;
    r.p0 = 0.0;
    r.p1 = float4(0, 0, 0, i);
    r.color = float4(tint, opacity);
    r.aux = 0.0;
    OutputBuffer[i] = r;

    int c = max(cols, 1);
    int rw = max(rows, 1);
    int triPer = c * rw * 2;
    if ((int)i >= triPer) return;

    int cellIdx = (int)i / 2;
    int orient = (int)i - cellIdx * 2;
    int cx = cellIdx % c;
    int cy = cellIdx / c;

    float2 mn = column_center - column_extent * 0.5;
    float2 cellSize = column_extent / float2((float)c, (float)rw);
    float2 cellMin = mn + float2((float)cx, (float)cy) * cellSize;
    float idf = (float)(cx + cy * 17 + orient * 53 + seed * 7);
    float h = hash11_local(idf);
    float band = 0.5 + 0.5 * sin((float)cy * 1.35 + (float)orient);
    float shade = lerp(0.16, 0.86, h);
    shade = lerp(shade, band, 0.22);
    shade = lerp(0.5, shade, contrast);

    r.p0 = float4(cellMin, cellSize);
    r.p1 = float4((float)orient, shade, 1.0, (float)i);
    r.color = float4(tint, opacity);
    r.aux = float4(mn, mn + column_extent);
    OutputBuffer[i] = r;
}
