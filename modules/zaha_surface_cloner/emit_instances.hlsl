#include "types.hlsli"
RWStructuredBuffer<SurfaceInstance> OutputBuffer : register(u0);

float hash11c(float p){return frac(sin(p*127.1)*43758.5453);}

[numthreads(64,1,1)]
void main(uint3 tid:SV_DispatchThreadID){
    uint i=tid.x; if(i>=512u)return; SurfaceInstance o=(SurfaceInstance)0;
    uint ringCount=(uint)clamp(clones_per_ring,3,12); uint slice=i/ringCount; uint lane=i-slice*ringCount;
    if(slice>=min(_Data0_Count,96u)){OutputBuffer[i]=o;return;}
    float activeSliceStep=max(1.0,96.0/max((float)vertical_rings,1.0));
    uint sourceSlice=min((uint)round((float)slice*activeSliceStep),95u);
    if(sourceSlice>=_Data0_Count||_Data0[sourceSlice].active<0.5){OutputBuffer[i]=o;return;}
    LoftSection s; s.center=float3(_Data0[sourceSlice].center[0],_Data0[sourceSlice].center[1],_Data0[sourceSlice].center[2]);
    s.radius_x=_Data0[sourceSlice].radius_x;s.radius_z=_Data0[sourceSlice].radius_z;s.rotation=_Data0[sourceSlice].rotation;s.curvature=_Data0[sourceSlice].curvature;s.u=_Data0[sourceSlice].u;
    s.floor_band=_Data0[sourceSlice].floor_band;s.skin_bias=_Data0[sourceSlice].skin_bias;s.void_bias=_Data0[sourceSlice].void_bias;s.active=_Data0[sourceSlice].active;s.tangent=float3(_Data0[sourceSlice].tangent[0],_Data0[sourceSlice].tangent[1],_Data0[sourceSlice].tangent[2]);s.seed=_Data0[sourceSlice].seed;
    float v=(float)lane/(float)ringCount; float attractU=(attractor_field.x-.5)*1.6; float attractV=(attractor_field.y-.5)*1.6;
    float wave=sin(s.u*6.2831853*helix_turns+v*6.2831853+attractU*4.0)*wave_depth;
    float angle=v*6.2831853+s.rotation+wave+attractV*s.u*2.0;
    float ca=cos(angle),sa=sin(angle),cr=cos(s.rotation),sr=sin(s.rotation);
    float2 local=float2(ca*s.radius_x,sa*s.radius_z); float2 rotated=float2(local.x*cr-local.y*sr,local.x*sr+local.y*cr);
    float3 normal=normalize(float3(ca*cr-sa*sr,0,ca*sr+sa*cr)+1e-5);
    float spacing=6.2831853*max(s.radius_x,s.radius_z)/(float)ringCount;
    float rnd=hash11c((float)i+seed*17.0);
    float pulse=0.5+0.5*sin(s.u*strata_frequency*6.2831853+v*6.2831853*2.0);
    int mode=cloner_mode; float typeId=(float)mode;
    if(mode==3)typeId=(lane%3u==0u)?0.0:((lane%3u==1u)?1.0:2.0);
    float dropout=saturate(aperture_field.x*0.72+s.void_bias*0.34-0.16);
    bool keep=rnd>dropout || lane==0u || typeId==0.0;
    float radial=surface_offset+(typeId==0.0?rib_depth:(typeId==2.0?terrace_depth:0.0));
    o.position=s.center+float3(rotated.x,0,rotated.y)+normal*radial;
    o.type_id=typeId;
    o.scale=float3(max(0.06,spacing*panel_width),max(0.05,tower_band_height*(typeId==0.0?1.25:0.82)),max(0.04,(typeId==0.0?rib_depth:(typeId==2.0?terrace_depth:panel_depth))));
    o.scale*=1.0+variation*(rnd-.5)*0.7;
    o.rotation=angle+1.5707963;
    o.normal=normal;o.material_id=(typeId==0.0?2.0:(typeId==1.0?3.0:(typeId==2.0?6.0:4.0)));
    o.uv=float2(v,s.u);o.emissive=(typeId==1.0?interior_glow*(0.25+0.75*pulse)*(0.6+0.4*rnd):0.0);o.active=keep?1.0:0.0;
    OutputBuffer[i]=o;
}
