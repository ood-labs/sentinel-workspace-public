// SS_Haze / haze_view — the preview's drawing geometry, shared by hzart (the averaged field, per pixel) and layout
// (frames, type, the machines and the readout column): plan over long section on one z axis, laid out as the
// club's own drawing (SS_Venue) lays them out. Stage left, audience right; plan page-up = +x (house right);
// section seen from house left. Call hazeView(R, domain) first.
#ifndef SS_HZ_VIEW_HLSLI
#define SS_HZ_VIEW_HLSLI
#define HV_SIDE 280.0

static HzDomain gV;
static float gS, gX0, gPT, gPB, gSB;
void hazeView(float2 R, HzDomain d)
{
    gV = d;
    gS = max(min((R.x - HV_SIDE - 40.0) / (d.L * 1.02), (R.y - 46.0 - 50.0) / ((d.W + d.Ht * 1.05) * 1.02 + 4.0)), 1e-3);
    gX0 = max(20.0, 0.5 * (R.x - HV_SIDE - d.L * gS));
    gPT = 46.0;
    gPB = gPT + d.W * gS;
    gSB = gPB + 40.0 + d.Ht * 1.05 * gS;      // a 40 px gap holds the section's caption
}
float2 planPx(float3 p) { return float2(gX0 + (p.z - gV.zc + 0.5 * gV.L) * gS, gPT + (0.5 * gV.W - p.x) * gS); }
float2 sectPx(float3 p) { return float2(gX0 + (p.z - gV.zc + 0.5 * gV.L) * gS, gSB - (p.y - gV.floorY) * gS); }
float viewZ(float px) { return (px - gX0) / gS - 0.5 * gV.L + gV.zc; }
float viewX(float py) { return 0.5 * gV.W - (py - gPT) / gS; }
float viewY(float py) { return gV.floorY + (gSB - py) / gS; }
// the hall's walls in each view
float4 planRect() { return float4(gX0, gPT, gX0 + gV.L * gS, gPB); }
float4 sectRect() { return float4(gX0, gSB - gV.Ht * gS, gX0 + gV.L * gS, gSB); }
#endif
