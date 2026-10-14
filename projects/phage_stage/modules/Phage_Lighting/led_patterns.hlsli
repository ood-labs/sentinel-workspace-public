// Pixel-bar LOOK patterns 0-15. u runs 0..1 along the whole bar (hip -> knee -> ankle on the legs,
// round the rings), P is the pixel's world position, rank the bar's place in the programmed ORDER.
// Knobs: lane phase/active, WIDTH, SPREAD, OFFSET, DIRECTION; base/accent = COLOUR / COLOUR 2.
#define TAU 6.2831853
float ledHash(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float gauss(float x,float w){return exp(-x*x/max(1e-5,w*w));}
float wrap01(float x){return x-floor(x+.5);}
float3 ledPattern(uint pat,uint bar,float u,float4 l,uint lane,PhProgram pr,float rank,float3 base,float3 accent,float3 P,float beat,float gate,float rate){
 float W=pr.timing.x,SP=pr.movement.w;float uu=pr.timing.z>.5?1-u:u;
 float ph=l.x+pr.timing.y,act=lane>0?l.y:1,s=ph-rank*SP;float val=0;float3 col=base;
 if(pat==0){val=lane>0?phChase(pr,l,rank,PH_BAR0+bar):1;}                       // SOLID
 else if(pat==1){float h=frac(s)*1.3-.15;float w=.03+W*.3;                         // CHASE: a pulse runs the bar
  val=gauss(uu-h,w)*act;col=lerp(base,accent,gauss(uu-h,w*.35));}
 else if(pat==2){val=(.5+.5*cos(s*TAU))*act;}                                     // PULSE: breathe
 else if(pat==3){float n=floor(2+W*10);float k=floor(frac(s)*n);                  // SEGMENTS: step along
  val=(floor(uu*n)==k?1:0)*act;col=fmod(k,2)<1?base:accent;}
 else if(pat==4){float tick=floor(beat*rate);float cell=floor(u*(8+W*40));         // SCATTER: beat-locked flecks
  val=(ledHash(float3(bar,cell,tick))<.22+W*.3?gate:0)*act;col=ledHash(float3(cell,bar,tick*.37))<.5?base:accent;}
 else if(pat==5){float h=frac(s);float d=frac(h-uu);                              // COMET: head + tail
  val=(exp(-d/max(.02,W*.35))+exp(-d*120)*.8)*act;col=lerp(base,accent,exp(-d*45));}
 else if(pat==6){float a=frac(s)*.5;float w=.02+W*.08;                            // TWIN: meet in the middle
  float meet=smoothstep(.42,.5,a);val=(gauss(uu-a,w)+gauss(uu-(1-a),w)+meet*1.2*gauss(uu-.5,.08+meet*.3))*act;
  col=lerp(base,accent,meet);}
 else if(pat==7){float f=frac(s);float lv=f<.5?f*2:2-f*2;                          // FILL: fill, then drain
  val=((uu<lv?.7:0)+gauss(uu-lv,.015)*1.4)*act;col=lerp(base,accent,gauss(uu-lv,.04));}
 else if(pat==8){float w=.015+W*.08;[unroll]for(int g=0;g<3;g++){float p=.5-.5*cos(TAU*(s-g*.035));val+=gauss(uu-p,w)*(g==0?1:.35/g);}
  val*=act;col=lerp(base,accent,saturate(val-.8));}                                  // SCANNER: ping-pong + ghosts
 else if(pat==9){float n=floor(6+W*30);float x=uu*n+ph*10*(bar%2==0?1:-1);float i=floor(x);  // BARCODE
  val=step(frac(x),.2)*(ledHash(float3(i,bar,3))>.5?1:0)*act;col=fmod(abs(i),3)<1?accent:base;}
 else if(pat==10){float k=.35+SP*1.2,a=ph*TAU;                                    // PLASMA: world-space waves
  float v=sin(P.x*.5*k+a)+sin(P.z*.4*k-a*1.3)+sin(P.y*.6*k+a*.7)+sin(length(P.xz)*.5*k-a*2);
  float t=saturate(.5+.5*sin(v*1.6));val=lerp(.12,1,t*t)*act;col=lerp(base,accent,.5+.5*sin(v*1.1+a));}
 else if(pat==11){float cell=floor(u*64);float h=ledHash(float3(cell,bar,1));float t=frac(ph*3+h*7);  // SPARKLE
  float on=ledHash(float3(bar,cell*1.37,2))<.2+W*.6?1:0;float sp=exp(-t*16)*on;
  val=.05+sp*(.5+.5*act)*1.4;col=lerp(base,accent,saturate(sp*1.5));}
 else if(pat==12){float age=frac(s);float m=abs(uu-.5)*2;                          // HEARTBEAT: lub-dub from centre
  float bt=exp(-age/max(.03,W*.2))+.7*(age>.18?exp(-(age-.18)/max(.03,W*.2)):0);float reach=saturate(.25+age*5);
  val=bt*(1-smoothstep(reach-.15,reach,m))*act;col=lerp(accent,base,m);}
 else if(pat==13){float h=frac(s)*30-3;float w=.8+W*5;                            // CLIMB: a band rises through the rig
  val=(gauss(P.y-h,w)+.25*gauss(P.y-h+w*1.8,w*1.5))*act;col=lerp(base,accent,saturate(P.y/24));}
 else if(pat==14){val=gate*(lane>0?(l.y>.001?saturate(phChase(pr,l,rank,PH_BAR0+bar)*4):0):1);}   // STROBE
 else{float d=length(P-float3(0,15,0))/(20/(.5+SP));float age=frac(s);float w=.02+W*.12;  // RIPPLE from the capsid
  val=(gauss(d-age*1.3,w)+.55*gauss(d-(age-.18)*1.3,w*.8))*act;col=lerp(base,accent,saturate(gauss(d-(age-.18)*1.3,w*.8)*2));}
 return col*val;
}
