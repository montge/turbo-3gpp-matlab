## ADDED Requirements

### Requirement: Lean 4 CRC equivalence proof

The system SHALL provide a Lean 4 proof under `proofs/lean/` establishing that for each of the four 3GPP CRC polynomials in TS36.212 §5.1.1 (`CRC24A`, `CRC24B`, `CRC16`, `CRC8`) and any natural number `A ≥ 1`, the value computed by the matrix-multiplication formulation `mod(a * G_max, 2)` (where `G_max = get_crc_generator_matrix(A, polynomial)`) is equal to the value computed by direct polynomial division of the bit polynomial `a(x) * x^P` by `polynomial(x)` over GF(2), where `P` is the CRC length.

#### Scenario: Lean checks the CRC proof
- **WHEN** `lake build crc_equivalence` is invoked under `proofs/lean/`
- **THEN** Lean reports `Build completed successfully` with no `sorry` or `axiom` markers in `crc_equivalence.lean`

#### Scenario: CRC proof covers all four polynomials
- **WHEN** the proof script is grep'd
- **THEN** lemmas `crc24a_equivalence`, `crc24b_equivalence`, `crc16_equivalence`, `crc8_equivalence` are each stated and proved (`#check` reports no remaining goals)

### Requirement: Lean 4 QPP interleaver bijection proof

The system SHALL provide a Lean 4 proof that for every supported information-block length `K` in the 188-entry table of TS36.212 §5.1.3.2.3, the function `pi(i) = mod(f1(K) * i + f2(K) * i^2, K)` is a bijection from `Fin K` to `Fin K`. The proof MAY be discharged by enumeration over the 188 cases.

#### Scenario: Lean checks the bijection proof
- **WHEN** `lake build interleaver_bijection` is invoked
- **THEN** Lean reports success with no `sorry` markers

#### Scenario: All 188 K values covered
- **WHEN** the table of supported `K` values in `proofs/lean/InterleaverTable.lean` is compared with the table embedded in `internal_interleaver.m`
- **THEN** both contain exactly the same 188 `(K, f1, f2)` triples

### Requirement: Lean 4 constituent encoder termination proof

The system SHALL provide a Lean 4 proof that applying the three trellis-termination steps defined in TS36.212 §5.1.3.2.2 — `s1' = 0`, `s2' = s1`, `s3' = s2` — to any starting state `(s1, s2, s3)` produces a final state of `(0, 0, 0)`.

#### Scenario: Termination proof checks
- **WHEN** `lake build encoder_termination` is invoked
- **THEN** Lean reports success with no `sorry` markers

#### Scenario: Proof matches the spec
- **WHEN** the Lean encoder model is compared with the source-of-truth in `openspec/specs/turbo-encoder/spec.md`
- **THEN** the same recursion `(s1', s2', s3') = (input, s1, s2)` is used (with `input = 0` during termination), confirming the proof discharges the right requirement

### Requirement: TLA+ HARQ protocol model

The system SHALL provide a TLA+ specification `proofs/tla/harq.tla` modeling the HARQ retransmission protocol implemented by `turbo_encoding_chain` + `turbo_decoding_chain` with `I_HARQ = 1`, including:

- A state variable `rv_idx_sequence : Seq(0..3)` representing the configured retransmission order.
- A state variable `attempt : 1..Len(rv_idx_sequence)` tracking the current retransmission index.
- A state variable `decoded : {NULL} \cup InformationBlock` representing the decoder's current output (`NULL` while still failing CRC).
- Actions for `EncodeAndTransmit`, `Channel` (non-deterministic, models AWGN as bounded bit flips), `DecodeAndCheck`, and `AdvanceRv`.

The model SHALL satisfy:

- **Safety** `CRCPassImpliesCorrect`: in every state where `DecodeAndCheck` sets `decoded /= NULL`, the value of `decoded` equals the originally transmitted information block.
- **Bounded liveness** `EventualTermination`: every trace either reaches a state with `decoded /= NULL` or reaches `attempt = Len(rv_idx_sequence) + 1` (explicit failure), in finite steps.

A `proofs/tla/harq.cfg` SHALL configure TLC with finite parameter bounds (e.g. `Len(rv_idx_sequence) = 4`, information block length `A = 16`) so model checking terminates on a standard CI runner.

#### Scenario: TLC checks the safety invariant
- **WHEN** `tlc harq.tla -config harq.cfg -invariant CRCPassImpliesCorrect` is invoked
- **THEN** TLC reports `Model checking completed. No error has been found.`

#### Scenario: TLC checks bounded liveness
- **WHEN** `tlc harq.tla -config harq.cfg -property EventualTermination` is invoked
- **THEN** TLC reports the property holds, with no deadlocks reported except the explicit failure state

### Requirement: Cryptol/SAW CRC bit-level equivalence

The system SHALL provide:

1. A Cryptol specification `proofs/cryptol/crc_3gpp.cry` defining all four CRC polynomials as Cryptol functions parameterized by input length `A`.
2. A translated reference implementation of `calculate_crc_bits.m` in C or Rust under `proofs/cryptol/calculate_crc_bits.{c|rs}` performing the same row-by-row XOR/shift on a bit-vector representation.
3. A SAW proof script `proofs/cryptol/crc_3gpp.saw` that establishes pointwise equivalence between the Cryptol spec and the translated reference for `A ∈ {1, …, 6144}` and all four polynomials.

#### Scenario: SAW checks the equivalence
- **WHEN** `saw crc_3gpp.saw` is invoked under `proofs/cryptol/`
- **THEN** SAW reports `Valid` for each of the four polynomial-equivalence goals

#### Scenario: Translation drift guard
- **WHEN** the test suite runs (post `add-test-suite-with-coverage`)
- **THEN** a property test asserts that for random `A` and random input bits, both `calculate_crc_bits.m` and the translated reference produce identical CRC bits

### Requirement: Traceability matrix

The system SHALL provide `proofs/traceability.md` containing a table mapping every proof obligation in this capability to:

- The proof artifact (e.g. `proofs/lean/crc_equivalence.lean`, `proofs/tla/harq.tla`)
- The OpenSpec capability and requirement title it discharges (e.g. `crc / CRC calculation, append, and verify`)
- The specific `#### Scenario:` block(s) the proof covers

#### Scenario: Traceability matrix exists and is parseable
- **WHEN** the CI verification job runs
- **THEN** `proofs/traceability.md` exists, contains at least one row per proof obligation listed in this spec, and every cited OpenSpec scenario can be located in `openspec/specs/`

#### Scenario: Adding a proof requires updating traceability
- **WHEN** a new `.lean`, `.tla`, or `.cry` file is added under `proofs/`
- **THEN** CI fails unless `proofs/traceability.md` contains a corresponding row referencing that file

### Requirement: CI verification job

The repository's `.github/workflows/ci.yml` SHALL include a `verify` job that:

1. Runs on `ubuntu-latest`.
2. Installs the pinned versions of Lean 4 (via `elan` and `proofs/lean/lean-toolchain`), TLA+ tools (`tla2tools.jar` at a pinned SHA), and Cryptol + SAW (pinned release tags).
3. Builds and checks each Lean proof via `lake build`.
4. Runs TLC against `proofs/tla/harq.tla` with `proofs/tla/harq.cfg`.
5. Runs `saw proofs/cryptol/crc_3gpp.saw`.
6. Runs the traceability check.
7. Fails fast on any non-zero exit code.

#### Scenario: Verify job present in CI
- **WHEN** the CI configuration is inspected
- **THEN** `.github/workflows/ci.yml` contains a `verify` job with steps for Lean, TLA+, Cryptol/SAW, and the traceability check

#### Scenario: Verify job runs on every PR
- **WHEN** a PR opens or updates
- **THEN** the `verify` job runs on every push, in addition to the existing `octave` and `openspec` jobs
