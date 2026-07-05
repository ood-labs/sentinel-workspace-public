// hud_panels — FUI panel chrome: framed data panels with header bars and fake
// "text" rows, a warning triangle, a small icon cluster, a bar-chart block, and
// edge tab boxes. All procedural rects/segments. Transport: render node.
//
// Two brightness tiers packed into one output: body_color (linework) and
// core_color (bright fills / accents).

RWTexture2D<float4> OutputUAV : register(u0);

static float g_body = 0.0;
static float g_core = 0.0;
static float g_dim  = 0.0;

float hash11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }

// rectangle outline in UV. r = (x0,y0,x1,y1). lw in UV-y units (x scaled by asp).
float rectFrame(float2 uv, float4 r, float lw, float asp)
{
    float2 lwv = float2(lw / asp, lw);
    bool inside = uv.x > r.x && uv.x < r.z && uv.y > r.y && uv.y < r.w;
    float dx = min(abs(uv.x - r.x), abs(uv.x - r.z));
    float dy = min(abs(uv.y - r.y), abs(uv.y - r.w));
    bool onV = dx < lwv.x && uv.y > r.y - lwv.y && uv.y < r.w + lwv.y;
    bool onH = dy < lwv.y && uv.x > r.x - lwv.x && uv.x < r.z + lwv.x;
    return (onV || onH) ? 1.0 : 0.0;
}

float inRect(float2 uv, float4 r){ return (uv.x>r.x&&uv.x<r.z&&uv.y>r.y&&uv.y<r.w)?1.0:0.0; }

// filled horizontal bar spanning the panel width at [y0,y1]
float hbar(float2 uv, float4 r, float y0, float y1)
{
    return (uv.x>r.x&&uv.x<r.z&&uv.y>y0&&uv.y<y1)?1.0:0.0;
}

// draw a framed data panel: outline + header fill + N fake text rows
void panel(float2 uv, float4 r, int rows, float seed, float asp)
{
    g_body = max(g_body, rectFrame(uv, r, 0.0013, asp));
    // header bar
    float hh = r.y + 0.012;
    g_core = max(g_core, hbar(uv, float4(r.x, r.y, r.z, r.w), r.y + 0.002, hh) * 0.9);
    // faint interior fill
    g_dim = max(g_dim, inRect(uv, r) * 0.06);
    // fake text rows below header
    float pad = 0.006 / asp;
    float top = hh + 0.010;
    float dy = 0.014;
    [loop]
    for (int i = 0; i < rows; i++)
    {
        float ry = top + (float)i * dy;
        if (ry > r.w - 0.006) break;
        float rowLen = (r.z - r.x - 2.0*pad) * (0.35 + 0.6 * hash11(seed + (float)i));
        float xs = r.x + pad;
        float xe = xs + rowLen;
        // dashed "words"
        if (abs(uv.y - ry) < 0.0016 && uv.x > xs && uv.x < xe)
        {
            float d = step(0.35, frac((uv.x - xs) * asp * 90.0));
            g_body = max(g_body, d * 0.75);
        }
    }
}

// small square with an X
void iconX(float2 uv, float2 c, float s, float asp)
{
    float2 p = (uv - c) * float2(asp, 1.0);
    float4 r = float4(c.x - s/asp, c.y - s, c.x + s/asp, c.y + s);
    g_body = max(g_body, rectFrame(uv, r, 0.0012, asp));
    float dcross = min(abs(p.x - p.y), abs(p.x + p.y));
    if (dcross < 0.0016 && abs(p.x) < s*0.72 && abs(p.y) < s*0.72)
        g_body = max(g_body, 1.0);
}

// small grid-of-cells icon
void iconGrid(float2 uv, float2 c, float s, float asp)
{
    float2 p = (uv - c) * float2(asp, 1.0);
    if (abs(p.x) < s && abs(p.y) < s)
    {
        float gx = step(0.5, frac((p.x / s * 0.5 + 0.5) * 3.0));
        float gy = step(0.5, frac((p.y / s * 0.5 + 0.5) * 3.0));
        g_core = max(g_core, (gx * gy) * 0.7);
    }
}

// warning triangle with exclamation
void warnTri(float2 uv, float2 c, float s, float asp)
{
    float2 p = (uv - c) * float2(asp, 1.0);
    // equilateral-ish triangle SDF (pointing up)
    float k = 1.7320508;
    float2 q = p; q.x = abs(q.x);
    float d = max(q.x * k + q.y - s, -q.y - s * 0.55);   // rough interior test
    // outline via band on the two slanted edges + base
    float edge = abs(q.x * 0.866 + q.y * 0.5 - s * 0.5);
    float onEdge = (1.0 - smoothstep(0.0, 0.002, edge)) * step(q.y, s*0.55) * step(-s*0.6, q.y);
    float base = (1.0 - smoothstep(0.0, 0.002, abs(q.y + s*0.55))) * step(q.x, s*0.62);
    g_core = max(g_core, max(onEdge, base));
    // exclamation mark
    float bar = (1.0 - smoothstep(0.0, 0.0018, q.x)) * step(-s*0.25, p.y) * step(p.y, s*0.15);
    float dot = 1.0 - smoothstep(0.0, 0.006, length(p - float2(0.0, -s*0.38)));
    g_core = max(g_core, max(bar, dot) * step(q.x, 0.01));
}

// vertical bar chart in rect r with n bars
void barChart(float2 uv, float4 r, int n, float seed, float asp)
{
    float w = (r.z - r.x) / (float)n;
    if (uv.x < r.x || uv.x > r.z || uv.y > r.w) return;
    int idx = (int)((uv.x - r.x) / w);
    float bx0 = r.x + (float)idx * w + w * 0.18;
    float bx1 = r.x + (float)idx * w + w * 0.82;
    float h = 0.25 + 0.75 * hash11(seed + (float)idx * 1.7);
    float by0 = lerp(r.w, r.y, h);
    if (uv.x > bx0 && uv.x < bx1 && uv.y > by0 && uv.y < r.w)
        g_body = max(g_body, 0.85);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    g_body = 0.0; g_core = 0.0; g_dim = 0.0;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;

    // ---- top-left icon cluster ----
    iconX(uv, float2(0.028, 0.055), 0.013, asp);
    iconGrid(uv, float2(0.075, 0.055), 0.014, asp);
    iconX(uv, float2(0.028, 0.10), 0.013, asp);

    // ---- left data panels ----
    panel(uv, float4(0.020, 0.150, 0.180, 0.300), 7, 3.1, asp);
    panel(uv, float4(0.020, 0.320, 0.140, 0.470), 6, 7.4, asp);
    panel(uv, float4(0.020, 0.640, 0.250, 0.870), 9, 1.9, asp);

    // small readout blocks
    panel(uv, float4(0.200, 0.150, 0.300, 0.240), 3, 5.2, asp);

    // ---- warning triangle (centre-left) ----
    warnTri(uv, float2(0.415, 0.255), 0.045, asp);

    // ---- bar chart block (bottom centre) ----
    barChart(uv, float4(0.320, 0.780, 0.520, 0.900), 14, 2.7, asp);
    // baseline + frame under the bars
    g_body = max(g_body, rectFrame(uv, float4(0.315, 0.775, 0.525, 0.905), 0.0012, asp) * 0.6);

    // ---- right-edge tab boxes (labels drawn by hud_labels) ----
    g_body = max(g_body, rectFrame(uv, float4(0.930, 0.230, 0.985, 0.290), 0.0013, asp));
    g_body = max(g_body, rectFrame(uv, float4(0.945, 0.420, 0.998, 0.480), 0.0013, asp));
    g_body = max(g_body, rectFrame(uv, float4(0.930, 0.690, 0.985, 0.750), 0.0013, asp));
    // a top tab
    g_body = max(g_body, rectFrame(uv, float4(0.610, 0.090, 0.660, 0.140), 0.0013, asp));

    float3 col = body_color * g_body + body_color * g_dim + core_color * g_core;
    col *= intensity;
    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
