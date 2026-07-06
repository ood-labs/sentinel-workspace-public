// prim_atlas — bakes 32 HUD primitives into an 8x4 grid atlas. Each cell is a
// self-contained primitive drawn in local space q in [-1,1]. Output channels:
//   R = body coverage (main linework)   G = core coverage (bright accents)
//   A = max(R,G)
// The widget renderer stamps these cells per instance with tint/scale/rot/depth.

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.2831853;
static const float PI  = 3.1415926;
static float BW = 0.030;   // base stroke width in q units

float ringC(float r, float r0, float w){ return 1.0 - smoothstep(0.0, w, abs(r - r0)); }
float band(float r, float a, float b){ return step(a, r) * step(r, b); }

void prim(int kind, float2 q, out float body, out float core)
{
    body = 0.0; core = 0.0;
    float r = length(q);
    float a = atan2(q.y, q.x);
    float w = BW;

    if (kind == 0) { body = ringC(r, 0.82, w*0.8); }                                   // ring thin
    else if (kind == 1) { body = ringC(r, 0.80, w*2.2); }                              // ring thick
    else if (kind == 2) { body = ringC(r, 0.80, w) * step(frac(a/TAU*24.0), 0.6); }    // dashed ring
    else if (kind == 3) {                                                              // tick ring
        body = band(r, 0.72, 0.86) * step(frac(a/TAU*48.0), 0.4);
        core = ringC(r, 0.90, w*0.7);
    }
    else if (kind == 4) {                                                              // reticle
        core = ringC(r, 0.78, w) * step(frac(a/TAU*4.0 + 0.02), 0.85);
        body = band(r, 0.55, 0.66) * step(frac(a/TAU*36.0), 0.4);
        float ch = (1.0-smoothstep(0.0,w,abs(q.x)))*step(r,0.9) + (1.0-smoothstep(0.0,w,abs(q.y)))*step(r,0.9);
        body = max(body, saturate(ch)*0.7);
        core = max(core, ringC(r, 0.30, w));
    }
    else if (kind == 5) {                                                              // crosshair
        float ch = (1.0-smoothstep(0.0,w,abs(q.x)))*step(abs(q.y),0.9)
                 + (1.0-smoothstep(0.0,w,abs(q.y)))*step(abs(q.x),0.9);
        body = saturate(ch);
        core = ringC(r, 0.20, w);
    }
    else if (kind == 6) {                                                              // plus marker
        float ch = (1.0-smoothstep(0.0,w*1.4,abs(q.x)))*step(abs(q.y),0.5)
                 + (1.0-smoothstep(0.0,w*1.4,abs(q.y)))*step(abs(q.x),0.5);
        core = saturate(ch);
    }
    else if (kind == 7) {                                                              // target (gapped concentric)
        core = ringC(r, 0.85, w) * step(0.15, frac(a/TAU*2.0));
        body = ringC(r, 0.60, w) * step(0.15, frac(a/TAU*2.0 + 0.5));
        core = max(core, ringC(r, 0.10, w*1.5));
    }
    else if (kind == 8) {                                                              // box frame
        float e = max(abs(q.x), abs(q.y));
        body = (1.0-smoothstep(0.0,w,abs(e-0.82))) * step(max(abs(q.x),abs(q.y)),0.9);
    }
    else if (kind == 9) {                                                              // box + header
        float e = max(abs(q.x), abs(q.y));
        body = (1.0-smoothstep(0.0,w,abs(e-0.82))) * step(e,0.9);
        core = step(abs(q.x),0.82) * step(q.y,0.82) * step(0.64,q.y);                  // header bar top
    }
    else if (kind == 10) {                                                             // corner brackets
        float len = 0.5;
        float2 aq = abs(q);
        float horiz = (1.0-smoothstep(0.0,w,abs(aq.y-0.82))) * step(aq.x,0.82) * step(0.82-len,aq.x);
        float vert  = (1.0-smoothstep(0.0,w,abs(aq.x-0.82))) * step(aq.y,0.82) * step(0.82-len,aq.y);
        body = saturate(horiz+vert);
    }
    else if (kind == 11) {                                                             // chevron / arrow bracket
        float2 aq = float2(abs(q.x), q.y);
        float d1 = abs(aq.x*0.7 + aq.y*0.7 - 0.1);
        body = (1.0-smoothstep(0.0,w,d1)) * step(aq.x,0.85) * step(-0.85,q.y) * step(q.y,0.85);
    }
    else if (kind == 12) {                                                             // warning triangle + !
        float2 aq = float2(abs(q.x), q.y);
        float edge = abs(aq.x*0.866 + aq.y*0.5 - 0.45);
        float onE = (1.0-smoothstep(0.0,w,edge))*step(q.y,0.5)*step(-0.62,q.y);
        float base = (1.0-smoothstep(0.0,w,abs(q.y+0.55)))*step(aq.x,0.66);
        core = max(onE, base);
        float bar = (1.0-smoothstep(0.0,w*1.3,aq.x))*step(-0.25,q.y)*step(q.y,0.18)*step(aq.x,0.06);
        float dot = 1.0-smoothstep(0.0,0.08,length(q-float2(0.0,-0.4)));
        core = max(core, max(bar,dot));
    }
    else if (kind == 13) {                                                             // diamond
        float d = abs(q.x)+abs(q.y);
        body = 1.0-smoothstep(0.0,w,abs(d-0.8));
    }
    else if (kind == 14) {                                                             // hexagon
        float2 aq = abs(q);
        float d = max(aq.x*0.866+aq.y*0.5, aq.y);
        body = 1.0-smoothstep(0.0,w,abs(d-0.78));
    }
    else if (kind == 15) {                                                             // half ring
        body = ringC(r, 0.80, w*1.6) * step(0.0, q.y);
        core = ringC(r, 0.80, w*1.6) * step(0.0, -q.y) * step(-0.3, q.y);
    }
    else if (kind == 16) {                                                             // tick fan (radiating arc)
        float wedge = step(-2.2, a) * step(a, 0.4);
        body = band(r, 0.60, 0.88) * step(frac(a/TAU*40.0), 0.35) * wedge;
        core = ringC(r, 0.90, w) * wedge;
    }
    else if (kind == 17) {                                                             // bars / histogram
        float n = 9.0;
        float col = floor((q.x*0.5+0.5)*n);
        float bx = frac((q.x*0.5+0.5)*n);
        float h = 0.3 + 0.6*frac(sin(col*12.9)*43758.5);
        float top = 0.8 - h*1.6;
        body = step(0.2,bx)*step(bx,0.8)*step(top,q.y)*step(q.y,0.8);
    }
    else if (kind == 18) {                                                             // hatch fill
        float hz = step(0.5, frac((q.x+q.y)*6.0));
        body = hz*0.6*step(max(abs(q.x),abs(q.y)),0.85);
    }
    else if (kind == 19) {                                                             // dot grid
        float2 g = frac(q*3.0)-0.5;
        body = (1.0-smoothstep(0.0,0.12,length(g)))*step(max(abs(q.x),abs(q.y)),0.9);
    }
    else if (kind == 20) {                                                             // mini dial
        body = ringC(r,0.80,w);
        core = band(r,0.60,0.74)*step(frac(a/TAU*24.0),0.4);
        core = max(core, ringC(r,0.86,w)*step(frac(a/TAU+0.75),0.62));
        core = max(core, 1.0-smoothstep(0.0,0.08,r));
    }
    else if (kind == 21) {                                                             // concentric dots
        core = ringC(r,0.4,w)+ringC(r,0.7,w)*0.7;
        body = ringC(r,0.9,w*0.7);
    }
    else if (kind == 22) {                                                             // waveform
        float y = 0.35*sin(q.x*8.0)*sin(q.x*3.0+1.0);
        body = (1.0-smoothstep(0.0,w*1.5,abs(q.y-y)))*step(abs(q.x),0.9);
    }
    else if (kind == 23) {                                                             // segmented arc
        core = ringC(r,0.80,w*1.8)*step(frac(a/TAU*8.0),0.7)*step(0.0,q.y);
    }
    else if (kind == 24) {                                                             // text block (fake rows)
        float rows = 5.0;
        float ry = floor((q.y*0.5+0.5)*rows);
        float rl = 0.4+0.5*frac(sin(ry*7.1)*99.0);
        float inRow = step(0.15, frac((q.y*0.5+0.5)*rows))*step(frac((q.y*0.5+0.5)*rows),0.6);
        float dash = step(0.35, frac((q.x*0.5+0.5)*22.0));
        body = inRow*dash*step(-0.8,q.x)*step(q.x,-0.8+rl*1.6);
    }
    else if (kind == 25) {                                                             // slider
        body = (1.0-smoothstep(0.0,w,abs(q.y)))*step(abs(q.x),0.85);
        core = 1.0-smoothstep(0.0,0.14,length(q-float2(0.3,0.0)));
    }
    else if (kind == 26) {                                                             // node dot (glow)
        core = exp(-r*r*6.0);
        body = ringC(r,0.5,w);
    }
    else if (kind == 27) {                                                             // radial ticks (full)
        body = band(r,0.55,0.85)*step(frac(a/TAU*32.0),0.35);
    }
    else if (kind == 28) {                                                             // scanline block
        float sl = step(0.5, frac(q.y*10.0));
        body = sl*0.5*step(max(abs(q.x),abs(q.y)),0.85);
    }
    else if (kind == 29) {                                                             // grid cell (3x3)
        float2 gc = frac((q*0.5+0.5)*3.0);
        float ln = step(gc.x,0.06)+step(0.94,gc.x)+step(gc.y,0.06)+step(0.94,gc.y);
        body = saturate(ln)*step(max(abs(q.x),abs(q.y)),0.9);
    }
    else if (kind == 30) {                                                             // solid disc (faint)
        body = (1.0-smoothstep(0.78,0.82,r))*0.5;
        core = ringC(r,0.80,w);
    }
    else {                                                                            // 31 gapped ring pair
        body = ringC(r,0.85,w)*step(0.12,frac(a/TAU*3.0));
        core = ringC(r,0.65,w*1.4)*step(0.12,frac(a/TAU*3.0+0.4));
    }
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    int col = (int)floor(uv.x * 8.0);
    int row = (int)floor(uv.y * 4.0);
    int kind = row * 8 + col;

    float2 local = frac(uv * float2(8.0, 4.0));
    float2 q = (local - 0.5) * 2.0 / 0.90;   // slight inset margin

    float body, core;
    prim(kind, q, body, core);

    OutputUAV[pixel] = float4(body, core, 0.0, max(body, core));
}
