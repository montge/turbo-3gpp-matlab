# Altera DE2 — turbo_decoder_top board self-check demo (K=512, 12.5 MHz PLL)

Board demo that runs the iterative Max-Log-MAP turbo **decoder**
(`hdl/rtl/turbo_decoder_top.vhdl`) on a Terasic DE2 (Cyclone II
`EP2C35F672C6`) and self-verifies it on-chip against a committed golden vector.
This is the first turbo **decoder** (the receive path) on real hardware — it
complements the archived `tx_chain_top` transmit demo. The core is instantiated
**unmodified**; this directory adds only the board wrapper, a PLL, an on-chip
golden ROM, a self-check FSM, the Quartus project, and constraints.

Stages 1–3 of `add-fpga-turbo-decoder-de2-demo` are complete: the synthesizable
wrapper + GHDL self-check (stage 1–2), and the Quartus fit + TimeQuest closure
at the PLL clock (stage 3). The **on-board program + observe (stage 4) is the
user's step** — see "Program" below.

## Target and toolchain

- **FPGA:** Cyclone II `EP2C35F672C6` — board marking `EP2C35F672C6N`; the
  lead-free `N` suffix is packaging-only and is **not** a separate Quartus
  device string.
- **Toolchain:** Quartus II **13.0sp1** only. Quartus II 13.1 cannot target
  Cyclone II (it dropped the family); do not use it for this board.

## The one new board element — a PLL-derived ~12.5 MHz clock (Option A)

Unlike the TX demo (which runs at the full 50 MHz `CLOCK_50`), the decoder
**cannot** close timing at 50 MHz. Its constituent core's forward α recurrence
(`constituent_decoder` `alpha_prev`: an 8-way saturating-add → max-norm →
saturate combinational cone, ~64.8 ns) is a **feedback recurrence** that caps
Fmax at **15.43 MHz** and cannot be naively pipelined. Per the user's **Option
A**, the demo therefore runs the whole design on a Cyclone II `altpll`-derived
**12.5 MHz** clock — `CLOCK_50` (50 MHz) ÷4, an 80 ns period that clears the
64.8 ns cone with ~15 ns raw margin. (÷3 → 16.67 MHz / 60 ns would **fail** the
cone, so it is not used; closing 50 MHz would need algorithmic α/β-recurrence
pipelining, a separate deferred increment — **Option B**.)

- **`pll_12p5_mf.vhd`** is the wizard-generated (qmegawiz) `altpll` megafunction
  (Cyclone II, NORMAL mode, inclk0 = 50 MHz, c0 = 12.5 MHz, locked); committed
  verbatim because A&S rejects a hand-rolled altpll GENERIC MAP that omits the
  per-clock / lock parameters.
- **`pll_12p5.vhdl`** is the thin SYNTHESIS wrapper around it (entity
  `pll_12p5`, ports `areset`/`inclk0`/`c0`/`locked`).
- **`pll_12p5_sim.vhdl`** is the SIMULATION stand-in — a behavioural ÷4 clock
  divider exposing the identical `pll_12p5` entity. GHDL cannot elaborate the
  altpll hard block, so the GHDL self-check lane compiles this divider instead.
  The demo is fully synchronous, so the divided sim clock is functionally
  identical to the synthesised PLL output for the bit-exact verdict; only
  Quartus elaborates the real PLL, and only the on-board run exercises it.

## What the demo does

On power-up (and again on each `KEY[0]` press) the self-check FSM, clocked on
the PLL output:

1. resets `turbo_decoder_top`, then pulses `in_start` with `k_in = 512`;
2. streams the 516 (= K+4) `d_a` channel-LLR columns from the on-chip ROM on
   `da_valid` (each beat presents `d_a(1)/d_a(2)/d_a(3)` for that column on
   `da1_in/da2_in/da3_in`, W_EXT = 12-bit signed codes);
3. waits out the whole-block iterative decode (thousands of cycles — H =
   2·max_iter = 4 half-iterations — between the last load beat and the first
   `out_valid`);
4. captures every `out_valid` hard-decision bit `c_out`, compares it to the
   expected `c` bit at the same index, and checks `out_last` arrives exactly at
   bit `K`−1;
5. latches a sticky **PASS** (all 512 bits matched and `out_last` landed at 511)
   or **FAIL** (any mismatch, or `out_last` early/late).

A PASS means the on-chip `turbo_decoder_top` decoded the committed channel-LLR
golden vector to the expected 512 hard bits bit-for-bit.

## On-chip golden ROM provenance

`turbo_decoder_golden_pkg.vhdl` holds, as VHDL constants, the **first K=512,
max_iter=2 row** of `hdl/vectors/turbo_decoder_top.csv` (data row 1 / file line
10), copied verbatim:

| field | value |
|-------|-------|
| `GV_K` | 512 |
| `GV_MAX_ITER` | 2 (→ H = 2·max_iter = 4 half-iterations) |
| `GV_DA1/2/3` | the 3×(K+4) = 3×516 = 1548 signed W_EXT (12-bit, Q7.4) channel-LLR codes, column-major, split into per-row arrays |
| `GV_C` | the 512 expected hard-decision decoded bits (index 0 = first `c_out` bit) |

That same row is the bit-exact golden the `turbo_decoder_top` cocotb lane
(`hdl/sim/turbo_decoder_top/`, MAX_ITER=2 group) checks. This is
board-presentation data; it lives under `hdl/boards/` and is **not** part of the
RTL core. The wrapper sets the core generic `MAX_ITERATIONS => GV_MAX_ITER = 2`
to match the row (a DUT built with a different H cannot bit-exactly reproduce an
H=4 frame, by construction).

## I/O mapping and verdict indication

| Signal | Board | Use |
|--------|-------|-----|
| `CLOCK_50` | 50 MHz oscillator (`PIN_N2`) | PLL reference (feeds the PLL only) |
| `KEY[0]` | push button (active-low) | press = synchronous restart / re-run |
| `LEDG[0]` | green LED | **PASS** (lit when the self-check passed) |
| `LEDR[0]` | red LED | **FAIL** (lit on mismatch) |
| `LEDG[1]` | green LED | **RUNNING** (lit until a verdict is reached) |
| `LEDR[1]` | red LED | **DONE** (lit once a verdict is reached) |
| `HEX1 HEX0` | seven-segment (active low) | status code |

Seven-segment status code (via the shared `hdl/boards/hex7seg.vhdl` nibble
decoder, so glyphs are the hex set):

| state | `HEX1 HEX0` |
|-------|-------------|
| running | `0 0` |
| **pass** | `A 5` |
| **fail** | `F F` |

The pin locations are copied **verbatim** from the verified `tx_chain_de2.qsf`
(same DE2 board, same CLOCK_50 / KEY / LEDR / LEDG / HEX subset). As with the TX
demo, the pinout **must be cross-checked against the Terasic DE2 user manual
before programming real hardware** (stage 4).

## Build (Quartus II 13.0sp1, no board needed)

```bash
cd hdl/boards/de2
C:\altera\13.0sp1\quartus\bin64\quartus_sh --flow compile turbo_decoder_de2
```

Produces `output_files/turbo_decoder_de2.sof` (gitignored). The K=512 build
fits the EP2C35 with comfortable headroom (well within 33,216 LE and 105 M4K;
0 multipliers) and TimeQuest closes setup/hold on the PLL-derived 12.5 MHz
domain (80 ns period ≫ the 64.8 ns α-recurrence cone). See the PR body for the
exact LE / M4K / slack numbers from the committed build.

## Program (stage 4 — the user's step, requires the physical board)

```bash
C:\altera\13.0sp1\quartus\bin64\quartus_pgm -c USB-Blaster -m jtag -o "p;output_files/turbo_decoder_de2.sof"
```

Then press `KEY[0]` (or just observe the power-up free-run) and watch
`LEDG[0]` (PASS) light and `HEX1 HEX0` show `A5` — i.e. the on-board
`turbo_decoder_top` decoded the committed K=512 channel-LLR golden vector to the
expected 512 hard bits bit-for-bit on silicon. A red `LEDR[0]` / `FF` means a
mismatch. Cross-check the pinout against the DE2 user manual first.

### On-board result — PASS (2026-05-24)

Run on real hardware: the DE2 (Cyclone II `EP2C35F672C6`) was programmed over
USB-Blaster JTAG with the above command — *"Configuration succeeded -- 1
device(s) configured, 0 errors"* — and the on-chip self-check reported
**HEX = A5 with LEDG[0] green (LEDR[0] off, LEDR[1] done on) = PASS**. The
on-board `turbo_decoder_top` therefore decoded the committed K=512 channel-LLR
golden vector (K=512, max_iter=2 → H=4) to the expected 512 hard bits
bit-for-bit on silicon at the PLL-derived 12.5 MHz.

## GHDL self-check (sim gate — no Quartus needed)

The cocotb lane under `hdl/sim/turbo_decoder_de2/` elaborates
`turbo_decoder_de2_top` (with the behavioural ÷4 sim PLL) and runs it to a
verdict:

```bash
source scripts/hdl_env.sh
cd hdl/sim/turbo_decoder_de2
make                       # case 1: real golden vector -> self-check PASS
python test_runner.py      # both cases: PASS on golden, FAIL on a flipped bit
```

`test_runner.py` runs the lane twice: once with the default `CORRUPT_IDX=-1`
(real behaviour, must reach **PASS**), and once with `CORRUPT_IDX=7` (one
expected bit flipped, must reach **FAIL**) — proving the comparator actually
checks. `CORRUPT_IDX` is a TEST-ONLY generic; the synthesized board uses the
default and never corrupts.

`make` alone runs only the PASS case and is the entry point picked up by
`scripts/run_all_hdl_lanes.sh`.
