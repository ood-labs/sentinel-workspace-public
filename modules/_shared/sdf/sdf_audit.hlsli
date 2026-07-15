#ifndef SENTINEL_SDF_AUDIT_HLSLI
#define SENTINEL_SDF_AUDIT_HLSLI

struct SdfAuditResult
{
    float assertion_id;
    float expected;
    float measured;
    float tolerance;
    float status;
    float error;
    float iterations;
    float reserved0;
};

float audit_sd_box(float3 p, float3 half_extent)
{
    float3 q = abs(p) - half_extent;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float audit_measure_top_height_box(float half_x, float half_z, float height, float tolerance, out float iterations)
{
    float lo = 0.0001;
    float hi = max(height * 2.0 + 0.25, 0.5);
    iterations = 0.0;
    [loop]
    for (int i = 0; i < 24; ++i)
    {
        float mid = (lo + hi) * 0.5;
        float d = audit_sd_box(
            float3(0.0, mid - height * 0.5, 0.0),
            float3(half_x, height * 0.5, half_z));
        if (d <= 0.0)
        {
            lo = mid;
        }
        else
        {
            hi = mid;
        }
        iterations = (float)(i + 1);
        if (abs(hi - lo) <= tolerance * 0.25)
        {
            break;
        }
    }
    return (lo + hi) * 0.5;
}

SdfAuditResult audit_make_result(float assertion_id, float expected, float measured, float tolerance, float iterations)
{
    SdfAuditResult result;
    result.assertion_id = assertion_id;
    result.expected = expected;
    result.measured = measured;
    result.tolerance = tolerance;
    result.status = abs(measured - expected) <= tolerance ? 1.0 : 0.0;
    result.error = measured - expected;
    result.iterations = iterations;
    result.reserved0 = 0.0;
    return result;
}

SdfAuditResult audit_make_min_result(float assertion_id, float min_expected, float measured, float tolerance, float iterations)
{
    SdfAuditResult result;
    result.assertion_id = assertion_id;
    result.expected = min_expected;
    result.measured = measured;
    result.tolerance = tolerance;
    result.status = measured + tolerance >= min_expected ? 1.0 : 0.0;
    result.error = measured - min_expected;
    result.iterations = iterations;
    result.reserved0 = 0.0;
    return result;
}

#endif
