## Context

The backported OpenSpec baseline records the as-built 3GPP turbo coding chain as nine capabilities with WHEN/THEN scenarios per requirement. The scenarios are the contract, but nothing in the repo runs them today. The only check we have — `test_octave_smoke.m` — exercises maybe 30 % of the codepaths and zero of the corner cases (multi-segment was added as an inline CI assertion only after Copilot caught a regression).

We need a test framework that:
- runs unmodified on both MATLAB and Octave (we don't want to maintain two suites),
- discovers tests automatically (no manual test runner registration),
- supports per-function tests AND property-based "for any K in supported set" style tests,
- can be invoked from CI without a license,
- emits a coverage number we can gate on.

## Goals / Non-Goals

**Goals:**
- One test file per source `.m` file in the repo root, plus a `tests/property/` catalogue of property-based tests indexed by capability.
- Every `#### Scenario:` in the OpenSpec specs has at least one corresponding test.
- ≥ 90 % line coverage of the *source* `.m` files (excluding `tests/`, `+matlab/`, and the simulation drivers which are MATLAB-graphics-bound).
- CI fails when coverage drops below the gate, so the floor only ratchets up.

**Non-Goals:**
- 100 % coverage. The graphical simulation drivers (`plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`) and any MATLAB-only paths are explicitly out of scope.
- Mutation testing. Useful but a much bigger investment; track separately if/when scope allows.
- BER/BLER regression testing (Monte Carlo). Out of scope for unit/property tests; covered separately by the simulation drivers.

## Decisions

### Decision 1: Vendor MOxUnit instead of using matlab.unittest or Octave %!test

`matlab.unittest` is the MATLAB-native xUnit framework but its Octave support is partial and brittle (class-based test inheritance behaves differently). Octave's `%!test` / `%!error` blocks live inside source files, which we don't want to touch on a vendored DSP codebase, and don't run on MATLAB at all. [MOxUnit](https://github.com/MOxUnit/MOxUnit) is a small (~3K LOC) xUnit clone that has been in production use on both MATLAB and Octave for years and only needs to be on the path. We vendor it under `tests/MOxUnit/` (git submodule with a pinned commit SHA — concrete SHA picked at implementation time) so CI doesn't need network access during the test run.

### Decision 2: Test layout — one file per source, plus property/

`tests/test_<source>.m` for per-function scenario tests (mirrors the source filename so test discovery is obvious) and `tests/property/test_<capability>_properties.m` for property-based tests that sweep parameter spaces (e.g. "for every supported `K` in `internal_interleaver`'s 188-entry table, `internal_interleaver(0:K-1)` is a permutation"). MOxUnit's `moxunit_runtests('tests', '-recursive')` discovers both.

### Decision 3: MOcov for coverage, 90 % gate on source files only

[MOcov](https://github.com/MOcov/MOcov) wraps a test command and produces line-coverage data. The coverage report excludes `tests/`, `+matlab/`, `plot_BLER_vs_SNR.m`, `plot_SNR_vs_A.m`, and `node_modules/` so the denominator is exactly the deterministic DSP code we want covered. The gate is 90 % to start; we'll ratchet it up via subsequent changes once we know what's realistic for the iterative decoder (`turbo_decoder.m` has a hot inner loop that may need targeted tests).

### Decision 4: Property-based tests are deterministic with fixed seed

To keep CI reproducible, every property test seeds `rand('state', ...)` at the top. We sample N random instances per property (e.g. 32 distinct `K` values for the interleaver property), not all of them, to keep CI under a minute on the runner.

### Decision 5: MISS_HIT for style + lint

[MISS_HIT](https://github.com/florianschanda/miss_hit) is the only mature static-analysis suite that handles both MATLAB and Octave `.m` files: `mh_style` for formatting/style, `mh_lint` for semantic warnings (undefined names, shadowed functions, unreachable code), and `mh_metric` for complexity metrics. It installs via `pip install miss_hit`, emits JSON for CI integration, and is configurable via a `miss_hit.cfg` file at the project root.

To avoid the usual "ratchet hell" of dropping a linter on a vendored DSP codebase, the gate fails CI only on **errors** (clear bugs: undefined variables, shadowed functions, broken syntax). **Warnings** (style preferences, naming) are reported in CI logs but do not fail the build until a separate ratcheting change. `mh_metric` runs informational only; it writes a per-file metric report to `tests/metric.txt` for trend analysis but does not gate.

The MISS_HIT config tunes line length to 120, enables tab-vs-space enforcement, and excludes `tests/MOxUnit/`, `node_modules/`, `results/`, and `openspec/changes/archive/`. The first CI run with this gate enabled MUST pass on the existing source — no preemptive `.m` edits are required.

### Decision 6: Coverage data uploaded as a CI artifact

Storing `tests/coverage.txt` (LCOV summary) as an actions/upload-artifact gives reviewers a quick diff of which lines went from covered → uncovered in a PR. No third-party coverage service (Codecov, Coveralls) is wired up by this change — that's a separate "send coverage upstream" decision.

## Risks / Trade-offs

- **MOxUnit upkeep**: Vendored at a pinned SHA. If MOxUnit ships a breaking change, we update the SHA explicitly. If unmaintained, we fork. Low operational risk.
- **Floating-point sensitivity in tests**: `constituent_decoder.m` uses `log`/`exp` and `maxstar`. Bit-exact LLR comparison across MATLAB/Octave could fail on platform-dependent rounding. Mitigation: where exact comparison fails, tests compare hard-decisioned bits (`c` outputs) rather than raw LLRs, or use a tight `assertElementsAlmostEqual` tolerance from MOxUnit.
- **Octave-only blind spots**: We measure coverage on Octave only. If a path is only reachable on MATLAB (e.g., a `matlab.System` lock semantics), it won't show up. Acceptable: such code is already a known MATLAB-only surface and is excluded.
- **Coverage ratchet drift**: 90 % can be gamed by trivial tests. We pair the gate with the OpenSpec scenario-coverage requirement (every `#### Scenario:` must have a test) so coverage and behavioral coverage move together.
