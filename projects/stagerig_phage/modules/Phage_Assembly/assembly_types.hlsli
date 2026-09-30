// Record types shared by the assembly passes.
#ifndef PH_ASSEMBLY_TYPES
#define PH_ASSEMBLY_TYPES
struct PhMember{float4 a;float4 b;float4 up;float4 meta;};
struct Tube{float4 a;float4 b;float4 cutA;float4 cutB;};   // a=(xyz,radius) b=(xyz,material)
struct PhSolid{float4 c;float4 x;float4 y;float4 z;};     // c=(centre,kind) x/y/z=(axis, half extent)
#define TRUSS_MEMBERS 138
#define TUBES_PER 96
#define TUBE_COUNT 13248
#define SOLID_COUNT 64
#endif
