// RS_Plan / canvas.hlsl — the editor surface.
//
// A draughtsman's CLEARANCE SECTION over a CROSS-SECTION ROSETTE, not a copy of the program
// image. The program image looks straight down the axis, which is exactly the one projection
// that cannot show the axis — so the diagram shows what that view hides.
//
// Reading it should answer, without opening the renderer: how wide is the bore at each station,
// what is bolted to which wall and how far it reaches inward, where every light sits, which
// records are hand-edited or switched off, where the eye is on the loop right now — and
// crucially WHETHER ANYTHING IS IN THE WAY. The flight tube is drawn as a dashed line and
// anything intruding into it turns red, so a heatsink you would fly through is visible here
// instead of being discovered later as a black frame.
//
// Every handle is drawn through the same helpers plan.hlsl picks with, so what you can see is
// exactly what you can grab.
#include "../_shared/shaft.hlsli"

StructuredBuffer<RsRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// INSTRUMENT PALETTE, taken from interaction_lab's sui3 theme: a near-black neutral ground, a
// monochrome value ladder, and ONE accent.
//
// ACCENT CONTRACT (inherited deliberately): amber means the active selection or an established
// live reading — where the eye is on the loop — and nothing else. It is never hover, never
// decoration, never an idle control. Edit state and kind identity therefore have to be carried
// by VALUE rather than by hue, which is the whole discipline.
#define INK       float3(0.0055, 0.0060, 0.0065)   // field
#define INK_WELL  float3(0.0125, 0.0135, 0.0145)   // well
#define INK_GRID  float3(0.0520, 0.0545, 0.0510)
#define INK_AXIS  float3(0.2200, 0.2250, 0.2150)   // rule
#define DIMC      float3(0.3800, 0.3850, 0.3700)   // dim
#define MIDC      float3(0.6000, 0.6050, 0.5800)   // mid
#define CHALK     float3(0.9000, 0.9050, 0.8800)   // ink
#define ACCENT    float3(1.000, 0.420, 0.090)      // SUI3_AMBER — reserved

// The ONE named exception to the monochrome rule. A clearance violation is the diagram's only
// alarm — the single state that means "this shaft cannot be flown" — and it must not be
// confusable with the accent, which is why it is not amber. Borrowed from the sui3 axis triad
// rather than invented, so the project introduces no new chroma of its own.
#define ALARM     float3(1.000, 0.250, 0.300)

// WHERE HUE IS STILL SPENT. The ground, the chrome, the fills, the ticks and the fixture ramp
// are monochrome. Hue is reserved for four things that a value alone genuinely cannot say:
//   1. amber accent  — selection, and where the eye is right now
//   2. alarm red     — the shaft cannot be flown
//   3. wall identity — which of three walls a thing is bolted to
//   4. lamp colour   — what colour that tube actually burns
// Everything else stays grey. Fully monochrome was tried first and lost: three identical grey
// curves are a tangle, and a schematic that cannot tell a magenta tube from a cyan one is
// throwing away information the records already hold.

// Muted enough to sit inside the instrument palette, separated enough to tell three walls apart.
static const float3 RS_FACECOL[3] = {
    float3(0.400, 0.505, 0.590),
    float3(0.530, 0.455, 0.585),
    float3(0.405, 0.560, 0.495)
};

// Fixture kind by VALUE, a ramp from rule to ink. Six hues would blow the budget on a
// distinction the legend below can carry, and the legend uses the same ramp so the mapping is
// readable off the diagram rather than memorised.
float3 fixColour(int k)
{
    float t = saturate((float)k / (float)(FK_KINDS - 1));
    return lerp(INK_AXIS * 1.45, CHALK, t);
}

// The lamp's real colour, pulled toward grey and renormalized to a constant brightness. Keeping
// the hue says WHICH tube; fixing the luminance stops a saturated magenta reading as dimmer than
// a white one when both are equally live.
float3 planLightCol(RsRec r, int pal)
{
    float3 raw = rs_lightCol(r, pal);
    float l = dot(raw, float3(0.2126, 0.7152, 0.0722));
    // 0.40 rather than 0.52: at higher saturation a warm lamp lands almost exactly on the
    // reserved accent, and a lamp that looks like a selection breaks the one colour rule the
    // diagram actually depends on.
    float3 c = lerp(l.xxx, raw, 0.40);
    return c * (0.88 / max(dot(c, float3(0.2126, 0.7152, 0.0722)), 1e-3));
}

float disc(float2 uv, float2 c, float r, float2 asp, float px)
{
    return 1.0 - smoothstep(r - px, r + px, length((uv - c) * asp));
}
float ring(float2 uv, float2 c, float r, float w, float2 asp, float px)
{
    float d = abs(length((uv - c) * asp) - r);
    return 1.0 - smoothstep(w - px, w + px, d);
}
float band(float y, float lo, float hi, float px)
{
    return smoothstep(min(lo, hi) - px, min(lo, hi) + px, y)
         * (1.0 - smoothstep(max(lo, hi) - px, max(lo, hi) + px, y));
}

RsProfile profileAtZ(float zw)
{
    int i0, i1, i2, i3; float t;
    rs_staFrame(rs_wrapZ(zw), i0, i1, i2, i3, t);
    return rs_profileFrom(Plan[RS_STA_0 + (uint)i0], Plan[RS_STA_0 + (uint)i1],
                          Plan[RS_STA_0 + (uint)i2], Plan[RS_STA_0 + (uint)i3], t);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    float2 uv  = ((float2)pixel + 0.5) / float2(W, H);
    float2 asp = float2((float)W / max((float)H, 1.0), 1.0);
    float  px  = 1.0 / (float)H;

    RsRec hdr   = Plan[RS_HEADER];
    float sel    = hdr.pos.y;
    float travel = hdr.phase;
    // transport, toggled by Space. Must match plan.hlsl's decode, including the legacy 1.0 case.
    float running = (hdr.tone < 1.5) ? 1.0 : ((hdr.tone > 2.5) ? 1.0 : 0.0);
    float packed = hdr.flags;
    uint style   = (uint)floor(packed / 262144.0);
    float rem    = packed - (float)style * 262144.0;
    uint viol    = (uint)floor(rem / 4096.0);
    rem -= (float)viol * 4096.0;
    uint liveL   = (uint)floor(rem / 64.0);
    uint liveF   = (uint)(rem - (float)liveL * 64.0);

    int rosSta = rs_rosStation(sel, travel);

    float3 col = INK;

    // =====================================================================================
    // STRIP 1 — the clearance section. z across, distance from the flight axis up.
    // =====================================================================================
    bool inLon = (uv.x > RS_LON_X0 && uv.x < RS_LON_X1 &&
                  uv.y > RS_LON_Y0 && uv.y < RS_LON_Y1);

    // station grid, drawn under everything
    for (uint g = 0u; g < RS_STATIONS; g++)
    {
        float gx = rs_zToX((float)g * RS_STATION_Z);
        float lw = (Plan[RS_STA_0 + g].active > 0.5) ? 0.0009 : 0.0005;
        float hit = 1.0 - smoothstep(lw, lw + px, abs(uv.x - gx));
        if (uv.y > RS_LON_Y0 - 0.018 && uv.y < RS_LON_Y1 + 0.018) col = lerp(col, INK_GRID, hit);
    }

    if (inLon)
    {
        float z = rs_xToZ(uv.x);
        RsProfile pf = profileAtZ(z);
        float r = rs_yToR(uv.y);

        // THE WALL SOLID, one translucent layer per face, filled OUTWARD from each face plane.
        // Three overlapping fills is not decoration: where they separate is exactly how
        // eccentric the bore has become, and the dark band underneath is the air you fly in.
        float eps = px * 2.0 * RS_WORLD_R;
        float minFd = 1e9;
        for (int f = 0; f < 3; f++)
        {
            float fd = rs_faceAxisDist(pf, f);
            minFd = min(minFd, fd);
            // On a near-black instrument ground the wall needs more fill than it did on a blue
            // one, or the solid and the air you fly in become the same nothing.
            float inWall = smoothstep(fd - eps, fd + eps, r);
            col = lerp(col, lerp(INK, RS_FACECOL[f], 0.42), inWall * 0.48);
            float rule = 1.0 - smoothstep(0.0012, 0.0012 + px, abs(uv.y - rs_rToY(fd)));
            col = lerp(col, RS_FACECOL[f], rule * 0.85);
        }

        // wall panel cadence, so the surface scale is legible from the diagram
        float cellz = frac(z / max(pf.panel, 0.10) * 0.5);
        col = lerp(col, col * 1.30, step(minFd, r) * step(cellz, 0.5) * 0.45);
    }

    // fixtures, drawn as bars reaching inward from their own face
    for (uint fi = 0u; fi < RS_FIXES; fi++)
    {
        RsRec r = Plan[RS_FIX_0 + fi];
        uint sta = rs_staOfFix(RS_FIX_0 + fi);
        float zw = rs_recZ(sta, r);
        RsProfile pf = profileAtZ(zw);
        RsFixGeo g = rs_fixGeo(r, pf);
        int face = (int)clamp(r.grp, 0.0, 2.0);
        bool on = r.active > 0.5;
        bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == RS_FIX_0 + fi);
        bool edited = (((uint)r.flags) & F_EDITED) != 0u;
        bool clash = g.clr < flight_clear;

        float dz = rs_wrapDZ(rs_xToZ(uv.x) - zw);
        float inZ = 1.0 - smoothstep(g.zh - px * 2.0, g.zh + px * 2.0, abs(dz));
        // drawn from the FACE CURVE it is bolted to down to its exact clearance, so a block
        // sitting out toward a corner still visibly touches its own wall instead of floating
        float yFace = rs_rToY(rs_faceAxisDist(pf, face));
        float yIn   = rs_rToY(g.clr);
        float inY = band(uv.y, yFace, yIn, px);
        float cov = inZ * inY * (inLon ? 1.0 : 0.0);

        float3 fc = clash ? ALARM : fixColour((int)r.kind);
        col = lerp(col, fc, cov * (on ? 0.62 : 0.14));
        // hard inner edge — the surface that actually eats the clearance
        float edge = inZ * (1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.y - yIn))) * (inLon ? 1.0 : 0.0);
        col = lerp(col, clash ? ALARM : lerp(fc, CHALK, 0.45), edge * (on ? 1.0 : 0.30));

        if (edited)
        {
            float m = inZ * (1.0 - smoothstep(0.0009, 0.0009 + px, abs(uv.y - (yFace - 0.0055))));
            col = lerp(col, MIDC, m * 0.9 * (inLon ? 1.0 : 0.0));
        }
        if (isSel)
        {
            float2 c = float2(rs_zToX(zw), (yFace + yIn) * 0.5);
            col = lerp(col, ACCENT, ring(uv, c, 0.020, 0.0020, asp, px));
        }
        // which wall it is on, as a tick under the strip
        float tick = inZ * band(uv.y, RS_LON_Y1 + 0.006 + (float)face * 0.0055,
                                      RS_LON_Y1 + 0.0095 + (float)face * 0.0055, px);
        col = lerp(col, RS_FACECOL[face], tick * (on ? 0.85 : 0.20));
    }

    // lights
    for (uint li = 0u; li < RS_LIGHTS; li++)
    {
        RsRec r = Plan[RS_LIGHT_0 + li];
        uint sta = rs_staOfLight(RS_LIGHT_0 + li);
        float zw = rs_recZ(sta, r);
        RsProfile pf = profileAtZ(zw);
        float2 tg; float2 sp = rs_lightSection(r, pf, tg);
        // plotted at the SAME measure as a fixture — nearest approach to the flight axis — so
        // the two families can be compared against the flight tube without a mental correction
        float2 hp = float2(rs_zToX(zw), rs_rToY(rs_lightClear(r, pf)));
        bool on = r.active > 0.5;
        bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == RS_LIGHT_0 + li);
        bool edited = (((uint)r.flags) & F_EDITED) != 0u;
        float3 lc = planLightCol(r, pf.pal);

        if ((int)r.kind == LK_RUN)
        {
            // a run has real extent along the shaft — draw it as one
            float dz = rs_wrapDZ(rs_xToZ(uv.x) - zw);
            float inZ = 1.0 - smoothstep(r.size.x - px, r.size.x + px, abs(dz));
            float inY = 1.0 - smoothstep(0.0022, 0.0022 + px, abs(uv.y - hp.y));
            col = lerp(col, lc, inZ * inY * (on ? 1.0 : 0.22));
        }
        else
        {
            float rad = ((int)r.kind == LK_FLOOD) ? 0.0075 : 0.0052;
            col = lerp(col, lc, disc(uv, hp, rad, asp, px) * (on ? 1.0 : 0.22));
            if ((int)r.kind == LK_FLOOD)
                col = lerp(col, lc, ring(uv, hp, 0.0125, 0.0010, asp, px) * (on ? 0.7 : 0.2));
        }
        if (edited) col = lerp(col, MIDC, ring(uv, hp, 0.0125, 0.0010, asp, px) * 0.85);
        if (isSel)  col = lerp(col, ACCENT,   ring(uv, hp, 0.0175, 0.0020, asp, px));
    }

    // station handles: grab one and drag it up or down to widen or narrow the bore there
    for (uint si = 0u; si < RS_STATIONS; si++)
    {
        RsRec r = Plan[RS_STA_0 + si];
        RsProfile pf = profileAtZ((float)si * RS_STATION_Z);
        float2 hp = float2(rs_zToX((float)si * RS_STATION_Z), rs_rToY(pf.rin));
        bool on = r.active > 0.5;
        bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == RS_STA_0 + si);
        bool edited = (((uint)r.flags) & F_EDITED) != 0u;
        float3 hc = MIDC;
        col = lerp(col, on ? hc : INK_AXIS, disc(uv, hp, 0.0092, asp, px));
        col = lerp(col, CHALK, ring(uv, hp, 0.0092, 0.0012, asp, px) * (on ? 0.85 : 0.30));
        if (edited) col = lerp(col, MIDC, ring(uv, hp, 0.0145, 0.0011, asp, px) * 0.85);
        if (isSel)  col = lerp(col, ACCENT,   ring(uv, hp, 0.0200, 0.0021, asp, px));
    }

    // THE FLIGHT TUBE. The dashed line is the radius the eye needs kept clear. Where a fixture
    // has eaten into it the line goes solid red — a shaft you cannot fly down is visible in the
    // diagram rather than discovered as a black frame.
    if (inLon)
    {
        float yF = rs_rToY(flight_clear);
        float lineF = 1.0 - smoothstep(0.0010, 0.0010 + px, abs(uv.y - yF));
        float z = rs_xToZ(uv.x);
        bool blocked = false;
        for (uint c2 = 0u; c2 < RS_FIXES; c2++)
        {
            RsRec r = Plan[RS_FIX_0 + c2];
            if (r.active < 0.5) continue;
            uint sta = rs_staOfFix(RS_FIX_0 + c2);
            float zw = rs_recZ(sta, r);
            if (abs(rs_wrapDZ(z - zw)) > r.phase) continue;
            RsProfile pf = profileAtZ(zw);
            if (rs_fixGeo(r, pf).clr < flight_clear) blocked = true;
        }
        float dash = blocked ? 1.0 : step(0.42, frac(uv.x * 210.0));
        col = lerp(col, blocked ? ALARM : DIMC, lineF * dash * 0.95);
    }

    // travel playhead, with the stretch of shaft about to arrive. The playhead carries the
    // transport state: a stopped playhead that looks identical to a moving one is a readout that
    // lies about why nothing is happening.
    float3 headCol = (running > 0.5) ? ACCENT : DIMC;
    if (inLon)
    {
        float tx = rs_zToX(travel);
        float dz = rs_wrapZ(rs_xToZ(uv.x) - travel);
        // a neutral value lift, not a colour wash: the accent belongs on the playhead itself,
        // and spreading it across a third of the diagram is exactly the decorative use the
        // accent contract forbids
        col = lerp(col, col + MIDC * 0.055, saturate(1.0 - dz / 8.0));
        float ph = 1.0 - smoothstep(0.0011, 0.0011 + px, abs(uv.x - tx));
        // paused draws as a dashed line, so the state is legible even in a still capture
        float dash = (running > 0.5) ? 1.0 : step(0.42, frac(uv.y * 150.0));
        col = lerp(col, headCol, ph * dash * 0.95);
    }

    // THE SCRUB RULER. Drawn as a real track with station ticks and a knob, because an invisible
    // hit region is a feature nobody finds. It spans the same z range as the clearance section
    // directly below it, so a position on the ruler is a position on the shaft.
    {
        float2 rc = float2((RS_LON_X0 + RS_LON_X1) * 0.5, (RS_SCRUB_Y0 + RS_SCRUB_Y1) * 0.5);
        float2 rh2 = float2((RS_LON_X1 - RS_LON_X0) * 0.5, (RS_SCRUB_Y1 - RS_SCRUB_Y0) * 0.5);
        float2 d2 = abs(uv - rc) - rh2;
        float inBand = 1.0 - step(0.0, max(d2.x, d2.y));
        col = lerp(col, INK_GRID * 0.85, inBand * 0.9);

        if (inBand > 0.5)
        {
            // station ticks, taller at station 0 so the loop origin is findable
            for (uint s2 = 0u; s2 < RS_STATIONS; s2++)
            {
                float sx = rs_zToX((float)s2 * RS_STATION_Z);
                float tall = (s2 == 0u) ? 0.011 : 0.006;
                float tick = (1.0 - smoothstep(0.0007, 0.0007 + px, abs(uv.x - sx)))
                           * step(uv.y, RS_SCRUB_Y1 - 0.004)
                           * step(RS_SCRUB_Y1 - 0.004 - tall, uv.y);
                col = lerp(col, INK_AXIS, tick * 0.95);
            }
            // the stretch already flown, filled behind the knob — a value step, not a tint
            float flown = step(uv.x, rs_zToX(travel));
            col = lerp(col, INK_AXIS * 0.42, flown * 0.75);
        }
        float border = 1.0 - smoothstep(0.0009, 0.0009 + px, abs(max(d2.x, d2.y)));
        col = lerp(col, INK_AXIS, border * 0.8);

        // the knob
        float kx = rs_zToX(travel);
        float2 kc = float2(kx, rc.y);
        float2 kd = abs(uv - kc) - float2(0.0038, rh2.y - 0.004);
        float knob = 1.0 - step(0.0, max(kd.x, kd.y));
        col = lerp(col, headCol, knob);
        float kEdge = 1.0 - smoothstep(0.0008, 0.0008 + px, abs(max(kd.x, kd.y)));
        col = lerp(col, CHALK, kEdge * 0.75);
    }

    // transport glyph above the strip: a play triangle or a pause bar pair
    {
        float2 g = (uv - float2(0.0205, (RS_SCRUB_Y0 + RS_SCRUB_Y1) * 0.5)) * asp / 0.0115;
        if (running > 0.5)
        {
            float tri = step(abs(g.y), saturate(1.0 - g.x * 0.85)) * step(-0.05, g.x) * step(g.x, 1.15);
            col = lerp(col, ACCENT, tri);
        }
        else
        {
            float bars = step(abs(g.y), 1.0)
                       * saturate(step(abs(g.x + 0.42), 0.24) + step(abs(g.x - 0.42), 0.24));
            col = lerp(col, DIMC, bars);
        }
    }

    // =====================================================================================
    // STRIP 2 — the cross-section rosette. The one projection that can show WHICH WALL.
    // =====================================================================================
    {
        float2 rc = float2(RS_ROS_CX, RS_ROS_CY);
        float rd = length((uv - rc) * asp);
        if (rd < RS_ROS_R * 1.20)
        {
            RsProfile pf = profileAtZ((float)rosSta * RS_STATION_Z);
            float rosW = rs_rosWorld(pf.rin);
            float2 s = rs_uvToSec(uv, asp, rosW);
            float k = RS_ROS_R / rosW;
            float spx = px / k;                       // one screen pixel in section units

            float d = rs_bore(s, pf, (int)style);     // > 0 inside the bore
            // wall solid
            col = lerp(col, INK_GRID * 1.5, smoothstep(spx, -spx, d) * 0.85);
            // bore interior, tinted by the palette in force here
            float3 tint = MIDC;
            col = lerp(col, lerp(INK, tint, 0.13), smoothstep(-spx, spx, d));
            // the wall line itself
            col = lerp(col, lerp(CHALK, tint, 0.35),
                       1.0 - smoothstep(spx * 1.2, spx * 2.4, abs(d)));

            // fixtures, drawn as their real section footprint on their real face
            for (uint fk = 0u; fk < RS_FIX_PER; fk++)
            {
                uint idx = RS_FIX_0 + (uint)rosSta * RS_FIX_PER + fk;
                RsRec r = Plan[idx];
                RsFixGeo g = rs_fixGeo(r, pf);
                bool on = r.active > 0.5;
                bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == idx);
                bool edited = (((uint)r.flags) & F_EDITED) != 0u;
                bool clash = g.clr < flight_clear;
                float2 dd = s - (g.face + g.nIn * g.pr * 0.5);
                float2 q = abs(float2(dot(dd, g.tang), dot(dd, g.nIn))) - float2(g.hw, g.pr * 0.5);
                float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
                float3 fc = clash ? ALARM : fixColour((int)r.kind);
                col = lerp(col, fc, smoothstep(spx, -spx, sd) * (on ? 0.55 : 0.12));
                col = lerp(col, lerp(fc, CHALK, 0.4),
                           (1.0 - smoothstep(spx * 1.0, spx * 2.2, abs(sd))) * (on ? 1.0 : 0.28));
                if (edited)
                    col = lerp(col, MIDC, (1.0 - smoothstep(spx * 1.0, spx * 2.4, abs(sd + spx * 3.5))) * 0.7);
                if (isSel)
                    col = lerp(col, ACCENT, 1.0 - smoothstep(spx * 1.2, spx * 3.0, abs(sd + spx * 6.0)));
            }

            // lights
            for (uint lk = 0u; lk < RS_LIGHT_PER; lk++)
            {
                uint idx = RS_LIGHT_0 + (uint)rosSta * RS_LIGHT_PER + lk;
                RsRec r = Plan[idx];
                float2 tg; float2 sp = rs_lightSection(r, pf, tg);
                bool on = r.active > 0.5;
                bool isSel = (sel > 0.5) && ((uint)(sel - 1.0) == idx);
                float3 lc = planLightCol(r, pf.pal);
                float sd;
                if ((int)r.kind == LK_BAR)
                {
                    float2 dd = s - sp;
                    float2 q = abs(float2(dot(dd, tg), dot(dd, float2(-tg.y, tg.x)))) - float2(r.size.x, r.size.y);
                    sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
                }
                else
                {
                    sd = length(s - sp) - max(r.size.y, 0.028);
                }
                col = lerp(col, lc, smoothstep(spx, -spx * 1.5, sd) * (on ? 1.0 : 0.22));
                col += lc * exp(-max(sd, 0.0) / 0.10) * (on ? 0.30 : 0.04);
                if (isSel)
                    col = lerp(col, ACCENT, 1.0 - smoothstep(spx * 1.2, spx * 3.0, abs(sd + spx * 5.0)));
            }

            // the flight tube, in section
            float fr = flight_clear;
            bool blocked = false;
            for (uint fb = 0u; fb < RS_FIX_PER; fb++)
            {
                RsRec r = Plan[RS_FIX_0 + (uint)rosSta * RS_FIX_PER + fb];
                if (r.active < 0.5) continue;
                if (rs_fixGeo(r, pf).clr < fr) blocked = true;
            }
            float rr = abs(length(s) - fr);
            float dash = blocked ? 1.0 : step(0.42, frac(atan2(s.y, s.x) * 9.5));
            col = lerp(col, blocked ? ALARM : DIMC,
                       (1.0 - smoothstep(spx * 0.8, spx * 2.0, rr)) * dash * 0.9);
            // the eye itself
            col = lerp(col, ACCENT, disc(uv, rc, 0.0038, asp, px));
        }
        // frame + station tally around the rosette
        col = lerp(col, INK_AXIS, ring(uv, rc, RS_ROS_R * 1.13, 0.0011, asp, px) * 0.8);
        for (uint t = 0u; t < RS_STATIONS; t++)
        {
            float a = ((float)t / (float)RS_STATIONS) * 6.2831853 - 1.5707963;
            float2 p = rc + float2(cos(a) / asp.x, sin(a)) * RS_ROS_R * 1.13;
            bool cur = ((int)t == rosSta);
            float on = (Plan[RS_STA_0 + t].active > 0.5) ? 1.0 : 0.0;
            col = lerp(col, cur ? ACCENT : lerp(INK_AXIS, CHALK, on),
                       disc(uv, p, cur ? 0.0068 : 0.0042, asp, px));
        }
    }

    // =====================================================================================
    // STRIP 3 — the core inset. The real plate, not a schematic of one.
    // =====================================================================================
    {
        float2 ic = float2((RS_INS_X0 + RS_INS_X1) * 0.5, (RS_INS_Y0 + RS_INS_Y1) * 0.5);
        float2 ih = float2((RS_INS_X1 - RS_INS_X0) * 0.5, (RS_INS_Y1 - RS_INS_Y0) * 0.5);
        float2 d = abs(uv - ic) - ih;
        if (max(d.x, d.y) < 0.0)
        {
            float2 s = float2((uv.x - ic.x) / ih.x, -(uv.y - ic.y) / ih.y);
            float3 cc = rs_corePlate(s, Plan[RS_CORE], _Time * max(core_spin, 0.0), px / ih.y);
            cc = cc / (1.0 + cc * 0.55);
            // The core's colour is real data, not chrome, so it is not made monochrome — but on
            // an instrument ground a full-strength magenta plate becomes the loudest thing in
            // the frame and outranks the readouts. Pulled back toward its own luminance and
            // exposed down, it reads as the ember it is.
            float cl = dot(cc, float3(0.2126, 0.7152, 0.0722));
            col = lerp(cl.xxx, cc, 0.55) * 0.62;
        }
        float border = 1.0 - smoothstep(0.0015, 0.0015 + px, abs(max(d.x, d.y)));
        bool coreSel = (sel > 0.5) && ((uint)(sel - 1.0) == RS_CORE);
        col = lerp(col, coreSel ? ACCENT : CHALK, border * (coreSel ? 1.0 : 0.45));
    }

    // =====================================================================================
    // Legend and tallies.
    // =====================================================================================
    {
        // fixture kind legend
        for (uint kk = 0u; kk < (uint)FK_KINDS; kk++)
        {
            float2 p = float2(0.430 + (float)kk * 0.0295, 0.610);
            col = lerp(col, fixColour((int)kk), disc(uv, p, 0.0072, asp, px));
        }
        // live fixtures
        for (uint t1 = 0u; t1 < RS_FIXES; t1++)
        {
            float2 p = float2(0.430 + fmod((float)t1, 18.0) * 0.0165,
                              0.680 + floor((float)t1 / 18.0) * 0.026);
            col = lerp(col, (t1 < liveF) ? CHALK : INK_AXIS, disc(uv, p, 0.0044, asp, px));
        }
        // live lights
        for (uint t2 = 0u; t2 < RS_LIGHTS; t2++)
        {
            float2 p = float2(0.430 + fmod((float)t2, 18.0) * 0.0165,
                              0.760 + floor((float)t2 / 18.0) * 0.026);
            col = lerp(col, (t2 < liveL) ? MIDC : INK_AXIS, disc(uv, p, 0.0044, asp, px));
        }
        // clearance violations — the one tally that means the shaft is broken
        for (uint t3 = 0u; t3 < 12u; t3++)
        {
            float2 p = float2(0.430 + (float)t3 * 0.0165, 0.845);
            col = lerp(col, (t3 < viol) ? ALARM : INK_AXIS, disc(uv, p, 0.0050, asp, px));
        }
        if (viol > 0u)
        {
            // a hard rule under the alarm row so a blocked shaft cannot be missed
            float r2 = band(uv.y, 0.868, 0.8715, px) * step(0.428, uv.x) * step(uv.x, 0.632);
            col = lerp(col, ALARM, r2);
        }
        // section style readout
        for (uint t4 = 0u; t4 < 4u; t4++)
        {
            float2 p = float2(0.430 + (float)t4 * 0.0165, 0.912);
            col = lerp(col, (t4 == style) ? ACCENT : INK_AXIS, disc(uv, p, 0.0050, asp, px));
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
