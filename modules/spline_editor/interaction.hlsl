#include "types.hlsli"
#include "../_shared/ui/sui_interaction.hlsli"
#include "_ui.generated.hlsli"

StructuredBuffer<SplineKnot> _Tex0 : register(t0);
RWStructuredBuffer<EditorState> OutputBuffer : register(u0);

int nextActive(uint splineId, int after) {
    [loop] for(int i=after+1;i<64;i++) if(_Tex0[i].active>0.5 && _Tex0[i].spline_id==splineId) return i;
    return -1;
}

void hitTest(float2 p, out int hitIndex, out int hitKind, out int hitSpline) {
    hitIndex=-1; hitKind=0; hitSpline=-1; float best=0.022;
    [loop] for(int i=0;i<64;i++) {
        SplineKnot k=_Tex0[i]; if(k.active<0.5) continue;
        float d=length(p-k.anchor); if(d<best){best=d;hitIndex=i;hitKind=1;hitSpline=(int)k.spline_id;}
        d=length(p-k.handle_in); if(d<best){best=d;hitIndex=i;hitKind=2;hitSpline=(int)k.spline_id;}
        d=length(p-k.handle_out); if(d<best){best=d;hitIndex=i;hitKind=3;hitSpline=(int)k.spline_id;}
    }
    if(hitKind!=0) return;
    [loop] for(uint spline=0u;spline<8u;spline++) {
        int a=nextActive(spline,-1); if(a<0) continue;
        int b=nextActive(spline,a);
        while(b>=0) {
            float2 prev=_Tex0[a].anchor;
            [unroll] for(int s=1;s<=12;s++) {
                float t=(float)s/12.0;
                float2 cur=cubicPoint(_Tex0[a].anchor,_Tex0[a].handle_out,_Tex0[b].handle_in,_Tex0[b].anchor,t);
                float d=pointSegmentDistance(p,prev,cur);
                if(d<best){best=d;hitIndex=a;hitKind=4;hitSpline=(int)spline;}
                prev=cur;
            }
            a=b; b=nextActive(spline,a);
        }
    }
}

[numthreads(1,1,1)]
void main(uint3 tid:SV_DispatchThreadID) {
    EditorState st=OutputBuffer[0];
    if(st.tool<0.0 || st.tool>1.0 || isnan(st.tool)) { st.tool=0.0; st.active_spline=0.0; st.tangent_mode=1.0; }
    st.command=0.0; st.phase=0.0;
    uint down=(suiInteraction(UI_INDEX_SELECT).down?1u:0u)|(suiInteraction(UI_INDEX_PEN).down?2u:0u)|(suiInteraction(UI_INDEX_TANGENT).down?4u:0u)|(suiInteraction(UI_INDEX_CLOSE).down?8u:0u)|(suiInteraction(UI_INDEX_DELETE).down?16u:0u);
    uint pressed=down&~(uint)round(st.toolbar_latch);st.toolbar_latch=(float)down;
    if((pressed&1u)!=0u)st.tool=0.0;
    if((pressed&2u)!=0u)st.tool=1.0;
    if((pressed&4u)!=0u){st.tangent_mode=fmod(st.tangent_mode+1.0,3.0);st.command=8.0;}
    if((pressed&8u)!=0u)st.command=7.0;
    if((pressed&16u)!=0u)st.command=9.0;

    uint count=min(_ViewportEventCount,64u);
    [loop] for(uint i=0u;i<count;i++) {
        ViewportEvent e=_ViewportEvents[i];
        if(e.type==4u && e.phase==1u) {
            if(e.code==22u) st.tool=0.0;              // V
            if(e.code==16u) st.tool=1.0;              // P
            if(e.code==20u){st.tangent_mode=fmod(st.tangent_mode+1.0,3.0);st.command=8.0;} // T
            if(e.code==15u) st.command=7.0;           // O
            if(e.code==52u) st.command=9.0;           // Backspace
            if(e.code==50u) st.active_spline=min(st.active_spline+1.0,7.0); // Enter
            if(e.code==48u){st.command=4.0;st.phase=8.0;}
        }
        // The host control layer also drives one-shot parameters. Ignore any
        // pointer boundary that lands in the authored toolbar so it can never
        // leak through as a canvas edit on the same frame.
        if(e.type==5u && e.device==0u && e.position.y<0.12) continue;
        if(e.type==5u && e.code==2u && e.phase==4u) st.active_spline=min(st.active_spline+1.0,7.0);
        if(e.type==5u && e.code==1u && e.phase==7u && st.tool>0.5) {
            st.command=5.0; st.pointer=e.position; st.modifiers=(float)e.modifiers;
        }
        if(e.type!=5u || e.code!=3u || e.device!=0u) continue;
        if(e.phase==5u) {
            int hitIndex,hitKind,hitSpline; hitTest(e.position,hitIndex,hitKind,hitSpline);
            st.command=1.0; st.phase=5.0; st.target=(float)hitIndex; st.target_kind=(float)(hitKind==0?5:hitKind);
            st.active_spline=hitSpline>=0?(float)hitSpline:st.active_spline;
            st.drag_start=e.position; st.pointer=e.position; st.marquee_start=e.position; st.marquee_end=e.position;
            st.modifiers=(float)e.modifiers;
        } else if((e.phase==6u || e.phase==7u || e.phase==8u) && st.target_kind>0.0) {
            st.command=e.phase==8u?4.0:(e.phase==7u?3.0:2.0); st.phase=(float)e.phase; st.pointer=e.position;
            st.marquee_end=e.position; st.modifiers=(float)e.modifiers;
            if(e.phase>=7u) { /* update consumes final state before next cook */ }
        }
    }
    OutputBuffer[0]=st;
}
