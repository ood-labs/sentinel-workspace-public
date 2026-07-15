#ifndef SPLINE_EDITOR_TYPES_HLSLI
#define SPLINE_EDITOR_TYPES_HLSLI

struct SplineKnot {
    float2 anchor;
    float2 handle_in;
    float2 handle_out;
    uint knot_id;
    uint spline_id;
    uint tangent_mode;
    uint flags;
    float active;
    float marker;
};

struct EditorState {
    float tool;
    float command;
    float phase;
    float target;
    float2 pointer;
    float2 drag_start;
    float target_kind;
    float active_spline;
    float tangent_mode;
    float modifiers;
    float2 marquee_start;
    float2 marquee_end;
    float toolbar_latch;
    float3 toolbar_pad;
};

bool knotSelected(SplineKnot knot) { return (knot.flags & 1u) != 0u; }
float pointSegmentDistance(float2 p, float2 a, float2 b) {
    float2 ba = b-a;
    float h = saturate(dot(p-a,ba)/max(dot(ba,ba),1e-7));
    return length(p-(a+ba*h));
}

float2 cubicPoint(float2 a, float2 b, float2 c, float2 d, float t) {
    float s=1.0-t;
    return s*s*s*a + 3.0*s*s*t*b + 3.0*s*t*t*c + t*t*t*d;
}

float2 cubicTangent(float2 a, float2 b, float2 c, float2 d, float t) {
    float s=1.0-t;
    return 3.0*s*s*(b-a)+6.0*s*t*(c-b)+3.0*t*t*(d-c);
}

#endif
