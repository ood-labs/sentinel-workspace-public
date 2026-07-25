// CRYOGRAM / SPECIMEN — packed field tap for the 3D interpretation layer.
//
// The relief renderer needs the solidification STATE, not a picture of it.
// Packed per texel:
//   R = solid fraction
//   G = elevation      (thickness: accrues with age, collapses during resorption)
//   B = orientation    (theta / TAU)
//   A = grain id
//
// Elevation is the physical reading of age: material that has been solid longer
// has accreted more, and material past its anneal life is losing thickness. That
// is why the relief breathes rather than just scrolling.

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    uint2 res = (uint2)_Resolution.xy;
    if (id.x >= res.x || id.y >= res.y) return;

    float4 st = _Tex0.Load(int3(id.xy, 0));
    float s = st.r, th = st.g, gid = st.b, age = st.a;

    bool resorbing = (gid > 0.0) && (age > anneal_life);

    float elev;
    if (gid <= 0.0) {
        elev = 0.0;
    } else if (resorbing) {
        elev = s * 0.55;                                  // collapsing
    } else {
        elev = s * (0.22 + 0.78 * saturate(age / max(anneal_life, 0.5)));
    }

    OutputUAV[id.xy] = float4(s, saturate(elev), frac(th / TAU), gid);
}
