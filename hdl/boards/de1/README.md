# Altera DE1 — crc8 board smoke

Board wrapper that runs the simulator-verified `crc8_parallel` core on a
Terasic DE1 (Cyclone II). The core in `hdl/rtl/crc8_parallel.vhdl` is
instantiated unmodified; this directory only adds board-adaptation logic,
the Quartus project, and constraints.

## Target and toolchain

- **FPGA:** Cyclone II `EP2C20F484C7` — board marking is `EP2C20F484C7N`;
  the lead-free `N` suffix is packaging-only and is **not** a separate
  Quartus device string.
- **Toolchain:** Quartus II **13.0sp1** only.
  **Quartus II 13.1 cannot target Cyclone II** (it dropped the device
  family); do not use it for this board.
- Tools: `C:\altera\13.0sp1\quartus\bin64\quartus_sh.exe`,
  `...\quartus_pgm.exe`.

## I/O mapping

The DE1 has only 10 toggle switches, so the demo uses an 8-bit,
zero-extended core input. A full 16-bit KEY-latched loader is a possible
follow-on and is intentionally out of scope here.

| Signal | Board | Use |
|--------|-------|-----|
| `SW[7:0]` | toggle switches `SW0..SW7` | low byte of `data_i`; high byte = 0 |
| `HEX1`,`HEX0` | seven-segment (active low) | 8-bit CRC as two hex digits |
| `LEDR[7:0]` | red LEDs | 8-bit CRC mirror |

Pin locations in `crc8_de1.qsf` are the canonical Terasic DE1 pinout. They
are valid package pins (synthesis/fitting succeed without a board) but
**must be cross-checked against the Terasic DE1 user manual before
programming hardware**.

## Build

```
cd hdl/boards/de1
C:\altera\13.0sp1\quartus\bin64\quartus_sh --flow compile crc8_de1
```

Produces `output_files/crc8_de1.sof` (gitignored).

## Program (requires the physical board)

The USB-Blaster driver is **not yet registered** on this host. Install it
once via Windows Device Manager pointing at
`C:\altera\13.0sp1\quartus\drivers\usb-blaster` (or `usb-blaster-ii`) when
the board is first connected.

```
C:\altera\13.0sp1\quartus\bin64\quartus_pgm -m jtag -o "p;output_files/crc8_de1.sof"
```

## Golden-vector smoke

Set switches to the input (switch up = `1`, `SW[n]` = bit `n`, `SW[0]` = LSB)
and read the two hex digits on `HEX1 HEX0`. Inputs are limited to one byte
because only 8 switches feed the core; expected values are the matching
rows of `hdl/vectors/crc8_parallel.csv` (the same golden model the
simulator uses):

| `SW[7:0]` (hex) | `data_i` | Expected `HEX1 HEX0` |
|-----------------|----------|----------------------|
| `00` | `0x0000` | `00` |
| `01` | `0x0001` | `9B` |
| `FF` | `0x00FF` | `7B` |

A match confirms the on-board core agrees with the MATLAB/Octave golden
model.
