// blob_layout — authors the BlobPart placement buffer for the glossy organic mass
// (strata plate 1). basePart(i) is the hand-dialed woven vertical column transcribed from
// reference #7; main() applies external arrangement transforms (spread/jitter/seed/lift/
// size) so one seed reshuffles the whole tangle. One thread = one record.
//
// BlobPart: 64 B / 16 floats, float2s first for aligned packing. Field order MUST match
// the manifest data_outputs schema. Semantics: kind=shape, mat=material class,
// group=blend cluster, colA/colB=palette gradient stops, grad=gradient axis code.

struct BlobPart {
    float2 pos_xy; float2 sc_xy;
    float pos_z; float sc_z; float yaw; float tilt; float roll;
    float kind; float mat; float group; float colA; float colB; float grad; float active;
};

RWStructuredBuffer<BlobPart> PartsOut : register(u0);

// kind ids (mirror sdf_blob.hlsli)
#define K_SPHERE 0.0
#define K_TUBE   1.0
#define K_TORUS  2.0
#define K_SCOOP  3.0
#define K_RBOX   4.0
#define K_LENS   5.0
#define K_BEAN   6.0
#define K_HORN   7.0
// material classes
#define MT_GLOSS  0.0
#define MT_CHROME 1.0
#define MT_CHECK  2.0
#define MT_MATTE  3.0
#define MT_SOLID  4.0
// palette indices (mirror palette.hlsli)
#define C_ICE 0.0
#define C_LIME 1.0
#define C_INDIGO 2.0
#define C_ORANGE 3.0
#define C_LAV 4.0
#define C_PURPLE 5.0
#define C_RED 6.0
#define C_WHITE 7.0
#define C_BLACK 8.0
#define C_GRAY 9.0

float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

BlobPart mk(float3 pos, float3 sc, float3 rot, float kind, float mat, float grp,
            float colA, float colB, float grad)
{
    BlobPart d;
    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy = sc.xy;   d.sc_z = sc.z;
    d.yaw = rot.x; d.tilt = rot.y; d.roll = rot.z;
    d.kind = kind; d.mat = mat; d.group = grp;
    d.colA = colA; d.colB = colB; d.grad = grad;
    d.active = 1.0;
    return d;
}
// oriented ribbon tube: radius r, half-length L along local Y, tilted by (tilt,roll)
BlobPart tube(float3 pos, float r, float L, float tilt, float roll, float colA, float colB, float grp)
{ return mk(pos, float3(r, L, r), float3(0, tilt, roll), K_TUBE, MT_GLOSS, grp, colA, colB, 0.0); }
BlobPart blob(float3 pos, float r, float colA, float colB, float grad, float grp)
{ return mk(pos, r.xxx, float3(0,0,0), K_SPHERE, MT_GLOSS, grp, colA, colB, grad); }

#define NPARTS 28

BlobPart basePart(uint i)
{
    // ---- top cluster (group 1) : ice scoop + a lime->orange ribbon + orange horn ----
    if (i == 0)  return mk(float3(-1.05, 2.75, 0.20), float3(0.94,0.94,0.94), float3(0.5,0.0,0.6), K_SCOOP, MT_GLOSS, 1, C_ICE, C_INDIGO, 1);
    if (i == 1)  return tube(float3(0.55, 2.95, 0.05), 0.40, 1.20, -0.5, 0.35, C_LIME, C_ORANGE, 1);
    if (i == 2)  return mk(float3(1.35, 2.55, 0.10), float3(0.88,0.88,0.88), float3(0.0,0.9,0.0), K_HORN, MT_GLOSS, 1, C_ORANGE, C_LIME, 1);
    if (i == 3)  return blob(float3(-0.15, 2.35, 0.35), 0.52, C_INDIGO, C_ICE, 1, 1);

    // ---- upper weave (group 2) : indigo + lime ribbons crossing ----
    if (i == 4)  return tube(float3(-0.35, 1.75, 0.10), 0.44, 1.28, 0.6, -0.4, C_INDIGO, C_ICE, 2);
    if (i == 5)  return tube(float3(0.45, 1.55, 0.25), 0.42, 1.15, -0.7, 0.5, C_LIME, C_ICE, 2);
    if (i == 6)  return mk(float3(1.55, 1.35, 0.05), float3(0.62,0.62,0.62), float3(0,0,0.3), K_LENS, MT_GLOSS, 2, C_ORANGE, C_LIME, 1);
    if (i == 7)  return blob(float3(-1.35, 1.25, 0.15), 0.46, C_ICE, C_LIME, 0, 2);
    if (i == 8)  return tube(float3(1.05, 0.95, 0.35), 0.38, 1.05, 0.4, 0.9, C_ORANGE, C_RED, 2);

    // ---- centre (group 3) : the checker cube + a chrome coil + wrapping ribbons ----
    if (i == 9)  return mk(float3(0.05, 0.10, 0.55), float3(0.80,0.80,0.80), float3(0.5,0.2,0.0), K_RBOX, MT_CHECK, 3, C_LIME, C_INDIGO, 0);
    if (i == 10) return tube(float3(-0.85, 0.25, 0.20), 0.46, 1.32, -0.55, -0.5, C_INDIGO, C_ICE, 3);
    if (i == 11) return tube(float3(0.95, 0.15, 0.15), 0.44, 1.22, 0.6, 0.45, C_LIME, C_ORANGE, 3);
    if (i == 12) return mk(float3(1.35, 0.45, -0.15), float3(0.62,0.62,0.62), float3(0.6,0.4,0.2), K_TORUS, MT_GLOSS, 3, C_INDIGO, C_ICE, 0);
    if (i == 13) return blob(float3(-1.45, -0.15, 0.25), 0.42, C_PURPLE, C_ICE, 1, 3);
    if (i == 14) return mk(float3(-1.15, -0.55, 0.35), float3(0.96,0.96,0.96), float3(2.4,0.2,0.4), K_SCOOP, MT_GLOSS, 3, C_ICE, C_LAV, 1);

    // ---- lower weave (group 4) : indigo tubes curving down + orange accents ----
    if (i == 15) return tube(float3(-0.25, -1.05, 0.20), 0.46, 1.30, 0.5, 0.4, C_INDIGO, C_PURPLE, 4);
    if (i == 16) return tube(float3(0.65, -1.25, 0.10), 0.42, 1.18, -0.6, -0.5, C_LIME, C_ORANGE, 4);
    if (i == 17) return blob(float3(1.15, -1.55, 0.25), 0.44, C_ORANGE, C_RED, 1, 4);
    if (i == 18) return mk(float3(-1.25, -1.65, 0.15), float3(0.72,0.72,0.72), float3(0,0,0.5), K_BEAN, MT_GLOSS, 4, C_LAV, C_PURPLE, 0);
    if (i == 19) return tube(float3(0.15, -2.05, 0.30), 0.44, 1.22, 0.3, 0.6, C_INDIGO, C_ICE, 4);

    // ---- foot (group 5) : big ice scoop + a colour torus + indigo sphere ----
    if (i == 20) return mk(float3(-0.55, -2.75, 0.25), float3(1.08,1.08,1.08), float3(0.3,0.1,0.5), K_SCOOP, MT_GLOSS, 5, C_ICE, C_LIME, 1);
    if (i == 21) return mk(float3(0.95, -2.65, -0.10), float3(0.68,0.68,0.68), float3(0.4,0.5,0.3), K_TORUS, MT_GLOSS, 5, C_ORANGE, C_LIME, 0);
    if (i == 22) return blob(float3(0.35, -3.05, 0.35), 0.50, C_INDIGO, C_PURPLE, 1, 5);
    if (i == 23) return blob(float3(1.35, -2.15, 0.15), 0.30, C_ORANGE, C_RED, 1, 5);

    // ---- floating accents (group 6) : matte gray + red + solid lime ----
    if (i == 24) return mk(float3(1.75, 3.05, -0.20), float3(0.24,0.24,0.24), float3(0,0,0), K_SPHERE, MT_MATTE, 6, C_GRAY, C_GRAY, 2);
    if (i == 25) return mk(float3(-1.85, -0.05, -0.15), float3(0.20,0.20,0.20), float3(0,0,0), K_SPHERE, MT_MATTE, 6, C_GRAY, C_GRAY, 2);
    if (i == 26) return mk(float3(1.55, -0.85, 0.45), float3(0.22,0.22,0.22), float3(0,0,0), K_SPHERE, MT_SOLID, 6, C_RED, C_RED, 2);
    if (i == 27) return mk(float3(-0.75, 0.85, 0.58), float3(0.26,0.26,0.26), float3(0,0,0), K_SPHERE, MT_SOLID, 6, C_LIME, C_LIME, 2);

    return blob(float3(0,0,0), 0.0, C_WHITE, C_WHITE, 0, 0);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;

    if (i >= (uint)NPARTS)
    {
        BlobPart z = basePart(0); z.active = 0.0;
        PartsOut[i] = z;
        return;
    }

    BlobPart d = basePart(i);

    // ---- external arrangement transforms (driveable from strata_control) ----
    static const float3 CENTER = float3(0.0, 0.0, 0.15);
    float3 pos = float3(d.pos_xy.x, d.pos_xy.y, d.pos_z);

    pos = CENTER + (pos - CENTER) * spread;                 // uniform expand/contract

    float3 jit = float3(h11(i * 1.73 + seed * 3.1) - 0.5,
                        h11(i * 2.91 + seed * 1.3) - 0.5,
                        h11(i * 4.13 + seed * 2.7) - 0.5);
    pos += jit * jitter;                                    // seeded scatter
    d.yaw  += (h11(i * 5.7 + seed) - 0.5) * jitter * 0.8;   // seeded re-orient
    d.roll += (h11(i * 7.1 + seed * 2.0) - 0.5) * jitter * 0.6;

    pos.y += lift;

    d.pos_xy = pos.xy; d.pos_z = pos.z;
    d.sc_xy *= size_mul; d.sc_z *= size_mul;

    PartsOut[i] = d;
}
