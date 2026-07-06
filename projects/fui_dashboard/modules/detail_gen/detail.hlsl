// detail_gen — emits the DENSE small-widget layer: scattered mini readouts,
// tick/marker clusters, connector-dot chains, and far background dust. Second
// Widget buffer feeding widget_render (data:1). Same struct contract as layout_gen.

struct Widget {
    float2 pos; float depth; float rot;
    float2 scale; float kind; float value;
    float2 p01; float2 p23;
    float tier; float active; float group; float seed;
};

RWStructuredBuffer<Widget> Out : register(u0);

static const float WX = 1.78;
float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }
float2 h22(float p){ return float2(h11(p*1.7), h11(p*3.1+5.0)); }

Widget mk(float2 pos, float depth, float rot, float2 scale, int kind, float tier, float grp, float sd)
{
    Widget w;
    w.pos = pos; w.depth = depth; w.rot = rot; w.scale = scale;
    w.kind = (float)kind; w.value = 0.6; w.p01 = float2(0,0); w.p23 = float2(0,0);
    w.tier = tier; w.active = 1.0; w.group = grp; w.seed = sd;
    return w;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 256u) return;

    Widget w = mk(float2(0,0), 0.5, 0.0, float2(0.03,0.03), 6, 1.0, 0.0, (float)i);
    w.active = 0.0;
    float fi = (float)i + (float)seed * 31.0;

    // ---- dense mini readouts, left + bottom weighted (0..63) ----
    if (i < 64u) {
        int kt[8] = {24,17,3,29,6,21,25,19};
        float2 r = h22(fi);
        // bias toward left half and lower third
        float2 p = float2(-1.6 + r.x*1.8, 0.75 - r.y*1.55);
        float sc = lerp(0.03, 0.075, h11(fi*6.1));
        w = mk(p, 0.5 + 0.2*h11(fi*2.2), 0.0, float2(sc, sc*0.8), kt[i%8], (h11(fi*9.0)<0.2)?2.0:1.0, 10.0, fi);
    }
    // ---- tiny markers/dots everywhere (64..127) ----
    else if (i < 128u) {
        int kt[5] = {6,26,5,13,21};
        float2 r = h22(fi*1.31);
        float2 p = float2(-1.7 + r.x*3.4, -1.0 + r.y*2.0);
        float sc = lerp(0.018, 0.045, h11(fi*7.7));
        w = mk(p, 0.55 + 0.35*h11(fi*3.9), 0.0, float2(sc,sc), kt[i%5], (h11(fi*4.2)<0.35)?2.0:1.0, 11.0, fi);
    }
    // ---- connector-dot chains (128..179) ----
    else if (i < 180u) {
        int c = ((int)i - 128) / 13;    // 4 chains, 13 dots each
        int k = ((int)i - 128) % 13;
        float t = (float)k / 12.0;
        float2 a, b;
        if (c==0)      { a=float2(-1.30,0.40); b=float2(-0.10,0.30); }
        else if (c==1) { a=float2(-0.05,0.30); b=float2(0.55,-0.02); }
        else if (c==2) { a=float2(0.30,-0.80); b=float2(1.30,-0.55); }
        else           { a=float2(-1.10,-0.55); b=float2(-0.30,0.00); }
        float2 p = lerp(a, b, t);
        w = mk(p, 0.66, 0.0, float2(0.010,0.010), 26, (k==0||k==12)?2.0:1.0, 12.0, fi);
    }
    // ---- background dust (far, faint) (180..231) ----
    else if (i < 232u) {
        float2 r = h22(fi*2.71);
        float2 p = float2(-1.75 + r.x*3.5, -1.0 + r.y*2.0);
        w = mk(p, 0.12 + 0.15*h11(fi*8.3), 0.0, float2(0.012,0.012), (h11(fi*5.1)<0.5)?26:19, 0.0, 13.0, fi);
    }
    // ---- small ring accents scattered (232..255) ----
    else {
        int kt[4] = {2,3,23,31};
        float2 anc = (h11(fi*1.9)<0.4) ? float2(0.92,-0.02) : float2(-1.6 + h11(fi*6.6)*3.2, -0.9 + h11(fi*7.2)*1.8);
        float2 off = (h22(fi*4.4)-0.5) * float2(0.5,0.4);
        float sc = lerp(0.045,0.11,h11(fi*2.6));
        w = mk(anc+off, 0.68, h11(fi*3.3)*6.28, float2(sc,sc), kt[i%4], 1.0, 14.0, fi);
    }

    if (h11(fi*0.51) > density) w.active = 0.0;

    Out[i] = w;
}
