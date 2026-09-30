// BLINK_Previs / laser_scan.hlsli: one laser's radiance along a camera ray. This is the record
// loop of laser_lab LS_Air solve() (1563058e): aperture glow, analytic swept-sheet scattering,
// Gaussian dwell beams and the timed scan landing on the nearest surface. Included once per
// laser; define before including:
//   SCAN, SCAN_COUNT   World Scan buffer and its record count
//   FIX, FIX_COUNT     Fixtures buffer and its record count
//   TILES              that laser's tile candidate lists
//   LASER_FN           the function name to emit
// Changes from the source: the room is the site (sceneHit from site.hlsli); surface light is
// returned separately so the caller can weight it by the surface albedo; the surface visibility
// test runs once per fixture origin instead of once per record; the overlap-inspection switch
// is gone; attenuation uses `extinction` instead of `haze`, so a thin outdoor path over 40 m
// does not swallow the beams while `haze` still sets how much light the air scatters.
float3 LASER_FN(float3 ro,float3 rd,float2 uv,float2 extent,float surfaceT,float3 surfaceP,bool fixtureHit,out float3 surfaceLight){
 surfaceLight=0;
 float3 radiance=0;
 if(show_fixtures&&aperture_glow>0&&FIX_COUNT>1){
  uint fixtures=min((uint)FIX[0].aperture.w,min(FIX_COUNT-1,4));
  for(uint j=1;j<=fixtures;j++){
   float3 forward=FIX[j].forward.xyz;float facing=-dot(rd,forward);
   if(facing>.02){
    float t=dot(FIX[j].aperture.xyz-ro,forward)/dot(rd,forward);
    if(t>0&&t<=surfaceT+.001){
     float3 q=ro+rd*t-FIX[j].aperture.xyz;
     float radius=aperture_glow_mm*.001;
     float pixel=t*tan(radians(_CameraFOV*.5))*2/extent.y;
     float core=.0015,core2=core*core+pixel*pixel*.18,halo2=radius*radius+pixel*pixel*.18;
     float r2=dot(q,q);
     float glow=8*core*core/core2*exp(-r2/(2*core2))+.15*radius*radius/halo2*exp(-r2/(2*halo2));
     radiance+=FIX[j].emission.rgb*aperture_glow*glow*sqrt(facing)*exp(-extinction*t);
    }
   }
  }
 }
 if(SCAN_COUNT==0)return radiance;
 uint count=min((uint)SCAN[0].origin.x,min(SCAN_COUNT-1,4095));
 float cycle=max(SCAN[0].origin.y,1e-7);
 uint2 tileCoord=(uint2)(uv*extent)/16;
 uint2 tileDims=((uint2)extent+15)/16;
 uint base=(tileCoord.y*tileDims.x+tileCoord.x)*129;
 bool indexed=tile_culling&&all(tileDims<=256);
 uint candidateCount=min(indexed?TILES[base]:count,count);
 uint maskWord=0,bits=indexed?TILES[base+1]:0;
 float3 litFrom=float3(1e9,1e9,1e9);bool surfaceLit=false;
 [loop]for(uint candidate=0;candidate<candidateCount;candidate++){
  uint i=candidate+1;
  if(indexed){
   [loop]while(bits==0&&maskWord<127){maskWord++;bits=TILES[base+1+maskWord];}
   if(bits==0)break;
   i=maskWord*32+firstbitlow(bits);bits&=bits-1;
  }
  if(SCAN[i].timing.w>.5||SCAN[i].timing.y<=0)continue;
  float wt=scanWeight(SCAN[i].timing.x,SCAN[i].timing.y,cycle);if(wt<=0)continue;
  float3 origin=SCAN[i].origin.xyz,d0=SCAN[i].direction0.xyz,d1=SCAN[i].direction1.xyz;
  float range=SCAN[i].direction1.w,aperture=SCAN[i].origin.w,div=SCAN[i].direction0.w;
  float3 delta=d1-d0;float chord=length(delta);
  float4 c0=SCAN[i].color0,c1=SCAN[i].color1;
  float3 light=0;
  if(chord>1e-5){
   // Analytic intersection with the finite triangle swept out by a scan segment.
   float3 e0=d0*range,e1=d1*range,h=cross(rd,e1);float det=dot(e0,h);
   if(abs(det)>1e-8){
    float3 v=ro-origin;float a=dot(v,h)/det;float3 q=cross(v,e0);
    float b=dot(rd,q)/det;float t=dot(e1,q)/det;
    float sumAB=a+b,uRaw=b/max(sumAB,1e-8);
    float roughR=max(.08,range*sumAB);
    float footprint=t*tan(radians(_CameraFOV*.5))*2/extent.y;
    float roughWidth=aperture+div*roughR+footprint*.5;
    float margin=3*roughWidth/max(roughR*chord,1e-7);
    if(sumAB>0&&uRaw>=-margin&&uRaw<=1+margin&&t>0&&t<surfaceT){
     float3 wp=ro+rd*t;float r=length(wp-origin);float u=saturate(uRaw);
     float3 d=normalize(wp-origin);float3 normal=normalize(cross(d0,d1));
     float angle=abs(dot(rd,normal));
     float width=aperture+div*r;
     float filterWidth=sqrt(width*width+footprint*footprint*.2);
     float span=r*chord,along=uRaw*span;
     float coverage=max(0,.5*(lsErf((span-along)/(1.41421356*filterWidth))-lsErf(-along/(1.41421356*filterWidth))));
     float farFade=1-smoothstep(range-filterWidth*2,range+filterWidth*2,r);
     // Finite-support cap at grazing views; exact coplanar sheets are a known limit.
     float slab=min(1/max(angle,1e-5),range/max(width,1e-5));
     if(r>0.001&&farFade>0&&coverage>1e-6&&r<sceneHit(origin,d)+0.001){
      float4 rgb=lerp(c0,c1,u);
      float density=0;
      [loop]for(int hidx=0;hidx<FOG_SAMPLES;hidx++){
       float z=((hidx+.5)/FOG_SAMPLES-.5)*min(width*slab*3,2);
       density+=hazeAt(wp+rd*z,footprint/sqrt((float)PIXEL_SAMPLES));
      }
      density/=FOG_SAMPLES;
      light+=rgb.rgb*rgb.a*(wt/max(r*chord,1e-7))*coverage*farFade*slab*density*phaseHG(dot(d,-rd))*exp(-extinction*(r+t));
     }
    }
   }
  }else{
   // Gaussian beam integrated along the camera ray; handles real zero-length dwell.
   float3 v=ro-origin;float b=dot(rd,d0),den=max(1-b*b,1e-7);
   float t=(b*dot(v,d0)-dot(v,rd))/den;
   float r=dot(v,d0)+b*t;
   if(t>0&&t<surfaceT&&r>.001&&r<range&&r<sceneHit(origin,d0)){
    float width=aperture+div*r;
    float footprint=t*tan(radians(_CameraFOV*.5))*2/extent.y;
    float w=sqrt(width*width+footprint*footprint*.18);
    float3 separation=v+rd*t-d0*r;
    float gaussian=exp(-dot(separation,separation)/(2*w*w));
    if(gaussian>1e-6)light+=c0.rgb*c0.a*wt*gaussian/(2.5066283*w*sqrt(den))*hazeAt(origin+d0*r,footprint/sqrt((float)PIXEL_SAMPLES))*phaseHG(dot(d0,-rd))*exp(-extinction*(r+t));
   }
  }
  radiance+=light*gain;
  // The same timed scan illuminates the nearest surface.
  if(surfaceT<999&&!fixtureHit){
   float3 v=surfaceP-origin;float r=length(v);
   float3 d=v/max(r,1e-6);
   if(any(origin!=litFrom)){litFrom=origin;surfaceLit=r<=sceneHit(origin,d)+0.035;}
   if(!surfaceLit||r>=range)continue;
   float footprint=surfaceT*tan(radians(_CameraFOV*.5))*2/extent.y;
   float width=aperture+div*r,w=sqrt(width*width+footprint*footprint*.2);
   float kernel,u=0;
   if(chord>1e-5){
    // Exact for any segment length: across = distance to the swept plane, along = angle inside
    // it times r. Laser Lab measured against the straight chord between d0*r and d1*r, which
    // bows ~14 cm off a 27 m grid line at 37 m and hid everything but the segment joins.
    float3 n=normalize(cross(d0,d1));
    float across=dot(v,n);
    float3 inPlane=v-n*across;
    float theta=atan2(dot(cross(d0,inPlane),n),dot(d0,inPlane));
    float theta1=max(atan2(dot(cross(d0,d1),n),dot(d0,d1)),1e-6);
    float along=theta*r,L=theta1*r;
    u=saturate(theta/theta1);
    float cdf=.5*(lsErf((L-along)/(1.41421356*w))-lsErf(-along/(1.41421356*w)));
    kernel=max(0,cdf)*exp(-across*across/(2*w*w))/(2.5066283*w*L);
   }else{
    float separation=length(d-d0)*r;
    kernel=exp(-separation*separation/(2*w*w))/(6.2831853*w*w);
   }
   if(kernel>1e-7){
    float4 rgb=lerp(c0,c1,u);
    surfaceLight+=rgb.rgb*rgb.a*wt*kernel*exp(-extinction*r)*surface_gain*gain;
   }
  }
 }
 return radiance;
}
