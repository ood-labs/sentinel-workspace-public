# Development changes

## State-backed parameter readback (candidate B)

External StateTree changes to an active encoder's state sink now update its
readout, next turn and reload snapshot after 200 ms of encoder quiet. Valid bank
changes schedule a debounced save without an extra target write. Pending local
edits win; invalid values are ignored. Explicit Sentinel readback has precedence.

This fixes the observed GLOBAL failure in both StageRig and LaserViz: native audio
could be at 63% while the surface still displayed 100%. No consumer source patch
or data-schema migration is required. This remains a development candidate until
the cross-show timing, transport and physical acceptance gates pass.
