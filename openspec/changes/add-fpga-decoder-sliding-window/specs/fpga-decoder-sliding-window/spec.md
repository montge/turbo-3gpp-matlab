## ADDED Requirements

### Requirement: Sliding-window α memory bounds on-chip storage

The system SHALL compute the constituent decoder's forward α metrics over
sliding windows with periodic state checkpoints, bounding α storage to a window
footprint (`8 × W` plus checkpoints) instead of the full-block `8 × (K+3)`, so
that the full K = 6144 turbo decoder fits the EP2C35 on-chip memory.

#### Scenario: Windowed α with checkpoints replaces full-block α

- **WHEN** the constituent decoder runs with the sliding-window architecture
- **THEN** it stores α for only the active window (`8 × W`) plus boundary-state
  checkpoints, recomputing α within a window from the nearest checkpoint rather
  than retaining all `K+3` columns
- **AND** the resulting α store is independent of K beyond the window/checkpoint
  sizing

#### Scenario: Full K = 6144 path fits the EP2C35

- **WHEN** the full K = 6144 turbo decoder path is fit under Quartus II 13.0sp1
  for the EP2C35
- **THEN** it fits within the device's M4K memory (the K = 6144 case that did
  not fit under full-block α), with no Fitter or Analysis & Synthesis errors

### Requirement: New sliding-window fixed-point reference defines the bit-exact contract

The system SHALL establish a new sliding-window fixed-point reference model and
golden vectors, because windowed α traversal changes the bit-exact contract;
the HDL SHALL be bit-exact to this new reference and characterized against the
float model within a documented band.

#### Scenario: Inner gate bit-exact to the new reference

- **WHEN** the sliding-window HDL is verified in cocotb over the representative
  K set
- **THEN** it is bit-exact to the new sliding-window fixed-point reference's
  golden vectors (the prior full-block vectors do not apply)

#### Scenario: Outer characterization confirms no accuracy regression

- **WHEN** the sliding-window fixed-point reference is characterized against the
  float `constituent_decoder.m` / `turbo_decoder.m`
- **THEN** the constituent-level equivalence and the bounded loop-level
  BER-vs-SNR stay within the documented band, confirming windowing adds no
  accuracy regression beyond that margin
