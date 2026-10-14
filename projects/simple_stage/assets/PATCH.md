# SIMPLE STAGE patch

Written by `tools/ss_stage.py` with `assets/simple_stage.mvr`. Universes are MVR numbers (Art-Net port
address = universe - 1). The Fixture Rig node owns the patch once it has imported the plot; this sheet is
the plot as generated.

- **Fixtures:** 76 (16 Halo Beams, 12 Linear Strobes, 48 Pixel Batten 1000 in 12 wall runs)
- **Universes:** 7

| Group | Type | Mode | Fixtures | FixtureIDs | Patch |
|---|---|---|---|---|---|
| Front Row | Halo Beam | Standard 15ch | 8 | 1-8 | 1.1 - 1.120 |
| Back Row | Halo Beam | Standard 15ch | 8 | 9-16 | 1.121 - 1.240 |
| Truss Strobes | Linear Strobe | Standard 7ch | 6 | 33-38 | 1.241 - 1.282 |
| Floor Strobes | Linear Strobe | Standard 7ch | 6 | 39-44 | 1.283 - 1.324 |
| Pixel Wall | Pixel Batten 1000 | Pixel 60ch | 48 | 10001-11104 | 2.1 - 7.480 |
