# StreamDiff

Pipeline type: `streamdiff`

StreamDiff is Sentinel's real-time image generation pipeline. It uses TensorRT engine packs and runs best on high-end NVIDIA RTX GPUs.

## First Use

StreamDiff needs large engine packs. On a fresh install:

1. Use `sentinel_app action=engine_status` to see `gpu_arch` and missing packs.
2. Install the required StreamDiff pack for the host GPU using `download_pack` or `install_pack`.
3. Poll `engine_status` until the relevant packs are `complete`.
4. Create the `streamdiff` pipeline and inspect it with `sentinel_pipeline info`.

For a small first-run engine test, `depthestimation` with pack `auxiliary` is faster than StreamDiff.

## Engine Families

StreamDiff packs include:

- shared SDXL core engines;
- resolution-specific IP-Adapter UNet engines;
- optional ControlNet + IP-Adapter engines;
- optional FP8 engines on supported Ada or Blackwell GPUs.

Use the engine dropdown in the UI or inspect parameters through MCP to select available profiles. Download size can be several GB.

## Inputs And Outputs

Slot 0 is the main generated output. Some configurations expose additional outputs such as depth. Use `sentinel_pipeline info` to inspect available output slots.

StreamDiff is heavy. A healthy node can still take several seconds to load engines or reinitialize after engine/profile changes.

## Hold And Render One

`hold` is a persistent bool parameter that keeps the node live while suppressing new diffusion. Use it to freeze a generated still without bypassing the whole node.

`render_count` is a persistent int, default 1. `render_one` is a momentary button/action at `/sentinel/pipelines/<id>/actions/render_one` and `/sentinel/pipelines/<id>/parameters/render_one`; it queues `render_count` diffusion frames, then returns to hold.

## Atlas Still Capture Tuning

For atlas still capture and single-image generation, use a separate tuning bundle from the smooth live-video defaults:

| Parameter | Value |
|-----------|-------|
| `seed_travel_enabled` | `false` |
| `seed_locked` | `false` |
| `frame_skip` | `1` |
| `denoise` | `0.972` |
| `feedback` | `1.0` |
| `ipadapter_enable` | `false` |
| `zoom` | `0.0` |
| `image_noise_strength` | `0.0` |
| `sharpen` | `0.0` |
| `render_count` | `1` |

This was captured from the live `Atlas Still Capture` preset on 2026-07-05. Treat prompt text as user content, not as part of the generic atlas default. An atlas capture controller should apply this behavior bundle, set `hold=true` while it owns capture, and invoke `render_one` once per cell.

## Good Automation Checks

After creating or changing StreamDiff, verify:

- `stats.healthy` is true;
- `stats.statusMessage` says ready or equivalent;
- `framesProcessed` climbs;
- the node has a preview SRV;
- captures are nonblank.

Do not treat a successful create call as proof that engines loaded.

## Hold And Single-Frame Render

- `hold` (bool parameter): freezes diffusion while the node stays live. Input mapping, pre-image processors, and control/style inputs keep flowing; the last generated frame republishes. Finer than the `/enabled` bypass, which stops the node cooking entirely.
- `render_one` (momentary action at `/sentinel/pipelines/<id>/actions/render_one`): fires exactly `render_count` diffusions then re-holds.
- `render_count` (int, default 1): render-N-then-hold.

All three are StateTree parameters, so OSC, expressions, MCP, and scene-group presets reach them. Use hold plus `render_one` for one-clean-still-at-a-time workflows such as filling an `atlas` node.

## Multiple Variants, Shared Engines, Mux

Several StreamDiff variants using the same engine files share loaded TensorRT engines through a ref-counted pool, so N variants cost one engine load (execution is one at a time). Switch between variants live with a `mux` node (`selected` picks 1-of-8 inputs); enable the mux's `solo_upstream` so the non-selected variants auto-hold and only the visible one diffuses. See `knowledge/scene-system.md`.

## Generated Subjects In An Authored Composition

Placing generated imagery into a graph that already has a plan authority: author each family
twice, drawn and generated, at the *same* plan records, so the compositor cannot tell them apart
and a single gain crossfades between them.

The chain, one per family:

```
conditioning records -> streamdiff -> matting -> stamp (reads the plan) -> compositor
```

The stamp reads the plan's records and the generated plate never decides placement. That is what
makes drawn and generated versions interchangeable; it is the same "one authority owns placement"
rule from `knowledge/reference-build-method.md`, applied to a generator.

### Generate photoreal on black, never a drawing

Counter-intuitive and load-bearing. A matting node is trained on photographs and cuts a real object
far more cleanly than a flat illustration, so ask for **hyper-real 4K on a solid pure black
background** even when the finished look is a drawing. Apply the drawn look — posterize, edge
detect, ink — as a **post effect in the stamp, after the cut**, where tuning it cannot damage the
matte. A lit subject on black also gives you a luminance key to cross-check the matte with, which
the next point depends on.

### Prompt lighting words decide whether the plate is mattable

| Say | Not |
|-----|-----|
| brightly lit, large softbox, bright even studio lighting, bright frontal illumination | dramatic lighting, rim lighting, hard raking light, chiaroscuro |

Asking for a subject *on black* plus *dramatic light* returns a subject that is itself in shadow — a
smoky mass with no silhouette for the matte to find. This is the single highest-leverage line in the
prompt; changing only these words turned an empty stamp into a clean marble profile.

### Never fix a dark plate with the `brightness` parameter

`brightness` lifts the **whole image**, including the black background. The luma key dies, the matte
claims the entire frame, and the stamp lands as a rectangular slab. Exposure belongs downstream,
where it can be measured against the matte. Keep `brightness` near 0 and fix darkness in the prompt
or in the stamp.

### Auto-expose in the stamp, do not tune levels by hand

Generator output brightness is **not repeatable**. The same prompt bank returns a chalk-white marble
hand on one fire and a hand almost entirely in shadow on the next, so fixed levels can only ever be
correct for the plate that happened to be on screen when they were set — fatal for an unattended
cadence. Add a measurement pass ahead of the stamp pass:

- walk the plate on a coarse grid (a few thousand taps, one thread, no atomics needed);
- count only pixels the **matte** calls foreground;
- publish the subject's black point and a luminance **percentile**, not a max — a max is hostage to
  one specular glint on a knuckle, which would set the white point for the whole subject;
- fall back to authored values when coverage is near zero, so a mid-generation plate does not drive
  the exposure off sixteen stray pixels.

### The matte is saliency, not a key — gate it with luminance

A background-removal matte decides what a picture is *about*. It will happily annex the empty
backdrop beside a subject as part of the same object; on a studio bust it returned a matte covering
the entire left half of the frame. Multiply it by a soft luminance gate — the lit-on-black plate
makes that an independent and reliable second opinion — and keep a mix parameter so a plate where
the matte is genuinely better can turn the gate off.

### Ordered duotone beats nearest-ink snapping on desaturated subjects

Snapping generated colour to the nearest palette entry is a per-pixel decision with no memory of its
neighbours. On a saturated subject it is fine — a green frond lands on the greens and stays. On a
**desaturated** one it falls apart: a pale marble hand is a field of near-equal greys, grey sits
almost equidistant from several inks, and neighbouring pixels leapfrog between them, mottling the
subject into camouflage. Ramp between a dark and a light ink by luminance instead. The choice
becomes ordered, adjacent tones cannot swap, and it is also what a two-colour riso separation
physically is.

### Feedback hygiene for held stills

Three silent failures. Nothing errors, the node reports healthy, and the damage only shows up as a
slowly degrading image several generations later.

| Rule | Without it |
|------|------------|
| Invoke `reset_feedback` **before every** `render_one` | `render_one` refines the *previous* frame; at high feedback each generation compounds on the last and the subject degrades within a few fires |
| Zero `zoom`, `pan_x`, `pan_y`, `rotation` | default `zoom` is `0.02`, which combined with feedback progressively zooms the loop every frame and smears the plate |
| Keep `controlnet_scale` around **0.6–0.7** | tighter glues the output to the control image and kills the model's contribution; much looser and the conditioning stops steering at all. Expect to dial it in |

The `zoom 0.0` in the Atlas Still Capture table above is this same rule.

### Cadence: publish a level, not a pulse

To regenerate families on independent clocks, drive `hold` from a controller's control output and
`prompt_position` from a monotonic fire counter (`fires % N` walks the prompt bank). Publish `hold`
as a **level**, not a one-cook pulse: the controller cooks far faster than its consumers, so a pulse
is unsamplable and will be missed. Stagger the lanes with offsets so families never fire together.

### Crop and size are separate decisions

A stamp needs `plate_zoom` (which part of the plate fills the record) independent of `stamp_scale`
(how big the record is). Scale alone does both at once — it widens the record's extent *and*, since
the same coordinates span a bigger box, narrows the plate region sampled — so framing a bust on its
head also doubles it in the composition. Related trap: test the record's footprint **independently**
of the plate crop. Deriving it from "is the plate coordinate inside `[0,1]`" ties them together, and
zooming in then shrinks that range, lets more of the canvas pass, and silently grows the stamp until
it covers everything. Feather both boundaries, or a subject leaving the record ends in a square
corner that reads as a compositing bug.

## Focused Workflow Examples

The portable collection at `projects/streamdiff_workflows/` isolates six patterns that are easy to confuse in a larger show:

1. image-space feedback zoom;
2. integrated depth-parallax feedback with auto-depth ControlNet;
3. content-aware tuning of that depth pattern for architectural flythroughs;
4. direct input-mode Mux switching with `solo_upstream`;
5. external video -> Depth Estimation -> Control Image conditioning;
6. authored RGB flow maps -> Warp Map displacement.

These studies deliberately omit Scene Groups and preset banks. They are technique specimens, not complete show looks. The direct Mux study also does not replace the separate groups-mode Scene Switcher pattern: use input mode for several individual textures, and groups mode when switching complete multi-node looks with one Group Output in each Scene Group.

### Feedback motion layers

Keep these motion mechanisms conceptually separate when debugging:

- `zoom`, `pan_x`, `pan_y`, and `rotation` transform the previous image in 2D;
- `depth_parallax` reprojects it according to estimated depth;
- `controlnet_auto_depth` uses projected prior-frame depth to condition the next diffusion result;
- an external Control Image supplies structure from another node, such as Depth Estimation;
- `warp_enabled` consumes a Warp Map and displaces the feedback loop by its encoded vector field.

Combining mechanisms is valid, but first prove each one in isolation. A flat zoom with depth disabled is the control case for depth-parallax tuning; a neutral-gray warp map is the control case for procedural displacement.

### Engine-safe review sequence

Engine profiles are large and can take seconds to unload. When reviewing a collection, load one saved project at a time and wait for `stats.has_preview_srv=true` before capturing or moving to a different resolution/tier. Avoid repeatedly cold-loading 896x512 and 512x896 ControlNet projects in immediate succession, especially on a constrained GPU.

Do not assume `engine_precision=Auto` will fall back across every installed pack in every build. Sentinel 0.5.38 was observed reporting `compatLevel=no_engine` when the saved 896x512 input-tier study used Auto but only the FP8 pack was installed. Save and document the precision that was actually proven, then tell users which alternate pack/precision to select on other GPU generations.
