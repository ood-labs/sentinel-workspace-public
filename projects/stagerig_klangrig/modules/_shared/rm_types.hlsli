struct RmPlan{float3 position;float fixture_id;float mount_pitch;float mount_roll;float base_visible;float active;float2 content_origin;float2 content_extent;float4 reserved;};
struct RmPose{float3 position;float fixture_id;float pan;float tilt;float target_pan;float target_tilt;float mount_pitch;float mount_roll;float active;float motion_mode;float2 content_origin;float2 content_extent;float4 reserved;};
struct RmOptical{float3 position;float fixture_id;float3 normal;float local_id;float3 colour;float intensity;float beam_tangent;float field_tangent;float reach;float active;float frost;float3 padding;};
float3 rmX(float3 p,float a){float s=sin(a),c=cos(a);return float3(p.x,c*p.y-s*p.z,s*p.y+c*p.z);}
float3 rmY(float3 p,float a){float s=sin(a),c=cos(a);return float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);}
float3 rmZ(float3 p,float a){float s=sin(a),c=cos(a);return float3(c*p.x-s*p.y,s*p.x+c*p.y,p.z);}
float3 rmMount(float3 p,RmPose r){return rmZ(rmX(p,r.mount_pitch),r.mount_roll);}
float3 rmHeadPoint(float3 p,RmPose r){return r.position+rmMount(float3(0,.075,0)+rmY(float3(0,.152,0)+rmX(p,r.tilt),r.pan),r);}
float3 rmHeadNormal(float3 n,RmPose r){return rmMount(rmY(rmX(n,r.tilt),r.pan),r);}
