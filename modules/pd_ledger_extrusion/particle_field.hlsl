RWTexture2D<float4> OutputUAV : register(u0);

struct ParticleRecord
{
    float3 position;
    float age;
    float3 origin;
    float life;
    float2 axis;
    float mass;
    float seed;
    uint kind;
    uint emitterId;
    uint active;
    uint serial;
};

struct SpawnState
{
    float remainder;
    uint spawnSerial;
    uint spawnBudget;
    uint initialized;
    float cameraDistance;
    float deltaTime;
    float pathPhase;
    float pad;
};

StructuredBuffer<ParticleRecord> ParticleInput : register(t0);
StructuredBuffer<SpawnState> SpawnInput : register(t1);

#include "rail_camera.hlsli"

static const float PD_PI = 3.14159265359;
static const float PD_TAU = 6.28318530718;

float2 pdRotate2(float2 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 pdRotateX(float3 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

float3 pdRotateY(float3 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

float3 pdRotateZ(float3 p, float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

float3 pdObjectToWorld(float3 p, float3 angles)
{
    p = pdRotateX(p, angles.x);
    p = pdRotateY(p, angles.y);
    p = pdRotateZ(p, angles.z);
    return p;
}

float3 pdWorldToObject(float3 p, float3 angles)
{
    p = pdRotateZ(p, -angles.z);
    p = pdRotateY(p, -angles.y);
    p = pdRotateX(p, -angles.x);
    return p;
}

float pdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-7));
    return length(pa - ba * h);
}

float pdStroke(float distanceValue, float width, float aa)
{
    return 1.0 - smoothstep(width, width + aa * 0.48, distanceValue);
}

float2 pdPath(float normalizedAge, float2 axis, float seed)
{
    float late = smoothstep(divergence_onset, 1.0, normalizedAge);
    float2 railOffset = path_bend * normalizedAge * normalizedAge * 0.34;
    railOffset += float2(
        sin(normalizedAge * PD_PI + seed * 4.0),
        sin(normalizedAge * 2.31 + seed * 5.7)
    ) * path_sway * sin(normalizedAge * PD_PI) * 0.16;
    float2 split = normalize(axis + float2(1e-5, 0.0))
        * (seed * 2.0 - 1.0) * axis_spread * divergence * late * late;
    return railOffset + split;
}

float pdSphereHit(
    float3 rayOrigin,
    float3 rayDirection,
    float3 center,
    float radius,
    out float3 worldNormal)
{
    float3 relative = rayOrigin - center;
    float b = dot(relative, rayDirection);
    float c = dot(relative, relative) - radius * radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0)
    {
        worldNormal = 0.0;
        return -1.0;
    }
    float t = -b - sqrt(discriminant);
    if (t <= 0.0)
    {
        worldNormal = 0.0;
        return -1.0;
    }
    worldNormal = normalize(rayOrigin + rayDirection * t - center);
    return t;
}

float pdEllipsoidHit(
    float3 rayOrigin,
    float3 rayDirection,
    float3 center,
    float3 radius,
    float3 angles,
    out float3 worldNormal,
    out float3 localHit)
{
    float3 localOrigin = pdWorldToObject(rayOrigin - center, angles) / max(radius, 1e-5);
    float3 localDirection = pdWorldToObject(rayDirection, angles) / max(radius, 1e-5);
    float a = dot(localDirection, localDirection);
    float b = dot(localOrigin, localDirection);
    float c = dot(localOrigin, localOrigin) - 1.0;
    float discriminant = b * b - a * c;
    if (discriminant < 0.0)
    {
        worldNormal = 0.0;
        localHit = 0.0;
        return -1.0;
    }
    float t = (-b - sqrt(discriminant)) / max(a, 1e-5);
    if (t <= 0.0)
    {
        worldNormal = 0.0;
        localHit = 0.0;
        return -1.0;
    }
    float3 unitHit = localOrigin + localDirection * t;
    localHit = unitHit * radius;
    worldNormal = normalize(pdObjectToWorld(normalize(unitHit / max(radius, 1e-5)), angles));
    return t;
}

float pdBoxHit(
    float3 rayOrigin,
    float3 rayDirection,
    float3 center,
    float3 halfExtent,
    float3 angles,
    out float3 worldNormal,
    out float3 localHit)
{
    float3 localOrigin = pdWorldToObject(rayOrigin - center, angles);
    float3 localDirection = pdWorldToObject(rayDirection, angles);
    float3 safeDirection = sign(localDirection) * max(abs(localDirection), 1e-5);
    float3 nearPlane = (-halfExtent - localOrigin) / safeDirection;
    float3 farPlane = (halfExtent - localOrigin) / safeDirection;
    float3 tMin3 = min(nearPlane, farPlane);
    float3 tMax3 = max(nearPlane, farPlane);
    float tNear = max(tMin3.x, max(tMin3.y, tMin3.z));
    float tFar = min(tMax3.x, min(tMax3.y, tMax3.z));
    if (tFar < max(tNear, 0.0))
    {
        worldNormal = 0.0;
        localHit = 0.0;
        return -1.0;
    }

    float t = tNear > 0.0 ? tNear : tFar;
    localHit = localOrigin + localDirection * t;
    float3 face = abs(localHit / max(halfExtent, 1e-5));
    float3 localNormal = 0.0;
    if (face.x >= face.y && face.x >= face.z)
        localNormal.x = localHit.x >= 0.0 ? 1.0 : -1.0;
    else if (face.y >= face.z)
        localNormal.y = localHit.y >= 0.0 ? 1.0 : -1.0;
    else
        localNormal.z = localHit.z >= 0.0 ? 1.0 : -1.0;
    worldNormal = normalize(pdObjectToWorld(localNormal, angles));
    return t;
}

float2 pdProjectWorld(
    float3 position,
    float aspect,
    float2 vanish,
    float2 cameraRail,
    float focalLength)
{
    float effectiveDepth = position.z * lerp(1.0, 0.52, camera_follow);
    return pdProjectLedger(
        float3(position.xy, effectiveDepth),
        aspect,
        SpawnInput[0].cameraDistance
    );
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint width;
    uint height;
    OutputUAV.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) return;

    float2 resolution = float2((float)width, (float)height);
    float2 uv = ((float2)tid.xy + 0.5) / resolution;
    float aspect = resolution.x / max(resolution.y, 1.0);
    float aa = 0.78 / max(resolution.y, 1.0);

    SpawnState spawn = SpawnInput[0];
    float2 cameraRail = pdRailCameraOffset(spawn.cameraDistance);
    float2 vanish = pdRailVanish(aspect);
    float2 screen = pdRailScreen(uv, aspect);
    float focalLength = pdRailFocalLength();
    float3 rayOrigin = pdRailCameraOrigin(spawn.cameraDistance);
    float3 rayDirection = pdRailCameraRay(uv, aspect, spawn.cameraDistance);

    float3 paper = float3(0.86, 0.88, 0.84);
    float3 graphite = float3(0.16, 0.175, 0.16);
    float3 liability = liability_color;
    float3 color = float3(0.0015, 0.0018, 0.0016);
    float frameBranchLayer = 0.0;

    // Reinterpret the ledger corners as a branching 3D scaffold. Each rail
    // uses the same world transform as the plate, then reaches outward into
    // the coordinate chamber.
    float3 cornerWorld[4] = {
        pdLedgerToWorld(float3(0.0, 0.0, 0.0), aspect),
        pdLedgerToWorld(float3(1.0, 0.0, 0.0), aspect),
        pdLedgerToWorld(float3(1.0, 1.0, 0.0), aspect),
        pdLedgerToWorld(float3(0.0, 1.0, 0.0), aspect)
    };
    [unroll]
    for (uint c = 0u; c < 4u; ++c)
    {
        float3 branchTarget = cornerWorld[c] + float3(
            (c == 0u || c == 3u) ? -0.85 : 0.85,
            (c < 2u) ? -0.65 : 0.65,
            2.8 + 0.35 * c
        );
        float2 cornerP = pdProjectWorld(cornerWorld[c], aspect, vanish, cameraRail, focalLength);
        float2 branchP = pdProjectWorld(branchTarget, aspect, vanish, cameraRail, focalLength);
        float branch = pdStroke(pdSegment(screen, cornerP, branchP), aa * 0.13, aa);
        frameBranchLayer = max(frameBranchLayer, branch * 0.34);
    }

    // World-space coordinate floor. The ray hits a real horizontal stage
    // beneath the ledger plane, so the grid parallax stays locked to the
    // internal camera and gives the emitted solids a measured spatial home.
    const float floorY = -1.18;
    if (abs(rayDirection.y) > 1e-4)
    {
        float floorT = (floorY - rayOrigin.y) / rayDirection.y;
        if (floorT > 0.0 && floorT < 80.0)
        {
            float3 floorPoint = rayOrigin + rayDirection * floorT;
            float2 floorXZ = floorPoint.xz;
            float2 floorWarp = floorXZ + float2(
                sin(floorXZ.y * 0.43 + phase * PD_TAU) * 0.10,
                cos(floorXZ.x * 0.37 - phase * PD_TAU * 0.7) * 0.08
            );
            float2 cell = abs(frac(floorWarp * 1.16 + 0.5) - 0.5);
            float minor = min(cell.x, cell.y);
            float gridWidth = 0.006 + floorT * 0.0010;
            float gridInk = 1.0 - smoothstep(gridWidth, gridWidth * 2.2, minor);
            float majorX = 1.0 - smoothstep(gridWidth * 1.8, gridWidth * 4.0,
                abs(frac(floorWarp.x * 0.29 + 0.5) - 0.5));
            float majorZ = 1.0 - smoothstep(gridWidth * 1.8, gridWidth * 4.0,
                abs(frac(floorWarp.y * 0.29 + 0.5) - 0.5));
            float axisX = 1.0 - smoothstep(gridWidth, gridWidth * 2.4, abs(floorXZ.x));
            float axisZ = 1.0 - smoothstep(gridWidth, gridWidth * 2.4, abs(floorXZ.y));
            float floorFade = saturate(1.0 - floorT / 26.0);
            color += graphite * gridInk * floorFade * 0.15;
            color += paper * max(majorX, majorZ) * floorFade * 0.08;
            color += liability * max(axisX, axisZ) * floorFade * 0.13;
        }
    }

    // Rear calibration wall: a second world-space grid closes the volume and
    // makes depth legible when the internal fly camera moves through it.
    if (abs(rayDirection.z) > 1e-4)
    {
        const float wallZ = 5.8;
        float wallT = (wallZ - rayOrigin.z) / rayDirection.z;
        if (wallT > 0.0 && wallT < 80.0)
        {
            float3 wallPoint = rayOrigin + rayDirection * wallT;
            float2 wallXY = wallPoint.xy;
            float2 wallWarp = wallXY + float2(
                sin(wallXY.y * 0.31 + phase * PD_TAU * 0.6) * 0.09,
                cos(wallXY.x * 0.39 - phase * PD_TAU) * 0.07
            );
            float2 wallCell = abs(frac(wallWarp * 1.16 + 0.5) - 0.5);
            float wallMinor = min(wallCell.x, wallCell.y);
            float wallWidth = 0.005 + wallT * 0.0009;
            float wallInk = 1.0 - smoothstep(wallWidth, wallWidth * 2.1, wallMinor);
            float wallMajorX = 1.0 - smoothstep(wallWidth * 1.6, wallWidth * 3.4,
                abs(frac(wallWarp.x * 0.29 + 0.5) - 0.5));
            float wallMajorY = 1.0 - smoothstep(wallWidth * 1.6, wallWidth * 3.4,
                abs(frac(wallWarp.y * 0.29 + 0.5) - 0.5));
            float wallFade = saturate(1.0 - wallT / 34.0);
            color += graphite * wallInk * wallFade * 0.10;
            color += paper * max(wallMajorX, wallMajorY) * wallFade * 0.055;
            color += liability * (1.0 - smoothstep(wallWidth, wallWidth * 2.0, abs(wallXY.y))) * wallFade * 0.08;
        }
    }

    // Conductor-driven depth gate. This is a real moving plane through the
    // chamber, not a screen-space wipe: it gives the coordinate volume a
    // deliberate scanning motion and briefly registers solids at its depth.
    if (abs(rayDirection.z) > 1e-4)
    {
        float scanZ = 0.35 + frac(phase) * 5.15;
        float scanT = (scanZ - rayOrigin.z) / rayDirection.z;
        if (scanT > 0.0 && scanT < 80.0)
        {
            float3 scanPoint = rayOrigin + rayDirection * scanT;
            float2 scanXY = scanPoint.xy;
            float2 scanCell = abs(frac(scanXY * 0.34 + 0.5) - 0.5);
            float scanMinor = min(scanCell.x, scanCell.y);
            float scanWidth = 0.004 + scanT * 0.0007;
            float scanInk = 1.0 - smoothstep(scanWidth, scanWidth * 1.8, scanMinor);
            float scanPulse = 0.62 + 0.38 * sin(frac(phase) * PD_TAU);
            color += liability * scanInk * scanPulse * 0.12;
            color += paper * (1.0 - smoothstep(scanWidth, scanWidth * 2.0, abs(scanXY.y))) * scanPulse * 0.045;
        }
    }

    // A single spatial cage establishes depth without cloning any source record.
    float radial = length(screen - vanish);
    float corridor = pdStroke(abs(radial - 0.22), aa * 0.65, aa)
        + pdStroke(abs(radial - 0.42), aa * 0.55, aa);
    color += graphite * saturate(corridor) * 0.062;
    color += lerp(paper, liability, 0.35) * frameBranchLayer;

    float nearestT = 100000.0;
    float3 nearestNormal = float3(0.0, 0.0, -1.0);
    float3 nearestLocal = 0.0;
    float3 nearestExtent = 1.0;
    float3 nearestBase = paper;
    float nearestFade = 0.0;
    float nearestDepth = 0.0;
    uint nearestKind = 0u;
    float trailLayer = 0.0;
    float tetherLayer = 0.0;
    float socketLayer = 0.0;
    float plexusLayer = 0.0;
    float lineageLayer = 0.0;
    float pylonLayer = 0.0;

    // Dark architectural occluders: these are depth-tested slabs, not a
    // screen-space mask. They carve negative space around the live focus and
    // remain stable as the native camera flies through the chamber.
    float3 occluderNormal = 0.0;
    float3 occluderLocal = 0.0;
    float3 occluderExtent = float3(0.24, 1.55, 0.72);
    float slabT = pdBoxHit(
        rayOrigin, rayDirection,
        float3(-2.05, 0.05, 3.65),
        occluderExtent,
        float3(0.0, -0.16, -0.08),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = occluderExtent;
        nearestBase = float3(0.012, 0.014, 0.013);
        nearestFade = 0.96;
        nearestDepth = 3.65;
        nearestKind = 3u;
    }
    slabT = pdBoxHit(
        rayOrigin, rayDirection,
        float3(2.10, 0.18, 4.55 + sin(phase * PD_TAU) * 0.32),
        float3(0.20, 1.72, 0.60),
        float3(0.0, 0.21 + sin(phase * PD_TAU) * 0.10, 0.12 + cos(phase * PD_TAU) * 0.08),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(0.20, 1.72, 0.60);
        nearestBase = float3(0.010, 0.012, 0.011);
        nearestFade = 0.96;
        nearestDepth = 4.55 + sin(phase * PD_TAU) * 0.32;
        nearestKind = 3u;
    }
    slabT = pdEllipsoidHit(
        rayOrigin, rayDirection,
        float3(0.15, -1.02, 5.55),
        float3(0.42, 0.28, 1.42),
        float3(0.15, -0.22, 0.34),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(0.42, 0.28, 1.42);
        nearestBase = float3(0.009, 0.010, 0.009);
        nearestFade = 0.96;
        nearestDepth = 5.55;
        nearestKind = 3u;
    }

    // Far sanctum: a broad, almost-black rear surface occludes the infinite
    // grid behind the focal cluster, creating a deliberate negative-space
    // silhouette that survives camera changes.
    slabT = pdEllipsoidHit(
        rayOrigin,
        rayDirection,
        float3(0.0, 0.15, 7.35),
        float3(2.55, 1.92, 0.24),
        float3(0.0, 0.0, 0.08),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(2.55, 1.92, 0.24);
        nearestBase = float3(0.004, 0.005, 0.004);
        nearestFade = 0.92;
        nearestDepth = 7.35;
        nearestKind = 1u;
    }

    // Sparse rear ribs: a few deliberately uneven columns extend the temple
    // cadence behind the focus while leaving broad dark gaps for negative
    // space.
    float3 ribCenters[3] = {
        float3(-1.25, 0.10, 6.35),
        float3(0.18, 0.48, 6.62),
        float3(1.42, -0.04, 6.18)
    };
    float3 ribExtents[3] = {
        float3(0.085, 1.42, 0.10),
        float3(0.10, 1.08, 0.085),
        float3(0.07, 1.62, 0.095)
    };
    [unroll]
    for (uint r = 0u; r < 3u; ++r)
    {
        float3 ribAngles = float3(0.0, 0.10 * sin(phase * PD_TAU + r), (r - 1.0) * 0.045);
        slabT = pdBoxHit(
            rayOrigin, rayDirection,
            ribCenters[r], ribExtents[r], ribAngles,
            occluderNormal,
            occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = ribExtents[r];
            nearestBase = float3(0.006, 0.007, 0.006);
            nearestFade = 0.90;
            nearestDepth = ribCenters[r].z;
            nearestKind = 3u;
        }
    }

    // Vault crown: five sparse, dark ellipsoid ribs arc over the rear sanctum.
    // They are intentionally discontinuous so the center stays open and the
    // ledger remains the focal aperture from oblique camera angles.
    float crownPhase = phase * PD_TAU;
    float3 crownCenters[5] = {
        float3(-2.55, 1.55, 7.62),
        float3(-1.38, 2.06, 7.76),
        float3(0.0, 2.28, 7.86),
        float3(1.38, 2.06, 7.76),
        float3(2.55, 1.55, 7.62)
    };
    float3 crownExtents[5] = {
        float3(0.18, 0.82, 0.16),
        float3(0.16, 0.96, 0.14),
        float3(0.14, 1.08, 0.13),
        float3(0.16, 0.96, 0.14),
        float3(0.18, 0.82, 0.16)
    };
    [unroll]
    for (uint c = 0u; c < 5u; ++c)
    {
        float side = (float)c - 2.0;
        float3 crownAngles = float3(
            0.0,
            0.12 * sin(crownPhase * 0.35 + c * 0.7),
            side * 0.18 + 0.018 * sin(crownPhase + c)
        );
        slabT = pdEllipsoidHit(
            rayOrigin, rayDirection,
            crownCenters[c], crownExtents[c],
            crownAngles, occluderNormal, occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = crownExtents[c];
            nearestBase = float3(0.005, 0.006, 0.005);
            nearestFade = 0.91;
            nearestDepth = crownCenters[c].z;
            nearestKind = 1u;
        }
    }

    // Suspended canopy: a shallow ceiling hangs above the aperture, turning
    // the upper field into an enclosed chamber while leaving the ledger slit
    // and crown gaps readable from the native fly camera.
    float canopyPhase = crownPhase * 0.31;
    float3 canopyCenter = float3(
        0.0,
        1.88 + 0.06 * sin(canopyPhase),
        5.22 + 0.16 * cos(canopyPhase * 0.7)
    );
    float3 canopyExtent = float3(1.92, 0.18, 0.46);
    float3 canopyAngles = float3(
        0.035 * sin(canopyPhase * 0.8),
        0.07 * sin(canopyPhase),
        0.045 * cos(canopyPhase * 0.6)
    );
    slabT = pdEllipsoidHit(
        rayOrigin, rayDirection, canopyCenter, canopyExtent, canopyAngles,
        occluderNormal, occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = canopyExtent;
        nearestBase = float3(0.004, 0.005, 0.004);
        nearestFade = 0.95;
        nearestDepth = canopyCenter.z;
        nearestKind = 1u;
    }

    // Threshold iris: four near-dark petals sit just behind the ledger plane.
    // Their slow phase rotation creates a real depth aperture around the
    // emitter cluster instead of another screen-space frame.
    float irisPhase = crownPhase * 0.22;
    float3 irisCenters[4] = {
        float3(-1.62,  1.05, 4.92),
        float3( 1.62,  1.05, 4.92),
        float3(-1.62, -1.02, 4.78),
        float3( 1.62, -1.02, 4.78)
    };
    float3 irisExtents[4] = {
        float3(0.16, 0.72, 0.13),
        float3(0.16, 0.72, 0.13),
        float3(0.14, 0.58, 0.12),
        float3(0.14, 0.58, 0.12)
    };
    [unroll]
    for (uint p = 0u; p < 4u; ++p)
    {
        float side = (p & 1u) == 0u ? -1.0 : 1.0;
        float row = p < 2u ? 1.0 : -1.0;
        float3 irisAngles = float3(
            row * 0.08,
            side * (0.18 + 0.035 * sin(irisPhase + p)),
            side * row * (0.24 + 0.025 * cos(irisPhase * 1.3 + p))
        );
        slabT = pdEllipsoidHit(
            rayOrigin, rayDirection,
            irisCenters[p], irisExtents[p], irisAngles,
            occluderNormal, occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = irisExtents[p];
            nearestBase = float3(0.006, 0.006, 0.005);
            nearestFade = 0.93;
            nearestDepth = irisCenters[p].z;
            nearestKind = 1u;
        }
    }

    // Grounding plinth: a broad, almost-black well sits behind the lower
    // emission band. It absorbs the floor grid locally and gives the airborne
    // ledger a physical threshold without flattening the scene into a frame.
    slabT = pdEllipsoidHit(
        rayOrigin, rayDirection,
        float3(-0.05, -1.02, 4.58),
        float3(1.78, 0.34, 0.62),
        float3(0.05, -0.10 + 0.03 * sin(irisPhase), 0.04),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(1.78, 0.34, 0.62);
        nearestBase = float3(0.005, 0.005, 0.004);
        nearestFade = 0.94;
        nearestDepth = 4.58;
        nearestKind = 1u;
    }

    // Side wings: two oblique, near-black masses push the architecture beyond
    // the frame while preserving a clear central slit for the live ledger.
    float wingBreath = 0.10 * sin(irisPhase * 0.7);
    float3 wingCenters[2] = {
        float3(-2.72, 0.26, 5.12 + wingBreath),
        float3( 2.72, 0.26, 5.12 - wingBreath)
    };
    [unroll]
    for (uint w = 0u; w < 2u; ++w)
    {
        float wingSide = (w == 0u) ? -1.0 : 1.0;
        float3 wingAngles = float3(
            0.0,
            wingSide * (0.22 + 0.04 * sin(irisPhase + w)),
            wingSide * 0.18
        );
        slabT = pdEllipsoidHit(
            rayOrigin, rayDirection,
            wingCenters[w], float3(0.56, 1.48, 0.22), wingAngles,
            occluderNormal, occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = float3(0.56, 1.48, 0.22);
            nearestBase = float3(0.005, 0.006, 0.005);
            nearestFade = 0.93;
            nearestDepth = wingCenters[w].z;
            nearestKind = 1u;
        }
    }

    // Rear spine: converging cross-members visually stitch the wings into the
    // crown, with a narrow gap that keeps the ledger's emission corridor open.
    float3 spineCenters[2] = {
        float3(-1.28, 1.28, 6.28),
        float3( 1.28, 1.28, 6.28)
    };
    [unroll]
    for (uint s = 0u; s < 2u; ++s)
    {
        float spineSide = (s == 0u) ? -1.0 : 1.0;
        float3 spineAngles = float3(
            0.02 * sin(irisPhase + s),
            spineSide * 0.10,
            spineSide * (0.14 + 0.025 * sin(irisPhase * 0.8 + s))
        );
        slabT = pdBoxHit(
            rayOrigin, rayDirection,
            spineCenters[s], float3(1.08, 0.075, 0.10), spineAngles,
            occluderNormal, occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = float3(1.08, 0.075, 0.10);
            nearestBase = float3(0.006, 0.007, 0.006);
            nearestFade = 0.92;
            nearestDepth = spineCenters[s].z;
            nearestKind = 3u;
        }
    }

    // Procession channels: two low dark rails run away from the ledger along
    // the floor plane, carving a convergent aisle through the warped grid.
    float3 aisleCenters[2] = {
        float3(-0.92, -1.20, 6.05),
        float3( 0.92, -1.20, 6.05)
    };
    [unroll]
    for (uint a = 0u; a < 2u; ++a)
    {
        float aisleSide = (a == 0u) ? -1.0 : 1.0;
        float3 aisleAngles = float3(
            0.0,
            aisleSide * 0.04,
            aisleSide * (0.035 + 0.02 * sin(irisPhase + a))
        );
        slabT = pdBoxHit(
            rayOrigin, rayDirection,
            aisleCenters[a], float3(0.075, 0.055, 1.95), aisleAngles,
            occluderNormal, occluderLocal
        );
        if (slabT > 0.0 && slabT < nearestT)
        {
            nearestT = slabT;
            nearestNormal = occluderNormal;
            nearestLocal = occluderLocal;
            nearestExtent = float3(0.075, 0.055, 1.95);
            nearestBase = float3(0.006, 0.006, 0.005);
            nearestFade = 0.91;
            nearestDepth = aisleCenters[a].z;
            nearestKind = 3u;
        }
    }

    // Void lens: a shallow, almost-black rear disk turns the ledger into an
    // aperture. Its slight phase wobble keeps the negative space alive while
    // the foreground particles and ink remain readable in front of it.
    slabT = pdEllipsoidHit(
        rayOrigin, rayDirection,
        float3(0.02, 0.05, 5.42),
        float3(1.48, 1.16, 0.16),
        float3(0.04 * sin(irisPhase * 0.55), 0.06, 0.03),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(1.48, 1.16, 0.16);
        nearestBase = float3(0.0035, 0.0040, 0.0035);
        nearestFade = 0.97;
        nearestDepth = 5.42;
        nearestKind = 1u;
    }

    // Outer lintels: thin dark crossbeams complete the first architectural
    // frame around the focus without becoming bright screen-space borders.
    slabT = pdBoxHit(
        rayOrigin, rayDirection,
        float3(0.0, 1.55, 5.05),
        float3(2.35, 0.10, 0.12),
        float3(0.0, 0.12, -0.025),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(2.35, 0.10, 0.12);
        nearestBase = float3(0.007, 0.008, 0.007);
        nearestFade = 0.94;
        nearestDepth = 5.05;
        nearestKind = 3u;
    }
    slabT = pdBoxHit(
        rayOrigin, rayDirection,
        float3(0.0, -1.35, 4.25),
        float3(2.15, 0.09, 0.11),
        float3(0.0, -0.10, 0.035),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(2.15, 0.09, 0.11);
        nearestBase = float3(0.006, 0.007, 0.006);
        nearestFade = 0.94;
        nearestDepth = 4.25;
        nearestKind = 3u;
    }

    // Counter-monolith: a tapered left gate balances the chamber aperture
    // while remaining slightly skewed, so the composition keeps directional
    // tension instead of becoming a symmetric frame.
    slabT = pdEllipsoidHit(
        rayOrigin,
        rayDirection,
        float3(-2.28, 0.22, 4.85 - sin(phase * PD_TAU) * 0.26),
        float3(0.30, 1.82, 0.70),
        float3(-0.08, 0.18 - sin(phase * PD_TAU) * 0.08, -0.12 + cos(phase * PD_TAU) * 0.06),
        occluderNormal,
        occluderLocal
    );
    if (slabT > 0.0 && slabT < nearestT)
    {
        nearestT = slabT;
        nearestNormal = occluderNormal;
        nearestLocal = occluderLocal;
        nearestExtent = float3(0.30, 1.82, 0.70);
        nearestBase = float3(0.009, 0.010, 0.009);
        nearestFade = 0.94;
        nearestDepth = 4.85 - sin(phase * PD_TAU) * 0.26;
        nearestKind = 1u;
    }

    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord particle = ParticleInput[i];
        if (particle.active == 0u) continue;

        float normalizedAge = saturate(particle.age / max(particle.life, 1e-4));
        float fade = smoothstep(0.0, 0.055, normalizedAge)
            * (1.0 - smoothstep(0.82, 1.0, normalizedAge));
        float effectiveDepth = particle.position.z * lerp(1.0, 0.52, camera_follow);
        float3 center = pdLedgerToWorld(
            float3(particle.position.xy, effectiveDepth),
            aspect
        );
        float radius = particle_scale * lerp(0.09, 0.20, saturate(particle.mass));

        float t = -1.0;
        float3 normal = 0.0;
        float3 localHit = 0.0;
        float3 extent = radius;
        float3 base = paper;
        float gain = 1.0;

        if (particle.kind == 1u)
        {
            t = pdSphereHit(rayOrigin, rayDirection, center, radius * 1.05, normal);
            base = liability;
            gain = macro_gain;
            localHit = t > 0.0 ? (rayOrigin + rayDirection * t - center) : 0.0;
            extent = radius;
        }
        else if (particle.kind == 2u)
        {
            float3 angles = float3(
                particle.seed * PD_TAU + normalizedAge * 1.7,
                particle.seed * 2.2 + normalizedAge * 2.35,
                (particle.seed - 0.5) * 1.8 + normalizedAge * 1.15
            );
            // Corner records are asymmetric folded shards, not stock cubes:
            // their footprint is stretched along the detected feature axis.
            extent = radius * float3(0.62, 0.96, 0.42);
            t = pdEllipsoidHit(rayOrigin, rayDirection, center, extent, angles, normal, localHit);
            base = paper;
            gain = hinge_gain;
        }
        else if (particle.kind == 3u)
        {
            float axisAngle = atan2(particle.axis.y, particle.axis.x);
            float3 angles = float3(
                normalizedAge * 1.35 + particle.seed,
                (particle.seed - 0.5) * 0.92,
                axisAngle + normalizedAge * 0.52
            );
            extent = radius * float3(2.15, 0.34, 0.38);
            t = pdBoxHit(rayOrigin, rayDirection, center, extent, angles, normal, localHit);
            base = lerp(graphite * 1.7, paper, 0.34);
            gain = rail_gain;
        }

        if (t > 0.0 && t < nearestT && fade > 0.001)
        {
            nearestT = t;
            nearestNormal = normal;
            nearestLocal = localHit;
            nearestExtent = extent;
            nearestBase = base * gain;
            nearestFade = fade;
            nearestDepth = particle.position.z;
            nearestKind = particle.kind;
        }

        // Trails are only motion evidence. The solids above carry the visual mass.
        float previousAge = max(0.0, normalizedAge - trail_length);
        float3 previousPosition = float3(
            particle.origin.xy + pdPath(previousAge, particle.axis, particle.seed),
            previousAge * depth_length
        );
        float2 currentP = pdProjectWorld(particle.position, aspect, vanish, cameraRail, focalLength);
        float2 previousP = pdProjectWorld(previousPosition, aspect, vanish, cameraRail, focalLength);
        float trail = pdStroke(
            pdSegment(screen, previousP, currentP),
            max(aa * 0.22, radius * 0.012),
            aa
        );
        trailLayer = max(trailLayer, trail * fade * trail_gain);

        // Persistent parent filament: every solid remains traceably attached
        // to its ledger spawn site, while the very small width keeps this
        // structural relationship subordinate to the objects themselves.
        float2 lineageEmitter = pdProjectWorld(
            float3(particle.origin.xy, 0.0),
            aspect,
            vanish,
            cameraRail,
            focalLength
        );
        float lineage = pdStroke(
            pdSegment(screen, lineageEmitter, currentP),
            max(aa * 0.11, radius * 0.004),
            aa
        );
        lineageLayer = max(lineageLayer, lineage * fade * 0.42);

        // Registration pylon: the ledger origin is projected onto the floor
        // with the same world transform, making each source coordinate occupy
        // a visible vertical measure inside the chamber.
        float3 emitterWorld = pdLedgerToWorld(float3(particle.origin.xy, 0.0), aspect);
        float3 floorWorld = float3(emitterWorld.x, floorY, emitterWorld.z);
        float2 emitterTop = pdProjectWorld(emitterWorld, aspect, vanish, cameraRail, focalLength);
        float2 emitterFoot = pdProjectWorld(floorWorld, aspect, vanish, cameraRail, focalLength);
        float pylon = pdStroke(
            pdSegment(screen, emitterTop, emitterFoot),
            max(aa * 0.13, radius * 0.0045),
            aa
        );
        pylonLayer = max(pylonLayer, pylon * fade * 0.30);

        // Connect only records from the same emitter lineage. Adjacent buffer
        // slots are not a semantic relationship by themselves; the emitter ID
        // is the real ledger-derived topology key.
        if (i < 191u)
        {
            ParticleRecord nextParticle = ParticleInput[i + 1u];
            float originGap = length(particle.origin.xy - nextParticle.origin.xy);
            if (nextParticle.active != 0u &&
                (nextParticle.emitterId == particle.emitterId || originGap < 0.035))
            {
                float depthGap = abs(particle.position.z - nextParticle.position.z);
                float2 nextP = pdProjectWorld(nextParticle.position, aspect, vanish, cameraRail, focalLength);
                float link = pdStroke(
                    pdSegment(screen, currentP, nextP),
                    max(aa * 0.12, radius * 0.005),
                    aa
                ) * smoothstep(0.95, 0.0, depthGap);
                plexusLayer = max(plexusLayer, link * fade * 0.62);
            }
        }

        if (normalizedAge < 0.15)
        {
            float2 emitterP = pdProjectWorld(
                float3(particle.origin.xy, 0.0),
                aspect,
                vanish,
                cameraRail,
                focalLength
            );
            float tether = pdStroke(pdSegment(screen, emitterP, currentP), aa * 0.24, aa)
                * (1.0 - normalizedAge / 0.15);
            tetherLayer = max(tetherLayer, tether * 1.35);

            // Exact birth registration: the socket is projected from the same
            // origin and plane transform as the particle center, never from a
            // decorative screen-space coordinate.
            float2 socketOffset = pdProjectWorld(
                float3(particle.origin.xy + float2(0.018, 0.0), 0.0),
                aspect,
                vanish,
                cameraRail,
                focalLength
            ) - emitterP;
            float socketRadius = max(length(socketOffset) * 1.55, aa * 2.0);
            float socket = pdStroke(
                abs(length(screen - emitterP) - socketRadius),
                aa * 1.05,
                aa
            ) * (1.0 - normalizedAge / 0.15);
            float socketCross =
                pdStroke(pdSegment(screen, emitterP - float2(socketRadius * 1.4, 0.0), emitterP + float2(socketRadius * 1.4, 0.0)), aa * 0.22, aa) +
                pdStroke(pdSegment(screen, emitterP - float2(0.0, socketRadius * 1.4), emitterP + float2(0.0, socketRadius * 1.4)), aa * 0.22, aa);
            socketLayer = max(socketLayer, socket + socketCross * 0.28);
        }
    }

    float occupancy = 0.0;
    if (nearestT < 99999.0)
    {
        float3 lightDirection = normalize(float3(-0.42, -0.58, -0.70));
        float3 viewDirection = -rayDirection;
        float diffuse = saturate(dot(nearestNormal, lightDirection));
        float rim = pow(saturate(1.0 - dot(nearestNormal, viewDirection)), 2.4);
        float specular = pow(
            saturate(dot(reflect(-lightDirection, nearestNormal), viewDirection)),
            nearestKind == 1u ? 28.0 : 16.0
        );
        float depthFog = exp(-nearestDepth * 0.10);

        float edge = 0.0;
        if (nearestKind != 1u)
        {
            float3 faceRatio = abs(nearestLocal / max(nearestExtent, 1e-5));
            float secondLargest = max(
                min(faceRatio.x, faceRatio.y),
                max(min(faceRatio.y, faceRatio.z), min(faceRatio.z, faceRatio.x))
            );
            edge = smoothstep(0.72, 0.98, secondLargest);
        }

        float3 shaded = nearestBase * (0.14 + diffuse * 0.86);
        shaded += paper * specular * 0.62;
        shaded = lerp(shaded, paper * 0.82, edge * 0.48);
        shaded += liability * rim * (nearestKind == 1u ? 0.22 : 0.065);
        color = lerp(color, shaded * depthFog, nearestFade);
        occupancy = nearestFade;
    }

    color += graphite * trailLayer * 0.23;
    color += lerp(graphite, liability, 0.34) * plexusLayer * 0.30;
    color += liability * tetherLayer * 0.42;
    color += lerp(graphite, liability, 0.48) * lineageLayer;
    color += lerp(graphite, paper, 0.45) * pylonLayer;
    color += liability * socketLayer * 1.15;

    float cross =
        pdStroke(pdSegment(screen, vanish - float2(0.020, 0.0), vanish + float2(0.020, 0.0)), aa * 0.65, aa) +
        pdStroke(pdSegment(screen, vanish - float2(0.0, 0.020), vanish + float2(0.0, 0.020)), aa * 0.65, aa);
    color += liability * saturate(cross) * 0.36;

    OutputUAV[tid.xy] = float4(saturate(color), saturate(max(occupancy, max(trailLayer, max(tetherLayer, max(lineageLayer, pylonLayer))))));
}
