# Altera DE2 — tx_chain_top board self-check demo (K=40)

Board demo that runs the synthesis-hardened LTE transmit chain
(`turbo_encode_top -> rate_matching_top`, i.e. `hdl/rtl/tx_chain_top.vhdl`) on
a Terasic DE2 (Cyclone II `EP2C35F672C6`) and self-verifies it on-chip against
a committed golden vector. The core is instantiated **unmodified**; this
directory adds only the board wrapper, an on-chip golden ROM, a self-check FSM,
the Quartus project, and constraints.

This is **stage 3** of `add-fpga-tx-chain-de2-demo`: the synthesizable wrapper
+ a GHDL self-check that is sim-clean and ready to open in Quartus. Stage 4
(Quartus fit + TimeQuest closure) and stage 5 (on-board program + observe) are
the next steps and need the toolchain / physical board.

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

Seven-segment status code (via the shared `hdl/boards/hex7seg.vhdl` nibble
decoder, so glyphs are the hex set):

| state | `HEX1 HEX0` |
|-------|-------------|
| running | `0 0` |
| **pass** | `A 5` |
| **fail** | `F F` |

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

## Program (stage 5 — requires the physical board)

```bash
C:\altera\13.0sp1\quartus\bin64\quartus_pgm -m jtag -o "p;output_files/tx_chain_de2.sof"
```

Then watch `LEDG[0]` (PASS) light and `HEX1 HEX0` show `A5`.

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
