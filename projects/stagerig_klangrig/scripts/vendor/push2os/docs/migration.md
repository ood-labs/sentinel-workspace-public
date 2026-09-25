# Saved-data migration

Public `@push2os/migration.prepare(config,pages,bank,saved)` validates through the
same restore planner used by Runtime. It returns a version-2 stable-ID snapshot
and an explicit identity/lifetime report. It makes no host calls and never edits
the supplied pages, bank or old snapshot. A failed validation returns the restore
diagnostic, with no migrated result to activate.

Preserve original bank and snapshot bytes in a verified backup before applying
the result. Native bank schema 1, sequence masks, pad layouts and theme numbers
are unchanged: copy those files byte-for-byte. The report's bank operation is
`preserve_original_bytes`; do not rewrite them just to mark migration. Write the
returned snapshot to a separate destination. To undo migration, unload the show
under maintenance, restore the backup bytes, and reload the prior package.

Legacy snapshot version 1 needs its original `legacy_page_ids` order plus explicit
`legacy_id`/`legacy_key` mappings. The converted snapshot includes every durable
record using stable page/record IDs, including in-memory bank edits. Page labels,
page order and file locations can then change independently. Transient and held
actions never enter the snapshot. Bank entries not owned by this Runtime stay in
the original bank and survive later explicit merge saves.

Theme IDs remain 0 Cockpit, 1 Graphite, 2 Phosphor, 3 Classic. Display inks do not
change fixture RGB or MIDI LEDs. Programmer temporary edits and Undo are native
session state with a separate recovery contract; this API does not serialize Undo.

Existing factories may accept `(api, guarded_host)` and use the explicit
`api.legacy_v1` adapter: theme, conventions, widgets, bands, button_menu,
column_grid, params, persist, pads, pad_window, pad_window_gesture and pad_desktop.
These tables are scoped to one Runtime. Do not reach into private src/internal
paths or import framework helpers back from show files. New pages use public
helpers and declare stable identities; the legacy adapter is for migrating
existing pages, not an alternative host lifecycle.
