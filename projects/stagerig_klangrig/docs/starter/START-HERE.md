# stagerig_klangrig

Created from StageRig starter 1.3.0 (4e47a7fe520b4eee44458dea493d82b5be314a9d), components: core.
Open `stagerig_klangrig.sentinel` in Sentinel 0.5.87 or later.
The generator never loads projects or takes control of hardware.

Surface, Push2 Display and Clock start enabled so the show plays on open; OSC and projector outputs are off.
Preset policy: **reference**. Blank means empty saved banks and default programming;
reference copies the baseline artistic banks as independent local data.

Tuned rendering, room materials and all four controller pages are retained. The crowd component is not installed.
`starter-tuning.json` records the adopted settings. `rig-descriptor.json` identifies
geometry and patch ownership. This version retains the 288-slot Klang wing adapter;
it does not automatically reconstruct a different photograph or change capacity.

`diagnostics.json` supplies direct parameter bundles for white/static movers with black
LED, address sweep, and blackout. Apply only with Surface disabled and snapshot/restore
the affected modules; issue its commit revision last. These do not alter artistic banks.

Diagnostic controls: LED pattern 5 and test_face 1-48 for unique address checks;
static pan/tilt with movement size zero; held blackout and held strobe after
controller activation. Review camera movement and occlusion.
See PROGRAMMING.md for the controls (node names use this show's prefix).

Keep this whole directory together. Edit your local show freely; verify reports drift
against installation hashes and never overwrites it. Recreate another fresh directory
for rollback; do not use a generator on a running show. Live compile, save/reopen and
physical device verification remain required for this new identity.
