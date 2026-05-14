# Proof obligation → OpenSpec spec traceability

Each row maps one formal-verification artifact to the OpenSpec capability,
requirement, and scenario(s) it discharges. Reviewers can verify coverage
top-to-bottom without opening every proof file.

> **Status legend:** ✅ landed and CI-checked · 🔄 tracked, PR in flight · ⏳ tracked, not started

## Lean 4 (PR 1)

| Status | Proof artifact | Theorem | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ✅ | `proofs/lean/Turbo3gpp/Encoder.lean` | `Turbo3gpp.Encoder.termination_reaches_zero_state` | `openspec/specs/turbo-encoder/spec.md` (Constituent encoder requirement) | "Trellis termination forces zero state" |
| ✅ | `proofs/lean/Turbo3gpp/Interleaver.lean` | `Turbo3gpp.Interleaver.qpp_bijection_for_supported_K` | `openspec/specs/internal-interleaver/spec.md` (QPP interleaver requirement) | "Permutation is a bijection" (over all 188 supported K values) |
| ✅ | `proofs/lean/Turbo3gpp/CRC.lean` | `Turbo3gpp.CRC.crc{24A,24B,16,8}_equivalence` | `openspec/specs/crc/spec.md` (CRC calculation requirement) | "Generator matrix shape", "Generator matrix sized larger than input", "CRC append round-trips with check" — matrix-product CRC ≡ polynomial-division CRC over a finite A-grid (1, 2, 4, 8, 16, 32, 64). Universal-A statement tracked as a follow-up; the algebraic argument is the standard "matrix is a precomputed LFSR" but takes ~200 more lines of stdlib Lean. |
| ✅ | `proofs/lean/Turbo3gpp/Interleaver.lean` (`table` constant) | `Turbo3gpp.Interleaver.table_has_188_entries` | `openspec/specs/internal-interleaver/spec.md` | "All 188 K values covered" — the 188 (K, f1, f2) triples in `table` match the table embedded in `internal_interleaver.m` (length check + per-row review against source). |

## TLA+ / TLC (PR 2 — pending)

| Status | Proof artifact | Property | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ⏳ | `proofs/tla/harq.tla` (`CRCPassImpliesSyndromeZero`) | safety invariant | `openspec/specs/coding-chain/spec.md` (Decoding chain / HARQ requirement) | "HARQ accumulation" + the implicit "decoder declares success ⇒ CRC = 0" assertion |
| ⏳ | `proofs/tla/harq.tla` (`EventualTermination`) | bounded liveness | `openspec/specs/coding-chain/spec.md` | "HARQ accumulation" (loop terminates within `Len(rv_idx_sequence) + 1` steps) |

## Cryptol / SAW (PR 3 — pending)

| Status | Proof artifact | Property | OpenSpec spec | Spec scenario(s) discharged |
|---|---|---|---|---|
| ⏳ | `proofs/cryptol/crc_3gpp.saw` | Cryptol spec ≡ translated `calculate_crc_bits` (C/Rust) for `A ∈ {1, …, 6144}` × all four polynomials | `openspec/specs/crc/spec.md` | Independent bit-level confirmation of the Lean CRC proof. Pairs with the "translation drift guard" property test once landed. |

## Follow-ups tracked here

- **CRC universal-A statement.** The Lean proof currently covers `A ∈ {1, 2, 4, 8, 16, 32, 64}` per polynomial via `native_decide`. Extending to "any natural number A ≥ 1" needs an auxiliary GF(2)-linearity lemma about the LFSR run plus a structural induction over the input list. ~200 more lines of stdlib Lean; tracked as its own change.
- **TLA+ HARQ model** (PR 2).
- **Cryptol/SAW CRC equivalence** (PR 3).
- **CI verify job** currently has `verify-lean` only; PR 2 adds `verify-tla` and PR 3 adds `verify-cryptol`.
