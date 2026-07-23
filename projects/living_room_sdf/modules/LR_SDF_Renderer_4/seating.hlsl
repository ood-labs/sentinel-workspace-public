RWTexture2D<float4> OutputUAV : register(u0);
float2 r2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float bx(float3 p,float3 b){float3 q=abs(p)-b;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0);}
float rb(float3 p,float3 b,float r){return bx(p,b-r)-r;}
float cy(float3 p,float h,float r){float2 d=abs(float2(length(p.xz),p.y))-float2(r,h);return min(max(d.x,d.y),0)+length(max(d,0));}
float sp(float3 p,float r){return length(p)-r;}
float cp(float3 p,float3 a,float3 b,float r){float3 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/dot(ba,ba)))-r;}
float2 H(float d,float m){return float2(d,m);}float2 U(float2 a,float2 b){return a.x<b.x?a:b;}
bool active(uint i){return i<=6||i==12||i==13||(i>=16&&i<=19);}
float3 fp(uint i){return float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]);}
float3 fd(uint i){return float3(_Data1[i].width,_Data1[i].height,_Data1[i].depth);}

float2 seatObject(float3 p,float k,float3 d,uint i)
{
    float w=d.x,h=d.y,z=d.z;float2 v=H(999,7);
    if(k<6.5){
        v=H(rb(p-float3(0,.22,z*.01),float3(w*.445,.105,z*.39),.024),9);
        v=U(v,H(rb(p-float3(0,.66,-z*.405),float3(w*.445,.285,z*.055),.026),7));
        v=U(v,H(rb(p-float3(-w*.455,.43,0),float3(w*.050,.245,z*.405),.025),7));v=U(v,H(rb(p-float3(w*.455,.43,0),float3(w*.050,.245,z*.405),.025),7));
        [loop]for(int j=-1;j<=1;j++){float3 cc=float3(j*w*.29,.45,z*.035);float cushion=rb(p-cc,float3(w*.132,.105,z*.325),.028);cushion=max(cushion,-sp(p-(cc+float3(0,.112,z*.025)),.018));v=U(v,H(cushion,7));v=U(v,H(cp(p,float3(j*w*.29-w*.105,.545,z*.352),float3(j*w*.29+w*.105,.545,z*.352),.007),11));float3 bc=float3(j*w*.29,.72,-z*.315);v=U(v,H(rb(p-bc,float3(w*.130,.205,z*.072),.028),7));v=U(v,H(cp(p,bc+float3(-w*.102,.198,z*.073),bc+float3(w*.102,.198,z*.073),.006),11));}
        [loop]for(int f=-1;f<=1;f+=2){v=U(v,H(cy(p-float3(f*w*.37,.095,z*.29),.085,.025),9));v=U(v,H(cy(p-float3(f*w*.37,.095,-z*.29),.085,.025),9));v=U(v,H(cy(p-float3(f*w*.37,.035,z*.29),.025,.045),13));v=U(v,H(cy(p-float3(f*w*.37,.035,-z*.29),.025,.045),13));}return v;
    }
    if(k<7.5){
        v=H(rb(p-float3(0,.23,0),float3(w*.39,.095,z*.37),.022),9);v=U(v,H(rb(p-float3(0,.69,-z*.39),float3(w*.365,.285,z*.050),.024),9));
        v=U(v,H(rb(p-float3(-w*.425,.43,0),float3(w*.055,.245,z*.37),.024),8));v=U(v,H(rb(p-float3(w*.425,.43,0),float3(w*.055,.245,z*.37),.024),8));float3 sc=float3(0,.445,z*.035);float seat=rb(p-sc,float3(w*.31,.105,z*.30),.026);seat=max(seat,-sp(p-(sc+float3(0,.112,z*.025)),.017));v=U(v,H(seat,8));float3 bc=float3(0,.71,-z*.305);v=U(v,H(rb(p-bc,float3(w*.29,.205,z*.068),.026),8));v=U(v,H(cp(p,float3(-w*.275,.54,z*.338),float3(w*.275,.54,z*.338),.008),9));
        [loop]for(int f=-1;f<=1;f+=2){v=U(v,H(cy(p-float3(f*w*.31,.10,z*.27),.09,.024),9));v=U(v,H(cy(p-float3(f*w*.31,.10,-z*.27),.09,.024),9));v=U(v,H(cy(p-float3(f*w*.31,.035,z*.27),.025,.040),13));v=U(v,H(cy(p-float3(f*w*.31,.035,-z*.27),.025,.040),13));}return v;
    }
    if(k<8.5){
        v=H(rb(p-float3(0,h-.06,0),float3(w*.5,.06,z*.5),.024),9);[loop]for(int x=-1;x<=1;x+=2)[loop]for(int q=-1;q<=1;q+=2)v=U(v,H(cy(p-float3(x*w*.39,h*.43,q*z*.36),h*.42,.032),10));
        return U(v,H(bx(p-float3(0,h*.62,0),float3(w*.40,.025,z*.34)),9));
    }
    if(k<9.5){v=H(cy(p-float3(0,h-.045,0),.045,w*.50),9);v=U(v,H(cy(p-float3(0,h*.48,0),h*.42,.035),13));return U(v,H(cy(p-float3(0,.055,0),.055,w*.27),13));}
    if(k<14.5){
        v=H(cy(p-float3(0,.055,0),.055,w*.36),13);v=U(v,H(cy(p-float3(0,h*.42,0),h*.38,.024),13));v=U(v,H(cp(p,float3(0,h*.78,0),float3(w*.45,h*.94,0),.024),13));
        v=U(v,H(max(cy(p-float3(w*.45,h*.82,0),.19,w*.34),-cy(p-float3(w*.45,h*.82,0),.20,w*.25)),20));return U(v,H(sp(p-float3(w*.45,h*.78,0),.07),21));
    }
    if(k<15.5){
        v=H(rb(p-float3(0,h*.18,0),float3(w*.27,h*.18,w*.27),.08),12);v=U(v,H(cy(p-float3(0,h*.46,0),h*.13,.025),13));
        v=U(v,H(max(cy(p-float3(0,h*.76,0),h*.20,w*.46),-cy(p-float3(0,h*.76,0),h*.22,w*.34)),20));return U(v,H(sp(p-float3(0,h*.68,0),.06),21));
    }
    if(k<19.5)return H(rb(p-float3(0,h*.5,0),d*.5,.058),8);
    if(k<20.5)return H(rb(p-float3(0,h*.5,0),d*.5,.042),19);
    v=H(rb(p-float3(-w*.15,.03,0),float3(w*.48,.025,z*.45),.015),23);v=U(v,H(rb(p-float3(-w*.10,.09,0),float3(w*.42,.025,z*.42),.012),22));
    return U(v,H(max(cy(p-float3(w*.34,.09,0),.075,w*.28),-cy(p-float3(w*.34,.12,0),.075,w*.20)),12));
}

float3 mapScene(float3 p){float3 best=float3(1000,-1,-1);[loop]for(uint i=0;i<min(_Data1_Count,23);i++){if(!active(i))continue;float3 pos=fp(i),d=max(fd(i),.01),q=p-pos;q.xz=r2(q.xz,-_Data1[i].yaw);float2 s=seatObject(q,_Data1[i].kind_id,d,i);if(s.x<best.x)best=float3(s.x,s.y,(float)i);}return best;}
float3 normalAt(float3 p,float t){float e=.0035+.0002*t;float3 n=0;[loop]for(int i=0;i<4;i++){float3 d=float3((i&1)?1:-1,(i&2)?1:-1,(i==0||i==3)?1:-1);n+=d*mapScene(p+d*e).x;}return normalize(n);}
float aoAt(float3 p,float3 n){float o=0,s=1;[loop]for(int j=1;j<=4;j++){float h=.04+j*.07;o+=(h-mapScene(p+n*h).x)*s;s*=.68;}return lerp(.44,1,saturate(1-o*ao_strength));}
struct Mat{float3 a;float rough;float3 b;float metal;float scale;float amount;float pattern;float emit;float spec;float norm;float seed;};
Mat mat(uint id){id=min(id,_Data2_Count-1);Mat m;m.a=float3(_Data2[id].base_color[0],_Data2[id].base_color[1],_Data2[id].base_color[2]);m.rough=_Data2[id].roughness;m.b=float3(_Data2[id].secondary_color[0],_Data2[id].secondary_color[1],_Data2[id].secondary_color[2]);m.metal=_Data2[id].metallic;m.scale=_Data2[id].texture_scale;m.amount=_Data2[id].texture_strength;m.pattern=_Data2[id].pattern_id;m.emit=_Data2[id].emissive;m.spec=_Data2[id].specular;m.norm=_Data2[id].normal_strength;m.seed=_Data2[id].seed;return m;}
float hs(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float3 baseColor(Mat m,float3 p,float t){float lod=1/(1+t*m.scale*.018),f=.5;if(m.pattern<1.5)f=.50+.28*sin((p.x*12+p.z*1.7+sin(p.x*2.1)*1.4)*lod)+.10*sin(p.x*37+p.z*3)*lod;else if(m.pattern<2.5)f=.50+.12*sin(p.x*1.3+p.y*.7)+.08*sin(p.z*1.9-p.y*1.1);else if(m.pattern<3.5)f=.45+.35*sin((p.y+p.x*.08)*m.scale)*lod;else if(m.pattern<5.5)f=.50+.22*sin(p.x*m.scale)*sin(p.z*m.scale*.82)*lod;else if(m.pattern<6.5)f=.48+.20*sin(p.x*m.scale)*sin((p.y+p.z)*m.scale*.73)*lod;else if(m.pattern<7.5)f=.46+.18*sin(dot(p,float3(11,7,5))+sin(p.z*19))*lod;else if(m.pattern<8.5)f=.42+.25*abs(sin(p.y*m.scale))*lod;return lerp(m.a,m.b,saturate(f)*m.amount);}
float3 bumpNormal(Mat m,float3 p,float3 n,float t){float fade=1/(1+t*.08);float3 g=float3(sin(p.y*m.scale*2.1+p.z*3.7),sin(p.z*m.scale*1.7+p.x*4.1),sin(p.x*m.scale*2.3+p.y*3.1));return normalize(n+g*(m.norm*.14*fade));}
float3 lp(uint i){return float3(_Data3[i].position[0],_Data3[i].position[1],_Data3[i].position[2]);}float3 lc(uint i){return float3(_Data3[i].color[0],_Data3[i].color[1],_Data3[i].color[2]);}
float3 shade(float3 p,float3 n,float3 v,float t,uint mid)
{
    Mat m=mat(mid);float3 base=baseColor(m,p,t);
    if(mid==7){float weave=.95+.05*abs(sin(p.x*61+p.z*3)*sin(p.y*67-p.z*4));base*=weave;}
    if(mid==8){float grain=.93+.045*sin(p.x*37+sin(p.y*23))+.025*sin(p.z*71+p.y*9);base*=grain;}
    if(mid==9){base*=.91+.09*sin(p.x*29+sin(p.z*8));}
    float ao=aoAt(p,n);n=bumpNormal(m,p,n,t);float visAO=lerp(.32,1,ao);float3 col=base*(.07+.15*saturate(n.y*.5+.5))*ao;
    [loop]for(uint i=0;i<min(_Data3_Count,6);i++){if(_Data3[i].type_id>2.5){col+=base*lc(i)*_Data3[i].intensity*.17*visAO;continue;}float3 dl=lp(i)-p;float dist=length(dl),att=pow(saturate(1-dist/max(_Data3[i].range,.1)),2),ndl=saturate(dot(n,dl/max(dist,.001)));float3 l=dl/max(dist,.001),hh=normalize(l+v);float fres=pow(1-saturate(dot(v,hh)),5);float specAmp=m.spec*lerp(.08,1,m.metal)*pow(1-m.rough*.72,2);float3 specular=lerp(.04.xxx,base,m.metal)*(specAmp*pow(saturate(dot(n,hh)),lerp(96,6,m.rough))*(1+fres));col+=(base*(1-m.metal)*ndl+specular)*lc(i)*_Data3[i].intensity*att*visAO;}
    col*=lerp(.68,1,saturate((p.y-.08)/.34));return col+base*m.emit;
}
void lockedView(int view,out float az,out float elv,out float dist,out float focal,out float3 target){if(view==0){az=-2.211;elv=.20;dist=4.75;focal=.56;target=float3(.15,1.05,.72);return;}if(view==1){az=-1.25;elv=.13;dist=3.75;focal=.74;target=float3(-.25,.96,.62);return;}if(view==2){az=.82;elv=.15;dist=4.65;focal=.72;target=float3(.15,1.02,.12);return;}az=2.92;elv=.15;dist=3.35;focal=.72;target=float3(-.15,1.02,1.05);}
float3 cameraRay(float2 uv,out float3 ro){float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);if(cam_mode==0){float4 a=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)),b=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1));a/=a.w;b/=b.w;ro=_CameraPos;return normalize(b.xyz-a.xyz);}float az,elv,dist,focal;float3 target;if(cam_mode==2)lockedView(evaluation_view,az,elv,dist,focal,target);else{az=orbit_azimuth+orbit_phase*6.2831853;elv=orbit_elevation;dist=orbit_distance;focal=orbit_focal;target=float3(orbit_target_x,orbit_target_y,orbit_target_z);}ro=target+dist*float3(cos(elv)*sin(az),sin(elv),cos(elv)*cos(az));float3 f=normalize(target-ro),rr=normalize(cross(float3(0,1,0),f)),u=cross(f,rr);return normalize(f+ndc.x*rr*focal+ndc.y*u*focal);}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float2 uv=((float2)id.xy+.5)/_Resolution.xy;float3 ro,ray=cameraRay(uv,ro),h=float3(0,-1,-1);float t=.02;[loop]for(int s=0;s<128;s++){if(s>=max_steps)break;float3 q=mapScene(ro+ray*t);if(q.x<.002+.00025*t){h=q;break;}t+=max(q.x*.78,.005);if(t>26)break;}float3 c=h.y<0?0:shade(ro+ray*t,normalAt(ro+ray*t,t),-ray,t,(uint)h.y)*exp(-t*fog_amount*.025);OutputUAV[id.xy]=float4(max(c,0),h.y<0?1000:t);}
