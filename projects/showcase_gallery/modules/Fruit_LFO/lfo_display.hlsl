#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

RWTexture2D<float4> OutputUAV:register(u0);
struct LFOData {
    float lfo1; float lfo2; float lfo3; float lfo4;
    float bias_x; float bias_y; float energy; float pulse;
};
StructuredBuffer<LFOData> _Tex0:register(t0);
static const float TWO_PI=6.28318530718;

float evalWave(float phaseValue,float shapeValue){
    float p=frac(phaseValue);uint shape=(uint)clamp(round(shapeValue),0.0,3.0);
    return shape==0u?sin(phaseValue*TWO_PI)*0.5+0.5:
           shape==1u?1.0-abs(p*2.0-1.0):shape==2u?p:step(0.5,p);
}
float4 pxRect(float4 r,float2 R){return r*float4(R,R);}

float3 drawLane(float2 P,float2 R,float4 r,float value,float speed,float amp,
                float shape,uint lane,Sui3Theme T,float sB,float sN){
    float3 c=sui3Well(P,r,T);
    c+=T.accent*sui3RectIn(P,float4(r.x,r.y,r.x+3.0,r.w))*value;
    float4 wave=float4(r.x+0.14*(r.z-r.x),r.y+0.14*(r.w-r.y),
                       r.x+0.65*(r.z-r.x),r.y+0.55*(r.w-r.y));
    c+=T.rule*0.22*sui3Graticule(P,wave,float2(8.0,2.0));
    c+=T.rule*sui3Frame(P,wave);
    if(sui3RectIn(P,wave)>0.5){
        float x=saturate((P.x-wave.x)/max(wave.z-wave.x,1.0));
        float y=evalWave(x*2.0,shape)*amp;
        float py=lerp(wave.w-3.0,wave.y+3.0,y);
        c+=T.ink*(1.0-smoothstep(0.45,1.45,abs(P.y-py)));
        float head=frac(_Time*master_rate*speed*0.5);
        float hx=lerp(wave.x,wave.z,head);
        float hy=lerp(wave.w-3.0,wave.y+3.0,evalWave(head*2.0,shape)*amp);
        c+=T.accent*(1.0-smoothstep(2.0,4.0,length(P-float2(hx,hy))));
    }
    float labelY=r.y+9.0*sB;
    if(R.x>=400.0){
        if(lane==0u)c+=T.ink*sui3Text(P,float2(r.x+10.0*sB,labelY),sB,S_P,S_R,S_O,S_M,S_P,S_T,0,0,0,0,0,0);
        if(lane==1u)c+=T.ink*sui3Text(P,float2(r.x+10.0*sB,labelY),sB,S_E,S_N,S_E,S_R,S_G,S_Y,0,0,0,0,0,0);
        if(lane==2u)c+=T.ink*sui3Text(P,float2(r.x+10.0*sB,labelY),sB,S_C,S_A,S_M,S_E,S_R,S_A,0,0,0,0,0,0);
        if(lane==3u)c+=T.ink*sui3Text(P,float2(r.x+10.0*sB,labelY),sB,S_P,S_U,S_L,S_S,S_E,0,0,0,0,0,0,0);
    }else{
        c+=T.ink*sui3Digits(P,float2(r.x+3.0,r.y+3.0),sB,(int)lane+1,2);
    }
    if(R.y>=360.0)
        c+=T.accent*sui3Digits(P,float2(r.x+10.0*sB,r.y+43.0*sB),sN,(int)round(value*100.0),3);
    return c;
}

[numthreads(8,8,1)]
void main(uint3 tid:SV_DispatchThreadID){
    if(tid.x>=(uint)_Resolution.x||tid.y>=(uint)_Resolution.y)return;
    float2 R=_Resolution.xy,P=(float2)tid.xy+0.5;
    float k=min(R.x/1280.0,R.y/720.0);
    float sB=k>=2.6?3.0:k>=1.7?2.0:1.0,sN=2.0*sB;
    float sT=R.y<180.0?sB:3.0*sB;
    float pad=max(8.0,0.02*R.x);
    Sui3Theme T=sui3Theme(SUI3_AMBER);
    LFOData d=_Tex0[0];
    float3 col=T.field;
    float4 shell=float4(pad,pad,R.x-pad,R.y-pad);
    col+=T.rule*0.18*sui3Graticule(P,shell,float2(24.0,18.0));
    col+=T.rule*sui3Frame(P,shell);

    float headerBottom=0.165*R.y;
    col+=T.well*sui3RectIn(P,float4(shell.x,shell.y,shell.z,headerBottom));
    col+=T.accent*sui3RectIn(P,float4(shell.x,shell.y,shell.x+4.0*sB,headerBottom));
    if(R.x>=700.0){
        col+=T.ink*sui3TextLong(P,float2(shell.x+18.0*sB,shell.y+(R.y<320.0?2.0:12.0)*sB),sT,
            S_F,S_R,S_U,S_I,S_T,S_SP,S_M,S_O,S_T,S_I,S_O,S_N,
            S_SP,S_C,S_O,S_N,S_S,S_O,S_L,S_E,0,0,0,0);
        if(R.y>=320.0)
            col+=T.dim*sui3TextLong(P,float2(shell.x+18.0*sB,shell.y+47.0*sB),sB,
                S_F,S_O,S_U,S_R,S_SP,S_L,S_A,S_N,S_E,S_SP,S_M,S_O,
                S_D,S_U,S_L,S_A,S_T,S_I,S_O,S_N,0,0,0,0);
    }else{
        col+=T.ink*sui3Text(P,float2(shell.x+9.0,shell.y+9.0),sT,
            S_M,S_O,S_T,S_I,S_O,S_N,S_SP,S_D,S_E,S_S,S_K,0);
    }

    float4 lane0=float4(0.035*R.x,0.200*R.y,0.755*R.x,0.365*R.y);
    float4 lane1=float4(0.035*R.x,0.390*R.y,0.755*R.x,0.555*R.y);
    float4 lane2=float4(0.035*R.x,0.580*R.y,0.755*R.x,0.745*R.y);
    float4 lane3=float4(0.035*R.x,0.770*R.y,0.755*R.x,0.935*R.y);
    col+=drawLane(P,R,lane0,d.lfo1,lfo1_speed,lfo1_amp,lfo1_shape,0u,T,sB,sN);
    col+=drawLane(P,R,lane1,d.lfo2,lfo2_speed,lfo2_amp,lfo2_shape,1u,T,sB,sN);
    col+=drawLane(P,R,lane2,d.lfo3,lfo3_speed,lfo3_amp,lfo3_shape,2u,T,sB,sN);
    col+=drawLane(P,R,lane3,d.lfo4,lfo4_speed,lfo4_amp,lfo4_shape,3u,T,sB,sN);

    float values[13]={
        saturate((master_rate-0.1)/2.9),
        saturate((lfo1_speed-0.05)/3.95),lfo1_amp,saturate(lfo1_shape/3.0),
        saturate((lfo2_speed-0.05)/3.95),lfo2_amp,saturate(lfo2_shape/3.0),
        saturate((lfo3_speed-0.05)/3.95),lfo3_amp,saturate(lfo3_shape/3.0),
        saturate((lfo4_speed-0.05)/3.95),lfo4_amp,saturate(lfo4_shape/3.0)
    };
    float4 rects[13]={
        pxRect(UI_RECT_MASTER_RATE,R),
        pxRect(UI_RECT_LFO1_SPEED,R),pxRect(UI_RECT_LFO1_AMP,R),pxRect(UI_RECT_LFO1_SHAPE,R),
        pxRect(UI_RECT_LFO2_SPEED,R),pxRect(UI_RECT_LFO2_AMP,R),pxRect(UI_RECT_LFO2_SHAPE,R),
        pxRect(UI_RECT_LFO3_SPEED,R),pxRect(UI_RECT_LFO3_AMP,R),pxRect(UI_RECT_LFO3_SHAPE,R),
        pxRect(UI_RECT_LFO4_SPEED,R),pxRect(UI_RECT_LFO4_AMP,R),pxRect(UI_RECT_LFO4_SHAPE,R)
    };
    [unroll]for(uint i=0u;i<13u;++i)col+=sui3Rail(P,rects[i],values[i],T);

    float4 muteRect=pxRect(UI_RECT_MUTE,R);
    col+=sui3Toggle(P,muteRect,mute,T);
    if(R.x>=400.0)
        col+=(mute?T.accent:T.ink)*sui3Text(P,float2(muteRect.x+7.0*sB,muteRect.y+8.0*sB),sB,
            S_M,S_U,S_T,S_E,0,0,0,0,0,0,0,0);
    else
        col+=(mute?T.accent:T.ink)*sui3Text(P,float2(muteRect.x+4.0,muteRect.y+2.0),sB,
            S_M,0,0,0,0,0,0,0,0,0,0,0);
    float4 padRect=pxRect(UI_RECT_MOTION_BIAS,R);
    col+=sui3Pad(P,padRect,motion_bias,T);
    if(R.x>=400.0)
        col+=T.dim*sui3Text(P,float2(padRect.x,padRect.y-16.0*sB),sB,
            S_M,S_O,S_T,S_I,S_O,S_N,S_SP,S_B,S_I,S_A,S_S,0);
    float4 burstRect=pxRect(UI_RECT_BURST,R);
    col+=sui3BankCell(P,burstRect,burst>0.5,T);
    if(R.x>=400.0)
        col+=T.ink*sui3Text(P,float2(burstRect.x+8.0*sB,burstRect.y+8.0*sB),sB,
            S_B,S_U,S_R,S_S,S_T,0,0,0,0,0,0,0);
    else
        col+=T.ink*sui3Text(P,float2(burstRect.x+4.0,burstRect.y+2.0),sB,
            S_B,0,0,0,0,0,0,0,0,0,0,0);

    float4 meters[4]={
        float4(0.800*R.x,0.650*R.y,0.950*R.x,0.680*R.y),
        float4(0.800*R.x,0.700*R.y,0.950*R.x,0.730*R.y),
        float4(0.800*R.x,0.750*R.y,0.950*R.x,0.780*R.y),
        float4(0.800*R.x,0.800*R.y,0.950*R.x,0.830*R.y)
    };
    float mv[4]={d.lfo1,d.lfo2,d.lfo3,d.lfo4};
    [unroll]for(uint j=0u;j<4u;++j)col+=sui3Rail(P,meters[j],mv[j],T);
    if(R.x>=400.0)
        col+=(mute?T.accent:T.ink)*sui3Text(P,float2(0.800*R.x,0.875*R.y),sB,
            mute?S_M:S_L,mute?S_U:S_I,mute?S_T:S_V,mute?S_E:S_E,0,0,0,0,0,0,0,0);
    OutputUAV[tid.xy]=float4(saturate(col),1.0);
}
