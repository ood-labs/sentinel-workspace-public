// Orientation mark: a letter F in the top-left cell of the 4x4 grid.
// F has no symmetry, so a flip, a mirror or a 90-degree rotation anywhere
// downstream is immediately readable.
//
// Coordinates are the [-1,1] space the pixel pass uses: x right, y DOWN
// (p = uv*2-1). grid.hlsl negates y as it writes the Scan Signal, which is
// ILDA scanner space (+y up), so the F is upright on the wall with no flips.
static const int F_STROKE_COUNT = 3;

void fStroke(int k, float extentIn, out float2 a, out float2 b)
{
 float cell = extentIn * 0.5;                    // 2*extent spans 4 cells
 float2 o   = float2(-extentIn, -extentIn);      // top-left cell corner
 float x0 = o.x + 0.29 * cell, x1 = o.x + 0.71 * cell;
 float yt = o.y + 0.15 * cell, yb = o.y + 0.85 * cell;
 float ym = lerp(yt, yb, 0.45);                  // middle arm height
 float xm = lerp(x0, x1, 0.75);                  // middle arm is shorter
 if (k == 0)      { a = float2(x1, yt); b = float2(x0, yt); }  // top arm, right to left
 else if (k == 1) { a = float2(x0, yt); b = float2(x0, yb); }  // spine, top to bottom
 else             { a = float2(x0, ym); b = float2(xm, ym); }  // middle arm
}
