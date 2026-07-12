# Viewport events authoring guide and click_ripples example — 2026-07-12

## Progress saved

- Built `modules/click_ripples/`, a complete interactive paint canvas exercising the Phase 88 authored viewport events surface end to end: left-click and drag painting with per-event positions, wheel brush sizing, C palette cycling, X clear, authored bindings help, and a persistent energy field. Every behavior was proven with injected real input against the live app (focus click, drags, key taps) and output captures; `/viewport/delivered_boundary_count` and `/viewport/bindings` readbacks confirmed delivery.
- Rewrote the Authored Viewport Events section of `knowledge/module-pipeline.md` from that hands-on session into a real authoring guide: full manifest token vocabularies (including the separate `bindings[].gesture` vocabulary that fails compile if you use `input.gestures` tokens), the injected shader API with the `ViewportKeyDown`/`ViewportButtonDown`/`ViewportModifierDown` helpers, the complete event type/phase/code tables with key codes, verified position conventions (normalized preview space equal to pass `uv`), gesture semantics (click arrives once as type 5 code 1 phase 7; drags stream begin/update/end), the reduce-once-fan-out pass architecture, focus and hot-reload lifecycle, and the diagnostics plus input-injection recipe for verifying interactivity.
- Documented the critical `_DeltaTime` rule discovered the hard way: modules cook at an uncapped rate far above the display rate, so per-cook decay constants annihilate event-driven visuals within milliseconds, which presents as "events never arrive" while every diagnostic counts them. All rate math must scale by `_DeltaTime`.
- Updated the `module-authoring` skill (both trees) with the same verified gotchas and a pointer to the worked example.
- Reconciled another dev-build provisioning sweep: 46 files were content-identical churn, 5 stale files were re-synced from the current sentinel seeds.

## Still in progress

- The sentinel repo seed edits behind this guide remain uncommitted there; commit them before the next installer build.

This is a documentation and example checkpoint, not a phase or subphase completion.
