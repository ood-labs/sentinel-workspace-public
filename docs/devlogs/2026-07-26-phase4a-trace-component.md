---
type: devlog
date: 2026-07-26
phase: 4
subphase: 4A
status: complete
approval: pending
summary: "Extract the audio_bands strip chart into sui3_trace.hlsli and document its four mechanisms"
---

## Done

`modules/_shared/ui/sui3_trace.hlsli`, 15 pure functions covering the four mechanisms lifted out of
`modules/audio_bands`: ring addressing with generation catch-up, decaying-peak autoscale with a
mandatory floor, max-reduce column spans, and reference-level participation in the full scale.

**4A.1** `compile_check` on `modules/_trace_probe` returns `compile_ok: true`, `params: 0`,
`passes: 2`. The probe declares no viewport block and no parameters, and both of its passes call
every public function in the header, so nothing is unproven for having gone uncalled.

**4A.2** Purity confirmed by grep: no `_Resolution`, `_DeltaTime`, `_DataN`, `register()`, text,
theme, or `au_` reference anywhere in the header outside comments. Every extent is an argument.

**4A.3** `knowledge/ui-authoring.md` gains a "Scrolling Data Traces" section carrying each mechanism
with the measurement that justifies it, plus the "when not to use it" case and an entry for
`audio_bands` as the reference consumer under Reference Examples.

Two design calls worth recording. The column reducer returns an index span rather than a value,
because HLSL cannot take a resource as a function argument and a macro that reaches for a buffer by
name would stop the header being shareable. And the strip's Y is value-up, opposite to
`sui3PadPoint`: a pad's direction is forced by a host that disagrees with itself, a plot's is not.
Both are documented in the header so neither reads as an oversight later.

## Next

4B: the Data Scope station. Audio In on a real source, `follow_panel` canvas, and the four
behavioural criteria including the autoscale and transient-survival assertions.
