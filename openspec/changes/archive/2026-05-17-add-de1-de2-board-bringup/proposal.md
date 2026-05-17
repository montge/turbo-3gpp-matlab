## Why

The `add-fpga-hdl-path` change established a simulator-verified board-neutral
HDL core (`crc8_parallel`) but deliberately deferred all Quartus project,
pin-constraint, and on-board programming work (its task 4.4) until the core was
stable and a real toolchain host was available. That host now exists: a Windows
machine with Quartus II 13.0sp1 installed, which is the last Quartus version
that supports the Cyclone II parts on the DE1/DE2 boards. This change turns the
deferred milestone into an actual board bring-up.

## What Changes

- Add a Quartus II 13.0sp1 project for the DE2 (`EP2C35F672C6N`) and DE1
  (`EP2C20F484C7N`) boards that synthesizes the existing verified
  `hdl/rtl/crc8_parallel.vhdl` core without modifying or forking it.
- Add board wrapper entities under `hdl/boards/de2/` and `hdl/boards/de1/`
  that instantiate the board-neutral core and adapt it to each board's
  switches, keys, LEDs, and seven-segment displays.
- Add pin-location and timing (SDC) constraints per board, kept isolated from
  the portable core per the existing `fpga-hdl-path` layout requirement.
- Define a manual program-and-observe smoke test: drive a known input via
  switches/keys, program the `.sof`, and confirm the displayed CRC matches the
  MATLAB/Octave golden value.
- Extend `.gitignore` so Quartus build/program outputs (`db/`,
  `incremental_db/`, `output_files/`, `*.sof`, `*.pof`, `*.qws`, etc.) are
  never committed.
- Pin and document the toolchain: Quartus II 13.0sp1 only; record that 13.1
  cannot target Cyclone II so future hosts do not regress.

## Capabilities

### New Capabilities

- `fpga-board-bringup`: Quartus project layout and toolchain pinning, per-board
  wrappers that reuse the verified core, pin/timing constraints isolated from
  the portable core, gitignored build artifacts, and a manual on-board
  program-and-observe smoke test validated against the software golden model.

### Modified Capabilities

<!-- None. This change fulfills the deferred "DE1/DE2 bring-up follows
     simulator verification" requirement from add-fpga-hdl-path without
     altering any existing spec-level requirements. -->

## Impact

- New files under `hdl/boards/de1/` and `hdl/boards/de2/` (wrappers, Quartus
  `.qpf`/`.qsf`, pin and SDC constraints, board-specific README).
- No changes to `hdl/rtl/crc8_parallel.vhdl` or the cocotb simulation lane;
  the synthesizable core stays board-neutral.
- `.gitignore` gains Quartus artifact patterns.
- Depends on Quartus II 13.0sp1 (`C:\altera\13.0sp1`); board synthesis and
  programming remain a local/manual step, not a CI lane, until tool licensing
  and automation are settled.
- Requires physical DE1 and/or DE2 hardware only for the final program-and-
  observe step; synthesis and timing closure can be checked without a board.
