// Compiles the editor's one working mapping (bank 0). Mappings are kept as node presets.
#include "quad.hlsli"
StructuredBuffer<float4> P:register(t1);
RWStructuredBuffer<float4> O:register(u0);
StructuredBuffer<float4> M:register(t2);
#include "masks.hlsli"
float2 cp(int b,int i){return (P[b*52+i].xy-.1)/.8;}
float2 evalMap(int b,float3x3 m,float2 uv){
 float2 z=saturate(uv)*4;int2 k=min((int2)floor(z),3);float2 t=z-k;float4 wx=weights(t.x),wy=weights(t.y);float2 d=0;
 [unroll]for(int y=0;y<4;y++)[unroll]for(int x=0;x<4;x++){int2 q=clamp(k+int2(x-1,y-1),0,4);d+=(cp(b,q.y*5+q.x)-applyQuad(m,float2(q)/4))*wx[x]*wy[y];}
 return applyQuad(m,uv)+d;
}
// tan's argument is clamped under pi/2 so a strong negative Spacing can't reach the pole at the field edge.
float spacingAxis(float v,float s){return abs(s)<1e-4?v:(s>0?atan(v*s)/s:tan(clamp(v*-s,-1.45,1.45))/-s);}
// c = the laser's straight-on point in the field, the centre the distortion is measured from.
float2 scannerShape(float2 q,float4 k,float2 c){q-=c;q=float2(spacingAxis(q.x,k.z),spacingAxis(q.y,k.w));return float2(q.x*(1-k.x*q.y*q.y),q.y*(1-k.y*q.x*q.x))+c;}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 int b=0;
 float3x3 m=quadMatrix(cp(b,0),cp(b,4),cp(b,24),cp(b,20));
 bool valid=convex(P[b*52].xy,P[b*52+4].xy,P[b*52+24].xy,P[b*52+20].xy);
 [loop]for(int y=0;y<=8;y++)[loop]for(int x=0;x<=8;x++){float2 uv=float2(x,y)/8,q=evalMap(b,m,uv);float2 dx=evalMap(b,m,uv+float2(.001,0))-q,dy=evalMap(b,m,uv+float2(0,.001))-q;valid=valid&&all(isfinite(q))&&cross2(dx,dy)>=1e-9;}
 float ext=extent_a;
 O[0]=float4(valid?1:0,ext,1,b);
 O[1]=float4(m[0],0);O[2]=float4(m[1],0);O[3]=float4(m[2],0);
 [unroll]for(int i=0;i<25;i++)O[4+i]=float4(cp(b,i)-applyQuad(m,float2(i%5,i/5)/4),0,0);
 // Scanner correction: it comes from the laser, not from the surface.
 // Centre is authored in scanner space (+y up); the calibration is mapping space (+y down).
 float4 k=float4(pincushion_x,pincushion_y,spacing_x,spacing_y);float2 ctr=float2(centre_x,-centre_y);float2 c[4];
 [unroll]for(int j=0;j<4;j++){float2 q=(evalMap(b,m,float2(j&1,j>>1))*2-1)*ext;c[j]=scannerShape(q,k,ctr)-q;}
 O[4]=float4(cp(b,0)-applyQuad(m,float2(0,0)),ctr);O[29]=k;O[30]=float4(c[0],c[1]);O[31]=float4(c[2],c[3]);
 // Zoning masks: 32 = (count, cookie, margin, only-in count), 33..64 = the enabled masks,
 // compacted, margin applied, in scanner units (+y down): (kind, mode, 1, angle) and the rect, or
 // (point count, 0, 0, 0) for a polygon whose points follow at CAL_POLY_BASE + 32 * slot.
 // Adaptive Mapping refuses a Calibration without this block, so a missing or unreadable mask set
 // blanks the laser instead of passing content through unmasked.
 uint n=maskCount(),used=0,allow=0;float mg=max(mask_margin,0);bool finite=M[0].y==MASK_COOKIE&&isfinite(mask_margin);
 [loop]for(uint z=CAL_MASK_BASE+1;z<CAL_POLY_BASE+POLY_MAX*MASK_MAX;z++)O[z]=0;
 [loop]for(uint j=0;j<n;j++){
  float4 info=maskInfo(j),r=maskRect(j);finite=finite&&all(isfinite(info))&&all(isfinite(r));
  if(info.z<.5)continue;
  if(info.x>1.5){
   uint np=polyCount(j);if(np<3)continue;
   // Mitred offset: outward for Block (grows), inward for Only-In (shrinks). The mitre of the
   // two offset edges contains the round offset at every corner, so a Block polygon's margin is
   // never thinner than Mask Margin. Needle-sharp spikes are capped at half a field unit.
   float area=0;[loop]for(uint i=0;i<np;i++){float2 a=polyPoint(j,i),b=polyPoint(j,(i+1)%np);area+=a.x*b.y-b.x*a.y;}
   float g=(info.y<.5?mg:-mg)*(area>=0?1:-1);
   [loop]for(uint i=0;i<np;i++){
    float2 p0=polyPoint(j,(i+np-1)%np),p1=polyPoint(j,i),p2=polyPoint(j,(i+1)%np);
    float2 e1=normalize(p1-p0+1e-12),e2=normalize(p2-p1+1e-12);
    float2 n1=float2(e1.y,-e1.x),n2=float2(e2.y,-e2.x);
    float2 off=g*(n1+n2)/max(1+dot(n1,n2),1e-3);if(length(off)>.5)off*=.5/length(off);
    O[CAL_POLY_BASE+POLY_MAX*used+i]=float4(p1+off,0,0);finite=finite&&all(isfinite(p1));
   }
   O[CAL_MASK_BASE+1+2*used]=float4(2,info.y,1,0);O[CAL_MASK_BASE+2+2*used]=float4(np,0,0,0);
  }else{
   O[CAL_MASK_BASE+1+2*used]=float4(info.x,info.y,1,info.w);O[CAL_MASK_BASE+2+2*used]=effectiveRect(info,r,mg);
  }
  allow+=info.y>.5?1:0;used++;
 }
 O[CAL_MASK_BASE]=float4(used,CAL_MASK_COOKIE,mask_margin,allow);
 if(!finite)O[0].x=0;
}
