## Why

Today the project ships with exactly one functional check — `test_octave_smoke.m`, a single noise-free round trip for `A=16, C=1`, plus an inline multi-segment assertion in `ci.yml`. That's enough to catch catastrophic regressions, but it leaves the per-block-size, per-rv_idx, per-iteration-count surface untested. A bit-flip in `internal_interleaver.m`'s QPP table or a subtle off-by-one in `circular_buffer.m` for a particular `K` would slip through.

This change introduces a proper test suite with measurable coverage so future contributions can be evaluated on whether they regress any of the 188 supported information-block sizes, the four redundancy versions, or the early-termination logic, and so the OpenSpec capability specs have direct test-traceability.

## What Changes

- Vendor [MOxUnit](https://github.com/MOxUnit/MOxUnit) as `tests/MOxUnit/` (git submodule or pinned tarball — design.md decides) so the test runner works identically on MATLAB and GNU Octave.
- Add a `tests/` directory with one `test_<source>.m` per source file in the repo root, plus a `tests/property/` subdirectory for property-based tests that sweep parameter spaces.
- Add MOcov-driven line-coverage measurement and require **≥ 90 % line coverage** of the source `.m` files (excluding `tests/`, `+matlab/`, and the simulation drivers which are graphical/MATLAB-only).
- Add [MISS_HIT](https://github.com/florianschanda/miss_hit) static analysis (`mh_style` + `mh_lint` + `mh_metric`) so style and lint defects are caught at PR time on both MATLAB and Octave `.m` files.
- Extend `.github/workflows/ci.yml` with a new `tests` job that runs the suite on Octave 8.4, the MISS_HIT analyzers, and fails CI if the coverage gate or the MISS_HIT error checks are missed.
- Add a `tests/coverage.txt` artifact uploaded by CI so coverage trends are visible per-PR.

## Capabilities

### New Capabilities

- `test-suite`: The MOxUnit-based test framework, the test-file naming convention and discovery rules, the property-based test catalogue (one property per backported capability), the MOcov line-coverage instrumentation and exclusion list, the ≥ 90 % coverage gate, and the CI job that enforces all of the above.

### Modified Capabilities

None. This change does not alter any DSP behavior; it only adds verification.

## Impact

- New top-level `tests/` directory containing MOxUnit, the per-source test files, and the property-based catalogue.
- New `.github/workflows/ci.yml` job `tests`; `npm run test` script in `package.json` for local invocation.
- New CI artifact: `tests/coverage.txt` (LCOV-style summary) uploaded on every run.
- No changes to any existing `.m` source file in the repo root.
- Each requirement in `openspec/specs/{crc,internal-interleaver,turbo-encoder,turbo-decoder,rate-matching,code-block-segmentation,coding-chain}/spec.md` becomes test-traceable: each `#### Scenario:` in the canonical specs gets at least one matching test in `tests/`.
