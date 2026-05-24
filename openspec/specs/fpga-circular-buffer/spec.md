# fpga-circular-buffer Specification

## Purpose
Defines the board-neutral HDL circular-buffer core (TS36.212 §5.1.4.1.2):
bit-collection buffer `w` construction, the `N_cb`/`k_0` redundancy-version
and LBRM start offset, and the filler-skipping circular read that yields the
length-`E` rate-matched output, bit-for-bit equal to the software
`circular_buffer`, plus its golden-vector simulation lane.
## Requirements
### Requirement: Board-neutral circular-buffer core

The system SHALL provide a synthesizable, board-neutral VHDL core under
`hdl/rtl/` that, given a 3×`K_Pi` sub-block-interleaved matrix `v` (each
element a bit plus a `filler` flag) and parameters `(N_ref, I_LBRM, rv_idx,
E)`, produces the length-`E` rate-matched output of TS36.212 §5.1.4.1.2,
bit-for-bit equal to `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`.

#### Scenario: Bit-collection buffer construction

- **WHEN** `v` is loaded
- **THEN** the core forms `w` of length `K_w = 3·K_Pi` with `w[k]=v(1,k)` for
  `k∈[0,K_Pi)` and the rows 2 and 3 interleaved as
  `w[K_Pi+2k]=v(2,k)`, `w[K_Pi+2k+1]=v(3,k)`

#### Scenario: Start offset matches the standard

- **WHEN** the core computes its start offset
- **THEN** `N_cb = K_w` for `I_LBRM=0` else `min(N_ref,K_w)`, and
  `k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)` with `R_TC = K_Pi/32`

#### Scenario: Filler-skipping circular read

- **WHEN** the output is produced
- **THEN** it is exactly `E` values read from `w` at `mod(k_0+j, N_cb)` with
  `j` advancing, skipping `filler` entries, equal to the `circular_buffer`
  golden output

### Requirement: K-agnostic streaming interface

The core SHALL accept `K_Pi/N_ref/I_LBRM/rv_idx/E` at run time via a start
handshake, consume the `K_Pi` `v` columns, then stream the `E` output bits;
it SHALL NOT require any of these fixed at synthesis time.

#### Scenario: Varied parameters without resynthesis

- **WHEN** different `(K_Pi, rv_idx, I_LBRM, E)` are run via the handshake
- **THEN** each yields the correct length-`E` output with no compile-time
  parameter

#### Scenario: Redundancy version and LBRM affect the offset

- **WHEN** the same `v`/`E` are run with different `rv_idx`, or with
  `I_LBRM≠0` and a constraining `N_ref`
- **THEN** the output matches `circular_buffer` for that parameter set
  (different `k_0`/`N_cb` as the standard dictates)

### Requirement: Simulation verified against the software golden model

The system SHALL provide a cocotb/GHDL lane driven by golden vectors generated
from the existing `circular_buffer` helper over a representative parameter set,
comparing every output bit.

#### Scenario: Every output bit matches the golden vector

- **WHEN** the simulation runs a golden case
- **THEN** the streamed length-`E` output equals
  `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)`

#### Scenario: Representative coverage

- **WHEN** the vector suite is generated
- **THEN** it spans encoder-relevant `K_Pi`, all `rv_idx∈{0,1,2,3}`, both
  `I_LBRM` modes, and `E` values including one that forces buffer wrap

### Requirement: Additive board-neutral placement

The change SHALL place the core under `hdl/rtl/` and its simulation under
`hdl/sim/circular_buffer/`, reuse the existing cross-platform HDL flow, keep
generated artifacts out of version control, and modify no existing cores or
specs.

#### Scenario: No regression to existing work

- **WHEN** the change is delivered
- **THEN** prior HDL cores, the existing specs, and MATLAB/Octave sources are
  unchanged, and simulator build products are gitignored

### Requirement: `w` storage infers M4K block RAM, bit-exact preserved

The `circular_buffer` `w_bit`/`w_fill` storage SHALL infer Cyclone II M4K block
RAM under Quartus II 13.0sp1 — synchronous registered read, the array write
lifted out of the synchronous-reset FSM body into an unconditional memory
process — while remaining bit-for-bit equal to
`circular_buffer(v, N_ref, I_LBRM, rv_idx, E)` for every supported parameter
set.

#### Scenario: `w` write is outside the reset-guarded FSM body

- **WHEN** `w_bit`/`w_fill` are loaded during `S_LOAD`
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the load address /
  control registers, not the arrays), and the three-positions-per-column load is
  re-sequenced into a single-write-port-per-array schedule so each array infers
  a 1-write/1-read M4K

#### Scenario: Synchronous read and latency-absorb unchanged

- **WHEN** the circular read streams `w` at the running index
- **THEN** the registered read (`rd_addr` → `rd_bit`/`rd_fill`) and the
  one-cycle latency-absorb beat are preserved, the load and read phases stay
  disjoint, and the emitted `(e_bit, out_valid, last)` stream is identical
  cycle-for-cycle to the pre-rework core

#### Scenario: Hardening preserves the golden output and its lane

- **WHEN** the reworked core is run against the existing
  `hdl/sim/circular_buffer/` cocotb lane
- **THEN** every streamed length-`E` output bit matches
  `hdl/vectors/circular_buffer.csv` and the committed golden vectors are
  byte-identical

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

