# Sentinel Vision Evaluation

`sentinel_vision` is Sentinel's AI visual-review tool. It evaluates captured images, PNG sequences, and small videos through OpenAI-compatible vision providers, with OpenRouter as the default. Use it for every visual claim you need to verify: render quality, scene contents, animation smoothness, before/after comparisons.

The API key lives in the workspace `vision.json` file or in environment variables. It is never passed as a tool argument and never pasted into chat.

## First-Time API Key Setup

Treat any `eval`, `compare`, or `eval_pipeline` failure that reports a missing, placeholder, or rejected key as a setup task: stop, walk the user through this flow, and retry once `status` is clean.

1. Run `sentinel_vision action=status`.
2. Read the returned `config_path`. That is the workspace `vision.json`.
3. If `created_template: true`, `key_present: false`, or `key_ok: false`, tell the user to open that file and replace the selected provider profile's `api_key` placeholder (`PASTE-YOUR-KEY-HERE`) with their provider key. The default profile is OpenRouter; any OpenAI-compatible provider profile works the same way.
4. Never ask the user to paste the key into chat, and never pass it through a tool argument. `sentinel_vision action=configure` updates provider metadata only (`base_url`, `model`, `capabilities`, `set_default`).
5. Rerun `sentinel_vision action=status`. Setup is complete when it reports `key_present: true`, `key_ok: true`, and a live `/models` fetch succeeds.

Environment-variable setup is also supported: set `SENTINEL_VISION_API_KEY`, or `OPENROUTER_API_KEY` for the `openrouter` profile, before launching the MCP client. If an env var was added after the MCP server started, reconnect or restart the client so the server inherits it. Editing `vision.json` needs no restart because the tool resolves the file on each request.

For keyless local OpenAI-compatible servers (Ollama, LM Studio), configure a local provider profile with a local `base_url` and leave `api_key` empty. Check reachability with `sentinel_vision action=status provider=<name>`.

## Common Calls

```text
sentinel_vision action=status
sentinel_vision action=models live=true
sentinel_vision action=eval path=<png-or-jpg> preset=render_quality
sentinel_vision action=compare image_paths=[a.png,b.png] mode=a_b
sentinel_vision action=eval_pipeline pipeline_id=<id> preset=render_quality
```

Presets: `render_quality`, `style_match`, `technical`, `animation_quality`, `comparison`. A custom `output_schema` overrides the preset.

`eval_pipeline` captures the requested pipeline output to `<workspace>/captures/vision_<timestamp>/output.png`, evaluates it over HTTP, and returns `_meta.captured_png` plus `_meta.proof_dir`.

## Motion And Video

For motion review, record with `sentinel_capture action=sweep_record` (see the `motion-eval` skill), then evaluate the result.

Small `.mp4` / `.mov` files are accepted only when the provider supports inline video and the raw file is at or below 14 MiB. For oversized clips or providers without video support, record with `mode=png_sequence` and pass the recording directory to `sentinel_vision action=eval max_frames=16`. Frames mode parses `manifest.json`, samples first and last inclusive frames, and labels timestamps.
