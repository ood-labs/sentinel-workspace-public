// Icosahedral reciprocal-space SDF raymarcher. The surface is an isosurface of
// six golden-ratio plane-wave pairs, carved by a dodecahedral radial shell.
RWTexture2D<float4> OutputUAV : register(u0);

float3 pal(float t){return 0.5+0.5*cos(6.28318*(t+float3(0.02,0.23,0.46)));}
float2 rot(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}

float quasiWave(float3 p)
{
    const float ph=1.61803398875;
    float3 v0=normalize(float3(0,1,ph)); float3 v1=normalize(float3(0,1,-ph));
    float3 v2=normalize(float3(1,ph,0)); float3 v3=normalize(float3(1,-ph,0));
    float3 v4=normalize(float3(ph,0,1)); float3 v5=normalize(float3(-ph,0,1));
    float t=phase*6.2831853;
    return (cos(dot(p,v0)*wave_frequency+t)+cos(dot(p,v1)*wave_frequency-t*2.0)+
            cos(dot(p,v2)*wave_frequency+t*3.0)+cos(dot(p,v3)*wave_frequency-t*4.0)+
            cos(dot(p,v4)*wave_frequency+t*5.0)+cos(dot(p,v5)*wave_frequency-t*6.0))/6.0;
}

float mapScene(float3 p, out float material)
{
    // Phason motion lives in the plane-wave offsets below. Keep object-space
    // orientation stable so the topology visibly transforms instead of spins.
    p.xz=rot(p.xz,0.22);
    p.xy=rot(p.xy,0.35);
    float w=quasiWave(p);
    float shell=abs(length(p)-shell_radius)-shell_thickness;
    float iso=abs(w-iso_level)/max(wave_frequency*0.45,0.5)-surface_thickness;
    float cage=max(iso,shell);
    float core=length(p)-core_radius;
    float tunnel=-(length(p.xz)-tunnel_radius);
    float d=min(cage,max(core,tunnel));
    material=(core<max(cage,tunnel))?1.0:saturate(w*0.5+0.5);
    return d;
}

float3 normalAt(float3 p)
{
    float e=0.004; float m;
    return normalize(float3(mapScene(p+float3(e,0,0),m)-mapScene(p-float3(e,0,0),m),
                            mapScene(p+float3(0,e,0),m)-mapScene(p-float3(0,e,0),m),
                            mapScene(p+float3(0,0,e),m)-mapScene(p-float3(0,0,e),m)));
}

[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+0.5)/_Resolution;
    float2 ndc=float2(uv.x*2.0-1.0,1.0-uv.y*2.0);
    ndc.x*=_Resolution.x/_Resolution.y;
    // A restrained periodic sway retains parallax without a full camera orbit.
    float orbit=0.62+0.16*sin(phase*6.2831853);
    float3 ro=float3(sin(orbit)*camera_distance,0.55+sin(orbit*0.7)*0.3,cos(orbit)*camera_distance);
    float3 target=float3(0,0,0),fw=normalize(target-ro),rt=normalize(cross(float3(0,1,0),fw)),up=cross(fw,rt);
    float3 rd=normalize(fw+ndc.x*rt+ndc.y*up);
    float travel=0.0,mat=0.0,d=0.0;int hit=0;
    [loop]for(int i=0;i<max_steps;i++){float3 p=ro+rd*travel;d=mapScene(p,mat);if(d<0.0015){hit=1;break;}travel+=max(d*0.72,0.002);if(travel>9.0)break;}
    float3 bg=lerp(float3(0.001,0.003,0.012),float3(0.018,0.004,0.035),uv.y);
    float stars=pow(frac(sin(dot(floor(uv*_Resolution/3.0),float2(12.9898,78.233)))*43758.5453),70.0);
    float3 col=bg+stars*0.28;
    if(hit!=0){float3 p=ro+rd*travel,n=normalAt(p);float3 l=normalize(float3(-0.4,0.8,-0.3));float diff=max(dot(n,l),0.0);float fres=pow(1.0-max(dot(n,-rd),0.0),3.0);float q=quasiWave(p);float3 base=pal(hue+q*0.24+mat*0.13);col=base*(0.08+diff*1.25)+pal(hue+0.45)*fres*fresnel_gain;col+=exp(-abs(d)*90.0)*emission*base;}
    // Project a bounded subset of the cut-project records as orbiting nuclei.
    uint cnt=min((uint)_Data0_Count,64u);
    [loop]for(uint j=0u;j<64u;j++){if(j>=cnt)break;if(_Data0[j].active<0.5)continue;float3 wp=_Data0[j].position*data_cloud_scale;float3 rel=wp-ro;float z=dot(rel,fw);if(z<0.1)continue;float2 sp=float2(dot(rel,rt),dot(rel,up))/z;float dd=length(ndc-sp);float glow=pow(max(0.0,1.0-dd/(0.018*_Data0[j].scale)),2.0);col+=pal(_Data0[j].hue)*glow*data_glow;}
    col=1.0-exp(-col*exposure);
    OutputUAV[px]=float4(pow(saturate(col),1.0/2.2),1.0);
}
