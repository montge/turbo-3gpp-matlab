## ADDED Requirements

### Requirement: `d1/d2/d3buf` infer M4K block RAM, bit-exact preserved

The `rate_matching_top` input buffers `d1buf`/`d2buf`/`d3buf` SHALL each infer a
Cyclone II M4K simple-dual-port (1-write/1-read) block RAM under Quartus II
13.0sp1 — synchronous registered read, the array write lifted out of the
synchronous-reset FSM body — while remaining bit-for-bit equal to
`rate_matching(...)` and the `tx_chain` golden output.

#### Scenario: `d*buf` write is outside the reset-guarded FSM body

- **WHEN** `d1/d2/d3buf` are loaded during `S_LOADD`
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the load address /
  control registers, not the arrays), so each buffer infers a 1-write/1-read M4K

#### Scenario: Registered reads keep the `v` columns identical

- **WHEN** the sub-block interleaver indices read `d1/d2/d3buf`
- **THEN** the registered reads (`rd1/rd2/rd3`) and the pipelined filler/valid
  taps load the `circular_buffer` `v` columns unchanged, and the streamed output
  is identical cycle-for-cycle to the pre-rework core

#### Scenario: Hardening preserves the golden output and its lanes

- **WHEN** the reworked core is run against the existing `rate_matching_top` and
  `tx_chain_top` cocotb lanes
- **THEN** every streamed output bit matches `hdl/vectors/rate_matching.csv` and
  `hdl/vectors/tx_chain.csv`, and the committed golden vectors are byte-identical
