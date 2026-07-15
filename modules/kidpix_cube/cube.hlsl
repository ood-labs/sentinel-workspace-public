// kidpix_cube — the tumbling 3D cube with classic Kid Pix fill-pattern faces (checkerboard, solid
// red/yellow/blue/cyan, black). Ray-box intersection (slab method) gives the hit face + face UV;
// faces are shaded FLAT and UNLIT with a nearest-neighbour pattern, and the pattern assignment
// cycles on a timer synced to the ~3s rotation (2 turns per 6s loop). Premultiplied-alpha plate
// (transparent where the ray misses) so it composites over the canvas. Self-animating on _Time.
RWTexture2D<float4> OutputUAV : register(u0);

static const float PI = 3.14159265359;

float3 rotX(float3 p, float a){ float s=sin(a),c=cos(a); return float3(p.x, c*p.y-s*p.z, s*p.y+c*p.z); }
float3 rotY(float3 p, float a){ float s=sin(a),c=cos(a); return float3(c*p.x+s*p.z, p.y, -s*p.x+c*p.z); }
float3 rotZ(float3 p, float a){ float s=sin(a),c=cos(a); return float3(c*p.x-s*p.y, s*p.x+c*p.y, p.z); }

float3 kidColor(int i)
{
    i = ((i % 6) + 6) % 6;
    if (i == 0) return float3(0.92, 0.12, 0.14);   // red
    if (i == 1) return float3(0.98, 0.85, 0.10);   // yellow
    if (i == 2) return float3(0.12, 0.22, 0.90);   // blue
    if (i == 3) return float3(0.10, 0.80, 0.85);   // cyan
    if (i == 4) return float3(0.05, 0.05, 0.06);   // black
    return float3(0.13, 0.70, 0.20);               // green
}

// pattern for a face: fuv in [0,1]^2. patKind: 0 checker, 1 solid, 2 halftone dots, 3 black.
float3 facePattern(float2 fuv, int patKind, int colA, int colB)
{
    float3 a = kidColor(colA), b = kidColor(colB);
    if (patKind == 0) {                             // checkerboard
        float2 g = floor(fuv * 8.0);
        float chk = fmod(g.x + g.y, 2.0);
        return chk < 0.5 ? a : b;
    }
    if (patKind == 2) {                             // halftone dots (colA on colB)
        float2 g = frac(fuv * 6.0) - 0.5;
        float dot = smoothstep(0.30, 0.26, length(g));
        return lerp(b, a, dot);
    }
    if (patKind == 3) return kidColor(4);           // solid black
    return a;                                        // solid
}

// ray vs unit cube [-h,h]^3 in object space; returns t (or -1), sets normal + which axis face
float boxHit(float3 ro, float3 rd, float h, out float3 nrm, out int faceId)
{
    nrm = float3(0,0,1); faceId = 0;
    float3 m = 1.0 / rd;
    float3 n = m * ro;
    float3 k = abs(m) * h;
    float3 t1 = -n - k;
    float3 t2 = -n + k;
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    if (tN > tF || tF < 0.0) return -1.0;
    // face from which slab produced tN
    if (t1.x > t1.y && t1.x > t1.z)      { nrm = float3(-sign(rd.x), 0, 0); faceId = rd.x > 0.0 ? 0 : 1; }
    else if (t1.y > t1.z)                { nrm = float3(0, -sign(rd.y), 0); faceId = rd.y > 0.0 ? 2 : 3; }
    else                                 { nrm = float3(0, 0, -sign(rd.z)); faceId = rd.z > 0.0 ? 4 : 5; }
    return tN;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;

    // camera: cube centered at (cube_x, cube_y) in canvas
    float2 c = (uv - float2(cube_x, cube_y)) * float2(aspect, 1.0);
    float3 ro = float3(0, 0, cam_dist);
    float3 rd = normalize(float3(c / focal, -1.0));

    // tumble: 2 turns per loop on yaw, gentler on pitch/roll
    float loopT = _Time / loop_seconds;
    float yaw   = loopT * 2.0 * PI * 2.0;
    float pitch = loopT * 2.0 * PI * 1.0 + 0.4;
    float roll  = sin(loopT * 2.0 * PI) * 0.25;

    // rotate the ray into object space (inverse rotation)
    float3 roO = rotY(rotX(rotZ(ro, -roll), -pitch), -yaw);
    float3 rdO = rotY(rotX(rotZ(rd, -roll), -pitch), -yaw);

    float3 nrm; int faceId;
    float t = boxHit(roO, rdO, cube_half, nrm, faceId);

    if (t < 0.0) { OutputUAV[px] = float4(0,0,0,0); return; }

    float3 hp = roO + rdO * t;                       // object-space hit
    // face UV from the two axes orthogonal to the face normal
    float2 fuv;
    if (faceId <= 1)      fuv = hp.zy;
    else if (faceId <= 3) fuv = hp.xz;
    else                  fuv = hp.xy;
    fuv = fuv / (2.0 * cube_half) + 0.5;

    // pattern cycle: which of the 6 faces gets which pattern shifts each half-turn
    int cyc = (int)floor(loopT * 2.0);               // steps twice per loop
    int fk = (faceId + cyc) % 6;
    int patKind; int colA; int colB;
    if (fk == 0) { patKind = 0; colA = 4; colB = 0; }        // checker black/red
    else if (fk == 1) { patKind = 1; colA = 1; colB = 1; }   // solid yellow
    else if (fk == 2) { patKind = 1; colA = 2; colB = 2; }   // solid blue
    else if (fk == 3) { patKind = 1; colA = 3; colB = 3; }   // solid cyan
    else if (fk == 4) { patKind = 2; colA = 0; colB = 1; }   // red dots on yellow
    else { patKind = 1; colA = 0; colB = 0; }                // solid red

    float3 col = facePattern(fuv, patKind, colA, colB);

    // flat look, but keep faces distinguishable with a tiny facing-based darken + black edges
    float facing = saturate(dot(nrm, float3(0,0,1)) * 0.5 + 0.5);
    col *= lerp(0.72, 1.0, facing);
    // edge lines (thin black cube edges)
    float2 e = min(fuv, 1.0 - fuv);
    float edge = smoothstep(0.015, 0.03, min(e.x, e.y));
    col = lerp(kidColor(4), col, edge);

    OutputUAV[px] = float4(col, 1.0) * intensity;    // opaque where hit (premult, a=1)
}
