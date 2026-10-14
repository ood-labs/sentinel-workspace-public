---
name: fixture-refinement
description: Refine a GDTF lighting fixture type so Sentinel's fixture engine draws and decodes it as the manufacturer documents it. Start from the type's readiness report, gather the manufacturer's public documents, then correct or accept only the warnings the report flags, through sentinel_fixture refine with a reason and source per override. Use when a library type shows Generic with open warnings, when a user asks to make a fixture match its data sheet, or when a type must reach Refined.
---

# Fixture refinement

A GDTF says most of what a fixture is: modes, channels, ranges, geometry and beams. Some GDTFs leave things out or
get them wrong: placeholder photometry, unset physical ranges, a strobe whose meaning is unclear. Sentinel grades each
type's GDTF in a **readiness report** and lets you fix what it flags in a **refinement**: one JSON file per GDTF,
named by its SHA-256, holding overrides (an address, a value, a reason and a source) and accepted warnings (a code and
a reason). The Fixture Rig node applies the refinement when it packs the type, so every Module that reads the rig
(FixtureTypes, FixtureRender, the fixture engine) sees the refined type within a second, with no recompile.

## Never

- Edit a GDTF's bytes, re-save it, or replace it with a hand-edited copy. A refinement is the only fix.
- Write a fixture profile, a per-type table or per-type shader code. The engine reads the refined GDTF.
- Commit manufacturer documents, GDTFs or files extracted from them. Documents go in the git-ignored
  `sources/<type-id>/documents/` of the project.
- Set a value no document, measurement, capture or operator states. A value you derive (an intensity from an
  illuminance, a per-cell figure from a whole-fixture one) is fine when the reason shows the arithmetic.
- Touch what the report does not flag, unless the user asks. A refinement answers warnings and nothing else.

## 1. Read the report

```
sentinel_fixture action=inspect pipeline=<Fixture Rig id> type=<GDTFSpec or library file>
sentinel_fixture action=inspect library_dir=<folder> type=<library file>          (a type no rig uses yet)
```

`readiness` gives the tier (Blocked, Generic, Refined, Verified) and each warning: `code`, `severity`, `where` (the
place, e.g. `geometry Beam 1` or `mode Basic, Strobe`), `text` and `state` (open, corrected, accepted). Work on every
`warn` that is open. `info` warnings are optional; `error` means the type is Blocked (a stub, no mode, a parse defect
or past an engine cap) and no refinement unblocks it: tell the user what the report says.

To see what you can address and what each field holds now:

```
sentinel_fixture action=inspect ... detail=addresses address=emitter:     (render emitters and GDTF emitters)
sentinel_fixture action=inspect ... detail=addresses address=geometry:    (GDTF geometries, beams with photometry)
sentinel_fixture action=inspect ... detail=addresses mode=<mode name>     (one mode's channels, functions and sets)
sentinel_fixture action=inspect ... detail=channels mode=<mode name>      (the DMX chart as the GDTF has it)
sentinel_fixture action=inspect ... detail=geometry                       (the geometry tree)
```

Each address entry lists its fields with `class` and current `value`. A render emitter entry also says `kind`,
`colour`, `cells` and `photometry_defaults` (true when its GDTF beams carry the GDTF default flux or beam angle, which
is what `default_photometry` flags).

## 2. Gather references

For each open warning, decide what could answer it (table below), then get that reference:

- The manufacturer's public data sheet, user manual (its DMX chart), dimension drawing and photometric files, from the
  manufacturer's product page. Download them with `curl` into `sources/<type-id>/documents/` and note each file's URL
  and the date. Read PDFs with a text extractor (`pdftotext`, or Python with `pypdf` or `fitz`) and look at the
  pages that carry figures.
- The GDTF itself (`detail=all`), which often states what a warning needs elsewhere in the file.
- A capture from a visualiser with frozen DMX, or the operator's own check, when the user has one.

## 3. Answer each warning

| Code | What answers it | How |
|---|---|---|
| `default_photometry` | The data sheet's photometry for the flagged beam: beam and field angle, luminous flux, illuminance at distance or peak intensity | Override the render emitter the flagged beams feed (`emitter:<id>/beam_deg`, `field_deg`, `flux_lm`, `peak_cd`) or the GDTF beams (`geometry:<beam>/beam_angle`, `field_angle`, `luminous_flux`) |
| `placeholder_physical` | The DMX chart: what each range of the flagged channel does in physical units | `mode:<m>/channel:<attribute>/function:<name>/physical_from`, `physical_to`; move boundaries with `dmx_from`, `dmx_to`; split a function with `bands` |
| `shutter_undecided` | The DMX chart: which ranges are closed, open and strobe | `.../function:<name>/shutter` (open or closed), `.../waveform`; for a function that holds several of them, `bands` with a `shutter` or `waveform` per band |
| `emitter_role_guessed` | The data sheet: what the emitter is (wash, beam, strobe, backlight) and its colour system | `emitter:<id>/kind`, `emitter:<id>/colour` |
| `colour_uncalibrated` | Measured emitter colour (CIE x, y or dominant wavelength) from a data sheet or a measurement | `emitter:<GDTF emitter>/color` or `dominant_wavelength` |
| `axis_unverified` | A pose reference: a visualiser capture with frozen DMX, or a real unit, showing which way pan and tilt turn | `axis:Pan/sense`, `axis:Tilt/sense` (1 or -1) |
| `cell_order_unverified` | The manufacturer's pixel map, or a capture with one cell lit | `face:<id>/cells` (the cells in their true order) |

Write each override in two steps. First a dry run:

```
sentinel_fixture action=refine op=set pipeline=<rig> type=<type> address=<address> value=<value>
    reason="<what the document says, and why it beats the GDTF>"
    source={"kind": "datasheet", "document": "<title and revision>", "page": <n>, "note": "<url, table, derivation>"}
    dry_run=true
```

The reply lists every field the override changes, before and after. Only the fields you meant should change; a dry
run that moves something else means the address is wrong. Then send the same call without `dry_run`. Source kinds:
datasheet, manual, reference_capture, measurement, operator, judgement. Use judgement only when you derive a value
from a documented one, and say so.

A warning no reference you can get answers is accepted, with a reason that says what would settle it:

```
sentinel_fixture action=refine op=accept pipeline=<rig> type=<type> code=axis_unverified where=""
    reason="No pose reference: the manual's drawings do not establish the turning sense; a frozen-DMX capture from a visualiser or a real unit would."
```

Drawings and isometric views are not reliable for rotation sense or pixel order. Accept those unless you have a
capture or the operator confirms.

### Photometry

- `beam_deg` and `field_deg` are full angles (at half and a tenth of the peak). A data sheet's "beam angle" is the
  first; set the field angle only when the sheet gives one.
- `flux_lm` is the emitter's total luminous flux, all its cells together. `peak_cd` is the on-axis peak intensity:
  of one cell for a beam emitter (many narrow beams), of the whole emitter for a wash. Leave `peak_cd` out and it is
  derived from the flux and beam angle; set it when the sheet gives an intensity or an illuminance.
- From an illuminance E (lux) at distance d (metres) on axis, I = E x d squared. Use the farthest distance the sheet
  gives, since a narrow beam is still forming close in. When the figure is for the whole fixture and the emitter has
  many cells, divide by the cell count for a per-cell `peak_cd`.
- A sheet's fixture flux for a multi-emitter fixture may be the total of all emitters; give each emitter its share only
  when the sheet separates them.
- Write the arithmetic in the reason.

### DMX ranges

- Addresses name channels by attribute, functions and sets by name, as the GDTF has them (`detail=addresses mode=...`
  lists them). `mode:*` applies an address in every mode that has it.
- `dmx_from` and `dmx_to` move a function's boundary with its neighbour. `bands` splits one function into several:
  write a function's other fields before its bands, since later addresses still name functions as the GDTF has them.
- A band is `{"dmx": [from, to], "physical": [p0, p1], "name": "..."}`, or `"none": true` for a range that does
  nothing. A band also takes its own `attribute`, `shutter` (open or closed) or `waveform` (strobe, pulse, ramp_up,
  ramp_down, ramp_updown, random, lightning, spikes): a shutter channel the GDTF holds as one function becomes
  Close, Open and Strobe bands, the strobe band with `"waveform": "strobe"` so the engine flashes it. Any other key is
  refused.

## 4. Check

- `inspect` again: each warning you answered reads corrected or accepted, and with none open the tier is Refined.
- `sentinel_fixture action=inspect ... detail=refinement` lists every override with its value, reason and source.
- A visible change (photometry, a body part, a colour): capture the fixture engine renderer at a fixed content time
  before and after, and compare the two with `sentinel_vision action=compare`, naming what to compare.
- A DMX change: a dry run's changes show the decoded values inside the range you corrected.

## 5. Report

Tell the user, per type: the tier before and after, each override (address, value, the document and page it came
from), each accepted warning and what would settle it, and what you could not find.

## Reference

- Readiness, refinements and the fixture engine: `knowledge/fixture-import.md` (Refining a type).
- `sentinel_fixture` actions and arguments: `sentinel_app action=capabilities`.
- `refine op=remove` removes overrides at an address or an accepted code; `op=verify` records that the refined type was
  checked against a named reference; `op=carry` copies a refinement from another revision of the same type.
