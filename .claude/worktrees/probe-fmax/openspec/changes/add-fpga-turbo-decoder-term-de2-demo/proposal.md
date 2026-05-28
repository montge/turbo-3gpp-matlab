## Why

The K=512 iterative turbo decoder (`turbo_decoder_top`, P2) already runs
self-checked on a real DE2 (archived `add-fpga-turbo-decoder-de2-demo` +
`add-fpga-lcd-status-display`: LED/7-seg + 16×2 LCD status). The **P3** decoder,
`turbo_decoder_term_top` — the full `turbo_decoder.m` behaviour with **CRC-aided
early termination**, **HARQ accumulation**, and **filler (NaN→+inf)** handling —
is sim-verified (10 frames, per `decoder_roadmap.md` §6) but has **never run on
hardware**. This change puts P3 on the board so the early-termination /
filler / HARQ path is exercised on real silicon, reusing the existing harness.

P3 brings a real **fit cost**: CRC-aided early termination uses the turbo CRC24
check, whose two **6144×24 CRC matrices** add ~**65 M4K (fixed)** on top of the
decoder loop. Against the K=512 decoder demo's current 54 M4K (57/105), that may
**exceed the EP2C35's 105 M4K**. This is flagged up front: the demo may need a
**smaller K** and/or **CRC-matrix optimization** (e.g. on-the-fly LFSR CRC vs
stored matrices) to fit. The fit study is part of the change.

## What Changes

- **Add** a DE2 board demo for `turbo_decoder_term_top`
  (`turbo_decoder_term_de2_top.vhdl`) reusing the existing `tx_chain_de2` /
  `turbo_decoder_de2` harness pattern: on-chip golden-LLR ROM, KEY0 restart,
  LED + 7-seg verdict, and the shared `hd44780_lcd` status (label line +
  RUNNING/heartbeat → PASS/FAIL), on the same PLL-derived ~12.5 MHz decoder
  clock.
- **Self-check** the decoded bits (and the early-termination outcome) against
  the committed P3 golden vector, bit-for-bit, with no host link.
- **Fit study** under Quartus II 13.0sp1: characterize the CRC-matrix M4K cost;
  if `turbo_decoder_term_top` at K=512 does not fit, reduce K and/or optimize
  the CRC representation, and record the chosen demo K and the M4K breakdown.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. The chosen demo K and any CRC-matrix optimization are
deferred to when this change is started.

## Capabilities

### New Capabilities

- `fpga-turbo-decoder-term-de2-demo`: a DE2 board demo of `turbo_decoder_term_top`
  (CRC early-termination + HARQ + filler) reusing the existing decoder-demo
  harness and LCD status pattern, self-checking against the P3 golden vector,
  with a documented CRC-matrix M4K fit study selecting the demo K.

## Impact

- Builds on `fpga-turbo-decoder-termination` (the P3 core),
  `fpga-turbo-decoder-de2-demo` (the harness), and `fpga-lcd-status-display`
  (the status pattern), all reused; the verified cores stay UNMODIFIED.
- Depends on Quartus II 13.0sp1 on the Windows host; the GHDL self-check lane +
  the Quartus fit/timing are verifiable without a board; on-board
  program-and-observe is a hardware-gated manual step.
- Risk: the two 6144×24 CRC matrices add ~65 M4K (fixed) — at K=512 this may
  exceed the EP2C35's 105 M4K, so a smaller K or CRC-matrix optimization may be
  required; the fit study resolves this and is the main open question.

## Out of Scope (explicit)

- Any change to the verified cores (`turbo_decoder_term_top`,
  `turbo_decoder_top`) or to the golden vectors / verdict logic.
- A DE1 variant or any host link.
- Decoder accuracy/memory maturation (M1/M2, separate changes).
