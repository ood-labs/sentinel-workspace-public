---
type: devlog
date: 2026-07-15
phase: 1
subphase: 1G
status: complete
approval: pending
summary: "Modernize Strata as a premultiplied modular composition desk with a real Features thread"
---

## Done

- Preserved the original eleven-node modular plate graph and its premultiplied-alpha composition.
- Rebuilt `strata_control` as a responsive gray-and-red Composition Desk with thirteen focused controls, fourteen control outputs, and a live count from the real Features corner buffer.
- Added a composition-specific `marble_focal` parameter gesture to `marble_panel`; no generic selection, gizmos, or unrelated editor behavior was introduced.
- Added shared palette variants across the authored passes without collapsing their distinct texture and data lanes.
- Connected live Features corners to both the corner-thread renderer and the Composition Desk, then proved the thread's enabled and disabled states visibly.
- Organized all twelve active nodes in one flat low-alpha purple Scene Group with exactly one Group Output, seven non-conflicting controls, and five distinct presets.
- Added project-scoped **Atelier Plate Balance** and **Hero Sculpture** node presets with explicit parameter stacks.
- Replaced absolute bundled paths with project-relative paths and removed all scoped shader caches.

## Proof

- Clean Studio, Melted Chrome, Graphic Poster, Wire Cage, and Performance produced visually distinct final captures without black alpha boxes or broken plate continuity.
- Live `features_0` inspection reported fifteen corner records with an active GPU buffer generation.
- Moving `panel_center` changed the visible marble focal; the declared viewport binding exposes the same left-drag interaction to a human.
- Performance bypassed Features, selected one-sample sculpture AA, and held approximately 59.7 FPS with healthy active nodes.
- All ten authored modules passed Sentinel `compile_check` and the official-example validator passed the portable project.

## Taste rules carried forward

- Add only interactions that belong to the scene's real semantic model.
- Keep the Scene Group small and non-conflicting when an authored Canvas already owns composition controls.
- Preserve separate plates and premultiplied alpha instead of merging a strong modular graph into one renderer.
- Use one flat group, one final output, low-alpha purple annotation styling, and no nested groups.

## Next

- Subphase 1H modernizes Desert Totem as a safe procedural sculpture workstation.
