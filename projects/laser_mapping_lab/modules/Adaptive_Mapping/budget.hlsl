StructuredBuffer<float4> Counts:register(t0);
RWStructuredBuffer<float4> Plan:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 uint n=SOURCE_COUNT>0?(uint)SOURCE[0].endpoints.x:0;bool ok=SOURCE_COUNT>n&&n<=1023&&_Data1_Count==577&&_Data1[DEST*577].value.x>.5&&_Data1[DEST*577+32].value.y==5151;
 if(SOURCE_COUNT>0)ok=ok&&all(isfinite(SOURCE[0].endpoints))&&SOURCE[0].endpoints.x==floor(SOURCE[0].endpoints.x)&&SOURCE[0].endpoints.x>=0&&SOURCE[0].endpoints.y>0&&SOURCE[0].endpoints.z>0;
 // A Calibration is the mapping (0..31) plus zoning masks (32..64) and polygon points (65..576); every element must be finite.
 if(_Data1_Count==577){ok=ok&&_Data1[DEST*577].value.y>0;[loop]for(uint c=0;c<577;c++)ok=ok&&all(isfinite(_Data1[DEST*577+c].value));}
 uint totals[12];[unroll]for(uint k=0;k<12;k++)totals[k]=0;uint hits=0;
 [loop]for(uint i=0;i<min(n,1023u);i++){[unroll]for(uint k=0;k<12;k++)totals[k]+=(uint)Counts[i*4+k/4][k%4];hits+=(uint)Counts[i*4+3].x;ok=ok&&Counts[i*4+3].y>.5;}
 uint level=0;[loop]while(level<11&&totals[level]>(uint)record_budget)level++;
 uint count=totals[level];uint status=!ok?3:(count>1023?2:((level>0||hits>0||count>(uint)record_budget)?1:0));
 Plan[0]=float4(n,count,level,status);Plan[1]=float4(tolerance,tolerance*exp2((float)level),hits,0);
 uint offset=1;[loop]for(uint i=0;i<min(n,1023u);i++){uint count=(uint)Counts[i*4+level/4][level%4];Plan[i+4]=float4(offset,count,0,0);offset+=count;}
}
