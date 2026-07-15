// clone_overlay — vector overlay driven by face_cutout's Clones buffer (data:0). Gathers the
// active clones into a compact list, then connects them:
//   Chain      — straight segments in order
//   Cage       — each point to its next K neighbours (cross-linked web)
//   Proximity  — all pairs within a radius (dense web)
//   Nearest    — each point to its closest
//   Spline     — one continuous Catmull-Rom curve threaded THROUGH all points (open)
//   Loop       — closed Catmull-Rom lasso, points angle-sorted around the centroid
// with optional bezier bow (segment modes), an arc-length chase window + dashes, dots and boxes.
// Premultiplied-alpha, transparent — composite over the accumulation. _Data0 = Clones.

RWTexture2D<float4> OutputUAV : register(u0);

static const uint CAP = 40;

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}
float sdBezier2(float2 p, float2 a, float2 b, float2 c)
{
    float d = 1e9; float2 prev = a;
    [unroll] for (int i = 1; i <= 8; i++)
    {
        float t = (float)i / 8.0;
        float2 pt = lerp(lerp(a, b, t), lerp(b, c, t), t);
        d = min(d, sdSeg(p, prev, pt)); prev = pt;
    }
    return d;
}
float2 catmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}
void over(inout float3 rgb, inout float cov, float3 c, float a)
{ rgb = c * a + rgb * (1.0 - a); cov = a + cov * (1.0 - a); }

float2 cloneUV(float2 pos){ return float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5); }

// core + glow + arc-length window + dashes, given distance d (px) and curve param u (0..1)
float strkDU(float d, float u)
{
    float core = smoothstep(line_width + 1.5, line_width, d);
    float halo = exp(-d / max(glow, 1.0)) * glow_amt;
    float off = frac(line_offset - _Time * flow_speed * 0.1);
    float w1 = off + line_length;
    float fe = 0.02;
    float win = smoothstep(off - fe, off + fe, u) * smoothstep(w1 + fe, w1 - fe, u);
    if (w1 > 1.0) win = max(win, smoothstep(-fe, fe, u) * smoothstep((w1 - 1.0) + fe, (w1 - 1.0) - fe, u));
    float dash = 1.0;
    if (dash_amt > 0.001)
    {
        float ph = frac(u * dash_count - _Time * flow_speed);
        dash = lerp(1.0, smoothstep(0.5, 0.30, abs(ph - 0.5)), dash_amt);
    }
    return (core * dash + halo) * win;
}

// one straight/bezier connection a->b
float segStrk(float2 P, float2 a, float2 b)
{
    float2 ba = b - a, pa = P - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    float d;
    if (curve > 0.001)
    {
        float2 nrm = normalize(float2(-ba.y, ba.x) + 1e-6);
        float2 ctrl = (a + b) * 0.5 + nrm * curve * length(ba);
        d = sdBezier2(P, a, ctrl, b);
    }
    else d = length(pa - ba * t);
    return strkDU(d, t);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 P = (float2)px + 0.5;

    float2 pts[CAP]; float2 exts[CAP]; uint M = 0;
    uint N = min((uint)_Data0_Count, 256u);
    [loop] for (uint j = 0u; j < N; j++)
    {
        if (M >= CAP) break;
        _DataType_0 c = _Data0[j];
        if (c.active < 0.5) continue;
        if (frac(sin(c.seed * 12.9898) * 43758.5453) > subset) continue;   // stable random subset
        pts[M] = cloneUV(c.pos + c.vel * lead) * res;                       // latency-correct with lead
        exts[M] = c.ext * 0.5 * res;
        M++;
    }

    float3 rgb = 0.0; float cov = 0.0;
    float3 tint = color;

    if (line_on != 0 && M >= 2u)
    {
        int cm = (int)connect_mode;
        if (cm == 1)                                  // Cage
        {
            uint K = (uint)clamp((int)connections, 1, 8);
            [loop] for (uint i = 0u; i < M; i++)
                [loop] for (uint k = 1u; k <= K; k++)
                    over(rgb, cov, tint, segStrk(P, pts[i], pts[(i + k) % M]));
        }
        else if (cm == 2)                             // Proximity
        {
            float rad = radius * res.y;
            [loop] for (uint i = 0u; i < M; i++)
                [loop] for (uint j2 = i + 1u; j2 < M; j2++)
                    if (distance(pts[i], pts[j2]) < rad)
                        over(rgb, cov, tint, segStrk(P, pts[i], pts[j2]));
        }
        else if (cm == 3)                             // Nearest
        {
            [loop] for (uint i = 0u; i < M; i++)
            {
                float best = 1e9; uint bj = i;
                [loop] for (uint j3 = 0u; j3 < M; j3++)
                { if (j3 == i) continue; float dd = distance(pts[i], pts[j3]); if (dd < best){ best = dd; bj = j3; } }
                over(rgb, cov, tint, segStrk(P, pts[i], pts[bj]));
            }
        }
        else if (cm == 4 || cm == 5)                  // Spline (open) / Loop (closed, angle-sorted)
        {
            bool loop = (cm == 5);
            int order[CAP];
            [loop] for (uint a = 0u; a < M; a++) order[a] = (int)a;
            if (loop)
            {
                float2 cen = 0.0;
                [loop] for (uint b = 0u; b < M; b++) cen += pts[b];
                cen /= (float)M;
                float ang[CAP];
                [loop] for (uint c2 = 0u; c2 < M; c2++) ang[c2] = atan2(pts[c2].y - cen.y, pts[c2].x - cen.x);
                [loop] for (uint ii = 1u; ii < M; ii++)   // insertion sort by angle
                {
                    int key = order[ii]; float ka = ang[key]; int jj = (int)ii - 1;
                    [loop] while (jj >= 0 && ang[order[jj]] > ka) { order[jj + 1] = order[jj]; jj--; }
                    order[jj + 1] = key;
                }
            }
            int Mi = (int)M;
            int segCount = loop ? Mi : Mi - 1;
            int S = 12;
            float d = 1e9; float bestU = 0.0;
            [loop] for (int seg = 0; seg < segCount; seg++)
            {
                int i0, im1, i1, i2;
                if (loop) { i0 = order[seg]; im1 = order[(seg - 1 + Mi) % Mi]; i1 = order[(seg + 1) % Mi]; i2 = order[(seg + 2) % Mi]; }
                else      { i0 = order[seg]; im1 = order[max(seg - 1, 0)]; i1 = order[min(seg + 1, Mi - 1)]; i2 = order[min(seg + 2, Mi - 1)]; }
                float2 P0 = pts[im1], P1 = pts[i0], P2 = pts[i1], P3 = pts[i2];
                float2 prev = P1;
                [loop] for (int s = 1; s <= S; s++)
                {
                    float t = (float)s / (float)S;
                    float2 cur = catmull(P0, P1, P2, P3, t);
                    float dd = sdSeg(P, prev, cur);
                    if (dd < d) { d = dd; bestU = ((float)seg + t) / (float)segCount; }
                    prev = cur;
                }
            }
            over(rgb, cov, tint, strkDU(d, bestU));
        }
        else                                          // Chain
        {
            [loop] for (uint i = 0u; i + 1u < M; i++)
                over(rgb, cov, tint, segStrk(P, pts[i], pts[i + 1u]));
        }
    }

    // dots (annotations, drawn over everything)
    if (dot_on != 0)
        [loop] for (uint i = 0u; i < M; i++)
        {
            float dist = length(P - pts[i]);
            float ring = smoothstep(1.5, 0.0, abs(dist - dot_size));
            float core = smoothstep(dot_size * 0.45, 0.0, dist);
            over(rgb, cov, tint, max(ring, core * 0.8));
        }

    // boxes with painter occlusion — only the TOPMOST clone whose rect covers P shows its border,
    // exactly like the stamps composite (later clones cover earlier ones' edges). Higher pts index
    // = higher draw order = on top.
    if (box_on != 0)
    {
        int top = -1;
        [loop] for (uint i = 0u; i < M; i++)
        {
            float2 hh = exts[i] + box_width;
            float2 dxy = abs(P - pts[i]);
            if (dxy.x <= hh.x && dxy.y <= hh.y) top = (int)i;
        }
        if (top >= 0)
        {
            float2 h = exts[top];
            float2 aq = abs(P - pts[top]);
            float bw = box_width;
            float b;
            if ((int)box_mode == 1)                   // Corners — short L ticks
            {
                float tl = min(h.x, h.y) * box_tick;
                float onX = smoothstep(bw + 1.5, bw, abs(aq.y - h.y)) * step(h.x - tl, aq.x) * step(aq.x, h.x + bw);
                float onY = smoothstep(bw + 1.5, bw, abs(aq.x - h.x)) * step(h.y - tl, aq.y) * step(aq.y, h.y + bw);
                b = max(onX, onY);
            }
            else                                      // Full outline
            {
                float onX = step(aq.x, h.x) * smoothstep(bw + 1.5, bw, abs(aq.y - h.y));
                float onY = step(aq.y, h.y) * smoothstep(bw + 1.5, bw, abs(aq.x - h.x));
                b = max(onX, onY);
            }
            over(rgb, cov, box_color, b * box_alpha);
        }
    }

    OutputUAV[px] = float4(rgb * intensity * opacity, cov * opacity);
}
