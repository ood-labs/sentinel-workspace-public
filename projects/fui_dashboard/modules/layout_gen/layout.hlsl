// layout_gen — emits structural HUD Widget records (panels, dials, brackets,
// tick-fans, reticles, corner tabs, background depth rings). One thread = one
// record; the layout is a set of clusters keyed by index range. Downstream
// widget_render stamps a primitive-atlas cell per record with depth parallax.

struct Widget {
    float2 pos; float depth; float rot;
    float2 scale; float kind; float value;
    float2 p01; float2 p23;
    float tier; float active; float group; float seed;
};

RWStructuredBuffer<Widget> Out : register(u0);

static const float WX = 1.78;
float h11(float p){ p = frac(p*0.1031); p *= p+33.33; p *= p+p; return frac(p); }

Widget mk(float2 pos, float depth, float rot, float2 scale, int kind, float value, float tier, float grp, float sd)
{
    Widget w;
    w.pos = pos; w.depth = depth; w.rot = rot; w.scale = scale;
    w.kind = (float)kind; w.value = value; w.p01 = float2(0,0); w.p23 = float2(0,0);
    w.tier = tier; w.active = 1.0; w.group = grp; w.seed = sd;
    return w;
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint i = DTid.x;
    if (i >= 128u) return;

    Widget w = mk(float2(0,0), 0.5, 0.0, float2(0.05,0.05), 0, 0.0, 1.0, 0.0, (float)i);
    w.active = 0.0;
    float fi = (float)i + (float)seed * 17.0;

    // ---- top reticle row (0..8) ----
    if (i <= 8u) {
        int k = (int)i;
        int kt[9] = {4,7,20,0,21,3,31,5,7};
        float x = -1.52 + (float)k * 0.375;
        float sc = lerp(0.045, 0.085, h11(fi*1.3));
        w = mk(float2(x, 0.86), 0.72 + 0.18*h11(fi*2.1), 0.0, float2(sc,sc), kt[k], 0.6, (k%3==0)?2.0:1.0, 1.0, fi);
    }
    // ---- left panel stack (9..20) ----
    else if (i <= 20u) {
        int k = (int)i - 9;
        int kt[12] = {9,24,8,17,24,29,9,24,17,8,24,25};
        float y = 0.70 - (float)k * 0.125;
        float2 sc = (kt[k]==9||kt[k]==8||kt[k]==17||kt[k]==24) ? float2(0.20,0.052) : float2(0.09,0.06);
        w = mk(float2(-1.42 + sc.x*0.0, y), 0.5, 0.0, sc, kt[k], 0.5, 1.0, 2.0, fi);
    }
    // ---- hero cluster: concentric rings + satellites (21..32) ----
    else if (i <= 32u) {
        int k = (int)i - 21;
        float2 HC = float2(0.92, -0.02);
        if (k < 6) {
            int kt[6] = {1,3,2,31,15,7};
            float sc = 0.30 + (float)k * 0.048;
            w = mk(HC, 0.85, 0.0, float2(sc,sc), kt[k], 0.6, (k%2==0)?1.0:2.0, 3.0, fi);
        } else {
            int ks = k - 6;
            int kt[6] = {20,4,7,21,5,26};
            float ang = (float)ks * 1.05 + 0.3;
            float2 p = HC + float2(cos(ang), sin(ang)) * float2(0.52, 0.50);
            w = mk(p, 0.9, 0.0, float2(0.055,0.055), kt[ks], 0.6, 2.0, 3.0, fi);
        }
    }
    // ---- bottom instrument row (33..46) ----
    else if (i <= 46u) {
        int k = (int)i - 33;
        int kt[14] = {17,20,25,22,6,20,17,24,20,25,17,20,6,24};
        float x = -0.55 + (float)k * 0.155;
        float2 sc = (kt[k]==17||kt[k]==24||kt[k]==25||kt[k]==22) ? float2(0.075,0.05) : float2(0.06,0.06);
        w = mk(float2(x, -0.80), 0.62 + 0.1*h11(fi*3.3), 0.0, sc, kt[k], 0.5, (k%4==0)?2.0:1.0, 4.0, fi);
    }
    // ---- center bracket + warning (47..52) ----
    else if (i <= 52u) {
        int k = (int)i - 47;
        if (k==0) w = mk(float2(-0.08,0.30), 0.6, 0.0, float2(0.38,0.24), 11, 0.6, 1.0, 5.0, fi);
        else if (k==1) w = mk(float2(-0.08,0.31), 0.95, 0.0, float2(0.10,0.10), 12, 0.6, 2.0, 5.0, fi);
        else if (k==2) w = mk(float2(0.30,0.20), 0.6, 0.0, float2(0.30,0.20), 10, 0.6, 1.0, 5.0, fi);
        else if (k==3) w = mk(float2(-0.55,0.56), 0.55, 0.0, float2(0.24,0.075), 9, 0.5, 1.0, 5.0, fi);
        else if (k==4) w = mk(float2(0.42,0.34), 0.8, 0.0, float2(0.16,0.16), 23, 0.6, 2.0, 5.0, fi);
        else w = mk(float2(-0.30,0.02), 0.6, 0.0, float2(0.10,0.10), 5, 0.6, 1.0, 5.0, fi);
    }
    // ---- tick fans bottom-left (53..56) ----
    else if (i <= 56u) {
        int k = (int)i - 53;
        if (k==0) w = mk(float2(-1.15,-0.58), 0.5, 0.0, float2(0.52,0.52), 16, 0.6, 1.0, 6.0, fi);
        else if (k==1) w = mk(float2(-1.05,-0.66), 0.55, 0.2, float2(0.36,0.36), 16, 0.6, 2.0, 6.0, fi);
        else if (k==2) w = mk(float2(-1.12,-0.60), 0.45, 0.0, float2(0.58,0.58), 27, 0.5, 1.0, 6.0, fi);
        else w = mk(float2(-1.10,-0.62), 0.5, 0.0, float2(0.44,0.44), 15, 0.6, 1.0, 6.0, fi);
    }
    // ---- corner tabs (57..62) ----
    else if (i <= 62u) {
        int k = (int)i - 57;
        float2 tp[6] = { float2(1.56,0.80), float2(1.60,0.18), float2(1.60,-0.52),
                         float2(-1.60,0.92), float2(0.32,0.92), float2(1.02,0.86) };
        w = mk(tp[k], 0.9, 0.0, float2(0.075,0.045), 8, 0.6, 1.0, 7.0, fi);
    }
    // ---- right instrument column (63..70) ----
    else if (i <= 70u) {
        int k = (int)i - 63;
        int kt[8] = {7,20,4,21,7,20,4,5};
        float y = 0.58 - (float)k * 0.17;
        w = mk(float2(1.62, y), 0.75, 0.0, float2(0.07,0.07), kt[k], 0.6, (k%2==0)?2.0:1.0, 8.0, fi);
    }
    // ---- background depth accents (71..84) small, faint, for parallax depth ----
    else if (i <= 84u) {
        int k = (int)i - 71;
        int kt[5] = {0,3,21,31,7};
        float2 p = float2(-1.3 + h11(fi*1.1)*2.9, -0.7 + h11(fi*2.7)*1.5);
        float sc = lerp(0.10, 0.26, h11(fi*4.4));
        w = mk(p, 0.20 + 0.22*h11(fi*5.5), 0.0, float2(sc,sc), kt[k%5], 0.5, 0.0, 9.0, fi);
    }

    // density gate
    if (h11(fi*0.37) > density) w.active = 0.0;

    Out[i] = w;
}
