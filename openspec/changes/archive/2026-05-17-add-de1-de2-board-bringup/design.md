## Context

`add-fpga-hdl-path` produced a board-neutral, simulator-verified core at
`hdl/rtl/crc8_parallel.vhdl`: a purely combinational entity with
`data_i : in std_logic_vector(15 downto 0)` and
`crc_o : out std_logic_vector(7 downto 0)`, checked by cocotb against
`hdl/vectors/crc8_parallel.csv` golden vectors generated from the MATLAB/Octave
implementation. `hdl/boards/de1/` and `hdl/boards/de2/` exist as placeholders.

The toolchain host is now a Windows machine with Quartus II **13.0sp1** at
`C:\altera\13.0sp1` (its `quartus/common/devinfo` includes `cycloneii`).
Quartus II 13.1 is also present but dropped Cyclone II support and must not be
used for these boards. Target devices: DE2 = `EP2C35F672C6N`, DE1 =
`EP2C20F484C7N` (Quartus may list the DE1 part without the lead-free `N`
suffix as `EP2C20F484C7`).

Board I/O differs materially:
- **DE2**: 18 toggle switches `SW[17:0]`, 18 red + 9 green LEDs, 8 seven-seg
  digits `HEX0..HEX7`, 50 MHz `CLOCK_50`.
- **DE1**: only 10 toggle switches `SW[9:0]`, 4 keys `KEY[3:0]`, 10 red + 8
  green LEDs, 4 seven-seg digits `HEX0..HEX3`, 50 MHz `CLOCK_50`.

## Goals / Non-Goals

**Goals:**

- Synthesize the existing `crc8_parallel` core for DE2 and DE1 under Quartus II
  13.0sp1 without editing or forking the core.
- Provide per-board wrapper top entities that map board pins to the core and
  expose the CRC result on observable outputs.
- Keep pin/timing constraints and Quartus project files isolated under
  `hdl/boards/<board>/`, never leaking into `hdl/rtl/`.
- Cross-check on-board output against the same `crc8_parallel.csv` golden
  vectors the simulator uses.
- Pin the toolchain and record the 13.1 incompatibility so the host cannot
  silently regress.

**Non-Goals:**

- No turbo encoder/decoder hardware; the smoke target stays the CRC core.
- No CI synthesis lane; board synthesis/programming is local/manual.
- No NIOS/soft-CPU, no SignalTap requirement (optional debugging only).
- Do not require both physical boards; either DE1 or DE2 satisfies the
  program-and-observe step. Synthesis and timing closure need no hardware.

## Decisions

1. **Wrapper instantiates the core as an unmodified component.**
   Each board top entity (`crc8_de2_top`, `crc8_de1_top`) declares
   `crc8_parallel` as a component and wires board pins to its ports. The
   synthesizable core file is added to the Quartus project read-only; zero
   edits to `hdl/rtl/`. This satisfies the `fpga-hdl-path` "board smoke test
   reuses a verified core" requirement structurally, not by convention.

2. **Keep the board demo combinational (no capture registers) for v1.**
   - **DE2**: `data_i <= SW(15 downto 0)` directly; `crc_o` shown as two hex
     digits on `HEX1`/`HEX0` and mirrored on `LEDR(7:0)`.
   - **DE1**: only 10 switches, so drive `data_i <= (15 downto 8 => '0') &
     SW(7 downto 0)` — an 8-bit zero-extended input. This still exercises the
     real CRC generator matrix end-to-end; CRC shown on `HEX1`/`HEX0` and
     `LEDR(7:0)`.
   Alternative considered: a KEY-latched two-byte loader on DE1 to reach the
   full 16-bit space. Rejected for v1 because it adds clocking, debounce, and
   edge-detect logic to the board layer — exactly the board-specific
   complexity the layout separation is meant to avoid. Documented as an
   optional follow-on, not in scope here.

3. **Seven-segment decode lives in the wrapper, not the core.**
   A small `hex7seg` helper (active-low segments, common on Terasic boards)
   converts each CRC nibble to `HEX` patterns. It is board-presentation logic
   and stays under `hdl/boards/`, keeping the core free of display concerns.

4. **Commit Quartus project + constraints, ignore all build outputs.**
   Commit `*.qpf`, `*.qsf` (device + `set_location_assignment` pins), `*.sdc`,
   and wrapper VHDL. Ignore `db/`, `incremental_db/`, `output_files/`,
   `simulation/`, `greybox_tmp/`, `hc_output/`, `*.sof`, `*.pof`, `*.qws`,
   `*.rpt`, `*.summary`, `*.smsg`, `*.jdi`, `*.pin`, `*.qarlog`. Add patterns
   before the first build and verify `git status` is clean afterward.

5. **Pin assignments sourced from Terasic manuals into the `.qsf`.**
   DE2/DE1 pin names are fixed by the Terasic user manuals already cited in
   PR #18. Encode them as `set_location_assignment` plus
   `set_instance_assignment ... -name IO_STANDARD "3.3-V LVTTL"`. Set unused
   pins to "As input tri-stated" (Quartus default) so the wrapper never drives
   conflicting board nets.

6. **Minimal SDC for a combinational design.**
   No functional clock is used in v1. The `.sdc` declares
   `derive_clock_uncertainty` and `set_false_path` from `SW*`/`KEY*` inputs and
   to `LEDR*`/`HEX*` outputs (asynchronous human-driven I/O). This documents
   intent and keeps TimeQuest from flagging unconstrained paths.

7. **Golden cross-check uses existing simulator vectors.**
   Pick fixed rows from `hdl/vectors/crc8_parallel.csv`; set switches to the
   input, read the displayed CRC byte, and confirm it equals the expected
   column. The board is validated against the same golden model as the
   simulator — no new expected-value source.

8. **Toolchain pinned and documented.**
   A board README records the exact host paths
   (`C:\altera\13.0sp1\quartus\bin64\quartus_sh`,
   `quartus_pgm`), the device strings, the USB-Blaster prerequisite, and an
   explicit warning that 13.1 cannot target Cyclone II.

## Risks / Trade-offs

- **DE1 has only 10 switches** → cannot present the full 16-bit input path →
  mitigate with the 8-bit zero-extended demo (Decision 2); full-width input is
  a documented optional follow-on.
- **DE1 part suffix mismatch** (`EP2C20F484C7` vs `...C7N`) → Quartus may
  reject the wrong string → set the device exactly as Quartus 13.0sp1 lists it
  and record the working string in the board README.
- **Wrong pin assignment produces no/garbled output** (not destructive) →
  cross-check every pin against the Terasic manual; unused pins tri-stated.
- **No physical board at synthesis time** → split tasks so synthesis + timing
  closure are verifiable without hardware; the program-and-observe task is
  explicitly gated on a connected board.
- **Quartus artifacts accidentally committed** → add `.gitignore` patterns
  before the first compile and assert a clean `git status` as a task step.
- **USB-Blaster driver missing on Windows host** → `quartus_pgm` fails →
  listed as an explicit prerequisite-check task before programming.

## Open Questions

- Which board (DE1 vs DE2) is physically connected first? Default: implement
  both wrappers + projects; run the on-board smoke on whichever is attached.
- Is the USB-Blaster driver already installed on the Windows host, or does it
  need installation from `C:\altera\13.0sp1\quartus\drivers`?
