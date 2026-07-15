// face_stitch compute — reads MediaPipe Face Landmarks (data:0, {x,y,depth,confidence},
// normalized image space, y-down) and emits a PNode placement stream (one anchor per face
// feature) for a downstream atlas-stamp renderer. THE ONE coordinate transform (image→NDC,
// y-flip) lives here. Canonical MediaPipe-468 indices select eye/mouth/nose/brow/cheek anchors.
// PNode: 48 B — pos.xy, dir.xy, depth, u, v, weight, group, kind, seed, active.

struct PNode {
    float2 pos; float2 dir;
    float depth; float u; float v; float weight;
    float group; float kind; float seed; float active;
};
RWStructuredBuffer<PNode> NodesOut : register(u0);
// _Data0 (Face Landmarks, type _DataType_0 with fields x,y,depth,confidence) + _Data0_Count injected.

float2 lmNDC(uint i)
{
    uint c = (uint)_Data0_Count;
    if (c == 0u) return float2(0.0, 0.0);
    i = min(i, c - 1u);
    _DataType_0 d = _Data0[i];
    return float2(d.x * 2.0 - 1.0, 1.0 - d.y * 2.0);   // image(y-down) -> NDC(y-up)
}
float2 avg4(uint a, uint b, uint c, uint d){ return 0.25 * (lmNDC(a) + lmNDC(b) + lmNDC(c) + lmNDC(d)); }

[numthreads(16,1,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint id = DTid.x;
    if (id >= 16u) return;

    PNode n;
    n.pos = float2(0.0, 0.0); n.dir = float2(1.0, 0.0);
    n.depth = 0.0; n.u = 0.0; n.v = 0.0; n.weight = 0.12;
    n.group = 0.0; n.kind = 0.0; n.seed = (float)id; n.active = 0.0;

    bool haveFace = ((uint)_Data0_Count) >= 468u;
    float2 a, b;

    if (haveFace)
    {
        if (id == 0u) {            // right eye (image-left)
            n.pos = avg4(33, 133, 159, 145);
            a = lmNDC(33); b = lmNDC(133);
            n.dir = normalize(b - a + float2(1e-5, 0.0)); n.weight = length(b - a);
            n.kind = (float)right_eye_slot; n.group = 0.0; n.active = (float)enable_eyes;
        } else if (id == 1u) {     // left eye (image-right)
            n.pos = avg4(263, 362, 386, 374);
            a = lmNDC(362); b = lmNDC(263);
            n.dir = normalize(b - a + float2(1e-5, 0.0)); n.weight = length(b - a);
            n.kind = (float)left_eye_slot; n.group = 0.0; n.active = (float)enable_eyes;
        } else if (id == 2u) {     // mouth
            n.pos = avg4(61, 291, 13, 14);
            a = lmNDC(61); b = lmNDC(291);
            n.dir = normalize(b - a + float2(1e-5, 0.0)); n.weight = length(b - a) * 0.7;
            n.kind = (float)mouth_slot; n.group = 1.0; n.active = (float)enable_mouth;
        } else if (id == 3u) {     // nose
            n.pos = lmNDC(4);
            n.dir = float2(1.0, 0.0); n.weight = length(lmNDC(129) - lmNDC(358));
            n.kind = (float)nose_slot; n.group = 2.0; n.active = (float)enable_nose;
        } else if (id == 4u) {     // right brow
            n.pos = avg4(70, 63, 105, 66);
            a = lmNDC(70); b = lmNDC(107);
            n.dir = normalize(b - a + float2(1e-5, 0.0)); n.weight = length(b - a);
            n.kind = (float)brow_slot; n.group = 3.0; n.active = (float)enable_brows;
        } else if (id == 5u) {     // left brow
            n.pos = avg4(336, 296, 334, 293);
            a = lmNDC(300); b = lmNDC(336);
            n.dir = normalize(b - a + float2(1e-5, 0.0)); n.weight = length(b - a);
            n.kind = (float)brow_slot; n.group = 3.0; n.active = (float)enable_brows;
        } else if (id == 6u) {     // right cheek
            n.pos = lmNDC(205);
            n.weight = 0.16; n.kind = (float)patch_slot; n.group = 4.0; n.active = (float)enable_cheeks;
        } else if (id == 7u) {     // left cheek
            n.pos = lmNDC(425);
            n.weight = 0.16; n.kind = (float)patch_slot; n.group = 4.0; n.active = (float)enable_cheeks;
        }

        // single global align transform
        n.pos = n.pos * face_scale + offset;
        n.weight *= size_mul;
    }

    NodesOut[id] = n;
}
