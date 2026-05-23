## Why

The DE2 TX-chain demo (`add-fpga-tx-chain-de2-demo`) only fits the Cyclone II
`EP2C35F672C6` because it was **parameterized down to K=40** (`MAXK=64`,
`DMAX=64`, `KW_MAX=256`). Running the real Quartus II 13.0sp1 fit on the
**full-size** chain (`MAXK=6144`, `DMAX=6148`, `KW_MAX=18528`) revealed the
deferred problem the demo recorded:

- **`Total memory bits : 0`.** NONE of the TX buffers inferred as M4K block
  RAM — they all synthesized to LE fabric (registers + decode/mux logic). At
  full `K` that was ~85k logic elements, **2.5× over the EP2C35's 33,216** →
  "Can't fit design in device".
- The EP2C35 has 483,840 RAM bits (105 M4K blocks). The TX chain's buffers
  total only ~55 Kbit (≈12 M4K), so **if** they inferred as M4K the full-`K`
  design would fit with large headroom — the inference rules simply are not
  being met.

The stage-1/stage-2 hardening already made every TX buffer **synchronous-read**
(registered read, one-cycle latency absorbed in the FSMs), which is necessary
but not sufficient: the writes still do not infer M4K.

**Root cause (confirmed empirically on Quartus II 13.0sp1, EP2C35F672C6).** A
reduced test bisected the failure to one structural rule: when the array
**write** statement is nested inside the `if rst = '1' then … else case st …
end case end if` synchronous-reset FSM body, Quartus 13.0sp1 refuses to map the
array to M4K and falls back to registers (`Total memory bits : 0`). Lifting the
identical write to the **top level** of the clocked process — so the
synchronous reset touches only the address/index/control registers, never the
memory body — makes the very same array infer altsyncram / M4K (`Total memory
bits > 0`). All three TX buffers (`turbo_encode_top` `buf`, `rate_matching_top`
`d1/d2/d3buf`, `circular_buffer` `w_bit`/`w_fill`) have their write buried in
exactly this reset-guarded FSM body. The synchronous-read style added earlier
is correct and is kept; only the write placement (and a couple of secondary
template details below) must change.

This change makes those TX-chain memories **M4K-inferable** so a full-capacity
(`K` up to 6144) build fits the DE2, while staying **bit-exact** to the
committed golden vectors. It is the TX-side analog of the decoder roadmap's
**M2** (sliding-window / BRAM) maturation item; the decoder α-RAM / LLR
memories are a **larger, separate** follow-on (see Out of Scope).

## What Changes

- **Restructure each TX memory to hit the Quartus M4K inference template**,
  bit-exact, by moving the array read/write out of the reset-guarded FSM body
  into a dedicated unconditional memory process (or top-level clocked block),
  with the FSM driving only the address / write-enable / control signals:
  - `turbo_encode_top.vhdl` `buf` (decl ~93–94; write ~189 inside `S_LOAD`;
    reads ~173–174). One write port + two read ports (`buf(didx)`,
    `buf(pi_idx)`) → two simple-dual-port M4K copies (or an explicit
    dual-read primitive), reads registered (already are), write lifted out of
    the `if rst … else case` body.
  - `rate_matching_top.vhdl` `d1/d2/d3buf` (decl ~86–87; writes ~204–206 inside
    `S_LOADD`; reads ~171–173). Each a 1W/1R simple-dual-port M4K; writes lifted
    out of the reset-guarded `case`.
  - `circular_buffer.vhdl` `w_bit`/`w_fill` (decl ~58–60; writes ~139–144 inside
    `S_LOAD`; sync read ~110–111). Each a 1W/1R simple-dual-port M4K; the six
    `S_LOAD` writes (`w[cidx]`, `w[K_Pi+2·cidx]`, `w[K_Pi+2·cidx+1]`) become a
    sequenced/expanded single-write-port schedule that does not defeat the
    one-write-port template, lifted out of the reset-guarded `case`.
- **Confirm the secondary template details** that the reduced test showed are
  *tolerated* but must be preserved: the array power-up init `:= (others =>
  '0')` (kept; maps to a `.mif`/no-clear init), no asynchronous clear on the
  array contents, and a defined read-during-write mode (`OLD_DATA` /
  don't-care, never reading the just-written address in the same cycle on the
  bit-exact path).
- **Add `ramstyle = "M4K"` synthesis attributes** to the array signals as an
  explicit belt-and-suspenders so inference is not silently lost on a future
  edit; if any memory still resists inference under 13.0sp1, fall back to an
  explicit `altsyncram` instantiation behind the same port behaviour (open
  question — see design).
- **Remove the per-demo parameterize-down workaround** as the route to fit:
  the board wrapper may still override depths, but the **full-`K` build**
  (`MAXK=6144`/`DMAX=6148`/`KW_MAX=18528`, or a documented intermediate) must
  fit the EP2C35 **because the memories infer M4K**, not because they are tiny.
- **Bit-exactness is preserved.** The existing cocotb lanes (`circular_buffer`,
  `rate_matching_top`, `turbo_encode_top`, `tx_chain_top`) stay green and the
  committed golden vectors (`circular_buffer.csv`, `rate_matching.csv`,
  `turbo_encoder.csv`, `tx_chain.csv`) are **unchanged**. Any read/write
  scheduling shift is absorbed inside the owning FSM exactly as the prior
  sync-read hardening did.

## Capabilities

### New Capabilities

- **`fpga-block-ram-inference`** — a synthesis-oracle capability: the TX-chain
  memories SHALL infer as Cyclone II M4K block RAM under Quartus II 13.0sp1, so
  that a **full-`K` (up to 6144)** `tx_chain_top` build fits the EP2C35 and
  closes 50 MHz timing, validated by a **two-tier gate** — the cocotb lane
  (functional bit-exactness) **and** the Quartus fit report (the synthesis
  oracle: `Total memory bits > 0` / `M4K > 0`, device fits, `Fmax ≥ 50 MHz`).
  This is genuinely new: prior fpga-* specs verify only functional
  bit-exactness in simulation; nothing yet asserts a synthesis-resource /
  block-RAM-inference property against the real fitter.

### Modified Capabilities

- **`fpga-circular-buffer`** — add a requirement that `w_bit`/`w_fill` infer M4K
  (write lifted out of the reset-guarded FSM; sync read; defined RDW), bit-exact
  to `circular_buffer(...)` and the existing cocotb lane.
- **`fpga-rate-matching`** — add a requirement that `d1/d2/d3buf` infer M4K
  simple-dual-port, bit-exact to `rate_matching(...)` / `tx_chain` and their
  lanes.
- **`fpga-turbo-encoder`** — add a requirement that the encoder `buf` infers M4K
  (two simple-dual-port copies for the natural/interleaved read taps), bit-exact
  to `turbo_encode_top` / `tx_chain` and their lanes.

**Decision — new capability *and* modify the three cores (not modify-only).**
The per-core deltas pin the inference fix where the RTL lives (each core stays
self-describing). But "the memories must infer M4K and the full-`K` design must
fit + close timing, proven by the Quartus fit report" is a **cross-cutting
synthesis-oracle property** that no single core spec owns, and it introduces a
**new verification gate** (the fit report alongside the cocotb gate). That
deserves its own capability rather than being smeared across three core specs
or overloaded onto `fpga-tx-chain-de2-demo` (whose requirements are about the
on-chip ROM + self-check board behaviour, not block-RAM inference).
`fpga-board-bringup` is **not** modified (it is crc8/switch-smoke specific).

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, `.m` edits
  land here. This is the proposal; implementation follows the staged `tasks.md`.
- When implemented: `hdl/rtl/circular_buffer.vhdl`,
  `hdl/rtl/rate_matching_top.vhdl`, `hdl/rtl/turbo_encode_top.vhdl` are
  restructured for M4K inference (bit-exact preserved). The board `.qsf` may
  add the full-`K` build target; the demo wrapper's small overrides may remain
  for the K=40 board run but are no longer the fit mechanism.
- The `tx_chain_top` core, `qpp_interleaver`, and `subblock_interleaver` need no
  change (already divider-free; 0 multipliers; ~55 Kbit ≈ 12 of 105 M4K — a
  trivial fit *once the memories infer*).
- Depends on Quartus II 13.0sp1 on the existing Windows host; the fit-report
  gate is a local/manual synthesis step (not CI), exactly as the prior demo's
  fit was.
- Requires no physical DE2 hardware: the cocotb gate and the Quartus fit /
  timing report are both verifiable without a board. (An optional on-board
  full-`K` run is a separate follow-on, not this change.)

## Out of Scope (explicit — separate / later increments)

- **Decoder α-RAM and LLR memories** (`constituent_decoder`,
  `turbo_decoder_top`, `turbo_decoder_term_top`) — a **much larger** follow-on
  tied to the decoder roadmap's **M2 sliding-window + BRAM** item. The
  full-block α store (`8·(K+3)` words) does not even fit on-chip past `K≈2700`
  and needs the sliding-window algorithm change first. This change is **TX-side
  only**.
- The **algorithmic** sliding-window rework itself (that is M2, separate).
- Any change to the divider-free arithmetic already landed in stage 1 (the
  `q`/`pos` recurrences stay as committed; this change touches only memory
  *inference*, not arithmetic).
- UART / host link; on-board large-`K` program-and-observe; DE1.
- Fixed-point / width changes (the TX chain is bit/integer logic).
