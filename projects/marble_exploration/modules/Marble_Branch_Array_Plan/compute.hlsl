struct Part { float4 transform_a; float4 transform_b; float4 rotation; float4 meta; };
RWStructuredBuffer<Part> OutputBuffer : register(u0);

void writePart(int i,float3 pos,float3 scale,float3 rot,float kind,float groupId,float materialId,float active) {
    Part p;
    p.transform_a=float4(pos,kind);
    p.transform_b=float4(scale,0.018);
    p.rotation=float4(rot,materialId);
    p.meta=float4(0.0,groupId,0.0,active);
    OutputBuffer[i]=p;
}

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    float t=_Time*phase_rate;
    float pulseBoost=1.0+pulse*0.08;
    float r=orbit_radius;
    float active=1.0;
    // A broken monolith and an offset plinth anchor the array.
    writePart(0,float3(0,-1.42,0),float3(1.65,0.10,1.12),float3(0,0,0),4,1,0.5,1);
    writePart(1,float3(0,0.12,0),float3(0.54,1.28,0.42)*shard_scale,float3(0,0,orbital_twist*0.08),7,2,0.5,1);
    writePart(2,float3(0.16,1.34,0.0),float3(0.78,0.12,0.38)*shard_scale,float3(0,0,-0.12),7,3,0.5,1);
    writePart(3,float3(-0.18,-0.16,0.22),float3(0.22,0.82,0.24)*shard_scale,float3(0,0,0.32),7,4,0.5,1);
    // Six orbital slabs: positional rotation and time phase create a spatially legible array.
    [unroll]
    for(int i=0;i<6;i++) {
        float fi=(float)i;
        float a=fi*1.04719755+t*0.72+seed*0.03;
        float wobble=sin(t*1.1+fi*1.7+seed)*0.12*asymmetry;
        float rr=r+(fi-2.5)*0.035*asymmetry;
        float3 pos=float3(cos(a)*rr,0.05+sin(a*2.0+t)*0.18+wobble,sin(a)*0.62);
        float3 scl=float3(0.16+frac(fi*0.27+seed)*0.12,0.46+frac(fi*0.41+seed)*0.32,0.18)*shard_scale;
        writePart(4+i,pos,scl,float3(0,0,a+0.22*sin(t+fi)),7,10+i,0.5,active);
        writePart(10+i,pos+float3(0.02,0.02,0),scl*float3(1.18,0.34,1.26)*cutter_scale,float3(0,0,a+0.7),3,20+i,0.5,active);
    }
    // Suspended crossbars make the negative spaces read as designed apertures.
    [unroll]
    for(int i=0;i<6;i++) {
        float fi=(float)i;
        float a=fi*1.04719755-t*0.42;
        float3 pos=float3(cos(a)*(r+0.18),0.78+sin(fi*2.2+seed)*0.22,sin(a)*0.55);
        float3 scl=float3(0.52,0.055,0.07)*shard_scale;
        writePart(16+i,pos,scl,float3(0,0,a),5,30+i,0.5,active);
        writePart(22+i,pos+float3(0,-0.12,0),scl*float3(0.8,1.0,1.0)*cutter_scale,float3(0,0,a+0.5),3,40+i,0.5,active);
    }
    // Nine razor bars form a graphic orbital cage around the mass.
    [unroll]
    for(int i=0;i<9;i++) {
        float fi=(float)i;
        float a=fi*0.6981317+t*0.28;
        float rad=r+0.52+sin(fi*1.3+seed)*0.08;
        float3 pos=float3(cos(a)*rad,-0.62+frac(fi*0.37+seed)*1.85,sin(a)*0.78);
        writePart(28+i,pos,float3(0.035,0.24+frac(fi*0.29+seed)*0.18,0.035)*shard_scale,float3(0,0,a+1.57),5,60+i,0.5,active);
    }
    writePart(37,float3(-0.72,1.42,0.12),float3(0.62,0.045,0.045),float3(0,0,0.28),5,80,0.5,active);
    writePart(38,float3(0.78,1.08,-0.18),float3(0.52,0.045,0.045),float3(0,0,-0.34),5,81,0.5,active);
    writePart(39,float3(0,-0.72,-0.84),float3(0.9,0.05,0.05),float3(0,0,0.0),5,82,0.5,active);
    // Fill remaining records with diagonal cutters that fracture the monolith.
    [unroll]
    for(int i=0;i<5;i++) {
        float fi=(float)i;
        float a=-0.9+fi*0.45+t*0.18;
        float3 pos=float3(-0.52+fi*0.26,0.18+sin(fi+seed)*0.45,0.15+cos(fi*1.4)*0.2);
        writePart(40+i,pos,float3(0.12,0.30+0.08*asymmetry,0.34)*cutter_scale,float3(0,0,a),3,90+i,0.5,active);
    }
    writePart(45,float3(0.0,0.34,0.35),float3(0.22,0.54,0.22)*cutter_scale,float3(0,0,0.78),3,96,0.5,active);
    writePart(46,float3(0.22,-0.7,0.0),float3(0.36,0.16,0.52)*cutter_scale,float3(0,0,-0.42),3,97,0.5,active);
    writePart(47,float3(-0.42,0.95,-0.08),float3(0.18,0.28,0.30)*cutter_scale,float3(0,0,0.2),3,98,0.5,active);
}
