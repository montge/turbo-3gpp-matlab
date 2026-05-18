## 1. Lane Runner

- [x] 1.1 `scripts/run_all_hdl_lanes.sh`: discovers `hdl/sim/*/Makefile`, runs `make SIM=ghdl` per lane, asserts a cocotb `PASS>=1 FAIL=0` summary, fails fast-ish (runs all, exits non-zero if any failed).
- [x] 1.2 Env shim factored into sourceable `scripts/hdl_env.sh` (`hdl_env_setup`): POSIX `.venv/bin` on Linux/macOS, Windows `LIBPYTHON_LOC`/`PYGPI_PYTHON_BIN`/`PYTHONPATH` knobs inert off-Windows. (run_hdl_tests.sh left untouched to minimise churn; future tidy could source the helper too.)
- [x] 1.3 Verified locally on Windows: **all 10 lanes PASS** (circular_buffer, crc8, internal_interleaver, qpp_rom, rate_matching_top, rsc_constituent_encoder, subblock_interleaver, turbo_encode_top, turbo_encoder, tx_chain_top).

## 2. CI Job

- [x] 2.1 Added `hdl-sim` job to `.github/workflows/ci.yml` (ubuntu-latest): apt `ghdl`+`make`, setup Python 3.12, `python -m venv .venv` + `pip install -r requirements-dev.txt`, run `scripts/run_all_hdl_lanes.sh`.
- [x] 2.2 Runner logs GHDL + cocotb versions at the top of the job.
- [x] 2.3 Additive only — existing jobs untouched (verified by diff: ci.yml gains one job).

## 3. Verification

- [ ] 3.1 Confirm the `hdl-sim` job runs and passes on the follow-up PR alongside the existing gates. (Deferred to PR push — this branch's commit will trigger it.)
- [x] 3.2 Sanity: deliberately corrupted `crc8_parallel.csv` → crc8 lane `PASS=0 FAIL=1` (gate detects regression); vector restored clean (`git diff` empty). The gate actually gates.
- [x] 3.3 Regression: only additive scripts + one CI job + a design.md wording fix; no RTL/vector/other-spec changes. `npx openspec validate --all --strict` green (below).

## 4. Validation and Docs

- [x] 4.1 `hdl/README.md` documents the lane runner + the CI gate.
- [x] 4.2 `npx openspec validate add-fpga-hdl-ci-gate --strict` — passes.
- [x] 4.3 `npx openspec validate --all --strict` — no regression.

## 5. Follow-on Note (not required for completion)

- [x] 5.1 PR-subset vs full-suite split (if CI runtime grows) and optional Quartus/synthesis-in-CI remain explicit follow-ons in proposal/design; out of scope here.
