float klangPulse(float phase,float rank,float width,float spread){float age=frac(phase-saturate(rank)*spread);return smoothstep(0,.025,age)*(1-smoothstep(.08,width,age));}
float klangRank(float z,float a,float b,float reverse){float r=saturate((z-min(a,b))/max(.001,abs(b-a)));return reverse>.5?1-r:r;}
// Deterministic noise for programmed FX (seeded by fixture, lane trigger count, repeat index).
float klangHash(float3 p){return frac(sin(dot(p,float3(12.9898,78.233,37.719)))*43758.5453);}
// Mover FX mode rides the movers' otherwise-unused led_pattern value: 16 + bits.
// bits 0-1 chase repeats x1/x2/x4/x8 per lane pulse; bit 2 random gate (~1/3 lit per flash, reshuffled per hit);
// bit 3 jump (each move-lane trigger picks a new random pan/tilt within +-amp; motors slew between);
// bit 4 step (each trigger moves to the next of five fixed points, holding still between; OFFSET shifts
// the start point in fifths, DIRECTION reverses the order). Step wins over jump.
uint klangMoverFx(float code){return code>=15.5?(uint)(code-16):0;}
float2 klangStepPoint(float trigger,float offset,float reverse){
    const float2 P[5]={float2(0,0),float2(1,.35),float2(-1,.35),float2(.55,-1),float2(-.55,-1)};
    int n=(int)fmod(trigger,1000)+(int)round(offset*5);if(reverse>.5)n=-n;return P[((n%5)+5)%5];}
