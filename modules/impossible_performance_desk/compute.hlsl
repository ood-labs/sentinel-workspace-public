struct DeskState {
    float focus_x;
    float focus_y;
    float rupture_x;
    float rupture_y;
    float pressure_value;
    float reindex_value;
    float strike_value;
    float phase_value;
};

RWStructuredBuffer<DeskState> StateOut : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    DeskState s;
    s.focus_x = focus_pad.x;
    s.focus_y = focus_pad.y;
    s.rupture_x = rupture_pad.x;
    s.rupture_y = rupture_pad.y;
    s.pressure_value = pressure;
    s.reindex_value = reindex_amount;
    // Momentary buttons use the authoritative host parameter directly in the UI and
    // downstream expression path; do not publish a frame-lagged GPU readback.
    s.strike_value = 0.0;
    s.phase_value = master_phase;
    StateOut[0] = s;
}
