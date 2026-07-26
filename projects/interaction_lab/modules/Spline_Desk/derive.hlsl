#include "types.hlsli"
StructuredBuffer<SplineKnot> _Tex0 : register(t0);

#if defined(DERIVE_HEADERS)
struct SplineHeader { uint first_knot; uint knot_count; uint closed; uint active; };
RWStructuredBuffer<SplineHeader> OutputBuffer : register(u0);
[numthreads(8,1,1)] void main(uint3 tid:SV_DispatchThreadID) {
    uint spline=tid.x; if(spline>=8u)return; SplineHeader h;h.first_knot=0xffffffffu;h.knot_count=0u;h.closed=0u;h.active=0u;
    [loop] for(uint i=0u;i<64u;i++) if(_Tex0[i].active>0.5 && _Tex0[i].spline_id==spline){if(h.first_knot==0xffffffffu)h.first_knot=i;h.knot_count++;h.closed|=(_Tex0[i].flags>>1u)&1u;}
    h.active=h.knot_count>0u?1u:0u; OutputBuffer[spline]=h;
}
#elif defined(DERIVE_SELECTION)
struct SelectionRecord { uint knot_id; uint spline_id; uint selected; uint tangent_mode; };
RWStructuredBuffer<SelectionRecord> OutputBuffer : register(u0);
[numthreads(64,1,1)] void main(uint3 tid:SV_DispatchThreadID) {
    uint i=tid.x;if(i>=64u)return;SelectionRecord r;r.knot_id=_Tex0[i].knot_id;r.spline_id=_Tex0[i].spline_id;r.selected=_Tex0[i].active>0.5&&knotSelected(_Tex0[i])?1u:0u;r.tangent_mode=_Tex0[i].tangent_mode;OutputBuffer[i]=r;
}
#else
struct PNode { float2 pos; float2 dir; float depth; float u; float v; float weight; float group; float kind; float seed; float active; };
RWStructuredBuffer<PNode> OutputBuffer : register(u0);
int knotAt(uint spline,int ordinal){int seen=0;[loop]for(int i=0;i<64;i++)if(_Tex0[i].active>0.5&&_Tex0[i].spline_id==spline){if(seen==ordinal)return i;seen++;}return -1;}
[numthreads(64,1,1)] void main(uint3 tid:SV_DispatchThreadID) {
    uint index=tid.x;if(index>=512u)return;uint spline=index/64u;uint local=index%64u;int count=0;bool closed=false;
    [loop]for(int i=0;i<64;i++)if(_Tex0[i].active>0.5&&_Tex0[i].spline_id==spline){count++;closed=closed||((_Tex0[i].flags&2u)!=0u);}
    PNode n=(PNode)0;n.group=(float)spline;n.u=(float)local/63.0;n.seed=(float)index;
    int segments=closed?count:max(count-1,0);if(segments>0){float sf=n.u*(float)segments;int seg=min((int)floor(sf),segments-1);float t=saturate(sf-(float)seg);int ai=knotAt(spline,seg);int bi=knotAt(spline,(seg+1)%count);
        if(ai>=0&&bi>=0){float2 q=cubicPoint(_Tex0[ai].anchor,_Tex0[ai].handle_out,_Tex0[bi].handle_in,_Tex0[bi].anchor,t);float2 d=normalize(cubicTangent(_Tex0[ai].anchor,_Tex0[ai].handle_out,_Tex0[bi].handle_in,_Tex0[bi].anchor,t)+1e-7);
            n.pos=float2((q.x-0.5)*3.56,(0.5-q.y)*2.0);n.dir=float2(d.x*3.56,-d.y*2.0);n.weight=1.0;n.active=1.0;}}
    OutputBuffer[index]=n;
}
#endif
