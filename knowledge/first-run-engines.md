# First-Run Engines

Many Sentinel pipelines require TensorRT engine packs. A fresh install may have no engines yet.

## Discover Engine State

Call:

```text
sentinel_app action=engine_status
```

The response includes:

- `gpu_arch`
- `gpu_name`
- `engines_dir`
- `packs[]`
- `download`
- `queue`

Each pack reports `id`, `status`, `download_size`, `download_url`, category, family, and dependency.

## Download Or Install A Pack

Use either:

```text
sentinel_app action=download_pack pack_id=auxiliary
sentinel_app action=install_pack pack_id=auxiliary
```

Official packs download, extract, rescan, and write pack version metadata as one operation. `install_pack` is an automation-friendly alias for the same operation.

Poll `engine_status` until the pack's `status` is `complete`. If `download.status` becomes `error`, report the error string.

## Useful Pack IDs

- `auxiliary`: Depth Anything V2 Small for `depthestimation`.
- `auxiliary-detection`: YOLOX-S for `detection`.
- `auxiliary-mediapipe-face`: face engines for `mediapipe` and the hidden `facemesh` alias.
- `auxiliary-mediapipe-hands`: hand engines for `mediapipe`.
- `auxiliary-pose`: pose engines.
- `auxiliary-personseg`: RF-DETR-Seg person segmentation engines for the `personseg` node.
- `streamdiff`: shared SDXL core engines.

Always inspect `engine_status` in the current build because pack availability depends on GPU architecture and the installed manifest.

## First Proof

A reliable first engine proof is:

1. Start with an empty engines directory.
2. `download_pack` or `install_pack` the `auxiliary` pack.
3. Poll until `auxiliary` is `complete`.
4. Create a pattern source.
5. Create a `depthestimation` pipeline.
6. Connect the source to the pipeline.
7. Run `sentinel_graph action=auto_layout`.
8. Inspect the pipeline until `stats.healthy=true`, `statusMessage=Ready`, and `framesProcessed` climbs.

No UI clicking is required for this setup path.
