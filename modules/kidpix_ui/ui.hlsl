// kidpix_ui — the static Kid Pix window chrome (procedural stylized). Drawn LAST over the canvas:
//   - top menu bar: crown logo + real "File / Edit / Goodies" text (scientifica font)
//   - left tool palette: a 2-column grid of black-outlined icon boxes with varied tool glyphs
//   - bottom bar: a rainbow color strip + a row of fill-pattern swatches
//   - a thin black window border framing the whole canvas
// Opaque where chrome is drawn, transparent over the canvas hole. Premultiplied RGBA. Static.
#define OS_NO_RECORD_BUFFER
#include "../_shared/fonts/scientifica_ascii.hlsli"
#include "../_shared/os_terminal.hlsli"
#include "../_shared/os_text.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float kh(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
void over(inout float3 rgb, inout float cov, float3 c, float a)
{ rgb = c * a + rgb * (1.0 - a); cov = a + cov * (1.0 - a); }

float boxIn(float2 uv, float2 lo, float2 hi){ return (uv.x>=lo.x && uv.x<=hi.x && uv.y>=lo.y && uv.y<=hi.y) ? 1.0 : 0.0; }
float boxLine(float2 uv, float2 lo, float2 hi, float t)
{ return saturate(boxIn(uv, lo, hi) - boxIn(uv, lo+t, hi-t)); }
float sdSeg(float2 p, float2 a, float2 b){ float2 pa=p-a, ba=b-a; float h=saturate(dot(pa,ba)/max(dot(ba,ba),1e-6)); return length(pa-ba*h); }

static const float3 BLACK = float3(0.05,0.05,0.06);
static const float3 GREY  = float3(0.80,0.80,0.82);
static const float3 DKGREY= float3(0.55,0.55,0.58);
static const float3 WHITE = float3(0.98,0.98,0.99);

float3 rainbow(int i, int n)
{
    float t = frac((float)i / (float)n) * 6.0; int j = (int)t;
    float3 cols[7] = { float3(0.90,0.10,0.12), float3(0.98,0.55,0.10), float3(0.98,0.85,0.10),
                       float3(0.13,0.70,0.20), float3(0.12,0.30,0.90), float3(0.55,0.15,0.75),
                       float3(0.90,0.10,0.12) };
    return cols[j];
}

// varied tool glyph in local cell space g in [0,1]; idx selects the tool
float toolGlyph(int idx, float2 g)
{
    float2 p = g - 0.5;            // -0.5..0.5
    float w = 0.06;
    float d = 1e9;
    idx = idx % 10;
    if (idx == 0)      d = sdSeg(p, float2(-0.28,0.28), float2(0.28,-0.28));                 // pencil
    else if (idx == 1) d = sdSeg(p, float2(-0.30,0.10), float2(0.30,-0.10));                 // line
    else if (idx == 2) return boxLine(g, float2(0.22,0.28), float2(0.78,0.72), 0.06);        // rect
    else if (idx == 3) return smoothstep(0.02,0.0, abs(length(p*float2(1.0,1.2))-0.26)-0.03); // oval
    else if (idx == 4) { d = min(sdSeg(p, float2(-0.25,0.28), float2(0.15,-0.20)), sdSeg(p, float2(0.15,-0.20), float2(0.28,-0.28))); w = 0.10; } // brush
    else if (idx == 5) { float b = boxLine(g, float2(0.30,0.25), float2(0.70,0.62), 0.05); float sp = smoothstep(0.02,0.0,length(p-float2(0.0,0.28))-0.10); return saturate(b+sp); } // bucket
    else if (idx == 6) return boxIn(g, float2(0.28,0.34), float2(0.72,0.66)) * 0.9;           // eraser (filled)
    else if (idx == 7) { // "A" text tool
        d = min(sdSeg(p, float2(-0.22,0.30), float2(0.0,-0.30)), sdSeg(p, float2(0.0,-0.30), float2(0.22,0.30)));
        d = min(d, sdSeg(p, float2(-0.11,0.05), float2(0.11,0.05)));
    }
    else if (idx == 8) { // spray dots
        float dots = 0.0;
        for (int i=0;i<7;i++){ float2 c = (float2(kh((float)i*1.3), kh((float)i*2.7))-0.5)*0.6; dots = max(dots, smoothstep(0.05,0.03,length(p-c))); }
        return dots;
    }
    else { // star stamp
        float s = 1e9; for (int i=0;i<5;i++){ float a=(float)i/5.0*6.2831; s=min(s, sdSeg(p, float2(0,0), float2(cos(a),sin(a))*0.30)); } d = s;
    }
    return smoothstep(w+0.01, w, d);
}

// blit a word given ascii codes; returns coverage at fpix
float blitWord(float2 fpix, float2 anchorPx, float sc, int codes[8], int len)
{
    float cellW = (float)SCIENTIFICA_GLYPH_W;
    float cov = 0.0;
    [loop] for (int k = 0; k < 8; k++)
    {
        if (k >= len) break;
        float2 a = anchorPx + float2((float)k * (cellW + 1.0) * sc, 0.0);
        cov = max(cov, osBlitGlyph(fpix, a, sc, 0, codes[k], false));
    }
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 fpix = (float2)px;
    float2 uv = (fpix + 0.5) / res;

    float3 rgb = 0.0; float cov = 0.0;

    float menuH = 0.05, palW = 0.085, botY = 0.90;

    // ========== TOP MENU BAR ==========
    if (uv.y < menuH)
    {
        over(rgb, cov, WHITE, 1.0);
        // crown logo
        float2 cl = float2(0.006, 0.008), ch = float2(0.045, menuH-0.008);
        if (boxIn(uv, cl, ch) > 0.5)
        {
            float2 g = (uv - cl) / (ch - cl);
            float base = step(0.62, g.y);
            float pts = 0.0;
            for (int k = 0; k < 3; k++)
            { float cxk = 0.2 + 0.3*(float)k; pts = max(pts, step(abs(g.x-cxk), (0.62-g.y)*0.35) * step(g.y,0.62)); }
            over(rgb, cov, float3(0.15,0.35,0.85), saturate(base+pts));
        }
        over(rgb, cov, BLACK, step(menuH-0.004, uv.y));       // bottom rule
    }

    // ========== LEFT TOOL PALETTE ==========
    if (uv.x < palW && uv.y > menuH && uv.y < botY)
    {
        over(rgb, cov, GREY, 1.0);
        int rows = 11;
        float gy0 = menuH + 0.004, gy1 = botY - 0.004;
        float cellW = (palW - 0.006) / 2.0;
        float cellH = (gy1 - gy0) / (float)rows;
        for (int r = 0; r < 11; r++)
        for (int cc = 0; cc < 2; cc++)
        {
            float2 lo = float2(0.003 + cellW*(float)cc, gy0 + cellH*(float)r) + 0.0015;
            float2 hi = lo + float2(cellW, cellH) - 0.003;
            over(rgb, cov, WHITE, boxIn(uv, lo, hi));
            over(rgb, cov, BLACK, boxLine(uv, lo, hi, 0.0015));
            if (boxIn(uv, lo+0.003, hi-0.003) > 0.5)
            {
                float2 g = (uv - lo) / (hi - lo);
                over(rgb, cov, BLACK, toolGlyph(r*2 + cc, g));
            }
        }
        over(rgb, cov, BLACK, step(palW-0.003, uv.x) * step(uv.x, palW));
    }

    // ========== BOTTOM BAR: color strip + pattern swatches ==========
    if (uv.y > botY)
    {
        over(rgb, cov, GREY, 1.0);
        over(rgb, cov, BLACK, step(uv.y, botY+0.004));
        float sY0 = botY + 0.012, sY1 = 0.985;
        float cX0 = palW + 0.01, cX1 = 0.52;
        if (uv.x > cX0 && uv.x < cX1 && uv.y > sY0 && uv.y < sY1)
        {
            float tt = (uv.x - cX0) / (cX1 - cX0);
            int nsw = 16; int si = (int)(tt * (float)nsw);
            over(rgb, cov, rainbow(si, nsw), 1.0);
            float cf = frac(tt * (float)nsw);
            over(rgb, cov, BLACK, step(cf,0.04) + step(0.96,cf));
        }
        float pX0 = 0.545, pX1 = 0.95;
        if (uv.x > pX0 && uv.x < pX1 && uv.y > sY0 && uv.y < sY1)
        {
            float tt = (uv.x - pX0) / (pX1 - pX0);
            int npt = 12; int pi = (int)(tt * (float)npt);
            float2 g = float2(frac(tt*(float)npt), (uv.y - sY0)/(sY1 - sY0));
            float ink = 0.0; int pk = pi % 4;
            if (pk == 0) { float2 cg = floor(g*4.0); ink = fmod(cg.x+cg.y, 2.0); }
            else if (pk == 1) ink = smoothstep(0.30,0.26, length(frac(g*3.0)-0.5));
            else if (pk == 2) ink = step(0.5, frac(g.x*4.0));
            else ink = 0.12;
            over(rgb, cov, WHITE, 1.0);
            over(rgb, cov, BLACK, ink);
            float cf = frac(tt*(float)npt);
            over(rgb, cov, DKGREY, step(cf,0.05) + step(0.95,cf));
        }
    }

    // ========== MENU TEXT (drawn over the white bar) ==========
    if (uv.y < menuH)
    {
        float sc = max(round(menu_text_scale), 1.0);
        float ty = 0.010 * res.y;
        int file[8]    = { 70,105,108,101, 0,0,0,0 };            // File
        int edit[8]    = { 69,100,105,116, 0,0,0,0 };            // Edit
        int goodies[8] = { 71,111,111,100,105,101,115, 0 };      // Goodies
        float t = 0.0;
        t = max(t, blitWord(fpix, float2(0.080*res.x, ty), sc, file, 4));
        t = max(t, blitWord(fpix, float2(0.185*res.x, ty), sc, edit, 4));
        t = max(t, blitWord(fpix, float2(0.290*res.x, ty), sc, goodies, 7));
        over(rgb, cov, BLACK, t);
    }

    // ========== OUTER WINDOW BORDER ==========
    over(rgb, cov, BLACK, boxLine(uv, float2(0,0), float2(1,1), 0.004));

    OutputUAV[px] = float4(rgb * intensity, cov);
}
