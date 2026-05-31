# Tasks — add-fpga-kr260-decoder-port (PL-only decoder demo)

Second board target (Kria K26 `xck26-sfvc784-2LV`, Vivado). PL-only decoder
self-check over JTAG — the Xilinx analog of the archived
`add-fpga-turbo-decoder-de2-demo`. The verified cores are reused UNMODIFIED; the
GHDL/cocotb bit-exact lanes stay green; the new gate is a Vivado synth+impl
timing closure + an on-board JTAG self-check. See `design.md` for the toolchain
pin, the Zynq clocking decision (§3), and the bring-up gotchas (§4/§7).

## 0. This change is design-only

- [x] 0.1 Author `proposal.md` / `design.md` / `spec.md` / `tasks.md`; no `hdl/`,
  `scripts/`, or Vivado files land in this change.
- [x] 0.2 `npx openspec validate add-fpga-kr260-decoder-port --strict` +
  `--all --strict` pass (35/35).

## 1. Toolchain + project skeleton

- [x] 1.1 Install AMD Vivado + the KR260/K26 board files; pin the exact version
  + device. **DONE (2026-05-28):** Vivado **2025.2.1** at
  `D:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat` (user installed on D:, not
  on PATH — invoke by full path); KR260 board files installed (confirmed via
  user's GUI project: `BoardPart="xilinx.com:kr260_som:part0:1.1"`). Device
  `xck26-sfvc784-2LV-c`. Pinned in `project_fpga_toolchain.md`.
- [x] 1.2 Create a reproducible **TCL build script** (not the binary `.xpr`)
  targeting `xck26-sfvc784-2LV`. **DONE:**
  `hdl/boards/kr260/turbo_decoder_kr260_synth.tcl` (committed artifact; the
  `.xpr` lives at `C:\Users\montg\project_1\` as user's scratch). Bare OOC
  synth of `turbo_decoder_top` with all three recurrence levers on
  (`ANCHOR_NORM`/`BAL_TREE_FOLD`/`PIPE_DFOLD`), K_MAX=512, MAX_ITER=2: **0
  errors, 0 critical warnings**. Logic: 7,019 LUTs (5.99%), 1,866 FFs (0.80%),
  561 CARRY8s, 0 DSP — tiny vs DE2's 38% LE.
- [x] 1.3 Re-verify Xilinx **BRAM inference** on the loop memories. **DONE:**
  **9 BRAM / 144 (6.25%), 100% inferred to RAMB36E2/RAMB18E2**, zero LUTRAM
  fallback — Vivado infers Block RAM correctly with NO Xilinx-specific hints
  (the Altera `ramstyle="M4K"` attrs are inert and harmless). `alpha_mem` =
  3× RAMB36E2 + 1× RAMB18E2; `ca/ce/chs/xpa/xpe/za/zpa_mem`, `xa/za_mem`
  (constituent input), and `qpp_rom` each inferred to RAMB18E2.

## 2. Clocking (design.md §3)

- [x] 2.1 Bring a PL clock + reset into the fabric: default = a minimal Zynq
  MPSoC PS block design exposing `pl_clk0` (~100 MHz target) + `pl_resetn0`, NO
  AXI (or a Clocking Wizard off a carrier clock if the KR260 routes one — confirm
  from the schematic). Regenerable from TCL. **DONE:** `kr260_create_clocking_bd`
  proc in `hdl/boards/kr260/turbo_decoder_kr260_synth.tcl` creates a BD with
  `zynq_ultra_ps_e_0` (K26 board preset, all AXI M/S disabled,
  `PSU__FPGA_PL0_ENABLE=1`, `PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ=100`) +
  `proc_sys_reset_0` (slowest_sync_clk ← pl_clk0; ext_reset_in ← pl_resetn0);
  BD output ports `pl_clk0` + `pl_resetn0` (the proc_sys_reset's
  `peripheral_aresetn`); `make_wrapper -import` generates
  `kr260_clocking_wrapper`. Re-runnable (clobbers prior BD/proj). Selectable
  via `-mode bd_only` for sanity (validate_bd_design) without paying a
  bitstream cost.

## 3. Self-check wrapper + constraints

- [x] 3.1 Port the DE2 self-check FSM + on-chip golden ROM into a new
  `turbo_decoder_kr260_top` (reuse the comparator / err-count / verdict logic;
  swap the Altera PLL + pin names for the §2 clock and KR260 LEDs). **DONE:**
  `hdl/boards/kr260/turbo_decoder_kr260_top.vhdl`. Ports: ONLY `LEDS(1 downto
  0)` (clock + reset come from the BD wrapper inside). Self-check FSM
  (CH_RESET/START/LOAD/RUN/PASS/FAIL), err_cnt comparator, frame_err, run_hold
  timer, heartbeat counter all ported VERBATIM from
  `hdl/boards/de2/turbo_decoder_de2_top.vhdl`. Golden ROM
  `turbo_decoder_golden_pkg` REUSED unchanged. Core `turbo_decoder_top`
  instantiated with `K_MAX=512, MAX_ITERATIONS=2, ANCHOR_NORM/BAL_TREE_FOLD/
  PIPE_DFOLD=true` (same recurrence-pipelined cores as the DE2 25 MHz build).
  Two-LED encoding: LEDS(0) = blink (running) → solid (PASS) → off (FAIL);
  LEDS(1) = solid only on FAIL. Restart edge synthesized off the PS reset
  release (single-shot per power-cycle, OK'd for v1).
- [x] 3.2 Write the `.xdc`: PL clock period constraint + LED/reset LOC +
  IOSTANDARD, with pin LOCs **confirmed against the KR260 board documentation**
  (do not guess — the DE2 pin-table discipline). **DONE:**
  `hdl/boards/kr260/turbo_decoder_kr260.xdc`. NO `create_clock` — the
  `zynq_ultra_ps_e` IP auto-generates `clk_pl_0` @ 100 MHz and timing closes
  against it (an explicit clock is redundant, and XDC forbids the `if` needed
  to guard it — it raised a Designutils 20-1307 critical warning, since removed
  in #99). `LEDS[0]` → pin F8 LVCMOS18 (User_led[0] = som240_1_d13), `LEDS[1]`
  → pin E8 LVCMOS18 (User_led[1] = som240_1_d14) from the kr260_carrier
  connection_map → kr260_som part0_pins; DRC passed (0 errors) but the LOCs are
  still pending physical confirmation on-board at stage 5. No set_false_paths
  needed (no async top-level inputs).
- [ ] 3.3 A KR260 self-check **GHDL/cocotb sim lane** (template: the DE2 self-
  check lane with the PLL sim model replaced by a plain divided/again clock)
  reaches the PASS verdict on the golden vector and FAIL on a corrupt index.

## 4. Vivado synth + impl + timing

- [x] 4.1 Run Vivado synth + implementation to a `.bit`; **timing closes**
  (non-negative WNS at the PL clock); record LUT/FF/BRAM/DSP + WNS + achieved
  Fmax (vs the DE2's ~28 MHz). (Parent drives the long build, per the DE2 lesson.)
  **DONE (parent-driven `-mode bitstream`, Vivado 2025.2.1):** `.bit` at
  `build/kr260/proj/kr260_demo.runs/impl_1/turbo_decoder_kr260_top.bit`.
  **Timing CLOSES at 100 MHz: WNS +0.836 ns** (clk_pl_0, 0/5029 failing
  endpoints; WHS +0.017, WPWS +4.238) → achieved Fmax ≈ **109 MHz** (vs DE2
  ~28 MHz). Utilization: **7,052 LUT (6.0%)**, 1,986 FF (0.85%), **9 BRAM
  (6.25%** — 3×RAMB36E2 + 12×RAMB18E2, all inferred), **0 DSP**, 2 IOB.
  Build is **0 errors / 0 critical warnings** (after the #99 XDC fix), DRC
  clean.

## 5. On-board (HARDWARE-GATED — user's KR260)

- [ ] 5.1 Download the `.bit` over the FT4232H JTAG (Vivado Hardware Manager);
  confirm the PASS LED lights (a corrupt build shows FAIL); exercise the re-run
  control.

## 6. Docs + validate

- [ ] 6.1 KR260 demo README (build TCL usage, JTAG download steps, LED meaning);
  update `project_fpga_toolchain.md` with the confirmed Vivado/board specifics.
- [ ] 6.2 `npx openspec validate --all --strict` passes; archive when on-board
  PASS is confirmed.
