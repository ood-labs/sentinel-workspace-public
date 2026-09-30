float cross2(float2 a,float2 b){return a.x*b.y-a.y*b.x;}
float3x3 quadMatrix(float2 a,float2 b,float2 c,float2 d){
 float2 delta=a-b+c-d,dx=b-c,dy=d-c;float det=cross2(dx,dy);
 float2 g=abs(det)>1e-7?float2(cross2(delta,dy),cross2(dx,delta))/det:0;
 float2 bx=b-a+g.x*b,by=d-a+g.y*d;
 return float3x3(bx.x,by.x,a.x,bx.y,by.y,a.y,g.x,g.y,1);
}
float3x3 inv3(float3x3 m){
 float3 a=cross(m[1],m[2]),b=cross(m[2],m[0]),c=cross(m[0],m[1]);
 float det=dot(m[0],a);return transpose(float3x3(a,b,c))/max(abs(det),1e-9)*(det<0?-1:1);
}
float2 applyQuad(float3x3 m,float2 uv){float3 p=mul(m,float3(uv,1));return p.xy/(abs(p.z)>1e-6?p.z:1e-6);}
bool convex(float2 a,float2 b,float2 c,float2 d){return cross2(b-a,c-b)>.001&&cross2(c-b,d-c)>.001&&cross2(d-c,a-d)>.001&&cross2(a-d,b-a)>.001;}
float4 weights(float t){float t2=t*t,t3=t2*t;return float4(-.5*t+t2-.5*t3,1-2.5*t2+1.5*t3,.5*t+2*t2-1.5*t3,-.5*t2+.5*t3);}
