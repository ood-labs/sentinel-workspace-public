#include "types.hlsli"
StructuredBuffer<EditorState> _Tex0 : register(t0);
StructuredBuffer<SplineKnot> _Tex1 : register(t1);
RWStructuredBuffer<SplineKnot> OutputBuffer : register(u0);

SplineKnot makeKnot(uint slot,uint spline,float2 p) {
    SplineKnot k; k.anchor=p; k.handle_in=p-float2(0.055,0); k.handle_out=p+float2(0.055,0);
    k.knot_id=slot+1u; k.spline_id=spline; k.tangent_mode=1u; k.flags=0u; k.active=1.0; k.marker=slot==0u?9109.0:0.0; return k;
}

void initialize() {
    [loop] for(uint i=0u;i<64u;i++) { SplineKnot z=(SplineKnot)0; z.knot_id=i+1u; z.marker=i==0u?9109.0:0.0; OutputBuffer[i]=z; }
    OutputBuffer[0]=makeKnot(0,0,float2(0.16,0.62));
    OutputBuffer[1]=makeKnot(1,0,float2(0.36,0.30));
    OutputBuffer[2]=makeKnot(2,0,float2(0.62,0.68));
    OutputBuffer[3]=makeKnot(3,0,float2(0.84,0.35));
}

[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID) {
    if(abs(OutputBuffer[0].marker-9109.0)>0.5) initialize();
    EditorState st=_Tex0[0]; uint cmd=(uint)round(st.command); uint target=st.target>=0.0?(uint)round(st.target):999u;
    bool shift=(((uint)round(st.modifiers)) & VIEWPORT_MODIFIER_SHIFT)!=0u;
    bool ctrl=(((uint)round(st.modifiers)) & VIEWPORT_MODIFIER_CONTROL)!=0u;
    if(cmd==1u) {
        if((uint)round(st.target_kind)==5u) {
            if(!shift && !ctrl) [loop] for(uint i=0u;i<64u;i++) OutputBuffer[i].flags&=~1u;
        } else if(target<64u) {
            uint spline=OutputBuffer[target].spline_id;
            if(!shift && !ctrl && !knotSelected(OutputBuffer[target])) [loop] for(uint i=0u;i<64u;i++) OutputBuffer[i].flags&=~1u;
            [loop] for(uint i=0u;i<64u;i++) if(OutputBuffer[i].active>0.5 && ((uint)round(st.target_kind)==4u?OutputBuffer[i].spline_id==spline:i==target)) {
                if(ctrl) OutputBuffer[i].flags&=~1u; else if(shift) OutputBuffer[i].flags^=1u; else OutputBuffer[i].flags|=1u;
            }
        }
    }
    if(cmd==2u || cmd==3u) {
        uint kind=(uint)round(st.target_kind); float2 delta=st.pointer-st.drag_start;
        if(kind==1u || kind==4u) {
            [loop] for(uint i=0u;i<64u;i++) if(OutputBuffer[i].active>0.5 && knotSelected(OutputBuffer[i])) {
                SplineKnot base=_Tex1[i]; OutputBuffer[i].anchor=base.anchor+delta; OutputBuffer[i].handle_in=base.handle_in+delta; OutputBuffer[i].handle_out=base.handle_out+delta;
            }
        } else if(target<64u && (kind==2u || kind==3u)) {
            SplineKnot base=_Tex1[target]; float2 moved=(kind==2u?base.handle_in:base.handle_out)+delta;
            if(kind==2u) OutputBuffer[target].handle_in=moved; else OutputBuffer[target].handle_out=moved;
            float2 v=moved-base.anchor; float2 opposite=kind==2u?base.handle_out-base.anchor:base.handle_in-base.anchor;
            uint tangent=OutputBuffer[target].tangent_mode;
            if(tangent==1u) opposite=-normalize(v+1e-7)*length(opposite);
            if(tangent==2u) opposite=-v;
            if(tangent>0u) { if(kind==2u) OutputBuffer[target].handle_out=base.anchor+opposite; else OutputBuffer[target].handle_in=base.anchor+opposite; }
        }
        if(cmd==3u && kind==5u) {
            float2 lo=min(st.marquee_start,st.marquee_end), hi=max(st.marquee_start,st.marquee_end);
            [loop] for(uint i=0u;i<64u;i++) if(OutputBuffer[i].active>0.5 && all(OutputBuffer[i].anchor>=lo) && all(OutputBuffer[i].anchor<=hi)) {
                if(ctrl) OutputBuffer[i].flags&=~1u; else OutputBuffer[i].flags|=1u;
            }
        }
    }
    if(cmd==4u) {
        [loop] for(uint i=0u;i<64u;i++) { uint flags=OutputBuffer[i].flags; OutputBuffer[i]=_Tex1[i]; OutputBuffer[i].flags=flags; }
    }
    if(cmd==5u) {
        [loop] for(uint i=0u;i<64u;i++) if(OutputBuffer[i].active<0.5) { OutputBuffer[i]=makeKnot(i,(uint)round(st.active_spline),st.pointer); OutputBuffer[i].tangent_mode=(uint)round(st.tangent_mode); break; }
    }
    if(cmd==7u) {
        [loop] for(uint i=0u;i<64u;i++) if(OutputBuffer[i].active>0.5 && OutputBuffer[i].spline_id==(uint)round(st.active_spline)) { OutputBuffer[i].flags^=2u; break; }
    }
    if(cmd==8u) [loop] for(uint i=0u;i<64u;i++) if(knotSelected(OutputBuffer[i])) OutputBuffer[i].tangent_mode=(uint)round(st.tangent_mode);
    if(cmd==9u) [loop] for(uint i=0u;i<64u;i++) if(knotSelected(OutputBuffer[i])) { OutputBuffer[i].active=0.0; OutputBuffer[i].flags=0u; }
    OutputBuffer[0].marker=9109.0;
}
