// Show State for every PHAGE consumer (layout in phage_show.hlsli). Musical time comes from the
// Clock conductor through expressions on `beat`, `bpm` and `running`; nothing here integrates time.
// Lanes 1-3 are either computed here (Internal: repeat cycle/rest/offset in beats, like the Surface's
// REPEAT mode) or written every frame by the Surface (its STEPS sequencer). BUILD ramps from
// build_origin over build_beats while its pulses double every quarter; PHRASE turns once per phrase.
#include "../_shared/phage_show.hlsli"
RWStructuredBuffer<float4>S:register(u0);
float3 unpackRGB(float v){uint c=(uint)v;return float3((c>>16)&255,(c>>8)&255,c&255)/255.;}
float4 repeatLane(float b,float cycle,float rest,float offset){
 float period=max(.0625,cycle+rest),t=b-offset,m=t-floor(t/period)*period;
 bool active=running&&m<cycle;return float4(saturate(m/max(.0625,cycle)),active?1:0,floor(t/period),active?1-saturate(m/max(.0625,cycle)):0);}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 float b=max(0,beat);
 S[0]=float4(frac(b/max(.25,cycle_beats)),enabled?1:0,pulse_width,chase_spread);
 S[1]=float4(0,reverse?1:0,led_peak,lane_source);
 S[2]=float4(native_control,b,bpm,260934);
 if(lane_source==0){S[3]=repeatLane(b,lane1_cycle,lane1_rest,lane1_offset);S[4]=repeatLane(b,lane2_cycle,lane2_rest,lane2_offset);S[5]=repeatLane(b,lane3_cycle,lane3_rest,lane3_offset);}
 else{S[3]=float4(lane1_phase,lane1_active,lane1_trigger,lane1_envelope);S[4]=float4(lane2_phase,lane2_active,lane2_trigger,lane2_envelope);S[5]=float4(lane3_phase,lane3_active,lane3_trigger,lane3_envelope);}
 float bb=max(0,b-build_origin),r=saturate(bb/max(1,build_beats)),rate=exp2(min(3,floor(r*4)));
 S[6]=float4(frac(bb*rate),r,floor(bb*rate),r);
 float pb=max(0,b-phrase_origin)/max(1,phrase_beats);
 S[7]=float4(frac(pb),1,floor(pb),1-frac(pb));
 S[8]=float4(unpackRGB(palette_a),1);S[9]=float4(unpackRGB(palette_b),1);S[10]=float4(unpackRGB(palette_c),1);
 // Beat-locked strobe gate; a stopped transport falls back to wall time at the same tempo.
 float g=running?b*strobe_rate:_Time*strobe_rate*bpm/60;
 S[11]=float4(global_strobe?1:0,frac(g)<strobe_duty?1:0,blackout?1:0,r);
 S[12]=float4(strobe_rate,strobe_duty,kinetics?1:0,running?1:0);
}
