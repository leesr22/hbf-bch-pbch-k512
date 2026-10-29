# Curation and provenance

This directory was curated from source commit
`cb3e897aebcb0466fb7701068e23cadaf48b4768` in
`/home/leesr0222/hbf-pbch-clean-k512`.

Included final implementations:

1. BCH Encoder W128
2. BCH Decoder W64 t=6
3. PBCH Encoder W64 ctx2 with incremental Gaussian Solver
4. PBCH Decoder W64 parent t=4 with selector FIFO and streaming recovery

Removed from the curated source tree:

- table, hybrid and direct masking Solver candidates;
- unused alternative BM, syndrome, Chien and replay implementations;
- failed/intermediate synthesis runs and broad candidate matrices;
- simulator build products.

The PBCH Encoder top was mechanically simplified to instantiate `mask_gauss`
directly. The removed METHOD branches were elaboration-dead in the selected
`pbch_encode_gauss` top. The constant `table_supported` output and associated
always-true state were also removed. Functional datapath, fallback rule,
selector, stored codeword, context scheduling and external source-cache
contract are unchanged.

Verification status:

- original selected source: completed VCS bit/status regressions listed in
  `docs/VERIFICATION.md` and preserved under `sim/logs/`;
- curated source: all four synthesis tops pass installed Verilator elaboration
  and lint with warnings only;
- a fresh VCS run was attempted, but the current invocation waited for an
  unavailable license. It is not reported as a completed fresh regression;
- copied UMC28 netlists/reports correspond to the original selected elaboration.
  A source-identical PPA for the mechanically curated source requires a new DC
  run ID, as documented in `docs/REPRODUCE.md`.

