## 1. Vendor MOxUnit and wire up the runner

- [x] 1.1 Add `tests/MOxUnit/` as a git submodule pinned to a specific commit SHA (record the SHA in the commit message)
- [x] 1.2 Add `scripts/run_tests.sh` that adds `tests/MOxUnit` to the path, runs `moxunit_runtests('tests', '-recursive', '-verbose')` under Octave, and exits non-zero on any failure
- [x] 1.3 Add an `npm test` script to `package.json` that calls `scripts/run_tests.sh`
- [x] 1.4 Smoke-run the empty suite (no tests yet) and confirm exit 0

## 2. Add per-source unit tests

For each source `.m` file in the repository root, add `tests/test_<source>.m` covering the corresponding `#### Scenario:` blocks from the canonical spec:

- [x] 2.1 `tests/test_get_3gpp_crc_polynomial.m` — covers `crc/spec.md` polynomial scenarios
- [x] 2.2 `tests/test_get_crc_generator_matrix.m` — shape + invalid polynomial scenarios
- [x] 2.3 `tests/test_calculate_crc_bits.m` / `test_generate_and_append_crc_bits.m` / `test_check_and_remove_crc_bits.m` — round-trip + corruption scenarios
- [x] 2.4 `tests/test_get_3gpp_code_block_segment_lengths.m` — single-segment, multi-segment, invalid B
- [x] 2.5 `tests/test_get_3gpp_encoded_code_block_segment_lengths.m` — equal-length, unequal-length
- [x] 2.6 `tests/test_code_block_segmentation.m` / `test_code_block_desegmentation.m` / `test_code_block_concatenation.m` / `test_code_block_deconcatenation.m` — round-trip + CRC-failure scenarios
- [x] 2.7 `tests/test_internal_interleaver.m` — smallest, largest, bijection, unsupported K scenarios
- [x] 2.8 `tests/test_constituent_encoder.m` — output shape, zero-input, termination-to-zero-state
- [x] 2.9 `tests/test_turbo_encoder.m` — output shape, interleaver mismatch, filler-bit propagation
- [x] 2.10 `tests/test_subblock_interleaver.m` — output length multiple-of-32, unsupported index
- [x] 2.11 `tests/test_circular_buffer.m` — rv_idx offsets, filler skipping, invalid rv_idx
- [x] 2.12 `tests/test_rate_matching.m` — encode→derate round trip
- [x] 2.13 `tests/test_maxstar.m` — exact, approximate, column-reduction forms
- [x] 2.14 `tests/test_constituent_decoder.m` — LLR length mismatch
- [x] 2.15 `tests/test_turbo_decoder.m` — shape, early termination, filler in output, half-iteration, invalid iteration count
- [x] 2.16 `tests/test_turbo_coding_chain.m` — default construction, name-value pairs, rejected Q_m/rv_idx, derived params, decoding-chain name-value pairs
- [x] 2.17 `tests/test_turbo_encoding_chain.m` — default-size G output, determinism
- [x] 2.18 `tests/test_turbo_decoding_chain.m` — noise-free round trip, HARQ accumulation, CRC failure → empty

## 3. Add property-based tests under `tests/property/`

- [x] 3.1 `tests/property/test_crc_properties.m` — round-trip for random A on all four polynomials
- [x] 3.2 `tests/property/test_internal_interleaver_properties.m` — bijection for 32 random K from the 188-entry table, with fixed seed
- [x] 3.3 `tests/property/test_turbo_encoder_properties.m` — encoder is deterministic and shape-correct for 16 random K
- [x] 3.4 `tests/property/test_turbo_decoder_properties.m` — noise-free LLR mapping recovers original bits across 16 random `(A, G, Q_m, rv_idx)` combinations
- [x] 3.5 `tests/property/test_rate_matching_properties.m` — derate maps each `e` index back to a unique `d` index for 16 random `(D, F, rv_idx)`
- [x] 3.6 `tests/property/test_code_block_segmentation_properties.m` — segmentation round-trip for 32 random B including the `B > 6144` regime

## 4. Spec-to-test traceability check

- [x] 4.1 Add `scripts/check_spec_traceability.py` (or a `.m` equivalent) that scans `openspec/specs/**/spec.md` for `#### Scenario:` headers and the `tests/` tree for `function test_<name>` declarations, then asserts every eligible scenario is matched
- [x] 4.2 Document the exclusion list (capabilities skipped: `simulation`, `octave-compatibility` since they're covered by other means)
- [x] 4.3 Wire the check into CI as a separate step (so its failure mode is distinct from a test failure)

## 5. Coverage measurement

- [x] 5.1 Vendor or `pip install` MOcov in the CI workflow
- [x] 5.2 Wrap the MOxUnit invocation in `mocov` to produce `tests/coverage.txt` (LCOV summary)
- [x] 5.3 Add a coverage-gate step that parses the percentage and exits non-zero below 90 %
- [x] 5.4 Upload `tests/coverage.txt` via `actions/upload-artifact@v4`

## 5b. MISS_HIT static analysis

- [x] 5b.1 Add `miss_hit.cfg` at the repository root with `project_root` set, the documented exclusions (`tests/MOxUnit`, `node_modules`, `results`, `openspec/changes/archive`), and rule tuning so the first CI run passes against the existing source unchanged
- [x] 5b.2 Pin a MISS_HIT version in `requirements-ci.txt` (or directly in the workflow) and install it in CI via `pip install`
- [x] 5b.3 Run `mh_style --fail-on-error` against the repository in CI
- [x] 5b.4 Run `mh_lint --fail-on-error` against the repository in CI
- [x] 5b.5 Run `mh_metric` producing `tests/metric.txt` (informational; no failure threshold)
- [x] 5b.6 Upload `tests/metric.txt` via `actions/upload-artifact@v4`
- [x] 5b.7 Verify the gate passes on master with zero `.m` edits

## 6. CI integration

- [x] 6.1 Add a new `tests` job to `.github/workflows/ci.yml` running steps 1.2 → 5.3 on `ubuntu-latest`
- [x] 6.2 Mark the existing `octave` smoke job as a dependency-free baseline (do not remove)
- [x] 6.3 Verify the new job passes on a no-changes-to-source PR

## 7. Documentation

- [x] 7.1 Add a "Running tests" section to `README.md` covering `npm test` and the coverage artifact
- [x] 7.2 Add a coverage badge to `README.md` pointing at the artifact or a shields.io endpoint

## 8. Land

- [x] 8.1 `npx openspec validate add-test-suite-with-coverage --strict` passes
- [x] 8.2 New CI `tests` job is green on the PR
- [x] 8.3 Coverage report shows ≥ 90 % on the included set
- [x] 8.4 Archive after merge with `openspec archive add-test-suite-with-coverage`
