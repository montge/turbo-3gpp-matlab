## ADDED Requirements

### Requirement: Encoder `buf` infers M4K block RAM, bit-exact preserved

The `turbo_encode_top` input block buffer `buf` SHALL infer Cyclone II M4K block
RAM under Quartus II 13.0sp1 — synchronous registered reads, the array write
lifted out of the synchronous-reset FSM body, and the one-write/two-read access
served by two simple-dual-port M4K copies — while remaining bit-for-bit equal to
the `turbo_encode_top` and `tx_chain` golden output.

#### Scenario: One-write/two-read served by dual M4K copies

- **WHEN** the encoder reads the natural-order (`buf(didx)`) and interleaved-order
  (`buf(pi_idx)`) taps
- **THEN** `buf` is implemented as two simple-dual-port (1-write/1-read) copies
  written identically — one read by `didx`, one by `pi_idx` — so each is a clean
  M4K (a single 1-write/2-read array cannot map to one M4K)

#### Scenario: `buf` write is outside the reset-guarded FSM body

- **WHEN** `buf` is loaded during `S_LOAD`
- **THEN** the array write statements live at the top level of an unconditional
  clocked memory process (the synchronous reset touches only the load address /
  control registers, not the arrays), and the registered read taps plus the
  prefetch latency-absorb beat keep the encoder feed identical cycle-for-cycle

#### Scenario: Hardening preserves the golden output and its lanes

- **WHEN** the reworked core is run against the existing `turbo_encode_top` and
  `tx_chain_top` cocotb lanes
- **THEN** every streamed output bit matches `hdl/vectors/turbo_encoder.csv` and
  `hdl/vectors/tx_chain.csv`, and the committed golden vectors are byte-identical
