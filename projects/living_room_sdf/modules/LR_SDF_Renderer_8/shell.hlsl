RWTexture2D<float4> OutputUAV : register(u0);

#include "distortion.hlsli"

float2 r2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float bx(float3 p,float3 b){float3 q=abs(p)-b;return length(max(q,0))+min(max(q.x,max(q.y,q.z)),0);}
float rb(float3 p,float3 b,float r){return bx(p,b-r)-r;}
float cy(float3 p,float h,float r){float2 d=abs(float2(length(p.xz),p.y))-float2(r,h);return min(max(d.x,d.y),0)+length(max(d,0));}
float sp(float3 p,float r){return length(p)-r;}
float2 H(float d,float m){return float2(d,m);}
float2 U(float2 a,float2 b){return a.x<b.x?a:b;}
float3 ap(uint i){return float3(_Data0[i].position[0],_Data0[i].position[1],_Data0[i].position[2]);}
float3 ad(uint i){return float3(_Data0[i].width,_Data0[i].height,_Data0[i].depth);}

bool artworkTargetMatches(uint objectId)
{
    if(art_texture_target==0)return objectId==11; // Right frame.
    if(art_texture_target==1)return objectId==10; // Left frame.
    return objectId==10||objectId==11;             // Both frames.
}

bool artworkBTargetMatches(uint objectId)
{
    if(art2_texture_target==0)return objectId==10; // Left frame.
    return objectId==11;                           // Right frame.
}

int artworkLane(uint objectId)
{
    // B intentionally wins if both lanes target the same frame.
    if(art2_texture_enabled!=0&&artworkBTargetMatches(objectId))return 2;
    if(art_texture_enabled!=0&&artworkTargetMatches(objectId))return 1;
    return 0;
}

bool artworkDepthEnabledForLane(int lane){return lane==2?art2_depth_enabled!=0:art_depth_enabled!=0;}
float artworkReliefAmountForLane(int lane){return lane==2?art2_depth_amount:art_depth_amount;}
int artworkDepthDirectionForLane(int lane){return lane==2?art2_depth_direction:art_depth_direction;}
float artworkRecessForLane(int lane){return lane==2?art2_depth_recess:art_depth_recess;}

bool artworkInward(uint objectId)
{
    int lane=artworkLane(objectId);
    return lane!=0&&artworkDepthEnabledForLane(lane)&&artworkDepthDirectionForLane(lane)==1;
}

float2 artworkFrameUv(float3 localPosition,float3 dimensions)
{
    return float2(
        .5-localPosition.x/(dimensions.x*.82),
        .5-(localPosition.y-dimensions.y*.5)/(dimensions.y*.82));
}

float2 artworkTextureUv(float2 frameUv,float3 dimensions,float sourceWidth,float sourceHeight,float2 pan,float zoom)
{
    float sourceAspect=max(sourceWidth,1)/max(sourceHeight,1);
    float frameAspect=dimensions.x/dimensions.y;
    float2 coverScale=1.0.xx;
    if(sourceAspect>frameAspect)coverScale.x=frameAspect/sourceAspect;
    else coverScale.y=sourceAspect/frameAspect;
    float2 visibleScale=coverScale/max(zoom,1.0);
    float2 cropMargin=max((1.0.xx-visibleScale)*.5,0.0.xx);
    return saturate(.5.xx+pan*cropMargin+(frameUv-.5.xx)*visibleScale);
}

float artworkDepth(float3 localPosition,float3 dimensions,int lane)
{
    float2 frameUv=artworkFrameUv(localPosition,dimensions);
    float depthWidth,depthHeight;
    float2 depthUv;
    float depthValue;
    float edgeFade;
    if(lane==2){
        _Tex7.GetDimensions(depthWidth,depthHeight);
        depthUv=artworkTextureUv(frameUv,dimensions,depthWidth,depthHeight,art2_texture_pan,art2_texture_zoom);
        depthValue=_Tex7.SampleLevel(LinearSampler,depthUv,0).r;
        depthValue=saturate((depthValue-art2_depth_black)/max(art2_depth_white-art2_depth_black,.001));
        if(art2_depth_invert!=0)depthValue=1-depthValue;
        depthValue=pow(max(depthValue,0.0001),max(art2_depth_gamma,.05));
        edgeFade=art2_depth_edge_fade;
    }else{
        _Tex5.GetDimensions(depthWidth,depthHeight);
        depthUv=artworkTextureUv(frameUv,dimensions,depthWidth,depthHeight,art_texture_pan,art_texture_zoom);
        depthValue=_Tex5.SampleLevel(LinearSampler,depthUv,0).r;
        depthValue=saturate((depthValue-art_depth_black)/max(art_depth_white-art_depth_black,.001));
        if(art_depth_invert!=0)depthValue=1-depthValue;
        depthValue=pow(max(depthValue,0.0001),max(art_depth_gamma,.05));
        edgeFade=art_depth_edge_fade;
    }

    // Return to the original canvas plane before reaching the inner frame.
    // This seals the height field and prevents relief from cutting the border.
    float edgeDistance=min(min(frameUv.x,1-frameUv.x),min(frameUv.y,1-frameUv.y));
    float edgeMask=smoothstep(0,max(edgeFade,.001),edgeDistance);
    return depthValue*edgeMask;
}

float artworkCanvasDistance(float3 localPosition,float3 dimensions,uint objectId)
{
    float3 center=float3(0,dimensions.y*.5,dimensions.z*.54);
    float3 halfSize=float3(dimensions.x*.41,dimensions.y*.41,.025);
    int lane=artworkLane(objectId);
    bool depthEnabled=artworkDepthEnabledForLane(lane);
    float reliefAmount=artworkReliefAmountForLane(lane);
    if(lane==0||!depthEnabled||reliefAmount<=.0001)
        return rb(localPosition-center,halfSize,.006);

    float relief=artworkDepth(localPosition,dimensions,lane)*reliefAmount;
    float2 side=abs(localPosition.xy-center.xy)-halfSize.xy;
    float sideDistance=min(max(side.x,side.y),0)+length(max(side,0));
    if(artworkDepthDirectionForLane(lane)==1){
        float surfaceZ=center.z+halfSize.z-artworkRecessForLane(lane)-relief;
        return max(sideDistance,abs(localPosition.z-surfaceZ)-.012);
    }
    float backDistance=(center.z-halfSize.z)-localPosition.z;
    float frontDistance=localPosition.z-(center.z+halfSize.z+relief);
    return max(sideDistance,max(backDistance,frontDistance));
}

float artworkCavityDistance(float3 localPosition,float3 dimensions,uint objectId)
{
    int lane=artworkLane(objectId);
    float cavityDepth=artworkRecessForLane(lane)+artworkReliefAmountForLane(lane)+.10;
    float frontZ=dimensions.z*.565+.035;
    float3 cavityCenter=float3(0,dimensions.y*.5,frontZ-cavityDepth*.5);
    return bx(localPosition-cavityCenter,float3(dimensions.x*.405,dimensions.y*.405,cavityDepth*.5));
}

float artworkWorldCavityDistance(float3 distortedWorldPosition,uint objectId)
{
    float3 dimensions=max(ad(objectId),.01);
    float3 localPosition=distortedWorldPosition-ap(objectId);
    localPosition.xz=r2(localPosition.xz,-_Data0[objectId].yaw);
    return artworkCavityDistance(localPosition,dimensions,objectId);
}

float2 archObject(float3 p,float k,float3 d,uint i)
{
    float w=d.x,h=d.y,z=d.z;float2 v=H(999,1);
    if(k<.5)return H(bx(p-float3(0,h*.5,0),d*.5),0);
    if(k<3.5){float2 wall=H(bx(p-float3(0,h*.5,0),d*.5),(i==2||i==12)?2:1);float3 trimB=float3(w>z?w*.49:w*.88,.060,w>z?z*.88:z*.49);wall=U(wall,H(rb(p-float3(0,.065,0),trimB,.012),20));wall=U(wall,H(rb(p-float3(0,h-.055,0),trimB*float3(1,.75,1),.010),20));if(i==12){[loop]for(int j=-10;j<=10;j++){float x=j*.34;bool behindArt=abs(x+1.60)<.62||abs(x-1.10)<.62;if(!behindArt)wall=U(wall,H(rb(p-float3(x,h*.50,z*.72),float3(.022,h*.43,.028),.008),9));}}return wall;}
    if(k<4.5){
        v=U(H(rb(p-float3(-w*.48,h*.5,0),float3(.055,h*.52,z*.7),.02),3),H(rb(p-float3(w*.48,h*.5,0),float3(.055,h*.52,z*.7),.02),3));
        v=U(v,H(rb(p-float3(0,.03,0),float3(w*.52,.055,z*.8),.02),3));v=U(v,H(rb(p-float3(0,h-.03,0),float3(w*.52,.055,z*.8),.02),3));
        v=U(v,H(bx(p-float3(0,h*.5,0),float3(.03,h*.44,z*.8)),3));v=U(v,H(bx(p-float3(0,h*.5,0),float3(w*.44,.025,z*.8)),3));
        v=U(v,H(bx(p-float3(0,h*.5,z*.18),float3(w*.445,h*.44,.018)),4));v=U(v,H(cy((p-float3(0,h+.13,z*.08)).yxz,w*.54,.022),13));[loop]for(int side=-1;side<=1;side+=2)[loop]for(int fold=0;fold<4;fold++){float x=side*(w*.56+fold*.045);v=U(v,H(cy(p-float3(x,h*.48,z*.04),h*.46,.025),20));}return U(v,H(rb(p-float3(0,-.06,z*.08),float3(w*.58,.07,z),.02),12));
    }
    if(k<5.5){
        v=H(rb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.5),.025),5);v=U(v,H(rb(p-float3(0,h*.30,-z*.52),float3(w*.37,h*.13,.025),.015),9));
        v=U(v,H(rb(p-float3(0,h*.70,-z*.52),float3(w*.37,h*.13,.025),.015),9));return U(v,H(sp(p-float3(w*.34,h*.5,-z*.65),.045),13));
    }
    if(k<13.5){v=H(rb(p-float3(0,h*.5,0),d*.5,.025),6);float border=max(rb(p-float3(0,h+.012,0),float3(w*.49,.018,z*.49),.012),-rb(p-float3(0,h+.012,0),float3(w*.42,.030,z*.42),.010));return U(v,H(border,22));}
    if(k<17.5){
        float frameDistance=rb(p-float3(0,h*.5,0),float3(w*.5,h*.5,z*.5),.012);
        if(artworkInward(i))frameDistance=max(frameDistance,-artworkCavityDistance(p,d,i));
        v=H(frameDistance,16);v=U(v,H(artworkCanvasDistance(p,d,i),(i&1)?18:17));
        // The rear mounting block is hidden in flat/outward mode, but a deep
        // inward height field can intersect it. Omit it only for the portal
        // configuration so the recessed artwork has an unobstructed cavity.
        if(artworkInward(i))return v;
        return U(v,H(bx(p-float3(0,h*.5,-z*.54),float3(w*.18,h*.18,z*.10)),3));
    }
    v=H(cy(p-float3(0,h*1.28,0),h*.70,.012),10);v=U(v,H(cy(p-float3(0,h*1.98,0),.025,w*.20),13));
    v=U(v,H(max(cy(p-float3(0,h*.80,0),h*.22,w*.46),-cy(p-float3(0,h*.80,0),h*.24,w*.34)),20));return U(v,H(sp(p-float3(0,h*.66,0),w*.12),21));
}

float3 mapScene(float3 p)
{
    p=lrDomainDistort(p,fx_architecture);
    float3 best=float3(1000,-1,-1);
    [loop]for(uint i=0;i<min(_Data0_Count,32);i++){
        float3 pos=ap(i),d=max(ad(i),.01),q=p-pos;q.xz=r2(q.xz,-_Data0[i].yaw);float2 s=archObject(q,_Data0[i].kind_id,d,i);
        if(_Data0[i].kind_id<3.5){
            if(_Data0_Count>10&&artworkInward(10))s.x=max(s.x,-artworkWorldCavityDistance(p,10));
            if(_Data0_Count>11&&artworkInward(11))s.x=max(s.x,-artworkWorldCavityDistance(p,11));
        }
        if(i==1&&_Data0_Count>5){float3 wp=ap(5),wd=ad(5);s.x=max(s.x,-bx(p-(wp+float3(0,wd.y*.5,0)),float3(wd.x*.47,wd.y*.47,.32)));}
        if(i==3&&_Data0_Count>6){float3 dp=p-ap(6);dp.xz=r2(dp.xz,-_Data0[6].yaw);float3 dd=ad(6);s.x=max(s.x,-bx(dp-float3(0,dd.y*.5,0),float3(dd.x*.56,dd.y*.52,.35)));}
        if(s.x<best.x)best=float3(s.x,s.y,(float)i);
    }best.x*=lrDistortLip(fx_architecture);return best;
}

float3 normalAt(float3 p,float t){float e=.0035+.0002*t;float3 n=0;[loop]for(int i=0;i<4;i++){float3 d=float3((i&1)?1:-1,(i&2)?1:-1,(i==0||i==3)?1:-1);n+=d*mapScene(p+d*e).x;}return normalize(n);}
float aoAt(float3 p,float3 n){float o=0,s=1;[loop]for(int j=1;j<=4;j++){float h=.04+j*.075;o+=(h-mapScene(p+n*h).x)*s;s*=.68;}return lerp(.38,1,saturate(1-o*ao_strength));}

struct Mat{float3 a;float rough;float3 b;float metal;float scale;float amount;float pattern;float emit;float spec;float norm;float seed;};
Mat mat(uint id){id=min(id,_Data2_Count-1);Mat m;m.a=float3(_Data2[id].base_color[0],_Data2[id].base_color[1],_Data2[id].base_color[2]);m.rough=_Data2[id].roughness;m.b=float3(_Data2[id].secondary_color[0],_Data2[id].secondary_color[1],_Data2[id].secondary_color[2]);m.metal=_Data2[id].metallic;m.scale=_Data2[id].texture_scale;m.amount=_Data2[id].texture_strength;m.pattern=_Data2[id].pattern_id;m.emit=_Data2[id].emissive;m.spec=_Data2[id].specular;m.norm=_Data2[id].normal_strength;m.seed=_Data2[id].seed;return m;}
float hs(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float3 baseColor(Mat m,float3 p,float t){float lod=1/(1+t*m.scale*.018),f=.5;if(m.pattern<1.5)f=.50+.28*sin((p.x*12+p.z*1.7+sin(p.x*2.1)*1.4)*lod)+.10*sin(p.x*37+p.z*3)*lod;else if(m.pattern<2.5)f=.50+.12*sin(p.x*1.3+p.y*.7)+.08*sin(p.z*1.9-p.y*1.1);else if(m.pattern<3.5)f=.45+.35*sin((p.y+p.x*.08)*m.scale)*lod;else if(m.pattern<4.5)f=.35+.25*pow(1-saturate(abs(dot(normalize(p+float3(.1,.2,.3)),float3(0,0,1)))),3);else if(m.pattern<5.5)f=.50+.22*sin(p.x*m.scale)*sin(p.z*m.scale*.82)*lod;else if(m.pattern<6.5)f=.48+.20*sin(p.x*m.scale)*sin((p.y+p.z)*m.scale*.73)*lod;else if(m.pattern<7.5)f=.46+.18*sin(dot(p,float3(11,7,5))+sin(p.z*19))*lod;else if(m.pattern<8.5)f=.42+.25*abs(sin(p.y*m.scale))*lod;else if(m.pattern<9.5)f=.35+.45*sin(p.x*5+p.y*7+sin(p.z*4));else if(m.pattern<11.5)f=.5+.5*sin(p.x*5+p.y*7+sin(p.z*4));return lerp(m.a,m.b,saturate(f)*m.amount);}
float3 bumpNormal(Mat m,float3 p,float3 n,float t){float fade=1/(1+t*.08);float3 g=float3(sin(p.y*m.scale*2.1+p.z*3.7),sin(p.z*m.scale*1.7+p.x*4.1),sin(p.x*m.scale*2.3+p.y*3.1));return normalize(n+g*(m.norm*.14*fade));}

float4 sampleArtwork(float3 worldPosition,uint objectId)
{
    float3 dimensions=max(ad(objectId),.01);
    float3 localPosition=lrDomainDistort(worldPosition,fx_architecture)-ap(objectId);
    localPosition.xz=r2(localPosition.xz,-_Data0[objectId].yaw);

    float sourceWidth,sourceHeight;
    float2 textureUv;
    float4 artwork;
    if(artworkLane(objectId)==2){
        _Tex6.GetDimensions(sourceWidth,sourceHeight);
        textureUv=artworkTextureUv(artworkFrameUv(localPosition,dimensions),dimensions,sourceWidth,sourceHeight,art2_texture_pan,art2_texture_zoom);
        artwork=_Tex6.SampleLevel(LinearSampler,textureUv,0);
        artwork.a*=art2_texture_opacity;
    }else{
        _Tex4.GetDimensions(sourceWidth,sourceHeight);
        textureUv=artworkTextureUv(artworkFrameUv(localPosition,dimensions),dimensions,sourceWidth,sourceHeight,art_texture_pan,art_texture_zoom);
        artwork=_Tex4.SampleLevel(LinearSampler,textureUv,0);
        artwork.a*=art_texture_opacity;
    }
    artwork.rgb=pow(saturate(artwork.rgb),2.2.xxx);

    // Keep a subtle physical canvas weave while leaving image color intact.
    float weave=.975+.025*abs(sin(localPosition.x*83)*sin(localPosition.y*89));
    artwork.rgb*=weave;
    return artwork;
}

float3 lp(uint i){return float3(_Data3[i].position[0],_Data3[i].position[1],_Data3[i].position[2]);}
float3 lc(uint i){return float3(_Data3[i].color[0],_Data3[i].color[1],_Data3[i].color[2]);}
float contactShadow(float3 p)
{
    float sh=1;
    [loop]for(uint i=0;i<min(_Data1_Count,23);i++){float2 q=p.xz-float2(_Data1[i].position[0],_Data1[i].position[2])-float2(.14,-.20);q=r2(q,-_Data1[i].yaw);float2 d=float2(_Data1[i].width,_Data1[i].depth)*.58+.12;float core=length(q/max(d,.08));float cast=length((q-float2(.08,-.14))/max(d*float2(1.05,1.35),.08));sh*=lerp(.18,1,smoothstep(.48,1.35,core));sh*=lerp(.72,1,smoothstep(.42,1.42,cast));}
    return sh;
}
float3 shade(float3 p,float3 n,float3 v,float t,uint mid,uint objectId)
{
    Mat m=mat(mid);float3 base=baseColor(m,p,t);float artworkCoverage=0;
    if((mid==17||mid==18)&&artworkLane(objectId)!=0){
        float4 artwork=sampleArtwork(p,objectId);artworkCoverage=saturate(artwork.a);base=lerp(base,artwork.rgb,artworkCoverage);
    }
    if(mid==0){float plank=frac((p.x+8)*3.45),seam=smoothstep(.014,.050,min(plank,1-plank));float grain=.91+.06*sin(p.z*31+sin(p.z*6+p.x*2))+.025*sin(p.z*83+p.x*5);float joint=smoothstep(.012,.045,abs(frac((p.z+8)*.72+floor((p.x+8)*3.45)*.37)-.5));base*=grain*lerp(.78,1,seam*joint);}
    if(mid==1||mid==2){float fleck=hs(floor(p*34));base*=.94+.09*fleck;}
    if(mid==4){float y=saturate((p.y-.55)/2.25);base=lerp(float3(.78,.88,.94),float3(.16,.36,.62),y);float skyline=.72+.34*hs(float3(floor(p.x*2.4),0,0));base=lerp(float3(.055,.085,.12),base,smoothstep(skyline-.05,skyline+.05,p.y));float sun=smoothstep(.22,.04,length(float2(p.x+2.45,p.y-2.18)));base+=sun*float3(1,.72,.38)*1.8;}
    if(mid==6){float weave=.95+.05*abs(sin(p.x*58)*sin(p.z*61));float motif=.5+.5*sin(p.x*3.2)*sin(p.z*3.8);base*=weave*lerp(.88,1,smoothstep(.35,.70,motif));}
    if(mid==17||mid==18){float ink=smoothstep(.42,.48,abs(sin(p.x*4.7+p.y*3.1)));base=lerp(base,base.bgr*.72,ink*.24*(1-artworkCoverage));}
    float ao=aoAt(p,n);if(mid==0||mid==6)ao*=contactShadow(p);n=bumpNormal(m,p,n,t);float visAO=lerp(.28,1,ao);float3 col=base*(.07+.15*saturate(n.y*.5+.5))*ao;
    [loop]for(uint i=0;i<min(_Data3_Count,6);i++){if(_Data3[i].type_id>2.5){col+=base*lc(i)*_Data3[i].intensity*.20*visAO;continue;}float3 dl=lp(i)-p;float dist=length(dl),att=pow(saturate(1-dist/max(_Data3[i].range,.1)),2),ndl=saturate(dot(n,dl/max(dist,.001)));float3 l=dl/max(dist,.001),hh=normalize(l+v);float fres=pow(1-saturate(dot(v,hh)),5);float specAmp=m.spec*lerp(.08,1,m.metal)*pow(1-m.rough*.72,2);float3 specular=lerp(.04.xxx,base,m.metal)*(specAmp*pow(saturate(dot(n,hh)),lerp(96,6,m.rough))*(1+fres));col+=(base*(1-m.metal)*ndl+specular)*lc(i)*_Data3[i].intensity*att*visAO;}
    [loop]for(uint j=1;j<min(_Data3_Count,5);j++){float dist=length(lp(j)-p),range=max(_Data3[j].range,.1);float pool=exp(-dist*dist/(range*range*.13));col+=base*lc(j)*_Data3[j].intensity*pool*.075*visAO;}
    if(mid==0||mid==6)col*=lerp(.46,1,contactShadow(p));return col+base*m.emit;
}

void lockedView(int view,out float az,out float elv,out float dist,out float focal,out float3 target){if(view==0){az=-2.211;elv=.20;dist=4.75;focal=.56;target=float3(.15,1.05,.72);return;}if(view==1){az=-1.25;elv=.13;dist=3.75;focal=.74;target=float3(-.25,.96,.62);return;}if(view==2){az=.82;elv=.15;dist=4.65;focal=.72;target=float3(.15,1.02,.12);return;}az=2.92;elv=.15;dist=3.35;focal=.72;target=float3(-.15,1.02,1.05);}
float3 cameraRay(float2 uv,out float3 ro){float2 ndc=float2((uv.x*2-1)*(_Resolution.x/_Resolution.y),1-uv.y*2);if(cam_mode==0){float4 a=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,0,1)),b=mul(_InvViewProjMatrix,float4(ndc.x/(_Resolution.x/_Resolution.y),ndc.y,1,1));a/=a.w;b/=b.w;ro=_CameraPos;return normalize(b.xyz-a.xyz);}float az,elv,dist,focal;float3 target;if(cam_mode==2)lockedView(evaluation_view,az,elv,dist,focal,target);else{az=orbit_azimuth+orbit_phase*6.2831853;elv=orbit_elevation;dist=orbit_distance;focal=orbit_focal;target=float3(orbit_target_x,orbit_target_y,orbit_target_z);}ro=target+dist*float3(cos(elv)*sin(az),sin(elv),cos(elv)*cos(az));float3 f=normalize(target-ro),rr=normalize(cross(float3(0,1,0),f)),u=cross(f,rr);return normalize(f+ndc.x*rr*focal+ndc.y*u*focal);}
float3 env(float3 ray){float y=saturate(ray.y*.5+.5);return lerp(float3(.025,.025,.03),float3(.16,.24,.34),y);}

[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID){if(id.x>=(uint)_Resolution.x||id.y>=(uint)_Resolution.y)return;float2 uv=((float2)id.xy+.5)/_Resolution.xy;float3 ro,ray=cameraRay(uv,ro),h=float3(0,-1,-1);float t=.02;float marchScale=((art_texture_enabled!=0&&art_depth_enabled!=0)||(art2_texture_enabled!=0&&art2_depth_enabled!=0))?.36:.78;[loop]for(int s=0;s<128;s++){if(s>=max_steps)break;float3 q=mapScene(ro+ray*t);if(q.x<.002+.00025*t){h=q;break;}t+=max(q.x*marchScale,.003);if(t>26)break;}float3 c=h.y<0?env(ray):shade(ro+ray*t,normalAt(ro+ray*t,t),-ray,t,(uint)h.y,(uint)h.z)*exp(-t*fog_amount*.025);OutputUAV[id.xy]=float4(max(c,0),h.y<0?1000:t);}
