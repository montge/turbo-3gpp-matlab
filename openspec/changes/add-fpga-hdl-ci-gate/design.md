## Context

`.github/workflows/ci.yml` is a standard GitHub Actions matrix of
`ubuntu-latest` jobs (Octave, MOxUnit+coverage, Lean, Cryptol/SAW, TLA+,
OpenSpec validate). The HDL lanes (`hdl/sim/*/`) read **committed** golden
CSVs and check the RTL bit-exact via cocotb/GHDL; they currently run only on
the developer's machine. The local entry point is `scripts/run_hdl_tests.sh`
(crc8 only) — it already handles the cross-platform venv/PATH shim.

## Goals / Non-Goals

**Goals:** every `hdl/sim/*/` lane runs as a CI gate on PR/push, using
committed vectors (no Octave dependency in the HDL job); a single lane runner
reused locally and in CI; zero change to existing jobs/RTL/vectors/specs.

**Non-Goals:** no Quartus/synthesis in CI (toolchain + licensing — documented
follow-on); no new HDL or vectors; no change to the other CI jobs.

## Decisions

1. **apt GHDL + pip cocotb on ubuntu.** `ghdl` and `make` from apt; Python +
   `pip install -r requirements-dev.txt` (pinned `cocotb==2.0.1`). The HDL
   lanes consume committed CSVs, so the job needs **no Octave/MATLAB** and is
   independent of the model regeneration path.

2. **One lane runner, reused.** `scripts/run_all_hdl_lanes.sh` discovers
   `hdl/sim/*/Makefile`, runs `make SIM=ghdl` in each, and exits non-zero on
   the first failure (parses cocotb `FAIL=`/non-zero make). CI calls it;
   developers can too. New lanes (e.g. P1 decoder) are picked up
   automatically.

3. **Reuse the env shim.** Factor the venv/PATH/`LIBPYTHON_LOC`/
   `PYGPI_PYTHON_BIN`/`PYTHONPATH` logic so Linux CI uses the POSIX `.venv/bin`
   path and the Windows-only knobs are inert — keeping local and CI identical
   in behaviour.

4. **Additive job.** New `hdl-sim` job only; existing jobs untouched, so a
   green run is strictly more coverage than today.

## Risks / Trade-offs

- **CI runtime growth** (full lanes incl. K=6144 ≈ tens of seconds each) →
  acceptable; if it becomes slow, gate a representative subset on PR and the
  full set on `master` push (note, not v1).
- **GHDL/cocotb version drift on apt** → cocotb pinned via
  `requirements-dev.txt`; record the GHDL apt version in the job log; mismatch
  surfaces as a lane failure, not a silent pass.
- **Vectors must be committed** (already are) → a missing vector surfaces as
  that lane's cocotb test failing (clear non-zero exit). The runner does *not*
  hard-map dir→CSV: the mapping is intentionally irregular (`turbo_encode_top`
  reuses `turbo_encoder.csv`; `rsc_constituent_encoder` has no CSV by design,
  it checks a Python reference), so a brittle pre-check would false-fail.
  "A future change forgot the vector" is therefore caught by lane execution,
  not a name-mapped assertion.

## Open Questions

- PR-subset vs full-suite split if runtime grows — defer until measured.
- Whether to also run the constituent-decoder *equivalence* harness in CI
  once P1 lands (Octave-dependent) — decide in the P1/P2 changes, not here.
