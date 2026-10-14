# Stage Equipment: Conventions, Contracts And Rigging Rules

Reference for recreating real stage equipment in Sentinel from manufacturer data: lighting fixtures,
truss and rigging hardware, speakers and line arrays, generators and vehicles. The workflow lives in
the `equipment-from-specs` skill; this file holds the conventions and data contracts the workflow
relies on. They were worked out over fifteen spec-sheet fixtures, a manufacturer truss catalogue, six
speaker families, a truck body and a generator, and every rule below exists because something broke
without it.

## What a recreation is

A recreation is a dimensioned, behaving visual model whose every number traces to a source. It is not
calibrated photometry, a structural calculation or a rigging approval.

- Say: built from the manufacturer's published spec sheet; dimensions from the drawing; channel
  layout from the manual; geometrically checked connections.
- Never say: safe, load-rated, certified, engineered, structurally sound, ready to rig, photometrically
  accurate, or approved by a manufacturer. Weight and power ratings may be recorded as documentation;
  they are never used for a load, span, ballast, wind or electrical claim.
- Name the source model to identify it, never to imply endorsement or official status.

## Sources stay out of the project

Manufacturer PDFs, drawings, photographs, gobo artwork, CAD files and GDTF Share files are the
manufacturer's material. Keep them in a folder outside any project that might be shared (for example
`<workspace>/sources/<item-id>/`) and record them in the fact sheet: title, revision, URL, retrieval
date and the page each value came from. A project carries facts (dimensions, ranges, channel tables
written out as data, with a source) and never the documents themselves. If a tool rasterises a page
for reading, the raster belongs with the sources, not under the project's `docs/` or `proof/`.

## Conventions

New equipment uses one convention. Older projects use others; adapt at the boundary with an explicit
transform, never by flipping content.

- Metres, degrees in documents and controls, radians in shaders. Right-handed, +Y up.
- Front (emission or audience-facing side at the home pose) is -Z.
- Origin, per family. Record the origin as a fact, with its status.
  - Floor equipment (speakers, generators, ground-support bases): centre of the ground-contact
    footprint, Y = 0 on the floor.
  - Hung or clamped fixtures: the centre of the plane the mount fastens to (for example the base face
    the omega brackets lock onto) on local Y = 0. Feet that protrude below it are geometry, not origin.
    The fixture body sits on +Y when standing and is inverted by the mount transform when hung. Pan and tilt apply in fixture
    space before the mount transform.
  - Line-array cabinets: the front upper hinge axis.
  - Truss parts: centred in XZ, minimum Y = 0.
  - Vehicles: rear deck edge at Z = 0, +Z toward the cab.
- Motors: pan about local Y, tilt about the pan-rotated X axis. Target and actual angles are separate;
  actual is speed-limited by elapsed time.
- Pixels and zones: origin top-left looking at the front, row-major unless the manual says otherwise.
  One helper owns the address-to-position conversion; every preview and renderer calls it.

## Record contracts

Reuse these layouts. The same byte count does not make two records interchangeable: a consumer reads a
record only from the family that published it.

**Placement, 48 bytes** (the `PNodes` record of `knowledge/precise-construction.md`):
`float3 position; float scale; float kind_id; float seed; float yaw; float height; float width; float depth; float2 dir;`
`scale = 0` hides a record but keeps its identity.

**Mount frame, 64 bytes**: `float4 axis_x, axis_y, axis_z, origin`. Columns are orthonormal with
determinant +1. A point maps as `origin + X*x + Y*y + Z*z`. `origin.w` is the stable id + 1 when active,
0 when not. Every attachment between families goes through a mount frame: fixture to clamp, cabinet to
cabinet, generator skid to deck. Consumers never choose another placement or base offset.

**Light record, 64 bytes** (moving heads and other directed sources):
`float3 position; float cone; float3 direction; float reach; float3 colour; float intensity; float fixture_id, group_id, pan, tilt;`
`position` is the actual world-space lens centre, `cone = tan(full angle / 2)`, pan and tilt are
actual radians. A negative `group_id` marks an inactive record.

**Optics record, 16 bytes** beside it: `gobo, rotation, softness, aperture`. Gobo ids are stable and
only ever appended.

**Pixel or cell record, 32 bytes**: `float3 colour; float intensity; float2 centre; float zone; float id;`

**Tube or primitive record, 64 bytes** (truss and structure): `float4 a, b, cutA, cutB`.

- Tube: `a.xyz` and `b.xyz` are the chord endpoints and `a.w` the outside radius. `cutA.xyz` and
  `cutB.xyz` are the end miter-plane normals (zero for a square cut).
- Box: `a.w = -1`, `a.xyz` is the centre, `b.xyz` the half extents, `cutA.xyz` and `cutB.xyz` the
  X and Y axes.

Keep wall thickness in a profile table the renderer reads by series. Never hard-code it per owner
index.

## Lighting fixtures

- **Graph shape:** content → plan (placement authority) → motion → mapper (actual motor pose, per-emitter
  optics) → renderer (internal camera, geometry, haze, Program). A static fixture needs no motion
  node. A DMX personality decoder sits where content and motion would: it produces the same inputs
  the programmer would set.
- **Emitters are not zones.** Sixty-four LED packages can be eight control zones. Model the zones the
  manual lets you address, and draw the packages as surface detail.
- **Beam is not field.** Beam angle is the 50% cone and field the 10% cone. Drive zoom in beam degrees
  and interpolate field.
  - Data sheets often quote a beam angle at one end of the zoom and a field angle at the other.
  - Not every manufacturer's "field" is 10%: one stated 42° where its own plot read about 50° at
    10%. Record the definition you used.
  - Optical modes can switch the zoom range, so store one range per mode.
- **Colour:** model the system the spec describes. CMY mixes subtractively from white, a colour wheel
  has ordered slots including split positions, RGBW and RGBA add. Collapsing every emitter to RGB is
  a stylised-kit choice, made only when the user asks for one.
- **Gobos:** one analytic mask per slot, shared by the beam volume and the surface projection, with
  stable ids. Geometric gobos (dots, bars, rings, breakups) are drawn procedurally from the description.
  Trace artwork gobos into procedural masks. Use a manufacturer gobo image itself as a mask only in
  the user's private project, with their agreement, loaded from the sources folder, never shipped. Rotation is either indexed (angle) or
  continuous (signed speed); shake is a separate oscillation.
- **Prism:** N facets replicate the beam with the facet's angular offset, rotating as one; overlay the
  open beam only if the spec says the prism leaves a centre beam.
- **Haze:** narrow cones for beams; broad pixel faces as a few binned sources averaged from their real
  pixels. Compute fog against the full-resolution nearest-surface depth and apply extinction once,
  in composition. More march samples do not fix a depth mismatch at thin edges.
- **Proof:** see the skill's fixture gates. Every zone at 1, 0.1, 0.01 and 0 with a true blackout.
  Addressing driven through the real input with non-target darkness checked. Motors timed against
  the spec's travel times. An array of 100 held at a measured frame rate.

## DMX personalities

A recreated fixture becomes console-drivable through a decoder Module that reads the DMX In port
(`knowledge/lighting-and-show-control.md`, `tools/templates/module-includes/dmx_schema_v2.hlsli`):

- **Patch:** the universe as the console counts it (Art-Net port address or sACN universe), the start
  address (1-based) and the mode.
  - Find the universe's record in the DMX In port by matching the metadata address slot. Never
    assume it is record `9 + universe`, because DMX In may start its range anywhere.
  - An array of fixtures sits at `start + i * footprint`.
- **Channel table:** a project script generates it from the fact sheet's `dmx` section; never
  hand-type it into HLSL.
  - A 16-bit attribute is `(coarse * 256 + fine) / 65535`.
  - A ranged channel (gobo slot, rotation speed, strobe mode) maps through its range table to a
    function and a value.
  - `depends_on` ranges are resolved after the channel they depend on, including latched modes held
    in decoder state.
  - Interlocks are applied last: a blocked attribute goes to its neutral value.
  - Activation holds (lamp, reset and settings functions) are usually not simulated. List them as
    ignored.
- **Output: a fixture state buffer.** One row per patched fixture, one float per attribute, in the
  order of the generated attribute table (for example `#define ATTR_GOBO_ROT_SLOT 9`).
  - Discrete attributes carry a slot index; continuous ones carry the physical unit the table states.
  - A full spot has several gobo wheels, an effect wheel, prisms, a beam shaper, CMY plus a colour
    wheel and more than one frost. A single 16-byte optics record cannot hold that: the mapper
    reads the state row and writes the light and optics records the renderer consumes.
  - The decoder never places a fixture or writes the renderer directly.
- **Proof:** a scripted loopback inside Sentinel (a producer Module or DMX Out into DMX In, Art-Net to
  `127.0.0.1` or sACN multicast).
  - Step every simulated channel to the boundaries of every range and read back the decoded attribute.
  - Set a prerequisite channel or latch before testing a dependent range.
  - A full spot has a few hundred ranges, so script the sweep and budget its time.
  - Then repeat a sample from the user's console or QLC+ if available.
  - Report which ranges are approximated or ignored (macros, reset, lamp control).

## Truss

**Facts per series:** outside size, chord outside diameter and wall, brace diameter, wall and pattern,
chord count (4 square, 3 triangle, 2 ladder), alloy, connector family, stock lengths, and
corner/junction/base envelopes.

- Square chords sit at `±(size - OD) / 2`.
- A triangle's height comes from the equilateral geometry plus OD, not the storefront's box size.
- A circle's quoted diameter is outside, so its path radius is smaller.

**Parts and ports:** each part carries ports. A port is a point plus a frame whose local +Z is the
outward normal.

- **Connect** solves the child port onto the parent port: `R = F_parent · Rz(twist) · flip · F_childᵀ`.
  - The flip is `diag(1,-1,-1)` for square and ladder sections, and `diag(-1,1,-1)` for triangles.
    The square flip inverts a triangle's apex.
  - `twist` is a multiple of 360 / chord count.
- **Close loops** with a join check. The gap, the normal sum and the nearest chord-end distance must
  each be at most 1e-5 m, so the whole chord pattern is checked, not just the centre.
- **Never scale a stock section to close a span.** Use stock lengths, or declare a custom part as
  custom.

**Rules a solver must enforce, refusing rather than silently correcting:**

- A port connects once.
- Mismatched end patterns, or a cross-series join without an explicit adapter part, are refused.
- A twist that misaligns the chord pattern is refused.
- A hinge moves only inside its limits.
- A clamp's size equals the chord's outside diameter.
- Clamps go on main chords only, never braces:
  - inside the chord's usable interval (keep about 70 mm clear at each end);
  - off brace junctions (about 32-65 mm, depending on the profile);
  - not overlapping another clamp.
- Mounting connector families must match.
- Every attachment frame is a proper rigid rotation.
- Two parts may not own coincident tube runs.
- At a crossing, use a supported connector or separate the runs in depth. Never allow an accidental
  penetration.
- A hung fixture hangs inverted, and its clamp meets the actual tube centreline, not an imaginary
  corner of a four-chord section.
- Port markers are connection centres, not load-rated attachment points.

**Proof:**

- Unit tests for the solver (loop closure, illegal joins, roll alignment, floor seating).
- CPU-versus-GPU parity of live ports and mount frames, within about 2e-6 m.
- A sampled clearance audit across hinge poses.
- Worklight inspection (front, side, rear, close oblique) before any haze.

## Speakers, power and vehicles

**Speakers:**

- Facts: envelope, taper and splay angles, driver sizes and positions, grille, handle pockets,
  runners or feet, connector plates, and rigging points from the drawing (hinge, link and pin
  positions, flying-frame pickups).
- Anchors: `ground`, `stack_top`, `front`. A wedge's second anchor is its acoustic face, so
  consumers branch on family.
- Stacking: only what the manufacturer supports, as `supported_by` relations.
- Line arrays: carry a full per-cabinet pose, because a splay cannot be encoded as yaw. Joint angles
  stay inside the spec's splay range, hinge gaps are zero, and a frame pickup stays a terminal
  attachment unless a hoist or truss is modelled.
- Realism: cones behind a depth-tested perforated grille, filtered by pixel footprint against moiré.
  No logos.

**Generators:**

- Enclosure, skid and vibration mounts, louvers, radiator, control panel, exhaust.
- Skid frames are mount frames.
- kVA and weight are documentation only.

**Vehicles:**

- Encode dimensions as relations (wheelbase, axle positions, deck height, cab clearance, door
  jambs) that refuse invalid sizes instead of moving parts.
- Keepouts cover a door's full sweep, not only its current pose.
- Decks publish mount frames, and equipment seats on them.

**Integration checks:**

- Support gap: nothing floats. A real case was a 0.17 m gap from a mismatched skid height.
- Equipment against keepouts. A real case was doors hitting a truss until it moved back 0.7 m.
- Ray bounds that cover protruding hardware.

## Origin of these rules

Every rule above came from a failure in the private research builds. The ones worth remembering:

- An 8-bit motion texture quantised the midpoint by about one degree, so motion now uses 32-bit float.
- A reversed pixel origin was fixed in the topology helper, not by flipping content.
- Half-resolution fog outlined thin brackets in black.
- A clamp sat on a brace junction.
- Overlapping truss runs.
- A triangle-truss apex flipped by the square mating rule.
- A generator floating on a mismatched skid.
- A grille moiré that only showed at distance.
