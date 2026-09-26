---
name: motion-graphics-sequences
description: Build choreographed motion-graphics sequences in Sentinel — 2D, 3D, generated or hybrid — as a chain of authored acts with designed transitions, driven by one editable, scrubbable score that owns time and placement. Use when a user asks for a motion graphics piece, title sequence, animated loop, sting, show opener, "a sequence in the style of <reference>", or several looks chained with custom transitions rather than crossfades.
---

# Motion Graphics Sequences

A motion-graphics sequence is a **time-organised** composition: a set of looks ("acts"), each
with its own choreography, joined by transitions that are designed rather than faded. This skill
fixes only what every such piece needs. **Everything else, above all the shape of the node graph
and the form of the editor, you design fresh for the piece in front of you.**

Read first: `knowledge/reference-build-method.md` (plan authority, generate-then-override,
presets, "design the scaffold for the subject"), `knowledge/motion-choreography.md`, and the
`module-authoring` and `module-ui-authoring` skills. For 3D, also read
`knowledge/internal-camera-template.md`.

The worked examples are **each one answer to one brief**, not templates. Neither is bundled in
this public workspace yet; the appendix below records the techniques worth reusing from them:

- **Threshold Rush** — a 2D cel piece.
- **Dot Matter** — 16,384 conserved dots carried through flat, image-space and 3D acts.
  It has the most developed score instrument so far: typed records, an inspector, a view that
  changes with the act, and meters and alarms computed by the renderers' own functions.

Do not reuse their layering, modules, palettes or looks unless the user asks for a remix.

## 1. The fixed contract

These hold for every sequence, whatever it looks like or however it is built:

1. **One timing authority.** A single node owns the clock (a phase accumulator, so live tempo
   changes never jump the playhead) and publishes it as a record every other node reads. Nothing
   runs on free `_Time`. If a Conductor, audio analysis or OSC drives time, it feeds this
   authority rather than replacing it.
2. **Acts are typed records.** Order and duration are stored; start times are derived every
   cook, so no edit can open a gap or an overlap. Everything an act owns (hero elements, camera
   marks, words, focus points, anything) is a record too, linked to the act by a stable uid, not a
   slot index. Every record has a kind from a shared enum and a documented per-kind field layout,
   in one contract header that every node includes.
3. **One placement authority.** Whatever decides where things are — 2D positions, 3D marks, a
   camera path, which generated plate goes where — is decided once, in records, and read
   everywhere else. Renderers never re-decide it.
4. **One transition contract.** How an act hands off to the next is defined once (a function,
   a record, a shared header) and every node that participates reads the same definition, so
   layers or renderers cannot disagree about which act owns a pixel or a moment.
5. **It is an instrument that tells the truth.**
   - The score is directly editable and scrubbable: select and change an act, reorder, resize,
     move what it owns, pause, seek.
   - Anything you can select names itself (what it is, what kind) and shows the few properties
     that define it.
   - What the editor draws (placements, budgets, alarms, the transport state) is computed with
     the same functions and tables the renderers use, so it cannot drift from the program.
   - An edge-triggered `cue` parameter makes every moment reachable from OSC and from
     deterministic proofs.
6. **Proven in motion.** You judge from per-act captures *and* a recording of the whole piece,
   not from reasoning.

## 2. Design the graph for this piece

**There is no default graph shape.** Before creating any node, plan the graph the way you would
plan the piece itself, and write the plan in the response. Work through these questions and let
the answers produce the topology:

- **What is the piece made of?** List every visual family across all acts (surfaces, type,
  props, characters, particles, camera, light, generated imagery, feedback) and which acts use
  each. Families shared across acts suggest shared nodes; families unique to one act may deserve
  their own.
- **What space does it live in?** Flat layers, a single 3D world, several separate worlds, image
  space (feedback, generation), or a mix. That decides whether acts share renderers or need their
  own, and what "placement" means in the records.
- **What do the transitions require?** A transition that needs both acts in one frame (a portal
  into the next world, a morph, a depth-aware wipe, a shared camera move) constrains the graph
  far more than a cut does. Decide where the outgoing and incoming acts must meet — the same
  shader, the same depth buffer, or a compositor fed by two renderers — and build towards that.
- **Where does time come from?** Fixed tempo, a Conductor sheet, audio, a performer's triggers,
  or a timecoded render. Keep one authority either way.
- **What is expensive, and what must stay live?** Heavy acts (generation, dense 3D) may need to
  render only while visible, run at a lower rung, or be banked. Plan cost with the topology,
  not after it.
- **What must each node's preview show?** Every node's own preview must make its role legible
  (`CLAUDE.md`: meaningful intermediate previews). If you cannot say what a node's preview
  would show, the decomposition is probably wrong.
- **What does editing need to reach, and in which view?** The score editor must be able to see
  and change what matters for *this* piece. A hybrid piece may need a different view per act:
  a frame for flat acts, or a plan with the camera's path and frustum for a 3D act. A section, a
  network or an audio view are also options. Design the editor's projection for the subject
  (`reference-build-method.md` §2.5).

Then state the decomposition: every node, its one responsibility, the data contract between
them, and how the transition contract reaches each participant. Challenge it before building:
is there a simpler graph that still delivers every transition? Is there a more ambitious one
the piece deserves? Sentinel can mix Modules, 3D renderers, mesh import, StreamDiff, Scene
Groups and Muxes, feedback, and audio in the same graph — do not limit the plan to the
techniques the examples happened to use.

Build it visibly, one node at a time (`CLAUDE.md`). Revise the plan when a capture shows it is
wrong, and say so.

## 3. Direction before code

- Study the reference for real: fetch the page, pull and look at the actual frames, and
  inventory palette, form language, type, motifs, camera and projection devices, and how the
  motion reads.
- Name the leap: what makes this more than the reference? Often it is the connective tissue:
  every hand-off a designed event, hits on the beat, or a camera or spatial idea that carries you
  through the acts. Something that persists through every act (the same particles, one camera,
  one character) makes the hand-offs feel inevitable.
- Write the direction plan: acts in order with durations, the transition between each pair,
  tempo or time source, the motion language, and what each node contributes.

## 4. Motion principles

- **Lock to the time source.** Entrances, cuts and hits land on beats, bars or cues from the
  clock record, never on free-running timers.
- **Springs and staggers from the shared vocabulary** (`anim.hlsli`, vendored into the
  project), never hand-rolled. Derive smear, squash and stretch from spring velocity.
- **Rate changes go through the phase accumulator**; target changes retarget from the current
  value and velocity.
- **Cadence is a design choice.** Holding character motion on twos, keeping camera motion
  smooth, or stepping everything are all valid; decide per layer and make it a score setting.
- **What is seen through a transition should already be alive.** Pre-roll the incoming act's
  entrances by the transition's length when the transition reveals it early.
- A transition that must stay legible (a portal, a reveal) should clear any effect that would
  bury it, such as smear, blur or fog.

## 5. The score editor

Present it as a full-bleed Canvas that follows the panel, with every rect derived from the live
size. Give it:

- scrub and seek;
- act selection, reorder and resize;
- direct manipulation of what each act owns, drawn in the view that act needs;
- an inspector: what the selection is, and the properties that define it;
- per-act cycling of the properties that define an act;
- a transport (key plus on-canvas button) with the `play` parameter kept as the master gate;
- a `cue` parameter for OSC and proofs;
- a drawn failure mode (whatever "this composition is broken" means for the piece).

### Patterns that proved themselves

These come from DOT MATTER's instrument. They are principles to keep, not a layout to copy.
Reinvent the form for each piece. If a piece organised along a path, a network, audio or a
performer wants a completely different instrument, build that instead. When something works
better than what is written here, write it back into this skill.

- **Typed selection and an inspector.** Selecting an act or an element shows what it is,
  down to the sub-kind (a word and which word, a figure and which figure, a window and its
  treatment), plus the handful of properties that define it, next to the stage. Generate the
  labels from the same tables as the enums, so the inspector can never name something the
  renderers do not draw.
- **One small verb vocabulary.** A few keys mean the same verb on every target: kind, palette
  or tone, look or transition, re-roll, hide, duplicate, earlier or later, bigger or smaller.
  Each record kind maps those verbs onto its own defining properties, so users learn the verbs
  once. Gestures follow the same idea: drag moves, a corner resizes, the wheel scales.
- **A lane that reads like the piece.** Each act block carries its own identity (for example its
  ground colour, muted), its hand-off drawn as a tail labelled with its kind, and dense runs (a
  card storm) as ticks, so the whole timeline is legible at a glance.
- **The view follows the act.** One stage can show many views:
  - the frame on the grid for a flat act;
  - a draughtsman's plan for a 3D act, showing the camera's path and its frustum;
  - the hand-off drawn at its pivot, such as a dive's aperture or a burst's origin.

  Switch views per act, based on what the act is.
- **Draw the program's own geometry, not a thumbnail.** Put words' dots at their real positions,
  subjects as their real footprints, links as the renderers' own curves, and the camera the
  renderer actually uses. A diagram built from the renderers' functions is exact and cheap; a
  downscaled render is neither.
- **Meters and alarms from the same functions.** A budget bar should be computed with the
  function the renderer enumerates with, and alarms should name the piece's real failure modes.
  If a deliberate, good-looking choice lights an alarm, the alarm's definition is wrong; fix it
  rather than shipping a red flag.
- **Show real state.** The transport shows the clock's actual state (master gate and pause
  together). Numbers on screen are real (a card's number is its actual ordinal). Nothing clamps
  silently.
- **Mostly monochrome** from `plan_theme.hlsli`: amber for the selection and the playhead, red
  only for broken, and a record's colours only where they are information.

Put structural exploration in an arrangement `enum` that rebuilds the sequence, and keep
random re-rolls scoped so they never touch the timeline. Re-deals that randomise relationships
(a window stays over its subject; a block never covers the subject's heart) stay presentable
at any seed. Bump a version constant that forces a rebuild whenever the default tables change.

**Input rules** (details in `knowledge/ui-authoring.md`, "Mouse Wheel And Held Keys"):

- **Consume every viewport event exactly once, by its `sequence` number**, in every event loop.
  Stale events are replayed on later cooks until newer input arrives: one wheel notch kept
  scaling until the mouse moved, and a held Space strobed.
- Scale wheel actions by `ev.value` (fractional notches). Tell users to use `Ctrl+wheel` if
  the host preview viewer takes the plain wheel.
- Latch toggle keys on press and release.
- Injected input never reaches viewport events. Build every gesture, verify the state logic
  through parameters, and tell the user which gestures need a hand test. When input
  misbehaves, add an on-canvas readout before theorising.

## 6. Build and proof loop

Per node:

1. Compile-check it, create it next to its neighbour, wire it, then focus it and open its window.
2. With play off, cue a moment inside each act, capture it, **look at it**, and fix before going
   downstream.

Once the program output exists:

3. Make **moment sheets** with `render_sequence`:
   - Use a sparse `cue_beat` track that holds each moment for four frames, so any staged or
     lagging passes settle.
   - Tile the last frame of each hold into a labelled sheet. One job proves 20–30 moments
     deterministically.
   - Tracks must name pipeline parameters; a Scene Group path is refused.
4. Record the whole piece in real time and make a contact sheet:
   `ffmpeg -i loop.mp4 -vf "fps=1,scale=384:216,tile=6x6" -frames:v 1 contact.png`.
   - Start paused at beat 0, start the recording, then play, so the opening is not clipped.
   - One image shows the choreography, pacing, transitions and dead spots. Look for long calm
     stretches around the loop point.
5. Sweep the arrangement enum, the re-deal and seed, and the quality rungs. Sweeps are honesty
   checks: they surface labels that clamp, alarms that fire on purpose, and constants that only
   hold at one resolution.
6. Profile, and build a quality ladder on the heaviest node (or the set of nodes that share a
   resolution). For 3D with an internal camera, save a frame contract (the camera preset). Save
   narrow project presets, curate a 4–8 control Scene Group, and verify each control through
   its group path and in the open group Properties.
7. Bake tuned defaults, save with `bundle_modules=true` to an explicit path, write the project
   README (graph rationale, contracts, traps, what was not verified), and make a proof bundle
   on the program node.

## 7. Traps

- **Resizing a persistent buffer (`element_count`) reallocates it and wipes live state**, taking
  the user's hand edits with it. Save first and reload afterwards, or reserve spare records up
  front.
- **A later pass reads an earlier pass's buffer one cook late**, for structured and texture
  buffers alike. Either predict each stage ahead by exactly its lag, or design the consumer so a
  one-cook-old read is harmless.
- **Two passes writing one buffer flip it between them.** Keep one writer per buffer, and
  restart counters with generation tags instead of a clear pass.
- **Draw passes have no alpha blending.** Overlapping antialiased marks (dots, particles) need
  compute binning into screen tiles and a per-pixel gather.
- **Pixel constants must scale with the output** (tile sizes, "big mark" thresholds, line
  widths), or each quality rung behaves differently.
- **A shader may index at most 4096 literal values.** Pack large tables, for example four ASCII
  codes per uint.
- **The shader cache keys on the main file**, and a file watcher can start a reload while a
  generator is still writing includes. After regenerating tables:
  1. clear `.sentinel/shader_cache`;
  2. force-reload;
  3. trigger the rebuild (bump the version, or toggle the arrangement away and back).
- Includes resolve from the **module folder**, not from the including header.
- HLSL has no struct ternary; select records with `if`. `line` and `pass` are reserved words.
- Every call site of a big painter inlines. Keep one call site per heavy function, or compile
  times climb past 30 s.
- A momentary `button` parameter written over MCP can pulse faster than a cook and be missed.
- Feedback nodes need `_DeltaTime`-corrected persistence, and must fall back to the live frame
  when their envelope is zero.

## Appendix: techniques from the worked examples

These are reusable pieces, not requirements.

### Threshold Rush

- **SDF word atlas** baked from an OFL font with Pillow and SciPy: one word per row, real
  kerning, and a generated `.hlsli` with per-letter spans so each letter can spring
  independently.
- **Extruded hatched type:** N offset copies; the first copy covering a pixel owns it, and the
  contour of the copy in front is inked. Use frame-relative hatch spacing.
- **Portal, streamer-wipe, melt and smash transitions** as one per-pixel function shared by the
  layers.
- **Quality ladder:** resolution with ink weight scaled alongside it, so every rung reads the same.

### Dot Matter

- **Conserved formations.** Rank the visible candidate sites of each formation with a prefix
  sum. Particle *i* then flies from rank ⌊i·n₀/M⌋ of the outgoing formation to ⌊i·n₁/M⌋ of the
  incoming one, with M = max(n₀, n₁). Merges and fissions come for free, and the whole piece
  stays deterministic and scrubbable.
- **Per-pixel ownership plus one schedule.** One function says which act owns a point and where
  it lands in that act. One stagger says when each point switches. Every layer reads both, so a
  plate's cells and the particles leave on the same beat.
- **Stage-wise prediction.** Each stage works ahead by exactly its inter-pass lag, so staged
  particles land on time against the plate.
- **An echo of only the moving marks.** Trail the composited frame minus the frame the marks
  were composited over, so surfaces stay crisp while the marks streak.
- **One generator script** writes the enums, arrangements, labels and word tables into every
  consumer, alongside a version constant.
