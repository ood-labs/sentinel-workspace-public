# Reference Build Method

Use this when the job is **build an ambitious specific thing, from scratch, in one pass** —
a reference image, a described composition, a "make me X" brief.

This is a different mode from `knowledge/creative-exploration-goals.md`, which evolves an
existing project indefinitely. Here there is a target, the graph starts empty, and the run
ends with a saved, proven show.

Worked example: `projects/matik_plate/` (read its README for the applied form).

---

## 1. Inventory before you build

Before writing any code, produce three things in the response:

1. **A complete element inventory of the reference.** Every distinct visual family, not a
   summary. Missing a family early is what forces a rewrite late.
2. **The node decomposition.** Name every node and its one responsibility.
3. **The data contract.** The record structs and which node owns each.

Do this even when the user did not ask for a plan. The cost is one message; the cost of
discovering the layout authority after building three renderers is the whole build.

State the archetype out loud (see `modular-scene-authoring`). **Hybrids are normal** — a
dense collage of technical panels plus organic 3D masses is a routing problem *and* an
organic problem. Unify hybrids under one record buffer with a `role` discriminator rather
than running two parallel contracts.

---

## 2. Elect a single plan authority

**One node owns placement. Every other node derives from its records and never re-decides
them.**

This is stronger than "one layout transform at the generator". The transform rule prevents
drift; the authority rule is what makes the finished graph *expressive* — because every
question about "where is anything" has exactly one answer, rearranging becomes a property of
the system rather than a feature you have to build.

Consequences to hold onto:

- Downstream nodes read plate/scene space straight off `uv` or off the records. They apply
  no global offset or scale of their own.
- Anything derivable from the records is derived, not published as a second lane. See the
  coverage rule below.
- The authority's preview becomes the diagnostic surface for the entire system. Invest in it.

Build the authority **first**, in signal-flow order. It is usually not the fun node.

---

## 3. Generate, then override

**The plan authority is a direct-manipulation editor. This is the default, not an option.**

Build it that way unless the user has explicitly said they want a fixed non-interactive
image. "The brief was a picture, not an editor" is **not** a reason to skip it — a plan you
cannot click is a dead end the moment the user wants the composition changed, and changing
the composition is the whole reason the plan authority exists.

**It must produce a complete, good result procedurally, and let interaction override
individual records on top of it.**

- The node is useful and unbroken from the first frame, before anyone touches it.
- Global parameters keep working after hand edits, because edits are deltas, not a
  replacement authoring model.
- "Re-roll this one record", "turn this one off", "cycle this one's kind" become trivially
  expressible, because a record already exists to mutate.
- Persistence stays cheap and meaningful — only the deltas matter.

The failure mode this replaces is the empty editor: a node that renders nothing until the
user authors everything by hand, and whose global controls fight the hand edits. The *other*
failure mode — the one that is easier to ship by accident — is the **opaque plan**: a node
that generates a good composition and then offers nothing but a seed and a variation slider.
It looks finished and it is not.

### When this applies

Whenever the build has **an arrangement worth randomizing or exploring** — which is most
reference work — it gets a plan authority, and that plan authority is manipulable. A plan
whose entire interface is a seed and a variation slider is an **opaque plan**: it looks
finished, and the first time anyone wants *that one element* moved, the system has nothing
to offer.

### The bar, not the template

`projects/soft_vitrine/modules/VT_Plan` is the benchmark. Read it before authoring a new plan
authority — not to clone its record layout or its keymap, but because it is the clearest
example of the bar being cleared: every element reachable and changeable, exploration cheap,
and a randomizer whose draws still read as compositions rather than scatter.

**Design the verbs for the subject.** VT_Plan cycles kind and material because its cast is
kinds and materials; a typographic plate might want to cycle weight and alignment, a
lighting rig to cycle beam shape. Pick the two or three properties that actually define an
element in *this* reference and make those the edits. Click-to-select and drag-to-move are
close to universal; past that, invent what fits.

What is **not** negotiable, because these are correctness properties rather than style:

- **Persistent records.** A `state_buffers` set so edits survive cooks, saves, presets, undo.
- **Signature-driven regeneration.** Structural parameters only (see below).
- **Selection stored once.** Derive every "am I selected" test from that single value rather
  than mirroring a flag onto records and keeping the two in sync.
- **Pick in the same space you draw in.** If the preview and the hit test derive their
  coordinates independently they will disagree, and it will look like a maths bug.
  Smallest-hit-wins, so a small record resting on a large one stays reachable.
- **A preview that shows editor state** — what is selected, what has been hand-edited, what
  has been switched off.
- **Randomness that still composes.** Stratify placement and preserve the size hierarchy so
  a random seed reads as a composition. `variation = 0` should be exactly the transcribed
  reference, so it can never be lost.

Implementation shape:

```
persistent buffer of resolved records + one editor header record
  signature = hash(all STRUCTURAL parameters + algorithm version + reseed salt)
  if (never initialised || signature changed) -> regenerate everything, clear selection
  else                                        -> keep the buffer, apply this frame's edits
  then, every cook: refresh appearance-only fields in place (they must not force a rebuild)
```

Regeneration must be signature-driven, not unconditional, or edits die every cook. Keep
pure-appearance parameters *out* of the signature and republish them each cook instead, or
every colour tweak wipes the user's layout work.

### Derived records follow their parent

When one record's placement derives from another (chips on a plate, leaves on a branch),
dragging the parent must carry the unedited children with it, while children the user has
hand-moved keep their own position. That is what the per-record `edited` flag is for.

### You will not be able to machine-prove the gestures — build them anyway

Injected input does not reach Module viewport events, so click/drag/key paths generally
cannot be verified over MCP. **This is a reporting obligation, not a reason to omit the
feature.** Build the full gesture set, verify everything reachable (buffer persistence,
signature behaviour, pick maths against known record coordinates, the preview's selection
readout), then say plainly which gestures the user needs to exercise by hand.

---

## 4. Derive magnitudes from upstream records, never from a parallel parameter

If a downstream node needs a size, a spacing, or an extent that *relates* to something an
upstream node already decided, compute it from the upstream record geometry.

Worked case: the organism grower sized its trees from the reserve radius the plan authority
had already cleared for them. One control then moved the clearing, the growth, and the panel
layout coherently.

The alternative — giving the downstream node its own independent size parameter — produces
two numbers that must be kept in agreement by hand, forever, and that silently disagree at
every setting the author did not personally test.

---

## 5. Coverage and masking authority

Masks have the same single-authority problem as placement.

- **Derive the mask from the records** wherever the records determine it. A compositor that
  recomputes panel coverage from the same records the panels were drawn from cannot drift
  out of registration with them.
- **Publish a real coverage lane only where colour genuinely cannot carry the information.**
  An opaque black shape on a black background is indistinguishable by colour; that needs its
  own lane.

Do not smuggle coverage into a colour lane's alpha to avoid adding an output. It makes the
node's own preview read wrong, which violates the honest-preview contract.

---

## 6. Exploration as shipped presets

When exploring alternatives, **do not build throwaway variants**. Build the exploration axis
as a permanent `enum` parameter on the node that owns it, then:

1. Sweep it and capture each value.
2. Judge from the images and pick a winner.
3. Bake the winner as the manifest default.
4. **Repair the losers instead of deleting them.**

Exploration cost converts directly into product features, and the user keeps every direction
that was investigated. A preset that lost on this reference is often the right answer for the
next one.

Record the verdict and the reasoning in the project README so the next agent does not repeat
the search.

Two to four axes is the useful range. Good axes change structure (layout strategy, mesh
style, growth mode). Palette and grade are not exploration axes.

---

## 7. Judge from the image after every change

Capture and actually look after every material edit. Do not reason your way to a fix.

Structural systems typically need several wrong iterations before they are right, and each
wrong one is diagnosable from a single capture in seconds and nearly undiagnosable from
theory. In the worked example the growth model took four attempts:

| Symptom in the capture | Cause | Fix |
| --- | --- | --- |
| Clusters collapse into knots | bond length followed radius decay geometrically | constant bond length, radius tapers then holds |
| Clusters fuse into featureless balls | children scattered back across the parent | outward direction persistence |
| Clusters march off the canvas | unconstrained persistence | soft containment steering inside the reserve |
| Clusters grow one-sided | root inherited a default up-vector | distribute first generation evenly on a sphere |

None of these were visible from the code. All were obvious from the picture.

---

## 8. Converge and hand over

Before reporting done:

- **Bake tuned values into the manifests** (`sentinel_module action=bake_defaults`) so the
  saved project reopens in the state you tuned, not in the state you first guessed.
- Save with `save_project bundle_modules=true` so the show travels with its Module files.
- Curate the Scene Group surface to 4–8 high-impact controls and **test every one through
  the group path**, confirming it reaches the member parameter.
- Profile the graph and confirm every node is healthy with frames advancing.
- Write a project README covering the route, the contracts, the traps, and the exploration
  verdicts.
- Produce proof: a final capture, a motion clip if anything animates, a proof bundle.

**Report what you could not verify.** Injected input does not reach Module viewport events,
so an authored click/drag/key path usually cannot be machine-proven — say so plainly and say
what the user needs to exercise. An honest gap costs nothing; a silent one costs trust.

---

## 9. Momentum

Work the visible one-node-at-a-time cycle continuously without asking for approval between
nodes. The contract is *visible incremental construction*, not stop-and-confirm gating. Ask
only when two readings of the brief would produce materially different work.

Do not narrate options you are not going to take. Choose, build, capture, judge, continue.
