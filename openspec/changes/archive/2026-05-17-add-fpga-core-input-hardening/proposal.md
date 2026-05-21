## Why

The automated PR review (CodeRabbit on PR #19) raised 6 actionable items plus
minor doc nits across the HDL cores. None is a correctness defect within the
verified contract — every flagged path is **unreachable** given the controlled
cocotb/golden-vector inputs the project drives by design (sim-first, bounded
inputs). They are legitimate **robustness hardening** for synthesis and reuse
outside the harness. Rather than ad-hoc patching archived, verified cores
(which would churn verified RTL and bypass OpenSpec), this change captures the
hardening as one bounded, deliberate increment.

## What Changes

- **Invalid/zero input guards** (no behaviour change for valid inputs):
  - `circular_buffer`: gate `K_Pi`/`N_cb`/`E = 0` before the compute/read
    paths (avoid divide/mod-by-zero and degenerate scans).
  - `rate_matching_top`: validate `d_len` (`0` or `> DMAX`) before `S_LOADD`.
  - `subblock_interleaver`: clean no-op/error path for `d_in = 0`.
  - `turbo_encode_top`: honour `qpp_rom`'s `supported` flag (don't encode with
    invalid `(d0,step)` for an unsupported `K`).
- **Interface cleanliness:** `qpp_rom` — make `done` a clean one-cycle pulse
  (or document the level semantics consistently with how integrators consume
  it).
- **Generator robustness:** `generate_hdl_qpp_rom.m` — create `hdl/vectors/`
  before `fopen` (match the sibling generators; clean-checkout safe).
- **Docs:** add language identifiers to fenced code blocks flagged in the
  board/sim READMEs and roadmap (the minor nits).

**Hard constraint:** every guard is additive and MUST NOT change output for
any currently-verified vector — all existing HDL lanes stay **bit-exact** and
green; regression is the acceptance gate.

## Capabilities

### New Capabilities

- `fpga-core-input-hardening`: defensive input validation + interface/doc
  cleanliness across the existing HDL cores, with verified behaviour
  preserved.

### Modified Capabilities

<!-- None at the requirement level: the cores' specified behaviour for valid
     inputs is unchanged; this adds out-of-contract input handling only. -->

## Impact

- Edits to `circular_buffer.vhdl`, `rate_matching_top.vhdl`,
  `subblock_interleaver.vhdl`, `turbo_encode_top.vhdl`, `qpp_rom.vhdl`,
  `scripts/generate_hdl_qpp_rom.m`, and a few README/doc fences.
- No golden-vector, MATLAB/Octave, or spec-behaviour changes.
- Re-runs all affected HDL lanes + full regression to prove bit-exactness is
  preserved.
- Non-goals: no algorithm/format change, no new feature, no synthesis work.
