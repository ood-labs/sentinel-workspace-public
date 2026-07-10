struct PrimitiveRecord { float2 p0; float2 p1; float3 color; float width; float kind; float group_id; float route_t; float active; };
RWStructuredBuffer<PrimitiveRecord> Out : register(u0);
float h(float n){ return frac(sin(n*127.1)*43758.5453); }
[numthreads(64,1,1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i=id.x; if(i>=192u)return;
    PrimitiveRecord r=(PrimitiveRecord)0; r.active=0;
    int count = detail == 0 ? 72 : (detail == 1 ? 128 : 184);
    if(i >= (uint)count){Out[i]=r;return;}
    // point2D is Cartesian (+Y up); texture UV is +Y down.
    float2 uiOffset=float2(composition_offset.x,-composition_offset.y);
    float2 center=float2(0.275,0.285)+uiOffset+_Data0[0].drift;
    float p=_Data0[0].phase;
    int lineCount=count-24;
    if(i<(uint)lineCount){
        uint arm=i/4u, seg=i%4u; float t0=seg/4.0,t1=(seg+1)/4.0;
        float base=6.2831853*h(arm+seed*17); float curl=(h(arm*3.1+seed)-0.5)*2.4;
        float a0=base+curl*t0+0.14*sin(6.2831853*p+arm*.73+t0*4.0);
        float a1=base+curl*t1+0.14*sin(6.2831853*p+arm*.73+t1*4.0);
        float rr0=.018+.255*pow(t0,.72),rr1=.018+.255*pow(t1,.72);
        r.p0=center+float2(cos(a0),sin(a0))*rr0*composition_scale;
        r.p1=center+float2(cos(a1),sin(a1))*rr1*composition_scale;
        r.color=lerp(float3(1.0,.08,.01),float3(1.0,.34,.03),t1);
        r.width=lerp(.0018,.00055,t1);r.kind=0;r.group_id=arm;r.route_t=t0;r.active=1;
    }else{
        float fi=(float)(i-lineCount);float aa=6.2831853*h(fi*3.7+seed);float rad=.17+.14*h(fi*7.1);
        r.p0=r.p1=center+float2(cos(aa),sin(aa))*rad*composition_scale;r.color=lerp(float3(.2,1,.8),float3(1,1,.2),h(fi));r.width=.004;r.kind=1;r.group_id=fi;r.route_t=p;r.active=1;
    }
    Out[i]=r;
}
