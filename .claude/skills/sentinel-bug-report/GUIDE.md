# Sentinel Bug Report Guide

This guide is for agents launched from the installed Sentinel workspace. Its job is to turn a user complaint into a useful Sentinel support report.

## What Gets Uploaded

A remote submission can include:

- Diagnostic JSON with system, GPU, engine, pipeline, source, output, and state-tree data.
- Sentinel log tail.
- Latest crash artifacts for crash reports.
- A screenshot path chosen by the user or captured by the agent.
- A `.sentinel` project file when the user approves it.

With a license, the report service uploads the bundle and creates or updates a Sentinel support issue. Without a license, Sentinel sends the narrative and inline diagnostic only. The issue receives the `unlicensed` label, has no Artifacts section, and is limited to 3 submissions per machine fingerprint and 10 per IP address each day. The response states that the file bundle was omitted and includes an issue number or URL.

## Minimum Useful Report

Every report needs:

- A specific title.
- A short symptom summary.
- Expected and actual behavior.
- Reproduction steps or the reason reproduction is blocked.
- Diagnostic report.
- Log tail when a licensed file bundle is available.
- Clear caveats for missing files, hardware, source media, or license state.

## Recommended MCP Sequence

```text
sentinel_app action="ping"
sentinel_app action="diagnostic" include_state_tree=true
sentinel_app action="logs" lines=200 source="both"
sentinel_screenshot action="window"
```

Then reproduce the issue using the relevant MCP tools:

- `sentinel_pipeline` for pipeline, source, and output state.
- `sentinel_graph` for graph wiring, followed by `sentinel_graph action="auto_layout"` after edits.
- `sentinel_state` for parameter changes and actions.
- `sentinel_ui` for UI interactions.
- `sentinel_capture` for visual proof from source or pipeline textures.

## Submission Example

```text
sentinel_app action="submit_bug_report"
  title="Bug: Module output turns black after reload"
  narrative="<structured markdown narrative>"
  report_kind="bug"
  include_diagnostic=true
  include_log=true
  include_latest_crash=false
  include_project=false
  screenshot_path="<workspace>/captures/module_black_output.png"
  labels_hint=["pipeline:module"]
```

For a crash:

```text
sentinel_app action="submit_bug_report"
  title="Crash: Sentinel exits while closing output window"
  narrative="<structured markdown narrative>"
  report_kind="crash"
  include_diagnostic=true
  include_log=true
  include_latest_crash=true
  include_project=false
```

## Failure Path

If remote submission fails, create a local bundle:

```text
sentinel_app action="bug_report"
  description="Local bundle for <short bug title>"
  include_diagnostic=true
  include_log=true
  include_latest_crash=true
```

Give the user the bundle path and the exact remote error. Do not claim the report was submitted.

## Privacy Rules

- Ask before including project files.
- Avoid private names, venues, emails, or full local paths in the narrative.
- Let Sentinel's built-in scrubber handle logs and diagnostics, but still write clean narrative text.
- Never paste a license key into the report narrative.
