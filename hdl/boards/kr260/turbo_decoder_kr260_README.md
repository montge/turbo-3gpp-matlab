# AMD Kria KR260 — turbo_decoder_top board self-check demo (K=512, 100 MHz PL)

Board demo that runs the iterative Max-Log-MAP turbo **decoder**
(`hdl/rtl/turbo_decoder_top.vhdl`) on an AMD Kria **KR260** (Zynq UltraScale+
K26 SOM, `xck26-sfvc784-2LV`) and self-verifies it on-chip against a committed
golden vector. This is the **second board target** for the decoder — the Xilinx
analog of the archived `add-fpga-turbo-decoder-de2-demo`. The verified cores are
instantiated **unmodified**; this directory adds only the board wrapper, a
minimal Zynq PS clocking block design, a sim clocking stub, the on-chip golden
ROM (reused from the DE2 build), a self-check FSM, the reproducible TCL build
script, a JTAG program script, and the `.xdc`.

`add-fpga-kr260-decoder-port` is **complete through the on-board run**: OOC synth
(stage 1), PS clocking BD + self-check wrapper + `.xdc` (stages 2–3), GHDL/cocotb
self-check lane (stage 3.3), Vivado synth→impl→bitstream with timing closure
(stage 4), and the **on-board PL-only self-check over JTAG (stage 5)**.

## Target and toolchain

- **FPGA / SOM:** Kria K26 `xck26-sfvc784-2LV-c` on the `kr260_som` carrier
  (board part `xilinx.com:kr260_som:part0:1.1`).
- **Toolchain:** AMD **Vivado 2025.2.1** (license-free for Kria), installed on
  `D:\AMDDesignTools\2025.2.1\` — **invoke by full path**
  (`D:/AMDDesignTools/2025.2.1/Vivado/bin/vivado.bat`); it is not on PATH. The
  KR260/K26 board files must be installed. This is the Xilinx analog of the DE2
  "Quartus 13.0sp1 pin" — pinned in the FPGA-toolchain memory.
- **Program link:** the on-board **FT4232H** provides JTAG (same USB cable that
  exposes the UART console on a separate channel); Vivado Hardware Manager
  downloads the `.bit` over it — the analog of `quartus_pgm`/USB-Blaster.

## Clocking — a minimal Zynq PS block design (design.md §3, Option A)

The KR260 carrier routes no top-level oscillator the PL can use without going
through the PS, so the demo takes its clock + reset from a minimal Zynq MPSoC PS
block design (no AXI, no DDR app):

- **`kr260_create_clocking_bd`** (a proc in `turbo_decoder_kr260_synth.tcl`)
  builds a BD with `zynq_ultra_ps_e_0` (K26 board preset, all AXI M/S disabled,
  `PSU__FPGA_PL0_ENABLE=1`, `PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ=100`) +
  `proc_sys_reset_0`. It exposes two BD output ports: `pl_clk0` (100 MHz to the
  PL) and `pl_resetn0` (the synchronized active-low `peripheral_aresetn`).
  `make_wrapper -import` generates `kr260_clocking_wrapper`, which the board
  wrapper instantiates. Re-runnable; validate-only via `-mode bd_only`.
- **`kr260_clocking_wrapper_sim.vhdl`** is the SIMULATION stand-in — a
  behavioural **self-clocking** stub exposing the identical
  `kr260_clocking_wrapper` entity (two outputs, no inputs). GHDL cannot
  elaborate the `zynq_ultra_ps_e` PS block, so the GHDL self-check lane compiles
  this stub instead; it self-generates a 100 MHz `pl_clk0` (`after`-driven, no
  input clock to divide — the PS sources its clock internally) and releases
  `pl_resetn0` after a few cycles. The demo is fully synchronous, so the
  behavioural clock is functionally identical to the real PS `pl_clk0` for the
  bit-exact verdict; only the Vivado build and the on-board run exercise the real
  PS block.

No explicit `create_clock` is in the `.xdc`: the `zynq_ultra_ps_e` IP
auto-generates `clk_pl_0` @ 100 MHz and timing closes against it. (An explicit
clock is redundant, and XDC forbids the `if` needed to guard against
double-defining it — an early attempt raised a `Designutils 20-1307` critical
warning, removed in #99.)

## What the demo does

On power-up / configuration (and again on a PS-reset deassertion) the self-check
FSM, clocked on `pl_clk0`:

1. resets `turbo_decoder_top`, then pulses `in_start` with `k_in = 512`;
2. streams the `GV_N_COLS` (= K+3) `d_a` channel-LLR columns from the on-chip ROM
   on `da_valid` (each beat presents `d_a(1)/d_a(2)/d_a(3)` on
   `da1_in/da2_in/da3_in`, W_EXT = 12-bit signed codes);
3. waits out the whole-block iterative decode (H = 2·max_iter = 4
   half-iterations);
4. captures every `out_valid` hard-decision bit `c_out`, compares it to the
   expected `c` bit at the same index, and checks `out_last` arrives exactly at
   bit `K`−1;
5. latches a sticky **PASS** (all 512 bits matched, `err_cnt = 0`,
   `frame_err = '0'`, and `out_last` at 511) or **FAIL** (any mismatch or
   framing error).

A PASS means the on-chip `turbo_decoder_top` decoded the committed channel-LLR
golden vector to the expected 512 hard bits bit-for-bit, at 100 MHz on the K26
PL. The core is instantiated with `K_MAX=512`, `MAX_ITERATIONS=2`, and all three
recurrence-pipelining levers on (`ANCHOR_NORM`/`BAL_TREE_FOLD`/`PIPE_DFOLD`) —
the same recurrence-pipelined cores as the DE2 25 MHz build, bit-exact.

## On-chip golden ROM provenance

`turbo_decoder_kr260_top` reuses `hdl/boards/de2/turbo_decoder_golden_pkg.vhdl`
unchanged — the **first K=512, max_iter=2 row** of
`hdl/vectors/turbo_decoder_top.csv` (`GV_K=512`, `GV_MAX_ITER=2`,
`GV_DA1/2/3` = 3×516 signed 12-bit channel-LLR codes, `GV_C` = 512 expected
hard bits). The wrapper sets `MAX_ITERATIONS => GV_MAX_ITER` so the core's
H = 2·max_iter = 4 matches the golden frame exactly.

## Two-LED status encoding (the user's constraint — only two LEDs)

| LED | Pin (IOSTANDARD) | Meaning |
|-----|------------------|---------|
| `LEDS(0)` | `F8` (LVCMOS18) | blink ~3 Hz while **running**; solid **on = PASS**; off on fail |
| `LEDS(1)` | `E8` (LVCMOS18) | solid **on = FAIL**; off otherwise |

Read across the room: **blink = running; one LED solid (LEDS0) = PASS; the other
solid (LEDS1) = FAIL; both off = power/clock problem (no heartbeat)**. The pins
are the `kr260_som` `som240_1_d13`/`som240_1_d14` user-LED nets → FPGA pins
`F8`/`E8`. Single-shot per power-cycle for v1 (the carrier has no convenient
PL-side push-button; `restart` is driven off the PS reset deassertion). The
heartbeat blink (`hb_cnt(25)` @ 100 MHz ≈ 0.34 s) matches the DE2's visual rate.

## Build (Vivado 2025.2.1, no board needed)

`turbo_decoder_kr260_synth.tcl` is mode-selectable (outputs land in
`build/kr260/`, gitignored):

```bash
V="D:/AMDDesignTools/2025.2.1/Vivado/bin/vivado.bat"
S=hdl/boards/kr260/turbo_decoder_kr260_synth.tcl

# OOC synth of the core only (utilization + BRAM-inference report)
"$V" -mode batch -source "$S" -nojournal -nolog -tclargs -mode synth_ooc

# Validate the PS clocking BD only (fast; no synth cost)
"$V" -mode batch -source "$S" -nojournal -nolog -tclargs -mode bd_only

# Full demo: synth -> impl -> write_bitstream (long, >10 min — parent drives)
"$V" -mode batch -source "$S" -nojournal -nolog -tclargs -mode bitstream
```

`-mode bitstream` writes
`build/kr260/proj/kr260_demo.runs/impl_1/turbo_decoder_kr260_top.bit` plus
utilization + timing reports under `build/kr260/`.

### Build result — timing CLOSES (2026-05-31)

The full `-mode bitstream` build closes timing at 100 MHz with **0 errors / 0
critical warnings**, DRC clean:

| metric | value |
|--------|-------|
| clock | `clk_pl_0` @ **100.000 MHz** (PS IP auto-generated) |
| **WNS** | **+0.836 ns** (0/5029 failing endpoints) → achieved Fmax ≈ **109 MHz** (vs DE2 ~28 MHz) |
| hold (WHS) / pulse (WPWS) | +0.017 ns / +4.238 ns |
| LUTs | 7,052 (6.0% of 117,120) |
| FFs | 1,986 (0.85%) |
| Block RAM | 9 (6.25%) — 3×RAMB36E2 + 12×RAMB18E2, all inferred (0 LUTRAM) |
| DSP | 0 |
| IOB | 2 (the two LEDs) |

## Program (stage 5 — requires the physical KR260)

```bash
V="D:/AMDDesignTools/2025.2.1/Vivado/bin/vivado.bat"
"$V" -mode batch -source hdl/boards/kr260/program_kr260.tcl -nojournal -nolog
#   [ -tclargs -bit <path-to-.bit> ]   # default = the impl_1 bitstream above
```

The script opens Hardware Manager, connects the FT4232H JTAG, narrows the chain
to the K26 (`xck26`/`xczu*`), and programs. Then watch the LEDs per the encoding
above. `program_kr260.tcl` is the analog of
`quartus_pgm -c USB-Blaster -m jtag -o "p;...sof"`.

### On-board result — PASS (2026-05-31)

Run on real hardware: the KR260 (K26 `xck26`) was programmed over FT4232H JTAG —
JTAG chain `xck26_0 arm_dap_1`, *"End of startup status: HIGH"* (configuration
succeeded) — and the on-chip self-check showed **`LEDS(0)` solid on, `LEDS(1)`
off = PASS**. The on-board `turbo_decoder_top` therefore decoded the committed
K=512 channel-LLR golden vector (max_iter=2 → H=4) to the expected 512 hard bits
bit-for-bit on silicon at 100 MHz. The `F8`/`E8` LED pin LOCs are thereby
confirmed correct (the board lit as designed).

## GHDL self-check (sim gate — no Vivado needed)

The cocotb lane under `hdl/sim/turbo_decoder_kr260/` elaborates
`turbo_decoder_kr260_top` (with the self-clocking sim stub) and runs it to a
verdict. Because the top exposes **only** `LEDS` (no clock/done port), the test
does not drive a clock — it advances sim time and polls the encoded LEDs, with
the run-hold window shrunk via `-gRUN_HOLD_CYC_OVR` so the latched verdict is
visible within the budget:

```bash
source scripts/hdl_env.sh
cd hdl/sim/turbo_decoder_kr260
make                       # case 1: real golden vector -> self-check PASS
python test_runner.py      # both cases: PASS on golden, FAIL on a flipped bit
```

`test_runner.py` runs the lane twice: default `CORRUPT_IDX=-1` (real behaviour,
must reach **PASS**) and `CORRUPT_IDX=7` (one expected bit flipped, must reach
**FAIL**) — proving the comparator actually checks. `CORRUPT_IDX` is a TEST-ONLY
generic; the synthesized board uses the default and never corrupts. `make` alone
runs only the PASS case and is the entry point picked up by
`scripts/run_all_hdl_lanes.sh` (which auto-discovers this lane — no CI change
needed).
