struct StreamScan { float4 endpoints, color0, color1, timing, meta; };
RWStructuredBuffer<StreamScan> O : register(u0);
[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x; if (i >= 1024) return;
    StreamScan s = (StreamScan)0;
    if (i < _Data0_Count) { s.endpoints = _Data0[i].endpoints; s.color0 = _Data0[i].color0; s.color1 = _Data0[i].color1; s.timing = _Data0[i].timing; s.meta = _Data0[i].meta; }
    // A record count beyond what was copied would index stale entries: clamp it in the copy.
    if (i == 0) s.endpoints.x = _Data0_Count > 0 ? min(s.endpoints.x, (float)min(_Data0_Count - 1, 1023u)) : 0;
    O[i] = s;
}
