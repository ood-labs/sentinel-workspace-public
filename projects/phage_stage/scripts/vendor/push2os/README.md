# Push 2 OS (development extraction)

Canonical source for the StageRig Phase 5 contract. This tree is not yet a release
or approved show runtime. The development public Runtime has executing scratch
proof; cross-show adoption and release gates remain open. Install through the
verified tools, not by replacing watched files directly.

`src/session.luau` composes a pure per-runtime module graph from explicit show
configuration and page factories. Each factory gets public theme, conventions,
widgets, compact-menu, column-grid and pad-window helpers. `id` is stable; `label`
may change. `legacy_id`, `legacy_key`, `state_path` and `legacy_window_id` declare
existing storage identities rather than deriving them from display text.

Every module in `src/internal/` is private. `_get` on the construction result is
reserved for the forthcoming runtime/compatibility adapter, not show code. The
internal legacy pad bridge remains only while original fixed-region pages exist;
remove it after consumers migrate to explicit stable-ID windows and pass held-pad
release and saved-layout migration tests. Framework source never loads show pages.

Each session constructs fresh mutable theme, menu, parameter, persistence and pad
state. Page factories must likewise allocate fresh records and avoid host output
during construction. The host adapter is explicit and owns resource lifetime.
`src/runtime.luau` now wraps native ownership, restore preflight, guarded callbacks
and complete frames. See [Runtime contract](docs/runtime.md) and the executing
`examples/runtime.luau`. Internal startup dispatch remains private.

Operator banks, patterns, layouts, looks and groups are show-owned data outside
the package. Temporary presses/programmer Undo, reload snapshots, durable UI
preferences and authored content have different lifetimes. No release number
changes those lifetimes implicitly. Installation/rollback will use verified
manifest-owned files under an exclusive maintenance lease, with data backups for
supported migrations. Never hand-edit a consumer's installed framework.

Export and verification are now available through `tools/package.py`:

```text
python tools/package.py export --source <package-dir> --output <outside-source.zip> --version 0.1.0-dev --development
python tools/package.py verify-artifact <outside-source.zip>
python tools/package.py verify --project <show-dir>
```

The lock is `<show-dir>/push2os.lock.json`; owned files are relative to
`<show-dir>/scripts/vendor/push2os/`. Unknown files are unowned and preserved.
Installation, rollback and interrupted-activation recovery now use the native
exclusive maintenance lease and retained transaction checkpoints. They default to
read-only previews; see [installation and recovery](docs/installation.md) before
applying an operation. Verification performs no writes.
Required host capability names in `package.json` are the pending Phase 20 contract,
not a claim that an existing binary implements them. `tested_host_revision: null`
deliberately prevents release export until executing compatibility proof exists.

Manifest encoding: UTF-8 JSON, sorted object keys, compact separators, Unicode
unescaped, no newline. File entries sort by case-sensitive POSIX path, with SHA-256
over exact file bytes. `content_sha256` hashes that canonical file-entry array.
Version, API/schema, source revision, development flag and tested host requirements
are separate lock metadata. ZIP entries have fixed timestamps, permissions, order
and no compression; identical source and metadata produce identical artifact bytes.
Development provenance is explicit even if those bytes happen to match a clean tree.
Release export requires exactly tracked clean source bytes and tested host metadata.
