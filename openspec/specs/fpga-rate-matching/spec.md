# fpga-rate-matching Specification

## Purpose
Defines the integrated hardware rate matching (`rate_matching_top` = 3×
`subblock_interleaver` + `circular_buffer`, TS36.212 §5.1.4.1) and the complete
hardware LTE transmit chain (`tx_chain_top` = `turbo_encode_top` →
`rate_matching_top`), each verified bit-for-bit against the software model and
reusing all sub-cores unmodified.

## Requirements
### Requirement: Integrated hardware rate matching

The system SHALL provide a board-neutral VHDL `rate_matching_top` that, given
the 3×`D` matrix `d` and parameters `(N_ref, I_LBRM, rv_idx, E)`, produces the
length-`E` rate-matched output of TS36.212 §5.1.4.1 by integrating three
`subblock_interleaver` instances (indices 0/1/2) and the `circular_buffer`
core without modifying them, bit-for-bit equal to
`rate_matching(d, N_ref, I_LBRM, rv_idx, E)`.

#### Scenario: Output matches the software model

- **WHEN** `rate_matching_top` is driven with `d` and the parameters
- **THEN** the streamed length-`E` output equals
  `rate_matching(d, N_ref, I_LBRM, rv_idx, E)`

#### Scenario: Sub-cores reused unmodified

- **WHEN** the integrated rate matcher is delivered
- **THEN** `subblock_interleaver.vhdl` and `circular_buffer.vhdl` are unchanged

### Requirement: Complete hardware transmit chain

The system SHALL provide a board-neutral VHDL `tx_chain_top` that, given a
code block `c`, its length `K`, and rate-match parameters, produces the
length-`E` rate-matched bits by feeding the unmodified `turbo_encode_top` into
`rate_matching_top`, equal to
`rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)), N_ref, I_LBRM,
rv_idx, E)`.

#### Scenario: End-to-end output matches the composed model

- **WHEN** `tx_chain_top` is driven with `(K, c, N_ref, I_LBRM, rv_idx, E)`
- **THEN** the streamed output equals the composed software chain result

#### Scenario: Chain reuses verified cores unmodified

- **WHEN** the chain is delivered
- **THEN** `turbo_encode_top` (and its children) and `rate_matching_top` are
  instantiated unmodified

### Requirement: Simulation verified against the software golden model

The system SHALL provide cocotb/GHDL lanes for `rate_matching_top` and
`tx_chain_top`, driven by golden vectors from `rate_matching.m` and the
composed software chain, comparing every output bit over a representative
parameter set.

#### Scenario: Every output bit matches

- **WHEN** either lane runs a golden case
- **THEN** the streamed length-`E` output equals the corresponding software
  golden output

#### Scenario: Representative coverage

- **WHEN** the vector suites are generated
- **THEN** they span `K`/`D` from the encoder-relevant sizes, `rv_idx` values,
  both `I_LBRM` modes, and `E` including buffer wrap

### Requirement: Additive board-neutral placement

The change SHALL place the new cores under `hdl/rtl/` and their simulations
under `hdl/sim/rate_matching_top/` and `hdl/sim/tx_chain_top/`, reuse the
existing cross-platform HDL flow, keep generated artifacts out of version
control, and modify no existing cores or specs.

#### Scenario: No regression to existing work

- **WHEN** the change is delivered
- **THEN** prior HDL cores, the existing specs, and MATLAB/Octave sources are
  unchanged, and simulator build products are gitignored
