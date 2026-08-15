// bench.hlsli — the spectral_bench DATA CONTRACT.
//
// One record buffer, `role` discriminated, owned by LT_Bench and read by LT_Trace and LT_Field.
// Nothing downstream re-decides placement: every "where is it / what is it" question has exactly
// one answer and it lives here.
//
// FIXED-BASE ADDRESSED. A consumer wanting element 3 reads LT_ELEM_BASE+3 without scanning, so a
// record's index is a stable identity across cooks, saves and undo — which is what lets the
// editor store its selection as a single integer.
#ifndef SPECTRAL_BENCH_HLSLI
#define SPECTRAL_BENCH_HLSLI

// ---------------------------------------------------------------------------------------------
// Buffer layout
// ---------------------------------------------------------------------------------------------
#define LT_HEADER     0
#define LT_EMIT_BASE  1
#define LT_MAX_EMIT   12
#define LT_ELEM_BASE  13
#define LT_MAX_ELEM   64
#define LT_TOTAL      77

// role
#define ROLE_HEADER  0.0
#define ROLE_EMITTER 1.0
#define ROLE_ELEMENT 2.0

// ---------------------------------------------------------------------------------------------
// Element kinds. Every one of these is a real thing on a real bench; each answers "how does the
// ray MEET it, how does it CARRY the ray, how does the ray LEAVE" differently, which is what
// stops the cast collapsing into one blob with decorations.
// ---------------------------------------------------------------------------------------------
#define EK_PRISM    0   // triangle, apex angle r0. Refracts twice -> disperses. The subject.
#define EK_MIRROR   1   // front-surface plane reflector, reflectivity r0. Folds the path.
#define EK_SLAB     2   // rectangular dielectric block. Lateral displacement, TIR at grazing.
#define EK_LENS     3   // biconvex, two arcs of curvature r0. Focuses; disperses longitudinally.
#define EK_SPLITTER 4   // half-silvered plane. Splits power r0 / (1-r0). Makes a branch.
#define EK_SCREEN   5   // diffuse detector bar. Terminates the ray and GLOWS where it lands.
#define EK_BLOCK    6   // opaque absorber. The only element that is meant to make darkness.
#define EK_COUNT    7

// Is this kind a dielectric body the ray travels INSIDE?
bool ltIsGlass(int k) { return k == EK_PRISM || k == EK_SLAB || k == EK_LENS; }

// ---------------------------------------------------------------------------------------------
// Glass materials. Dispersion is a MATERIAL PROPERTY, so the choice of glass is the choice of
// how wide the fan opens — the single most consequential creative control on the bench.
// Cauchy: n(lambda) = A + B / lambda_um^2.
// ---------------------------------------------------------------------------------------------
#define GM_CROWN   0   // BK7. The honest reference glass; a modest, clean fan.
#define GM_FLINT   1   // SF10. Heavy flint, ~3x the dispersion of crown. The showy one.
#define GM_SILICA  2   // fused silica. The tightest fan; barely splits.
#define GM_SAPPHIRE 3  // high index, low dispersion. Bends hard, spreads little.
#define GM_DIAMOND 4   // extreme index AND extreme dispersion. Fire.
#define GM_WATER   5   // n~1.33. The rainbow's own material.
#define GM_COUNT   6

void ltCauchy(int mat, out float A, out float B)
{
    if      (mat == GM_FLINT)    { A = 1.6280; B = 0.012650; }
    else if (mat == GM_SILICA)   { A = 1.4580; B = 0.003540; }
    else if (mat == GM_SAPPHIRE) { A = 1.7503; B = 0.004500; }
    else if (mat == GM_DIAMOND)  { A = 2.3830; B = 0.010600; }
    else if (mat == GM_WATER)    { A = 1.3240; B = 0.003000; }
    else                         { A = 1.5046; B = 0.004200; }  // GM_CROWN / BK7
}

// DISPERSION GAIN — a scale on the Cauchy B term, i.e. on the Abbe number.
//
// At 1.0 this is real glass, and real glass produces a fan about 1.5 degrees wide for crown and
// 6 for heavy flint. That is the truth and it is nothing like the reference photograph, which is
// a long-throw, high-contrast studio shot of a demonstration prism. Rather than quietly faking
// the colours downstream, the exaggeration lives HERE, as one honest, labelled, sweepable number
// that still preserves every material's relationship to every other. Set it to 1.0 to see what
// the bench would really do.
//
// Each shader sets this from its `dispersion` parameter before tracing.
static float gDispGain = 1.0;

// Refractive index at a wavelength in NANOMETRES.
float ltIOR(int mat, float wl_nm)
{
    float A, B; ltCauchy(mat, A, B);
    float um = max(wl_nm, 1.0) * 0.001;
    return A + gDispGain * B / (um * um);
}

// ---------------------------------------------------------------------------------------------
// Emitter spectra. `tone` on an emitter record.
// ---------------------------------------------------------------------------------------------
#define SP_WHITE     0   // flat equal-energy across the visible band. The reference beam.
#define SP_TUNGSTEN  1   // warm blackbody-ish roll-off; red-heavy fan
#define SP_TRIAD     2   // three narrow laser lines (RGB) — discrete, not continuous
#define SP_BAND      3   // a single narrow band, centred by wl0 with width wl1
#define SP_COUNT     4

// Beam profiles. `kind` on an emitter record.
#define BP_COLLIMATED 0   // parallel rays across the aperture. The reference.
#define BP_FAN        1   // rays diverge over an angle
#define BP_CONVERGE   2   // rays converge to a waist then diverge
#define BP_COUNT      3

// flags bits (stored in a float, tested via LtFlag)
#define F_EDITED 1u   // hand-moved: a global re-layout must not stomp it
#define F_OFF    2u   // switched off by the user
#define F_ALARM  4u   // set by the plan when this record breaks the composition
#define F_UNLIT  8u   // resolved: no chief ray reached this element. The bench failure mode.
#define F_ANCHOR 16u  // chain root — never displaced by the fit pass
// A prism left on AUTO keeps re-solving itself to minimum deviation from whatever ray actually
// arrives, so dragging the emitter re-aims the prism for free. Hand-rotating one sets this bit
// and it stops solving — the user's angle wins, permanently, until they press P.
#define F_MANUAL 32u
// HAND-SPAWNED. The generator allocates around these rather than over them, so a bench you built
// by hand survives a reseed, a variation sweep, or any other change to the generated chain. This
// is what makes the node a bench BUILDER and not just a randomiser with an undo.
#define F_USER   64u
// AIM ONCE, THEN STOP.
//
// A prism carrying this solves itself to minimum deviation on the next resolve and then clears
// the bit. Continuous auto-aim was the original design and it is wrong for a bench you build by
// hand: every time you nudge a source, every prism it touches spins, which reads as the prisms
// moving on their own. Helpful once — when it is generated, when you drop it, or when you press
// P — and inert forever after. That is also what a real bench does.
#define F_AIM   128u

// TOUCH IT AND YOU OWN IT. The generator allocates around anything the user spawned OR edited, so
// the rule is one sentence: whatever you have laid a hand on is yours and survives every reseed,
// preset change and variation sweep; everything else is still the generator's to re-roll.
bool LtOwnedF(float f)
{
    uint v = (uint)max(f, 0.0);
    return (v & (F_USER | F_EDITED)) != 0u;
}

// ---------------------------------------------------------------------------------------------
// Record. 20 floats / 80 bytes. Field meaning depends on `role`.
//
// An ELEMENT stores WHERE IT SITS as a resolved cache (p0, hdg) but also WHAT IT HANGS OFF
// (par, att, dev). The relational fields are the truth for a re-roll; the cache is what
// everything downstream reads. That is what makes a re-roll produce a BENCH rather than debris:
// an element placed on the beam is lit by construction.
// ---------------------------------------------------------------------------------------------
struct BenchRec
{
    float2 p0;   // EMITTER origin          | ELEMENT centre                    (bench units)
    float2 p1;   // EMITTER (aperture, rays)| ELEMENT (half-extent, thickness)
    float  role;
    float  kind; // EMITTER beam profile    | ELEMENT kind
    float  tone; // EMITTER spectrum mode   | ELEMENT glass material
    float  seed;
    float  hdg;  // heading / orientation, radians. Bench plane, +x right, +y DOWN.
    float  r0;   // EMITTER intensity       | PRISM apex angle / MIRROR reflectivity /
                 //                           LENS curvature / SPLITTER split ratio
    float  r1;   // EMITTER divergence      | ELEMENT secondary (screen gain, block softness)
    float  flags;
    float  active;
    float  par;  // chain parent record index (-1 = hangs off the emitter directly)
    float  att;  // chain distance from the parent interaction, bench units
    float  dev;  // chain drawn deflection at this element, radians
    float  z;    // paint order within the plan diagram
    float  gen;  // sub-seed
    float  wl0;  // EMITTER band centre nm  | ELEMENT resolved: chief-ray hit distance (-1 = unlit)
    float  wl1;  // EMITTER band width nm   | ELEMENT resolved: chief-ray incidence angle
};

// ---------------------------------------------------------------------------------------------
// The SECOND record type: one straight run of light between two interactions. 13 floats / 52
// bytes. LT_Trace produces these, LT_Field draws them, and LT_Bench's rail reads its own small
// copy of them.
//
// It lives beside BenchRec rather than in the kernel header because a consumer has to be able to
// DECLARE its buffers before including the code that indexes them — SM 5.0 cannot pass a resource
// as a function argument, so the kernel reaches its buffers through macros, and macros are only
// bound after the declaration exists.
// ---------------------------------------------------------------------------------------------
#define LT_MAX_RAY    40
#define LT_MAX_WAVE   32
#define LT_BRANCH      3    // 0 primary, 1 first-surface reflection, 2 internal reflection
#define LT_MAX_SEG    14
#define LT_PATH_TOTAL (LT_MAX_RAY * LT_MAX_WAVE * LT_BRANCH * LT_MAX_SEG)   // 53760
// One reserved slot past the lanes carries how much of the buffer is actually live this cook.
// Without it every downstream consumer has to scan all 32k segments to find the ~2k that exist,
// and the tile binner — which walks the whole buffer once per screen tile — pays for that scan
// 3600 times over. Lanes are indexed by the LIVE counts, so the live region is contiguous.
#define LT_PATH_HDR   LT_PATH_TOTAL
#define LT_PATH_ALLOC (LT_PATH_TOTAL + 1)

struct PathSeg
{
    float2 a;       // start, bench units
    float2 b;       // end
    float  wl;      // nanometres
    float  power;   // radiometric weight carried ALONG this segment, 0..1
    float  evt;     // event at `a`
    float  evtEnd;  // event at `b`
    float  lane;    // packed lane id, for grouping and for the rail lookup
    float  depth;   // interaction index, 0 = straight out of the emitter
    float  elem;    // element record index reached at `b` (-1 = escaped)
    float  dev;     // cumulative signed deviation from the emitted heading, radians
    float  ior;     // refractive index of the medium this segment travels in (1.0 = air)
};

bool ltSegLive(PathSeg s) { return s.power > 1e-4; }

// Indexed by the LIVE counts, not the maxima, so the live lanes are contiguous from zero.
uint ltLaneIndex(uint ray, uint wave, uint branch, uint nWave, uint nBranch)
{
    return (ray * nWave + wave) * nBranch + branch;
}

// Header record (role = ROLE_HEADER, index LT_HEADER):
//   p0    = (selection record index, drag record index)
//   p1    = signature pack (see LtSigPack)
//   kind  = plan algorithm version
//   tone  = reseed salt
//   seed  = live record count
//   hdg   = drag grab offset x
//   r0    = drag grab offset y
//   r1    = element count
//   att   = emitter count
//   dev   = spectral-rail target emitter index
//   z     = resolved alarm count
//   gen   = command counter (monotonic; survives downstream feedback by expression)
//   par   = the live DISPERSION GAIN. Published rather than duplicated as a parameter on every
//           downstream node: two numbers that must be kept in agreement by hand will disagree.
//   wl0   = resolved total deviation of the chief path, degrees
//   wl1   = resolved spectral spread at the last interaction, degrees

bool  LtFlag(BenchRec r, uint bit) { return (((uint)max(r.flags, 0.0)) & bit) != 0u; }
bool  LtFlagF(float f, uint bit)   { return (((uint)max(f, 0.0)) & bit) != 0u; }
float LtSetFlag(float f, uint bit, bool on)
{
    uint v = (uint)max(f, 0.0);
    return (float)(on ? (v | bit) : (v & ~bit));
}

// A signature must survive a float round-trip EXACTLY, or the plan regenerates every cook and
// every hand edit dies. Two sub-2^16 integers are exact in fp32; asfloat() of an arbitrary uint
// is not, because a NaN payload is free to change.
float2 LtSigPack(uint sig) { return float2((float)(sig & 0xFFFFu), (float)((sig >> 16) & 0xFFFFu)); }
uint   LtSigUnpack(float2 f)
{
    uint lo = (uint)clamp(f.x, 0.0, 65535.0);
    uint hi = (uint)clamp(f.y, 0.0, 65535.0);
    return lo | (hi << 16);
}

// ---------------------------------------------------------------------------------------------
// Integer hashing. frac(sin(x)) collapses toward a few values once x is large, which shows up as
// a weighted draw coming out skewed and reads as a layout bug. Integer bit mixing only, so an
// arbitrary seed is as good as any other.
// ---------------------------------------------------------------------------------------------
uint ltHashU(uint x)
{
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}
uint  ltHash2(uint a, uint b) { return ltHashU(a * 0x9E3779B9u ^ ltHashU(b)); }
float ltRnd(uint a, uint b)   { return (float)(ltHash2(a, b) & 0xFFFFFFu) / 16777216.0; }
float ltRndS(uint a, uint b)  { return ltRnd(a, b) * 2.0 - 1.0; }
float ltRange(uint a, uint b, float lo, float hi) { return lerp(lo, hi, ltRnd(a, b)); }

// ---------------------------------------------------------------------------------------------
// BENCH SPACE.
//
// x in [0, 1], y in [0, BENCH_H] with y DOWN. ISOTROPIC — one bench unit is the same distance on
// both axes, so a rotation is a rotation and a prism does not shear when it turns. BENCH_H is
// 9/16 so bench space maps exactly onto the 1280x720 program image with no letterbox.
//
// The bench is a real breadboard: BENCH_MM across. Every readout in the plan is in millimetres,
// and every physical quantity (a 120 mm prism, a 12 mm beam) means something.
// ---------------------------------------------------------------------------------------------
#define BENCH_H      0.5625
#define BENCH_MM     400.0
#define LT_PI        3.14159265359
#define LT_TAU       6.28318530718

float  ltToMM(float benchUnits) { return benchUnits * BENCH_MM; }
float  ltFromMM(float mm)       { return mm / BENCH_MM; }

// The visible band the whole system is about.
#define WL_MIN 400.0
#define WL_MAX 700.0

#endif
