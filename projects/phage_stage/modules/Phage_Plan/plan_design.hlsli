// The Design record reader for the plan itself: parameters + stance + hand edits.
// Record order is the PhDesign layout in _shared/phage_anatomy.hlsli; downstream nodes read the
// published Design buffer instead. `E` (the edit state buffer) is declared by the including pass.
#define PLAN_VERSION 3
#define PLAN_MAGIC 260929
float4 stanceOffset(){ // knee radius, knee height, foot radius, ankle height
 return stance==1?float4(1.6,2.6,2.4,0):stance==2?float4(-1.2,3.6,.4,.3):stance==3?float4(2.6,-2.2,3.2,-.4):float4(0,0,0,0);}
float4 phD(uint i){
 float4 so=stanceOffset();
 if(i==0)return float4(plate_height,plate_radius,plate_inner,plate_depth);
 if(i==1)return float4(sheath_radius,collar_height,collar_radius,capsid_size);
 if(i==2)return float4(capsid_stretch,knee_radius+so.x,knee_height+so.y,foot_radius+so.z);
 if(i==3)return float4(ankle_height+so.w,booth_radius,booth_height,riser_height);
 if(i==4)return float4(riser_width,riser_depth,leg_truss,capsid_truss);
 if(i==5)return float4(ring_truss,mover_scale,strobe_length,spike_radius);
 if(i==6)return float4(plate_outer_movers,plate_inner_movers,capsid_movers?1:0,knee_movers);
 if(i==7)return float4(collar_movers,booth_movers,foot_movers?1:0,0);
 if(i==8)return float4(collar_strobes,plate_strobes,knee_strobes?1:0,foot_strobes?1:0);
 if(i==9)return float4(capsid_strobes?1:0,booth_strobes,0,0);
 if(i>=10&&i<16)return E[4+i-10];
 if(i==16)return float4(PLAN_VERSION,E[0].x,E[3].x,PLAN_MAGIC);
 return 0;
}
