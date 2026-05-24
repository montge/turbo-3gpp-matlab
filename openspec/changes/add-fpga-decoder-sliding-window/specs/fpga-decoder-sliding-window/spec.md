## ADDED Requirements

### Requirement: Sliding-window α/β memory bounds on-chip storage

The system SHALL compute the constituent decoder's α/β metrics over sliding
windows of length `W` with periodic state checkpoints and an `L`-step β
acquisition warm-up, bounding α storage to a window footprint (`≈ 8 × W` plus
checkpoints) instead of the full-block `8 × (K+3)`, so that the full K = 6144
turbo decoder fits the EP2C35 on-chip M4K memory.

#### Scenario: Windowed α with checkpoints replaces full-block α

- **WHEN** the constituent decoder runs with the sliding-window architecture
- **THEN** it stores α for only the active window (`≈ 8 × W`) plus boundary-state
  checkpoints, recomputing α within a window from the nearest checkpoint rather
  than retaining all `K + 3` columns
- **AND** the live α/β storage is independent of K beyond the window/checkpoint
  sizing

#### Scenario: β acquisition warm-up converges before each window is emitted

- **WHEN** β is computed for a window
- **THEN** it is initialised flat (equiprobable) at a column `L` steps beyond the
  window edge and recursed backward across those `L` acquisition steps before any
  in-window extrinsic is emitted
- **AND** the window adjacent to the true block end uses the true terminated-state
  β initialisation instead of a flat acquisition

#### Scenario: Full K = 6144 path fits the EP2C35

- **WHEN** the full K = 6144 constituent / `turbo_decoder_top` / `rx_chain_top`
  path is fit under Quartus II 13.0sp1 for the EP2C35F672C6
- **THEN** it fits within the device's M4K memory (the K = 6144 case that did not
  fit under full-block α), with no Analysis & Synthesis or Fitter errors
- **AND** the K = 512 M4K count drops materially below the full-block baseline
  (constituent 35 M4K, `rx_chain_top` 96/105)

### Requirement: New sliding-window fixed-point reference defines the bit-exact contract

The system SHALL establish a new sliding-window fixed-point reference model and
new golden vectors, because finite-acquisition windowed BCJR is an approximation
whose β/extrinsic is not bit-exact to the full-block decoder; the HDL SHALL be
bit-exact to this new reference, and the prior full-block golden vectors SHALL
NOT apply.

#### Scenario: Inner gate bit-exact to the new windowed reference

- **WHEN** the sliding-window HDL is verified in cocotb over the representative
  K set with the pinned `W` and `L`
- **THEN** it is bit-exact to the new sliding-window fixed-point reference's
  golden vectors (the prior full-block vectors do not apply)

#### Scenario: Inherited fixed-point format unchanged

- **WHEN** the windowed reference and HDL quantize and accumulate metrics
- **THEN** they use the inherited P1 widths (`W_in = 9`, `F_in = 4`,
  `W_gamma = 10`, `W_ab = 15`, `W_delta = 17`, `W_xe = 18`), the per-step
  max-normalization, the saturating arithmetic, and the ±inf sentinel UNCHANGED
- **AND** only the α/β schedule and storage differ from the full-block reference

### Requirement: Windowing loss against the full-block decoder stays within a documented band

The system SHALL characterise the windowed reference against the full-block
decoder and bound the windowing loss within a documented band, separately from
the quantization loss already characterised at P1/P2.

#### Scenario: Constituent-level windowing-loss band

- **WHEN** the windowed fixed-point reference is compared to the full-block
  fixed-point reference on identical LLR frames
- **THEN** the extrinsic-LLR error (max / RMS) and hard-decision agreement on the
  systematic bits stay within the documented windowing-loss band for the pinned
  `W`/`L`

#### Scenario: Loop-level windowing-loss band

- **WHEN** a bounded end-to-end BER-vs-SNR comparison runs the iterative turbo
  decoder with the windowed core against the full-block core (and against float
  `turbo_decoder.m`)
- **THEN** the windowed core's implementation loss stays within the documented dB
  band (≲ 0.1–0.2 dB attributable to windowing for the pinned `L`), confirming
  windowing adds no accuracy regression beyond that margin

#### Scenario: Existing float-vs-fixed margins preserved

- **WHEN** the existing P1 equivalence and P2 BER characterizations are re-run
  with the windowed core
- **THEN** they continue to pass their pinned bands, so windowing does not erode
  the previously established float-vs-fixed-point margins
