// dada_scatter — authors a second DadaPart buffer: a field of small accent objects
// (tiny spheres, thin rods, little discs) hash-scattered in a shell around the totem,
// to fill negative space with the reference's dense little mechanical bits.

struct DadaPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float p0; float p1; float p2; float active;
};

RWStructuredBuffer<DadaPart> PartsOut : register(u0);

float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;

    DadaPart d;
    d.pos_xy = float2(0, 0); d.sc_xy = float2(0, 0); d.pos_z = 0; d.sc_z = 0;
    d.yaw = 0; d.tilt = 0; d.roll = 0; d.kind = 0; d.mat = 0; d.group = 9;
    d.p0 = 0; d.p1 = 0; d.p2 = 0; d.active = 0;

    if (i >= (uint)scatter_count) { PartsOut[i] = d; return; }

    float s = scatter_seed;
    float hx = h11(i * 1.13 + s * 3.1);
    float hy = h11(i * 2.37 + s * 1.7);
    float hz = h11(i * 3.71 + s * 0.7);
    float hk = h11(i * 5.19 + s * 2.3);
    float hm = h11(i * 7.53 + s * 4.1);
    float hs = h11(i * 9.11 + s * 0.9);

    // shell placement: bias outward so accents ring the sculpture, not clog its centre
    float ang = hx * 6.28318;
    float rad = 1.9 + hz * 1.9;                       // 1.9..3.8 from spine axis
    float3 pos;
    pos.x = cos(ang) * rad * 0.75;
    pos.z = sin(ang) * rad * 0.55 + 0.3;
    pos.y = 0.4 + hy * 8.4;
    d.pos_xy = pos.xy; d.pos_z = pos.z;

    // kind: 55% tiny sphere, 30% thin rod, 15% small disc
    float kind; float scl; float mat;
    if (hk < 0.55)      { kind = 0.0; scl = 0.05 + hs * 0.11; }     // sphere
    else if (hk < 0.85) { kind = 11.0; scl = 0.03 + hs * 0.04; }    // rod
    else                { kind = 3.0; scl = 0.14 + hs * 0.16; }     // disc
    d.kind = kind;

    if (kind == 11.0)
    {
        d.sc_xy = float2(scl, 0.10 + hs * 0.35);      // thin, medium-long
        d.sc_z = scl;
        d.yaw = hx * 6.28; d.tilt = (hy - 0.5) * 2.4; d.roll = (hz - 0.5) * 2.4;
        d.p0 = 0.5;                                    // rod radius (canonical)
    }
    else
    {
        d.sc_xy = scl.xx; d.sc_z = (kind == 3.0) ? 0.10 : scl;
        d.tilt = (kind == 3.0) ? (hy - 0.5) * 3.0 : 0.0;
        d.p0 = (kind == 3.0) ? 0.12 : 0.0;
    }

    // accent palette: mostly black/gray/gold with occasional red/white
    if (hm < 0.40)      mat = 15.0;   // glossy black
    else if (hm < 0.62) mat = 14.0;   // grey
    else if (hm < 0.80) mat = 17.0;   // gold
    else if (hm < 0.92) mat = 16.0;   // white
    else                mat = 10.0;   // red
    d.mat = mat;

    d.active = 1.0;
    PartsOut[i] = d;
}
