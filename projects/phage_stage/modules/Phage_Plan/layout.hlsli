// One projection for drawing AND picking: plan (top view, audience down) on the left,
// a radial section through the selected leg on the right.
#define PL_HEAD 38.0
#define PL_FOOT 30.0
float4 planRect(){return float4(12,PL_HEAD,_Resolution.x*.52-6,_Resolution.y-PL_FOOT);}
float4 sectRect(){return float4(_Resolution.x*.52+6,PL_HEAD,_Resolution.x-12,_Resolution.y-PL_FOOT);}
float planScale(){float4 r=planRect();return min((r.z-r.x)/44.0,(r.w-r.y)/44.0);}
float2 planCenter(){float4 r=planRect();return (r.xy+r.zw)*.5+float2(0,-.02*(r.w-r.y));}
float2 planPx(float3 p){return planCenter()+float2(p.x,p.z)*planScale();}
// Section spans 12 m behind the axis (the opposite leg) to 20 m out along the selected leg, 0-24.5 m up.
float sectScale(){float4 r=sectRect();return min((r.z-r.x-16)/32.0,(r.w-r.y-60)/24.5);}
float2 sectOrigin(){float4 r=sectRect();float s=sectScale();float spare=max(0,(r.w-r.y-60)-24.5*s);return float2(r.x+8+12*s,r.w-16-spare*.5);}
float2 sectPx(float3 p,float az){return sectOrigin()+float2(dot(p,float3(sin(az),0,cos(az))),-p.y)*sectScale();}
bool inRect(float2 p,float4 r){return p.x>=r.x&&p.x<=r.z&&p.y>=r.y&&p.y<=r.w;}
float segDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-5)));}
uint mirrorLeg(uint i){return 5-i;}
