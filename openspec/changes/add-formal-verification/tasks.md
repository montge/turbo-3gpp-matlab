## 1. Lean 4 toolchain and scaffold

- [ ] 1.1 Add `proofs/lean/lean-toolchain` pinning a specific Lean 4 toolchain version (e.g. `leanprover/lean4:v4.x.y`)
- [ ] 1.2 Add `proofs/lean/lakefile.lean` declaring the project and any mathlib dependency at a pinned revision
- [ ] 1.3 Add `proofs/lean/lake-manifest.json` (auto-generated) and commit it
- [ ] 1.4 Smoke-build the empty Lean project (`lake build`) and confirm exit 0

## 2. Lean 4: CRC equivalence

- [ ] 2.1 Define `proofs/lean/CRC/Polynomial.lean` with the four 3GPP polynomials as `List Bool` (matching the bit-order convention in `get_3gpp_crc_polynomial.m`)
- [ ] 2.2 Define `proofs/lean/CRC/GeneratorMatrix.lean` mirroring `get_crc_generator_matrix.m`
- [ ] 2.3 Define `proofs/lean/CRC/PolyDivision.lean` with classical polynomial division over GF(2)
- [ ] 2.4 Prove `crc_equivalence` showing matrix-product CRC equals poly-division CRC for arbitrary `A` and polynomial coefficients
- [ ] 2.5 Specialize to `crc24a_equivalence`, `crc24b_equivalence`, `crc16_equivalence`, `crc8_equivalence`
- [ ] 2.6 `lake build` succeeds with no `sorry`

## 3. Lean 4: QPP interleaver bijection

- [ ] 3.1 Define `proofs/lean/Interleaver/Table.lean` with the 188 `(K, f1, f2)` triples from `internal_interleaver.m` (verify by string-diff against the source)
- [ ] 3.2 Define `proofs/lean/Interleaver/QPP.lean` with `pi K f1 f2 i = (f1 * i + f2 * i^2) % K`
- [ ] 3.3 Prove `qpp_bijection_for_K : (K, f1, f2) ∈ Table → Function.Bijective (pi K f1 f2)` by `decide` (each case discharged by direct computation)
- [ ] 3.4 `lake build` succeeds with no `sorry`

## 4. Lean 4: constituent encoder termination

- [ ] 4.1 Define `proofs/lean/Encoder/Constituent.lean` with the state-transition relation matching `constituent_encoder.m`
- [ ] 4.2 Prove `termination_reaches_zero_state : ∀ (s1 s2 s3 : Bool), applyTermination (s1, s2, s3) = (false, false, false)`
- [ ] 4.3 `lake build` succeeds

## 5. TLA+ HARQ model

- [ ] 5.1 Add `proofs/tla/harq.tla` declaring state variables (`rv_idx_sequence`, `attempt`, `decoded`, `buffer`) and actions (`EncodeAndTransmit`, `Channel`, `DecodeAndCheck`, `AdvanceRv`)
- [ ] 5.2 State the safety invariant `CRCPassImpliesSyndromeZero` and the *liveness* property `EventualTermination` (the latter is a temporal property, not a state invariant, and SHALL be checked separately with TLC's `-property` flag rather than `-invariant`)
- [ ] 5.3 Add `proofs/tla/harq.cfg` bounding `Len(rv_idx_sequence) = 4`, `A = 16`, channel non-determinism cardinality
- [ ] 5.4 Run TLC locally against the safety invariant and confirm it completes without finding a counterexample
- [ ] 5.5 Run TLC against `EventualTermination` and confirm liveness holds
- [ ] 5.6 Pin `tla2tools.jar` SHA in a `proofs/tla/tla-version` file

## 6. Cryptol / SAW CRC equivalence

- [ ] 6.1 Add `proofs/cryptol/crc_3gpp.cry` defining the four CRCs in Cryptol parameterized by input length
- [ ] 6.2 Add `proofs/cryptol/calculate_crc_bits.{c|rs}` transliterating the row-by-row XOR/shift implementation of `calculate_crc_bits.m`
- [ ] 6.3 Add `proofs/cryptol/crc_3gpp.saw` proving Cryptol spec ≡ translated reference for `A ∈ {1, …, 6144}` and each polynomial
- [ ] 6.4 Pin Cryptol and SAW versions in `proofs/cryptol/version.txt`
- [ ] 6.5 Run `saw crc_3gpp.saw` locally and confirm `Valid` for each goal

## 7. Traceability matrix

- [ ] 7.1 Add `proofs/traceability.md` with one row per proof obligation listed in the spec, citing the proof artifact, the OpenSpec capability/requirement, and the scenario(s) discharged
- [ ] 7.2 Add `scripts/check_proof_traceability.py` (or `.m`) that verifies every `.lean` / `.tla` / `.cry` file under `proofs/` is referenced by `proofs/traceability.md`
- [ ] 7.3 Add the check as a CI step

## 8. CI verification job

- [ ] 8.1 Add a `verify` job to `.github/workflows/ci.yml`
- [ ] 8.2 Install Lean via `leanprover/lean-action@v1` (or `elan curl install`) with cache keyed on `lean-toolchain`
- [ ] 8.3 Download and cache `tla2tools.jar` at the pinned SHA
- [ ] 8.4 Install Cryptol + SAW via pinned binary release; cache `~/.cabal` or equivalent if needed
- [ ] 8.5 Step: `cd proofs/lean && lake build`
- [ ] 8.6 Step: `cd proofs/tla && java -jar $TLA_JAR -config harq.cfg harq.tla`
- [ ] 8.7 Step: `cd proofs/cryptol && saw crc_3gpp.saw`
- [ ] 8.8 Step: run the traceability check

## 9. Documentation

- [ ] 9.1 Add `proofs/README.md` covering how to install each toolchain locally and run each proof
- [ ] 9.2 Add a "Formal verification" badge to `README.md`
- [ ] 9.3 Cross-link from each `openspec/specs/<cap>/spec.md` (where applicable) to the proof obligation it carries

## 10. Land

- [ ] 10.1 `npx openspec validate add-formal-verification --strict` passes
- [ ] 10.2 The `verify` CI job is green on the PR
- [ ] 10.3 All proofs check on a clean clone (no cached artifacts)
- [ ] 10.4 Archive after merge with `openspec archive add-formal-verification`
