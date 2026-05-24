# Altera DE2 — tx_chain_top board self-check demo (K=40)

Board demo that runs the synthesis-hardened LTE transmit chain
(`turbo_encode_top -> rate_matching_top`, i.e. `hdl/rtl/tx_chain_top.vhdl`) on
a Terasic DE2 (Cyclone II `EP2C35F672C6`) and self-verifies it on-chip against
a committed golden vector. The core is instantiated **unmodified**; this
directory adds only the board wrapper, an on-chip golden ROM, a self-check FSM,
the Quartus project, and constraints.

All stages of `add-fpga-tx-chain-de2-demo` are complete: the synthesizable
wrapper + GHDL self-check (stage 3), the Quartus fit + TimeQuest closure
(stage 4), and the on-board program + observe (stage 5) — which **passed on a
real DE2 on 2026-05-23** (see "On-board result" below).

## Target and toolchain

- **FPGA:** Cyclone II `EP2C35F672C6` — board marking `EP2C35F672C6N`; the
  lead-free `N` suffix is packaging-only and is **not** a separate Quartus
  device string.
- **Toolchain:** Quartus II **13.0sp1** only. Quartus II 13.1 cannot target
  Cyclone II (it dropped the family); do not use it for this board.

## What the demo does

On power-up (and again on each `KEY[0]` press) the self-check FSM:

1. resets `tx_chain_top`, then pulses `in_start` with the on-chip
   `K`/`N_ref`/`I_LBRM`/`rv`/`E` params;
2. streams the `K`=40 input code bits `c` into the core on `c_in_valid`;
3. captures every `out_valid` output bit `e_bit`, comparing it to the expected
   bit at the same index, and checks that `last` arrives exactly at bit `E`−1;
4. latches a sticky **PASS** (all 400 bits matched and `last` landed at 399)
   or **FAIL** (any mismatch, or `last` early/late).

A PASS means the on-chip hardened `tx_chain_top` reproduced the committed
`tx_chain` golden vector bit-for-bit.

## On-chip golden ROM provenance

`tx_chain_golden_pkg.vhdl` holds, as VHDL constants, the **K=40 row** of
`hdl/vectors/tx_chain.csv` (the smallest committed `tx_chain` vector):

| field | value |
|-------|-------|
| `K` | 40 |
| `N_ref` | 0 |
| `I_LBRM` | 0 |
| `rv` | 0 |
| `E` | 400 |
| `c` | 40-bit input code block (verbatim from the CSV) |
| `e` | 400-bit expected rate-matched output (verbatim from the CSV) |

This is board-presentation data; it lives under `hdl/boards/` and is **not**
part of the RTL core.

## I/O mapping and verdict indication

| Signal | Board | Use |
|--------|-------|-----|
| `CLOCK_50` | 50 MHz oscillator (`PIN_N2`) | functional clock for the whole demo |
| `KEY[0]` | push button (active-low) | press = synchronous restart / re-run |
| `LEDG[0]` | green LED | **PASS** (lit when the self-check passed) |
| `LEDR[0]` | red LED | **FAIL** (lit on mismatch) |
| `LEDG[1]` | green LED | **RUNNING** (lit until a verdict is reached) |
| `LEDR[1]` | red LED | **DONE** (lit once a verdict is reached) |
| `HEX1 HEX0` | seven-segment (active low) | status code |
| `LCD_*` | 16x2 HD44780 character LCD | human-readable status (additive) |

Seven-segment status code (via the shared `hdl/boards/hex7seg.vhdl` nibble
decoder, so glyphs are the hex set):

| state | `HEX1 HEX0` |
|-------|-------------|
| running | `0 0` |
| **pass** | `A 5` |
| **fail** | `F F` |

### Character LCD (additive, human-readable status)

The DE2's on-board 16x2 HD44780 character LCD is driven by the shared
`hdl/boards/hd44780_lcd.vhdl` controller (instantiated with
`CLK_HZ => 50_000_000`, the full `CLOCK_50`) **in addition to** the LED/7-seg
verdict — the LEDs and `A5`/`FF` codes are unchanged. The LCD is driven from the
**same** `pass_f`/`fail_f`/`done_f` flags (read only — no verdict-logic change):

| line | content |
|------|---------|
| line 1 | `3GPP TX K=40` (fixed demo label — tells you which demo is loaded) |
| line 2, running | `RUNNING` + an **always-on blink heartbeat** (`*` toggling ~0.34 s off a free-running counter, so the board always shows a live pulse) |
| line 2, pass | `PASS` (with the same blinking `*` heartbeat) |
| line 2, fail | `FAIL` (with the same blinking `*` heartbeat) |

**Minimum RUNNING-display window (~1.5 s).** The K=40 self-check latches its
verdict in well under 1 ms, so without help the `RUNNING` state would flash by
invisibly. A display-state timer (`RUN_HOLD_CYC = (3 × CLK_HZ) / 2` cycles ≈
1.5 s at 50 MHz, reloaded on each `KEY[0]` start) **holds the LCD's `RUNNING`
*display*** for at least ~1.5 s before line 2 switches to the latched verdict —
gating only the displayed string, not the verdict/LED/7-seg path (those still
latch in under 1 ms). The heartbeat `*` blinks in **every** state.

`KEY[0]` restarts the demo and re-runs the LCD init. The same shared controller
serves the 12.5 MHz decoder demo too — every HD44780 timing delay is
counter-based and scaled from `CLK_HZ`. The LCD bus is write-only (`LCD_RW` tied
`0`), and `LCD_ON`/`LCD_BLON` are driven `1`. The LCD pins are the **canonical
Terasic DE2 user-manual pins** and **must be cross-checked against the DE2 user
manual before programming real hardware** (stage 4).

The `LEDR[0]`/`HEX0` and `HEX1` pin locations are copied **verbatim** from the
verified `crc8_de2.qsf`. `CLOCK_50`, `KEY`, and `LEDG` use the canonical
Terasic DE2 user-manual pins. As with crc8, the pinout **must be cross-checked
against the Terasic DE2 user manual before programming real hardware**
(stage 5).

## Build (Quartus II 13.0sp1, no board needed)

```bash
cd hdl/boards/de2
C:\altera\13.0sp1\quartus\bin64\quartus_sh --flow compile tx_chain_de2
```

Produces `output_files/tx_chain_de2.sof` (gitignored). Expect ~12 of 105 M4K
blocks, 0 multipliers, and Fmax ≥ 50 MHz on the `CLOCK_50` domain.

## Full-`K`=6144 synthesis-oracle fit (block-RAM inference proof)

The K=40 demo above only fits because its buffer depths are parameterized
*down* (`MAXK=64`, `DMAX=64`, `KW_MAX=256`) so they fit as LE register fabric.
The real test is whether the **full-size** chain (`tx_chain_top` at its default
TS36.212 maxima `MAXK=6144`, `DMAX=6148`, `KW_MAX=18528`) fits the EP2C35 —
which it does **only because** the three TX buffers now infer Cyclone II M4K
block RAM (`add-fpga-block-ram-inference`, integrates #45/#46/#47).

This is verified with a minimal synthesis harness — `tx_chain_fullk_synth_top`
— that instantiates `tx_chain_top` at its default generics and folds its
ports to pins so nothing is optimized away. Compiled in a scratch dir under
Quartus II 13.0sp1 (`EP2C35F672C6`, VHDL-2008, 50 MHz `CLOCK_50`); the build
artifacts are not committed.

**Before → after (the inference fix headline):**

| Metric | Before (as LE logic) | After (M4K inferred) |
|--------|----------------------|----------------------|
| Total memory bits | `0` | `90,112 / 483,840` (19%) |
| M4K block RAM | `0 / 105` | `22 / 105` (21%) |
| Total logic elements | ~85,000 (2.5× over device — **did not fit**) | `1,716 / 33,216` (5%) — **fits** |
| Dedicated registers | (huge buffer flop banks) | `605` |
| Embedded multipliers | — | `2 / 70` (3%) — see note |
| Fmax (`CLOCK_50`) | — | **89.33 MHz** (setup slack +8.805 ns, hold +0.391 ns — **50 MHz closes**) |

The 22 M4K decompose exactly as the per-core stage fits predicted:
`circular_buffer` `w_sys`/`w_ev`/`w_od` = 12, `rate_matching_top`
`d1`/`d2`/`d3buf` = 6, `turbo_encode_top` `buf_a`/`buf_b` (dual-copy) = 4. All
inferred as `altsyncram` simple-dual-port (no explicit primitive / no fallback).

> **Multiplier note.** At full `KW_MAX` the `circular_buffer` `N_cb`/`q` index
> arithmetic synthesizes 2 embedded 9-bit multipliers (`lpm_mult`), which the
> parameterized-down K=40 demo did not. They are unrelated to the M4K fix and
> trivial (2 of 70 DSP); the design still fits with large headroom. The
> divider-free `q`/`pos` recurrences are unchanged — this is the fitter mapping
> a width-dependent multiply to a DSP at full size rather than to LEs.

The functional bit-exactness gate is unchanged: all 14 cocotb/GHDL lanes PASS
against the committed golden vectors (byte-identical) with the integrated M4K
RTL.

## Program (stage 5 — requires the physical board)

```bash
C:\altera\13.0sp1\quartus\bin64\quartus_pgm -c USB-Blaster -m jtag -o "p;output_files/tx_chain_de2.sof"
```

Then watch `LEDG[0]` (PASS) light and `HEX1 HEX0` show `A5`.

### On-board result — PASS (2026-05-23)

Run on real hardware: the DE2 (Cyclone II `EP2C35F672C6`) was programmed over
USB-Blaster JTAG with the above command — *"Configuration succeeded -- 1
device(s) configured, 0 errors"* — and the on-chip self-check reported
**HEX = A5 with LEDG[0] green = PASS**. The on-board hardened `tx_chain_top`
therefore reproduced the committed `tx_chain` golden vector (K=40, N_ref=0,
I_LBRM=0, rv=0, E=400) bit-for-bit on silicon.

## GHDL self-check (sim gate — no Quartus needed)

The cocotb lane under `hdl/sim/tx_chain_de2/` elaborates `tx_chain_de2_top` and
runs it to a verdict:

```bash
source scripts/hdl_env.sh
cd hdl/sim/tx_chain_de2
make                       # case 1: real golden vector -> self-check PASS
python test_runner.py      # both cases: PASS on golden, FAIL on a flipped bit
```

`test_runner.py` runs the lane twice: once with the default `CORRUPT_IDX=-1`
(real behaviour, must reach **PASS**), and once with `CORRUPT_IDX=5` (one
expected bit flipped, must reach **FAIL**) — proving the comparator actually
checks. `CORRUPT_IDX` is a TEST-ONLY generic; the synthesized board uses the
default and never corrupts.

`make` alone runs only the PASS case and is the entry point picked up by
`scripts/run_all_hdl_lanes.sh`.
