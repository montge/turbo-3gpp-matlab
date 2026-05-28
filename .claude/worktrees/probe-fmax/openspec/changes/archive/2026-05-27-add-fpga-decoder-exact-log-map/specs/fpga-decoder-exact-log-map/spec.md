## ADDED Requirements

### Requirement: Exact Log-MAP correction term and extrinsic scaling

The system SHALL compute the constituent decoder using exact Log-MAP — each
pairwise `max(a,b)` augmented by a LUT-based correction term `f(|a−b|)` (the
`max*` operation) — and SHALL apply an extrinsic scaling factor to the exchanged
extrinsic LLRs, in order to recover the BER loss of the Max-Log-MAP baseline.

#### Scenario: max* replaces plain max in the recurrence and extrinsic

- **WHEN** the exact-Log-MAP constituent decoder evaluates an α/β recurrence
  step or the extrinsic computation
- **THEN** each pairwise combine is `max(a,b) + f(|a−b|)` using a quantized
  correction LUT indexed by `|a−b|`, instead of plain `max(a,b)`
- **AND** the exchanged extrinsic LLRs are multiplied by the configured
  extrinsic scaling factor

#### Scenario: BER improvement over Max-Log-MAP is demonstrated

- **WHEN** the exact-Log-MAP fixed-point reference is characterized against the
  float `turbo_decoder.m` with a bounded BER-vs-SNR comparison
- **THEN** it recovers the ~0.1–0.5 dB Max-Log-MAP loss within a documented dB
  margin of the float model

### Requirement: New exact-Log-MAP fixed-point reference defines the bit-exact contract

The system SHALL establish a new exact-Log-MAP fixed-point reference model and
golden vectors, distinct from the Max-Log-MAP baseline, because the correction
LUT changes the output; the HDL SHALL be bit-exact to this new reference.

#### Scenario: Inner gate bit-exact to the new reference

- **WHEN** the exact-Log-MAP HDL is verified in cocotb over the representative
  K set
- **THEN** it is bit-exact to the new exact-Log-MAP fixed-point reference's
  golden vectors (the prior Max-Log-MAP vectors do not apply)
