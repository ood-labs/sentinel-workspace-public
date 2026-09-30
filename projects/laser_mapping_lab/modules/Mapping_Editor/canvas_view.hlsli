// One world unit occupies the same pixel distance on both axes.
float canvasScale(){return max(1,min(_Resolution.x,_Resolution.y));}
float2 canvasOffset(float2 uv){return (uv-.5)*_Resolution/canvasScale();}
float2 canvasWorld(float2 uv,float4 view){return canvasOffset(uv)/view.z+view.xy;}
float2 canvasPixel(float2 p,float4 view){return (p-view.xy)*view.z*canvasScale()+.5*_Resolution;}
