# Expressive Flow Layers

This generator builds an RGB warp map from up to three geometric vector fields. Neutral displacement is `(0.5, 0.5)` in red/green; deviations encode signed X/Y flow for StreamDiff's Warp Map input. Blue can carry magnitude, rings, interference, or one layer's contribution.

The parent study bundles `modules/_shared/show_timeline.hlsli`, which supplies deterministic phase and lifecycle helpers used by `flow.hlsl`.
