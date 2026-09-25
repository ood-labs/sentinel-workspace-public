struct RoomSettings{float4 fill,material,tint,bounds,finish;};
RWStructuredBuffer<RoomSettings> O:register(u0);
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){RoomSettings r;r.fill=float4(ambient,crowd_fill,truss_fill,surface_spill);r.material=float4(metal_roughness,metal_reflection,floor_roughness,floor_reflection);r.tint=float4(fill_color,led_spill);r.bounds=float4(width,length,height,floor_level);r.finish=float4(floor_wear,wall_texture,0,0);O[0]=r;}
