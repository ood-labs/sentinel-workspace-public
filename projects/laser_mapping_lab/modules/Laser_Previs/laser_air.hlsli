// BLINK_Previs / laser_air.hlsli: the atmosphere and scan-time helpers from sentinel-workspace
// projects/laser_lab LS_Air/air.hlsl (1563058e), unchanged. Needs FogClock declared first.
// Every loop count that comes from a parameter is clamped: a hot recompile can hand the shader a
// stale constant buffer, and an unclamped int read from a float's bits loops ~1e9 times and hangs
// the GPU (it BSOD'd the show machine on 2026-09-24).
#define PIXEL_SAMPLES clamp(pixel_samples,1,8)
#define FOG_SAMPLES clamp(fog_samples,1,8)
float lsHash(float3 p){p=frac(p*.1031);p+=dot(p,p.yzx+33.33);return frac((p.x+p.y)*p.z);}
float lsNoise(float3 p){
 float3 a=floor(p),f=frac(p);f=f*f*(3-2*f);
 return lerp(lerp(lerp(lsHash(a),lsHash(a+float3(1,0,0)),f.x),lerp(lsHash(a+float3(0,1,0)),lsHash(a+float3(1,1,0)),f.x),f.y),lerp(lerp(lsHash(a+float3(0,0,1)),lsHash(a+float3(1,0,1)),f.x),lerp(lsHash(a+float3(0,1,1)),lsHash(a+float3(1,1,1)),f.x),f.y),f.z);
}
float hazeAt(float3 p,float footprint){
 float drift=FogClock[0].x;
 float3 q=(p-float3(drift,drift*.13,drift*.31))*fog_scale;
 q.x/=fog_stretch;
 float3 warp=float3(lsNoise(q*.43+3.7),lsNoise(q*.43+19.1),lsNoise(q*.43-7.3))-.5;
 q+=warp*fog_warp*3;
 float frequencyNow=fog_scale;
 float n=lsNoise(q),sum=.5+(n-.5)*(1-smoothstep(.25,.9,footprint*frequencyNow)),norm=1,amp=fog_detail;
 [unroll]for(int octave=1;octave<5;octave++){
  q=q*2.17+float3(11.3,7.9,3.1);
  frequencyNow*=2.17;
  float band=1-smoothstep(.25,.9,footprint*frequencyNow);
  sum+=amp*(.5+(lsNoise(q)-.5)*band);norm+=amp;amp*=fog_roughness;
 }
 n=sum/norm;
 float wisps=pow(max(.005,n*2),fog_contrast);
 return haze*lerp(fog_floor,1,wisps);
}
float phaseHG(float c){float g=anisotropy;return (1-g*g)/(12.5663706*pow(max(0.01,1+g*g-2*g*c),1.5));}
float lsErf(float x){float s=x<0?-1:1;float a=abs(x),t=1/(1+.3275911*a);return s*(1-(((((1.061405429*t-1.453152027)*t)+1.421413741)*t-.284496736)*t+.254829592)*t*exp(-a*a));}
float integralTime(float t,float start,float dur,float cycle){
 float k=floor(t/cycle);return k*dur+clamp(t-k*cycle-start,0,dur);
}
float scanWeight(float start,float dur,float cycle){
 if(shutter_mode==0)return dur/cycle;
 float e=exposure_ms*.001;float end=shutter_phase*cycle;
 return max(0,(integralTime(end,start,dur,cycle)-integralTime(end-e,start,dur,cycle))/e);
}
