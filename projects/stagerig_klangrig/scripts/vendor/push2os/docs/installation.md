# Local installation and recovery

Run the tools from the canonical development checkout or a pinned installation.
Export/verify use Python's standard library. Applying install/rollback/recovery
also requires `pyzmq` and the Phase 20 maintenance-capable Sentinel Control host.
The full framework Runtime and release compatibility gates are still open.

```text
python tools/package.py install candidate.zip --project <show-dir>
python tools/package.py install candidate.zip --project <show-dir> --apply
python tools/package.py verify --project <show-dir>
python tools/package.py rollback --project <show-dir> --checkpoint <checkpoint-dir>
python tools/package.py rollback --project <show-dir> --checkpoint <checkpoint-dir> --apply
python tools/package.py recover --project <show-dir> --checkpoint <checkpoint-dir> --apply
```

Install/rollback/recover default to a read-only preview. If the directory contains
multiple `.ctrl` files, install requires `--project-file <absolute-ctrl-file>`.
Applying an operation acquires native maintenance and unloads the active Control
runtime. Capture operator programming and obtain runtime ownership first. After
success the lease is released and the host remains empty; explicitly load the
desired show to resume. Running-target installation is allowed only through this
verified unload/lease workflow. No disconnected-host or painter-only bypass exists.

The tool verifies the artifact and existing owned bytes, rejects unknown-file
collisions, and stages the complete candidate plus preserved unknown files.
Modified owned files, links, path escapes and invalid manifests refuse activation.
Show-authored data stays outside the vendor tree and lock. A record's persistence
schema/migration is a separate Runtime barrier; installing a new source version
does not migrate or reset authored data implicitly.

Activation journals live under `<show-dir>/.push2os-transactions/<id>/`. The tool
records the original file hashes, exact original lock bytes, native lease identity
and new file hashes. It flushes staged bytes and journal updates before replacement.
The prior vendor directory and original lock remain recoverable. Native readiness,
canonical project, token, generation, empty modules and stopped/drained watchers are
rechecked at every replacement boundary. Verification finishes before lease release.

An ordinary activation exception restores the prior package and lock while the
lease is held. Loss of host/readiness or unrecognized current/backup bytes leaves
maintenance held with `RECOVERY_REQUIRED` and a checkpoint path. After an installer
process interruption, use `recover` with that checkpoint. If the host also restarted,
recovery reacquires the durable lease using the saved token, receives a new token,
and restores the original tree before release. It refuses altered backups/current
files. If release succeeded but its acknowledgement was lost, recovery recognizes
the exact verified installation without rewriting package files.

Use `rollback` for a completed upgrade. It verifies the saved prior artifact and
activates it through a new native lease/transaction. Unknown files added or edited
since the upgrade are preserved; collisions with returning owned paths refuse.
Rolling back the first install removes its owned files and lock while preserving
unknown files. Keep checkpoints until the show has passed its upgrade proof.

If interruption occurs before a checkpoint exists, no package activation has begun.
Inspect native `maintenance_status` and the project before explicit lease recovery;
absence of a CLI response is not proof that acquisition failed. Never remove the
native durable marker to bypass a held or unreadable lease.

Native capabilities and source provenance remain distinct. A development artifact
is labeled development even when its files verify; this tool does not turn it into
a tested release or waive the host, restoration, physical-input or soak gates.
