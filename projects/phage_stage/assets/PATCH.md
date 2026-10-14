# PHAGE patch

Written by `tools/phage_mvr.py` with `assets/phage_rig.mvr`. Universes are MVR numbers (Art-Net port address
= universe - 1). The Fixture Rig node owns the patch once it has imported the plot; this sheet is the plot as
generated.

- **Fixtures:** 561 (100 Halo Beams, 41 Linear Strobes, 420 Pixel Batten 1000 in 47 runs)
- **Pixels:** 8400 RGB pixels on 420.0 m of batten (the runs measure 457.7 m)
- **Universes:** 57

| Group | Type | Mode | Fixtures | FixtureIDs | Patch |
|---|---|---|---|---|---|
| Plate Out Movers | Halo Beam | Standard 15ch | 24 | 1-24 | 1.1 - 1.360 |
| Plate In Movers | Halo Beam | Standard 15ch | 12 | 25-36 | 1.361 - 2.30 |
| Capsid Movers | Halo Beam | Standard 15ch | 24 | 37-60 | 2.31 - 2.390 |
| Knee Movers | Halo Beam | Standard 15ch | 12 | 61-72 | 2.391 - 3.60 |
| Collar Movers | Halo Beam | Standard 15ch | 6 | 73-78 | 3.61 - 3.150 |
| Booth Movers | Halo Beam | Standard 15ch | 16 | 85-100 | 3.151 - 3.390 |
| Foot Movers | Halo Beam | Standard 15ch | 6 | 101-106 | 3.391 - 3.480 |
| Collar Strobes | Linear Strobe | Standard 7ch | 6 | 129-134 | 4.1 - 4.42 |
| Plate Strobes | Linear Strobe | Standard 7ch | 12 | 135-151 | 4.43 - 4.126 |
| Knee Strobes | Linear Strobe | Standard 7ch | 6 | 153-158 | 4.127 - 4.168 |
| Foot Strobes | Linear Strobe | Standard 7ch | 6 | 159-164 | 4.169 - 4.210 |
| Capsid Strobes | Linear Strobe | Standard 7ch | 5 | 165-169 | 4.211 - 4.245 |
| Booth Strobes | Linear Strobe | Standard 7ch | 6 | 170-175 | 4.246 - 4.287 |
| Leg Upper Pixels | Pixel Batten 1000 | Pixel 60ch | 84 | 10001-12107 | 5.1 - 15.240 |
| Leg Lower Pixels | Pixel Batten 1000 | Pixel 60ch | 108 | 10201-12309 | 15.241 - 28.480 |
| Plate Edge Pixels | Pixel Batten 1000 | Pixel 60ch | 24 | 12401-12904 | 29.1 - 31.480 |
| Sheath Pixels | Pixel Batten 1000 | Pixel 60ch | 60 | 13001-13412 | 32.1 - 39.240 |
| Collar Pixels | Pixel Batten 1000 | Pixel 60ch | 48 | 13501-13624 | 39.241 - 45.240 |
| Capsid Square Pixels | Pixel Batten 1000 | Pixel 60ch | 48 | 13701-14208 | 45.241 - 51.240 |
| Capsid Link Pixels | Pixel Batten 1000 | Pixel 60ch | 24 | 14301-14508 | 51.241 - 54.240 |
| Booth Pixels | Pixel Batten 1000 | Pixel 60ch | 24 | 14601-14624 | 54.241 - 57.240 |
