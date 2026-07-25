// CRYOGRAM / CONSOLE — one layout, shared by the event reducer and the renderer.
//
// The panel follows the dock, so its aspect is arbitrary. The Program is 16:9
// and must NOT be stretched to fill it: the stage is fitted, and the leftover
// space becomes real gutters carrying tools rather than letterbox padding.
// Pointer coordinates are remapped into the stage rect, so a click lands on the
// specimen and not on some scaled approximation of it.

#ifndef CRYO_CONSOLE_LAYOUT
#define CRYO_CONSOLE_LAYOUT

struct ConsoleLayout {
    float4 stage;     // fitted 16:9 program stage, pixels
    float4 pad;       // tension XY pad, pixels
    float4 kinds;     // probe-kind button strip, pixels
    float4 witness;   // 3D witness thumbnail, pixels
    float  headerH;
    float  footerY;
    float  margin;
};

ConsoleLayout cryoLayout(float2 res) {
    ConsoleLayout L;
    L.margin  = clamp(res.x * 0.012, 8.0, 24.0);
    L.headerH = clamp(res.y * 0.070, 20.0, 46.0);
    float footerH = clamp(res.y * 0.190, 70.0, 150.0);
    L.footerY = res.y - footerH;

    float m = L.margin;
    float4 area = float4(m, L.headerH + m * 0.5, res.x - m, L.footerY - m * 0.5);

    float aw = max(area.z - area.x, 1.0);
    float ah = max(area.w - area.y, 1.0);
    const float target = 16.0 / 9.0;
    float w = min(aw, ah * target);
    float h = w / target;
    float cx = (area.x + area.z) * 0.5;
    float cy = (area.y + area.w) * 0.5;
    L.stage = float4(cx - w * 0.5, cy - h * 0.5, cx + w * 0.5, cy + h * 0.5);

    float fy0 = L.footerY + m * 0.4;
    float fy1 = res.y - m * 0.6;
    float fh = max(fy1 - fy0, 8.0);

    L.pad = float4(m, fy0, m + fh, fy1);                       // square
    float wW = fh * (16.0 / 9.0);
    L.witness = float4(res.x - m - wW, fy0, res.x - m, fy1);
    float kx0 = L.pad.z + m;
    float kx1 = max(L.witness.x - m, kx0 + 40.0);
    L.kinds = float4(kx0, fy1 - fh * 0.38, kx1, fy1);
    return L;
}

// Panel-normalized pointer -> stage-local 0..1. Returns false outside the stage.
bool cryoStageLocal(ConsoleLayout L, float2 res, float2 nrm, out float2 local) {
    float2 p = nrm * res;
    local = float2((p.x - L.stage.x) / max(L.stage.z - L.stage.x, 1.0),
                   (p.y - L.stage.y) / max(L.stage.w - L.stage.y, 1.0));
    return local.x >= 0.0 && local.x <= 1.0 && local.y >= 0.0 && local.y <= 1.0;
}

bool cryoInRect(float2 p, float4 r) {
    return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w;
}

#endif
