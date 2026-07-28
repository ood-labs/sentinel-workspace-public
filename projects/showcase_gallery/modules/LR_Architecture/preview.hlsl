#include "types.hlsli"
#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

StructuredBuffer<PNode> PreviewNodes:register(t0);
StructuredBuffer<ArchitectureEditorState> EditorStateBuffer:register(t1);
RWTexture2D<float4> OutputUAV:register(u0);

float2 rotate2(float2 p,float a){float s=sin(a),c=cos(a);return float2(c*p.x-s*p.y,s*p.x+c*p.y);}
float box2(float2 p,float2 b){float2 q=abs(p)-b;return length(max(q,0.0))+min(max(q.x,q.y),0.0);}
float segment2(float2 p,float2 a,float2 b){float2 pa=p-a,ba=b-a;return length(pa-ba*saturate(dot(pa,ba)/max(dot(ba,ba),1e-5)));}
float3 kindTone(float k,Sui3Theme T){
    if(k<3.5)return T.ink;
    if(k<5.5)return T.accent;
    if(k<14.0)return T.mid;
    return lerp(T.mid,T.ink,saturate((k-14.0)/6.0));
}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){
    if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;
    float2 R=_Resolution.xy,P=(float2)tid.xy+0.5,uv=P/R;
    float k=min(R.x/1280.0,R.y/720.0);
    float sB=k>=2.6?3.0:k>=1.7?2.0:1.0,sN=2.0*sB,sT=3.0*sB;
    float pad=max(10.0,0.022*R.x);
    Sui3Theme T=sui3Theme(SUI3_AMBER);
    ArchitectureEditorState editor=EditorStateBuffer[0];
    float3 col=T.field;
    float toolbar=ARCH_PLAN_TOP*R.y;
    col+=T.well*sui3RectIn(P,float4(0,0,R.x,toolbar));
    col+=T.rule*sui3HairAt(P.y,toolbar);

    if(uv.y>=ARCH_PLAN_TOP){
        float2 world=archPlanWorld(uv,editor.view_pan,editor.view_zoom);
        float2 grid=abs(frac(world)-0.5);
        col+=T.rule*0.25*(1.0-smoothstep(0.48,0.496,min(grid.x,grid.y)));
        col+=T.mid*0.40*((1.0-smoothstep(0.010,0.022,abs(world.x)))+
                        (1.0-smoothstep(0.010,0.022,abs(world.y))));
        float wpp=archPlanSpan().y/max(R.y*(1.0-ARCH_PLAN_TOP)*editor.view_zoom,1.0);
        [loop]for(uint i=0u;i<13u;++i){
            PNode n=PreviewNodes[i];
            float2 local=rotate2(world-n.position.xz,-n.yaw);
            float d=box2(local,max(float2(n.width,n.depth)*0.5,0.035));
            float edge=1.0-smoothstep(wpp*0.65,wpp*1.75,abs(d));
            float fill=smoothstep(wpp*1.3,-wpp*0.55,d);
            float3 tone=kindTone(n.kind_id,T);
            col=lerp(col,tone*0.18,fill*(n.kind_id<3.5?0.10:0.28));
            col+=tone*edge*0.80;
            float dot=1.0-smoothstep(wpp,wpp*2.0,length(world-n.position.xz));
            float arrow=1.0-smoothstep(wpp*0.65,wpp*1.75,
                segment2(world,n.position.xz,n.position.xz+normalize(n.dir+1e-5)*0.34));
            col+=T.ink*dot*0.62+tone*arrow*0.62;
        }
        col+=T.rule*0.55*sui3Registration(P-float2(0,toolbar),float2(R.x,R.y-toolbar),14.0*sB);
    }

    if(R.x>=700.0){
        col+=T.ink*sui3TextLong(P,float2(pad,pad),sT,
            S_A,S_R,S_C,S_H,S_I,S_T,S_E,S_C,S_T,S_U,S_R,S_E,S_SP,S_P,S_L,S_A,S_N,0,0,0,0,0,0,0);
        col+=T.dim*sui3TextLong(P,float2(pad,pad+41.0*sB),sB,
            S_M,S_I,S_D,S_D,S_L,S_E,S_SP,S_P,S_A,S_N,S_SP,S_SL,S_SP,S_W,S_H,S_E,S_E,S_L,S_SP,S_Z,S_O,S_O,S_M,0);
        col+=T.accent*sui3DigitsRight(P,R.x-pad,pad,sN,13,2);
    }else{
        col+=T.ink*sui3Text(P,float2(pad,pad),sT,S_A,S_R,S_C,S_H,S_SP,S_P,S_L,S_A,S_N,0,0,0);
        col+=T.accent*sui3DigitsRight(P,R.x-pad,pad,sN,13,2);
    }
    if(R.x>=700.0)
        col+=T.dim*sui3TextLong(P,float2(0.62*R.x,pad+41.0*sB),sB,
            S_S,S_H,S_E,S_L,S_L,S_SP,S_SL,S_SP,S_E,S_N,S_T,S_R,
            S_Y,S_SP,S_SL,S_SP,S_F,S_L,S_O,S_O,S_R,S_SP,S_SL,0);
    OutputUAV[tid.xy]=float4(saturate(col),1.0);
}
