struct MaterialRecord {
    float3 base_color; float roughness;
    float3 secondary_color; float metallic;
    float texture_scale; float texture_strength; float pattern_id; float emissive;
    float specular; float normal_strength; float seed; float reserved;
};
RWStructuredBuffer<MaterialRecord> OutputBuffer : register(u0);

MaterialRecord makeMat(float3 baseColor, float rough, float3 secondary, float metal,
                       float texScale, float texStrength, float patternId, float emission,
                       float spec, float normalAmount, float seedValue) {
    MaterialRecord m;
    m.base_color=baseColor; m.roughness=rough; m.secondary_color=secondary; m.metallic=metal;
    m.texture_scale=texScale; m.texture_strength=texStrength; m.pattern_id=patternId; m.emissive=emission;
    m.specular=spec; m.normal_strength=normalAmount; m.seed=seedValue; m.reserved=0;
    return m;
}

[numthreads(16,1,1)]
void main(uint3 id:SV_DispatchThreadID) {
    uint i=id.x; if(i>=12)return;
    float warmth=(tone_balance.x-.5)*.22;
    float reflectance=lerp(.72,1.28,tone_balance.y);
    float3 tone=float3(1.0+warmth*.45,1.0,1.0-warmth*.65);
    MaterialRecord m=makeMat(float3(.5,.5,.5),.7,float3(.35,.35,.35),0,4,.2,0,0,.25,.1,(float)i*13.7);
    if(i==0)  m=makeMat(plaza_stone*tone,stone_roughness,plaza_stone*.62*tone,0,3.0,.42*texture_detail,1,0,.18*reflectance,.20*normal_detail,11);
    if(i==1)  m=makeMat(limestone*tone,stone_roughness*.92,limestone*float3(.72,.78,.86)*tone,0,1.8,.38*texture_detail,2,0,.22*reflectance,.24*normal_detail,23);
    if(i==2)  m=makeMat(board_concrete*tone,min(1.0,stone_roughness*1.06),board_concrete*.58*tone,0,1.2,.46*texture_detail,3,0,.12*reflectance,.30*normal_detail,31);
    if(i==3)  m=makeMat(glass_tint*tone,glass_roughness,float3(.42,.68,.82)*tone,.06,8,.24*texture_detail,4,.10,.96*reflectance,.05*normal_detail,43);
    if(i==4)  m=makeMat(bronze*tone,bronze_roughness,lerp(bronze*.55,float3(.08,.30,.24),bronze_age),.86,10,.32*texture_detail,5,0,.88*reflectance,.12*normal_detail,47);
    if(i==5)  m=makeMat(black_metal,.22,float3(.12,.14,.16),.92,12,.28,5,0,.94,.10,59);
    if(i==6)  m=makeMat(timber*tone,.54,timber*float3(.36,.48,.62)*tone,0,5.5,.52*texture_detail,6,0,.38*reflectance,.18*normal_detail,61);
    if(i==7)  m=makeMat(float3(.11,.12,.13),.94,float3(.045,.05,.055),0,6,.38,2,0,.05,.24,71);
    if(i==8)  m=makeMat(foliage,.82,foliage*float3(.34,.56,.38),0,14,.78*texture_detail,7,0,.08,.48*normal_detail,73);
    if(i==9)  m=makeMat(window_glow,.18,window_glow*float3(1,.72,.38),0,1,0,0,5.5*emission_gain,.22,0,79);
    if(i==10) m=makeMat(float3(.18,.20,.22),.64,float3(.07,.08,.09),.35,4,.30,3,0,.56,.12,83);
    if(i==11) m=makeMat(float3(.16,.24,.28),.06,float3(.55,.78,.88),.04,2,.12,4,.25,.98,.02,89);
    OutputBuffer[i]=m;
}
