## 1. Lane Runner

- [ ] 1.1 Add `scripts/run_all_hdl_lanes.sh`: discover `hdl/sim/*/Makefile`, run `make SIM=ghdl` in each, assert the lane's golden CSV exists, fail fast on any non-pass.
- [ ] 1.2 Factor the venv/PATH env shim (POSIX on Linux; Windows LIBPYTHON/PYGPI/PYTHONPATH knobs inert) so local and CI behave identically.
- [ ] 1.3 Verify locally on Windows that the runner executes all current lanes green.

## 2. CI Job

- [ ] 2.1 Add a `hdl-sim` job to `.github/workflows/ci.yml` (ubuntu-latest): apt `ghdl`+`make`, setup Python, `pip install -r requirements-dev.txt`, create `.venv`, run `scripts/run_all_hdl_lanes.sh`.
- [ ] 2.2 Log the GHDL + cocotb versions in the job for drift visibility.
- [ ] 2.3 Job is additive — no edits to existing jobs.

## 3. Verification

- [ ] 3.1 Push; confirm the new job runs and passes on the PR alongside the existing gates.
- [ ] 3.2 Sanity: a deliberately corrupted vector makes the job fail (then revert) — confirms it actually gates.
- [ ] 3.3 Regression: existing CI jobs still pass; no RTL/vector/spec changes.

## 4. Validation and Docs

- [ ] 4.1 Note the runner + CI gate in `hdl/README.md` (or a short `hdl/docs` note).
- [ ] 4.2 `npx openspec validate add-fpga-hdl-ci-gate --strict` passes.
- [ ] 4.3 `npx openspec validate --all --strict` — no regression.

## 5. Follow-on Note (not required for completion)

- [ ] 5.1 PR-subset vs full-suite split (if CI runtime grows) and optional Quartus/synthesis-in-CI recorded as explicit follow-ons; out of scope here.
