RWTexture2D<float4> OutputUAV : register(u0);

float4 px(int2 p){p=clamp(p,int2(0,0),int2(_Resolution.xy)-1);return _Tex0.Load(int3(p,0));}

void lockedView(int view,out float az,out float elv,out float dist,out float focal,out float3 target)
{
    if(view==0){az=-2.211;elv=.20;dist=4.75;focal=.56;target=float3(.15,1.05,.72);return;}
    if(view==1){az=-1.25;elv=.13;dist=3.75;focal=.74;target=float3(-.25,.96,.62);return;}
    if(view==2){az=.82;elv=.15;dist=4.65;focal=.72;target=float3(.15,1.02,.12);return;}
    az=2.92;elv=.15;dist=3.35;focal=.72;target=float3(-.15,1.02,1.05);
}

float3 cameraRay(float2 uv,out float3 ro)
{
    float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);
    if(cam_mode==0){float4 a=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)),b=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1));a/=a.w;b/=b.w;ro=_CameraPos;return normalize(b.xyz-a.xyz);}
    float az,elv,dist,focal;float3 target;
    if(cam_mode==2)lockedView(evaluation_view,az,elv,dist,focal,target);else{az=orbit_azimuth+orbit_phase*6.2831853;elv=orbit_elevation;dist=orbit_distance;focal=orbit_focal;target=float3(orbit_target_x,orbit_target_y,orbit_target_z);}
    ro=target+dist*float3(cos(elv)*sin(az),sin(elv),cos(elv)*cos(az));float3 f=normalize(target-ro),rr=normalize(cross(float3(0,1,0),f)),u=cross(f,rr);return normalize(f+ndc.x*rr*focal+ndc.y*u*focal);
}

float3 worldAt(int2 p,float z,out float3 ray)
{
    float2 uv=(float2(p)+.5)/_Resolution.xy;float3 ro;ray=cameraRay(uv,ro);return ro+ray*z;
}

float occTap(float z,int2 p,float radius)
{
    float q=px(p).a,d=z-q;
    return (q<999)?saturate((d-.025)/max(radius*.018,.03))*saturate(1-d*.20):0;
}

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;
    int2 p=int2(id.xy);float4 src=px(p);if(src.a>=999){OutputUAV[p]=float4(src.rgb,src.a);return;}

    float3 ray,wp=worldAt(p,src.a,ray),dummy;
    float zl=px(p+int2(-1,0)).a,zr=px(p+int2(1,0)).a,zu=px(p+int2(0,-1)).a,zd=px(p+int2(0,1)).a;
    float3 pl=worldAt(p+int2(-1,0),min(zl,src.a+.5),dummy),pr=worldAt(p+int2(1,0),min(zr,src.a+.5),dummy);
    float3 pu=worldAt(p+int2(0,-1),min(zu,src.a+.5),dummy),pd=worldAt(p+int2(0,1),min(zd,src.a+.5),dummy);
    float3 n=normalize(cross(pr-pl,pd-pu));if(dot(n,-ray)<0)n=-n;

    float occ=0;
    occ+=occTap(src.a,p+int2(-3,0),3)+occTap(src.a,p+int2(3,0),3)+occTap(src.a,p+int2(0,-3),3)+occTap(src.a,p+int2(0,3),3);
    occ+=occTap(src.a,p+int2(-7,-5),7)+occTap(src.a,p+int2(7,-5),7)+occTap(src.a,p+int2(-7,5),7)+occTap(src.a,p+int2(7,5),7);
    occ+=occTap(src.a,p+int2(-14,0),14)+occTap(src.a,p+int2(14,0),14)+occTap(src.a,p+int2(0,-14),14)+occTap(src.a,p+int2(0,14),14);
    occ=saturate(occ/12)*saturate(ao_strength*.34);

    float3 gi=0;float wsum=0;
    int2 o0=int2(10,0),o1=int2(-10,0),o2=int2(0,10),o3=int2(0,-10),o4=int2(7,7),o5=int2(-7,7),o6=int2(7,-7),o7=int2(-7,-7);
    float4 s0=px(p+o0),s1=px(p+o1),s2=px(p+o2),s3=px(p+o3),s4=px(p+o4),s5=px(p+o5),s6=px(p+o6),s7=px(p+o7);
    float w0=exp(-abs(s0.a-src.a)*1.4),w1=exp(-abs(s1.a-src.a)*1.4),w2=exp(-abs(s2.a-src.a)*1.4),w3=exp(-abs(s3.a-src.a)*1.4),w4=exp(-abs(s4.a-src.a)*1.4),w5=exp(-abs(s5.a-src.a)*1.4),w6=exp(-abs(s6.a-src.a)*1.4),w7=exp(-abs(s7.a-src.a)*1.4);
    gi=s0.rgb*w0+s1.rgb*w1+s2.rgb*w2+s3.rgb*w3+s4.rgb*w4+s5.rgb*w5+s6.rgb*w6+s7.rgb*w7;wsum=w0+w1+w2+w3+w4+w5+w6+w7;gi/=max(wsum,.001);

    float3 key=normalize(float3(-.45,.78,.30));float keyTerm=saturate(dot(n,key));float hemi=saturate(n.y*.5+.5);
    float3 color=src.rgb*(.91+.07*keyTerm+.045*hemi)*(1-occ*.30);
    color+=gi*.075*(.35+.65*hemi);
    color+=float3(.032,.016,.006)*exp(-max(wp.y,0)*.45);
    OutputUAV[p]=float4(max(color,0),src.a);
}
