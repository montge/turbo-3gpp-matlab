## Why

The complete LTE transmit chain (`tx_chain_top` = `turbo_encode_top` →
`rate_matching_top`) is built and bit-exact in simulation, but the only 3GPP
block ever proven on real silicon is the trivial combinational `crc8_parallel`
(archived `add-de1-de2-board-bringup`). The TX cores were written **sim-first**:
they use integer division, a non-power-of-2 `mod`, and large async-read arrays
that GHDL simulates exactly but that do **not** map cleanly to Cyclone II
fabric. Their own headers already flag the divider rewrite as a documented
follow-on (`circular_buffer.vhdl` lines 11–13).

This change is the first **DE2 hardware bring-up** beyond crc8: synthesis-harden
the TX chain so it fits and closes timing on a real `EP2C35F672C6`, then
demonstrate `tx_chain_top` at a small fixed `K` on the board using the proven
crc8 harness pattern (on-chip golden-vector ROM + self-check FSM + LED/7-seg
pass/fail). It proves the sim→synthesis hardening discipline on a real turbo
block while keeping the cocotb bit-exact gate green and the committed golden
vectors unchanged.

The decoder is deliberately **not** the first hardware target: it needs
sliding-window / sync-α-BRAM rework first (decoder roadmap M2) and its board
demo is a separate later increment (M4). This change is TX-only.

## What Changes

- **Synthesis-harden `circular_buffer.vhdl`** so it infers Cyclone II fabric
  without integer dividers:
  - replace `q = ⌈N_cb/(8·R_TC)⌉` (the non-power-of-2 divide at ~line 121) with
    a subtract-/shift-based recurrence (the approach the file header already
    documents);
  - replace the non-power-of-2 `pos = (k_0+j) mod N_cb` (~line 134) with a
    running index that conditionally subtracts `N_cb`;
  - make the two ~18,528-bit `w_bit`/`w_fill` arrays (~lines 37–39, 136)
    **synchronous-read** so they infer M4K block RAM (M4K is sync-read only);
  - bound the unbounded `jj` integer (~line 54).
- **Make the rate-match and encoder buffers synchronous-read** so they infer
  M4K rather than huge LUT-RAM/registers: `d1/d2/d3buf` in
  `rate_matching_top.vhdl` (~lines 105–107) and the dual-async-read `buf` in
  `turbo_encode_top.vhdl` (~lines 129–130).
- **All hardening is bit-exact-preserving.** The existing cocotb lanes
  (`circular_buffer`, `rate_matching_top`, `turbo_encode_top`, `tx_chain_top`)
  stay green and the committed golden vectors are unchanged; any read-latency
  shift is absorbed inside the FSMs so the verified output streams are
  identical.
- **Add a DE2 board demo for `tx_chain_top`** under `hdl/boards/de2/`, reusing
  the crc8 pattern: a board wrapper instantiates the (now hardened) core
  unmodified; an on-chip ROM holds ONE golden vector for a chosen small `K`
  (e.g. `K=40` from `hdl/vectors/tx_chain.csv`); a self-check FSM clocks the
  core at `CLOCK_50`, compares the streamed length-`E` output against the
  expected bits, and drives LED = pass/fail plus a 7-seg status code. No UART.
- **Add a board `.qsf`/`.sdc` and README** for the demo, isolated under
  `hdl/boards/de2/`, reusing the crc8 `EP2C35F672C6` pin table and `hex7seg`.

## Capabilities

### New Capabilities

- `fpga-tx-chain-de2-demo`: the on-chip golden-vector ROM + self-check FSM +
  LED/7-seg pass/fail DE2 demonstration of `tx_chain_top` at a fixed small `K`,
  clocked at `CLOCK_50`, validated against the committed `tx_chain` golden
  vector — a genuinely new clocked, self-checking board behavior distinct from
  the asynchronous switch-driven crc8 smoke.

### Modified Capabilities

- `fpga-circular-buffer`: add a synthesis-hardening requirement (divider-free
  arithmetic + synchronous-read BRAM-inferable `w` storage) that explicitly
  preserves the bit-exact `circular_buffer` contract and the existing cocotb
  lane; relaxes the prior "the core is unchanged" placement clause for this
  specific, gate-guarded hardening.
- `fpga-rate-matching`: add a synthesis-hardening requirement for the
  `d1/d2/d3buf` input buffers (synchronous-read, BRAM-inferable) preserving the
  `rate_matching_top` and `tx_chain_top` bit-exact contracts and their cocotb
  lanes.
- `fpga-turbo-encoder`: add a synthesis-hardening requirement for the encoder
  block `buf` (synchronous-read dual-port, BRAM-inferable) preserving the
  `turbo_encode_top` bit-exact contract and its cocotb lane.

`fpga-board-bringup` is intentionally **not** modified: its requirements are
worded specifically around the `crc8_parallel` core and an asynchronous,
human-driven switch smoke. The clocked, ROM-fed, self-checking TX-chain demo is
a different shape of board behavior, so it gets its own capability rather than
overloading the CRC bring-up spec.

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, or `.m`
  edits land here. This is the proposal; implementation follows in the staged
  `tasks.md`.
- When implemented: `hdl/rtl/circular_buffer.vhdl`,
  `hdl/rtl/rate_matching_top.vhdl`, `hdl/rtl/turbo_encode_top.vhdl` are edited
  for synthesis (bit-exact preserved); new files under `hdl/boards/de2/` (TX
  demo wrapper, on-chip ROM, self-check FSM, `.qpf`/`.qsf`/`.sdc`, README).
- The `tx_chain_top` core, `qpp_interleaver`, and `subblock_interleaver` need
  no change (already divider-free; the chain uses 0 multipliers, ~55 Kbit ≈ 12
  of 105 M4K — trivial fit).
- Depends on Quartus II 13.0sp1 on the existing Windows host; board
  synthesis/program remains a local/manual step, not CI.
- Requires physical DE2 hardware only for the final program-and-observe step;
  the hardening, cocotb gate, fit, and timing closure are all verifiable
  without a board.

## Out of Scope (explicit — all later increments)

- Decoder board demo (decoder roadmap M4) and the sliding-window / sync-α-BRAM
  decoder rework (M2).
- UART or any host link (deferred; on-chip ROM + self-check is the I/O).
- Large `K` on the board (the demo fixes one small `K`); multi-vector or
  parameter-swept on-board runs.
- Throughput/iteration optimization of the TX cores beyond what fit and 50 MHz
  timing closure require.
- DE1 TX demo (DE2 is the locked first hardware target).
