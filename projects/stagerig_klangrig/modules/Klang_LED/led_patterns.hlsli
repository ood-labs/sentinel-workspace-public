// Programmed LED content 5-15 (0-4 live in content.hlsl). Each returns lit RGB before master/gain.
// u runs round each wing loop, t across its band; P is the pixel's world position on the truss.
// Knobs: lane phase/active (l.x/l.y), WIDTH, SPREAD, OFFSET, DIRECTION; base/accent = LED palettes.
#define TAU 6.2831853
float ledHash(float2 p){return frac(sin(dot(p,float2(127.1,311.7)))*43758.5453);}
float3 loopPoint(uint wing,float u){ // reads the global R (Rig Segments)
    float len[4];float total=0;
    for(uint j=0;j<4;j++){RigRecord r=R[1+wing*4+j];len[j]=length(r.b.xyz-r.a.xyz);total+=len[j];}
    float d=u*total;
    for(uint k=0;k<4;k++){RigRecord r=R[1+wing*4+k];if(d<=len[k]||k==3)return lerp(r.a.xyz,r.b.xyz,saturate(d/max(.001,len[k])));d-=len[k];}
    return R[1+wing*4].a.xyz;
}
float gauss(float x,float w){return exp(-x*x/max(1e-5,w*w));}
float wrapDist(float a,float b){float d=abs(frac(a)-frac(b));return min(d,1-d);}

float3 ledPattern(uint pat,uint wing,float u,float t,float4 l,uint lane,KlangProgram pr,float rank,
                  float3 base,float3 accent,float3 P,float3 C,float time){
    float W=pr.timing.x,SP=pr.movement.w,dir=pr.timing.z>.5?-1:1;
    bool left=wing%2==0,up=wing%4<2;
    float uu=left?1-u:u;                      // mirror the loops so left/right move symmetrically
    float ph=(lane>0?l.x:time*.25)+pr.timing.y;// no lane: free-run one cycle every 4 s
    float act=lane>0?l.y:1;
    float band=1-smoothstep(.085,.105,abs(t-.5));// thin centre line (~quarter of the band); keep content thin
    float val=0;float3 col=base;

    if(pat==5){ // COMET: a head with a long decaying tail laps each loop, loops staggered along the rig
        float h=frac(ph*2*dir-rank*SP);float d=frac(h-uu);
        val=exp(-d/max(.02,W*.35))*band;col=lerp(base,accent,exp(-d*45));
        val+=exp(-d*120)*.8;
    }else if(pat==6){ // TWIN SPIN: hard counter-rotating heads; as they meet the loop blinks hard
        // and hard echo ticks fire outward from the meeting point
        float a=frac(ph-rank*SP),b=frac(-ph+rank*SP+.5);float seg=.01+W*.03;
        float ha=step(wrapDist(uu,a),seg),hb=step(wrapDist(uu,b),seg);float gap=wrapDist(a,b);
        float m1=frac((a+b)*.5),m2=frac(m1+.5);float m=wrapDist(a,m1)<wrapDist(a,m2)?m1:m2;
        float blink=gap<.06?step(.5,frac(gap/.06*2.5)):0;
        float echo=gap<.22?step(abs(wrapDist(uu,m)-gap*2.4),seg*.5)*(1-gap/.22):0;
        val=max(max(ha,hb),max(blink*.9,echo))*band;
        col=hb>0?accent:(ha>0?base:(echo>0?lerp(accent,1,.5):accent));
    }else if(pat==7){ // FILL: loops fill round then drain, staggered; bright leading edge
        float f=frac(ph-rank*SP);float level=f<.5?f*2:2-f*2;
        val=(uu<level?.75:0)+gauss(uu-level,.012)*1.5;col=lerp(base,accent,gauss(uu-level,.03));val*=band;
    }else if(pat==8){ // SCANNER: ping-pong bar with two fading ghosts behind it
        float s=ph-rank*SP;float w=.015+W*.08;
        for(int g=0;g<3;g++){float p=.5-.5*cos(TAU*(s-g*.035));val+=gauss(uu-p,w)*(g==0?1:.35/g);}
        col=lerp(base,accent,saturate(val-.8));val*=band;
    }else if(pat==9){ // BARCODE: short sparse ticks scroll fast, opposite ways on upper/lower tiers
        float n=floor(10+W*30);float x=uu*n+ph*12*dir*(up?1:-1);float i=floor(x);
        val=step(frac(x),.18)*band*(ledHash(float2(i,wing))>.55?1:0);
        col=fmod(abs(i),3)<1?accent:base;
    }else if(pat==10){ // PLASMA: interfering waves in world space flow through the whole rig
        float k=.4+SP*1.6;float a=ph*TAU;
        float v=sin(P.x*.9*k+a)+sin(P.z*.35*k-a*1.3)+sin((P.y+P.x)*.7*k+t*3)+sin(length(P.xz-C.xz)*.6*k-a*2);
        val=.5+.5*sin(v*1.6);val=lerp(.15,1,val*val)*band;col=lerp(base,accent,.5+.5*sin(v*1.1+a));
    }else if(pat==11){ // SPARKLE: random cells twinkle over a dim glow; WIDTH sets density
        float cell=floor(uu*96);float h=ledHash(float2(cell,wing));float s=frac(ph*3+h*7);
        float on=ledHash(float2(wing,cell*1.37))<.25+W*.7?1:0;
        float spark=exp(-s*16)*on*band;
        val=.04*band+spark*(.5+.5*act)*1.4;col=lerp(base,accent,saturate(spark*1.5));
    }else if(pat==12){ // HEARTBEAT: lub-dub from each edge's midpoint outward, decaying by WIDTH
        float age=frac(ph-rank*SP);float e=frac(u*4);float m=abs(e-.5)*2;
        float beat=exp(-age/max(.03,W*.2))+.7*(age>.18?exp(-(age-.18)/max(.03,W*.2)):0);
        float reach=saturate(.25+age*5);
        val=beat*(1-smoothstep(reach-.15,reach,m))*band*act;col=lerp(accent,base,m);
    }else if(pat==13){ // EDGE HOP: one of each loop's four edges per beat, neighbours offset
        float s=(ph-rank*SP)*4;float step_=floor(s),age=frac(s);uint e=(uint)floor(u*4)%4;
        val=(e==((uint)step_+wing)%4)?exp(-age/max(.05,W*.6)):0;val*=band*act;col=(wing%2==0)?base:accent;
    }else if(pat==14){ // CHEVRON: sparse thin diagonal ticks; tiers lean opposite ways; WIDTH = tick size
        float x=uu*6+t*1.2*(up?1:-1)-ph*4*dir;float i=floor(x);float f=frac(x);
        float duty=.03+W*.3;val=step(f,duty)*band*(ledHash(float2(i,wing+20))>.4?1:0);
        col=fmod(abs(i),2)<1?base:accent;
    }else{ // 15 RIPPLE: spherical shock rings expand from rig centre on each hit, with an accent echo
        float d=length(P-C)/(18/(.5+SP));float age=frac(ph);float w=.02+W*.12;
        val=gauss(d-age*1.3,w)+.55*gauss(d-(age-.18)*1.3,w*.8);val*=act*band;
        col=lerp(base,accent,saturate(gauss(d-(age-.18)*1.3,w*.8)*2));
    }
    return col*val;
}
