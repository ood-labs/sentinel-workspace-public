// pl_path — spline shaper. Groups input PNodes by `group`, fits a Catmull-Rom
// curve through each group's members (gathered in buffer/encounter order = u
// order for pl_grid outputs), and resamples to `points_per_path` PNodes per group
// with `dir` = tangent, `u` = param. "Draw splines within the grid."

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight; float group; float kind; float seed; float active;
};

RWStructuredBuffer<PNode> Out : register(u0);

float2 catmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 a = 2.0*p1;
    float2 b = p2 - p0;
    float2 c = 2.0*p0 - 5.0*p1 + 4.0*p2 - p3;
    float2 d = -p0 + 3.0*p1 - 3.0*p2 + p3;
    return 0.5*(a + b*t + c*t*t + d*t*t*t);
}
float2 catmullTan(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 b = p2 - p0;
    float2 c = 2.0*p0 - 5.0*p1 + 4.0*p2 - p3;
    float2 d = -p0 + 3.0*p1 - 3.0*p2 + p3;
    return 0.5*(b + 2.0*c*t + 3.0*d*t*t);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 256u) return;

    PNode outp;
    outp.pos = float2(0,0); outp.dir = float2(1,0); outp.depth = 0.6;
    outp.u = 0; outp.v = 0; outp.weight = 1; outp.group = 0; outp.kind = 0; outp.seed = (float)i; outp.active = 0;

    int PPP = max(points_per_path, 2);
    int g = (int)i / PPP;
    int k = (int)i % PPP;
    if (g < num_groups)
    {
        // gather this group's control points in buffer order
        float2 cp[16];
        float ck[16];
        float cd[16];
        int n = 0;
        uint cnt = min((uint)_Data0_Count, 256u);
        [loop]
        for (uint j = 0u; j < 256u; j++)
        {
            if (j >= cnt) break;
            PNode s = _Data0[j];
            if (s.active < 0.5) continue;
            if ((int)(s.group + 0.5) != g) continue;
            if (n < 16) { cp[n] = s.pos; ck[n] = s.kind; cd[n] = s.depth; n++; }
        }

        if (n >= 2)
        {
            float t = (PPP > 1) ? (float)k / (float)(PPP - 1) : 0.0;
            if (mode == 1) {                                 // Linear
                float s = t * (float)(n - 1);
                int a = (int)floor(s); a = clamp(a, 0, n-2);
                float f = s - (float)a;
                outp.pos = lerp(cp[a], cp[a+1], f);
                outp.dir = normalize(cp[a+1] - cp[a] + 1e-4);
                outp.kind = ck[a]; outp.depth = lerp(cd[a], cd[a+1], f);
            } else {                                          // Smooth / Loop (Catmull-Rom)
                float s = t * (float)(n - 1);
                int a = (int)floor(s); a = clamp(a, 0, n-2);
                float f = s - (float)a;
                int i0 = max(a-1, 0), i1 = a, i2 = a+1, i3 = min(a+2, n-1);
                outp.pos = catmull(cp[i0], cp[i1], cp[i2], cp[i3], f);
                outp.dir = normalize(catmullTan(cp[i0], cp[i1], cp[i2], cp[i3], f) + 1e-4);
                outp.kind = ck[i1]; outp.depth = lerp(cd[i1], cd[i2], f);
            }
            outp.u = t; outp.group = (float)g; outp.weight = 1.0;
            outp.seed = (float)i; outp.active = 1.0;
        }
    }

    Out[i] = outp;
}
