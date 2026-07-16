struct MaterialRecord {
    float3 base_color;
    float roughness;
    float3 secondary_color;
    float metallic;
    float texture_scale;
    float texture_strength;
    float pattern_id;
    float emissive;
    float specular;
    float normal_strength;
    float seed;
    float reserved;
};

RWStructuredBuffer<MaterialRecord> OutputBuffer : register(u0);

MaterialRecord makeMaterial(float3 baseColor, float roughnessValue, float3 secondaryColor,
                            float metallicValue, float textureScale, float textureStrength,
                            float patternId, float emissiveValue, float specularValue,
                            float normalStrength, float seedValue)
{
    MaterialRecord m;
    m.base_color = baseColor;
    m.roughness = roughnessValue;
    m.secondary_color = secondaryColor;
    m.metallic = metallicValue;
    m.texture_scale = textureScale;
    m.texture_strength = textureStrength;
    m.pattern_id = patternId;
    m.emissive = emissiveValue;
    m.specular = specularValue;
    m.normal_strength = normalStrength;
    m.seed = seedValue;
    m.reserved = 0.0;
    return m;
}

[numthreads(32, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= 24) return;

    MaterialRecord m = makeMaterial(float3(0.5, 0.5, 0.5), 0.65, float3(0.35, 0.35, 0.35),
                                    0.0, 4.0, 0.1, 0.0, 0.0, 0.25, 0.0, (float)i * 17.0);
    if (i == 0)  m = makeMaterial(oak_color, .48, oak_color * float3(.46,.54,.62), 0, 3.2, .72, 1, 0, .42, .22, 11);
    if (i == 1)  m = makeMaterial(plaster_color, .90, plaster_color * 1.08, 0, 1.7, .22, 2, 0, .12, .08, 23);
    if (i == 2)  m = makeMaterial(accent_wall_color, .86, accent_wall_color * .72, 0, 2.2, .28, 2, 0, .14, .10, 31);
    if (i == 3)  m = makeMaterial(float3(.055,.065,.072), .28, float3(.14,.16,.18), .78, 8, .32, 3, 0, .72, .12, 43);
    if (i == 4)  m = makeMaterial(float3(.30,.48,.62), .08, float3(.72,.88,1.0), .08, 1, .12, 4, .10, .95, .03, 47);
    if (i == 5)  m = makeMaterial(walnut_color, .42, walnut_color * float3(.42,.55,.68), 0, 4.5, .66, 1, 0, .48, .18, 59);
    if (i == 6)  m = makeMaterial(rug_color, .94, rug_color * .54, 0, 7.0, .44, 5, 0, .06, .26, 61);
    if (i == 7)  m = makeMaterial(sofa_color, .88, sofa_color * 1.18, 0, 18, .58, 6, 0, .08, .34, 71);
    if (i == 8)  m = makeMaterial(chair_color, .52, chair_color * float3(.48,.55,.62), 0, 12, .46, 7, 0, .38, .22, 73);
    if (i == 9)  m = makeMaterial(walnut_color * .76, .34, walnut_color * .30, 0, 5.5, .62, 1, 0, .52, .14, 79);
    if (i == 10) m = makeMaterial(float3(.016,.020,.026), .16, float3(.08,.10,.13), .18, 1, .10, 4, 0, .92, .02, 83);
    if (i == 11) m = makeMaterial(float3(.055,.060,.065), .82, float3(.015,.018,.022), 0, 20, .34, 8, 0, .08, .08, 89);
    if (i == 12) m = makeMaterial(ceramic_color, .66, ceramic_color * .72, 0, 5, .26, 2, 0, .25, .08, 97);
    if (i == 13) m = makeMaterial(brass_color, .24, brass_color * .45, .82, 10, .36, 3, 0, .86, .10, 101);
    if (i == 14) m = makeMaterial(float3(.16,.20,.15), .75, float3(.07,.09,.065), 0, 5, .32, 2, 0, .12, .14, 103);
    if (i == 15) m = makeMaterial(leaf_color, .72, leaf_color * float3(.35,.55,.31), 0, 8, .52, 9, 0, .16, .28, 107);
    if (i == 16) m = makeMaterial(float3(.075,.045,.028), .48, float3(.20,.12,.055), 0, 7, .46, 1, 0, .44, .12, 109);
    if (i == 17) m = makeMaterial(art_a_color, .70, art_b_color, 0, 3.5, .92, 10, 0, .16, .08, 113);
    if (i == 18) m = makeMaterial(art_b_color, .72, accent_color, 0, 4.2, .88, 11, 0, .15, .08, 127);
    if (i == 19) m = makeMaterial(accent_color, .92, accent_color * .62, 0, 20, .58, 6, 0, .06, .32, 131);
    if (i == 20) m = makeMaterial(linen_color, .88, linen_color * .72, 0, 16, .40, 6, .18, .10, .20, 137);
    if (i == 21) m = makeMaterial(float3(1.0,.53,.20), .18, float3(1.0,.80,.45), 0, 1, 0, 0, 6.0, .20, 0, 139);
    if (i == 22) m = makeMaterial(float3(.68,.48,.27), .82, float3(.94,.84,.65), 0, 14, .48, 12, 0, .08, .12, 149);
    if (i == 23) m = makeMaterial(float3(.56,.18,.10), .72, float3(.10,.25,.31), 0, 9, .62, 13, 0, .12, .08, 151);
    OutputBuffer[i] = m;
}
