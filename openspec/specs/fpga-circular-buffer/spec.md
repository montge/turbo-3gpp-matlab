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
