// kidpix_stamp_atlas — bakes a 4x4 grid of classic Kid Pix rubber-stamp icons into one texture,
// each cell in local q in [-1,1]. Stores straight icon COLOR in rgb and coverage in a (the swarm
// renderer stamps cells from it). Simple flat SDF glyphs, hard-edged. Static bake.
//   0 heart  1 star  2 ghost  3 lightbulb  4 sun  5 fish  6 flower  7 smiley
//   8 diamond 9 moon 10 cloud 11 tree 12 arrow 13 house 14 drop 15 spiral
RWTexture2D<float4> OutputUAV : register(u0);

float sdCircle(float2 p, float r){ return length(p) - r; }
float sdBox(float2 p, float2 b){ float2 d = abs(p) - b; return length(max(d,0.0)) + min(max(d.x,d.y),0.0); }
float sdSeg(float2 p, float2 a, float2 b){ float2 pa=p-a, ba=b-a; float h=saturate(dot(pa,ba)/dot(ba,ba)); return length(pa-ba*h); }
float sdTri(float2 p, float2 a, float2 b, float2 c)
{
    float2 e0=b-a, e1=c-b, e2=a-c, v0=p-a, v1=p-b, v2=p-c;
    float2 pq0=v0-e0*saturate(dot(v0,e0)/dot(e0,e0));
    float2 pq1=v1-e1*saturate(dot(v1,e1)/dot(e1,e1));
    float2 pq2=v2-e2*saturate(dot(v2,e2)/dot(e2,e2));
    float s=sign(e0.x*e2.y-e0.y*e2.x);
    float2 d=min(min(float2(dot(pq0,pq0),s*(v0.x*e0.y-v0.y*e0.x)),
                     float2(dot(pq1,pq1),s*(v1.x*e1.y-v1.y*e1.x))),
                     float2(dot(pq2,pq2),s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}
float sdStar(float2 p, float r, int n)
{
    float an = 3.14159265/(float)n;
    float a = atan2(p.x, -p.y);
    float sec = fmod(a + 100.0*an, 2.0*an) - an;
    float2 q = length(p) * float2(cos(sec), abs(sin(sec)));
    q -= float2(r, 0);
    q += float2(clamp(-q.x, 0.0, r*0.4), 0.0);
    return length(max(q, 0.0)) * sign(q.y);
}

// returns coverage (1 inside) and writes color
float icon(int k, float2 q, out float3 col)
{
    col = float3(0,0,0);
    float d = 1e9; float cov = 0.0;
    if (k == 0) {                                   // heart (red)
        float2 p = q * 1.15; p.y += 0.15;
        float a = sdCircle(p - float2(-0.28,-0.18), 0.34);
        float b = sdCircle(p - float2( 0.28,-0.18), 0.34);
        float t = sdTri(p, float2(-0.60,-0.10), float2(0.60,-0.10), float2(0.0,0.75));
        d = min(min(a,b), t); col = float3(0.90,0.12,0.16);
    } else if (k == 1) {                            // star (yellow)
        d = sdStar(q, 0.85, 5); col = float3(0.98,0.82,0.10);
    } else if (k == 2) {                            // ghost (white body, dark eyes)
        float body = min(sdCircle(q - float2(0,-0.15), 0.6), sdBox(q - float2(0,0.35), float2(0.6,0.45)));
        d = body; col = float3(0.96,0.96,0.98);
        cov = smoothstep(0.02,-0.02,d);
        float eyes = min(sdCircle(q-float2(-0.22,-0.2),0.10), sdCircle(q-float2(0.22,-0.2),0.10));
        if (smoothstep(0.02,-0.02,eyes) > 0.5) col = float3(0.05,0.05,0.06);
        return saturate(cov + smoothstep(0.02,-0.02,eyes));
    } else if (k == 3) {                            // lightbulb (yellow bulb + grey base)
        float bulb = sdCircle(q - float2(0,-0.1), 0.5);
        float base = sdBox(q - float2(0,0.55), float2(0.22,0.18));
        d = min(bulb, base); col = (smoothstep(0.02,-0.02,base) > 0.5) ? float3(0.5,0.5,0.55) : float3(0.98,0.85,0.15);
    } else if (k == 4) {                            // sun (orange disc + rays)
        d = sdCircle(q, 0.5); col = float3(0.98,0.55,0.10);
        float rays = 1e9;
        for (int i=0;i<8;i++){ float a=(float)i/8.0*6.2831; float2 dir=float2(cos(a),sin(a)); rays=min(rays,sdSeg(q,dir*0.6,dir*0.92)); }
        cov = max(smoothstep(0.02,-0.02,d), smoothstep(0.06,0.03,rays));
        return cov;
    } else if (k == 5) {                            // fish (cyan)
        float body = sdCircle(q*float2(0.7,1.0), 0.55);
        float tail = sdTri(q, float2(0.4,0.0), float2(0.9,-0.35), float2(0.9,0.35));
        d = min(body, tail); col = float3(0.12,0.75,0.82);
    } else if (k == 6) {                            // flower (magenta petals + yellow center)
        float pet = 1e9;
        for (int i=0;i<6;i++){ float a=(float)i/6.0*6.2831; pet=min(pet, sdCircle(q-float2(cos(a),sin(a))*0.42, 0.30)); }
        d = pet; col = float3(0.90,0.15,0.72);
        cov = smoothstep(0.02,-0.02,d);
        float ctr = sdCircle(q, 0.22);
        if (smoothstep(0.02,-0.02,ctr) > 0.5) col = float3(0.98,0.82,0.10);
        return saturate(cov + smoothstep(0.02,-0.02,ctr));
    } else if (k == 7) {                            // smiley (yellow + face)
        d = sdCircle(q, 0.6); col = float3(0.98,0.82,0.10);
        cov = smoothstep(0.02,-0.02,d);
        float eyes = min(sdCircle(q-float2(-0.22,-0.15),0.08), sdCircle(q-float2(0.22,-0.15),0.08));
        float mouth = abs(sdCircle(q-float2(0,-0.05),0.35)) - 0.05; mouth = max(mouth, q.y-0.28); mouth=max(mouth,-(q.y-0.05));
        float feat = max(smoothstep(0.02,-0.02,eyes), smoothstep(0.04,0.0,mouth));
        if (feat > 0.5) col = float3(0.10,0.08,0.05);
        return cov;
    } else if (k == 8) {                            // diamond (blue)
        d = sdBox(float2(q.x*0.7, q.y*0.9), float2(0.5,0.5)); // rotated look via aspect
        float rot = abs(q.x)+abs(q.y)-0.7; d = rot; col = float3(0.15,0.35,0.90);
    } else if (k == 9) {                            // crescent moon (yellow)
        float a = sdCircle(q, 0.55);
        float b = sdCircle(q - float2(0.28,-0.05), 0.5);
        d = max(a, -b); col = float3(0.98,0.85,0.20);
    } else if (k == 10) {                           // cloud (light blue)
        float c = min(min(sdCircle(q-float2(-0.35,0.05),0.35), sdCircle(q-float2(0.0,-0.1),0.45)), sdCircle(q-float2(0.35,0.05),0.35));
        float bar = sdBox(q-float2(0,0.22), float2(0.6,0.18));
        d = min(c, bar); col = float3(0.55,0.75,0.95);
    } else if (k == 11) {                           // tree (green top + brown trunk)
        float top = sdTri(q, float2(-0.5,0.35), float2(0.5,0.35), float2(0.0,-0.7));
        float trunk = sdBox(q-float2(0,0.6), float2(0.12,0.3));
        d = min(top, trunk); col = (smoothstep(0.02,-0.02,trunk)>0.5)? float3(0.45,0.28,0.12): float3(0.15,0.65,0.20);
    } else if (k == 12) {                           // arrow (black)
        float shaft = sdBox(q, float2(0.5,0.14));
        float head = sdTri(q, float2(0.3,-0.4), float2(0.3,0.4), float2(0.85,0.0));
        d = min(shaft, head); col = float3(0.06,0.06,0.07);
    } else if (k == 13) {                           // house (red body + roof)
        float body = sdBox(q-float2(0,0.2), float2(0.45,0.35));
        float roof = sdTri(q, float2(-0.55,-0.15), float2(0.55,-0.15), float2(0.0,-0.7));
        d = min(body, roof); col = (smoothstep(0.02,-0.02,roof)>0.5)? float3(0.5,0.15,0.10): float3(0.88,0.20,0.16);
    } else if (k == 14) {                           // water drop (blue)
        float c = sdCircle(q-float2(0,0.2), 0.42);
        float t = sdTri(q, float2(-0.30,0.1), float2(0.30,0.1), float2(0.0,-0.7));
        d = min(c,t); col = float3(0.15,0.45,0.92);
    } else {                                        // spiral (purple) — concentric arcs
        float r = length(q);
        float ring = abs(frac(r*3.5)-0.5)-0.18;
        d = ring; if (r > 0.9) d = 1.0;
        col = float3(0.5,0.18,0.78);
    }
    cov = smoothstep(0.02, -0.02, d);
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    int col = (int)(uv.x * 4.0);
    int row = (int)(uv.y * 4.0);
    int k = row * 4 + col;
    float2 q = (frac(uv * 4.0) * 2.0 - 1.0) * 1.15;    // slight padding

    float3 ic; float cov = icon(k, q, ic);
    OutputUAV[px] = float4(ic, cov);                   // straight color + coverage
}
