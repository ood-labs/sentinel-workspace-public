#include "../_shared/sdf/sdf_ops.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct Part { float4 transform_a; float4 transform_b; float4 rotation; float4 meta; };
struct MarbleProfile { float4 stone_color_roughness; float4 vein_color_scale; float4 vein_contrast_pore_scale; float4 cavity_subsurface_micro_normal; };
struct LightRecord { float4 position_radius; float4 color_intensity; float4 direction_type; };
struct GlitchField { float4 global_distortion; float4 slice_pattern; float4 fracture_pattern; float4 temporal_motion; };

float3 rotateZ(float3 p, float a) {
    float c=cos(a); float s=sin(a);
    return float3(c*p.x-s*p.y, s*p.x+c*p.y, p.z);
}
float hash31(float3 p) {
    return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);
}
float valueNoise(float3 p) {
    float3 i=floor(p), f=frac(p); f=f*f*(3.0-2.0*f);
    float n000=hash31(i+float3(0,0,0)); float n100=hash31(i+float3(1,0,0));
    float n010=hash31(i+float3(0,1,0)); float n110=hash31(i+float3(1,1,0));
    float n001=hash31(i+float3(0,0,1)); float n101=hash31(i+float3(1,0,1));
    float n011=hash31(i+float3(0,1,1)); float n111=hash31(i+float3(1,1,1));
    float x0=lerp(n000,n100,f.x), x1=lerp(n010,n110,f.x);
    float x2=lerp(n001,n101,f.x), x3=lerp(n011,n111,f.x);
    return lerp(lerp(x0,x1,f.y),lerp(x2,x3,f.y),f.z);
}
float detailNoise(float3 p) {
    float total=0.0, amp=0.55;
    [unroll] for(int i=0;i<5;i++) { total+=valueNoise(p)*amp; p=p*2.03+float3(11.7,3.1,7.9); amp*=0.5; }
    return saturate(total);
}
float sdEllipsoid(float3 p, float3 r) { return (length(p / max(r,float3(0.02,0.02,0.02))) - 1.0) * min(r.x,min(r.y,r.z)); }
float sdBar(float3 p, float3 r) {
    float3 q=abs(p)-r;
    return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0);
}
float sdRoundBox(float3 p, float3 b, float radius) {
    float3 q=abs(p)-b+radius;
    return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0)-radius;
}
float sharpBlock(float3 p, float3 b, float bevel) {
    float3 q=abs(p)-b+bevel;
    return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0)-bevel;
}
float sdOcta(float3 p,float s) { return (abs(p.x)+abs(p.y)+abs(p.z)-s)*0.57735027; }
float3 glitchDomain(float3 p, GlitchField g) {
    float time=g.temporal_motion.x;
    float warp=g.global_distortion.x;
    float twist=g.global_distortion.y;
    float fold=g.global_distortion.z;
    float quant=g.global_distortion.w;
    float slices=max(g.slice_pattern.y,2.0);
    float sliceIndex=floor((p.y+2.0)*slices*0.22);
    float sliceHash=hash31(float3(sliceIndex,g.slice_pattern.w,4.7));
    float active=step(0.48,sliceHash);
    float sliceWave=sin(p.z*7.0+time*1.7+sliceHash*8.0);
    p.x += active*(sliceHash-0.5)*g.slice_pattern.x;
    p.x += sliceWave*warp*0.10;
    p.z += cos(p.x*8.0-time*1.1)*warp*0.055;
    float angle=twist*(p.y*0.28+sin(time*0.61+g.slice_pattern.w)*0.045);
    p=rotateZ(p,angle);
    p=abs(p)-fold*0.035;
    p=sign(p)*max(abs(p)-fold*0.018,0.0);
    float grid=4.0+g.fracture_pattern.x*12.0;
    float3 snapped=round(p*grid)/grid;
    p=lerp(p,snapped,quant*0.24);
    float fracture=sin(p.x*grid*1.7+time)*sin(p.z*grid*1.3-time*0.7);
    p.y += fracture*g.fracture_pattern.y*0.018*warp;
    return p;
}
float partSdf(float3 p, Part q) {
    float3 local=rotateZ(p-q.transform_a.xyz,-q.rotation.z);
    float3 r=q.transform_b.xyz;
    int kind=(int)q.transform_a.w;
    if(kind==7 || kind==4) return sharpBlock(local,r,edge_break);
    if(kind==5 || kind==6) return sdBar(local,r);
    if(kind==3) {
        if(q.meta.y >= 8.0 && q.meta.y < 9.0) return sdOcta(local,max(r.y,max(r.x,r.z)));
        if(q.meta.y >= 9.0 && q.meta.y < 10.0) return sharpBlock(local,r,min(edge_break,0.012));
        return sdBar(local,r);
    }
    return sdEllipsoid(local,r);
}
float sceneSdf(float3 p, out float matId) {
    GlitchField glitch=_Data3[0];
    p=glitchDomain(p,glitch);
    float d=100.0; matId=0.0;
    [loop]
    for(uint i=0;i<64;i++) {
        if(i >= (uint)_Data0_Count) break;
        Part q=_Data0[i]; if(q.meta.w < 0.5) continue;
        float pd=partSdf(p,q); int kind=(int)q.transform_a.w;
        if(kind==3) d=max(d,-pd);
        else if(pd<d) { d=pd; matId=q.rotation.w; }
    }
    float nearSurface=saturate(1.0-abs(d)/0.24);
    d += max(0.0,detailNoise(p*noise_scale)-0.60) * surface_carve * nearSurface;
    return d;
}
float3 marbleAlbedo(float3 p, MarbleProfile m, float cavity) {
    float broad=sin(p.x*m.vein_color_scale.w + sin(p.z*2.2)*2.3 + p.y*1.4);
    float fine=sin(p.z*m.vein_color_scale.w*2.6 - p.x*4.0 + sin(p.y*5.0));
    float vein=pow(saturate(1.0-abs(broad*0.72+fine*0.28)),max(0.4,m.vein_contrast_pore_scale.x));
    float pore=sin(p.x*42.0+sin(p.z*23.0))*sin(p.y*51.0);
    float3 stone=m.stone_color_roughness.rgb*(1.0+pore*m.vein_contrast_pore_scale.y*0.025);
    float3 albedo=lerp(stone,m.vein_color_scale.rgb,vein*vein_visibility*micro_normal*0.95);
    return lerp(albedo,float3(0.006,0.007,0.009),cavity*0.55);
}
float softShadow(float3 ro,float3 rd) {
    float res=1.0; float t=0.04;
    [loop]
    for(int i=0;i<20;i++) {
        float mat; float h=sceneSdf(ro+rd*t,mat);
        res=min(res,12.0*h/max(t,0.001)); t+=clamp(h,0.02,0.22);
        if(h<surface_eps || t>3.5) break;
    }
    return saturate(res);
}

[numthreads(8,8,1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel=DTid.xy; if(pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv=((float2)pixel+0.5)/_Resolution.xy;
    float2 ndc=float2(uv.x*2.0-1.0,1.0-uv.y*2.0);
    float4 nearW=mul(_InvViewProjMatrix,float4(ndc,0.0,1.0));
    float4 farW=mul(_InvViewProjMatrix,float4(ndc,1.0,1.0));
    nearW/=nearW.w; farW/=farW.w;
    float3 ro=_CameraPos;
    float3 rd=normalize(farW.xyz-nearW.xyz);
    float3 bg=lerp(float3(0.012,0.014,0.018),float3(0.035,0.030,0.024),uv.y);
    float t=0.0; float mat=0.0; float h=1.0;
    [loop]
    for(int i=0;i<160;i++) {
        if(i>=ray_steps) break;
        h=sceneSdf(ro+rd*t,mat); t+=h*0.78;
        if(abs(h)<surface_eps || t>max_distance) break;
    }
    float3 col=bg;
    if(t<max_distance && abs(h)<surface_eps*3.0) {
        float3 pos=ro+rd*t;
        float matNow; float3 n;
        float e=0.002;
        n=normalize(float3(sceneSdf(pos+float3(e,0,0),matNow)-sceneSdf(pos-float3(e,0,0),matNow),sceneSdf(pos+float3(0,e,0),matNow)-sceneSdf(pos-float3(0,e,0),matNow),sceneSdf(pos+float3(0,0,e),matNow)-sceneSdf(pos-float3(0,0,e),matNow)));
        MarbleProfile marble=_Data1[0];
        float cavity=saturate(1.0-abs(dot(n,-rd)));
        float3 albedo=marbleAlbedo(pos,marble,cavity);
        float3 lit=albedo*0.075;
        [loop]
        for(uint li=0;li<16;li++) {
            if(li >= (uint)_Data2_Count) break;
            LightRecord l=_Data2[li];
            float3 toL=l.position_radius.xyz-pos; float dist=length(toL); float3 L=toL/max(dist,0.001);
            float atten=saturate(1.0-dist/max(l.position_radius.w,0.05)); atten*=atten;
            float diff=saturate(dot(n,L));
            float sha=softShadow(pos+n*surface_eps*2.0,L);
            float3 lc=l.color_intensity.rgb*l.color_intensity.w;
            lit += albedo*lc*diff*atten*lerp(0.42,1.0,sha);
            float specPower=lerp(22.0,128.0,chrome_amount*(1.0-marble.stone_color_roughness.w));
            lit += lc*pow(saturate(dot(reflect(-L,n),-rd)),specPower)*atten*(0.32+chrome_amount*0.9);
        }
        float fresnel=pow(1.0-saturate(dot(n,-rd)),4.0);
        float3 darkEnv=lerp(float3(0.012,0.018,0.028),float3(0.20,0.25,0.34),saturate(n.y*0.5+0.25));
        lit += darkEnv*fresnel*(0.20+chrome_amount*0.65);
        lit += albedo*marble.cavity_subsurface_micro_normal.y*pow(1.0-saturate(dot(n,-rd)),2.0)*0.28;
        col=lit*exposure;
        float fog=saturate((t-3.0)/max_distance)*0.32;
        col=lerp(col,bg,fog);
    }
    col=1.0-exp(-max(col,0.0));
    col=pow(saturate(col),0.88);
    OutputUAV[pixel]=float4(col,1.0);
}
