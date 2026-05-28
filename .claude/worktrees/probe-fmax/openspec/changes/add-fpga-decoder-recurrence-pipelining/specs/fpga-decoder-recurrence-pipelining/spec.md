## ADDED Requirements

### Requirement: Pipelined α/β recurrence raises decoder Fmax

The system SHALL restructure the constituent decoder's α/β forward/backward
recurrence using ACS look-ahead or radix-2 unrolling to break the single-cycle
saturating-add → max-normalize → saturate feedback cone, raising the decoder
Fmax above the current ~15.4 MHz so that `turbo_decoder_top` closes timing at
50 MHz, removing the Option-A slow-clock workaround.

#### Scenario: Feedback cone is broken by look-ahead

- **WHEN** the restructured constituent decoder computes the α/β recurrence
- **THEN** it folds two trellis steps into one precomputed-then-selected cycle
  (look-ahead / radix-2) so the per-cycle combinational path no longer spans a
  full single-step 8-way saturating-add → max-norm → saturate cone

#### Scenario: 50 MHz timing closure demonstrated

- **WHEN** `turbo_decoder_top` (at the board-demo K) is fit under Quartus II
  13.0sp1
- **THEN** it closes timing at 50 MHz (vs the prior ~15.4 MHz limit), so the
  decoder demo no longer needs the ~12.5 MHz PLL workaround

### Requirement: New pipelined fixed-point reference defines the bit-exact contract

The system SHALL establish a new fixed-point reference model capturing the
pipelined recurrence schedule and intermediate widths, and golden vectors,
because the restructuring changes the internal schedule; the HDL SHALL be
bit-exact to this new reference and characterized to show unchanged decoded
output.

#### Scenario: Inner gate bit-exact to the new reference

- **WHEN** the pipelined-recurrence HDL is verified in cocotb over the
  representative K set
- **THEN** it is bit-exact to the new pipelined fixed-point reference's golden
  vectors (the prior decoder vectors do not apply unchanged)

#### Scenario: Decoded output unchanged within the documented band

- **WHEN** the pipelined reference is characterized against the float model
- **THEN** the decoded output / BER is unchanged within the documented band,
  confirming the restructuring is a throughput optimization only
