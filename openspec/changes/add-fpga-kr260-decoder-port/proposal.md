## Why

The LTE turbo codec (TX + RX) is fully verified in simulation (102/102 Octave +
the cocotb/GHDL bit-exact lanes) and the decoder is hardware-confirmed on the
**Altera DE2** (Cyclone II, now running K=512 at 25 MHz, bit-exact). The user
has acquired a **second board — the AMD/Xilinx KR260** (Kria K26 SOM
`SMK-K26-XCL2G`, silicon **XCK26-SFVC784-2LV**, Zynq UltraScale+ MPSoC). Moving
the decoder there:

- **Validates the cores are board-portable** beyond the Altera fabric — the
  verified VHDL (`constituent_decoder`, `turbo_decoder_top`, the QPP ROM/
  interleaver) is generic `--std=08` and should synthesize on Xilinx with no
  algorithmic change; only the *board glue* is Altera-specific.
- **Unlocks real throughput headroom** — the DE2's ~2004 90 nm fabric caps the
  decoder near ~28 MHz even after the recurrence-pipelining work; the K26's
  modern 16 nm fabric should clock the SAME RTL several times higher, so the
  recurrence-pipelining levers (`ANCHOR_NORM`/`BAL_TREE_FOLD`/`PIPE_DFOLD`,
  already merged behind generics) can be exercised at a meaningful clock.

**This is a planning/design change only** (no `hdl/`, `scripts/`, or Vivado
files land here). It pins the toolchain + target, decides the integration
shape, maps clocking/IO, and stages the work — exactly how every DE2 arc began.

## What Changes

- **Target the PL-only self-check demo first** (the direct analog to the DE2
  decoder demo): `turbo_decoder_top` (the merged, recurrence-pipelined core) +
  an on-chip golden-vector ROM + a self-check FSM that lights the KR260 user
  LEDs (PASS / FAIL / RUNNING + heartbeat), downloaded over **JTAG** via the
  on-board FT4232H — **no microSD, no Linux, no PS+AXI**, mirroring
  `quartus_pgm`. The verified cores are instantiated UNMODIFIED.
- **Pin the toolchain** (the DE2 "Quartus 13.0sp1" analog): **AMD Vivado ML
  Edition (Standard, license-free for Kria)**, device **`xck26-sfvc784-2LV-c`**
  with the **KR260/K26 board files**; exact Vivado version pinned at install
  time (KR260 board files require ≥ 2021.1; pick the latest stable). Record it in
  the FPGA-toolchain memory like the Quartus pin.
- **Decide the clocking strategy** (the key Zynq-vs-Altera difference): on Zynq
  UltraScale+ the PL clock normally originates from the **PS (`pl_clk0`)**, so
  even a "PL-only" demo typically needs a minimal **Zynq MPSoC PS block-design
  instance** (PL clock + reset only, no AXI), OR a free-running PL bank clock if
  the KR260 carrier routes one. The design picks one (default: minimal PS for
  `pl_clk0`) and documents the trade.
- **Keep the two-tier verification discipline**: the existing GHDL/cocotb lanes
  are board-agnostic and stay green unchanged (the bit-exact contract is the
  same RTL); the KR260 adds a Vivado **synth + implementation + timing-closure**
  gate and an on-board **JTAG self-check** (PASS LED), hardware-gated on the
  user's board.

## Capabilities

### New Capabilities

- `fpga-kr260-decoder-port`: a Vivado PL-only board demo that runs the verified
  `turbo_decoder_top` on the Kria K26 (`xck26-sfvc784-2LV`), self-checking
  against an on-chip golden vector and reporting PASS/FAIL on the KR260 user
  LEDs over a JTAG-downloaded bitstream, with timing closed in Vivado — the
  Xilinx analog of the archived `add-fpga-turbo-decoder-de2-demo`.

## Impact

- Adds a **second board target** alongside the DE2; the portable cores are
  shared, the board glue (`.xdc` constraints, clocking, LED self-check wrapper,
  Vivado project/TCL) is new and KR260-specific. The Altera flow
  (`.qsf`/`altpll`/`quartus_pgm`) does NOT carry over.
- Depends on a **large new toolchain install (Vivado)** — a user-driven,
  multi-GB action that gates all build work; and on the KR260 JTAG link (the
  FT4232H, already confirmed enumerating on the host).
- **Risk:** the Zynq clocking model (PS-sourced `pl_clk0`) and the exact
  KR260 user-LED/PMOD pin constraints are the main unknowns — flagged for
  confirmation at board bring-up (the DE2 had an analogous device-string gotcha).
  Vivado synthesis behavior on the same RTL (e.g. block-RAM inference, the
  `ramstyle`/M4K attributes are Altera-specific and ignored/replaced on Xilinx)
  must be re-checked.

## Out of Scope (explicit)

- **PS + PL AXI integration** and any Linux / Kria runtime PL-overlay app
  (a much larger separate arc; this demo is bitstream-over-JTAG only).
- The **TX chain and RX chain** on the KR260 (decoder-first, like the DE2).
- **CRC24 / HARQ** termination on the KR260.
- Booting Linux / flashing a Kria SD image (a separate Path-B effort).
- Any change to the verified cores or their bit-exact golden vectors.
