// KA_Robot / scope_marks.hlsli — what the Scope's marks mean and where they land, shared by the
// drawing (scope.hlsl) and the type (scope_layout.hlsl), so a number laid beside a mark takes that
// mark's colour and sits on the same projection.
#ifndef KA_SCOPE_MARKS_HLSLI
#define KA_SCOPE_MARKS_HLSLI

// ---------------------------------------------------------------------------
// Mark colour
// ---------------------------------------------------------------------------
// Hue is assigned by WHAT A MARK MEANS, never by which line happened to need drawing next, so a
// palette swap re-skins the instrument without shuffling what anything stands for:
//
//   FUTURE   the predicted arc — where the ball is going to be
//   NOW      the velocity vector — how fast it is going right now
//   SUBJECT  the ball itself, and its plumb line
//   DECIDE   the contact and the elected striker. Keeps the accent in every palette, because it
//            is the single thing the whole diagram exists to show being decided.
//
// Every mark passes through scMark(), which blends from the project's grey-and-amber instrument
// theme toward that hue. At Mark Colour 0 the blend does nothing and the scope is the monochrome
// instrument the rest of the project is drawn in; the dial is the whole range in between.
struct ScopePal { float3 future, now, subject, decide, arm, alarm; };

ScopePal scopePalette()
{
    ScopePal p;
    p.alarm = PT_ALARM;
    int k = (int)scope_palette;
    if (k == 0)          // Pure — solid RGB primaries, for reading marks off a bright render
    {
        p.future  = float3(0.10, 1.00, 0.20);
        p.now     = float3(0.15, 0.45, 1.00);
        p.subject = float3(1.00, 1.00, 1.00);
        p.decide  = float3(1.00, 0.10, 0.10);
        p.arm     = float3(0.00, 0.90, 1.00);
        // DECIDE takes red here, which is alarm's colour everywhere else in the project, so
        // alarm moves to magenta rather than letting the two states become indistinguishable.
        // The rule that matters is that they differ, not which hue each one holds.
        p.alarm   = float3(1.00, 0.10, 0.85);
    }
    else if (k == 2)     // Chalk — soft pastels, for bright grounds where saturated ink glares
    {
        p.future  = float3(0.62, 0.93, 0.68);
        p.now     = float3(0.99, 0.86, 0.55);
        p.subject = float3(0.95, 0.93, 0.90);
        p.decide  = float3(1.00, 0.72, 0.42);
        p.arm     = float3(0.72, 0.84, 0.95);
    }
    else if (k == 3)     // Blueprint — cool and technical, hue carried by the cyans
    {
        p.future  = float3(0.35, 0.95, 0.80);
        p.now     = float3(0.55, 0.80, 1.00);
        p.subject = float3(0.86, 0.94, 1.00);
        p.decide  = float3(1.00, 0.78, 0.30);
        p.arm     = float3(0.40, 0.62, 0.88);
    }
    else                 // Signal — saturated and separable, the loudest of the three
    {
        p.future  = float3(0.16, 0.96, 0.42);
        p.now     = float3(0.30, 0.72, 1.00);
        p.subject = float3(1.00, 0.97, 0.92);
        p.decide  = float3(1.00, 0.58, 0.10);
        p.arm     = float3(0.52, 0.72, 1.00);
    }
    return p;
}

float3 scMark(float3 theme, float3 hue) { return lerp(theme, hue, saturate(scope_hue)); }

// World point -> output pixel, through the module's own injected internal camera.
bool projectPt(float3 w, float2 res, out float2 sp, out float vz)
{
    sp = float2(-1e6, -1e6); vz = 1e9;
    float4 c = mul(_ViewProjMatrix, float4(w, 1.0));
    if (c.w <= 1e-4) return false;
    float3 n = c.xyz / c.w;
    sp = float2((n.x * 0.5 + 0.5) * res.x, (1.0 - (n.y * 0.5 + 0.5)) * res.y);
    vz = length(w - _CameraPos);
    return true;
}

#endif
