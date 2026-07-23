RWTexture2D<float4> OutputUAV : register(u0);

float2 r2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float bx(float3 p,float3 b){float3 q=abs(p)-b;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0);}
float rb(float3 p,float3 b,float r){return bx(p,b-r)-r;}
float cy(float3 p,float h,float r){float2 d=abs(float2(length(p.xz),p.y))-float2(r,h);return min(max(d.x,d.y),0)+length(max(d,0));}
float sp(float3 p,float r){return length(p)-r;}
float2 H(float d,float m){return float2(d,m);}
float2 U(float2 a,float2 b){return a.x<b.x?a:b;}
float3 ap(uint i){return float3(_Data0[i].position[0],_Data0[i].position[1],_Data0[i].position[2]);}
float3 ad(uint i){return float3(_Data0[i].width,_Data0[i].height,_Data0[i].depth);}

float2 archObject(float3 p,float k,float3 d,uint i)
{
    float w=d.x,h=d.y,z=d.z;float2 v=H(999,1);
    if(k<.5)return H(bx(p-float3(0,h*.5,0),d*.5),0);
    if(k<3.5)return H(bx(p-float3(0,h*.5,0),d*.5),(i==2||i==12)?2:1);
    if(k<4.5){
        v=U(H(rb(p-float3(-w*.48,h*.5,0),float3(.055,h*.52,z*.7),.02),3),H(rb(p-float3(w*.48,h*.5,0),float3(.055,h*.52,z*.7),.02),3));
        v=U(v,H(rb(p-float3(0,.03,0),float3(w*.52,.055,z*.8),.02),3));v=U(v,H(rb(p-float3(0,h-.03,0),float3(w*.52,.055,z*.8),.02),3));
        v=U(v,H(bx(p-float3(0,h*.5,0),float3(.03,h*.44,z*.8)),3));v=U(v,H(bx(p-float3(0,h*.5,0),float3(w*.44,.025,z*.8)),3));
        v=U(v,H(bx(p-float3(0,h*.5,z*.18),float3(w*.445,h*.44,.018)),4));return U(v,H(rb(p-float3(0,-.06,z*.08),float3(w*.58,.07,z),.02),12));
    }
    if(k<5.5){
        v=H(rb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.5),.025),5);v=U(v,H(rb(p-float3(0,h*.30,-z*.52),float3(w*.37,h*.13,.025),.015),9));
        v=U(v,H(rb(p-float3(0,h*.70,-z*.52),float3(w*.37,h*.13,.025),.015),9));return U(v,H(sp(p-float3(w*.34,h*.5,-z*.65),.045),13));
    }
    if(k<13.5)return H(rb(p-float3(0,h*.5,0),d*.5,.035),6);
    if(k<17.5){
        v=H(rb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.5),.025),16);v=U(v,H(rb(p-float3(0,h*.5,-z*.54),float3(w*.41,h*.41,.025),.012),(i&1)?18:17));
        return U(v,H(bx(p-float3(0,h*.5,z*.54),float3(w*.18,h*.18,z*.10)),3));
    }
    v=H(cy(p-float3(0,h*1.28,0),h*.70,.012),10);v=U(v,H(cy(p-float3(0,h*1.98,0),.025,w*.20),13));
    v=U(v,H(max(cy(p-float3(0,h*.80,0),h*.22,w*.46),-cy(p-float3(0,h*.80,0),h*.24,w*.34)),20));return U(v,H(sp(p-float3(0,h*.66,0),w*.12),21));
}

float3 mapScene(float3 p)
{
    float3 best=float3(1000,-1,-1);
    [loop]for(uint i=0;i<min(_Data0_Count,32);i++){
        float3 pos=ap(i),d=max(ad(i),.01),q=p-pos;q.xz=r2(q.xz,-_Data0[i].yaw);float2 s=archObject(q,_Data0[i].kind_id,d,i);
        if(i==1&&_Data0_Count>5){float3 wp=ap(5),wd=ad(5);s.x=max(s.x,-bx(p-(wp+float3(0,wd.y*.5,0)),float3(wd.x*.47,wd.y*.47,.32)));}
        if(i==3&&_Data0_Count>6){float3 dp=p-ap(6);dp.xz=r2(dp.xz,-_Data0[6].yaw);float3 dd=ad(6);s.x=max(s.x,-bx(dp-float3(0,dd.y*.5,0),float3(dd.x*.56,dd.y*.52,.35)));}
        if(s.x<best.x)best=float3(s.x,s.y,(float)i);
    }return best;
}

float3 normalAt(float3 p,float t){float e=.0035+.0002*t;float3 n=0;[loop]for(int i=0;i<4;i++){float3 d=float3((i&1)?1:-1,(i&2)?1:-1,(i==0||i==3)?1:-1);n+=d*mapScene(p+d*e).x;}return normalize(n);}
float aoAt(float3 p,float3 n){float o=0,s=1;[loop]for(int j=1;j<=4;j++){float h=.04+j*.075;o+=(h-mapScene(p+n*h).x)*s;s*=.68;}return saturate(1-o*ao_strength);}

struct Mat{float3 a;float rough;float3 b;float metal;float scale;float amount;float pattern;float emit;float spec;float seed;};
Mat mat(uint id){id=min(id,_Data2_Count-1);Mat m;m.a=float3(_Data2[id].base_color[0],_Data2[id].base_color[1],_Data2[id].base_color[2]);m.rough=_Data2[id].roughness;m.b=float3(_Data2[id].secondary_color[0],_Data2[id].secondary_color[1],_Data2[id].secondary_color[2]);m.metal=_Data2[id].metallic;m.scale=_Data2[id].texture_scale;m.amount=_Data2[id].texture_strength;m.pattern=_Data2[id].pattern_id;m.emit=_Data2[id].emissive;m.spec=_Data2[id].specular;m.seed=_Data2[id].seed;return m;}
float hs(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float3 baseColor(Mat m,float3 p,float t){float lod=1/(1+t*m.scale*.018),f=.5+.5*sin(dot(p,float3(7.1,3.3,5.7))+m.seed);if(m.pattern<1.5)f=.5+.35*sin((p.x*10+p.z*1.3+f*1.2)*lod);else if(m.pattern>4.5&&m.pattern<8.5)f=.45+.25*sin(p.x*m.scale)*sin((p.y+p.z)*m.scale*.8)*lod;else if(m.pattern>9.5&&m.pattern<11.5)f=.5+.5*sin(p.x*5+p.y*7+sin(p.z*4));return lerp(m.a,m.b,saturate(f)*m.amount);}
float3 lp(uint i){return float3(_Data3[i].position[0],_Data3[i].position[1],_Data3[i].position[2]);}
float3 lc(uint i){return float3(_Data3[i].color[0],_Data3[i].color[1],_Data3[i].color[2]);}
float contactShadow(float3 p)
{
    float sh=1;
    [loop]for(uint i=0;i<min(_Data1_Count,23);i++){float2 q=p.xz-float2(_Data1[i].position[0],_Data1[i].position[2]);q=r2(q,-_Data1[i].yaw);float2 d=float2(_Data1[i].width,_Data1[i].depth)*.58+.14;float ellipse=length(q/max(d,.08));sh*=lerp(.48,1,smoothstep(.55,1.35,ellipse));}
    return sh;
}
float3 shade(float3 p,float3 n,float3 v,float t,uint mid){Mat m=mat(mid);float3 base=baseColor(m,p,t);float ao=aoAt(p,n);if(mid==0)ao*=contactShadow(p);float3 col=base*(.055+.11*saturate(n.y*.5+.5))*ao;
    [loop]for(uint i=0;i<min(_Data3_Count,6);i++){if(_Data3[i].type_id>2.5){col+=base*lc(i)*_Data3[i].intensity*.22;continue;}float3 dl=lp(i)-p;float dist=length(dl),att=pow(saturate(1-dist/max(_Data3[i].range,.1)),2),ndl=saturate(dot(n,dl/max(dist,.001)));float3 hh=normalize(dl/max(dist,.001)+v);float spec=pow(saturate(dot(n,hh)),lerp(80,5,m.rough))*m.spec;col+=(base*ndl+spec)*lc(i)*_Data3[i].intensity*att;}return col+base*m.emit;}

void lockedView(int view,out float az,out float elv,out float dist,out float focal,out float3 target){if(view==0){az=-2.211;elv=.20;dist=4.75;focal=.56;target=float3(.15,1.05,.72);return;}if(view==1){az=-1.25;elv=.13;dist=3.75;focal=.74;target=float3(-.25,.96,.62);return;}if(view==2){az=.82;elv=.15;dist=4.65;focal=.72;target=float3(.15,1.02,.12);return;}az=2.92;elv=.15;dist=3.35;focal=.72;target=float3(-.15,1.02,1.05);}
float3 cameraRay(float2 uv,out float3 ro){float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);if(cam_mode==0){float4 a=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)),b=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1));a/=a.w;b/=b.w;ro=_CameraPos;return normalize(b.xyz-a.xyz);}float az,elv,dist,focal;float3 target;if(cam_mode==2)lockedView(evaluation_view,az,elv,dist,focal,target);else{az=orbit_azimuth+orbit_phase*6.2831853;elv=orbit_elevation;dist=orbit_distance;focal=orbit_focal;target=float3(orbit_target_x,orbit_target_y,orbit_target_z);}ro=target+dist*float3(cos(elv)*sin(az),sin(elv),cos(elv)*cos(az));float3 f=normalize(target-ro),rr=normalize(cross(float3(0,1,0),f)),u=cross(f,rr);return normalize(f+ndc.x*rr*focal+ndc.y*u*focal);}
float3 env(float3 ray){float y=saturate(ray.y*.5+.5);return lerp(float3(.025,.025,.03),float3(.16,.24,.34),y);}

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float2 uv=((float2)id.xy+.5)/_Resolution.xy;float3 ro,ray=cameraRay(uv,ro),h=float3(0,-1,-1);float t=.02;[loop]for(int s=0;s<128;s++){if(s>=max_steps)break;float3 q=mapScene(ro+ray*t);if(q.x<.002+.00025*t){h=q;break;}t+=max(q.x*.78,.005);if(t>26)break;}float3 c=h.y<0?env(ray):shade(ro+ray*t,normalAt(ro+ray*t,t),-ray,t,(uint)h.y)*exp(-t*fog_amount*.025);OutputUAV[id.xy]=float4(max(c,0),h.y<0?1000:t);}
