RWTexture2D<float4> OutputUAV : register(u0);
#include "distortion.hlsli"
float2 r2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float bx(float3 p,float3 b){float3 q=abs(p)-b;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0);}
float rb(float3 p,float3 b,float r){return bx(p,b-r)-r;}
float cy(float3 p,float h,float r){float2 d=abs(float2(length(p.xz),p.y))-float2(r,h);return min(max(d.x,d.y),0)+length(max(d,0));}
float sp(float3 p,float r){return length(p)-r;}
float cp(float3 p,float3 a,float3 b,float r){float3 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/dot(ba,ba)))-r;}
float el(float3 p,float3 r){float k0=length(p/r),k1=length(p/(r*r));return k0*(k0-1)/max(k1,.0001);}
float2 H(float d,float m){return float2(d,m);}float2 U(float2 a,float2 b){return a.x<b.x?a:b;}
bool active(uint i){return (i>=7&&i<=11)||(i>=14&&i<=15)||(i>=20&&i<=22);}
float3 fp(uint i){return float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]);}float3 fd(uint i){return float3(_Data1[i].width,_Data1[i].height,_Data1[i].depth);}

float2 mediaObject(float3 p,float k,float3 d,uint i)
{
    float w=d.x,h=d.y,z=d.z;float2 v=H(999,9);
    if(k<10.5){
        v=H(rb(p-float3(0,h*.60,0),float3(w*.5,h*.38,z*.5),.016),9);v=U(v,H(bx(p-float3(0,h*.14,0),float3(w*.46,h*.055,z*.42)),10));
        [loop]for(int j=-1;j<=1;j++){float x=j*w*.30;v=U(v,H(rb(p-float3(x,h*.60,-z*.52),float3(w*.135,h*.25,.018),.01),5));v=U(v,H(rb(p-float3(x,h*.60,-z*.56),float3(w*.05,.012,.01),.006),13));}return v;
    }
    if(k<11.5){
        v=H(rb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.50),.012),10);v=U(v,H(rb(p-float3(0,h*.52,-z*.56),float3(w*.465,h*.44,.012),.006),10));
        v=U(v,H(bx(p-float3(0,h*.50,z*.70),float3(w*.22,h*.18,z*.18)),3));v=U(v,H(cy(p-float3(0,-.245,z*.65),.245,.018),3));return U(v,H(sp(p-float3(w*.39,h*.08,-z*.59),.012),21));
    }
    if(k<12.5){
        v=U(H(bx(p-float3(-w*.47,h*.5,0),float3(.055,h*.5,z*.5)),9),H(bx(p-float3(w*.47,h*.5,0),float3(.055,h*.5,z*.5)),9));
        [loop]for(int j=0;j<5;j++){float y=.08+j*h*.22;v=U(v,H(bx(p-float3(0,y,0),float3(w*.47,.035,z*.5)),9));[loop]for(int b=0;b<3;b++)v=U(v,H(rb(p-float3(-w*.26+b*w*.20,y+.12,-z*.36),float3(w*.05,.11,z*.10),.008),23));}return v;
    }
    if(k<16.5){
        v=H(cy(p-float3(0,.24,0),.24,w*.32),14);[loop]for(int j=0;j<11;j++){float a=j*.571;float tier=(float)(j%3);float3 a1=float3(cos(a)*w*(.13+.025*tier),h*(.56+.060*tier+.018*(j&1)),sin(a)*z*(.13+.025*tier));float3 tip=a1+float3(cos(a)*w*(.30+.025*tier),h*(.07+.020*tier),sin(a)*z*(.30+.025*tier));v=U(v,H(cp(p,float3(0,.43,0),a1,.013),16));float3 center=lerp(a1,tip,.48),q=p-center;q.xz=r2(q.xz,-a);q.xy=r2(q.xy,-.34+.10*tier);v=U(v,H(el(q,float3(w*.25,h*.040,z*.075)),15));v=U(v,H(cp(p,a1,tip,.006),16));}return v;
    }
    if(k<18.5){
        v=H(rb(p-float3(0,h*.5,0),d*.5,.035),10);v=U(v,H(rb(p-float3(0,h*.53,-z*.52),float3(w*.42,h*.42,.015),.02),11));
        v=U(v,H(cy((p-float3(0,h*.68,-z*.56)).xzy,.035,w*.23),3));return U(v,H(cy((p-float3(0,h*.30,-z*.56)).xzy,.055,w*.29),3));
    }
    if(i==20){v=H(cy(p-float3(0,h*.34,0),h*.28,w*.30),12);v=U(v,H(sp(p-float3(0,h*.62,0),w*.24),12));return U(v,H(cy(p-float3(0,h*.78,0),.025,w*.15),13));}
    if(i==21){[loop]for(int j=0;j<3;j++)v=U(v,H(rb(p-float3(0,.035+j*.07,0),float3(w*.5,.03,z*.45),.01),j==1?17:23));return v;}
    v=H(cy(p-float3(0,h*.45,0),h*.25,w*.22),12);v=U(v,H(sp(p-float3(0,h*.75,0),w*.18),13));return U(v,H(cy(p-float3(0,h*.94,0),h*.18,.015),16));
}
float3 mapScene(float3 p){p=lrDomainDistort(p,fx_media);float3 best=float3(1000,-1,-1);[loop]for(uint i=0;i<min(_Data1_Count,23);i++){if(!active(i))continue;float3 pos=fp(i),d=max(fd(i),.01),q=p-pos;q.xz=r2(q.xz,-_Data1[i].yaw);float2 s=mediaObject(q,_Data1[i].kind_id,d,i);if(s.x<best.x)best=float3(s.x,s.y,(float)i);}best.x*=lrDistortLip(fx_media);return best;}
float3 normalAt(float3 p,float t){float e=.0035+.0002*t;float3 n=0;[loop]for(int i=0;i<4;i++){float3 d=float3((i&1)?1:-1,(i&2)?1:-1,(i==0||i==3)?1:-1);n+=d*mapScene(p+d*e).x;}return normalize(n);}
float aoAt(float3 p,float3 n){float o=0,s=1;[loop]for(int j=1;j<=4;j++){float h=.04+j*.07;o+=(h-mapScene(p+n*h).x)*s;s*=.68;}return lerp(.44,1,saturate(1-o*ao_strength));}
struct Mat{float3 a;float rough;float3 b;float metal;float scale;float amount;float pattern;float emit;float spec;float norm;float seed;};
Mat mat(uint id){id=min(id,_Data2_Count-1);Mat m;m.a=float3(_Data2[id].base_color[0],_Data2[id].base_color[1],_Data2[id].base_color[2]);m.rough=_Data2[id].roughness;m.b=float3(_Data2[id].secondary_color[0],_Data2[id].secondary_color[1],_Data2[id].secondary_color[2]);m.metal=_Data2[id].metallic;m.scale=_Data2[id].texture_scale;m.amount=_Data2[id].texture_strength;m.pattern=_Data2[id].pattern_id;m.emit=_Data2[id].emissive;m.spec=_Data2[id].specular;m.norm=_Data2[id].normal_strength;m.seed=_Data2[id].seed;return m;}
float hs(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float3 baseColor(Mat m,float3 p,float t){float lod=1/(1+t*m.scale*.018),f=.5;if(m.pattern<1.5)f=.50+.28*sin((p.x*12+p.z*1.7+sin(p.x*2.1)*1.4)*lod)+.10*sin(p.x*37+p.z*3)*lod;else if(m.pattern<2.5)f=.50+.12*sin(p.x*1.3+p.y*.7)+.08*sin(p.z*1.9-p.y*1.1);else if(m.pattern<3.5)f=.45+.35*sin((p.y+p.x*.08)*m.scale)*lod;else if(m.pattern<5.5)f=.50+.22*sin(p.x*m.scale)*sin(p.z*m.scale*.82)*lod;else if(m.pattern<6.5)f=.48+.20*sin(p.x*m.scale)*sin((p.y+p.z)*m.scale*.73)*lod;else if(m.pattern<7.5)f=.46+.18*sin(dot(p,float3(11,7,5))+sin(p.z*19))*lod;else if(m.pattern<8.5)f=.42+.25*abs(sin(p.y*m.scale))*lod;else if(m.pattern<9.5)f=.35+.45*sin(p.x*5+p.y*7+sin(p.z*4));else if(m.pattern<11.5)f=.5+.5*sin(p.x*5+p.y*7+sin(p.z*4));return lerp(m.a,m.b,saturate(f)*m.amount);}
float3 bumpNormal(Mat m,float3 p,float3 n,float t){float fade=1/(1+t*.08);float3 g=float3(sin(p.y*m.scale*2.1+p.z*3.7),sin(p.z*m.scale*1.7+p.x*4.1),sin(p.x*m.scale*2.3+p.y*3.1));return normalize(n+g*(m.norm*.14*fade));}
float3 lp(uint i){return float3(_Data3[i].position[0],_Data3[i].position[1],_Data3[i].position[2]);}float3 lc(uint i){return float3(_Data3[i].color[0],_Data3[i].color[1],_Data3[i].color[2]);}
float3 shade(float3 p,float3 n,float3 v,float t,uint mid)
{
    Mat m=mat(mid);float3 base=baseColor(m,p,t);
    if(mid==5||mid==9){float grain=.91+.06*sin(p.x*33+sin(p.z*9))+.03*sin(p.x*91+p.y*7);base*=grain;}
    if(mid==10){float refl=saturate(.5+.5*sin(p.x*1.7+p.y*2.4));base=lerp(float3(.006,.009,.014),float3(.025,.075,.12),refl*.42);}
    if(mid==11){base*=.91+.09*abs(sin(p.y*56)*sin(p.x*51));}
    if(mid==15){float veins=.89+.11*abs(sin(p.x*18+p.z*11));base*=veins;}
    float ao=aoAt(p,n);n=bumpNormal(m,p,n,t);float visAO=lerp(.32,1,ao);float3 col=base*(.07+.15*saturate(n.y*.5+.5))*ao;
    [loop]for(uint i=0;i<min(_Data3_Count,6);i++){if(_Data3[i].type_id>2.5){col+=base*lc(i)*_Data3[i].intensity*.17*visAO;continue;}float3 dl=lp(i)-p;float dist=length(dl),att=pow(saturate(1-dist/max(_Data3[i].range,.1)),2),ndl=saturate(dot(n,dl/max(dist,.001)));float3 l=dl/max(dist,.001),hh=normalize(l+v);float fres=pow(1-saturate(dot(v,hh)),5);float specAmp=m.spec*lerp(.08,1,m.metal)*pow(1-m.rough*.72,2);float3 specular=lerp(.04.xxx,base,m.metal)*(specAmp*pow(saturate(dot(n,hh)),lerp(96,6,m.rough))*(1+fres));col+=(base*(1-m.metal)*ndl+specular)*lc(i)*_Data3[i].intensity*att*visAO;}
    float soft=pow(saturate(dot(n,normalize(float3(-.38,.72,.42)))),mid==10?28:16);if(mid==5||mid==9)col+=float3(.14,.075,.03)*soft*.13;if(mid==10)col+=float3(.12,.20,.28)*soft*.18;if(mid==13)col+=float3(.55,.32,.10)*soft*.22;
    col*=lerp(.70,1,saturate((p.y-.08)/.34));return col+base*m.emit;
}
void lockedView(int view,out float az,out float elv,out float dist,out float focal,out float3 target){if(view==0){az=-2.211;elv=.20;dist=4.75;focal=.56;target=float3(.15,1.05,.72);return;}if(view==1){az=-1.25;elv=.13;dist=3.75;focal=.74;target=float3(-.25,.96,.62);return;}if(view==2){az=.82;elv=.15;dist=4.65;focal=.72;target=float3(.15,1.02,.12);return;}az=2.92;elv=.15;dist=3.35;focal=.72;target=float3(-.15,1.02,1.05);}
float3 cameraRay(float2 uv,out float3 ro){float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);if(cam_mode==0){float4 a=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)),b=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1));a/=a.w;b/=b.w;ro=_CameraPos;return normalize(b.xyz-a.xyz);}float az,elv,dist,focal;float3 target;if(cam_mode==2)lockedView(evaluation_view,az,elv,dist,focal,target);else{az=orbit_azimuth+orbit_phase*6.2831853;elv=orbit_elevation;dist=orbit_distance;focal=orbit_focal;target=float3(orbit_target_x,orbit_target_y,orbit_target_z);}ro=target+dist*float3(cos(elv)*sin(az),sin(elv),cos(elv)*cos(az));float3 f=normalize(target-ro),rr=normalize(cross(float3(0,1,0),f)),u=cross(f,rr);return normalize(f+ndc.x*rr*focal+ndc.y*u*focal);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float2 uv=((float2)id.xy+.5)/_Resolution.xy;float3 ro,ray=cameraRay(uv,ro),h=float3(0,-1,-1);float t=.02;[loop]for(int s=0;s<128;s++){if(s>=max_steps)break;float3 q=mapScene(ro+ray*t);if(q.x<.002+.00025*t){h=q;break;}t+=max(q.x*.78,.005);if(t>26)break;}float3 c=h.y<0?0:shade(ro+ray*t,normalAt(ro+ray*t,t),-ray,t,(uint)h.y)*exp(-t*fog_amount*.025);OutputUAV[id.xy]=float4(max(c,0),h.y<0?1000:t);}
