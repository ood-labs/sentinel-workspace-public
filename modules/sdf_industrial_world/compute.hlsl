struct Part { float4 transform_a; float4 transform_b; float4 rotation; float4 meta; };
RWStructuredBuffer<Part> OutputBuffer : register(u0);

void writePart(int i,float3 pos,float3 scale,float3 rot,float kind,float groupId,float materialId,float active) {
    Part p;
    p.transform_a=float4(pos,kind);
    p.transform_b=float4(scale,0.02);
    p.rotation=float4(rot,materialId);
    p.meta=float4(0.0,groupId,0.0,active);
    OutputBuffer[i]=p;
}

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    float t=_Time*motion_rate;
    float s=world_scale;
    float h=tower_height*s;
    float active=saturate(industrial_density+pulse*0.04);
    float phase=seed*0.37+sin(t)*0.14;
    // A heavy plinth and offset slabs establish a larger architectural world.
    writePart(0,float3(0,-1.68,0),float3(2.75,0.07,2.0)*s,float3(0,0,0),4,20,2,1);
    writePart(1,float3(0,-1.42,1.48),float3(2.4,0.62,0.08)*s,float3(0,0,0),7,21,2,active);
    writePart(2,float3(-1.95,0.0,0.75),float3(0.14,h,0.14)*s,float3(0,0,0),7,22,2,active);
    writePart(3,float3(1.95,0.15,0.72),float3(0.18,h*0.86,0.18)*s,float3(0,0,0),7,23,2,active);
    writePart(4,float3(0.0,1.88,1.42),float3(2.1,0.10,0.10)*s,float3(0,0,0),5,24,2,active);
    writePart(5,float3(-1.0,0.65,1.42),float3(0.08,1.15,0.08)*s,float3(0,0,0),5,25,2,active);
    writePart(6,float3(1.0,0.35,1.42),float3(0.08,0.95,0.08)*s,float3(0,0,0),5,26,2,active);
    // Offset graphic bars: deliberately legible as a machine-readable scaffold.
    [unroll]
    for(int i=0;i<8;i++) {
        float fi=(float)i;
        float x=-1.65+fi*frame_gap;
        float y=-1.15+frac(fi*0.618+phase)*2.15;
        float z=1.06+sin(fi*1.71+phase)*0.16;
        float w=graphic_thickness*(0.7+frac(fi*0.37+seed)*0.8);
        writePart(7+i,float3(x,y,z),float3(w,0.32+frac(fi*0.41+seed)*0.32,w)*s,float3(0,0,(fi-3.5)*0.055),5,30+i,3,active);
    }
    // Two monumental side frames.
    writePart(15,float3(-2.35,0.20,0.15),float3(0.07,1.55,0.07)*s,float3(0,0,0),5,50,2,active);
    writePart(16,float3(-2.35,0.20,0.15),float3(0.65,0.07,0.07)*s,float3(0,0,0),5,51,2,active);
    writePart(17,float3(2.35,-0.15,0.15),float3(0.07,1.32,0.07)*s,float3(0,0,0),5,52,2,active);
    writePart(18,float3(2.35,-0.15,0.15),float3(0.72,0.07,0.07)*s,float3(0,0,0),5,53,2,active);
    writePart(19,float3(0,0.8,-1.55),float3(1.8,0.07,0.07)*s,float3(0,0,0.18),5,54,2,active);
    writePart(20,float3(0,-0.35,-1.55),float3(1.45,0.06,0.06)*s,float3(0,0,-0.22),5,55,2,active);
    writePart(21,float3(-0.85,-1.05,-1.2),float3(0.06,0.34,0.06)*s,float3(0,0,0),5,56,3,active);
    writePart(22,float3(0.85,-0.88,-1.2),float3(0.06,0.46,0.06)*s,float3(0,0,0),5,57,3,active);
    writePart(23,float3(0,1.12,-0.9),float3(0.9,0.045,0.045)*s,float3(0,0,0.35),5,58,3,active);
}
