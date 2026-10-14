// SS_Stage / pieces - the pixel runs' straight pieces, SS_BAR_SEGS per run (Kinetics' Bar Pieces layout in PHAGE):
// u runs 0..1 along the whole run by length, so content flows continuously across pieces.
#include "stage_types.hlsli"
#include "../_shared/ss_stage.hlsli"
RWStructuredBuffer<SsPiece> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=SS_BARS*SS_BAR_SEGS)return;
 SsPiece p;p.a=SS_PIECE_DATA[i*4];p.b=SS_PIECE_DATA[i*4+1];p.n=SS_PIECE_DATA[i*4+2];p.w=SS_PIECE_DATA[i*4+3];O[i]=p;}
