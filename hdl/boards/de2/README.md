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

```
cd hdl/boards/de2
C:\altera\13.0sp1\quartus\bin64\quartus_sh --flow compile crc8_de2
```

Produces `output_files/crc8_de2.sof` (gitignored).

## Program (requires the physical board)

The USB-Blaster driver is **not yet registered** on this host. Install it
once via Windows Device Manager pointing at
`C:\altera\13.0sp1\quartus\drivers\usb-blaster` (or `usb-blaster-ii`) when
the board is first connected.

```
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
