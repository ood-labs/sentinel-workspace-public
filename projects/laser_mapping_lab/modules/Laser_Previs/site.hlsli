// Laser_Previs / site.hlsli: the warehouse bay and drywall mock-up, and the camera. Every pass
// that needs the world includes this, so camera rays, laser occlusion and laser surface hits all
// see the same geometry. (Replaces BLINK_Previs's Interactive Stage 2 site model.)
//
// World: metres, right-handed, y up. The drywall's painted face is the plane z = 0 facing +z;
// the room (and the laser) is at z > 0.

// ------------------------------------------------------------------ the taped target frame
// Blue painter's tape, 48 mm wide, on the drywall face: 3.0 x 1.8 m outer size, centred.
static const float2 FRAME_C = float2(0.0, 1.5);
static const float2 FRAME_HALF = float2(1.5, 0.9);
static const float TAPE_W = 0.048;

// Frame-mapped wall coordinates: the video projector's image is mapped onto the taped frame
// (as MadMapper would map it), so image uv (0,0) is the frame's top-left corner.
float2 frameUV(float2 w) { return float2((w.x - (FRAME_C.x - FRAME_HALF.x)) / (2 * FRAME_HALF.x), ((FRAME_C.y + FRAME_HALF.y) - w.y) / (2 * FRAME_HALF.y)); }

// ------------------------------------------------------------------ camera
// Sentinel's camera space is left-handed; the room is authored right-handed with the laser at +z.
// Mirroring z on entry keeps every dimension as written: camera z = -8 stands 8 m from the wall.
float3 camPos() { return _CameraPos * float3(1, 1, -1); }
float3 camRayAt(float2 pixel)
{
    float2 uv = pixel / _Resolution, ndc = float2(uv.x * 2 - 1, 1 - uv.y * 2);
    float4 nw = mul(_InvViewProjMatrix, float4(ndc, 0, 1)), fw = mul(_InvViewProjMatrix, float4(ndc, 1, 1));
    nw /= nw.w; fw /= fw.w;
    return normalize(fw.xyz - nw.xyz) * float3(1, 1, -1);
}

// ------------------------------------------------------------------ static geometry
// Materials: 0 drywall mock-up, 2 warehouse wall, 3 painted steel, 4 road case, 5 pallet wood,
// 6 concrete floor (ground plane), 7 roof deck, 8 stacked board on the pallet.
static const int NB = 18;
static const float3 BMIN[NB] = {
    float3(-2.4, 0, -0.125),                                   // drywall mock-up (4 x 1.2 m sheets)
    float3(-2.5, 0, -0.35), float3(2.4, 0, -0.35),             // floor-plate braces behind it
    float3(-12.3, 0, -8), float3(12, 0, -8),                   // side walls
    float3(-12, 0, -8.3), float3(-12, 0, 20),                  // back wall, front wall
    float3(-12, 7.5, -8),                                      // roof deck
    float3(-6.15, 0, -3.15), float3(5.85, 0, -3.15),           // steel columns (back row)
    float3(-6.15, 0, 7.85), float3(5.85, 0, 7.85),             // steel columns (front row)
    float3(1.55, 0, 0.7),                                      // road case
    float3(-2.35, 0, 0.9), float3(-2.3, 0.14, 0.95),           // pallet, stacked board on it
    float3(0, -10, 0),                                         // (unused: the laser stand follows the fixture)
    float3(0.36, 1.46, 6.50), float3(0.57, 0, 6.63)            // video projector body, its stand
};
static const float3 BMAX[NB] = {
    float3(2.4, 3.0, 0),
    float3(-2.3, 0.05, 0), float3(2.5, 0.05, 0),
    float3(-12, 7.5, 20), float3(12.3, 7.5, 20),
    float3(12, 7.5, -8), float3(12, 7.5, 20.3),
    float3(12, 7.8, 20),
    float3(-5.85, 7.5, -2.85), float3(6.15, 7.5, -2.85),
    float3(-5.85, 7.5, 8.15), float3(6.15, 7.5, 8.15),
    float3(2.35, 0.95, 1.3),
    float3(-1.15, 0.14, 2.1), float3(-1.2, 0.42, 2.05),
    float3(0, -10, 0),
    float3(0.84, 1.74, 6.92), float3(0.63, 1.46, 6.79)
};
static const int BMAT[NB] = { 0, 3, 3, 2, 2, 2, 2, 7, 3, 3, 3, 3, 4, 5, 8, 3, 3, 3 };

// The laser's stand follows Laser Fixture: floor plate, mast and head plate under the housing.
// Passes that bind the Fixtures data (#define FIX before including this file) use the fixture's
// real aperture; the others fall back to the default pose.
float3 standHead()
{
#ifdef FIX
    // The RAW 10's body is centred 0.175 m behind its aperture and its feet sit 0.10 m below it.
    if (FIX_COUNT > 1 && FIX[0].aperture.w > 0.5) return FIX[1].aperture.xyz - FIX[1].forward.xyz * 0.175;
#endif
    return float3(1.39, 1.55, 6.47);
}
// The stand turns with the laser: its boxes are in the laser's own horizontal frame (x along the
// housing's right, z along its aim), centred under the body, so the head plate sits square under
// the four feet whatever the yaw.
float2 standRight()
{
#ifdef FIX
    if (FIX_COUNT > 1 && FIX[0].aperture.w > 0.5)
    {
        float2 r = FIX[1].right.xz;
        if (dot(r, r) > 1e-6) return normalize(r);
    }
#endif
    return float2(-0.9778, 0.2094);
}
void standBox(int k, out float3 bmin, out float3 bmax)
{
    float3 h = standHead(); float top = max(h.y - 0.10, 0.1);
    if (k == 0) { bmin = float3(-0.28, 0, -0.28); bmax = float3(0.28, 0.03, 0.28); }       // floor plate
    else if (k == 1) { bmin = float3(-0.025, 0, -0.025); bmax = float3(0.025, top - 0.02, 0.025); } // mast
    else { bmin = float3(-0.125, top - 0.02, -0.17); bmax = float3(0.125, top, 0.17); }    // head plate, under the feet
}

bool hitBox(float3 ro, float3 rd, float3 bmin, float3 bmax, out float t, out float3 n)
{
    float3 d = (abs(rd) < 1e-6) ? float3(1e-6, 1e-6, 1e-6) : rd;
    float3 inv = 1.0 / d;
    float3 t0 = (bmin - ro) * inv, t1 = (bmax - ro) * inv;
    float3 lo = min(t0, t1), hi = max(t0, t1);
    float tn = max(max(lo.x, lo.y), lo.z);
    float tf = min(min(hi.x, hi.y), hi.z);
    t = tn; n = float3(0, 0, 0);
    if (tf < tn || tn <= 1e-4) return false;
    if (tn == lo.x) n = float3(-sign(d.x), 0, 0);
    else if (tn == lo.y) n = float3(0, -sign(d.y), 0);
    else n = float3(0, 0, -sign(d.z));
    return true;
}

// One stand box, hit in the stand's frame; the normal comes back in world space.
bool hitStand(float3 ro, float3 rd, int k, out float t, out float3 n)
{
    float3 h = standHead(); float2 R = standRight(), F = float2(-R.y, R.x);
    float2 q = ro.xz - h.xz;
    float3 lo, hi; standBox(k, lo, hi);
    float3 nl;
    bool hit = hitBox(float3(dot(q, R), ro.y, dot(q, F)), float3(dot(rd.xz, R), rd.y, dot(rd.xz, F)), lo, hi, t, nl);
    float2 nxz = nl.x * R + nl.z * F;
    n = float3(nxz.x, nl.y, nxz.y);
    return hit;
}

// Primary hit: returns t (1e9 = nothing), normal, material.
float trace(float3 ro, float3 rd, out float3 n, out int mat)
{
    float best = 1e9; n = float3(0, 1, 0); mat = -1;
    if (rd.y < -1e-5)
    {
        float tg = -ro.y / rd.y;
        if (tg > 0) { best = tg; n = float3(0, 1, 0); mat = 6; }
    }
    [loop] for (int i = 0; i < NB; i++)
    {
        float t; float3 nn;
        if (hitBox(ro, rd, BMIN[i], BMAX[i], t, nn) && t < best) { best = t; n = nn; mat = BMAT[i]; }
    }
    [unroll] for (int k = 0; k < 3; k++)
    {
        float t; float3 nn;
        if (hitStand(ro, rd, k, t, nn) && t < best) { best = t; n = nn; mat = 3; }
    }
    return best;
}

// Laser Lab's room query: distance to the nearest surface, capped at 1000.
float sceneHit(float3 ro, float3 rd)
{
    float3 n; int mat;
    return min(trace(ro, rd, n, mat), 1000);
}

// True if anything blocks the straight segment from p to q.
bool occluded(float3 p, float3 q)
{
    float3 v = q - p;
    float len = length(v);
    float3 rd = v / max(len, 1e-6);
    if (rd.y < -1e-5) { float tg = -p.y / rd.y; if (tg > 0.02 && tg < len - 0.05) return true; }
    [loop] for (int i = 0; i < NB; i++)
    {
        float t; float3 nn;
        if (hitBox(p, rd, BMIN[i], BMAX[i], t, nn) && t > 0.02 && t < len - 0.05) return true;
    }
    [unroll] for (int k = 0; k < 3; k++)
    {
        float t; float3 nn;
        if (hitStand(p, rd, k, t, nn) && t > 0.02 && t < len - 0.05) return true;
    }
    return false;
}

// The room's own light at a surface: cool skylight from the clerestory and one warm work lamp on a
// tall stand front-right that rakes across the drywall, with its shadow. All under Environment
// Light, so the room can go dark. The walls, the stand and the laser housing all use this.
static const float3 WORK_LAMP = float3(3.6, 3.2, 6.5);
float3 roomLight(float3 p, float3 n)
{
    float3 light = ambient * float3(0.72, 0.8, 1.0) * (0.55 + 0.45 * saturate(n.y * 0.5 + 0.5));
    float3 v = WORK_LAMP - p;
    float d2 = dot(v, v);
    if (!occluded(p + n * 0.01, WORK_LAMP))
        light += work_lamp * float3(1.0, 0.72, 0.45) * 24.0 * saturate(dot(n, v * rsqrt(d2))) / (d2 + 0.5);
    return light * environment_light;
}
