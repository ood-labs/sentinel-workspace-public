---
type: lessons
updated: 2026-07-05
---

# Lessons

Gotchas worth knowing before re-hitting the same wall. Newest at top.

## 2026-07-05 — `save_project bundle_modules` doesn't copy `modules/_shared/`

**Symptoms**: A bundled `.sentinel` show that `#include`s shared HLSL (e.g. the scientifica font from
`modules/_shared/fonts/`) is fine while the original workspace copy is loaded, but would fail to
compile if reloaded purely from the bundle — the `../_shared/...` include path resolves to a
`_shared/` dir that was never copied into `projects/<show>/modules/`.

**Cause**: `bundle_modules=true` copies only the Module folders referenced by pipelines; a shared
include directory that modules reference by relative path is not a pipeline and isn't followed, so
it's left out of the bundle.

**Fix**: After bundling a show whose modules include from `_shared/`, manually copy
`modules/_shared/` into `projects/<show>/modules/_shared/` (preserving `fonts/` and the `.hlsli`
files). Verify the bundle compiles standalone before treating it as portable.

**Frequency**: recurring (any bundled show using shared includes)

**Discovered**: 2026-07-05
