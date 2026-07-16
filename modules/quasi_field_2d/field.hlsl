RWTexture2D<float4> OutputUAV : register(u0);

float3 palette(float t)
{
    return 0.5 + 0.5*cos(6.2831853*(t + float3(0.00,0.23,0.47)));
}

float waveFamily(float2 p, int n, float k, float ph, out float ridges)
{
    float s = 0.0;
    float prod = 1.0;
    [loop] for(int i=0;i<12;i++) {
        if(i>=n) break;
        float a = 6.2831853*(float)i/(float)n;
        float w = cos(dot(p,float2(cos(a),sin(a)))*k + 1.4*cos(ph+a*2.0));
        s += w;
        prod *= 0.72 + 0.28*w;
    }
    s /= (float)n;
    ridges = pow(saturate(1.0-abs(s-contour_level)*contour_sharpness),3.0);
    return s*0.72 + prod*0.28;
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px=DTid.xy;
    if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution;
    float asp=_Resolution.x/_Resolution.y;
    float2 p=(uv-0.5)*float2(asp,1.0)*zoom;
    // Keep the lattice orientation artist-controlled. Phase should morph the
    // reciprocal field, not spin the entire image.
    float a=rotation;
    p=float2(cos(a)*p.x-sin(a)*p.y,sin(a)*p.x+cos(a)*p.y);
    float2 phason=float2(sin(p.y*1.73+phase*6.283),cos(p.x*1.31-phase*3.883))*phason_warp;
    p+=phason;
    int symmetry = (symmetry_mode==0)?5:((symmetry_mode==1)?8:12);
    float ridges=0.0;
    float f=waveFamily(p,symmetry,frequency,phase*6.2831853,ridges);
    float cells=abs(frac((f+1.0)*cell_density)-0.5)*2.0;
    float edge=pow(1.0-saturate(cells),edge_power);
    float radial=length(p);
    float3 col=palette(hue + f*0.19 + radial*0.045);
    col*=0.12 + field_gain*pow(saturate(f*0.5+0.5),2.0);
    col+=palette(hue+0.32)*ridges*ridge_gain;
    col+=palette(hue+0.68)*edge*edge_gain;
    float vign=exp(-radial*radial*0.10);
    col*=lerp(1.0,vign,vignette);
    OutputUAV[px]=float4(col,1.0);
}
