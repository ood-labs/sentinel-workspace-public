// pl_grid — the reusable layout STRUCTURE source. Emits PNode anchors in one of
// several modes (Grid/Ring/Spiral/Scatter/Line/Border/Radial). Grouped + ordered
// (group = row/ring/spoke, u = position within group 0..1) so pl_path can fit a
// spline per group. The one node you duplicate everywhere with different params.
//
// PNode is the universal placement token shared by the whole layout kit.

struct PNode {
    float2 pos; float2 dir;   // float2s first for aligned structured-buffer packing
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWStructuredBuffer<PNode> Out : register(u0);

static const float TAU = 6.2831853;
static const float WX = 1.78;
float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }
float2 h22(float p){ return float2(h11(p*1.7), h11(p*3.1+5.0)); }

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 256u) return;

    PNode p;
    p.pos = float2(0,0); p.depth = depth_base; p.dir = float2(1,0);
    p.u = 0; p.v = 0; p.weight = 1; p.group = 0; p.kind = (float)base_kind; p.seed = (float)i; p.active = 0;

    int N = min(active_count, 256);
    float fi = (float)i + (float)seed * 19.0;
    float2 C = float2(center_x, center_y);
    float2 E = float2(extent_x, extent_y);

    if ((int)i < N)
    {
        if (mode == 0) {                                   // Grid
            int cols = max(grid_cols, 1), rows = max(grid_rows, 1);
            int gx = (int)i % cols, gy = (int)i / cols;
            if (gy < rows) {
                float u = (cols > 1) ? (float)gx/(float)(cols-1) : 0.5;
                float v = (rows > 1) ? (float)gy/(float)(rows-1) : 0.5;
                p.pos = C + (float2(u, v)*2.0 - 1.0) * E + (h22(fi)-0.5)*jitter;
                p.u = u; p.v = v; p.group = (float)gy; p.dir = float2(1,0); p.active = 1;
            }
        }
        else if (mode == 1) {                              // Ring (concentric)
            int per = max(per_ring, 1);
            int ring = (int)i / per, k = (int)i % per;
            if (ring < max(rings,1)) {
                float rad = radius + (float)ring * radius_step;
                float ang = ((float)k/(float)per)*TAU + angle_offset + (float)ring*0.35;
                float2 d = float2(cos(ang), sin(ang));
                p.pos = C + d * rad + (h22(fi)-0.5)*jitter;
                p.dir = float2(-d.y, d.x);
                p.u = (float)k/(float)per; p.v = (float)ring/(float)max(rings,1);
                p.group = (float)ring; p.weight = 1.0 - weight_falloff*p.v; p.active = 1;
            }
        }
        else if (mode == 2) {                              // Spiral (phyllotaxis)
            float t = ((float)i + 0.5) / (float)max(N,1);
            float ang = (float)i * 2.3999632 + angle_offset;
            float rad = radius * sqrt(t) * (1.0 + radius_step*4.0);
            float2 d = float2(cos(ang), sin(ang));
            p.pos = C + d * rad;
            p.dir = float2(-d.y, d.x); p.u = t; p.group = 0; p.weight = 1.0-weight_falloff*t; p.active = 1;
        }
        else if (mode == 3) {                              // Scatter (hashed)
            float2 r = h22(fi*1.3);
            p.pos = C + (r*2.0 - 1.0) * E;
            p.group = floor(h11(fi*2.9)*8.0); p.u = h11(fi*3.7); p.weight = h11(fi*5.1);
            p.dir = normalize(h22(fi*7.3)*2.0-1.0 + 1e-3); p.active = 1;
        }
        else if (mode == 4) {                              // Line
            float t = (N > 1) ? (float)i/(float)(N-1) : 0.5;
            p.pos = C + (t*2.0 - 1.0) * E + (h22(fi)-0.5)*jitter;
            p.dir = normalize(E + 1e-3); p.u = t; p.group = 0; p.active = 1;
        }
        else if (mode == 5) {                              // Border (rect perimeter)
            float t = (float)i / (float)max(N,1);
            float seg = frac(t) * 4.0; int e = (int)seg; float ft = frac(seg);
            float2 pos;
            if (e==0) pos = C + float2(lerp(-E.x,E.x,ft), -E.y);
            else if (e==1) pos = C + float2(E.x, lerp(-E.y,E.y,ft));
            else if (e==2) pos = C + float2(lerp(E.x,-E.x,ft), E.y);
            else pos = C + float2(-E.x, lerp(E.y,-E.y,ft));
            p.pos = pos; p.group = (float)e; p.u = ft; p.dir = float2(1,0); p.active = 1;
        }
        else {                                             // Radial spokes
            int per = max(per_ring, 1);
            int spoke = (int)i / per, k = (int)i % per;
            int spokes = max(rings, 1);
            if (spoke < spokes) {
                float ang = ((float)spoke/(float)spokes)*TAU + angle_offset;
                float rad = radius + (float)k * radius_step;
                float2 d = float2(cos(ang), sin(ang));
                p.pos = C + d * rad;
                p.dir = d; p.u = (float)k/(float)per; p.group = (float)spoke;
                p.weight = 1.0 - weight_falloff*p.u; p.active = 1;
            }
        }

        p.depth = saturate(depth_base + depth_var * (h11(fi*4.4)-0.5)*2.0);
        p.kind = (float)base_kind + floor(h11(fi*6.6) * (float)max(kind_span,1) + 0.0);
    }

    Out[i] = p;
}
