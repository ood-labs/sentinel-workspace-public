# StreamDiff Canvas

A lightweight Sentinel example for generating a prompt-driven subject and
painting or procedurally stamping it into persistent canvases.

## Graph

`Radial Gradient -> Collage Diffusion -> Collage Cutout + Depth Estimation`

The generated color, matte, and depth feed two parallel canvases:

- **Paint Canvas** is a direct painting surface.
- **Pattern Canvas** stamps subjects automatically using a selected placement
  pattern.

**Pattern Depth SDF** renders the Pattern Canvas color, accumulated depth, and
cutout mask as a lightweight 3D relief.

The Collage Diffusion prompt bank requests isolated studio photographs on a
uniform black field. Every prompt explicitly rejects illustration, engraving,
screenprint, halftone, scanned-print, film-border, contact-sheet, and paper
artifacts, and ends with `hyper-realistic, 4K` so the matting stage receives a
clean photographic subject rather than a photographed or scanned print.

## Radial Gradient

The StreamDiff input is intentionally basic. Its Gradient group has four
Properties controls:

- **Center**
- **Radius**
- **Hardness**
- **Color**

An optional Noise group multiplies Smooth, Fractal, or Grain noise over the
gradient, with controls for amount, scale, and monochrome or colored noise.
Noise defaults to off, so the clean radial gradient remains the starting look.

The module has no authored viewport interaction and publishes one `Gradient`
texture.

## Generation Controller

Generation timing is owned entirely by the Generation Controller, not either
canvas. Its full-panel interface exposes Mode, Run, Generate, and Next Prompt.
The body displays the live prompt position, cycle count, hold state, and timing
progress.

- **Manual** holds StreamDiff until Generate or Next Prompt changes.
- **Interval** advances by Prompt Step at Prompt Rate and opens StreamDiff for
  one Render Window.
- **Continuous** releases hold continuously and travels through the prompt bank
  at Prompt Rate.

**Prompt Rate** controls both Interval cadence and Continuous travel.
**Stamp Speed** controls Pattern Canvas in stamps per second; its maximum is
20 stamps per second.

The controller drives Collage Diffusion's `hold` and `prompt_position`
parameters through control-output expressions.

## Canvas controls

Paint Canvas:

- Left click or drag paints.
- Middle drag pans.
- Wheel zooms; Alt + wheel changes brush size.
- `F` fits the canvas.
- `X` clears it.

Pattern Canvas:

- The Generation Controller's **Run** starts or pauses stamping.
- **Stamp Speed** controls independent cadence when **Linked** is off.
- **Linked** stamps once after each completed generation window.
- Pattern, scale, rotation, feedback, matte, depth, and canvas controls shape
  the composition.

Neither canvas contains audio reactivity, kick envelopes, or StreamDiff
generation timing.

## Engines

Collage Diffusion requires a compatible StreamDiff engine pack. Collage Cutout
and Depth Estimation require their corresponding auxiliary engines. Use
Sentinel's engine setup flow when opening the project on a fresh install.
