## ADDED Requirements

### Requirement: Cross-runtime test framework

The system SHALL provide a test suite that runs unmodified on both MATLAB (R2020a+) and GNU Octave (8.4+) via a vendored copy of [MOxUnit](https://github.com/MOxUnit/MOxUnit) under `tests/MOxUnit/`. The vendored MOxUnit SHALL be pinned to an explicit commit SHA (recorded in `tests/MOxUnit/VERSION` or a git submodule reference) so test behavior is reproducible across runs.

#### Scenario: Test suite runs on Octave
- **WHEN** `octave --no-gui --eval "addpath(genpath('tests/MOxUnit')); moxunit_runtests('tests', '-recursive', '-verbose')"` is invoked at the repository root
- **THEN** all discovered tests execute and the call returns exit code 0 on success, non-zero on any failure

#### Scenario: Test suite runs on MATLAB
- **WHEN** the same MOxUnit `moxunit_runtests` invocation is run from a MATLAB session
- **THEN** the discovered test set is identical (same file count, same scenario count) and all tests pass

#### Scenario: MOxUnit version is pinned
- **WHEN** a contributor clones the repository and initializes submodules
- **THEN** `tests/MOxUnit` checks out at a single, documented commit SHA, not at "latest"

### Requirement: One test file per source, plus property catalogue

The system SHALL provide test files under `tests/` organized as:

- `tests/test_<source>.m` for each source `.m` file in the repository root (mirroring the source filename), containing per-scenario assertions in MOxUnit's `function test_suite = test_<name>` form.
- `tests/property/test_<capability>_properties.m` for property-based tests indexed by OpenSpec capability name (`crc`, `internal-interleaver`, `turbo-encoder`, etc.), where each test sweeps a parameter space (multiple `K`, multiple `rv_idx`, multiple `Q_m`).

#### Scenario: Per-source coverage
- **WHEN** the test directory is inspected
- **THEN** for every non-classdef, non-script `.m` file `<name>.m` in the repository root, a corresponding `tests/test_<name>.m` exists

#### Scenario: Property catalogue exists per capability
- **WHEN** the test directory is inspected
- **THEN** `tests/property/` contains at least one `test_<capability>_properties.m` for each capability spec under `openspec/specs/` (with the exception of `simulation`, which is MATLAB-graphics-bound, and `octave-compatibility`, which is exercised by `test_octave_smoke.m`)

### Requirement: Spec scenarios are test-traceable

Every `#### Scenario:` block in the canonical specs under `openspec/specs/{crc,internal-interleaver,turbo-encoder,turbo-decoder,rate-matching,code-block-segmentation,coding-chain}/spec.md` SHALL have at least one corresponding MOxUnit test whose function name encodes the scenario name (e.g. `function test_supported_short_block(...)` for `#### Scenario: Supported short block`). A spec-to-test traceability check SHALL run in CI and fail when any scenario lacks a test.

#### Scenario: Every scenario has a test
- **WHEN** the spec-to-test traceability script scans `openspec/specs/**/spec.md` for `#### Scenario:` blocks and the `tests/` directory for `function test_<name>` declarations
- **THEN** every scenario in the eligible capabilities is matched by at least one test, and the script exits 0

#### Scenario: New scenario without test fails CI
- **WHEN** a contributor adds a `#### Scenario:` to an existing spec without an accompanying test
- **THEN** the traceability check fails CI with a clear message naming the unmatched scenario

### Requirement: Property-based tests use deterministic seeds

Every property-based test in `tests/property/` SHALL seed `rand('state', N)` (or `rng(N)`) with a fixed integer N declared as the first statement of the test, so that two runs on the same revision are bit-exact. Property tests SHALL sample a documented number of instances per property (e.g. 32 of the 188 supported `K` values for the interleaver bijection property) rather than enumerating the full space, keeping the suite under one minute on a standard CI runner.

#### Scenario: Reproducible failure
- **WHEN** a property test fails
- **THEN** rerunning the same test on the same commit produces the same failure (same `K`, same input, same expected vs actual)

### Requirement: 90 % line coverage of source `.m` files

The system SHALL measure line coverage of source `.m` files using [MOcov](https://github.com/MOcov/MOcov), with the following exclusion list:

- `tests/**`
- `+matlab/**`
- `plot_BLER_vs_SNR.m`
- `plot_SNR_vs_A.m`
- `node_modules/**`

The CI test job SHALL fail when coverage of the included set drops below **90 %**. The achieved coverage percentage and a summary LCOV-style report SHALL be written to `tests/coverage.txt` and uploaded as a GitHub Actions artifact on every run.

#### Scenario: Coverage gate passes
- **WHEN** the test suite runs and line coverage of the included set is ≥ 90 %
- **THEN** the CI job exits 0 and `tests/coverage.txt` is uploaded

#### Scenario: Coverage gate fails
- **WHEN** the test suite runs and line coverage of the included set drops below 90 %
- **THEN** the CI job exits non-zero with a message naming the achieved percentage and the largest contributors to the uncovered set

#### Scenario: Coverage artifact uploaded
- **WHEN** any CI test run completes (pass or fail)
- **THEN** `tests/coverage.txt` is available as a downloadable GitHub Actions artifact for the PR

### Requirement: CI test job integration

The repository's `.github/workflows/ci.yml` SHALL include a `tests` job that:

1. Runs on `ubuntu-latest`.
2. Installs Octave 8.4+ via `apt-get`.
3. Checks out submodules so `tests/MOxUnit/` is populated.
4. Runs the MOxUnit suite via a `scripts/run_tests.sh` (or equivalent) entry point.
5. Runs the spec-to-test traceability check.
6. Runs MOcov coverage measurement and gates at 90 %.
7. Uploads `tests/coverage.txt` as an artifact.

#### Scenario: CI tests job present
- **WHEN** the repository's CI configuration is inspected
- **THEN** `.github/workflows/ci.yml` contains a job that runs the steps above on every pull request and on pushes to `master`

#### Scenario: Local invocation
- **WHEN** a contributor runs `npm test` (mapped in `package.json` to the test runner)
- **THEN** the same MOxUnit invocation runs locally and reports pass/fail and a coverage percentage
