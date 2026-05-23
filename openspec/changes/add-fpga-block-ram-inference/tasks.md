## 1. `circular_buffer` `w_bit`/`w_fill` → M4K-inferable (bit-exact)

- [x] 1.1 Lift the `w_bit`/`w_fill` writes out of the `if rst='1' … else case st
  … when S_LOAD` body (~lines 113–144) into a dedicated unconditional clocked
  memory process; the FSM drives only write-address / write-enable / write-data
  and the registered read address `rd_addr`, never the arrays directly.
- [x] 1.2 Re-sequence the three-writes-per-`v`-column load (`w[cidx]`,
  `w[K_Pi+2·cidx]`, `w[K_Pi+2·cidx+1]`, ~lines 139–144) into a single-write-port
  schedule (sub-beats per column, or a two-bank even/odd-address split with one
  write/bank/cycle) so each array is a clean 1W port; the loaded `w` contents
  before the read begins MUST be identical.
  (Done via THREE-bank split: `w_sys`/`w_ev`/`w_od`, each K_Pi-deep, written by
  one port at column `cidx`; the circular read decodes pos→bank.)
- [x] 1.3 Keep the synchronous read (`rd_addr` → `rd_bit`/`rd_fill`, ~lines
  110–111) and the `S_PRIME` latency-absorb beat unchanged; ensure the load and
  read phases stay disjoint (no same-address read-during-write on the bit-exact
  path). (Per-bank reads registered in the mem process; `rd_bit`/`rd_fill` are a
  registered-tag bank mux with identical one-cycle latency; load fully precedes
  read so RDW=OLD_DATA is harmless.)
- [x] 1.4 Add `ramstyle = "M4K"` attributes to `w_bit`/`w_fill`; keep the
  `:= (others => '0')` init; confirm no async clear on the array body.
  (Attributes on all six bank arrays; init kept; no async clear — confirmed
  `ADDRESS_ACLR = NONE` in the inferred altsyncram.)
- [x] 1.5 **Inner gate:** re-run the `circular_buffer` cocotb/GHDL lane
  (`hdl/sim/circular_buffer/`) — MUST pass bit-for-bit with
  `hdl/vectors/circular_buffer.csv` byte-identical (all `rv_idx∈{0,1,2,3}`, both
  `I_LBRM`, the wrap `E`). No edit accepted until green + vectors unchanged.
  (PASS=2/2 bit-exact; `scripts/run_all_hdl_lanes.sh` 14/14 PASS; vectors
  byte-identical — `git diff hdl/vectors/` empty.)
- [x] 1.6 **Outer gate (per-memory):** synthesize `circular_buffer` at full
  `KW_MAX=18528` under Quartus II 13.0sp1; confirm the report shows the
  `w_bit`/`w_fill` arrays inferred (`Total memory bits > 0`, M4K segments), not
  LE registers. Record the count. (Fall back to explicit `altsyncram` only if it
  still resists — design Decision 4.)
  (BEFORE: memory bits 0, 115,074 LE. AFTER: 49,152 memory bits / 12 M4K,
  584 LE, fits EP2C35, Fmax 96.48 MHz, setup +9.635 ns / hold +0.391 ns.
  Inference clean — no altsyncram fallback needed.)

## 2. `rate_matching_top` `d1/d2/d3buf` → M4K-inferable (bit-exact)

- [x] 2.1 Lift the `d1/d2/d3buf` writes out of the `if rst … else case st …
  when S_LOADD` body (~lines 179–212) into a top-level memory process; the FSM
  drives only the write address (`widx`) / write-enable / write-data and the
  read addresses (`s0/s1/s2_idx`).
- [x] 2.2 Keep each buffer a 1W/1R simple-dual-port (registered reads
  `rd1/rd2/rd3`, ~lines 171–173) with its pipelined filler/valid taps so the
  `circular_buffer` `v` columns load unchanged; add `ramstyle = "M4K"`.
- [x] 2.3 **Inner gate:** re-run `rate_matching_top` (and the downstream
  `tx_chain_top`) cocotb/GHDL lanes — MUST stay bit-for-bit with
  `hdl/vectors/rate_matching.csv` and `tx_chain.csv` byte-identical.
- [x] 2.4 **Outer gate (per-memory):** synthesize `rate_matching_top` at full
  `DMAX=6148`/`KW_MAX=18528`; confirm `d1/d2/d3buf` infer M4K (`memory bits > 0`).
  Record the count. (Quartus II 13.0sp1, EP2C35F672C6: each `d*buf` inferred as
  altsyncram Simple-Dual-Port, 8192 bits; Total memory bits 0 → 24,576; M4Ks
  0 → 6; LE 110,000 → 79,023. Isolated harness; device fit/Fmax = full-chain
  gate task 4 once sibling stages land.)

## 3. `turbo_encode_top` `buf` → M4K-inferable (bit-exact)

- [x] 3.1 Split `buf` into two simple-dual-port copies (`buf_a` read by `didx`,
  `buf_b` read by `pi_idx`) written identically, so each is a clean 1W/1R M4K
  (1W+2R cannot share one M4K); reads already registered into
  `cbit_r`/`cpbit_r`.
- [x] 3.2 Lift both copies' writes out of the `if rst … else case st … when
  S_LOAD` body into a top-level (unconditional) memory process; FSM drives only
  write-addr (`widx`) / we (`buf_we`) / data (`buf_wd`) and the read addresses;
  kept the `S_ENC_PRIME` prefetch beat. Added `ramstyle = "M4K"`.
- [x] 3.3 **Inner gate:** re-ran `turbo_encode_top` (and `tx_chain_top`)
  cocotb/GHDL lanes — PASS bit-for-bit; `hdl/vectors/turbo_encoder.csv` and
  `tx_chain.csv` byte-identical (`git status` clean for vectors); full suite
  14/14 lanes PASS.
- [x] 3.4 **Outer gate (per-memory):** synthesized `turbo_encode_top` at full
  `MAXK=6144` (Quartus II 13.0sp1, EP2C35F672C6). Both copies infer altsyncram
  simple-dual-port M4K. Before: `Total memory bits 0`, 15,619 LE, Fmax 71.51 MHz.
  After: `Total memory bits 16,384`, **4 M4K** (2 per copy), 744 LE, Fmax
  117.38 MHz (setup +15.575 ns / hold +0.215 ns — 50 MHz closes). Dual-copy
  doubled M4K (2→4) as expected; trivial vs 105 available.

## 4. Full-`K` `tx_chain_top` fit + timing (the synthesis oracle)

- [ ] 4.1 Build a **full-`K`** `tx_chain_top` Quartus project (target
  `MAXK=6144`/`DMAX=6148`/`KW_MAX=18528`, or the documented intermediate) under
  Quartus II 13.0sp1, `EP2C35F672C6`, VHDL_2008 — Full Compilation, 0 errors.
- [ ] 4.2 **Assert the fit-report oracle:** `Total memory bits > 0` and inferred
  **M4K > 0** (expectation ≈ 12 M4K / ~55 Kbit of 105 M4K / 483,840 bits);
  device **fits** (LE ≪ 33,216 — the buffers are no longer LE register banks);
  DSP/multipliers = 0. Record LE / M4K / memory-bit / register counts. This is
  the deliverable that proves the inference fix (contrast: the K=40 demo's
  `M4K = 0`).
- [ ] 4.3 Confirm TimeQuest closes setup and hold for the 50 MHz `CLOCK_50`
  domain (**`Fmax ≥ 50 MHz`**, positive slacks); no unconstrained-path warnings
  beyond intentionally false-pathed async I/O. Record `Fmax` / slacks.
- [ ] 4.4 Confirm `git status` after compile shows only intended sources (no
  `db/`, `output_files/`, `*.sof`, report artifacts) — `.gitignore` covers them.

## 5. Documentation + validation

- [ ] 5.1 Update the RTL headers of `circular_buffer.vhdl`,
  `rate_matching_top.vhdl`, `turbo_encode_top.vhdl` to record that the M4K
  block-RAM inference rework landed (write lifted out of the reset-guarded FSM;
  `ramstyle = "M4K"`), that bit-exactness is preserved (cocotb gate green,
  vectors unchanged), and the full-`K` fit numbers.
- [ ] 5.2 Add an `hdl/boards/de2/` (or `hdl/docs/`) note recording the full-`K`
  fit report (LE / M4K / Fmax) and contrasting it with the prior K=40 demo's
  `M4K = 0` parameterized-down fit — the before/after that demonstrates the fix.
- [ ] 5.3 Re-run the full HDL cocotb suite and the Octave software suite —
  confirm no sim/software regression and all golden vectors byte-identical.
- [ ] 5.4 Run `npx openspec validate add-fpga-block-ram-inference --strict` and
  `npx openspec validate --all --strict` — both pass, no regression.
