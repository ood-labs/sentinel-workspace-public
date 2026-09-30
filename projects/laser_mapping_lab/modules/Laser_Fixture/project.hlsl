struct Beam { float4 origin; float4 direction0; float4 direction1; float4 color0; float4 color1; float4 timing; float4 meta; };
#include "pose.hlsli"
RWStructuredBuffer<Beam> OutputBuffer:register(u0);
#include "curve.hlsli"
StructuredBuffer<uint4> CurveMap:register(t1);
float3 directionFor(float2 xy,uint projector,float lane) {
 // BLINK Calibrated to Wall: what the show looks like once each laser is mapped to the wall
 // on site (Sentinel laser mapping / MadLaser against the CAL grid). Scan (x, y) lands on the
 // same template-frame point the projector puts pixel (x, y) on: x = scan.x * 13.745 m,
 // y = 12.985 + scan.y * 8.015 m on the wall plane. Raw optics below keystones and skews.
 if(calibrated){float3 w=float3(xy.x*13.745,12.985+xy.y*8.015,0);return normalize(w-apertureFor(projector));}
 // Laser Out's output orientation, as a real DAC would receive it (ILDA: +y is up).
 // A Sent Stream already carries Laser Out's flips.
 if(flip_x&&!input_is_sent_stream)xy.x=-xy.x;
 if(flip_y&&!input_is_sent_stream)xy.y=-xy.y;
 // The real device path: tested lasers draw X mirrored with no flips (sentinel-bugs#147).
 if(device_mirrors_x)xy.x=-xy.x;
 // BLINK: the site frame is right-handed (BLINK_Previs mirrors z on entry), Laser Lab's is
 // Sentinel's left-handed one. Without this, scan +x landed on the audience's left of the wall.
 xy.x=-xy.x;
 if(mirror_alternate&&(projector%2==1))xy.x=-xy.x;
 float showRoll=show_enabled?((show_cue==2||show_cue==3)?projector*35:15*sin(show_beat*.392699+projector*1.57)):0;
 float roll=radians(rotation+projector*rotation_step+showRoll);float2 q=float2(cos(roll)*xy.x-sin(roll)*xy.y,sin(roll)*xy.x+cos(roll)*xy.y);
 q+=float2(offset_x,offset_y);q.x*=1+keystone*q.y;
 float3 d;
 if(scanner_model==0)d=normalize(float3(q.x*tan(radians(scan_x*0.5)),q.y*tan(radians(scan_y*0.5)),1));
 else{
  // A real XY galvo scanner. The drive signal sets each mirror's ANGLE (through an amplifier
  // that is never quite linear, with gains that never quite match, around a zero that is never
  // quite the optical centre, on mirror axes that are never quite square). The beam leaves the
  // X mirror at angle ax, then the Y mirror turns it by ay: direction (sin ax, cos ax sin ay,
  // cos ax cos ay). On a flat wall that is x = D tan(ax) / cos(ay), y = D tan(ay): spacing
  // widens toward the edges (angle, not tan) and vertical lines bow out at top and bottom (the
  // 1 / cos(ay)). These are exactly what Mapping Editor's Spacing, Bow and Centre correct.
  float2 a=q+float2(zero_x,zero_y);
  a.y*=gain_y;
  a+=nonlinearity*a*a*a;
  a=float2(a.x*(1+pincushion_x*a.y*a.y),a.y*(1+pincushion_y*a.x*a.x));
  a.x+=tan(radians(skew_deg))*a.y;
  float ax=a.x*radians(scan_x*0.5),ay=a.y*radians(scan_y*0.5);
  d=float3(sin(ax),cos(ax)*sin(ay),cos(ax)*cos(ay));
 }
 return orientFixture(d,projector);
}
// A Sent Stream is the sample stream the DAC is sent: mostly zero-length records, each a sample
// point held for a sample or two, stepping along the path. The galvos smooth those steps into a
// line, so the beam's path runs through each record's START point to the next record's start (the
// last wraps to the first). Drawing the records one by one instead makes every sample a dot.
// Only a step the mirrors could physically make joins two samples: at most ~1.5 x Max Step per
// sample over the record's duration. A farther "step" is a break in the data (Laser Out handing
// over to the next animation frame), and drawing it lit put lines across the picture.
float2 sampleNext(uint j,uint count){
 float2 next=Stream[j<count?j+1:1].endpoints.xy;
 float reach=max(0.02,Stream[j].timing.y*max(Stream[0].endpoints.z,1)*sample_max_step*1.5);
 // Measured from where this record ENDS: a long lit edge must not "reach" a far sample.
 return distance(next,Stream[j].endpoints.zw)<=reach?next:Stream[j].endpoints.zw;
}
// Where the stream had the beam at time T (seconds into the cycle, wrapping). Records are laid end
// to end in time, so a binary search on their start times finds the active one.
float2 pathAt(float T,uint count){
 float cycle=max(Stream[0].endpoints.y,1e-6);
 T=T-floor(T/cycle)*cycle;
 uint lo=1,hi=count;
 [loop]for(uint k=0;k<11&&lo<hi;k++){uint mid=(lo+hi+1)/2;if(Stream[mid].timing.x<=T)lo=mid;else hi=mid-1;}
 float4 r=Stream[lo].endpoints;float4 tm=Stream[lo].timing;
 return lerp(r.xy,sampleNext(lo,count),saturate((T-tm.x)/max(tm.y,1e-9)));
}
// The stream's colour at time T (seconds into the cycle, wrapping): black while blanked.
float4 colourAt(float T,uint count){
 float cycle=max(Stream[0].endpoints.y,1e-6);
 T=T-floor(T/cycle)*cycle;
 uint lo=1,hi=count;
 [loop]for(uint k=0;k<11&&lo<hi;k++){uint mid=(lo+hi+1)/2;if(Stream[mid].timing.x<=T)lo=mid;else hi=mid-1;}
 if(Stream[lo].timing.w>.5)return float4(0,0,0,1);
 return lerp(Stream[lo].color0,Stream[lo].color1,saturate((T-Stream[lo].timing.x)/max(Stream[lo].timing.y,1e-9)));
}
[numthreads(64,1,1)]
void main(uint3 id:SV_DispatchThreadID) {
 uint i=id.x;if(i>=4096)return;
 Beam b=(Beam)0;
 if(StreamCount()>0){
  uint sourceCount=min((uint)Stream[0].endpoints.x,min(StreamCount()-1,1023));
  uint bankCount=clamp(projector_count,1,4);
  uint perProjector=CurveMap[0].x;
  if(i==0){b.origin=Stream[0].endpoints;b.origin.x=perProjector*bankCount;b.meta=Stream[0].meta;b.meta.w=bankCount;}
  else if(sourceCount>0&&i<=perProjector*bankCount){
   uint projector=(i-1)/perProjector,local=(i-1)%perProjector;
   uint4 map=CurveMap[local+1];uint j=map.x,sub=map.y,steps=map.z,jEnd=max(map.w,map.x);
   float t0=float(sub)/steps,t1=float(sub+1)/steps;
   float lane=float(projector)-float(bankCount-1)*0.5;
   b.origin=float4(apertureFor(projector),diameter_mm*0.0005);
   // A Sent Stream is what the DAC is told; the mirrors reach it Galvo Lag later, while colour is on
   // time. So the beam piece that carries this record's colour sits where the path was lag ago.
   float2 c0=curvePoint(j,sourceCount,t0),c1=curvePoint(j,sourceCount,t1);
   // A merged run of samples j..jEnd: from j's sample point to the one after jEnd.
   if(input_is_sent_stream){c0=Stream[j].endpoints.xy;c1=sampleNext(jEnd,sourceCount);}
   b.direction0=float4(directionFor(c0,projector,lane),divergence_mrad*0.001);
   b.direction1=float4(directionFor(c1,projector,lane),throw_distance);
   b.color0=lerp(Stream[j].color0,Stream[j].color1,t0);b.color1=lerp(Stream[jEnd].color0,Stream[jEnd].color1,t1);
   // Galvo lag, from the colour's side: the mirrors trail the command, which is the same as the
   // colour leading the path. The beam stays on the stream's own samples (a merged piece keeps its
   // true corners) and takes the colour the stream has Galvo Lag later. Moving the geometry back
   // instead cut the corners of merged pieces.
   if(input_is_sent_stream&&galvo_lag_ms>0){
    float lag=galvo_lag_ms*1e-3,ts=Stream[j].timing.x+t0*Stream[j].timing.y,te=Stream[jEnd].timing.x+t1*Stream[jEnd].timing.y;
    b.color0=colourAt(ts+lag,sourceCount);b.color1=colourAt(te+lag,sourceCount);
   }
   b.color0.rgb*=power*fixtureGate(projector);b.color1.rgb*=power*fixtureGate(projector);
   b.timing=Stream[j].timing;b.meta=Stream[j].meta;b.meta.w=projector+1;
   if(input_is_sent_stream)b.timing.y=Stream[jEnd].timing.x+Stream[jEnd].timing.y-Stream[j].timing.x;
   b.timing.x+=t0*b.timing.y;b.timing.y/=steps;
   b.meta.xy=lerp(Stream[j].meta.xx,Stream[j].meta.yy,float2(t0,t1));
  }
 }
 OutputBuffer[i]=b;
}
