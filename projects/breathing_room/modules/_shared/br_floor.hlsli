// br_floor.hlsli -- parquet layout shared by the plan diagram (BR_Shell) and the floor shader
// (BR_Render), so the slats you see in the drawing are the slats that get shaded.
//
// Herringbone is built as two lattice vectors over k:1 bricks (k = length / width), measured in
// brick-width units: staircase step (1, 1) and staircase pitch (k, -k). A staircase j holds
//     H_j = [j, j+k] x [j, j+1]          V_j = [j+k, j+k+1] x [j+1-k, j+1]
// and S + n(k,-k) tiles the plane exactly. The whole lattice is laid at 45 degrees to the walls,
// which is what turns the staircases into the familiar V columns.
#ifndef BR_FLOOR_HLSLI
#define BR_FLOOR_HLSLI

struct BRSlat
{
    float edge;       // distance to the nearest slat edge, metres (groove lines)
    float2 local;     // position inside the slat: x along its length, y across (metres, centred)
    float2 size;      // slat length, width (metres)
    float2 grainDir;  // world-XZ unit vector along the slat's length
    uint id;          // stable per-slat id (colour, grain seed)
    float2 centre;    // the slat's centre, world XZ (the trip times its waves by it)
};

float brBoxEdge(float2 p, float2 lo, float2 hi)
{
    float2 d = min(p - lo, hi - p);
    return min(d.x, d.y);              // > 0 inside
}

// Herringbone in brick units. Returns the slat containing q.
void brHerringboneUnits(float2 q, float k, out float edge, out float2 lo, out float2 hi, out bool vertical, out int2 key)
{
    float beta = (q.x - q.y) / (2.0 * k);
    int j2 = (int)floor(beta);
    float2 base = q - (float)j2 * float2(k, -k);
    edge = -1e9; lo = 0; hi = 1; vertical = false; key = int2(0, 0);
    [unroll] for (int s = -1; s <= 1; s++)
    {
        float2 p = base - (float)s * float2(k, -k);
        int jh = (int)floor(p.y);
        float2 hlo = float2(jh, jh), hhi = float2(jh + k, jh + 1);
        float eh = brBoxEdge(p, hlo, hhi);
        if (eh > edge) { edge = eh; lo = hlo + (float)(j2 + s) * float2(k, -k); hi = hhi + (float)(j2 + s) * float2(k, -k); vertical = false; key = int2(jh, j2 + s); }
        int jv = (int)floor(p.x - k);
        float2 vlo = float2(jv + k, jv + 1 - k), vhi = float2(jv + k + 1, jv + 1);
        float ev = brBoxEdge(p, vlo, vhi);
        if (ev > edge) { edge = ev; lo = vlo + (float)(j2 + s) * float2(k, -k); hi = vhi + (float)(j2 + s) * float2(k, -k); vertical = true; key = int2(jv, j2 + s); }
    }
}

// pattern: 0 herringbone, 1 chevron, 2 straight plank, 3 basketweave
BRSlat brFloorSlat(float2 xz, int pattern, float slatW)
{
    BRSlat o;
    float w = max(slatW, 0.02);
    if (pattern == 2)
    {
        // Straight plank: boards run along x, random-length butt joints per row.
        float plankW = w * 2.2;
        float row = floor(xz.y / plankW);
        float y = xz.y - row * plankW;
        float lenBase = plankW * 9.0;
        float shift = frac(sin(row * 12.9898) * 43758.5453) * lenBase;
        float x = xz.x + shift;
        float col = floor(x / lenBase);
        float lx = x - col * lenBase;
        o.edge = min(min(y, plankW - y), min(lx, lenBase - lx));
        o.local = float2(lx - lenBase * 0.5, y - plankW * 0.5);
        o.size = float2(lenBase, plankW);
        o.grainDir = float2(1, 0);
        o.id = (uint)(int)(row * 97.0 + col * 13.0 + 4096.0) * 2654435761u;
        o.centre = float2(col * lenBase + lenBase * 0.5 - shift, row * plankW + plankW * 0.5);
        return o;
    }
    if (pattern == 3)
    {
        // Basketweave: 3-slat squares alternating direction.
        float cell = w * 3.0;
        float2 c = floor(xz / cell);
        float2 f = xz - c * cell;
        bool alt = fmod(abs(c.x + c.y), 2.0) > 0.5;
        float across = alt ? f.y : f.x;
        float along = alt ? f.x : f.y;
        float si = floor(across / w);
        float ac = across - si * w;
        o.edge = min(min(ac, w - ac), min(along, cell - along));
        o.local = float2(along - cell * 0.5, ac - w * 0.5);
        o.size = float2(cell, w);
        o.grainDir = alt ? float2(1, 0) : float2(0, 1);
        o.id = (uint)(int)(c.x * 131.0 + c.y * 17.0 + si * 7.0 + 8192.0) * 2654435761u;
        o.centre = c * cell + (alt ? float2(cell * 0.5, si * w + w * 0.5) : float2(si * w + w * 0.5, cell * 0.5));
        return o;
    }
    if (pattern == 1)
    {
        // Chevron: slats cut at 45 degrees meeting on straight centre lines along z.
        float k = 5.0;
        float colW = w * k * 0.7071;              // column width across x
        float col = floor(xz.x / colW);
        float fx = xz.x - col * colW;
        bool flip = fmod(abs(col), 2.0) > 0.5;
        float lx = flip ? colW - fx : fx;
        float along = xz.y + lx;                  // 45-degree shear
        float pitch = w * 1.41421;
        float row = floor(along / pitch);
        float ry = along - row * pitch;
        float perp = ry * 0.7071;
        o.edge = min(min(perp, (pitch - ry) * 0.7071), min(fx, colW - fx));
        o.local = float2(lx * 1.41421 - colW * 0.7071, perp - w * 0.5);
        o.size = float2(colW * 1.41421, w);
        o.grainDir = normalize(float2(flip ? -1.0 : 1.0, -1.0));
        o.id = (uint)(int)(col * 211.0 + row * 19.0 + 16384.0) * 2654435761u;
        o.centre = float2(col * colW + colW * 0.5, (row + 0.5) * pitch - colW * 0.5);
        return o;
    }
    // Herringbone, laid at 45 degrees. 5:1 slats.
    float k = 5.0;
    const float c45 = 0.70710678;
    float2 q = float2(xz.x * c45 + xz.y * c45, -xz.x * c45 + xz.y * c45) / w;
    float edgeU; float2 lo, hi; bool vert; int2 key;
    brHerringboneUnits(q, k, edgeU, lo, hi, vert, key);
    float2 ctr = (lo + hi) * 0.5;
    float2 d = (q - ctr) * w;
    o.edge = edgeU * w;
    o.local = vert ? float2(d.y, d.x) : d;
    o.size = float2(k * w, w);
    // brick axis in the rotated frame -> world
    float2 axisR = vert ? float2(0, 1) : float2(1, 0);
    o.grainDir = float2(axisR.x * c45 - axisR.y * c45, axisR.x * c45 + axisR.y * c45);
    o.id = (uint)(key.x * 7919 + key.y * 104729 + (vert ? 1 : 0) * 15485863 + 1000003) * 2654435761u;
    o.centre = float2((ctr.x - ctr.y) * c45, (ctr.x + ctr.y) * c45) * w;
    return o;
}

#endif
