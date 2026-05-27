# Altera DE2 — crc8 board smoke

Board wrapper that runs the simulator-verified `crc8_parallel` core on a
Terasic DE2 (Cyclone II). The core in `hdl/rtl/crc8_parallel.vhdl` is
instantiated unmodified; this directory only adds board-adaptation logic,
the Quartus project, and constraints.

## Target and toolchain

- **FPGA:** Cyclone II `EP2C35F672C6` — board marking is `EP2C35F672C6N`;
  the lead-free `N` suffix is packaging-only and is **not** a separate
  Quartus device string.
- **Toolchain:** Quartus II **13.0sp1** only.
  **Quartus II 13.1 cannot target Cyclone II** (it dropped the device
  family); do not use it for this board.
- Tools: `C:\altera\13.0sp1\quartus\bin64\quartus_sh.exe`,
  `...\quartus_pgm.exe`.

## I/O mapping

| Signal | Board | Use |
|--------|-------|-----|
| `SW[15:0]` | toggle switches `SW0..SW15` | 16-bit core input `data_i` |
| `HEX1`,`HEX0` | seven-segment (active low) | 8-bit CRC as two hex digits |
| `LEDR[7:0]` | red LEDs | 8-bit CRC mirror |

Pin locations in `crc8_de2.qsf` are the canonical Terasic DE2 pinout. They
are valid package pins (synthesis/fitting succeed without a board) but
**must be cross-checked against the Terasic DE2 user manual before
programming hardware**.

## Build

```bash
cd hdl/boards/de2
C:\altera\13.0sp1\quartus\bin64\quartus_sh --flow compile crc8_de2
```

Produces `output_files/crc8_de2.sof` (gitignored).

## Program (requires the physical board)

The USB-Blaster driver is **not yet registered** on this host. Install it
once via Windows Device Manager pointing at
`C:\altera\13.0sp1\quartus\drivers\usb-blaster` (or `usb-blaster-ii`) when
the board is first connected.

```bash
C:\altera\13.0sp1\quartus\bin64\quartus_pgm -m jtag -o "p;output_files/crc8_de2.sof"
```

## Golden-vector smoke

Set switches to the input (switch up = `1`, `SW[n]` = bit `n`, `SW[0]` = LSB)
and read the two hex digits on `HEX1 HEX0`. Expected values are taken from
`hdl/vectors/crc8_parallel.csv` (the same golden model the simulator uses):

| `SW[15:0]` (hex) | Expected `HEX1 HEX0` |
|------------------|----------------------|
| `0000` | `00` |
| `1234` | `40` |
| `ACE1` | `96` |
| `FFFF` | `CA` |

A match confirms the on-board core agrees with the MATLAB/Octave golden
model.

## Other DE2 demos on this board

This directory also hosts two larger self-checking 3GPP demos that report on
the LEDs, the 7-seg, **and** the DE2's on-board 16x2 HD44780 character LCD:

- **`tx_chain_de2`** (`tx_chain_de2_top`, K=40, 50 MHz) — see
  `tx_chain_de2_README.md`.
- **`turbo_decoder_de2`** (`turbo_decoder_de2_top`, K=512, 12.5 MHz PLL) — see
  `turbo_decoder_de2_README.md`.

Both drive the LCD via the shared `../hd44780_lcd.vhdl` controller (a board
component, like `../hex7seg.vhdl`, referenced by each demo's `.qsf`; its
`CLK_HZ` generic scales all HD44780 delays so one core serves both clocks). The
LCD is **additive** — the LED/7-seg verdict is unchanged. It shows a fixed demo
label on line 1 (so you know which demo is loaded) and a live status on line 2:
`RUNNING` with an always-on blinking heartbeat (`*` in col 16), resolving to a
verdict that now carries the **output-bit error count**: the decoder shows
`PASS e=000 it=2*` / `FAIL e=NNN it=2*` (with the static configured
max-iterations `it=N`) and the TX demo shows `PASS err=000   *` /
`FAIL err=NNN   *`. The `CH_RUN` self-check counts every mismatch across the
full stream (saturating at 999) and latches the verdict at end-of-stream — PASS
iff the count is 0 and the framing is correct — so `e=NNN` proves the comparator
actually counted, not just tripped a flag. Digits are formatted by the shared
`lcd_format_pkg.uint_to_ascii` helper and registered one cycle off the divider
chain to keep the formatter clear of the LCD data register's timing path (this
is what holds the 50 MHz TX demo's setup slack positive). Because the self-check
latches its
verdict in under 1 ms, the `RUNNING` *display* is deliberately **held a minimum
~1.5 s** (a display-state timer sized as `(3 × CLK_HZ) / 2` cycles, reloaded on
each `KEY[0]` start) so a human can actually see it; this gates only the LCD
string, not the verdict/LED/7-seg path. The heartbeat `*` blinks in every state.
The LCD pins are the canonical Terasic DE2 user-manual pins and must
be cross-checked against the DE2 user manual before programming real hardware.
