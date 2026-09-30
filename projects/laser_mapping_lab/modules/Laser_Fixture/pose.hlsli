float laneFor(uint projector){return float(projector)-float(clamp(projector_count,1,4)-1)*0.5;}
float fixtureGate(uint projector){
 if(!show_enabled)return 1;
 if(show_cue==0)return ((uint)floor(show_beat*.5)%4==projector)?1:0;
 if(show_cue==1)return ((uint)floor(show_beat*2)%4==projector)?1:.08;
 if(show_cue==2)return ((uint)floor(show_beat)%2==projector%2)?1:.12;
 if(show_cue==5)return ((uint)floor(show_beat*2)+projector)%2==0?1:.1;
 return 1;
}
float3 apertureFor(uint projector){return float3(position_x+laneFor(projector)*projector_spacing,position_y,position_z);}
float3 orientFixture(float3 d,uint projector){
 float p=radians(aim_pitch),y=radians(aim_yaw-laneFor(projector)*toe_in);
 d=float3(d.x,d.y*cos(p)+d.z*sin(p),d.z*cos(p)-d.y*sin(p));
 return float3(d.x*cos(y)+d.z*sin(y),d.y,d.z*cos(y)-d.x*sin(y));
}
