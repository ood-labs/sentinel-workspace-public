# Public Runtime (development)

`examples/runtime.luau` is an executing native-host example. Install the exact
artifact using the leased installer and declare `@push2os` as
`./vendor/push2os/src` in project `scripts/.luaurc`. Copy the example into the
show's scripts directory and provide its named bank. No sibling checkout is used.

The root calls `Runtime.create(config, Runtime.native({...native namespaces...}))`
and returns `runtime.callbacks`. Creation is pure: page factories build fresh
records using the supplied public drawing/window helpers. `runtime.status()`
reports pending/refusal/running diagnostics; a healthy native script alone does
not prove activation. `runtime.stop()` is idempotent and releases ownership.

Config requires stable `id`, exact root StateTree prefix, explicit MIDI output
port, persistence group/preset/schema_version, and 1..8 page factories. The root
prefix must match its script stem. A page needs stable `id`, `render(ctx)` and
optional `params`, `records`, `top`, `top_labels`, `windows`, and lifecycle hooks.
Display labels may change without changing identities. Every record declares
its lifetime (`none`, `snapshot`, `state`, `bank`), numeric bounds or explicit
`value_type`, default and stable ID. Window dimension records enter composition
before restore checks. `legacy_pads=true` explicitly requests the private legacy
pad adapter; a page with no windows otherwise allocates no pad window.

Startup requires native session, complete-frame, restore-barrier and merge-save capabilities.
It reads a snapshot without recalling it, validates every bank record and saved
reload record, claims exclusive ownership, initializes records, then registers
all pages and enables rendering/input. Missing, corrupt or incompatible existing
banks cannot emit defaults. `persistence.new_empty=true` permits defaults only
when the entire named group is absent; missing presets in an existing group are
still refusals. Pending/failed banks can be repaired and startup retries.
Deferred startup runs in the existing UI callback, keeping bank reads and full
registration out of the musical tick. Callback budgets remain unchanged. The
owner must receive both native tick and UI callbacks to make progress.

Durable saves pass explicit owned paths with `merge_existing=true`; unowned bank
entries survive. Failed saves retain dirty state and retry after the debounce.
Reload snapshots retain unsaved values and reschedule saving when they differ
from disk. The migration entry point and versioned compatibility adapter are
documented in [migration.md](migration.md).

Records with a `state` sink follow external changes to that exact path after the
200 ms encoder quiet period. The readout, next encoder turn and reload snapshot
then use the external value. Bank-backed records schedule a debounced save without
echoing a redundant state write. Invalid/out-of-range values are ignored. Explicit
Sentinel `readback` retains precedence. This polling covers the active page's eight
encoder records; show-owned models remain responsible for their off-page state.

Runtime snapshots are version 2, with stable page ID and durable record values.
They preserve unsaved bank edits across hot reload; held/transient values are
excluded. Bank files retain their native version-1 schema. Legacy Runtime version-1
snapshots require version-1 `params.values` and explicit `legacy_page_ids` giving
the original page order; `legacy_id`/`legacy_key` map record storage identities.
Unknown schemas, records, missing values and out-of-range/type-invalid values
refuse before activation. No implicit clamping/data migration is performed.

Stop sends release edges for held semantic controls while A still owns its
outputs, stops page resources, aborts pending drawing, and invokes native session
cleanup. Retired callbacks are inert and repeated A.stop cannot retire B. Caught
render faults abort the partial native frame; a subsequent complete diagnostic
frame may show ERR, followed by normal recovery when rendering succeeds.

Development evidence covers isolated logic, native startup refusal and repair,
restored 73->encoder 73.15, reload, momentary edges and render-fault captures on
Push 2. Full cross-show saved-data adoption, timing soaks and physical gesture /
glass evidence remain separate pending gates. This is not release compatibility.
