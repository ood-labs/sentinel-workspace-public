// 2D dispatch check: 100 lags x 160 phases, allocated rectangular with invalid
// threads returning early - the exact shape 2E1's comb matrix needs.
struct G { uint tau, theta, hit, pad; };
RWStructuredBuffer<G> Grid : register(u0);

static const uint TAU_N = 100u;
static const uint THETA_N = 160u;

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint tau = tid.x, theta = tid.y;
    if (tau >= TAU_N || theta >= THETA_N) return;   // invalid threads bail
    G g;
    g.tau = tau; g.theta = theta; g.hit = 1u; g.pad = tau * THETA_N + theta;
    Grid[tau * THETA_N + theta] = g;
}
