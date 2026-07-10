RWTexture2D<float4> OutputUAV : register(u0);

static const float PI = 3.14159265359;

float2 r2(float2 p, float a) { float s = sin(a), c = cos(a); return float2(c*p.x-s*p.y, s*p.x+c*p.y); }
float sdBx(float3 p, float3 b) { float3 q=abs(p)-b; return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0); }
float sdRb(float3 p, float3 b, float r) { return sdBx(p,b-r)-r; }
float sdCy(float3 p, float h, float r) { float2 d=abs(float2(length(p.xz),p.y))-float2(r,h); return min(max(d.x,d.y),0.0)+length(max(d,0.0)); }
float sdSp(float3 p, float r) { return length(p)-r; }
float smn(float a,float b,float k){ float h=saturate(0.5+0.5*(b-a)/k); return lerp(b,a,h)-k*h*(1.0-h); }

float3 recPos(int lane,uint i){ return lane==0?float3(_Data0[i].position[0],_Data0[i].position[1],_Data0[i].position[2]):float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]); }
float recKind(int lane,uint i){ return lane==0?_Data0[i].kind_id:_Data1[i].kind_id; }
float recYaw(int lane,uint i){ return lane==0?_Data0[i].yaw:_Data1[i].yaw; }
float3 recDims(int lane,uint i){ return lane==0?float3(_Data0[i].width,_Data0[i].height,_Data0[i].depth):float3(_Data1[i].width,_Data1[i].height,_Data1[i].depth); }

float furnitureSdf(float3 p,float kind,float3 d)
{
    float w=d.x,h=d.y,z=d.z;
    if(kind<5.5) return sdBx(p-float3(0,h*.5,0),d*.5);
    if(kind<6.5){
        float v=sdRb(p-float3(0,.28,z*.04),float3(w*.46,.22,z*.43),.10);
        v=min(v,sdRb(p-float3(0,.72,-z*.38),float3(w*.46,.32,z*.10),.09));
        v=min(v,sdRb(p-float3(-w*.455,.52,0),float3(w*.07,.42,z*.46),.08));
        v=min(v,sdRb(p-float3(w*.455,.52,0),float3(w*.07,.42,z*.46),.08));
        [loop] for(int j=-1;j<=1;j++) v=min(v,sdRb(p-float3(j*w*.29,.57,z*.02),float3(w*.135,.12,z*.34),.07));
        return v;
    }
    if(kind<7.5){
        float v=sdRb(p-float3(0,.30,0),float3(w*.44,.23,z*.43),.10);
        v=min(v,sdRb(p-float3(0,.70,-z*.38),float3(w*.42,.33,z*.10),.08));
        v=min(v,sdRb(p-float3(-w*.42,.50,0),float3(w*.09,.36,z*.42),.07));
        v=min(v,sdRb(p-float3(w*.42,.50,0),float3(w*.09,.36,z*.42),.07));
        return v;
    }
    if(kind<8.5){
        float v=sdRb(p-float3(0,h-.055,0),float3(w*.5,.055,z*.5),.045);
        float3 leg=float3(w*.39,h*.44,z*.36);
        v=min(v,sdCy(p-float3(leg.x,leg.y,leg.z),h*.43,.035)); v=min(v,sdCy(p-float3(-leg.x,leg.y,leg.z),h*.43,.035));
        v=min(v,sdCy(p-float3(leg.x,leg.y,-leg.z),h*.43,.035)); v=min(v,sdCy(p-float3(-leg.x,leg.y,-leg.z),h*.43,.035)); return v;
    }
    if(kind<9.5){ float v=sdCy(p-float3(0,h-.045,0),.045,w*.48); return min(v,sdCy(p-float3(0,h*.47,0),h*.43,.045)); }
    if(kind<10.5){
        float v=sdRb(p-float3(0,h*.56,0),float3(w*.5,h*.40,z*.5),.035);
        v=min(v,sdBx(p-float3(0,h*.13,0),float3(w*.43,h*.06,z*.40)));
        return v;
    }
    if(kind<11.5){ float v=sdRb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.5),.035); return min(v,sdCy(p-float3(0,-.12,0),.12,.025)); }
    if(kind<12.5){
        float t=.055; float v=min(sdBx(p-float3(-w*.46,h*.5,0),float3(t,h*.5,z*.5)),sdBx(p-float3(w*.46,h*.5,0),float3(t,h*.5,z*.5)));
        v=min(v,sdBx(p-float3(0,h-.05,0),float3(w*.5,.05,z*.5)));
        [loop] for(int j=0;j<5;j++) v=min(v,sdBx(p-float3(0,.12+j*h*.205,0),float3(w*.46,.035,z*.5)));
        return v;
    }
    if(kind<13.5) return sdRb(p-float3(0,h*.5,0),d*.5,.025);
    if(kind<14.5){ float v=sdCy(p-float3(0,.055,0),.055,w*.38); v=min(v,sdCy(p-float3(0,h*.45,0),h*.40,.025)); v=min(v,sdCy(p-float3(0,h*.84,0),h*.14,w*.31)); return v; }
    if(kind<15.5){ float v=sdCy(p-float3(0,.10,0),.10,w*.30); v=min(v,sdCy(p-float3(0,h*.38,0),h*.22,.025)); v=min(v,sdCy(p-float3(0,h*.78,0),h*.19,w*.48)); return v; }
    if(kind<16.5){
        float v=sdCy(p-float3(0,.24,0),.24,w*.30); v=min(v,sdCy(p-float3(0,h*.45,0),h*.28,.035));
        [loop] for(int j=0;j<6;j++){ float a=j*1.047; float3 lp=float3(cos(a)*w*.24,h*(.62+.05*(j&1)),sin(a)*z*.24); v=smn(v,sdSp(p-lp,w*.23),.10); } return v;
    }
    if(kind<17.5){ float v=sdRb(p-float3(0,h*.5,0),d*.5,.025); return max(v,-sdBx(p-float3(0,h*.5,-z*.03),float3(w*.42,h*.42,z*.5))); }
    if(kind<18.5){ float v=sdRb(p-float3(0,h*.5,0),d*.5,.025); return v; }
    if(kind<19.5) return sdRb(p-float3(0,h*.5,0),d*.5,.11);
    if(kind<20.5) return sdRb(p-float3(0,h*.5,0),d*.5,.08);
    if(kind<21.5){ float v=sdCy(p-float3(0,h*.22,0),h*.22,w*.34); return min(v,sdSp(p-float3(0,h*.78,0),w*.30)); }
    float v=sdCy(p-float3(0,h*.82,0),h*.18,w*.46); return min(v,sdCy(p-float3(0,h*1.5,0),h*.7,.018));
}

float2 mapLane(float3 p,int lane,uint count,float2 best)
{
    [loop] for(uint i=0;i<count;i++){
        float3 pos=recPos(lane,i), dims=max(recDims(lane,i),.01); float kind=recKind(lane,i);
        float3 cen=pos+float3(0,dims.y*.5,0); float rad=length(dims)*.53; float bd=length(p-cen)-rad;
        if(bd<best.x+.25){ float3 q=p-pos; q.xz=r2(q.xz,-recYaw(lane,i)); float ds=furnitureSdf(q,kind,dims); if(ds<best.x) best=float2(ds,kind); }
    }
    return best;
}

float2 mapScene(float3 p)
{
    float2 b=float2(1000.0,-1.0);
    b=mapLane(p,0,min(_Data0_Count,96),b); b=mapLane(p,1,min(_Data1_Count,96),b);
    return b;
}

float3 normalAt(float3 p){ float e=.003; float2 h=float2(e,0); return normalize(float3(mapScene(p+h.xyy).x-mapScene(p-h.xyy).x,mapScene(p+h.yxy).x-mapScene(p-h.yxy).x,mapScene(p+h.yyx).x-mapScene(p-h.yyx).x)); }
float aoAt(float3 p,float3 n){ float o=0,sc=1; [loop] for(int j=1;j<=3;j++){ float h=.05*j; o+=(h-mapScene(p+n*h).x)*sc; sc*=.65; } return saturate(1-o*2.2); }

float3 matColor(float k,float3 p)
{
    if(k<.5){ float plank=step(.82,frac((p.x+p.z*.17)*3.5)); return lerp(float3(.24,.105,.045),float3(.42,.20,.075),plank*.22)+.025*sin(p.x*35); }
    if(k<3.5) return float3(.50,.48,.43);
    if(k<4.5) return float3(.44,.70,.88)*2.2;
    if(k<5.5) return float3(.14,.10,.07);
    if(k<6.5) return sofa_color;
    if(k<7.5) return chair_color;
    if(k<10.5) return wood_color;
    if(k<11.5) return float3(.025,.035,.045);
    if(k<12.5) return float3(.18,.12,.075);
    if(k<13.5){ float weave=.5+.5*sin(p.x*22)*sin(p.z*18); return lerp(rug_color,rug_color*.55,weave*.22); }
    if(k<15.5) return float3(.86,.57,.24);
    if(k<16.5) return float3(.08,.29,.10);
    if(k<17.5) return float3(.78,.33,.16);
    if(k<18.5) return float3(.055,.05,.045);
    if(k<19.5) return chair_color*.82;
    if(k<20.5) return accent_color;
    if(k<21.5) return float3(.42,.55,.62);
    return float3(1.0,.62,.22)*2.6;
}

float3 rayDirOrbit(float2 ndc,out float3 ro)
{
    float az=orbit_azimuth+orbit_phase*6.2831853; float el=orbit_elevation; float3 target=float3(orbit_target_x,orbit_target_y,orbit_target_z);
    ro=target+orbit_distance*float3(cos(el)*sin(az),sin(el),cos(el)*cos(az));
    float3 f=normalize(target-ro), r=normalize(cross(float3(0,1,0),f)), u=cross(f,r); return normalize(f+ndc.x*r*orbit_focal+ndc.y*u*orbit_focal);
}

[numthreads(8,8,1)]
void main(uint3 DTid:SV_DispatchThreadID)
{
    uint2 px=DTid.xy; if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    float2 uv=((float2)px+.5)/_Resolution.xy; float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);
    float3 ro,rd;
    if(cam_mode==0){ float4 nw=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)); float4 fw=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1)); nw/=nw.w; fw/=fw.w; ro=_CameraPos; rd=normalize(fw.xyz-nw.xyz); }
    else rd=rayDirOrbit(ndc,ro);
    float t=.02; float2 hit=float2(0,-1); int steps=max_steps;
    [loop] for(int s=0;s<96;s++){ if(s>=steps)break; float2 q=mapScene(ro+rd*t); if(q.x<.0025){hit=q;break;} t+=max(q.x*.78,.008); if(t>24)break; }
    float3 col=float3(.015,.022,.032)+float3(.03,.025,.02)*(1-uv.y);
    if(hit.y>=0){
        float3 p=ro+rd*t,n=normalAt(p),base=matColor(hit.y,p); float3 sun=normalize(float3(-.45,.72,.34)); float dif=saturate(dot(n,sun));
        float ao=aoAt(p,n); float3 warmDir=normalize(float3(.35,.72,-.20)); float warm=saturate(dot(n,warmDir));
        float fres=pow(1-saturate(dot(n,-rd)),4); float spec=pow(saturate(dot(reflect(-sun,n),-rd)),32);
        const float scenePulse = 0.5;
        col=base*(.18+.90*dif*daylight+.42*warm*warm_light*(.94+.06*scenePulse))*ao;
        col+=float3(.82,.91,1.0)*spec*.28+fres*float3(.08,.10,.12);
        if((hit.y>3.5&&hit.y<4.5)||(hit.y>13.5&&hit.y<15.5)||hit.y>21.5) col+=base*(.68+.08*scenePulse);
        col*=exp(-t*fog_amount*.035);
    }
    col=col/(1+col);
    OutputUAV[px]=float4(pow(saturate(col),1/2.2),1);
}
