// World-space light grid over the hall (built each frame by lightgrid.hlsl). Every cell lists the
// fixture sources whose cone can reach it and the pixel-bar emitters within LG_NEAR metres, and
// carries an L1 irradiance probe for all farther bar light. A cell that would list more than its
// capacity is flagged, and its pixels fall back to the full loop, so the grid never drops light.
// Layout per cell (uint): [0] lights | emitters<<8 | flags<<16 (1 light overflow, 2 emitter overflow)
// [1..6] probe as halves (R: T,Dx,Dy,Dz  G: ...  B: ...), [8..] light ids, then emitter ids.
#define LG_X 24
#define LG_Y 10
#define LG_Z 32
#define LG_CELLS 7680
#define LG_LIGHTS 80
#define LG_EMITS 48
#define LG_LIST 8
#define LG_STRIDE 136
#define LG_NEAR 4.0
#define LG_SOURCES 352
#define LG_CANDIDATES 224
// Bounds are the Venue room bounds (width, length, height, floor), padded a metre on every side.
float3 lgMin(float4 bounds){return float3(-bounds.x*.5-1,bounds.w-1,-bounds.y*.5-1);}
float3 lgCellSize(float4 bounds){return float3(bounds.x+2,bounds.z+2,bounds.y+2)/float3(LG_X,LG_Y,LG_Z);}
uint lgIndex(uint3 c){return (c.z*LG_Y+c.y)*LG_X+c.x;}
uint lgCellOf(float3 p,float4 bounds){float3 g=floor((p-lgMin(bounds))/lgCellSize(bounds));
 return lgIndex((uint3)clamp(g,0,float3(LG_X-1,LG_Y-1,LG_Z-1)));}
// Near-field weight of an emitter at distance d; the probe carries the complement.
float lgWindow(float d){float x=saturate(1-d*d/(LG_NEAR*LG_NEAR));return x*x;}
// Candidate k (0..223) -> sources row: 128 mover beams (even rows), then 96 strobe tube/plate rows.
uint lgSourceRow(uint k){return k<128?k*2:128+k;}
