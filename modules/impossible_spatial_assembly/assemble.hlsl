struct PanelRecord {
    float2 center; float2 size;
    float angle; float depth; float kind; float palette;
    float group_id; float order_id; float fold; float pattern;
    float skew; float phase; float weight; float active;
};

struct FaceRecord {
    float2 center;
    float2 size;
    float2 axis_x;
    float2 axis_y;
    float depth;
    float face_kind;
    float palette;
    float pattern;
    float source_id;
    float group_id;
    float phase;
    float active;
};

StructuredBuffer<PanelRecord> PanelsIn : register(t0);
RWStructuredBuffer<FaceRecord> FacesOut : register(u0);

FaceRecord inactiveFace() {
    FaceRecord f = (FaceRecord)0;
    f.active = 0.0;
    return f;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint outIndex = tid.x;
    if (outIndex >= 288u) return;

    uint sourceIndex = outIndex / 3u;
    uint variant = outIndex - sourceIndex * 3u;
    PanelRecord p = PanelsIn[sourceIndex];
    if (p.active < 0.5) {
        FacesOut[outIndex] = inactiveFace();
        return;
    }

    float cs = cos(p.angle);
    float sn = sin(p.angle);
    float2 ax = float2(cs, sn);
    float2 ay = float2(-sn, cs);
    float2 liftDir = normalize(parallax_direction + float2(0.0001, 0.0001));
    float indexWave = sin((p.group_id * 0.71 + p.phase + motion_phase) * 6.2831853);
    float layerLift = p.depth * depth_spread;
    float hinge = p.fold * fold_gain + indexWave * motion_amount;

    FaceRecord f;
    f.center = p.center + liftDir * layerLift;
    f.size = p.size;
    f.axis_x = ax;
    f.axis_y = ay;
    f.depth = p.depth;
    f.face_kind = (float)variant;
    f.palette = p.palette;
    f.pattern = p.pattern;
    f.source_id = p.order_id;
    f.group_id = p.group_id;
    f.phase = p.phase;
    f.active = 1.0;

    if (variant == 0u) {
        f.center += ay * hinge * 0.014;
        f.size.x *= 1.0 + abs(hinge) * 0.08;
    } else if (variant == 1u) {
        float sideWidth = max(0.012, extrusion * (0.022 + abs(p.depth) * 0.018));
        f.center += ax * (p.size.x * 0.5 + sideWidth * 0.5);
        f.center += liftDir * extrusion * 0.018;
        f.size = float2(sideWidth, p.size.y * (0.88 + 0.12 * abs(hinge)));
        f.axis_x = normalize(lerp(ax, liftDir, 0.55));
        f.axis_y = ay;
        f.palette = fmod(p.palette + 1.0 + (float)assembly_mode, 8.0);
        f.depth += 0.015;
    } else {
        float shadowReach = extrusion * (0.035 + 0.025 * saturate(p.weight));
        f.center += liftDir * shadowReach;
        f.size = p.size + float2(shadowReach * 0.45, shadowReach * 0.25);
        f.palette = 1.0;
        f.pattern = 0.0;
        f.depth -= 0.08;
    }

    if (assembly_mode == 1) {
        f.center += float2((p.group_id - 3.5) * 0.012, indexWave * 0.018);
    } else if (assembly_mode == 2) {
        f.axis_x = normalize(lerp(f.axis_x, float2(1.0, 0.0), 0.32));
        f.axis_y = float2(-f.axis_x.y, f.axis_x.x);
    } else if (assembly_mode == 3) {
        float groupFan = (p.group_id - 3.5) / 3.5;
        float2 fanDir = normalize(float2(groupFan, -0.45 + p.phase));
        f.center += fanDir * (0.035 + abs(groupFan) * 0.085) * (0.6 + extrusion * 0.4);
        f.center += float2(indexWave, -indexWave) * 0.055 * (1.0 + p.group_id * 0.08);
        f.size *= 0.78 + 0.34 * frac(p.group_id * 0.37);
        f.axis_x = normalize(lerp(f.axis_x, fanDir, 0.22));
        f.axis_y = float2(-f.axis_x.y, f.axis_x.x);
    }

    FacesOut[outIndex] = f;
}
