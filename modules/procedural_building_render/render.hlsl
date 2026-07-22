RWTexture2D<float4> OutputUAV : register(u0);

#define PI 3.14159265359

float pbBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float pbRoundBox(float3 p, float3 b, float r) { return pbBox(p, max(b-r,0.001)) - r; }
float pbSphere(float3 p, float r) { return length(p)-r; }
float pbCylinderY(float3 p, float r, float h) {
    float2 d=abs(float2(length(p.xz),p.y))-float2(r,h);
    return min(max(d.x,d.y),0.0)+length(max(d,0.0));
}
float2 pbRot2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float2 pbMin(float2 a,float2 b){return a.x<b.x?a:b;}
float pbHash31(float3 p){p=frac(p*.1031);p+=dot(p,p.yzx+33.33);return frac((p.x+p.y)*p.z);}
float pbNoise3(float3 p){float3 i=floor(p),f=frac(p);f=f*f*(3-2*f);return lerp(lerp(lerp(pbHash31(i+float3(0,0,0)),pbHash31(i+float3(1,0,0)),f.x),lerp(pbHash31(i+float3(0,1,0)),pbHash31(i+float3(1,1,0)),f.x),f.y),lerp(lerp(pbHash31(i+float3(0,0,1)),pbHash31(i+float3(1,0,1)),f.x),lerp(pbHash31(i+float3(0,1,1)),pbHash31(i+float3(1,1,1)),f.x),f.y),f.z);}
float3 readP0Pos(uint i){return float3(_Data0[i].position[0],_Data0[i].position[1],_Data0[i].position[2]);}
float3 readP1Pos(uint i){return float3(_Data1[i].position[0],_Data1[i].position[1],_Data1[i].position[2]);}
float3 readP1Size(uint i){return float3(_Data1[i].size[0],_Data1[i].size[1],_Data1[i].size[2]);}

float2 facadeRibs(float3 p){
    if(_Data1_Count<2||_Data0_Count<3)return float2(1e5,5);
    uint frontBays=1;
    [loop]for(uint j=1;j<12;j++){if(j>=_Data1_Count)break;if(_Data1[j].floor_index>.5){frontBays=j;break;}}
    float3 e0=readP1Pos(0);float3 e1=readP1Pos(min(1u,_Data1_Count-1));
    float pitchX=max(abs(e1.x-e0.x),.2);
    float pitchY=1.5;if(frontBays<_Data1_Count)pitchY=max(abs(readP1Pos(frontBays).y-e0.y),.4);
    float3 b=readP0Pos(2);float w=_Data0[2].width,h=_Data0[2].height;
    float left=b.x-w*.5, bottom=b.y, front=e0.z+readP1Size(0).z*.5+.03;
    float cx=frac((p.x-left)/pitchX);float dx=min(cx,1-cx)*pitchX;
    float cy=frac((p.y-bottom)/pitchY);float dy=min(cy,1-cy)*pitchY;
    float dV=max(max(max(dx-.035,abs(p.x-b.x)-w*.5),abs(p.y-(bottom+h*.5))-h*.5),abs(p.z-front)-.10);
    float dH=max(max(max(dy-.032,abs(p.y-(bottom+h*.5))-h*.5),abs(p.x-b.x)-w*.5),abs(p.z-front)-.10);
    return float2(min(dV,dH),5.0);
}

float2 sceneMap(float3 p){
    float2 res=float2(p.y+.03,0.0);
    uint count=min((uint)_Data0_Count,12u);
    [loop]for(uint i=0;i<12;i++){
        if(i>=count)break;
        float3 base=readP0Pos(i);float h=_Data0[i].height,w=_Data0[i].width,d=_Data0[i].depth;
        float kind=_Data0[i].kind_id;float yaw=_Data0[i].yaw;
        float3 c=base+float3(0,h*.5,0);float3 q=p-c;q.xz=pbRot2(q.xz,-yaw);
        float2 hit=float2(1e5,0);
        if(kind<.5) hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.08),0);
        else if(kind<1.5) hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.10),1);
        else if(kind<2.5) hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.07),2);
        else if(kind<3.5) hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.08),11);
        else if(kind<4.5){
            hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.08),4);
            float columnA=pbCylinderY(p-float3(base.x-w*.38,base.y-1.45,base.z+d*.18),.10,1.45);
            float columnB=pbCylinderY(p-float3(base.x+w*.38,base.y-1.45,base.z+d*.18),.10,1.45);
            hit=pbMin(hit,float2(min(columnA,columnB),5));
            float downA=pbSphere(p-float3(base.x-w*.30,base.y-.015,base.z+d*.08),.075);
            float downB=pbSphere(p-float3(base.x,base.y-.015,base.z+d*.08),.075);
            float downC=pbSphere(p-float3(base.x+w*.30,base.y-.015,base.z+d*.08),.075);
            hit=pbMin(hit,float2(min(downA,min(downB,downC)),9));
        }
        else if(kind<5.5){
            float planter=pbRoundBox(q,float3(w,h,d)*.5,.12);
            hit=float2(planter,1);
            float3 crownC=base+float3(0,h+.55,0);
            float foliage=min(pbSphere(p-(crownC+float3(-.5,0,.05)),.72),pbSphere(p-(crownC+float3(.45,.08,-.08)),.67));
            foliage=min(foliage,pbSphere(p-(crownC+float3(0,.38,0)),.66));
            hit=pbMin(hit,float2(foliage,8));
        }
        else if(kind<6.5){
            float pole=pbCylinderY(p-(base+float3(0,h*.46,0)),w*.16,h*.46);
            float head=pbRoundBox(p-(base+float3(0,h*.91,0)),float3(.20,.12,.20),.05);
            hit=pbMin(float2(pole,5),float2(head,9));
        }
        else hit=float2(pbRoundBox(q,float3(w,h,d)*.5,.07),10);
        res=pbMin(res,hit);
    }
    if(_Data0_Count>4){
        float3 cp=readP0Pos(4);
        [unroll]for(int si=0;si<3;si++){
            float sw=4.8-(float)si*.45;float3 sc=float3(cp.x,.10+(float)si*.07,cp.z+1.15+(float)si*.38);
            res=pbMin(res,float2(pbRoundBox(p-sc,float3(sw*.5,.09,.34),.035),1));
        }
    }
    res=pbMin(res,facadeRibs(p));
    return res;
}

float3 calcNormal(float3 p){
    float e=.0025;float2 k=float2(1,-1);
    return normalize(k.xyy*sceneMap(p+k.xyy*e).x+k.yyx*sceneMap(p+k.yyx*e).x+k.yxy*sceneMap(p+k.yxy*e).x+k.xxx*sceneMap(p+k.xxx*e).x);
}
float rayMarch(float3 ro,float3 rd,out float matId){
    float t=.02;matId=0;
    [loop]for(int i=0;i<160;i++){
        if(i>=max_steps)break;float2 h=sceneMap(ro+rd*t);if(abs(h.x)<.0018*(1+t*.03)){matId=h.y;return t;}t+=max(h.x*.78,.002);if(t>75)break;
    }return -1;
}
float softShadow(float3 ro,float3 rd,float maxDist){
    float t=.035,res=1;
    [loop]for(int i=0;i<28;i++){float h=sceneMap(ro+rd*t).x;res=min(res,14*h/t);t+=clamp(h,.025,.65);if(h<.001||t>maxDist)break;}return saturate(res);
}
float ambientOcclusion(float3 p,float3 n){
    float occ=0,weight=1;
    [unroll]for(int i=1;i<=5;i++){float h=.045*i;occ+=(h-sceneMap(p+n*h).x)*weight;weight*=.68;}return saturate(1-occ*ao_strength);
}

void readMaterial(int idx,out float3 base,out float rough,out float3 secondary,out float metal,out float texScale,out float texStrength,out float pattern,out float emission,out float spec,out float normalAmount){
    idx=clamp(idx,0,(int)_Data2_Count-1);base=float3(_Data2[idx].base_color[0],_Data2[idx].base_color[1],_Data2[idx].base_color[2]);
    rough=_Data2[idx].roughness;secondary=float3(_Data2[idx].secondary_color[0],_Data2[idx].secondary_color[1],_Data2[idx].secondary_color[2]);metal=_Data2[idx].metallic;
    texScale=_Data2[idx].texture_scale;texStrength=_Data2[idx].texture_strength;pattern=_Data2[idx].pattern_id;emission=_Data2[idx].emissive;spec=_Data2[idx].specular;normalAmount=_Data2[idx].normal_strength;
}
float3 textureMaterial(float3 base,float3 second,float3 p,float3 n,float scale,float strength,float pattern){
    float v=pbNoise3(p*scale*.35);
    if(pattern<1.5){float joints=max(smoothstep(.46,.50,abs(frac(p.x*.42)-.5)),smoothstep(.46,.50,abs(frac(p.z*.42)-.5)));return lerp(lerp(base,second,v*strength),second,joints*.45);}
    if(pattern<2.5)return lerp(base,second,pbNoise3(p*scale*.65)*strength);
    if(pattern<3.5){float boards=smoothstep(.42,.49,abs(frac(p.y*scale*.45)-.5));return lerp(lerp(base,second,v*strength),second,boards*.32);}
    if(pattern<4.5)return lerp(base,second,pow(saturate(dot(reflect(normalize(p),n),float3(0,.7,.7))),4)*strength);
    if(pattern<5.5)return lerp(base,second,(.5+.5*sin((p.y+p.x*.08)*scale*15))*strength*.35);
    if(pattern<6.5)return lerp(base,second,(.5+.5*sin(p.x*scale*5+pbNoise3(p*2)*2))*strength);
    return lerp(base,second,pbNoise3(p*scale)*strength);
}

int materialAt(float3 p,int baseMat,out float windowEnergy,out float frameMask){
    windowEnergy=0;frameMask=0;
    if(baseMat==2){
        if(_Data0_Count>2){
            float3 b=readP0Pos(2);float front=b.z+_Data0[2].depth*.5;
            if(abs(p.x-b.x)<1.28&&p.y>b.y+.08&&p.y<b.y+2.65&&abs(p.z-front)<.34){
                frameMask=max(1-smoothstep(.035,.075,abs(p.x-b.x)),1-smoothstep(.035,.075,abs(p.y-(b.y+1.35))));windowEnergy=.22;return frameMask>.45?5:3;
            }
        }
        uint count=min((uint)_Data1_Count,160u);
        [loop]for(uint i=0;i<160;i++){if(i>=count)break;if(_Data1[i].active<.5)continue;float3 c=readP1Pos(i),sz=readP1Size(i);float3 q=p-c;q.xz=pbRot2(q.xz,-_Data1[i].yaw);if(abs(q.x)<sz.x*.5&&abs(q.y)<sz.y*.5&&abs(q.z)<.28){float mx=1-smoothstep(.022,.050,abs(q.x));float my=1-smoothstep(.020,.045,abs(q.y));frameMask=max(mx,my);windowEnergy=_Data1[i].emissive;return frameMask>.45?5:3;}}
    }
    return baseMat;
}
float3 skyColor(float3 rd,float3 sunDir,float3 sunColor,float3 skyTint){
    float h=saturate(rd.y*.5+.5);float3 horizon=skyTint*.30+float3(.10,.09,.08);float3 zenith=skyTint*.78+float3(.015,.025,.055);
    float3 col=lerp(horizon,zenith,pow(h,.55));float disk=pow(saturate(dot(rd,sunDir)),900);float glow=pow(saturate(dot(rd,sunDir)),18);
    float cloud=pbNoise3(rd*4.2+float3(2.1,7.3,4.8));cloud=smoothstep(.54,.78,cloud)*smoothstep(.05,.40,rd.y);col+=cloud*float3(.14,.15,.16);
    float angle=atan2(rd.x,rd.z);float skyline=.022+.010*sin(angle*13)+.008*sin(angle*29+1.2);float city=1-smoothstep(skyline,skyline+.008,rd.y);
    col=lerp(col,float3(.045,.060,.082)+skyTint*.10,city*.78);return col+sunColor*(disk*7+glow*.18);
}
float3 pbrLight(float3 base,float rough,float metal,float spec,float3 n,float3 v,float3 l,float3 color,float intensity,float visibility){
    float ndl=saturate(dot(n,l));if(ndl<=0)return 0;float3 h=normalize(v+l);float ndv=max(saturate(dot(n,v)),.001),ndh=saturate(dot(n,h)),vdh=saturate(dot(v,h));
    float a=max(rough*rough,.035);float a2=a*a;float den=ndh*ndh*(a2-1)+1;float D=a2/max(PI*den*den,.001);
    float k=(rough+1)*(rough+1)/8;float G=(ndl/(ndl*(1-k)+k))*(ndv/(ndv*(1-k)+k));float3 F0=lerp(.04*max(spec,.25),base,metal);float3 F=F0+(1-F0)*pow(1-vdh,5);
    float3 diffuse=(1-F)*(1-metal)*base/PI;float3 brdf=diffuse+D*G*F/max(4*ndl*ndv,.001);return brdf*color*intensity*ndl*visibility;
}

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){
    uint2 px=id.xy;if(px.x>=(uint)_Resolution.x||px.y>=(uint)_Resolution.y)return;
    // Canonical Sentinel camera contract: the native camera feature is the sole
    // owner. The saved node defaults to Fly; no authored orbit/hero mode exists.
    float2 uv=((float2)px+.5)/_Resolution.xy;
    float2 clip=float2(uv.x*2-1,1-uv.y*2);
    float4 nw=mul(_InvViewProjMatrix,float4(clip,0,1));
    float4 fw=mul(_InvViewProjMatrix,float4(clip,1,1));
    nw/=nw.w; fw/=fw.w;
    float3 ro=_CameraPos;
    float3 rd=normalize(fw.xyz-nw.xyz);

    float3 sunDir=float3(.55,.45,.70),sunCol=float3(1,.55,.28),skyTint=float3(.22,.38,.68);float sunPower=2,skyPower=.6;
    if(_Data3_Count>1){sunDir=normalize(float3(_Data3[0].direction[0],_Data3[0].direction[1],_Data3[0].direction[2]));sunCol=float3(_Data3[0].color[0],_Data3[0].color[1],_Data3[0].color[2]);sunPower=_Data3[0].intensity;skyTint=float3(_Data3[1].color[0],_Data3[1].color[1],_Data3[1].color[2]);skyPower=_Data3[1].intensity;}
    float3 bg=skyColor(rd,sunDir,sunCol,skyTint);float matF;float t=rayMarch(ro,rd,matF);float3 col=bg;
    if(t>0){
        float3 p=ro+rd*t,n=calcNormal(p),v=normalize(ro-p);float winEnergy,frameMask;int mid=materialAt(p,(int)round(matF),winEnergy,frameMask);
        float3 base,second;float rough,metal,scale,strength,pattern,matEmission,spec,normAmt;readMaterial(mid,base,rough,second,metal,scale,strength,pattern,matEmission,spec,normAmt);
        base=textureMaterial(base,second,p,n,scale,strength,pattern);float ao=ambientOcclusion(p,n);float vis=softShadow(p+n*.018,sunDir,45);
        col=pbrLight(base,rough,metal,spec,n,v,sunDir,sunCol,sunPower,vis);
        col+=base*(.045+.22*skyPower)*ao*(.45+.55*saturate(n.y*.5+.5));
        float3 refl=skyColor(reflect(-v,n),sunDir,sunCol,skyTint);col+=refl*(spec*.12+metal*.28+(mid==3?.42:0))*(1-rough*.72);
        uint lc=min((uint)_Data3_Count,8u);[loop]for(uint li=2;li<8;li++){if(li>=lc)break;if(_Data3[li].enabled<.5)continue;float3 lp=float3(_Data3[li].position[0],_Data3[li].position[1],_Data3[li].position[2]);float3 lv=lp-p;float dist=length(lv);float att=pow(saturate(1-dist/max(_Data3[li].range,.1)),2);float3 lcol=float3(_Data3[li].color[0],_Data3[li].color[1],_Data3[li].color[2]);col+=pbrLight(base,rough,metal,spec,n,v,lv/max(dist,.001),lcol,_Data3[li].intensity*att,1);}
        if(mid==3||mid==9||mid==11){float3 glowBase=float3(_Data2[9].base_color[0],_Data2[9].base_color[1],_Data2[9].base_color[2]);col+=glowBase*(winEnergy*interior_boost+matEmission*.35);}
        float fog=1-exp(-fog_density*max(t-8,0));col=lerp(col,bg,fog);col*=lerp(.72,1,ao);
    }
    // Native camera-space inverse depth for structure-guided downstream tools.
    // Near geometry is bright, distant geometry approaches black, and sky is black.
    float depthGuide = t > 0.0 ? saturate(1.0 - t / 75.0) : 0.0;
    OutputUAV[px]=float4(max(col,0),depthGuide);
}
