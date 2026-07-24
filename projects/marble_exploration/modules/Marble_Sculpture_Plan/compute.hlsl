struct Part {
    float4 transform_a; // position.xyz, primitive kind
    float4 transform_b; // scale.xyz, blend radius
    float4 rotation;    // rotation.xyz, material id
    float4 meta;        // logical id, group id, seed, active
};
RWStructuredBuffer<Part> OutputBuffer : register(u0);

void writePart(int index, float3 pos, float3 scale, float3 rot, float kind, float groupId, float seed, float active) {
    Part p;
    p.transform_a=float4(pos,kind);
    p.transform_b=float4(scale,0.10);
    p.rotation=float4(rot,0.0);
    p.meta=float4((float)index,groupId,seed,active);
    OutputBuffer[index]=p;
}

[numthreads(1,1,1)]
void main(uint3 id : SV_DispatchThreadID) {
    // One positive, monolithic mass. Everything interesting below is a cut.
    float blockTwist=torsion*0.08;
    writePart(0,float3(0,0.10,0),float3(0.86,1.48,0.56),float3(0,0,blockTwist),7,0,0.1,1);
    writePart(1,float3(0,-1.38,0),float3(1.18,0.13,0.76),float3(0,0,0),4,1,0.2,1);

    // Central void: an intentionally off-axis aperture, not anatomy.
    writePart(2,float3(0.10,0.08,0),float3(void_width*1.18,0.86,0.68),float3(0,0,torsion*0.16),3,2,0.3,1);

    // Seventeen repeated cutters arranged on a golden-angle helix. Their
    // group selects diamond / box / slot geometry in the renderer.
    const float GOLDEN=2.39996323;
    for(int i=0;i<17;i++) {
        float fi=(float)i;
        float a=fi*GOLDEN+torsion*0.45;
        float y=-1.02+frac(fi*0.6180339)*2.18;
        float ring=0.48+0.14*sin(fi*1.73+asymmetry*3.0);
        float3 pos=float3(cos(a)*ring,y,sin(a)*0.52);
        float3 scl=float3(0.18+0.10*frac(fi*0.37),0.22+0.28*frac(fi*0.71),0.34+0.22*frac(fi*0.23));
        float group=8.0+(float)(i%3);
        float rot=a+0.35*sin(fi*2.1+torsion);
        writePart(3+i,pos,scl,float3(0.28*sin(fi*1.41),0.34*cos(fi*1.17),rot),3,group,frac(fi*0.173+0.31),1);
    }
}
