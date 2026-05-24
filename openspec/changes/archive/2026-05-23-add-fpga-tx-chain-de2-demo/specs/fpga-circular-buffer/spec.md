## ADDED Requirements

### Requirement: Circular buffer is synthesis-hardened, bit-exact preserved

The `circular_buffer` core SHALL be implementable on Cyclone II
(`EP2C35F672C6`) without integer division by a non-power-of-2 and with its
bit-collection storage inferable as synchronous-read block RAM (M4K), while
remaining bit-for-bit equal to `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`
for every supported parameter set.

#### Scenario: No non-power-of-2 dividers

- **WHEN** the core computes `q = ⌈N_cb/(8·R_TC)⌉` and the circular read index
- **THEN** it uses divider-free arithmetic — a subtract-/shift-based recurrence
  for `q` and a running index that conditionally subtracts `N_cb` for the
  `mod N_cb` wrap — with no `/` or `mod` by a non-power-of-2 operand

#### Scenario: Bit-collection storage infers synchronous-read RAM

- **WHEN** the `w_bit`/`w_fill` arrays are read during the circular read
- **THEN** the read address is registered (synchronous read) so the storage
  infers M4K block RAM rather than distributed/LUT RAM
- **AND** any added read latency is absorbed inside the read FSM

#### Scenario: Hardening preserves the golden output and its lane

- **WHEN** the hardened core is run against the existing
  `hdl/sim/circular_buffer/` cocotb lane
- **THEN** every streamed length-`E` output bit matches
  `hdl/vectors/circular_buffer.csv` and the committed golden vectors are
  unchanged
