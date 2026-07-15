---
name: sentinel-bug-report
description: Prepare, reproduce, package, submit, and verify Sentinel bug reports through the installed Sentinel MCP bug-report pipeline. Use when a user says to report a bug, submit a crash, prepare a support issue, collect a reproducible Sentinel report, or upload a diagnostic bundle for Sentinel support.
distribution: true
---

# Sentinel Bug Report

## Goal

Create high-quality Sentinel support reports from an installed workspace. The report should explain the user's problem, include concrete reproduction evidence when possible, attach the right diagnostics, and verify that the submission reached the Sentinel bug-report service.

Use this skill for new bug reports and crash reports. For maintainers fixing an already-created GitHub issue, use the repo's engineering workflow after intake.

## Required Behavior

Do not submit a vague report. First collect enough evidence that support can act on it.

- Get user consent before submitting anything remotely.
- Tell the user what will be included: diagnostic report, log tail, crash artifacts when requested, optional screenshot, and optional project file.
- Do not attach a user project file unless the user explicitly approves it or the agent created a minimized repro project for this report.
- Do not put license keys, private paths, emails, customer names, secrets, or venue names in the narrative.
- Prefer a local MCP reproduction path before submission.
- If reproduction is blocked, say exactly what was tried and what remains unknown.
- After submission, verify the returned issue number or URL and uploaded byte count.

## Intake Checklist

Capture these notes before submitting:

- Report kind: `bug` or `crash`.
- User-facing symptom.
- Expected behavior.
- Sentinel version and build, from `sentinel_app action="diagnostic"` when possible.
- GPU, driver, OS, and engine pack state.
- Exact steps to reproduce.
- Whether the issue is reproducible, partially reproducible, or not reproduced locally.
- Files or media required to reproduce.
- Whether the user approved including a screenshot or project file.

If the user provided a short complaint, ask at most one concise question when the missing detail blocks a useful report. Otherwise continue with the evidence you can collect.

## Reproduce and Collect Evidence

Start with the app and MCP surface.

1. Check connectivity:
   - `sentinel_app action="ping"`
   - If Sentinel is not running, launch it through the normal installed path or ask the user to open it if launch is blocked.
2. Capture baseline diagnostics:
   - `sentinel_app action="diagnostic" include_state_tree=true`
   - `sentinel_app action="logs" lines=200 source="both"`
   - `sentinel_screenshot action="window"` when the UI state matters.
3. Exercise the reported workflow:
   - Use `sentinel_pipeline` for sources, pipelines, outputs, and pipeline info.
   - Use `sentinel_graph` for links and always run `sentinel_graph action="auto_layout"` after graph edits.
   - Use `sentinel_state` for parameter reads, writes, and actions.
   - Use `sentinel_ui` for UI-specific bugs.
   - Use `sentinel_capture` for source or pipeline output proof.
4. Classify the result:
   - `REPRODUCED`: the reported behavior happened locally.
   - `PARTIAL`: some symptoms matched, but not the full report.
   - `NOT REPRODUCED`: the attempted path stayed healthy.
   - `BLOCKED`: missing hardware, source media, license state, engine pack, or user file prevented the test.

For crashes, include latest crash artifacts if the user approves and the crash is relevant to this report.

## Narrative Format

Use this structure in the `narrative` field:

```text
## Summary
<one paragraph describing the bug or crash>

## Expected
<what should have happened>

## Actual
<what happened instead>

## Reproduction
1. <step>
2. <step>
3. <step>

## Evidence
- Reproduction result: <REPRODUCED, PARTIAL, NOT REPRODUCED, or BLOCKED>
- Diagnostics captured: <yes/no>
- Log tail captured: <yes/no>
- Screenshot included: <yes/no and path if yes>
- Project included: <yes/no and reason if yes>
- Relevant MCP observations: <frame counts, pipeline status, errors, output behavior>

## Caveats
<missing source files, hardware, license state, or anything support must know>
```

Keep the title specific:

```text
Crash: Sentinel exits while <doing action>
Bug: <pipeline or panel> <specific failure>
```

## Submit Through Sentinel MCP

Use the installed Sentinel MCP action:

```text
sentinel_app action="submit_bug_report"
  title="<specific title>"
  narrative="<narrative from above>"
  report_kind="bug" | "crash"
  include_diagnostic=true
  include_log=true
  include_latest_crash=true | false
  include_project=true | false
  screenshot_path="<optional screenshot path>"
  project_file_path="<optional .sentinel project path>"
  labels_hint=["pipeline:<name>", "version:<major.minor>", "sm:<compute>"]
```

Set `include_latest_crash=true` only for crash reports or when the latest crash is clearly related. Set `include_project=true` only with approval.

If the remote submit fails, create a local bundle for handoff:

```text
sentinel_app action="bug_report"
  description="<short local bundle description>"
  include_diagnostic=true
  include_log=true
  include_latest_crash=true | false
  include_project=true | false
  screenshot_path="<optional screenshot path>"
  project_file_path="<optional .sentinel project path>"
```

Tell the user the local bundle path and the remote submit error.

## Verify Submission

After `submit_bug_report`, inspect the response and report:

- `http_status`
- `issue_number`
- `issue_url`
- `uploaded_bytes`
- `is_duplicate`

If the response lacks an issue URL or issue number, treat the submission as unverified and preserve the returned error text.

Final user response format:

```text
Submitted Sentinel bug report: <issue_url or issue number>.

Evidence included:
- <diagnostic/log/screenshot/project/crash summary>

Reproduction result:
- <classification and one sentence>

Caveats:
- <none or exact missing proof>
```
