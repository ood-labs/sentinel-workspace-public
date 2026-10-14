// Record types shared by the stage passes and the canvas.
#ifndef SS_STAGE_TYPES
#define SS_STAGE_TYPES
#include "../_shared/ss_slots.hlsli"
struct SsMember{float4 a;float4 b;float4 up;float4 meta;};   // a=(xyz,width) b=(xyz,kind) up=(xyz,profile) meta.w=section
struct Tube{float4 a;float4 b;float4 cutA;float4 cutB;};     // a=(xyz,radius) b=(xyz,material)
struct SsSolid{float4 c;float4 x;float4 y;float4 z;};        // c=(centre,kind + 10 material) x/y/z=(axis, half extent)
struct SsPiece{float4 a;float4 b;float4 n;float4 w;};        // a=(xyz,u0) b=(xyz,u1) n=(facing,run) w=(length,family,valid,piece)
#define TRUSS_MEMBERS SS_MEMBERS
#define TUBES_PER SS_TUBES_PER
#define TUBE_COUNT SS_TUBE_COUNT
#define SOLID_COUNT SS_SOLID_COUNT
#define KIND_FRONT 1
#define KIND_BACK 2
#define KIND_WALL 3
#define KIND_LEG 4
#define KIND_BLOCK 5
#endif
