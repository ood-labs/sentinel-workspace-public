struct PrimitiveRecord { float2 p0; float2 p1; float3 color; float width; float kind; float group_id; float route_t; float active; };RWStructuredBuffer<PrimitiveRecord>Out:register(u0);
// Convert the Cartesian point2D offset once at the UV boundary.
float2 tx(float2 p){float2 uiOffset=float2(composition_offset.x,-composition_offset.y);return p*composition_scale+uiOffset+_Data0[0].drift;}
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=128)return;PrimitiveRecord o=(PrimitiveRecord)0;o.active=0;float p=_Data0[0].phase;
if(i<8){float2 corners[4]={float2(.43,.25),float2(.78,.39),float2(.78,.69),float2(.43,.55)};uint e=i%4;o.p0=tx(corners[e]);o.p1=tx(corners[(e+1)%4]);if(i>=4){o.p0+=float2(.012,.008);o.p1+=float2(.012,.008);}o.color=float3(.95,.16,.03);o.width=.0012;o.kind=0;o.group_id=i/4;o.route_t=e/4.0;o.active=1;}
else if(i<88){uint j=i-8;uint lane=j/20,seg=j%20;float t0=seg/20.0,t1=(seg+1)/20.0;float x0=.455+t0*.30,x1=.455+t1*.30;float base=.35+lane*.045;float ph=6.283*(t0*1.4-p*2+lane*.19);o.p0=tx(float2(x0,base+sin(ph)*.018));o.p1=tx(float2(x1,base+sin(ph+0.32)*.018));o.color=lane%2?float3(.12,.75,1):float3(.18,1,.8);o.width=.0014;o.kind=0;o.group_id=10+lane;o.route_t=t0;o.active=1;}
else{uint j=i-88;float col=j%10,row=j/10;o.p0=o.p1=tx(float2(.61+col*.018,.31+row*.022));o.color=float3(.75,1,.55);o.width=.002;o.kind=2;o.group_id=40+row;o.route_t=fmod(j+floor(p*10),10);o.active=j<(detail==0?20:(detail==1?32:40));}
Out[i]=o;}
