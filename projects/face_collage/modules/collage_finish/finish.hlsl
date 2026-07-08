// collage_finish — reference finish: a periwinkle/purple grid background with the collage inset
// on top (grid shows as a border), plus RGB-split glitch, grain, and vignette. input:0 = collage.
// ps_5_0 fullscreen; injected VS_OUTPUT{Position,Uv}, _Time, _Resolution.

float h21(float2 p){ return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

float3 gridBG(float2 uv)
{
    float3 top = float3(bg_top_r, bg_top_g, bg_top_b);
    float3 bot = float3(bg_bot_r, bg_bot_g, bg_bot_b);
    float3 col = lerp(top, bot, smoothstep(0.0, 1.0, uv.y));
    // grid lines
    float2 g = frac(uv * grid_cells);
    float2 lw = fwidth(uv * grid_cells) * grid_width;
    float gline = max(1.0 - smoothstep(0.0, lw.x, min(g.x, 1.0 - g.x)),
                      1.0 - smoothstep(0.0, lw.y, min(g.y, 1.0 - g.y)));
    col = lerp(col, float3(grid_r, grid_g, grid_b), gline * 0.5);
    // faint stars
    float2 sc = floor(uv * 40.0);
    float st = step(0.985, h21(sc));
    col += st * 0.5;
    return col;
}

float4 main(VS_OUTPUT input) : SV_TARGET0
{
    float2 uv = input.Uv;
    float3 col = gridBG(uv);

    // inset the collage over the grid
    float2 c = (uv - 0.5) / max(0.4, inset) + 0.5;
    if (c.x > 0.001 && c.x < 0.999 && c.y > 0.001 && c.y < 0.999)
    {
        // per-row glitch offset + RGB split on the collage
        float row = floor(c.y * 120.0);
        float gl = (h21(float2(row, floor(_Time * 6.0))) - 0.5);
        gl = (abs(gl) > (1.0 - glitch_amt)) ? gl * glitch_amt * 0.3 : 0.0;
        float2 gu = c + float2(gl, 0.0);
        float sp = chroma * 0.004;
        float r = _Tex0.SampleLevel(LinearSampler, saturate(gu + float2(sp, 0)), 0).r;
        float4 mid = _Tex0.SampleLevel(LinearSampler, saturate(gu), 0);
        float b = _Tex0.SampleLevel(LinearSampler, saturate(gu - float2(sp, 0)), 0).b;
        float3 cc = float3(r, mid.g, b);
        // composite the accumulated collage OVER the grid using its alpha (gaps show grid)
        col = lerp(col, cc, saturate(mid.a));
    }

    // grade
    col = (col - 0.5) * contrast + 0.5 + brightness;
    col = pow(saturate(col), 1.0 / max(0.4, gamma));

    // grain
    float grain = (h21(uv * _Resolution.xy + frac(_Time)) - 0.5) * grain_amt;
    col += grain;

    // vignette
    float v = 1.0 - vignette * smoothstep(0.4, 1.1, length((uv - 0.5) * float2(1.0, 1.4)));
    col *= v;

    return float4(saturate(col), 1.0);
}
