## Context

The TX chain is sim-complete and bit-exact in GHDL/cocotb:

```
tx_chain_top  =  turbo_encode_top  →  rate_matching_top
                 (qpp_rom + qpp_         (3× subblock_interleaver
                  interleaver +           + circular_buffer)
                  turbo_encoder)
```

A just-completed synthesis-readiness audit of the RTL (verified against the
sources) found:

- **`circular_buffer.vhdl` is the main blocker.** It uses, in `S_COMPUTE`/
  `S_READ`:
  - a non-power-of-2 integer divide `q := (ncb + 8*rtc - 1) / (8*rtc)`
    (~line 121) — `⌈N_cb/(8·R_TC)⌉`;
  - a non-power-of-2 modulo `pos := (k0 + jj) mod N_cb` (~line 134);
  - two `KW_MAX = 18528`-element arrays `w_bit`/`w_fill` (~lines 37–39) read
    **combinationally** (async) in `S_READ` (~line 136);
  - an effectively unbounded loop index `jj : integer` (~line 54), only capped
    by a `> 8*KW_MAX` safety test.
  The file header (~lines 11–13) already states "a divider-free synthesis
  reformulation … [is a] documented follow-on."
- **`rate_matching_top.vhdl`** holds `d1buf`/`d2buf`/`d3buf` (`DMAX = 6148`)
  read **async** by the sub-block interleaver index (~lines 105–107).
- **`turbo_encode_top.vhdl`** holds `buf` (`MAXK = 6144`) with **two async
  read ports** — `buf(didx)` and `buf(pi_idx)` (~lines 129–130) — the
  natural- and interleaved-order taps.
- `qpp_interleaver` / `subblock_interleaver` are already divider-free (the QPP
  recurrence and the column/row index math use only adds/compares and
  power-of-2 ops) → **no change**.
- The TX chain uses **0 multipliers** and ~55 Kbit of memory ≈ **12 of the 105
  M4K** blocks on `EP2C35F672C6` → fits with large headroom once the memories
  infer as M4K rather than registers/LUT-RAM.

Async-read arrays this large will not infer M4K (M4K read is **synchronous
only**) and synthesize to enormous distributed RAM / register banks — the
direct cause of poor or failing fit. The dividers further cost LUTs/Fmax and
are the documented blocker.

## Goals / Non-Goals

**Goals:**

- Make `circular_buffer`, `rate_matching_top`, and `turbo_encode_top`
  synthesizable for Cyclone II: divider-free arithmetic and synchronous-read,
  M4K-inferable memories.
- Keep every change **bit-exact**: the four cocotb lanes stay green and the
  committed golden vectors are unchanged.
- Demonstrate `tx_chain_top` on a real DE2 at a fixed small `K` using the
  proven crc8 harness pattern: on-chip golden ROM + self-check FSM + LED/7-seg.
- Report fit (LE / M4K) and timing closure (Fmax ≥ 50 MHz) under 13.0sp1.

**Non-Goals:**

- No decoder work, no sliding-window, no UART, no large-`K` board run, no DE1
  TX demo (all out of scope, see proposal).
- No fixed-point/width changes — the TX chain is bit/integer logic; widths are
  unchanged.
- No CI synthesis lane; board synthesis/program stays local/manual (as crc8).
- No algorithmic change to the TX chain — only the *implementation* of the
  arithmetic and memories changes; the standard-defined behavior is identical.

## Decisions

### 1. Divider-free `circular_buffer`

- **`q = ⌈N_cb/(8·R_TC)⌉` → subtract-/shift recurrence.** `R_TC = K_Pi/32` and
  `K_Pi` is always a multiple of 32, so `8·R_TC = K_Pi/4` is exact and a known
  per-block constant. Compute `q` by an iterative *compare-and-subtract* over a
  small number of steps (a non-restoring/long-division style loop bounded by
  `q ≤ ⌈18528/8⌉`), or accumulate `8·R_TC` until it reaches/exceeds `N_cb`,
  counting the steps — both divider-free, both producing the exact ceil. The
  loop runs once per block in a dedicated compute state, so latency is
  irrelevant to throughput.
- **`pos = (k_0+j) mod N_cb` → running index with conditional subtract.** Hold
  a register `pos`; each read step `pos ← pos + 1; if pos = N_cb then pos ← 0`.
  Initialize `pos` to `k_0 mod N_cb` computed once at block start by the same
  compare-and-subtract recurrence (`k_0 < 2·N_cb`-ish, so a bounded subtract).
  This removes the per-cycle `mod` entirely; the standard's circular read is a
  pure increment-with-wrap.
- **Bound `jj`.** Declare `jj : integer range 0 to 8*KW_MAX` (matching the
  existing safety cap) so synthesis sizes the counter; functionally unchanged.
- These are exactly the reformulations the file header pre-authorized. The
  golden behavior — which `w` positions are read, in what order, skipping
  fillers — is identical, so the `circular_buffer` cocotb lane stays bit-exact.

### 2. Synchronous-read BRAM inference

M4K requires the read **address** to be registered (read data appears one
cycle later). For each memory:

- **`circular_buffer` `w_bit`/`w_fill`:** register the read index `pos`; the
  `S_READ` FSM consumes the registered output one cycle later. Absorb the
  one-cycle read latency inside `S_READ` (e.g. a pipeline/lookahead beat) so
  the emitted `(e_bit, out_valid, last)` stream is identical cycle-for-cycle to
  today's. Write port (`S_LOAD`) is already synchronous.
- **`rate_matching_top` `d1/d2/d3buf`:** the async reads
  `d1buf(to_integer(s0_idx))` etc. become registered-address synchronous reads;
  the `v1b/v2b/v3b` taps that feed `circular_buffer` shift by one cycle, so the
  `circular_buffer` `v_valid` timing is realigned in the rate-match FSM to keep
  the loaded `v` columns identical.
- **`turbo_encode_top` `buf`:** the dual async read (`buf(didx)`,
  `buf(pi_idx)`) becomes a **true-dual-port** (or two single-port copies)
  synchronous-read M4K; the registered read addresses delay `te_cbit`/
  `te_cpbit` by one cycle, so the encoder feed (`S_ENC_DATA`) is realigned so
  `turbo_encoder` samples the same bit pair on the same relative beat.
- **Latency-absorption is the core risk-control discipline.** Any added read
  latency MUST be hidden inside the owning FSM so the cocotb-verified output
  streams (and the committed vectors) are unchanged — the cocotb gate is the
  proof. No change to `qpp_rom`/`qpp_interleaver`/`subblock_interleaver`/
  `turbo_encoder`/`rsc_constituent_encoder` (sub-cores reused unmodified).

### 3. Board harness (crc8 pattern, clocked + self-checking)

Reuse the archived crc8 DE2 harness shape (`hdl/boards/de2/crc8_de2_top.vhdl`,
`crc8_de2.qsf`, `crc8_de2.sdc`, shared `hdl/boards/hex7seg.vhdl`):

- **On-chip golden-vector ROM.** One row of `hdl/vectors/tx_chain.csv` for a
  chosen small `K` (default `K=40`: it has `N_ref=0, I_LBRM=0, rv=0, E=400`,
  so `c` is 40 bits and `e` is 400 bits — both small constant arrays). The ROM
  holds `K`, the params `(N_ref, I_LBRM, rv, E)`, the `K` input bits `c`, and
  the `E` expected output bits `e`, as VHDL constants under `hdl/boards/de2/`
  (board-presentation data, not in `hdl/rtl/`).
- **Self-check FSM.** On reset/KEY-press: pulse `in_start` with `K`/params,
  stream the `K` `c` bits into the core on `c_in_valid`, then capture each
  `out_valid` `e_bit` and compare to the expected `e` bit at the same index;
  assert a sticky `fail` if any bit mismatches or if the output length / `last`
  position differs from `E`.
- **Outputs (LED + 7-seg).** A single LED = **pass** (all `E` bits matched and
  `last` arrived at bit `E−1`), a second LED = **fail/mismatch**, a third =
  **done/running**; the 7-seg shows a small status code (e.g. `P`=pass,
  `F`=fail, `-`=running) via `hex7seg`. No UART, no screen.
- **Clocking.** Driven by `CLOCK_50` (the chain is fully synchronous after
  hardening). The `.sdc` declares a real 50 MHz clock on `CLOCK_50`
  (`create_clock`) plus `derive_clock_uncertainty`, and `set_false_path` on the
  async KEY input / LED+HEX outputs — unlike the crc8 `.sdc`, which had no
  functional clock.
- **Pins/device.** Reuse the crc8 `EP2C35F672C6` device string and the verified
  DE2 SW/LEDR/HEX pin table; add `CLOCK_50` (DE2 `PIN_N2`) and one KEY pin for
  start/reset. The lead-free `N` suffix on the board marking is packaging-only
  — the Quartus device string stays `EP2C35F672C6`.
- **Wrapper instantiates the hardened core unmodified** (same discipline as
  crc8): all demo logic (ROM, FSM, hex decode) lives under `hdl/boards/de2/`;
  `hdl/rtl/tx_chain_top.vhdl` is wired in as a component, not edited by the
  board layer.

### 4. Fixed-point / widths unchanged

The TX chain is bit/integer logic. No Q-format, no LLR, no width retuning.
Hardening changes arithmetic *implementation* (divide→recurrence) and memory
*read style* (async→sync), never the values or bit-widths.

## Risks / Trade-offs

- **Bit-exact preservation of the divider rewrite = top risk.** The
  compare-and-subtract `q` and the running-`pos` wrap must reproduce
  `⌈N_cb/(8·R_TC)⌉` and `(k_0+j) mod N_cb` exactly for every golden parameter
  set. *Mitigation:* the `circular_buffer` cocotb lane (all `rv_idx∈{0,1,2,3}`,
  both `I_LBRM`, buffer-wrap `E`) is the gate; the rewrite is not accepted until
  it passes bit-for-bit with the committed vectors unchanged.
- **Latency-shift bugs from sync-read.** Registering read addresses delays data
  by a cycle in three FSMs; a missed realignment corrupts the stream.
  *Mitigation:* same cocotb gate at each stage (Stage 1 guards
  `circular_buffer`; Stage 2 guards rate-match + encode + the full
  `tx_chain_top` lane) before any board work.
- **M4K inference under 13.0sp1.** The synchronous-read pattern must actually
  infer M4K (not LUT-RAM). *Mitigation:* the fit report (LE/M4K counts) is a
  task deliverable; expectation ~12 M4K, 0 multipliers.
- **Timing closure at 50 MHz.** The compare-and-subtract `q` loop and any wide
  comparators must close at 20 ns. *Mitigation:* the `q`/`pos`-init recurrences
  run in dedicated per-block states (not the critical streaming path); the
  streaming path is increment-with-wrap + a 1-bit RAM read. Fmax is a reported
  deliverable.
- **On-chip ROM size.** `K=40` keeps the expected `e` array at 400 bits — well
  within M4K/LUT. Larger `K` would grow the ROM; the demo deliberately fixes
  small `K`.

## Open Questions

- **Which `K` for the demo?** Default `K=40` (smallest committed `tx_chain`
  row, 40-bit input / 400-bit expected output). Confirm, or pick another small
  committed row (e.g. `K=512`).
- **Full `tx_chain_top`, or `turbo_encode_top` only first?** The locked
  decision is the full chain; a fallback first step could demo only
  `turbo_encode_top` (no rate-match) if fit/timing surprises arise. Confirm
  whether a staged encoder-only board bring-up is wanted as a safety net.
- **7-seg richness.** Just pass/fail/running status, or also show
  throughput/cycle-count or a small output signature? Default: status only
  (matches the crc8 simplicity).
- **Resource/timing margin to advertise.** Expectation ~12/105 M4K, 0 DSP,
  Fmax ≫ 50 MHz — confirm whether a specific margin target should be a gate or
  just reported.
- **Start control.** Free-run-on-power-up vs KEY-triggered re-run. Default:
  KEY-triggered (debounce-free single-shot edge), sticky pass/fail latch.
