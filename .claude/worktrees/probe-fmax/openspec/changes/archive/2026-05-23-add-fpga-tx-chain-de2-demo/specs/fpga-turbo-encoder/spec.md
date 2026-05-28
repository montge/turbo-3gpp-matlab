## ADDED Requirements

### Requirement: Encoder block buffer is synthesis-hardened, bit-exact preserved

The `turbo_encode_top` core SHALL hold its code-block buffer as synchronous-read,
block-RAM-inferable (M4K) storage with two read taps (natural and interleaved
order) so the encode datapath is implementable on Cyclone II (`EP2C35F672C6`),
while remaining bit-for-bit equal to its software model.

#### Scenario: Block buffer infers dual-port synchronous-read RAM

- **WHEN** the encoder reads the natural-order tap `buf(didx)` and the
  interleaved-order tap `buf(pi_idx)`
- **THEN** both read addresses are registered (synchronous read) so the buffer
  infers a true-dual-port (or duplicated single-port) M4K block RAM rather than
  distributed/LUT RAM
- **AND** the resulting one-cycle read latency is realigned inside the encode
  FSM so `turbo_encoder` samples the same `(c, c')` bit pair on the same beat

#### Scenario: Hardening preserves the golden output and lane

- **WHEN** the hardened `turbo_encode_top` is run against its existing
  `hdl/sim/turbo_encode_top/` cocotb lane
- **THEN** every emitted column triple matches `hdl/vectors/turbo_encoder.csv`
  and the committed golden vectors are unchanged
