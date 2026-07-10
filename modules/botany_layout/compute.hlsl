// botany_layout — authors the BouquetPart placement buffer (the bouquet arrangement). Each
// record is one element instance: kind (blade/petal/cone/berry/wire/stamen), world position,
// scale, rotation, and a 0..1 tint. External transforms (spread/jitter/seed/lift/size) are
// driveable from botany_control so one seed reshuffles the whole bouquet. One thread = one record.
//
// BouquetPart: 64 B / 16 floats (matches the blob part layout so it reuses the data plumbing).
struct Part {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};
RWStructuredBuffer<Part> PartsOut : register(u0);

// kind ids mirror sdf_botany.hlsli
#define K_BLADE  0.0
#define K_PETAL  1.0
#define K_CONE   2.0
#define K_BERRY  3.0
#define K_WIRE   4.0
#define K_STAMEN 5.0

float h11(float p){ p = frac(p*0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

Part mk(float3 pos, float3 sc, float3 rot, float kind, float tint)
{
    Part d;
    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy = sc.xy;   d.sc_z = sc.z;
    d.yaw = rot.x; d.tilt = rot.y; d.roll = rot.z;
    d.kind = kind; d.mat = kind; d.group = kind;
    d.colA = tint; d.colB = 0.0; d.grad = 0.0;
    d.active = 1.0;
    return d;
}

// blade anchored so its BASE sits near (baseX, 0.18, depth); splays by roll, leans by tilt.
Part blade(float baseX, float depth, float roll, float tilt, float halfLen, float wid, float tint)
{
    float3 up = float3(-sin(roll)*cos(tilt), cos(roll)*cos(tilt), sin(tilt));
    float3 c  = float3(baseX, 0.18, depth) + up*halfLen;
    return mk(c, float3(wid, halfLen, wid*0.9), float3(0, tilt, roll), K_BLADE, tint);
}

#define NPARTS 38

Part basePart(uint i)
{
    // ---- 11 fan blades + 3 hero, splaying up, asymmetric lean ----
    if (i < 11u){
        float fi = (float)i; float u = (fi+0.5)/11.0;
        float r1 = h11(fi*1.7+0.3), r2 = h11(fi*2.9+1.1), r3 = h11(fi*3.7+2.3);
        float roll = -0.12 + (u-0.5)*1.30 + (r1-0.5)*0.20;     // asymmetric splay
        float tilt = (r2-0.5)*0.42;
        float halfLen = 0.58 + r2*0.34;
        float wid = 1.15 + r1*0.55;                            // broader blades (less darty)
        return blade((u-0.5)*0.30, (r3-0.5)*0.32, roll, tilt, halfLen, wid, r3);
    }
    if (i == 11u) return blade( 0.00, 0.00,  0.02,  0.05, 0.96, 1.35, 0.10);  // hero center
    if (i == 12u) return blade(-0.05, 0.06, -0.20,  0.10, 0.90, 1.20, 0.60);
    if (i == 13u) return blade( 0.06,-0.04,  0.22, -0.05, 0.86, 1.20, 0.35);

    // ---- 6 protea cones, upright cluster in the core, riding ABOVE the petal skirt ----
    if (i == 14u) return mk(float3(-0.06, 0.74, 0.22), float3(0.34,0.44,0.34), float3(0,0.02,-0.03), K_CONE, 0.15);
    if (i == 15u) return mk(float3( 0.16, 0.82, 0.12), float3(0.32,0.42,0.32), float3(0,0.00, 0.06), K_CONE, 0.55);
    if (i == 16u) return mk(float3(-0.20, 0.90, 0.18), float3(0.30,0.40,0.30), float3(0,0.03,-0.05), K_CONE, 0.80);
    if (i == 17u) return mk(float3( 0.04, 0.66, 0.16), float3(0.36,0.46,0.36), float3(0,0.01, 0.02), K_CONE, 0.30);
    if (i == 18u) return mk(float3(-0.02, 1.02, 0.12), float3(0.28,0.38,0.28), float3(0,0.00, 0.04), K_CONE, 0.62);
    if (i == 19u) return mk(float3( 0.24, 0.62, 0.24), float3(0.32,0.42,0.32), float3(0,0.02,-0.08), K_CONE, 0.42);

    // ---- 3 grey berry clusters flanking ----
    if (i == 20u) return mk(float3(-0.44, 0.72, 0.12), float3(0.17,0.17,0.17), float3(0,0,0), K_BERRY, 0.0);
    if (i == 21u) return mk(float3( 0.46, 0.62, 0.06), float3(0.15,0.15,0.15), float3(0,0,0), K_BERRY, 0.0);
    if (i == 22u) return mk(float3(-0.30, 1.02, -0.04), float3(0.12,0.12,0.12), float3(0,0,0), K_BERRY, 0.0);

    // ---- 8 tulip petals: point DOWN (roll ~ pi), broad face to camera, drooping skirt ----
    if (i == 23u) return mk(float3(-0.04, 0.08, 0.26), float3(0.44,0.50,0.42), float3(0, -0.55, 3.14), K_PETAL, 0.05);
    if (i == 24u) return mk(float3( 0.30, 0.10, 0.20), float3(0.40,0.46,0.40), float3(0, -0.62, 2.55), K_PETAL, 0.35);
    if (i == 25u) return mk(float3(-0.34, 0.06, 0.24), float3(0.42,0.48,0.40), float3(0, -0.60, 3.70), K_PETAL, 0.55);
    if (i == 26u) return mk(float3( 0.40, 0.02, 0.18), float3(0.38,0.44,0.38), float3(0, -0.66, 2.30), K_PETAL, 0.85);
    if (i == 27u) return mk(float3(-0.42, 0.00, 0.22), float3(0.40,0.46,0.38), float3(0, -0.55, 4.02), K_PETAL, 0.20);
    if (i == 28u) return mk(float3( 0.02, 0.20, 0.28), float3(0.38,0.44,0.38), float3(0, -0.70, 3.10), K_PETAL, 0.45);
    if (i == 29u) return mk(float3(-0.18, 0.18, 0.24), float3(0.39,0.45,0.38), float3(0, -0.66, 2.86), K_PETAL, 0.70);
    if (i == 30u) return mk(float3( 0.20, 0.16, 0.22), float3(0.38,0.44,0.38), float3(0, -0.64, 3.42), K_PETAL, 0.10);

    // ---- 4 black wire tangle ----
    if (i == 31u) return mk(float3(-0.02, 0.66, 0.28), float3(0.55,0.55,0.55), float3(0.2, 0.0, 0.3), K_WIRE, 0.0);
    if (i == 32u) return mk(float3( 0.06, 0.78, 0.24), float3(0.50,0.50,0.50), float3(-0.5, 0.2, -0.4), K_WIRE, 0.0);
    if (i == 33u) return mk(float3(-0.10, 0.56, 0.30), float3(0.52,0.52,0.52), float3(0.9, -0.2, 0.6), K_WIRE, 0.0);
    if (i == 34u) return mk(float3( 0.10, 0.62, 0.32), float3(0.46,0.46,0.46), float3(1.4, 0.1, -0.3), K_WIRE, 0.0);

    // ---- 3 curling stamens up top ----
    if (i == 35u) return mk(float3(-0.05, 1.05, 0.22), float3(0.40,0.40,0.40), float3(0.2, 0.1, 0.3), K_STAMEN, 0.0);
    if (i == 36u) return mk(float3( 0.05, 1.02, 0.24), float3(0.42,0.42,0.42), float3(-0.3, 0.0, -0.4), K_STAMEN, 0.0);
    if (i == 37u) return mk(float3( 0.00, 1.10, 0.20), float3(0.38,0.38,0.38), float3(0.1, 0.2, 0.1), K_STAMEN, 0.0);

    Part z = mk(float3(0,0,0), float3(0,0,0), float3(0,0,0), K_BLADE, 0.0); z.active = 0.0; return z;
}

[numthreads(64,1,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;
    if (i >= (uint)NPARTS){ Part z = basePart(0); z.active = 0.0; PartsOut[i] = z; return; }

    Part d = basePart(i);

    // ---- external arrangement transforms (driveable from botany_control) ----
    static const float3 CENTER = float3(0.0, 0.55, 0.15);
    float3 pos = float3(d.pos_xy.x, d.pos_xy.y, d.pos_z);
    pos = CENTER + (pos - CENTER) * spread;                 // expand/contract
    float3 jit = float3(h11(i*1.73 + seed*3.1)-0.5, h11(i*2.91 + seed*1.3)-0.5, h11(i*4.13 + seed*2.7)-0.5);
    pos += jit * jitter;
    d.roll += (h11(i*7.1 + seed*2.0)-0.5) * jitter * 0.5;
    pos.y += lift;
    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy *= size_mul; d.sc_z *= size_mul;

    PartsOut[i] = d;
}
