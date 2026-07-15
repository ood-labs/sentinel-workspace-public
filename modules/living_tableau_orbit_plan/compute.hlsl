struct PrimitiveRecord { float2 p0; float2 p1; float3 color; float width; float kind; float group_id; float route_t; float active; };RWStructuredBuffer<PrimitiveRecord>Out:register(u0);
float2 orb(float a,float rx,float ry,float tilt){float2 q=float2(cos(a)*rx,sin(a)*ry);float c=cos(tilt),s=sin(tilt);return float2(c*q.x-s*q.y,s*q.x+c*q.y);}
// Convert the Cartesian point2D offset once at the UV boundary.
float2 tx(float2 p){float2 uiOffset=float2(composition_offset.x,-composition_offset.y);return p*composition_scale+uiOffset+_Data0[0].drift;}
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=128)return;PrimitiveRecord o=(PrimitiveRecord)0;o.active=0;float p=_Data0[0].phase;uint segs=detail==0?18:(detail==1?24:30);uint rings=3;uint lineCount=segs*rings;float2 center=float2(.74,.18);
if(i<lineCount){uint ring=i/segs,j=i%segs;float a0=6.2831853*j/segs,a1=6.2831853*(j+1)/segs;float rr=.055+ring*.026;o.p0=tx(center+orb(a0,rr,rr*(.45+.15*ring),-.35+ring*.32));o.p1=tx(center+orb(a1,rr,rr*(.45+.15*ring),-.35+ring*.32));o.color=float3(1,.18,.025);o.width=.0014;o.kind=0;o.group_id=ring;o.route_t=(float)j/segs;o.active=1;}
else if(i<lineCount+4){uint b=i-lineCount;float rr=.025+b*.025;float a=6.2831853*(p*(1+b*.22)+b*.29);o.p0=o.p1=tx(center+orb(a,rr,rr*(.55+b*.08),-.25+b*.19));o.color=b==0?float3(1,1,.45):float3(1,.75,.18);o.width=b==0?.008:.004;o.kind=1;o.group_id=10+b;o.route_t=p;o.active=1;}
Out[i]=o;}
