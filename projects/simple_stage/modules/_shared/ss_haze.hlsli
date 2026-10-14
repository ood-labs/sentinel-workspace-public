// The haze's contract between SS_Haze, which simulates the hall's air and the haze it carries, and SS_Renderer,
// which lights it: the grids, where they sit in the hall, and the layout of the Haze Field texture SS_Haze
// publishes. Change a number here and both sides follow.
#ifndef SS_HAZE_HLSLI
#define SS_HAZE_HLSLI

// The air: 88 x 40 x 120 cells. The haze rides on a grid twice as fine.
#define HZ_AX 88
#define HZ_AY 40
#define HZ_AZ 120
#define HZ_FX 176
#define HZ_FY 80
#define HZ_FZ 240

// The grid for a hall (bounds = width, length, height, floor, as the Venue publishes them in Venue[3]; zc = the
// hall's centre along z, Venue[4].z). The cell is the largest that fits the hall in all three axes, and the
// grid's x and z centres are the hall's, so a bigger hall gets coarser air rather than a grid that stops short.
struct HzDomain { float3 lo; float h; float W, L, Ht, floorY, zc; };
HzDomain hzDomainOf(float4 bounds, float zc)
{
    HzDomain d;
    d.h = max(max(max(bounds.x / (float)HZ_AX, bounds.y / (float)HZ_AZ), bounds.z / (float)HZ_AY), 0.05);
    d.lo = float3(-0.5 * (float)HZ_AX * d.h, bounds.w, zc - 0.5 * (float)HZ_AZ * d.h);
    d.W = bounds.x; d.L = bounds.y; d.Ht = bounds.z; d.floorY = bounds.w; d.zc = zc;
    return d;
}
// the hall the Venue publishes (n = its record count), or the stage's own hall when no Venue is linked
HzDomain hzVenueDomain(uint n, float4 v3, float4 v4)
{
    bool ok = n > 4u && v3.x > 1.0 && v3.y > 1.0 && v3.z > 1.0;
    return hzDomainOf(ok ? v3 : float4(22.0, 30.0, 8.5, 0.0), ok ? v4.z : 9.0);
}
bool hzInHall(HzDomain d, float3 p)
{
    return abs(p.x) <= 0.5 * d.W && p.y >= d.floorY && p.y <= d.floorY + d.Ht && abs(p.z - d.zc) <= 0.5 * d.L;
}

// ---- the Haze Field: one 2048 x 2200 RGBA16F texture, three atlases of z slices stacked, and a header texel
#define HF_W 2048u
#define HF_H 2200u
#define HF_DEN_Y 0u       // the haze (r, Haze units): 176 x 80 tiles, 11 across, 22 rows
#define HF_AIR_Y 1760u    // the air: 88 x 40 tiles, 23 across, 6 rows (rgb velocity m/s, a temperature above ambient K)
#define HF_NOI_Y 2000u    // the wisp noise: 66 x 66 tiles (64 + a wrapped border texel each side), 31 across, 3 rows
#define HF_HDR_Y 2199u    // texel (0, 2199): (cell size, 1 = a live field, Haze Base, 0)
#define HZN_T 64.0        // the wisp noise tiles every 64 texels
#define HZN_P 66u

// Atlases: z slices of a grid laid out in rows of tiles, read with hardware bilinear in xy and a lerp in z.
// `oy` is the region's first row.
uint2 atlasTile(uint z, uint tw, uint th, uint W) { uint across = max(W / tw, 1u); return uint2((z % across) * tw, (z / across) * th); }
bool atlasCell(uint2 px, uint tw, uint th, uint nz, uint W, out int3 c)
{
    uint across = max(W / tw, 1u);
    uint tx = px.x / tw, ty = px.y / th;
    uint z = ty * across + tx;
    c = int3(px.x % tw, px.y % th, z);
    return tx < across && z < nz;
}
// g = continuous cell coordinate (cell centres at integers)
float4 atlasSample(Texture2D Tx, SamplerState S, float3 g, uint tw, uint th, uint nz, uint oy)
{
    uint W, H;
    Tx.GetDimensions(W, H);
    g = clamp(g, 0.0, float3(tw - 1, th - 1, nz - 1));
    float z0 = min(floor(g.z), nz - 2.0);
    float fz = g.z - z0;
    float2 inv = 1.0 / float2(W, H);
    float2 o = float2(0.0, (float)oy);
    float4 a = Tx.SampleLevel(S, ((float2)atlasTile((uint)z0, tw, th, W) + o + g.xy + 0.5) * inv, 0);
    float4 b = Tx.SampleLevel(S, ((float2)atlasTile((uint)z0 + 1u, tw, th, W) + o + g.xy + 0.5) * inv, 0);
    return lerp(a, b, fz);
}
// the wisp noise at q (noise texels; wraps every 64): two bilinear fetches and a lerp in z
float hfNoise(Texture2D F, SamplerState S, float3 q)
{
    float3 g = frac(q / HZN_T) * HZN_T;
    float z0 = floor(g.z);
    float fz = g.z - z0;
    uint za = (uint)z0 & 63u, zb = (za + 1u) & 63u;
    const uint across = HF_W / HZN_P;
    float2 inv = 1.0 / float2(HF_W, HF_H);
    float2 oa = float2((za % across) * HZN_P, HF_NOI_Y + (za / across) * HZN_P);
    float2 ob = float2((zb % across) * HZN_P, HF_NOI_Y + (zb / across) * HZN_P);
    float a = F.SampleLevel(S, (oa + g.xy + 1.5) * inv, 0).r;
    float b = F.SampleLevel(S, (ob + g.xy + 1.5) * inv, 0).r;
    return lerp(a, b, fz);
}

#endif
