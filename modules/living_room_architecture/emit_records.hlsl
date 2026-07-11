struct PNode {
    float3 position;
    float scale;
    float kind_id;
    float seed;
    float yaw;
    float height;
    float width;
    float depth;
    float2 dir;
};

RWStructuredBuffer<PNode> OutputBuffer : register(u0);

static const uint kRecordCount = 13;
static const PNode kRecords[13] = {
    { float3(0.000000, 0.000000, 0.000000), 1.000000, 0.000000, 3505864192.000000, 0.000000, 0.120000, 8.800000, 7.200000, float2(0.000000, 1.000000) },
    { float3(0.000000, 0.000000, -3.520000), 1.000000, 1.000000, 1542489984.000000, 0.000000, 3.600000, 8.800000, 0.160000, float2(0.000000, 1.000000) },
    { float3(-4.320000, 0.000000, 0.000000), 1.000000, 2.000000, 1692200064.000000, 0.000000, 3.600000, 0.160000, 7.200000, float2(0.000000, 1.000000) },
    { float3(4.320000, 0.000000, 0.000000), 1.000000, 2.000000, 4285397504.000000, 0.000000, 3.600000, 0.160000, 7.200000, float2(0.000000, 1.000000) },
    { float3(0.001000, 3.560000, 0.000000), 1.000000, 3.000000, 1465455616.000000, 0.000000, 0.100000, 8.800000, 7.200000, float2(0.000000, 1.000000) },
    { float3(-2.450000, 0.720000, -3.390000), 1.000000, 4.000000, 1322666112.000000, 0.000000, 1.900000, 2.650000, 0.120000, float2(0.000000, 1.000000) },
    { float3(4.210000, 0.000000, 1.850000), 1.000000, 5.000000, 3566631424.000000, -1.570800, 2.420000, 1.050000, 0.160000, float2(1.000000, 0.000000) },
    { float3(-0.300000, 0.125000, 0.450000), 1.000000, 13.000000, 355363104.000000, -0.035000, 0.035000, 4.800000, 3.300000, float2(-0.034993, 0.999388) },
    { float3(-1.200000, 2.820000, 0.350000), 1.000000, 22.000000, 3150411008.000000, 0.000000, 0.720000, 0.760000, 0.760000, float2(0.000000, 1.000000) },
    { float3(1.200000, 2.820000, 0.350000), 1.000000, 22.000000, 3100078080.000000, 0.000000, 0.720000, 0.760000, 0.760000, float2(0.000000, 1.000000) },
    { float3(-4.200000, 1.320000, -1.175000), 1.000000, 17.000000, 1436880768.000000, 1.570800, 1.420000, 1.080000, 0.120000, float2(-1.000000, 0.000000) },
    { float3(-4.200000, 1.320000, 0.875000), 1.000000, 17.000000, 3568190720.000000, 1.570800, 1.420000, 1.080000, 0.120000, float2(-1.000000, 0.000000) },
    { float3(0.000000, 0.000000, 3.520000), 1.000000, 1.000000, 2685345792.000000, 3.141590, 3.600000, 8.800000, 0.160000, float2(0.000000, -1.000000) },
};

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= kRecordCount) return;
    uint i = id.x;
    PNode r = kRecords[i];

    // The blueprint remains the authored baseline; these controls are the live
    // layout layer. World X/Z uses the point2D pad directly (+Y = room-forward).
    r.position.x += room_offset.x;
    r.position.z += room_offset.y;

    if (i == 0) {
        r.width = room_width;
        r.depth = room_depth;
    } else if (i == 1) {
        r.position.z = room_offset.y - room_depth * 0.5 + 0.08;
        r.height = ceiling_height;
        r.width = room_width;
    } else if (i == 2 || i == 3) {
        float side = i == 2 ? -1.0 : 1.0;
        r.position.x = room_offset.x + side * (room_width * 0.5 - 0.08);
        r.height = ceiling_height;
        r.depth = room_depth;
    } else if (i == 4) {
        r.position = float3(room_offset.x + 0.001, ceiling_height - 0.04, room_offset.y);
        r.width = room_width;
        r.depth = room_depth;
    } else if (i == 5) {
        r.position = float3(room_offset.x + window_position.x, window_position.y,
                            room_offset.y - room_depth * 0.5 + 0.21);
        r.width = 2.65 * window_scale;
        r.height = 1.90 * window_scale;
    } else if (i == 6) {
        r.position = float3(room_offset.x + door_position.x, 0.0, room_offset.y + door_position.y);
        r.yaw = door_yaw;
    } else if (i == 7) {
        r.position.xz = room_offset + rug_position;
        r.width = 4.70 * rug_size;
        r.depth = 3.20 * rug_size;
    } else if (i == 8 || i == 9) {
        float side = i == 8 ? -1.0 : 1.0;
        r.position = float3(room_offset.x + side * pendant_spread * 0.5,
                            ceiling_height - pendant_drop,
                            room_offset.y + pendant_z);
    } else if (i == 10 || i == 11) {
        float side = i == 10 ? -1.0 : 1.0;
        r.position = float3(room_offset.x - room_width * 0.5 + 0.20,
                            art_height,
                            room_offset.y + art_center_z + side * art_spread * 0.5);
        r.yaw = 1.5708;
        r.dir = float2(-1.0, 0.0);
    } else if (i == 12) {
        r.position = float3(room_offset.x, 0.0, room_offset.y + room_depth * 0.5 - 0.08);
        r.width = room_width;
        r.height = ceiling_height;
    }

    OutputBuffer[i] = r;
}
