// Crop Select — node A of the node-to-node float output test.
//
// Read the float UV map (slot 0, _Tex0: R = x, G = y in [0,1]) and remap the output
// UV so the [crop_center +/- crop_size/2] sub-rectangle of the input fills the whole
// output. The sampled R/G coordinates are written straight to the render target.
//
// The manifest sets output_format: RGBA32F, so this pass's RT and the pipeline output
// texture are both 32-bit float. The cropped coordinates therefore leave this node at
// full precision and reach the next graph node unquantized; node B (crop_present)
// samples a fine pattern through them and any 8-bit truncation would band visibly.
//
// _Tex0 (Texture2D<float4>), PointSampler, and VS_OUTPUT (.Uv) are injected by the
// module compiler. crop_center_x / crop_center_y / crop_size come from the cbuffer.

float4 main(VS_OUTPUT In) : SV_TARGET0
{
    // Map the output pixel (In.Uv in [0,1]) into the cropped input sub-rect.
    float2 cropMin = float2(crop_center_x, crop_center_y) - crop_size * 0.5;
    float2 srcUv   = cropMin + In.Uv * crop_size;

    float2 uv = _Tex0.SampleLevel(PointSampler, srcUv, 0).rg;
    return float4(uv, 0.0, 1.0);
}
