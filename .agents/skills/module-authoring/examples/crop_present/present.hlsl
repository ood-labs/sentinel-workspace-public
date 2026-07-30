// Crop Present — node B of the node-to-node float output test.
//
// Read the cropped float coordinates published by node A (crop_select) on slot 0
// (_Tex0: R = x, G = y) and visualize them. The R/G channels show the received
// coordinates directly as a gradient (proving the cropped UV data crossed the graph
// link intact), and the blue channel draws fine concentric rings through those
// coordinates. The rings are what make precision visible: continuous float coordinates
// give smooth rings, but if the upstream node-to-node boundary had been 8-bit (256
// levels) the rings would stair-step into visible bands. Output is plain 8-bit (this
// module declares no output_format), proving a float intermediary can hand precision
// to an 8-bit node.
//
// _Tex0 (Texture2D<float4>), PointSampler, and VS_OUTPUT (.Uv) are injected by the
// module compiler.

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    float2 uv = _Tex0.SampleLevel(PointSampler, In.Uv, 0).rg;

    // Concentric rings through the received coordinates. The frequency is tuned so a
    // full [0,1] coordinate range shows ~12 smooth rings; under 8-bit quantization the
    // same sweep collapses onto stepped radii and the rings band.
    float r     = length(uv - 0.5);
    float rings = 0.5 + 0.5 * sin(r * 110.0);

    return float4(saturate(uv.x), saturate(uv.y), rings, 1.0);
}
