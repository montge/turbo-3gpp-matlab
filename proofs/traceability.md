# Proof obligation → OpenSpec spec traceability

Each row maps one formal-verification artifact to the OpenSpec capability,
requirement, and scenario(s) it discharges. Reviewers can verify coverage
top-to-bottom without opening every proof file.

> **Status legend:** ✅ landed and CI-checked · 🔄 tracked, PR in flight · ⏳ tracked, not started

## Lean 4 (PR 1)

| Status | Proof artifact | Theorem | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ✅ | `proofs/lean/lakefile.lean` | Lean package and build-target declaration for the proof modules below | `openspec/changes/add-formal-verification/specs/formal-verification/spec.md` (CI verification job requirement) | "Lean checks the CRC proof", "Lean checks the bijection proof", and "Termination proof checks" — gives CI a pinned Lake build graph for all Lean proof modules. |
| ✅ | `proofs/lean/Turbo3gpp.lean` | Root Lean package module importing the proof modules below | `openspec/specs/crc/spec.md`, `openspec/specs/internal-interleaver/spec.md`, `openspec/specs/turbo-encoder/spec.md` | CI build entry point for the Lean proof package; imports the CRC, QPP interleaver, and encoder obligations referenced in the following rows. |
| ✅ | `proofs/lean/Turbo3gpp/Encoder.lean` | `Turbo3gpp.Encoder.termination_reaches_zero_state` | `openspec/specs/turbo-encoder/spec.md` (Constituent encoder requirement) | "Trellis termination forces zero state" |
| ✅ | `proofs/lean/Turbo3gpp/Interleaver.lean` | `Turbo3gpp.Interleaver.qpp_bijection_for_supported_K` | `openspec/specs/internal-interleaver/spec.md` (QPP interleaver requirement) | "Permutation is a bijection" (over all 188 supported K values) |
| ✅ | `proofs/lean/Turbo3gpp/CRC.lean` | `Turbo3gpp.CRC.crc{24A,24B,16,8}_equivalence` | `openspec/specs/crc/spec.md` (CRC calculation requirement) | "Generator matrix shape", "Generator matrix sized larger than input", "CRC append round-trips with check" — matrix-product CRC ≡ polynomial-division CRC over a finite A-grid (1, 2, 4, 8, 16, 32, 64). Universal-A statement tracked as a follow-up; the algebraic argument is the standard "matrix is a precomputed LFSR" but takes ~200 more lines of stdlib Lean. |
| ✅ | `proofs/lean/Turbo3gpp/Interleaver.lean` (`table` constant) | `Turbo3gpp.Interleaver.table_has_188_entries` | `openspec/specs/internal-interleaver/spec.md` | "All 188 K values covered" — the 188 (K, f1, f2) triples in `table` match the table embedded in `internal_interleaver.m` (length check + per-row review against source). |

## TLA+ / TLC (PR 2)

| Status | Proof artifact | Property | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ✅ | `proofs/tla/harq.tla` (`CRCPassImpliesSyndromeZero`) | safety invariant — every state with `decoded /= NULL` satisfies `crcZero(decoded)` | `openspec/specs/coding-chain/spec.md` (Decoding chain / HARQ requirement) | "HARQ accumulation" — the implicit "decoder declares success ⇒ CRC = 0" assertion; checked by TLC over a 4-RV / 2-tag state space (~70 states). |
| ✅ | `proofs/tla/harq.tla` (`TypeOK`, `DoneIsExplicit`) | structural invariants | `openspec/specs/coding-chain/spec.md` | Ratifies that the model's state-space bounds and the "done = success-or-exhausted" condition hold for every reachable state. |
| ✅ | `proofs/tla/harq.tla` (`EventualTermination`) | bounded liveness — `<>[](phase = "done")` | `openspec/specs/coding-chain/spec.md` | "HARQ accumulation" — every trace eventually settles in `phase = done`, which by `DoneIsExplicit` means either `decoded /= NULL` or `attempt = Len(RvIdxSequence) + 1`. No infinite-retransmission cycles. |

## Cryptol / SAW (PR 3)

| Status | Proof artifact | Property | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ✅ | `proofs/cryptol/crc_3gpp.saw` + `proofs/cryptol/crc_3gpp.cry` + `proofs/cryptol/calculate_crc_bits.c` | Bit-level equivalence: the Cryptol spec and the C transliteration produce identical CRC bits for every 16-bit input, across all four 3GPP polynomials (`crc24A`, `crc24B`, `crc16`, `crc8`). Discharged by SAW's `llvm_verify` with Z3 over all 2^16 inputs per polynomial. | `openspec/specs/crc/spec.md` | "SAW checks the equivalence" — independent bit-level confirmation of the Lean CRC proof, using a tool purpose-built for crypto specs. Limited to A = 16 in this PR (representative grid; extension to the full A ∈ {1, …, 6144} range tracked alongside the Lean universal-A follow-up). Caught a real off-by-one in the C `crc24B_poly` constant during initial development; SAW returned a Z3 counterexample that pointed at the polynomial. |

## Follow-ups tracked here

- **CRC universal-A statement.** The Lean proof currently covers `A ∈ {1, 2, 4, 8, 16, 32, 64}` per polynomial via `native_decide`. Extending to "any natural number A ≥ 1" needs an auxiliary GF(2)-linearity lemma about the LFSR run plus a structural induction over the input list. ~200 more lines of stdlib Lean; tracked as its own change.
- **A-grid extension for both CRC tracks** (Lean and Cryptol/SAW). Both currently cover a finite A-grid; full A ∈ {1, …, 6144} extension is tracked as one follow-up because the Lean structural induction and the SAW polymorphic spec land together.
- **Translation drift guard property test** — a MATLAB-side / Octave-side test that compares `calculate_crc_bits.m` output against the C transliteration on random inputs, so a future edit to either file that drifts the two apart fails before SAW ever runs. Pairs with the existing CRC property tests in `tests/property/`.
