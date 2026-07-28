// corner_thread — threads a smooth spline THROUGH the corner points detected by a `features`
// node on the composited image, drawn over the final picture. Video input _Tex0 = base image;
// _Tex1 = exact analysis-proxy extent; data input _Data0 = Corners buffer
// ({x,y,response,pad}, x/y in ANALYSIS PIXELS, top-left origin).
// Loop mode sorts corners by angle around their centroid → a closed Catmull-Rom lasso woven
// through every corner; Chain mode threads them in buffer (response) order (open path).
// A feedback-free reactive overlay: the linework follows the actual image content.
#include "../_shared/palette.hlsli"

struct Corner { float x; float y; float response; float pad; };
// _Data0 (Corners) + _Data0_Count and _Tex0 (base) + LinearSampler are engine-injected.
RWTexture2D<float4> OutputUAV : register(u0);

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-5));
    return length(pa - ba * h);
}
float2 catmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 uv = ((float2)px + 0.5) / res;
    float2 P = (float2)px;                                  // pixel space = corner space
    uint analysisW, analysisH;
    _Tex1.GetDimensions(analysisW, analysisH);
    float2 analysisToProgram = res / max(float2(analysisW, analysisH), 1.0);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    uint n = min(_Data0_Count, 15u);
    if (n < 3u) { OutputUAV[px] = float4(base * base_gain, 1.0); return; }

    // load corners + centroid
    float2 pts[15]; float resp[15]; float2 cen = float2(0, 0);
    [loop] for (uint i = 0u; i < n; i++)
    {
        Corner c = _Data0[i];
        pts[i] = float2(c.x, c.y) * analysisToProgram;
        resp[i] = c.response;
        cen += pts[i];
    }
    cen /= (float)n;

    // ordering
    int order[15];
    [loop] for (uint a = 0u; a < n; a++) order[a] = (int)a;
    if ((int)thread_mode == 0)                               // Loop: sort by angle around centroid
    {
        float ang[15];
        [loop] for (uint b = 0u; b < n; b++) ang[b] = atan2(pts[b].y - cen.y, pts[b].x - cen.x);
        [loop] for (uint ii = 1u; ii < n; ii++)             // insertion sort
        {
            int key = order[ii]; float ka = ang[key]; int j = (int)ii - 1;
            [loop] while (j >= 0 && ang[order[j]] > ka) { order[j + 1] = order[j]; j--; }
            order[j + 1] = key;
        }
    }

    int segCount = ((int)thread_mode == 0) ? (int)n : (int)n - 1;
    int S = clamp((int)samples, 4, 24);

    // nearest distance to the threaded spline + arc param at the nearest point
    float d = 1e9; float bestU = 0.0;
    [loop] for (int seg = 0; seg < segCount; seg++)
    {
        int i0, im1, i1, i2;
        if ((int)thread_mode == 0) {                        // closed
            i0  = order[seg];
            im1 = order[(seg - 1 + (int)n) % (int)n];
            i1  = order[(seg + 1) % (int)n];
            i2  = order[(seg + 2) % (int)n];
        } else {                                            // open (clamp ends)
            i0  = order[seg];
            im1 = order[max(seg - 1, 0)];
            i1  = order[min(seg + 1, (int)n - 1)];
            i2  = order[min(seg + 2, (int)n - 1)];
        }
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

    // line core + glow, optional flowing dash along arc param
    float w = line_width;
    float core = smoothstep(w + 1.5, w, d);
    float halo = exp(-d / max(glow_radius, 1.0)) * glow;
    float dash = 1.0;
    if (dash_amt > 0.001)
    {
        float ph = frac(bestU * dash_count - _Time * flow_speed);
        dash = lerp(1.0, smoothstep(0.5, 0.5 - 0.18, abs(ph - 0.5)), dash_amt);
    }
    // trim the drawn portion by arc length — "line length" (great in Chain; animatable via
    // chain_offset). Draws the window [chain_offset, chain_offset+chain_length] of the path.
    float wStart = chain_offset;
    float wEnd   = chain_offset + chain_length;
    float fe = 0.012;
    float win = smoothstep(wStart - fe, wStart + fe, bestU) * smoothstep(wEnd + fe, wEnd - fe, bestU);

    float3 col = base * base_gain;
    col += thread_color.rgb * ((core * dash + halo) * win) * intensity;

    // corner markers (rings sized by response) — only the ones inside the drawn window
    if (marker_on != 0)
    {
        [loop] for (uint m = 0u; m < n; m++)
        {
            float mu = (float)m / max((float)n - 1.0, 1.0);      // ~arc pos in Chain order
            float mwin = step(wStart, mu) * step(mu, wEnd);
            float dm = distance(P, pts[m]);
            float mr = marker_size * (0.7 + 0.5 * saturate((resp[m] - 0.8) / 1.6));
            float ring = smoothstep(1.6, 0.0, abs(dm - mr));
            float dot  = smoothstep(2.0, 0.0, dm);
            col += thread_color.rgb * (ring * 0.9 + dot * 0.6) * intensity * mwin;
        }
    }

    OutputUAV[px] = float4(col, 1.0);
}
