## ADDED Requirements

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
