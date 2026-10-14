// Pixel-bar LOOK patterns 0-15. u runs 0..1 along the whole run (bottom to top of a wall run), P is the pixel's world
// position, rank the bar's place in the programmed ORDER.
// Knobs: lane phase/active, WIDTH, SPREAD, OFFSET, DIRECTION; base/accent = COLOUR / COLOUR 2.
// The wall is symmetric about the stage's centre line and so is its content: the per-run patterns ripple by ORDER
// (OUT runs them from the middle to both edges at once), and the patterns with randomness (RAIN, EQ, SPARKLE) seed
// it per mirrored pair of runs, so the left half is always the right half's reflection.
#define TAU 6.2831853
// The wall's scale (ss_stage.hlsli SS_WALL): CLIMB runs from the runs' feet to their tops, RIPPLE spreads from the
// middle of the wall and reaches its edges in one lane cycle.
#define CLIMB_Y0 SS_WALL.x
#define CLIMB_Y1 SS_WALL.y
#define RIPPLE_ORIGIN float3(0,(SS_WALL.x+SS_WALL.y)*.5,SS_WALL.z)
#define RIPPLE_REACH (SS_WALL.w*1.15)
float ledHash(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
float gauss(float x,float w){return exp(-x*x/max(1e-5,w*w));}
float wrap01(float x){return x-floor(x+.5);}
float3 ledPattern(uint pat,uint bar,float u,float4 l,uint lane,SsProgram pr,float rank,float3 base,float3 accent,float3 P,float beat,float gate,float rate){
 float W=pr.timing.x,SP=pr.movement.w;float uu=pr.timing.z>.5?1-u:u;
 float ph=l.x+pr.timing.y,act=lane>0?l.y:1,s=ph-rank*SP;float val=0;float3 col=base;
 if(pat==0){val=lane>0?ssChase(pr,l,rank,SS_BAR0+bar):1;}                       // SOLID
 else if(pat==1){float h=frac(s)*1.3-.15;float w=.03+W*.3;                         // CHASE: a pulse runs the bar
  val=gauss(uu-h,w)*act;col=lerp(base,accent,gauss(uu-h,w*.35));}
 else if(pat==2){val=(.5+.5*cos(s*TAU))*act;}                                     // PULSE: breathe
 else if(pat==3){float n=floor(2+W*10);float k=floor(frac(s)*n);                  // SEGMENTS: step along
  val=(floor(uu*n)==k?1:0)*act;col=fmod(k,2)<1?base:accent;}
 else if(pat==4){float mp=floor(abs(P.x)*2+.5);float tail=.05+W*.35;              // RAIN: three drops fall down
  [unroll]for(int k=0;k<3;k++){float h=1.12-frac(ph*(1+k)+ledHash(float3(mp,k,7))+rank*SP)*1.3;float x=uu-h;  // each run
   val+=(x>0?exp(-x/(tail*(1+.6*k))):exp(-x*x/.0002))*(1-.22*k);}
  val*=act;col=lerp(base,accent,saturate(val*1.5-.9));}
 else if(pat==5){float h=frac(s);float d=frac(h-uu);                              // COMET: head + tail
  val=(exp(-d/max(.02,W*.35))+exp(-d*120)*.8)*act;col=lerp(base,accent,exp(-d*45));}
 else if(pat==6){float a=frac(s)*.5;float w=.02+W*.08;                            // TWIN: meet in the middle
  float meet=smoothstep(.42,.5,a);val=(gauss(uu-a,w)+gauss(uu-(1-a),w)+meet*1.2*gauss(uu-.5,.08+meet*.3))*act;
  col=lerp(base,accent,meet);}
 else if(pat==7){float yn=saturate((P.y-CLIMB_Y0)/max(.1,CLIMB_Y1-CLIMB_Y0));       // CHEVRON: arrows across the
  float d=(pr.timing.z>.5?1-yn:yn)+saturate(abs(P.x)/max(.1,SS_WALL.w))*(.1+SP*1.1);  // whole wall, up (DIRECTION:
  float x=(d-ph)*2;float f=frac(x),w=.1+W*.55;                                          // down), SPREAD the angle
  val=smoothstep(0,.05,f)*(1-smoothstep(w,w+.05,f))*act;col=fmod(floor(x)+16,2)<1?base:accent;}
 else if(pat==8){float w=.015+W*.08;[unroll]for(int g=0;g<3;g++){float p=.5-.5*cos(TAU*(s-g*.035));val+=gauss(uu-p,w)*(g==0?1:.35/g);}
  val*=act;col=lerp(base,accent,saturate(val-.8));}                                  // SCANNER: ping-pong + ghosts
 else if(pat==9){float age=frac(ph);float r=ledHash(float3(round(rank*32),fmod(l.z,997),5));  // EQ: each run a
  float h0=(.3+.7*r)*(1-SP*.75*saturate(rank));                                        // level bar that jumps on
  float h=h0*saturate(age*30)*pow(saturate(1-age),.5+W*2.5);float pk=h0*(1-saturate(age-.3)*.85);  // the lane, falls
  val=((uu<h?.55+.45*uu/max(h,.05):0)*step(frac(uu*20),.8)+gauss(uu-pk,.012)*1.3)*act;  // and leaves its peak
  col=lerp(base,accent,saturate(uu*1.15));}
 else if(pat==10){float k=.35+SP*1.2,a=ph*TAU,ax=abs(P.x);                         // PLASMA: mirrored waves
  float v=sin(ax*.5*k+a)+sin(P.z*.4*k-a*1.3)+sin(P.y*.6*k+a*.7)+sin(length(float2(ax,P.y-RIPPLE_ORIGIN.y))*.5*k-a*2);
  float t=saturate(.5+.5*sin(v*1.6));val=lerp(.12,1,t*t)*act;col=lerp(base,accent,.5+.5*sin(v*1.1+a));}
 else if(pat==11){float mp=floor(abs(P.x)*2+.5);float cell=floor(u*64);float h=ledHash(float3(cell,mp,1));  // SPARKLE
  float t=frac(ph*3+h*7);float on=ledHash(float3(mp,cell*1.37,2))<.2+W*.6?1:0;float sp=exp(-t*16)*on;
  val=.05+sp*(.5+.5*act)*1.4;col=lerp(base,accent,saturate(sp*1.5));}
 else if(pat==12){float age=frac(s);float m=abs(uu-.5)*2;                          // HEARTBEAT: lub-dub from centre
  float bt=exp(-age/max(.03,W*.2))+.7*(age>.18?exp(-(age-.18)/max(.03,W*.2)):0);float reach=saturate(.25+age*5);
  val=(.1+bt*(1-smoothstep(reach-.15,reach,m)))*act;col=lerp(accent,base,m);}   // over a 10% glow
 else if(pat==13){float w=.2+W*.9;float h=lerp(CLIMB_Y0-w,CLIMB_Y1+w,frac(s));      // CLIMB: a band rises up the wall
  val=(gauss(P.y-h,w)+.25*gauss(P.y-h+w*1.8,w*1.5))*act;col=lerp(base,accent,saturate((P.y-CLIMB_Y0)/(CLIMB_Y1-CLIMB_Y0)));}
 else if(pat==14){val=gate*(lane>0?(l.y>.001?saturate(ssChase(pr,l,rank,SS_BAR0+bar)*4):0):1);}   // STROBE
 else{float d=length(P-RIPPLE_ORIGIN)/(RIPPLE_REACH/(.5+SP));float age=frac(s);float w=.02+W*.12;  // RIPPLE from the deck
  val=(gauss(d-age*1.3,w)+.55*gauss(d-(age-.18)*1.3,w*.8))*act;col=lerp(base,accent,saturate(gauss(d-(age-.18)*1.3,w*.8)*2));}
 return col*val;
}
