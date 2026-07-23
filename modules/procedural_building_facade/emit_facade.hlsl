#include "types.hlsli"
StructuredBuffer<FacadeControlState> _Tex1 : register(t1);
RWStructuredBuffer<FacadeElement> OutputBuffer : register(u0);

FacadeElement emptyElement(){FacadeElement e;e.position=0;e.type_id=0;e.size=0;e.yaw=0;e.material_id=0;e.seed=0;e.emissive=0;e.active=0;e.uv=0;e.floor_index=0;e.bay_index=0;return e;}

[numthreads(64,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=id.x; if(i>=160u)return; FacadeElement e=emptyElement();
    if(_Data0_Count<3){OutputBuffer[i]=e;return;}
    float3 base=float3(_Data0[2].position[0],_Data0[2].position[1],_Data0[2].position[2]);
    float buildingW=_Data0[2].width,buildingH=_Data0[2].height,buildingD=_Data0[2].depth;
    uint fCount=(uint)max(floors,1),frontCount=fCount*(uint)max(front_bays,1),sidePerFace=fCount*(uint)max(side_bays,1);
    uint totalCount=min(frontCount+sidePerFace*2u,160u);
    if(i>=totalCount){OutputBuffer[i]=e;return;}

    float floorPitch=buildingH/(float)fCount,glazingH=floorPitch*window_height;
    float2 rhythmHandle=_Tex1[0].position,featureHandle=_Tex1[1].position;
    float2 rhythmN=saturate((rhythmHandle-FC_LOCAL_MIN)/max(FC_LOCAL_MAX-FC_LOCAL_MIN,1e-5));
    float2 featureN=saturate((featureHandle-FC_LOCAL_MIN)/max(FC_LOCAL_MAX-FC_LOCAL_MIN,1e-5));
    float rhythmX=rhythmN.x,rhythmY=rhythmN.y;
    float featureX=featureN.x,featureY=1.0-featureN.y;
    int mode=clamp(rhythm_mode,0,3);
    e.active=1;e.material_id=style==1?2.0:3.0;e.seed=(float)i*19.17+7.3;e.emissive=interior_glow*(.55+.45*frac(sin((float)i*14.31)*4517.23));

    if(i<frontCount){
        uint fl=i/(uint)front_bays,bay=i-fl*(uint)front_bays; float bayPitch=buildingW/(float)front_bays;
        float centerX=base.x-buildingW*.5+(bay+.5)*bayPitch;
        float floorN=fCount>1u?(float)fl/(float)(fCount-1u):0;
        if(mode==1){float stagger=(rhythmX-.5)*bayPitch*1.35*variation;centerX+=((fl&1u)==0u?-1.0:1.0)*stagger;}
        centerX=clamp(centerX,base.x-buildingW*.5+bayPitch*.25,base.x+buildingW*.5-bayPitch*.25);
        float widthScale=1.0+(rhythmY-.5)*(floorN-.5)*variation*1.5;
        if(mode==2)widthScale*=lerp(.72,1.18,(float)((bay+fl)&1u));
        if(mode==3&&fl>fCount*2u/3u&&(bay<1u||bay>(uint)front_bays-2u))e.active=0;
        uint featureBay=min((uint)(featureX*(float)front_bays),(uint)front_bays-1u);
        uint featureFloor=min((uint)(featureY*(float)fCount),fCount-1u);
        bool feature=(bay==featureBay&&fl==featureFloor);
        e.position=float3(centerX,base.y+(fl+.5)*floorPitch,base.z+buildingD*.5+facade_offset);
        e.size=float3(bayPitch*window_width*widthScale*(feature?1.22:1.0),glazingH*(feature?1.18:1.0),.10+reveal_depth);
        e.yaw=0;e.type_id=(float)mode;e.uv=float2((bay+.5)/(float)front_bays,(fl+.5)/(float)fCount);e.floor_index=(float)fl;e.bay_index=(float)bay;
        if(feature){e.emissive=max(e.emissive,.92);e.material_id=3.0;}
    }else{
        uint j=i-frontCount,face=j/sidePerFace,rem=j-face*sidePerFace,fl=rem/(uint)side_bays,bay=rem-fl*(uint)side_bays;
        float bayPitch=buildingD/(float)side_bays,sideSign=face==0u?-1.0:1.0;
        float widthScale=mode==2?lerp(.76,1.12,(float)((bay+fl)&1u)):1.0;
        e.position=float3(base.x+sideSign*(buildingW*.5+facade_offset),base.y+(fl+.5)*floorPitch,base.z-buildingD*.5+(bay+.5)*bayPitch);
        e.size=float3(bayPitch*window_width*widthScale,glazingH,.10+reveal_depth);e.yaw=1.5707963;e.type_id=4.0+(float)mode;
        e.uv=float2((bay+.5)/(float)side_bays,(fl+.5)/(float)fCount);e.floor_index=(float)fl;e.bay_index=(float)bay;
    }
    OutputBuffer[i]=e;
}
