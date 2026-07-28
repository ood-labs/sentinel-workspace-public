#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

struct LightRecord {
    float3 position; float type_id;
    float3 direction; float range;
    float3 color; float intensity;
    float2 size; float softness; float enabled;
};
StructuredBuffer<LightRecord> Lights : register(t0);

float box2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float segment2(float2 p, float2 a, float2 b) {
    float2 pa = p-a, ba = b-a;
    return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),1e-5)));
}
float2 rotate2(float2 p, float a) {
    float s=sin(a), c=cos(a); return float2(c*p.x-s*p.y,s*p.x+c*p.y);
}
float pnodeEdge(float2 world,float2 center,float yaw,float width,float depth,float wpp) {
    float d=box2(rotate2(world-center,-yaw),max(float2(width,depth)*0.5,0.025));
    return 1.0-smoothstep(wpp*0.55,wpp*1.45,abs(d));
}
float4 pxRect(float4 r,float2 R){return r*float4(R,R);}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID) {
    if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;
    float2 R=_Resolution.xy;
    float2 P=(float2)tid.xy+0.5;
    float2 uv=P/R;
    float k=min(R.x/1280.0,R.y/720.0);
    float sB=k>=2.6?3.0:k>=1.7?2.0:1.0;
    float sN=2.0*sB, sT=3.0*sB;
    float pad=max(10.0,0.025*R.x);
    Sui3Theme T=sui3Theme(SUI3_AMBER);
    float3 col=T.field;

    float4 header=float4(pad,pad,R.x-pad,max(54.0*sB,0.145*R.y));
    float4 plan=float4(pad,0.18*R.y,0.642*R.x,R.y-pad);
    float4 desk=float4(0.665*R.x,0.18*R.y,R.x-pad,R.y-pad);
    col+=sui3Well(P,header,T)+sui3Well(P,plan,T)+sui3Well(P,desk,T);
    col+=T.accent*sui3HairAt(P.x,header.x+3.0*sB)
        *sui3RectIn(P,float4(header.x,header.y,header.x+7.0*sB,header.w));

    float2 planSize=max(plan.zw-plan.xy,1.0);
    float2 planCenter=(plan.xy+plan.zw)*0.5;
    float ppw=max(min(planSize.x/10.4,planSize.y/8.4),1.0);
    float2 world=(P-planCenter)/ppw;
    float wpp=1.0/ppw;
    float mask=sui3RectIn(P,plan);
    float2 grid=abs(frac(world+0.5)-0.5);
    col+=T.rule*0.28*mask*(1.0-smoothstep(wpp*0.55,wpp*1.35,min(grid.x,grid.y)));
    col+=T.mid*0.35*mask*((1.0-smoothstep(wpp*0.55,wpp*1.35,abs(world.x)))+
                         (1.0-smoothstep(wpp*0.55,wpp*1.35,abs(world.y))));

    [loop]for(uint i=0u;i<min(_Data0_Count,13u);++i){
        float e=pnodeEdge(world,float2(_Data0[i].position[0],_Data0[i].position[2]),
                          _Data0[i].yaw,_Data0[i].width,_Data0[i].depth,wpp);
        col+=mask*T.ink*e*0.58;
    }
    [loop]for(uint j=0u;j<min(_Data1_Count,23u);++j){
        float e=pnodeEdge(world,float2(_Data1[j].position[0],_Data1[j].position[2]),
                          _Data1[j].yaw,_Data1[j].width,_Data1[j].depth,wpp);
        col+=mask*T.mid*e*0.58;
    }
    [loop]for(uint q=0u;q<6u;++q){
        LightRecord L=Lights[q]; if(L.enabled<0.5)continue;
        float2 center=L.position.xz;
        float practical=step(0.5,L.type_id)*(1.0-step(2.0,L.type_id));
        float radius=lerp(1.10,0.34,practical);
        float d=length(world-center);
        float ring=1.0-smoothstep(wpp*0.55,wpp*1.55,abs(d-radius));
        float core=1.0-smoothstep(wpp*1.0,wpp*3.2,d);
        float3 tone=practical>0.5?T.accent:T.ink;
        col+=mask*tone*(ring*0.78+core)*saturate(0.35+L.intensity*0.22);
        float2 dir=normalize(L.direction.xz+1e-4);
        float ray=1.0-smoothstep(wpp*0.55,wpp*1.55,segment2(world,center,center+dir*0.62));
        col+=mask*T.mid*ray*(1.0-practical)*0.60;
    }

    if(R.x>=700.0) {
        col+=T.ink*sui3TextLong(P,float2(header.x+14.0*sB,header.y+10.0*sB),sT,
            S_L,S_I,S_G,S_H,S_T,S_I,S_N,S_G,S_SP,S_D,S_E,S_S,S_K,0,0,0,0,0,0,0,0,0,0,0);
        col+=T.dim*sui3TextLong(P,float2(header.x+14.0*sB,header.y+40.0*sB),sB,
            54,S_SP,S_L,S_I,S_V,S_E,S_SP,S_L,S_I,S_G,S_H,S_T,S_SP,S_R,S_E,S_C,S_O,S_R,S_D,S_S,0,0,0,0);
    } else {
        col+=T.ink*sui3Text(P,float2(header.x+9.0,header.y+9.0),sT,
            S_L,S_I,S_G,S_H,S_T,S_S,0,0,0,0,0,0);
    }

    float values[4]={
        saturate(daylight_intensity/3.0),saturate(practical_intensity/4.0),
        saturate(ambient_fill/1.5),saturate((shadow_softness-0.02)/0.98)
    };
    float4 rects[4]={
        pxRect(UI_RECT_DAYLIGHT,R),pxRect(UI_RECT_PRACTICAL,R),
        pxRect(UI_RECT_AMBIENT,R),pxRect(UI_RECT_SOFTNESS,R)
    };
    [unroll]for(uint c=0u;c<4u;++c)col+=sui3Rail(P,rects[c],values[c],T);
    float labelX=desk.x+0.09*(desk.z-desk.x);
    float numberX=desk.z-0.07*(desk.z-desk.x);
    float labelY0=0.280*R.y, stepY=0.140*R.y;
    if(R.x>=700.0){
        col+=T.dim*sui3Text(P,float2(labelX,labelY0),sB,S_W,S_I,S_N,S_D,S_O,S_W,S_SP,S_D,S_A,S_Y,0,0);
        col+=T.dim*sui3Text(P,float2(labelX,labelY0+stepY),sB,S_P,S_R,S_A,S_C,S_T,S_I,S_C,S_A,S_L,0,0,0);
        col+=T.dim*sui3Text(P,float2(labelX,labelY0+2.0*stepY),sB,S_A,S_M,S_B,S_I,S_E,S_N,S_T,0,0,0,0,0);
        col+=T.dim*sui3Text(P,float2(labelX,labelY0+3.0*stepY),sB,S_S,S_O,S_F,S_T,S_N,S_E,S_S,S_S,0,0,0,0);
    }
    [unroll]for(uint n=0u;n<4u;++n)
        col+=T.ink*sui3DigitsRight(P,numberX,labelY0+n*stepY,sN,(int)round(values[n]*100.0),3);

    col+=T.dim*sui3Text(P,float2(desk.x+10.0*sB,desk.w-29.0*sB),sB,
        S_D,S_A,S_Y,S_SP,S_SL,S_SP,S_L,S_A,S_M,S_P,S_S,0);
    OutputUAV[tid.xy]=float4(saturate(col),1.0);
}
