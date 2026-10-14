// BR_Render / resolve.hlsl -- the beams composited, then temporal accumulation.
//
// The shaded frame is jittered by a Halton(2,3) sub-pixel offset (prep.hlsl); this pass
// reprojects the history into it, clips the history to the frame's 3x3 neighbourhood in YCoCg,
// and blends. While the camera holds still the blend weight falls as 1/(n+1) toward a floor, so a
// still frame converges to a supersampled, noise-free image; the moment the camera moves the
// weight jumps back up. Alpha carries the reprojection depth onward (BR_Lens uses it).
//
// Every input here was written by another pass a cook earlier -- this build hands a pass the
// other passes' buffers one cook late per hop -- and each one carries the camera it was rendered
// with (br_camtexels.hlsli):
//   hdr       the shaded image (shade.hlsl). Alpha: how far along its eye ray each pixel's image
//             sits (the surface; a sheer, the trees, a mirror's virtual image), negative where
//             moving emission (the flames) must keep a short history
//   foghist   the accumulated beams (fogtaa.hlsl), usually a cook OLDER than hdr. Alpha packs
//             transmittance with each texel's ray length (fogPack)
//   history   this pass's own output from the last cook
// The beams and the history are brought into the shaded image's camera by reprojection. Nothing
// here asks the live camera or the G-buffer, which belong to other frames than this image. When
// the history's camera came from the scene buffer instead, every fetch in motion landed a frame's
// motion off, was clipped away, and the raw jittered frame flickered through everywhere.
#include "render_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 toYCoCg(float3 c) { return float3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b, 0.5 * c.r - 0.5 * c.b, -0.25 * c.r + 0.5 * c.g - 0.25 * c.b); }
float3 fromYCoCg(float3 y) { return float3(y.x + y.y - y.z, y.x + y.z, y.x - y.y - y.z); }

// tonemapped-domain weights keep fireflies from dominating the neighbourhood box
// Reversible Karis weighting. The inverse is BOUNDED: clamping in YCoCg can return an RGB triple
// whose max channel reaches 1, and an unbounded 1/(1-max) then grows history by ~1e4 per frame
// until it is infinite -- which the preview's tonemap turns into NaN and shows as black.
float3 compress(float3 c) { return c / (1.0 + max(c.r, max(c.g, c.b))); }
float3 expand(float3 c) { float m = min(max(c.r, max(c.g, c.b)), 0.985); return max(c, 0.0) / (1.0 - m); }

// the shaded image at a pixel (its header texels read as the row below)
float4 hdrAt(int2 p, int2 maxP)
{
    p = clamp(p, int2(0, 0), maxP);
    if (isCamTexel(p)) p.y = 1;
    return _Tex1.Load(int3(p, 0));
}

// The beams in front of world point w, as the beam image saw it: a 4x4 tent over the
// quarter-resolution texels around where w lands in the beams' camera, weighted by how close each
// texel's own ray length is to the distance of w (through a window: to where that ray leaves the
// room box, as fog.hlsl marched it). A texel whose ray ran PAST w is shortened to it (in-scatter
// and extinction scale with the path), so a leaf in front of a sunbeam takes the little light in
// front of it, not the whole shaft behind it. Returns (in-scatter rgb, transmittance).
float4 beamsAt(CamHdr fc, float3 w, int2 FQ)
{
    float2 fuv;
    if (!fc.ok || !camProject(fc, w, fuv)) return float4(0, 0, 0, 1);
    float3 dv = w - fc.eye;
    float dP = length(dv);
    if (insideRoomBox(fc.eye, 0.0))
    {
        float3 fN;
        dP = min(dP, boxExit(fc.eye, dv / max(dP, 1e-5), fN));
    }
    dP = max(dP, 0.02);
    float2 q = fuv * float2(FQ) - 0.5;
    int2 q0 = (int2)floor(q);
    float2 fq = q - (float2)q0;
    int2 maxF = FQ - 1;
    float4 sum = 0;
    float ws = 0.0;
    float4 best = float4(0, 0, 0, 1);
    float bestE = 1e9;
    [unroll] for (int j = -1; j <= 2; j++)
    [unroll] for (int i = -1; i <= 2; i++)
    {
        int2 f = clamp(q0 + int2(i, j), int2(0, 0), maxF);
        if (isCamTexel(f)) f.y = 1;
        float4 v = _Tex2.Load(int3(f, 0));
        float2 u = fogUnpack(v.a);
        float dS = max(u.y, 0.02);
        float4 s = float4(v.rgb, u.x);
        float k = saturate(dP / dS);
        if (k < 0.999) { s.rgb *= k; s.a = pow(max(s.a, 1e-4), k); }
        float2 dq = abs(float2((float)i, (float)j) - fq);
        float wS = max(0.0, 1.0 - dq.x * 0.5) * max(0.0, 1.0 - dq.y * 0.5);
        float e = abs(log(dS / dP));                 // relative depth gap
        float wgt = wS * exp(-e * e * 60.0);
        sum += s * wgt; ws += wgt;
        if (e < bestE) { bestE = e; best = s; }
    }
    float4 o = (ws > 1e-4) ? sum / ws : best;
    bool ok = abs(o.r) < 6e4 && abs(o.g) < 6e4 && abs(o.b) < 6e4 && abs(o.a) < 4.0;
    return ok ? float4(max(o.rgb, 0.0), saturate(o.a)) : float4(0, 0, 0, 1);
}

// History through a 5-tap Catmull-Rom (the bicubic's corner taps dropped and renormalised).
// Bilinear history resampled every frame blurs a moving image a little more each frame, which is
// what forced a short history in motion; this keeps it sharp enough to trust for longer.
float3 historyAt(float2 uv, float2 res)
{
    float2 sp = uv * res;
    float2 t1 = floor(sp - 0.5) + 0.5;
    float2 f = sp - t1;
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 w12 = w1 + w2;
    float2 t12 = (t1 + w2 / max(w12, 1e-5)) / res;
    float2 t0 = (t1 - 1.0) / res, t3 = (t1 + 2.0) / res;
    float3 c = _Tex4.SampleLevel(LinearSampler, float2(t12.x, t0.y), 0).rgb * (w12.x * w0.y)
             + _Tex4.SampleLevel(LinearSampler, float2(t0.x, t12.y), 0).rgb * (w0.x * w12.y)
             + _Tex4.SampleLevel(LinearSampler, float2(t12.x, t12.y), 0).rgb * (w12.x * w12.y)
             + _Tex4.SampleLevel(LinearSampler, float2(t3.x, t12.y), 0).rgb * (w3.x * w12.y)
             + _Tex4.SampleLevel(LinearSampler, float2(t12.x, t3.y), 0).rgb * (w12.x * w3.y);
    float wsum = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(c / max(wsum, 1e-4), 0.0);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    float2 res = float2(W, H);
    int2 pix = int2(tid.xy);
    // The shaded image fills only the render region (render_common: renderRes); this pass and its
    // history are full resolution. Below full scale it is a temporal UPSCALER: rendered pixel q was
    // cast through (q + 0.5 + jitter) / RR, so each output pixel knows where this frame's samples
    // fell around it, reconstructs from them, and takes them into its history in proportion to how
    // close the nearest one landed. The jitter sweeps every sample across the output pixels it
    // covers, so a still frame converges to full resolution.
    int2 RR = renderRes(int2(W, H));
    int2 maxP = RR - 1;
    float2 up = res / float2(RR);                  // output pixels per rendered pixel
    bool scaled = RR.x < (int)W || RR.y < (int)H;
    float4 fr = scFrame();
    CamHdr hc = camHeader(_Tex1);                 // the shaded image's camera
    if (!hc.ok) hc = camLive(_ViewProjMatrix, _InvViewProjMatrix, _CameraPos, fr.yz, fr.x);
    // the history this pass writes describes that image: its camera travels on with it
    if (isCamTexel(pix)) { OutputUAV[tid.xy] = camHeaderTexel(hc, pix.x); return; }
    uint FW, FH;
    _Tex2.GetDimensions(FW, FH);
    CamHdr fc = camHeader(_Tex2);                 // the beams' camera
    CamHdr pc = camHeader(_Tex4);                 // the history's camera

    float2 lp = (float2(pix) + 0.5) / up - 0.5 - hc.jit.xy;      // in rendered pixels; integers are samples
    int2 q0 = scaled ? clamp((int2)round(lp), int2(0, 0), maxP) : pix;
    float4 hp = hdrAt(q0, maxP);
    float depth = clamp(abs(hp.a), 0.02, 480.0);
    float dyn = (hp.a < 0.0) ? 1.0 : 0.0;
    float3 ro, rd;
    camRay(hc, float2(pix), res, float2(0, 0), ro, rd);
    float3 wp = ro + rd * depth;
    float4 beams = beamsAt(fc, wp, int2(FW, FH));
    float3 cur = hp.rgb * beams.a + beams.rgb;

    // the neighbourhood under this pixel's beams (they change little across three pixels); scaled,
    // the same nine samples also reconstruct this pixel (a Gaussian over where each one fell, in
    // output pixels, half a rendered pixel wide) and say how close the nearest landed
    float3 mn = 1e9, mx = -1e9, m1 = 0, m2 = 0;
    float3 rec = 0, nearC = 0;
    float rw = 0.0, near2 = 1e9;
    float sig2 = 2.0 * (0.5 * up.x) * (0.5 * up.x);
    [unroll] for (int j = -1; j <= 1; j++)
    [unroll] for (int i = -1; i <= 1; i++)
    {
        int2 q = q0 + int2(i, j);
        float3 cc = compress(hdrAt(q, maxP).rgb * beams.a + beams.rgb);
        float3 c = toYCoCg(cc);
        mn = min(mn, c); mx = max(mx, c);
        m1 += c; m2 += c * c;
        float2 dq = ((float2)clamp(q, int2(0, 0), maxP) - lp) * up;
        float d2 = dot(dq, dq);
        float wq = exp(-d2 / sig2);
        rec += cc * wq; rw += wq;
        if (d2 < near2) { near2 = d2; nearC = cc; }
    }
    m1 /= 9.0; m2 /= 9.0;
    // History takes the NEAREST sample as it is, in proportion to how close it landed (within half
    // an output pixel it counts in full, between pixels barely at all), so detail converges sharp;
    // taking the reconstruction there averaged neighbours two pixels away into every pixel. The
    // reconstruction only stands in where there is no history to keep.
    float conf = scaled ? exp(-near2 * 2.0) : 1.0;
    float3 curH = scaled ? expand(nearC) : cur;
    if (scaled) cur = expand(rec / max(rw, 1e-5));
    float3 sd = sqrt(max(m2 - m1 * m1, 0.0));
    // still means the history shares this image's camera (the scene's still-count arrives late)
    bool camMoved = !pc.ok || camDelta(hc, pc) > 1e-6;
    float staticF = camMoved ? 0.0 : fr.w;
    // a moving camera clips history to the current neighbourhood, but not so tightly that the
    // box itself -- built from this frame's noise -- decides every pixel
    float k = (staticF > 3.0) ? 1.6 : 1.25;
    float3 bmin = max(mn, m1 - sd * k), bmax = min(mx, m1 + sd * k);

    float2 puv = float2(0, 0);
    bool onScreen = pc.ok && camProject(pc, wp, puv);
    // never fetch history from the header texels: a point that sat beside them reads just below
    // (dropping its history instead left the corner raw and flickering)
    if (nearCamTexels(puv * res)) puv.y = max(puv.y, 3.5 / res.y);

    float3 outc = cur;
    // Scope (17) shows the beauty, so it accumulates like it
    if (taa != 0 && onScreen && fr.x > 2.0 && (view == 0 || view == 17))
    {
        float3 hist = historyAt(puv, res);
        // magnitude test, not x == x: fast-math may fold a NaN self-compare to true
        bool histOk = abs(hist.r) < 1e4 && abs(hist.g) < 1e4 && abs(hist.b) < 1e4;
        if (histOk)
        {
            float3 hy = toYCoCg(compress(hist));
            float3 hc3 = clamp(hy, bmin, bmax);
            // a still camera may trust history further: clip only what is clearly stale
            // a running trip moves the image under a still camera: clip fully and keep the history short
            float warpM = scFrameB().y;
            bool moving = warpM > 0.001;
            // (upscaling, that box spans twice the pixels and pulled converged detail back toward
            // the coarse frame every cook: a still, scaled image keeps nearly all its history)
            hy = (staticF > 3.0 && dyn < 0.5 && !moving) ? lerp(hc3, hy, scaled ? 0.98 : 0.5) : hc3;
            hist = expand(fromYCoCg(hy));
            // in motion, ~10 frames of reprojected history (was ~6: every per-frame noise showed)
            float alpha = (staticF > 1.0) ? max(1.0 / (staticF + 1.0), taa_floor) : 0.10;
            alpha = max(alpha, dyn * 0.45);
            // the trip moves surfaces under a still camera with no motion vectors: the clip above
            // catches what moved, so only a mild floor is needed (a strong one re-exposed all noise)
            if (moving) alpha = max(alpha, 0.05 + 0.05 * saturate(warpM * 2.0));
            outc = lerp(hist, curH, alpha * conf);
        }
    }
    if (view == 14)
    {
        // the beams alone: in-scattered light (x8); green where they block more than 95% of the room
        outc = beams.rgb * 8.0;
        if (beams.a < 0.05) outc = float3(0.0, 1.0, 0.0);
    }
    if (view == 13)
    {
        // TAA probe: left = the history as reprojected and clipped, right = (history found,
        // box floor Y, history Y in compressed space). Top-left swatches: did the shaded image,
        // the beams and the history each carry a readable camera (green) or not (red)?
        float3 hraw = historyAt(puv, res);
        bool ok = onScreen && abs(hraw.r) < 1e4 && abs(hraw.g) < 1e4 && abs(hraw.b) < 1e4;
        float3 hy = toYCoCg(compress(ok ? hraw : float3(0, 0, 0)));
        float3 hpr = expand(fromYCoCg(lerp(clamp(hy, bmin, bmax), hy, 0.5)));
        outc = (pix.x < (int)(W / 2)) ? hpr * 0.25 : float3(ok ? 1.0 : 0.0, bmin.x, hy.x);
        if (pix.y >= 4 && pix.y < 18 && pix.x < 46)
        {
            int s = pix.x / 16;
            bool g = (s == 0) ? camHeader(_Tex1).ok : ((s == 1) ? fc.ok : pc.ok);
            outc = ((pix.x % 16) >= 14) ? float3(0, 0, 0) : (g ? float3(0.1, 0.8, 0.2) : float3(0.9, 0.1, 0.1));
        }
    }
    bool outOk = abs(outc.r) < 6.0e4 && abs(outc.g) < 6.0e4 && abs(outc.b) < 6.0e4;
    outc = outOk ? max(outc, 0.0) : min(max(cur, 0.0), 6.0e4);
    OutputUAV[tid.xy] = float4(outc, depth);
}
