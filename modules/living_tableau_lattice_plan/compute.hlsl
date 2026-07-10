struct PrimitiveRecord { float2 p0; float2 p1; float3 color; float width; float kind; float group_id; float route_t; float active; };
RWStructuredBuffer<PrimitiveRecord> Out:register(u0);
float wave(float x,float y,float p){return sin(x*1.7+p*6.283)*cos(y*1.3-p*6.283)*0.018;}
float2 gp(int c,int r,float p){float2 q=float2(0.08+c*0.035+r*0.012,0.61+r*0.027+c*0.011);q.y+=wave(c,r,p);float2 uiOffset=float2(composition_offset.x,-composition_offset.y);return q*composition_scale+uiOffset+_Data0[0].drift;}
[numthreads(64,1,1)] void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=192)return;PrimitiveRecord o=(PrimitiveRecord)0;o.active=0;float p=_Data0[0].phase;int cols=detail==0?8:(detail==1?11:13);int rows=detail==0?7:(detail==1?10:12);int pts=cols*rows;
if(i<(uint)pts){int c=i%cols,r=i/cols;o.p0=o.p1=gp(c,r,p);o.color=float3(.68,1,.72);o.width=.0022;o.kind=2;o.group_id=r;o.route_t=fmod((float)(c+r*3),10);o.active=1;}
else{uint j=i-pts;int hcount=(cols-1)*rows;if(j<(uint)hcount){int c=j%(cols-1),r=j/(cols-1);o.p0=gp(c,r,p);o.p1=gp(c+1,r,p);o.group_id=r;o.route_t=(float)c/max((float)(cols-1),1.0);o.active=1;}else{j-=hcount;int vcount=cols*(rows-1);if(j<(uint)vcount){int c=j%cols,r=j/cols;o.p0=gp(c,r,p);o.p1=gp(c,r+1,p);o.group_id=32+c;o.route_t=(float)r/max((float)(rows-1),1.0);o.active=1;}}o.color=float3(.38,1,.72);o.width=.0011;o.kind=0;}
Out[i]=o;}
