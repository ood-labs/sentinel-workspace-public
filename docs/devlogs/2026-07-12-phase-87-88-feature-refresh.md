# Workspace feature refresh for 0.5.29 and phases 87-88 — 2026-07-12

## Progress saved

- Audited the delta since anchor `390b3302` (0.5.29 release, Phase 87 UI polish, Phase 87.1 Properties reset, Phase 88 interactive viewport events) and refreshed every affected doc.
- Recovered a provisioning regression: the installed 0.5.29 build was compiled before the current sentinel seed edits were committed, so its workspace provisioning overwrote the committed manuals, knowledge, and skills with older content. The drift was discarded and the current seeds re-copied; the version bump to 0.5.29 was kept.
- Agent manuals (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`): Node Presets now states `sentinel_preset` is carried by installs at 0.5.29 or newer; the module authoring section notes the `viewport:` block and the authored-events surface with a "builds newer than 0.5.29" caveat.
- `knowledge/module-pipeline.md`: new Authored Viewport Events section (interest tokens, bindings help, injected `_ViewportEvents`/`_ViewportEventCount`/key-bit globals, router focus and capture priority, cancellation semantics, `_Mouse` fallback).
- `knowledge/FEATURE-MAP.md`: `sentinel_preset` entry for 0.5.29+.
- `knowledge/scene-system.md`: camera fly/orbit toggle corrected from `C` to `Tab` (Phase 87), with the gizmo flash.
- `module-authoring` skill (both skill trees): `Tab` toggle correction plus an authored viewport events pointer with the availability caveat.

## Still in progress

- Remove the Phase 88 "builds newer than 0.5.29" caveats once an installer ships authored viewport events.
- The sentinel repo seed edits behind this refresh still need their own commit there; until they land, a new installer would regress these docs again.

This is a documentation refresh checkpoint, not a phase or subphase completion.
