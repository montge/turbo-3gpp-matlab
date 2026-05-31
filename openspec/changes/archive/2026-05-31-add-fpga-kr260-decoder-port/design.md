# Design — add-fpga-kr260-decoder-port (PL-only decoder demo)

## 1. Target + toolchain (the DE2 → KR260 translation)

| aspect | DE2 (done) | KR260 (this plan) |
|--------|-----------|-------------------|
| board | Terasic DE2 | AMD Kria **KR260** (K26 SOM `SMK-K26-XCL2G`) |
| silicon | Cyclone II `EP2C35F672C6` | Zynq UltraScale+ **`xck26-sfvc784-2LV`** (-2, LV) |
| tool | Quartus II **13.0sp1** | **Vivado ML Standard** (license-free for Kria), KR260/K26 board files; exact version pinned at install (≥ 2021.1 has Kria; use latest stable) |
| program | `quartus_pgm` over USB-Blaster | Vivado **Hardware Manager** `.bit` over the on-board **FT4232H** JTAG (confirmed enumerating: USB Serial Converter A–D) |
| block RAM | M4K, `ramstyle="M4K"` attr | Xilinx **BRAM** (RAMB36/18); the Altera `ramstyle` attributes are ignored — re-verify inference, add `ram_style` Xilinx attrs only if needed |
| clock | 50 MHz osc → `altpll` (÷2 = 25 MHz) | **see §3** — no simple board oscillator to PL; clock comes from the PS `pl_clk0` or a carrier clock |
| status I/O | LEDG/LEDR/HEX/LCD | KR260 user LEDs / PMOD — **pins TBD at bring-up** (§4) |

**Pin the toolchain in memory** (`project_fpga_toolchain.md`) once the Vivado
version is installed, exactly like the Quartus 13.0sp1 pin — including any
board-file install step and the JTAG/cable specifics.

## 2. What ports cleanly vs. what is new

**Ports unchanged (generic `--std=08`, no Altera primitives):**
`constituent_decoder.vhdl` (incl. the merged `ANCHOR_NORM`/`BAL_TREE_FOLD`/
`PIPE_DFOLD` levers), `turbo_decoder_top.vhdl`, `qpp_rom`/`qpp_interleaver`,
`turbo_decoder_golden_pkg.vhdl` (the on-chip K=512 golden ROM),
`lcd_format_pkg`/`hd44780_lcd` IF an LCD is wired (optional on KR260).
The self-check FSM logic from `turbo_decoder_de2_top` is reusable; only its
Altera-specific instances (PLL, pin names) change.

**New, KR260-specific:**
- A Vivado project (prefer a **checked-in TCL build script**, not the binary
  `.xpr`, so the flow is reproducible/reviewable — the analog of the committed
  `.qsf`).
- A constraints file **`.xdc`** (pin LOC + IOSTANDARD for the clock, reset, and
  the status LEDs; timing constraint on the PL clock — the `.sdc` analog).
- A KR260 top wrapper (`turbo_decoder_kr260_top`) = the reusable self-check FSM +
  golden ROM + LED mapping + the clocking source from §3.
- The clocking block design / IP (§3).

## 3. Clocking — the key Zynq-vs-Altera difference (decision)

On Cyclone II the 50 MHz board oscillator drives an `altpll` directly. On Zynq
UltraScale+ the **PL has no guaranteed free-running oscillator** unless the
carrier routes one; the canonical PL clock is **`pl_clk0` from the PS** (the
Zynq MPSoC hard block). Options:

- **(A — default) Minimal Zynq MPSoC PS block design for `pl_clk0` + `pl_resetn0`
  only** — instantiate the `zynq_ultra_ps_e` IP with a bare config (one PL clock,
  e.g. 100 MHz, one reset; NO AXI, no DDR app, no peripherals), feed the decoder.
  This is the standard "PL-only but clocked by PS" pattern. Cost: a small block
  design (`.bd`) and the PS preset for the K26 board (the board file provides it).
- **(B) Clocking Wizard (MMCM/PLL) off a carrier clock** — only if the KR260
  routes a free-running clock to a PL bank (to confirm from the KR260 schematic);
  avoids the PS but needs a real clock-capable input pin.

Default to **(A)**: it's the documented Kria PL clocking path and the board file
auto-presets the PS. Start the PL clock modest (e.g. 100 MHz target) and let the
recurrence-pipelined decoder's timing report set the achievable rate — the K26
fabric should clear it with large margin vs the DE2's ~28 MHz, so a later step
can push the PL clock up to find the real Fmax (a nice throughput showcase).

## 4. Status I/O (confirm at bring-up — the DE2 pin-table discipline)

The DE2 demo drove LEDG[0]=PASS, LEDR[0]=FAIL, LEDG[1]=RUNNING, 7-seg `A5`/`FF`,
and the LCD. The KR260 has fewer simple LEDs (the K26 SOM has a couple of user
LEDs; the carrier exposes status LEDs + PMOD headers). Plan:
- Map **PASS / FAIL / RUNNING + heartbeat** to whatever user LEDs the KR260
  exposes (≥ 2 LEDs minimum; heartbeat can share or use a PMOD pin).
- Pin LOC/IOSTANDARD values are **TBD until verified against the KR260
  schematic / board user guide** — flagged exactly like the DE2 "verify pins
  against the Terasic table" gate. Do NOT guess LOCs; confirm from the board doc.
- An LCD is optional (only if a compatible character LCD is wired to a PMOD);
  the LED PASS/FAIL is the primary self-check readout for v1.

## 5. Verification (two-tier, unchanged discipline)

- **Inner (board-agnostic, already green):** the GHDL/cocotb bit-exact lanes for
  `turbo_decoder_top` etc. are unchanged — the KR260 demo instantiates the SAME
  RTL, so no new reference/vectors. The DE2 self-check sim lane is the template
  for a KR260 self-check sim (swap the PLL sim model for a plain clock; the
  golden ROM + FSM are identical).
- **Outer (Xilinx):** Vivado **synthesis + implementation + `report_timing`**
  must close at the chosen PL clock on `xck26-sfvc784-2LV`; record LUT/FF/BRAM/
  DSP + WNS. Re-confirm **BRAM inference** on the loop memories (the Altera
  M4K attributes are inert on Xilinx; expect RAMB inference, add `ram_style` only
  if Vivado scatters them to LUTRAM).
- **On-board (hardware-gated, user's board):** download the `.bit` over JTAG;
  confirm the PASS LED lights (and a corrupt build shows FAIL), with a re-run
  control (a button/PMOD or a re-download).

## 6. Staging

1. **Toolchain + project skeleton** (gated on Vivado install): pin the Vivado
   version + device + board files in memory; create the reproducible TCL build
   script targeting `xck26-sfvc784-2LV`; add the shared core sources; confirm a
   bare elaborate/synth of `turbo_decoder_top` runs (no board glue yet).
2. **Clocking** (§3): minimal Zynq PS `pl_clk0` block design (or clocking wizard);
   bring a clock + reset into the PL.
3. **Self-check wrapper + `.xdc`**: port the DE2 self-check FSM + golden ROM into
   `turbo_decoder_kr260_top`; map PASS/FAIL/RUNNING to confirmed KR260 LEDs;
   write the `.xdc` (clock period + LED LOC/IOSTANDARD). A KR260 GHDL/cocotb
   self-check sim lane stays green.
3. **Synth + impl + timing**: Vivado run to a `.bit`; timing closes; record
   resources + WNS + achieved Fmax (vs the DE2's 28 MHz).
4. **On-board (user)**: JTAG-download the `.bit`; confirm PASS LED; corrupt-build
   FAIL; re-run.
5. **Docs + validate**: README for the KR260 demo; update the toolchain memory;
   `openspec validate --strict`.

## 7. Risks / open questions (be honest)

- **Vivado install is the big gate** — multi-GB, user-driven; nothing builds
  until it's in. The plan is install-agnostic; the version is pinned at install.
- **PS clocking** (§3) adds a block design — more than the DE2's pure-RTL+PLL
  flow; the `.bd` is the least-reproducible artifact (mitigate with a TCL that
  regenerates it).
- **KR260 LED/clock pin LOCs unknown** — must come from the board doc, not a
  guess (DE2 pin-table discipline).
- **BRAM inference** on Xilinx may differ from the M4K result — re-verify; the
  decoder fit on the K26 should be trivially small (the K26 is far larger than
  the EP2C35), so capacity is a non-issue, but inference *style* matters for Fmax.
- This is a **large new arc**; PL-only-decoder-first keeps it bounded and
  reuses the verified cores, deferring PS+PL/AXI and Linux entirely.
