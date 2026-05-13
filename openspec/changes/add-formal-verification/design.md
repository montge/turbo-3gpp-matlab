## Context

This codebase is unusually well-suited to formal verification compared with a typical software project:

- It is **pure / functional in the relevant places** (CRC, interleaver, constituent encoder are stateless modulo-2 functions over GF(2)).
- The supported input space is **finite and small** (188 `K` values, 4 CRC polynomials, 4 `rv_idx` values). Many proof obligations are *decidable by enumeration*.
- The specification (TS36.212) gives **closed-form math** for each operation, so the proof artifact can be a faithful transcription of the standard with the MATLAB implementation as the obligation to discharge.
- The HARQ retransmission protocol is a **small state machine** that's a natural fit for TLA+/TLC.

The risk is mismatched tooling: picking a single hammer (e.g. Lean only) means stretching it across problems it's not the best fit for. The decision below picks three complementary tools — one for discrete math, one for protocol state machines, one for bit-level cryptographic equivalence.

## Goals / Non-Goals

**Goals:**
- Prove **CRC equivalence** across all four polynomials and arbitrary input length: the matrix-multiplication formulation in `calculate_crc_bits.m` matches polynomial division by the standard's `crc_polynomial_pattern`.
- Prove **QPP interleaver bijection** for every one of the 188 supported `K` values: the polynomial `mod(f1*i + f2*i², K)` is a permutation. This is decidable per-`K` by computation; Lean enumerates.
- Prove **constituent encoder zero-state termination**: the 3-step termination drives `(s1, s2, s3)` to `(0, 0, 0)` from any prior state, matching TS36.212 §5.1.3.2.2.
- Model-check the **HARQ retransmission protocol** safety (CRC pass ⇒ decoded block matches) and bounded liveness (retransmissions terminate within `length(rv_idx_sequence)`).
- Provide bit-level **CRC equivalence in Cryptol/SAW** against an artifact derived from the MATLAB implementation, as an independent cross-check of the Lean proof.

**Non-Goals:**
- Proving the **Log-BCJR decoder is optimal**, or that it achieves any particular BLER. The decoder is iterative numerical; correctness here means "given perfect-confidence LLRs, the decoder returns the original info bits" which is already a test, not a formal-verification target.
- Proving floating-point operations are stable across `maxstar` implementations. Out of scope; the test suite handles bit-exactness via hard-decisioned outputs.
- Hardware extraction. This is verification of the MATLAB spec, not of any synthesized HDL.

## Decisions

### Decision 1: Three tools, each on its strongest fit

| Tool | Used for | Why not the others |
|---|---|---|
| **Lean 4** | CRC matrix ≡ polynomial division (GF(2) algebra); QPP bijection (decidable per `K`); constituent encoder termination | Cryptol/SAW could prove CRC bit-equivalence but is awkward for the QPP table and encoder state machine. TLA+ doesn't reason about GF(2) algebra. |
| **TLA+ / TLC** | HARQ state-machine safety and bounded liveness | Lean can model state machines but lacks TLC's automated model checking; this protocol has a small, finite state space ideal for TLC. |
| **Cryptol / SAW** | CRC bit-level equivalence between Cryptol spec and a translated MATLAB form | Independent confirmation of the Lean CRC proof, using a tool purpose-built for bit-level crypto specs. The redundancy is valuable because CRCs ship in compliance reports. |

### Decision 2: Proofs live under `proofs/<tool>/`, not under `openspec/`

OpenSpec describes *what* the system does; formal proofs are *evidence* the system does it. They're orthogonal artifacts and shouldn't share a directory. `openspec/specs/formal-verification/spec.md` lists the proof obligations; the actual `.lean`, `.tla`, and `.cry` files live under `proofs/`.

### Decision 3: Proof artifacts must be checkable in CI on every PR

Every PR that changes:
- a source `.m` file related to a proven property
- a `proofs/<tool>/` file
- the OpenSpec requirement a proof discharges

...SHALL trigger a re-check of every proof. Toolchains are pinned per-tool (Lean via `elan` + `lean-toolchain`; TLA+ via a pinned `tla2tools.jar` SHA; Cryptol/SAW via a pinned binary release tag) so the CI run is reproducible.

### Decision 4: Traceability matrix is a first-class artifact

`proofs/traceability.md` maps each proof to the OpenSpec requirement and scenario it discharges. Example row:

```
| Lean proof              | Spec                                       | Scenario                       |
| crc_equivalence.lean    | openspec/specs/crc/spec.md                 | "CRC append round-trips ..."   |
```

Reviewers should be able to read the matrix top-to-bottom and confirm coverage without opening each proof file. This is also what we'd export into a conformance report.

### Decision 5: Cryptol/SAW pipeline routes through a translation step, not a direct MATLAB-to-SAW

SAW doesn't read MATLAB. The simplest faithful route is to translate `calculate_crc_bits.m` into a tiny C or Rust function that performs the same row-by-row XOR/shift on a bit-vector representation, then have SAW prove that translation equivalent to the Cryptol spec. The translation lives at `proofs/cryptol/calculate_crc_bits.{c|rs}` and is itself trivially testable (it's a transliteration of a function we already trust under the Lean proof). This is the standard SAW workflow.

## Risks / Trade-offs

- **Three toolchains is a maintenance bill.** True; we pin versions to amortize. The traceability matrix makes any one proof's failure visible and replaceable without affecting the others. If Cryptol or SAW becomes unmaintained, the Lean proof remains and is the canonical CRC correctness statement.
- **The QPP bijection proof is 188 cases.** Lean discharges each by computation; this is fast in practice (seconds), and we tag the lemma `@[reducible]` or use a decision procedure so the proof terms are small.
- **HARQ liveness depends on environment assumptions.** TLC will need a finite channel model — we model AWGN as a non-deterministic "may corrupt one bit" oracle. The liveness property is "given fairness, the loop terminates"; with a finite `rv_idx_sequence` this is decidable.
- **The Cryptol/SAW pipeline introduces a translated C/Rust artifact.** That artifact is itself testable; we pin its source under `proofs/cryptol/`. The risk is that the translation drifts from `calculate_crc_bits.m`. Mitigation: a CI step asserts the translation produces bit-equivalent CRCs on the same random inputs as the MOxUnit property test for CRC round-trip.
- **No proof of the Log-BCJR decoder.** Acknowledged out of scope; future work could attempt a proof in Lean using mathlib's measure theory for the BCJR derivation, but the practical value is low compared with the proven encoder/CRC/interleaver surface that downstream conformance work depends on.
