# Sentinel Vision setup and verification

Sentinel Vision evaluates pipeline captures through an OpenAI-compatible provider.
The MCP server resolves configuration from `<workspace>/vision.json`; always run
`sentinel_vision action=status` first and use the returned `config_path` instead
of guessing the workspace or line numbers.

Never ask a user to paste an API key into chat, pass a key as an MCP argument, or
print a configured key while debugging. `vision.json` is local-only and ignored by
Git.

## First-time setup

1. Run `sentinel_vision action=status`.
2. Open the returned `config_path`. In a seeded workspace this is normally
   `<workspace>/vision.json`.
3. Find the top-level `providers` array. Put each key in the `api_key` field of its
   own provider object.
4. Set `default_provider` to the profile Sentinel should use when no provider is
   passed explicitly.
5. Run `status` once for every configured provider. Require `key_present=true`,
   `key_ok=true`, and a nonzero `model_count`.
6. Run a real image evaluation. Authentication and `/models` success do not prove
   that multimodal structured output works for the selected model.

Use this template, replacing placeholders only in the local file:

```json
{
  "default_provider": "openrouter",
  "providers": [
    {
      "name": "openrouter",
      "base_url": "https://openrouter.ai/api/v1",
      "api_key": "PASTE-YOUR-OPENROUTER-KEY-HERE",
      "default_model": "google/gemini-3.5-flash",
      "capabilities": {
        "images": true,
        "json_object": true,
        "max_images": 20,
        "video": true
      }
    },
    {
      "name": "gemini",
      "base_url": "https://generativelanguage.googleapis.com/v1beta/openai/",
      "api_key": "PASTE-YOUR-GEMINI-API-KEY-HERE",
      "default_model": "gemini-3-flash-preview",
      "capabilities": {
        "images": true,
        "json_object": true,
        "max_images": 20,
        "video": true
      }
    },
    {
      "name": "ollama",
      "base_url": "http://127.0.0.1:11434/v1",
      "default_model": "llava",
      "capabilities": {
        "images": true,
        "json_object": true,
        "max_images": 8,
        "video": false
      }
    }
  ]
}
```

OpenRouter and Google AI Studio issue different keys. An OpenRouter key belongs only
in the `openrouter` profile; a Gemini API key belongs only in the `gemini` profile.
OpenRouter model ids include the vendor prefix (`google/gemini-3.5-flash`), while
the direct Gemini endpoint uses `gemini-3-flash-preview`.

Environment configuration is also supported when variables are set before MCP is
launched: use `OPENROUTER_API_KEY` for the OpenRouter profile or
`SENTINEL_VISION_API_KEY` for the selected provider. Editing `vision.json` is the
clearest path when multiple providers are configured simultaneously.

## Verification

Validate authentication and live model discovery independently:

```text
sentinel_vision action=status provider=openrouter
sentinel_vision action=status provider=gemini
sentinel_vision action=models provider=openrouter live=true limit=20
sentinel_vision action=models provider=gemini live=true limit=20
```

Then evaluate the same known-good image through both providers. Use an explicit,
small schema for the smoke test so failures are easy to diagnose:

```json
{
  "type": "object",
  "properties": {
    "valid_render": { "type": "boolean" },
    "summary": { "type": "string" }
  },
  "required": ["valid_render", "summary"],
  "additionalProperties": false
}
```

For normal scene review, use
`sentinel_vision action=eval_pipeline pipeline_id=<id> preset=render_quality`.
It captures the live pipeline, releases Sentinel IPC, performs the HTTP evaluation,
and returns `_meta.captured_png` plus the structured assessment.

## Troubleshooting

- **`key_present=false`**: the selected profile has no key, still contains a
  placeholder, or the environment variable was set after MCP launched.
- **`key_ok=false`**: the key was rejected by the configured endpoint. Confirm the
  key belongs to that provider; do not move an OpenRouter key into the Gemini
  profile or vice versa.
- **A requested provider resolves to another profile's endpoint**: the named profile
  does not exist in `providers`. Add the provider object before testing it.
- **`vision/bad_json` after authentication succeeds**: the provider is reachable,
  but the model failed structured output. Retry with a small explicit schema and a
  different live model. In the verified July 2026 setup, direct
  `gemini-3.5-flash` returned malformed reversed JSON, while
  `gemini-3-flash-preview` completed the same image/schema test. OpenRouter
  `google/gemini-3.5-flash` also completed the render-quality preset successfully.
- **A config edit is not visible**: rerun `status`; if the key came from an
  environment variable, restart or reconnect MCP.
