// handles.hlsli - Handles' contract, shared by the program render and the editor overlay, so the
// ring that is drawn, the test that lights it and the host's grab radius come from one place.
//
// FOUR HANDLES, EIGHT ORDINARY PARAMETERS. Each object is a vec2 position parameter plus a float
// rotation parameter, bound in the manifest's viewport.param_gestures. The host owns the drag:
// left-drag within the radius moves the position, right-drag turns the rotation, and the edit
// commits on release as ONE undo entry. No event code in this module - the parameters stay
// ordinary: Properties shows them, presets store them, expressions can drive them.
//
// 0.6.3 SHOWS NOTHING UNTIL RELEASE. The docs promise a live preview, but the engine writes the
// parameter only on release, and while it holds the drag the module gets no input (no events, no
// buttons, the pointer frozen at the press), so no module code can draw the drag either. Engine
// bug sentinel-bugs #173, written up in PLAN.md; this station is its test case and goes live
// unchanged once the engine previews param gestures.
#ifndef HANDLES_HLSLI
#define HANDLES_HLSLI

#define H_COUNT  4u
#define H_LAMP   0u
#define H_BLADE  1u
#define H_PRISM  2u
#define H_ARC    3u
#define H_RADIUS 0.05     // = manifest param_gestures radius (all four handles)

// WHAT THE HOST DOES (measured on 0.6.3 with real drags and parameter readback):
//   - a vec2 position parameter is the image position, top-down, x and y in 0..1;
//   - the grab test is a CIRCLE IN NORMALIZED COORDINATES, length(pointer - position) <= radius,
//     so on a 16:9 frame the grabbable area is an ellipse 16/9 times wider than it is tall
//     (64 x 36 px at 1280x720 - engine bug sentinel-bugs #174);
//   - left-drag puts the handle under the pointer (an off-centre grab jumps it there) and follows;
//   - right-drag turns the rotation parameter by horizontal motion (rightward = clockwise, about
//     a quarter degree per image pixel) and leaves the position alone;
//   - the edit commits on release as one undo entry - and on 0.6.3 nothing changes before that.
//
// THE ONE CONVERSION between a handle parameter and the image (the Style Authority rule, applied
// to param gestures): every drawing and every hover test goes through these.
float2 hdUv(float2 param) { return param; }
float2 hdParam(float2 uv) { return uv; }
float  hdHitDist(float2 pointerUv, float2 param) { return length(pointerUv - hdUv(param)); }
// The ring is round: the radius in image heights, the round part of the grab area, so everything
// inside it grabs. Until #174 is fixed the host also grabs a strip past the ring's left and right
// (to 64 px at 1280x720), and hdHitDist follows the host, so the ring lights there too. Once the
// radius is measured in image heights, hdHitDist becomes length((pointerUv - hdUv(param)) *
// float2(aspect, 1)) and the ring is exactly the grab area.
float  hdRingRadiusPx(float2 res) { return H_RADIUS * res.y; }

// Stage space: aspect-corrected, y down, one unit = the image height.
float2 hdStage(float2 uv, float aspect) { return float2(uv.x * aspect, uv.y); }

// Degrees, 0 = +x, increasing clockwise on screen (y is down).
float2 hdDir(float deg) { float a = deg * (IL_PI / 180.0); return float2(cos(a), sin(a)); }
// Into an object's frame (its +x axis along its rotation).
float2 hdLocal(float2 p, float2 c, float deg) { float2 d = hdDir(deg); float2 v = p - c; return float2(dot(v, d), dot(v, float2(-d.y, d.x))); }

struct HdScene
{
    float2 pos[H_COUNT];     // stage space
    float  rot[H_COUNT];     // degrees
    float  aspect;
};

HdScene hdScene(float2 res)
{
    HdScene S;
    S.aspect = res.x / res.y;
    S.pos[H_LAMP]  = hdStage(hdUv(lamp_pos),  S.aspect); S.rot[H_LAMP]  = lamp_rot;
    S.pos[H_BLADE] = hdStage(hdUv(blade_pos), S.aspect); S.rot[H_BLADE] = blade_rot;
    S.pos[H_PRISM] = hdStage(hdUv(prism_pos), S.aspect); S.rot[H_PRISM] = prism_rot;
    S.pos[H_ARC]   = hdStage(hdUv(arc_pos),   S.aspect); S.rot[H_ARC]   = arc_rot;
    return S;
}

// ---------------------------------------------------------------- the occluders (stage units)
// Blade: a long thin slab.
float sdBlade(float2 p)
{
    float2 d = abs(p) - float2(0.150, 0.016);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.004;
}
// Prism: an equilateral triangle, one vertex on its +x axis.
float sdPrism(float2 p)
{
    const float k = 1.7320508;
    const float r = 0.075;                       // inradius
    p = float2(p.y, p.x);                        // apex toward +x (iq's apex is on +y)
    p.x = abs(p.x) - r * k;
    p.y = p.y + r;
    if (p.x + k * p.y > 0.0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r * k, 0.0);
    return -length(p) * sign(p.y) - 0.003;
}
// Arc: a thick ring with its gap facing +x.
float sdArc(float2 p)
{
    const float R = 0.072, T = 0.017;
    const float2 sc = float2(sin(2.45), cos(2.45));   // half-aperture of the solid part
    p.x = -p.x;
    p.y = abs(p.y);
    float2 q = float2(p.y, p.x);
    float d = (sc.y * q.x > sc.x * q.y) ? length(q - sc * R) : abs(length(q) - R);
    return d - T;
}

// The occluder field; `id` is the nearest object.
float hdField(float2 q, HdScene S, out uint id)
{
    float b = sdBlade(hdLocal(q, S.pos[H_BLADE], S.rot[H_BLADE]));
    float p = sdPrism(hdLocal(q, S.pos[H_PRISM], S.rot[H_PRISM]));
    float a = sdArc(hdLocal(q, S.pos[H_ARC], S.rot[H_ARC]));
    id = H_BLADE;
    float d = b;
    if (p < d) { d = p; id = H_PRISM; }
    if (a < d) { d = a; id = H_ARC; }
    return d;
}
float hdField(float2 q, HdScene S) { uint id; return hdField(q, S, id); }

#endif
