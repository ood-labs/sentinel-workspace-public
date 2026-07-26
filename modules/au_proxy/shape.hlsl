// AUTOPSIA — analysis lens. Two-source observation image, built so ONE Features
// node can resolve two different kinds of finding without them fighting:
//
//   MASSES  come from the specimen's density field. Smooth, peaked, separable —
//           thresholding high yields discrete nuclei instead of one merged web.
//   TEXTURE comes from the plate's inscription detail (contour lines, membranes).
//           Weighted deliberately BELOW the blob threshold so it never welds
//           masses together, but still carries the gradient structure that
//           corner detection needs.
//
// _Tex0 = Plate (inscription)   _Tex1 = Field (density)
RWTexture2D<float4> Shaped : register(u0);

float au_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float platLuma(float2 uv) {
    return au_luma(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    // ---- area-filtered sampling (1280x720 observed at 480x270) -------------
    float plate = 0.0;
    float dens = 0.0;
    float wsum = 0.0;
    [unroll] for (int oy = -1; oy <= 1; ++oy) {
        [unroll] for (int ox = -1; ox <= 1; ++ox) {
            float2 o = float2(ox, oy) * texel * (0.55 + preblur * 1.6);
            float wgt = (ox == 0 && oy == 0) ? 2.0 : 1.0;
            plate += platLuma(uv + o) * wgt;
            dens += _Tex1.SampleLevel(LinearSampler, uv + o, 0).r * wgt;
            wsum += wgt;
        }
    }
    plate /= max(wsum, 1e-5);
    dens /= max(wsum, 1e-5);

    // ---- inscription detail: local-mean subtraction isolates the strokes ---
    float mean = 0.0;
    [unroll] for (int k = 0; k < 8; ++k) {
        float a = (float)k * 0.7853981634;
        float2 o = float2(cos(a), sin(a)) * texel * max(local_radius, 0.5) * 4.0;
        mean += platLuma(uv + o);
    }
    mean /= 8.0;
    float detail = max(plate - mean, 0.0);

    // ---- nucleus separation (top-hat) --------------------------------------
    // Raw density leaves touching cells welded into one connected component and
    // lets a bright landmass swallow its neighbours. Subtracting the local mean
    // of the density at roughly one cell radius isolates each local maximum, so
    // the instrument resolves INDIVIDUAL nuclei instead of colonies.
    float densMean = 0.0;
    [unroll] for (int m = 0; m < 8; ++m) {
        float a = (float)m * 0.7853981634 + 0.3926990817;
        float2 o = float2(cos(a), sin(a)) * texel * max(sep_radius, 0.5);
        densMean += _Tex1.SampleLevel(LinearSampler, uv + o, 0).r;
    }
    densMean /= 8.0;

    float sep = saturate((dens - densMean * separation) * mass_gain);
    float mass = pow(sep, max(mass_gamma, 0.05));

    float shaped = saturate(mass + detail * line_texture + analysis_bias);

    Shaped[tid.xy] = float4(shaped, shaped, shaped, 1.0);
}
