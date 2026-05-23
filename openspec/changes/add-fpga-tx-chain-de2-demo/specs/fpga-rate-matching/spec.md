## ADDED Requirements

### Requirement: Rate-match input buffers are synthesis-hardened, bit-exact preserved

The `rate_matching_top` core SHALL hold its `d1/d2/d3` input buffers as
synchronous-read, block-RAM-inferable (M4K) storage so the integrated rate
matcher and the complete transmit chain are implementable on Cyclone II
(`EP2C35F672C6`), while remaining bit-for-bit equal to their software models.

#### Scenario: Input buffers infer synchronous-read RAM

- **WHEN** the sub-block-interleaver index reads `d1buf`/`d2buf`/`d3buf`
- **THEN** the read address is registered (synchronous read) so the buffers
  infer M4K block RAM rather than distributed/LUT RAM
- **AND** the resulting one-cycle read latency is realigned inside the
  rate-match FSM so the `v` columns presented to `circular_buffer` are identical

#### Scenario: Hardening preserves the golden outputs and lanes

- **WHEN** the hardened `rate_matching_top` and `tx_chain_top` are run against
  their existing cocotb lanes
- **THEN** every streamed length-`E` output bit matches
  `hdl/vectors/rate_matching.csv` and `hdl/vectors/tx_chain.csv`, and the
  committed golden vectors are unchanged
