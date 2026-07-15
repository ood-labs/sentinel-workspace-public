// hud_leaders — dashed connector / leader lines threading between widgets, with
// small end nodes and elbow (right-angle) routing. Procedural segment SDF over a
// hand-authored table of routes. Transport: render node (alpha = luminance).

RWTexture2D<float4> OutputUAV : register(u0);

static float g_line = 0.0;
static float g_dot  = 0.0;

// distance from point p to segment a-b (all aspect-corrected)
float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

// dashed segment: coverage with dashes along the segment
void dseg(float2 p, float2 a, float2 b, float w, float dash, bool dashed)
{
    float d = sdSeg(p, a, b);
    float cov = 1.0 - smoothstep(0.0, w, d);
    if (dashed)
    {
        float2 ba = b - a; float2 pa = p - a;
        float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
        float len = length(ba);
        float phase = frac(t * len / dash);
        cov *= step(phase, 0.6);
    }
    g_line = max(g_line, cov);
}

void dot(float2 p, float2 a, float r){ g_dot = max(g_dot, 1.0 - smoothstep(0.0, r, length(p - a))); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    g_line = 0.0; g_dot = 0.0;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = _Resolution.x / _Resolution.y;
    float2 p = uv * float2(asp, 1.0);   // aspect-corrected screen space
    float w = 0.0011;
    float dash = 0.010;

    // helper to convert a UV point to aspect-space
    #define A(x,y) (float2((x)*asp,(y)))

    // panel -> warning triangle
    dseg(p, A(0.180,0.230), A(0.370,0.255), w, dash, true);
    // warning -> hero gauge
    dseg(p, A(0.460,0.255), A(0.560,0.300), w, dash, true);
    dseg(p, A(0.560,0.300), A(0.560,0.430), w, dash, true);
    // secondary dial -> hero
    dseg(p, A(0.580,0.430), A(0.640,0.450), w, dash, false);
    // orbits -> hero (elbow)
    dseg(p, A(0.520,0.220), A(0.520,0.340), w, dash, true);
    dseg(p, A(0.520,0.340), A(0.610,0.360), w, dash, true);
    // globe -> panel
    dseg(p, A(0.145,0.300), A(0.145,0.320), w, dash, false);
    // bottom bars -> right
    dseg(p, A(0.525,0.840), A(0.680,0.840), w, dash, true);
    dseg(p, A(0.680,0.840), A(0.680,0.700), w, dash, true);
    // long horizontal top rail
    dseg(p, A(0.300,0.120), A(0.610,0.120), w, dash, true);
    dseg(p, A(0.660,0.120), A(0.900,0.120), w, dash, true);
    // hero -> right tab
    dseg(p, A(0.900,0.430), A(0.945,0.450), w, dash, false);
    // diagonal accent lines (top-right)
    dseg(p, A(0.760,0.090), A(0.900,0.180), w, dash, true);

    // end nodes
    dot(p, A(0.180,0.230), 0.006);
    dot(p, A(0.560,0.430), 0.006);
    dot(p, A(0.300,0.120), 0.005);
    dot(p, A(0.900,0.120), 0.005);
    dot(p, A(0.680,0.700), 0.006);
    dot(p, A(0.145,0.300), 0.005);

    #undef A

    float3 col = line_color * g_line + core_color * g_dot;
    col *= intensity;
    float lum = max(col.r, max(col.g, col.b));
    OutputUAV[pixel] = float4(col, saturate(lum));
}
