## Why

This is the roadmap's **Option B** (`hdl/docs/decoder_roadmap.md` §6 + the
archived `add-fpga-turbo-decoder-de2-demo` proposal): the decoder's **Fmax is
capped at ~15.43 MHz** by the constituent core's **forward α recurrence** — a
single-cycle 8-way **saturating-add → max-normalize → saturate** combinational
feedback cone (~64.8 ns). This cone is intrinsic to the Max-Log-MAP algorithm,
not the M4K rework, and **cannot be naively pipelined** because it is a feedback
recurrence. Today the DE2 decoder demo works around it with **Option A**: a
PLL-derived ~12.5 MHz clock. **Option B** is the algorithmic restructuring —
ACS look-ahead / radix-2 unrolling of the α/β recurrence — that raises Fmax so a
**50 MHz decoder board build** becomes possible without the slow-clock
workaround.

This **touches the bit-exact contract**: restructuring the recurrence (e.g.
combining two trellis steps per cycle via look-ahead) changes the internal
schedule and intermediate widths, so it needs its **own fixed-point reference**
and **golden vectors** that capture the pipelined recurrence, characterized to
prove the decoded output is unchanged vs the existing decoder within the
documented band.

## What Changes

- **Restructure** the constituent decoder's α (and β) forward/backward
  recurrence to break the single-cycle feedback cone — e.g. **ACS look-ahead**
  or **radix-2** (two trellis steps folded into one precomputed-then-selected
  cycle) — raising Fmax above ~15.4 MHz toward a 50 MHz target.
- **Author** a fixed-point **reference** capturing the pipelined recurrence
  schedule + widths, and golden vectors; the existing decoder vectors do NOT
  carry over unchanged.
- **Verify** two-tier: inner cocotb bit-exact vs the new pipelined reference;
  outer characterization vs float confirming the decoded output / BER is
  unchanged within the documented band.
- **Demonstrate** the throughput goal: `turbo_decoder_top` (at the board-demo K)
  **closes timing at 50 MHz** under Quartus II 13.0sp1, removing the need for the
  12.5 MHz PLL workaround.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. The exact look-ahead radix and the pipeline-depth /
latency trade are deferred to when this change is started.

## Capabilities

### New Capabilities

- `fpga-decoder-recurrence-pipelining`: an ACS look-ahead / radix-2
  restructuring of the constituent decoder's α/β recurrence that breaks the
  single-cycle saturating-add→max-norm→saturate feedback cone, raising decoder
  Fmax above ~15.4 MHz toward a 50 MHz board build, bit-exact to a new pipelined
  fixed-point reference (a new bit-exact contract).

## Impact

- Extends `fpga-constituent-decoder` (and transitively `fpga-turbo-decode-loop`
  and `fpga-turbo-decoder-de2-demo`) with a restructured recurrence; changes the
  bit-exact golden-vector contract and removes the Option-A slow-clock
  workaround.
- Depends on the two-tier discipline (cocotb bit-exact + outer characterization)
  and Quartus II 13.0sp1 timing-closure on the Windows host.
- Risk: recurrence restructuring is the hard part — look-ahead precompute grows
  area and the latency/throughput trade must be re-characterized; the bit-exact
  contract change requires a fresh reference (the safety-critical artifact per
  roadmap §1).

## Out of Scope (explicit)

- Exact Log-MAP accuracy (M1 / `add-fpga-decoder-exact-log-map`).
- Sliding-window memory (M2 / `add-fpga-decoder-sliding-window`).
- A new board demo beyond demonstrating 50 MHz timing closure (the existing
  decoder demo can later drop its PLL once this lands).
