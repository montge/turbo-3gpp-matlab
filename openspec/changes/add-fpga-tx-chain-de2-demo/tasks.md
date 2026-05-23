## 1. Harden `circular_buffer` (divider-free + synchronous-read RAM)

- [x] 1.1 Replace `q = ⌈N_cb/(8·R_TC)⌉` (~line 121) with a divider-free
  subtract-/shift recurrence (compare-and-subtract or accumulate-and-count over
  the constant `8·R_TC = K_Pi/4`), in a dedicated per-block compute state.
- [x] 1.2 Replace `pos = (k_0+j) mod N_cb` (~line 134) with a running `pos`
  register that increments and conditionally subtracts `N_cb`; initialize
  `pos = k_0 mod N_cb` once at block start via a bounded subtract recurrence.
- [x] 1.3 Bound `jj` to `integer range 0 to 8*KW_MAX` (~line 54) so the counter
  is sized for synthesis.
- [x] 1.4 Make `w_bit`/`w_fill` (~lines 37–39, 136) synchronous-read: register
  the read index and absorb the one-cycle read latency inside `S_READ` so the
  emitted `(e_bit, out_valid, last)` stream is unchanged cycle-for-cycle.
- [x] 1.5 Re-run the `circular_buffer` cocotb/GHDL lane (`hdl/sim/circular_buffer/`)
  — it MUST pass bit-for-bit with `hdl/vectors/circular_buffer.csv` unchanged
  (all `rv_idx∈{0,1,2,3}`, both `I_LBRM`, the buffer-wrap `E`). Gate: no edit is
  accepted until this is green and the committed vector file is byte-identical.

## 2. Synchronous-read the rate-match and encoder buffers (bit-exact)

- [x] 2.1 `rate_matching_top.vhdl`: make `d1/d2/d3buf` (~lines 105–107)
  synchronous-read (registered address); realign the `v1b/v2b/v3b` →
  `circular_buffer` `v_valid` timing so the loaded `v` columns are identical.
- [x] 2.2 `turbo_encode_top.vhdl`: make `buf` (~lines 129–130) a synchronous-read
  dual-port (true-dual-port or two single-port copies) M4K; realign
  `te_cbit`/`te_cpbit` so `turbo_encoder` samples the same bit pair on the same
  beat. Sub-cores (`qpp_rom`, `qpp_interleaver`, `turbo_encoder`,
  `subblock_interleaver`, `rsc_constituent_encoder`) stay unmodified.
- [x] 2.3 Re-run the `turbo_encode_top`, `rate_matching_top`, and `tx_chain_top`
  cocotb/GHDL lanes — all MUST stay green bit-for-bit with their committed
  golden vectors (`turbo_encoder.csv`, `rate_matching.csv`, `tx_chain.csv`)
  unchanged. Gate: this is the proof the latency-absorption preserved behavior.

## 3. DE2 board demo — wrapper + on-chip golden ROM + self-check (crc8 pattern)

- [ ] 3.1 Choose the demo `K` (default `K=40` from `hdl/vectors/tx_chain.csv`:
  `N_ref=0, I_LBRM=0, rv=0, E=400`); record the exact `(K, N_ref, I_LBRM, rv,
  E, c, e)` row used.
- [ ] 3.2 Add an on-chip golden-vector ROM under `hdl/boards/de2/` holding that
  row's `K`/params, the `K` input bits `c`, and the `E` expected output bits
  `e` as VHDL constants (board-presentation data, not under `hdl/rtl/`).
- [ ] 3.3 Add a self-check FSM that pulses `in_start` with `K`/params, streams
  `c` into the core, captures each `out_valid` `e_bit`, compares to the expected
  `e` bit at the same index, and checks the `last` arrives at bit `E−1`;
  latches a sticky pass/fail.
- [ ] 3.4 Add the DE2 board wrapper (`tx_chain_de2_top.vhdl`) instantiating the
  hardened `tx_chain_top` **unmodified**, wiring `CLOCK_50` and a KEY start, and
  driving LED = pass / LED = fail / LED = running plus a 7-seg status code via
  the shared `hdl/boards/hex7seg.vhdl`.
- [ ] 3.5 Add the Quartus project + constraints under `hdl/boards/de2/`: `.qpf`,
  `.qsf` (device `EP2C35F672C6`, reuse the verified crc8 SW/LEDR/HEX pins, add
  `CLOCK_50`=`PIN_N2` and the KEY pin, all source paths incl. the hardened RTL),
  and `.sdc` (`create_clock` 50 MHz on `CLOCK_50`, `derive_clock_uncertainty`,
  `set_false_path` on the async KEY input / LED+HEX outputs).

## 4. Synthesis fit + timing closure (no board required)

- [ ] 4.1 Compile the DE2 TX-demo project under Quartus II 13.0sp1 — Full
  Compilation, 0 errors, no unsupported-family / unconstrained-device errors.
- [ ] 4.2 Record the fit: logic elements, M4K block count (expect ~12 of 105),
  and DSP/multiplier count (expect 0).
- [ ] 4.3 Confirm TimeQuest closes setup and hold for the 50 MHz `CLOCK_50`
  domain (Fmax ≥ 50 MHz reported); no unconstrained-path warnings beyond the
  intentionally false-pathed async I/O.
- [ ] 4.4 Confirm `git status` after compile shows only intended sources (no
  `db/`, `output_files/`, `*.sof`, report artifacts) — `.gitignore` patterns
  cover the new project.

## 5. On-board program-and-observe (hardware-gated)

- [ ] 5.1 Program the DE2 (`quartus_pgm -c USB-Blaster -m jtag -o
  "p;output_files/tx_chain_de2.sof"`, 13.0sp1) — configuration succeeds.
- [ ] 5.2 Trigger the self-check; confirm the **pass** LED lights and the 7-seg
  shows the pass code — i.e. the on-board hardened `tx_chain_top` reproduces the
  committed `tx_chain` golden vector for the chosen `K` bit-for-bit. Record the
  board, cable, device JTAG ID, and the observed pass/fail.

## 6. Documentation + validation

- [ ] 6.1 Add an `hdl/boards/de2/` README section (or sibling README) for the TX
  demo: the chosen `K`/vector row, build command, program command, what the
  LEDs/7-seg mean, and how to read pass/fail — repeatable per the crc8 pattern.
- [ ] 6.2 Note in the relevant RTL headers that the divider-free / sync-read
  hardening landed (the `circular_buffer` header follow-on is now done) and that
  bit-exactness is preserved (cocotb gate green, vectors unchanged).
- [ ] 6.3 Run `npx openspec validate add-fpga-tx-chain-de2-demo --strict` and
  `npx openspec validate --all --strict` — both pass, no regression.
- [ ] 6.4 Re-run the full HDL cocotb suite (`circular_buffer`,
  `rate_matching_top`, `turbo_encode_top`, `tx_chain_top` at minimum) and the
  Octave software suite — confirm no sim/software regression and all golden
  vectors unchanged.
