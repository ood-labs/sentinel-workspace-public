// VT_Composite / comp.hlsl — put the objects into the room.
//
// Three things happen here that no single renderer could do, because each needs the WHOLE
// object stack at once:
//   * a contact/drop shadow cast onto the wall and floor, derived from total coverage;
//   * a floor reflection, mirrored about the horizon the plan authority owns and compressed
//     the way a receding ground plane actually compresses one;
//   * the final over-composite.
//
// The horizon is read from the plan's stage record — the same number VT_Stage drew the seam
// at — so the reflection can never sit at a different height than the ground it reflects in.
#include "../_shared/vitrine.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
Texture2D<float4> Stage : register(t0);
Texture2D<float4> Stack : register(t1);
StructuredBuffer<PlanRec> Plan : register(t2);

#define TAP(T, UV) T[clamp(int2((UV) * _Resolution.xy), int2(0, 0), \
                           int2((int)_Resolution.x - 1, (int)_Resolution.y - 1))]

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pix = DTid.xy;
    if (pix.x >= (uint)_Resolution.x || pix.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pix + 0.5) / _Resolution.xy;

    float hz = clamp(Plan[PLAN_STAGE].pos.x, 0.05, 0.99);

    float3 col = Stage[pix].rgb;

    // ---------------------------------------------------------------- drop shadow
    // Offset down-right from the key, softened by a small ring of taps. It lands on whatever
    // is behind the objects, which is what glues the plates to the wall.
    if (shadow_amt > 0.001)
    {
        float2 off = float2(shadow_dx, shadow_dy);
        float s = 0.0;
        float r = max(shadow_blur, 0.0005);
        s += TAP(Stack, uv - off).a * 0.28;
        [unroll]
        for (int i = 0; i < 8; i++)
        {
            float ang = 6.2831853 * (float)i / 8.0;
            float2 d = float2(cos(ang), sin(ang)) * r;
            s += TAP(Stack, uv - off + d).a * 0.09;
        }
        s = saturate(s);
        col *= lerp(1.0, 1.0 - shadow_amt, s);
    }

    // ---------------------------------------------------------------- floor reflection
    if (uv.y > hz && refl_amt > 0.001)
    {
        float d = uv.y - hz;
        // A mirror in a receding plane does not flip 1:1 — the further below the seam a pixel
        // is, the further UP the source sits, so the reflection is vertically compressed.
        float2 src = float2(uv.x, hz - d * max(refl_squash, 0.05));

        float spread = refl_blur * d;
        float4 acc = TAP(Stack, src) * 0.34;
        float wsum = 0.34;
        [unroll]
        for (int i = 0; i < 6; i++)
        {
            float ang = 6.2831853 * (float)i / 6.0 + 0.4;
            float2 o = float2(cos(ang) * 1.4, sin(ang) * 0.6) * spread;
            acc += TAP(Stack, src + o) * 0.11;
            wsum += 0.11;
        }
        acc /= wsum;

        float fade = exp(-d * refl_falloff) * refl_amt;
        // the wet floor tints what it reflects toward its own colour
        float3 rc = lerp(acc.rgb, acc.rgb * refl_tint.rgb * 2.0, refl_tint_amt);
        col += rc * fade;
    }

    // ---------------------------------------------------------------- objects
    float4 st = Stack[pix];
    col = col * (1.0 - saturate(st.a)) + st.rgb;

    OutputUAV[pix] = float4(max(col, 0.0), 1.0);
}
