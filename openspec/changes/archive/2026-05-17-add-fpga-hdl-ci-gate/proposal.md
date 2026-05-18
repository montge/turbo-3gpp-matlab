## Why

CI currently gates the MATLAB/Octave model, the formal proofs, and OpenSpec
integrity — but **not** the HDL itself. The cocotb/GHDL lanes (every TX block,
bit-exact vs the golden model) run only locally. For a solo workflow relying
on CI as the safety net, that is the single biggest gap: an HDL regression
would not be caught by a gate. This change adds a GHDL+cocotb CI job so the
HDL lanes become a real gate, closing the gap documented since
`add-fpga-hdl-path`.

## What Changes

- Add a `hdl-sim` job to `.github/workflows/ci.yml` (ubuntu-latest):
  install GHDL + GNU make + Python + cocotb (pinned `requirements-dev.txt`),
  then run every committed HDL lane via `make SIM=ghdl` against the
  **committed golden-vector CSVs** (no Octave regeneration needed — vectors
  are tracked).
- Add `scripts/run_all_hdl_lanes.sh`: enumerate `hdl/sim/*/` lanes, run each,
  fail the job on any non-pass; reused by the CI job and locally.
- The job is **additive** — it does not change existing jobs, RTL, vectors,
  or specs; it only promotes existing local verification to a gate.

## Capabilities

### New Capabilities

- `fpga-ci-gate`: a CI job that runs the cocotb/GHDL HDL lanes on every PR/push
  so HDL correctness is gated, not just locally verified.

### Modified Capabilities

<!-- None. Existing CI jobs, RTL, vectors, and specs are unchanged. -->

## Impact

- `.github/workflows/ci.yml` gains one job; new `scripts/run_all_hdl_lanes.sh`.
- No changes to RTL, golden vectors, MATLAB/Octave sources, or other specs.
- Cross-platform: the lane runner mirrors the local `run_hdl_tests.sh`
  environment handling (POSIX path on Linux CI; the Windows-specific
  LIBPYTHON/PYGPI/PYTHONPATH shim is a no-op on Linux).
- Non-goals: no synthesis/Quartus in CI (toolchain/licensing — stays a
  documented follow-on); no new HDL; decoder lanes join automatically once P1
  lands.
