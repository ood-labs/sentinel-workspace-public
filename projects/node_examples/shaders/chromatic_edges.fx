Texture2D <float4> InputBuffer : INPUTBUFFER;

float ChromaticEdges;

sampler LinearClampSampler
{
    Filter = Min_Mag_Linear_Mip_Point;
    AddressU = Clamp;
    AddressV = Clamp;
    AddressW = Clamp;
};

struct VS_OUTPUT
{
    float4 Position : SV_POSITION;
    float2 Uv : TEXCOORD0;
};

VS_OUTPUT VS_Fullscreen(float4 Position : POSITION)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;
    Out.Position = float4(Position.xy, 0, 1);
    Out.Uv = Position.xy * 0.5f + 0.5f;
    return Out;
}

float luminance(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

float4 PS_ChromaticEdges(VS_OUTPUT In) : SV_TARGET0
{
    float2 uv = In.Uv;
    uint width, height;
    InputBuffer.GetDimensions(width, height);
    float2 texel = 1.0 / float2(width, height);

    float4 source = InputBuffer.SampleLevel(LinearClampSampler, uv, 0);
    float amount = saturate((ChromaticEdges + 5.0) / 15.0);
    float2 offset = texel * lerp(0.0, 13.0, amount);

    float red = InputBuffer.SampleLevel(LinearClampSampler, uv + float2(offset.x, 0), 0).r;
    float green = source.g;
    float blue = InputBuffer.SampleLevel(LinearClampSampler, uv - float2(offset.x, 0), 0).b;
    float3 split = float3(red, green, blue);

    float left = luminance(InputBuffer.SampleLevel(LinearClampSampler, uv - texel, 0).rgb);
    float right = luminance(InputBuffer.SampleLevel(LinearClampSampler, uv + texel, 0).rgb);
    float edge = saturate(abs(right - left) * 8.0);
    float3 glow = float3(0.1, 0.8, 1.0) * edge * amount;
    float3 effect = saturate(split + glow);

    float3 wet = lerp(source.rgb, effect, amount);
    return float4(wet, source.a);
}

BlendState NoBlend
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = FALSE;
    BlendEnable[1] = FALSE;
    BlendEnable[2] = FALSE;
    BlendEnable[3] = FALSE;
};

DepthStencilState NoDepthState
{
    DepthEnable = FALSE;
    DepthWriteMask = All;
    DepthFunc = Less;
    StencilEnable = FALSE;
};

RasterizerState DefaultRasterState
{
    CullMode = None;
    FillMode = Solid;
    DepthBias = 0;
    ScissorEnable = false;
};

technique11 ApplyPostProcess
{
    pass p0
    {
        SetVertexShader(CompileShader(vs_4_0, VS_Fullscreen()));
        SetPixelShader(CompileShader(ps_4_0, PS_ChromaticEdges()));
        SetBlendState(NoBlend, float4(0.0f, 0.0f, 0.0f, 0.0f), 0xFFFFFFFF);
        SetDepthStencilState(NoDepthState, 0);
        SetRasterizerState(DefaultRasterState);
    }
}
