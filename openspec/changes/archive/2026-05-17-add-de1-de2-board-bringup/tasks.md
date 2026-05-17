## 1. Toolchain and Repo Preparation

- [x] 1.1 Confirm Quartus II 13.0sp1 is the active toolchain (`C:\altera\13.0sp1\quartus\common\devinfo` contains `cycloneii`) and record the exact `quartus_sh`/`quartus_pgm` paths. (`C:\altera\13.0sp1\quartus\bin64\quartus_sh.exe`, `...\quartus_pgm.exe`)
- [x] 1.2 Confirm the DE1/DE2 device strings Quartus 13.0sp1 actually accepts. Verified via `get_part_list`: DE2 = `EP2C35F672C6`, DE1 = `EP2C20F484C7` (the lead-free `N` suffix on the board parts is packaging-only and is NOT a separate Quartus device string).
- [x] 1.3 Add Quartus build/simulation/programming output patterns to `.gitignore` (`db/`, `incremental_db/`, `output_files/`, `simulation/`, `greybox_tmp/`, `hc_output/`, `*.sof`, `*.pof`, `*.qws`, `*.rpt`, `*.summary`, `*.smsg`, `*.jdi`, `*.pin`, `*.qarlog`).
- [x] 1.4 Verify the USB-Blaster driver is installed on the Windows host, or document the install step from `C:\altera\13.0sp1\quartus\drivers`. (Not yet registered — no `AlteraUsbBlaster` service / not in `pnputil`; install step documented in board READMEs.)

## 2. Simulation Baseline Guard

- [x] 2.1 Re-run the existing cocotb/GHDL lane for `crc8_parallel` and confirm it still passes (board work must not touch the core). Toolchain installed on this Windows host: Python 3.13 venv + cocotb 2.0.1, GHDL 6.0.0 mcode (`winget ghdl.ghdl.ucrt64.mcode`), GNU make 4.4.1 (`winget ezwinports.make`). `scripts/run_hdl_tests.sh` made cross-platform (detects `.venv/Scripts` vs `.venv/bin`; on Windows sets `LIBPYTHON_LOC`/`PYGPI_PYTHON_BIN`/`PYTHONPATH` so GHDL's embedded interpreter resolves cocotb). `npm run test:hdl` result: `test_crc8_parallel.matches_matlab_crc8_golden_vectors PASS`, `TESTS=1 PASS=1 FAIL=0`, VCD written — sim guard verified on this host; core confirmed byte-for-byte unchanged vs HEAD.
- [x] 2.2 Select fixed golden rows from `hdl/vectors/crc8_parallel.csv` for the on-board smoke. DE2 (16-bit, `SW[15:0]`): `0x0000`→CRC `0x00`, `0x1234`→`0x40`, `0xACE1`→`0x96`, `0xFFFF`→`0xCA`. DE1 (8-bit `SW[7:0]`, inputs ≤`0xFF`): `0x00`→`0x00`, `0x01`→`0x9B`, `0xFF`→`0x7B`.

## 3. Board Presentation Helper

- [x] 3.1 Add a `hex7seg` nibble-to-seven-segment helper (active-low segments) under `hdl/boards/` shared by both wrappers. (`hdl/boards/hex7seg.vhdl`, VHDL-93-compatible selected assignment.)

## 4. DE2 Wrapper and Quartus Project

- [x] 4.1 Add `hdl/boards/de2/crc8_de2_top.vhdl` instantiating `crc8_parallel` with `data_i <= SW(15 downto 0)` and `crc_o` on `HEX1`/`HEX0` + `LEDR(7:0)`.
- [x] 4.2 Add the DE2 Quartus project (`.qpf`, `.qsf`) targeting `EP2C35F672C6` (non-`N` per task 1.2), including the core source path and `set_location_assignment` pins (canonical Terasic DE2 pinout) with default `3.3-V LVTTL`. Pins flagged in-file for manual cross-check before the hardware step.
- [x] 4.3 Add `hdl/boards/de2/crc8_de2.sdc` with `derive_clock_uncertainty` and `set_false_path` on async switch inputs / LED+HEX outputs.

## 5. DE1 Wrapper and Quartus Project

- [x] 5.1 Add `hdl/boards/de1/crc8_de1_top.vhdl` instantiating `crc8_parallel` with `data16 <= "00000000" & SW(7 downto 0)` and `crc_o` on `HEX1`/`HEX0` + `LEDR(7:0)`.
- [x] 5.2 Add the DE1 Quartus project (`.qpf`, `.qsf`) targeting `EP2C20F484C7` (non-`N` per task 1.2), including the core source path and `set_location_assignment` pins (canonical Terasic DE1 pinout) with default `3.3-V LVTTL`. Pins flagged in-file for manual cross-check before the hardware step.
- [x] 5.3 Add `hdl/boards/de1/crc8_de1.sdc` with `derive_clock_uncertainty` and `set_false_path` on async switch inputs / LED+HEX outputs.

## 6. Synthesis and Timing Closure (no board required)

- [x] 6.1 Compile the DE2 project under Quartus II 13.0sp1 — Full Compilation successful, 0 errors; `hdl/boards/de2/output_files/crc8_de2.sof` produced.
- [x] 6.2 Compile the DE1 project under Quartus II 13.0sp1 — Full Compilation successful, 0 errors; `hdl/boards/de1/output_files/crc8_de1.sof` produced.
- [x] 6.3 TimeQuest reports "Design is fully constrained for setup requirements" and "for hold requirements" for both; the only timing note is the expected "No clocks defined" for a purely combinational design — no unconstrained-path warnings.
- [x] 6.4 `git status` after both compiles shows only intended sources (`.qpf`/`.qsf`/`.sdc`/`*_top.vhdl`/`hex7seg.vhdl`); no `db/`, `output_files/`, `*.sof`, or report artifacts — `.gitignore` patterns verified effective.

## 7. On-Board Program-and-Observe Smoke (hardware-gated)

- [x] 7.1 Program the connected board. DE2 programmed via `quartus_pgm -c USB-Blaster -m jtag -o "p;output_files/crc8_de2.sof"` (13.0sp1): "Using cable USB-Blaster [USB-0]", device JTAG ID `0x020B40DD` (EP2C35), "Configuration succeeded -- 1 device(s) configured", 0 errors. NOTE (Win11 25H2 driver saga): the bundled 2013 SHA-1 USB-Blaster driver is blocked (`STATUS_DRIVER_BLOCKED`) by the enforced kernel CI policy — not fixable via Memory Integrity / vulnerable-driver-blocklist toggles. Resolved by installing the modern SHA-256 (FTDI-signed, v2.12.28) USB-Blaster driver from the standalone **Quartus Prime 25.1std Programmer (qdrivers)**, then **Disabling the auto-installed 25.1 `JTAGServer` Windows service** so 13.0sp1's own `jtagd` owns port 1309 (the 25.1 server is protocol-incompatible with the 13.0sp1 client). `jtagconfig` then shows `USB-Blaster [USB-0]` + `EP2C35`.
- [x] 7.2 Golden-vector smoke — on-board `HEX1 HEX0` matches `hdl/vectors/crc8_parallel.csv` for all four DE2 vectors: `0x0000`→`00`, `0xFFFF`→`CA`, `0x1234`→`40`, `0xACE1`→`96`. Pin cross-check resolved: the authoritative Terasic DE2 pin table is byte-identical to `crc8_de2.qsf` (SW/LEDR/HEX0/HEX1) — pins verified correct, no rebuild needed.
- [x] 7.3 Recorded: board = DE2 (Cyclone II `EP2C35F672C6`); cable = `USB-Blaster [USB-0]`; program cmd = `quartus_pgm -c USB-Blaster -m jtag -o "p;output_files/crc8_de2.sof"`; inputs/outputs per 7.2 (all 4 vectors pass). DE1 wrapper/project remain synthesis-verified only (no DE1 hardware) — acceptable per the change design (either board satisfies the smoke).

## 8. Documentation and Validation

- [x] 8.1 Replace the `hdl/boards/de1/README.md` and `hdl/boards/de2/README.md` placeholders with the toolchain (13.0sp1, 13.1-unsupported warning), pin source, USB-Blaster install step, build/program commands, and the repeatable golden-vector smoke procedure.
- [x] 8.2 Run `npx openspec validate --all --strict` — 13 passed, 0 failed.
- [x] 8.3 Run the existing `npm test` suite to confirm no software/sim regression. Octave 11.1.0 installed on this Windows host via `winget install --id GNU.Octave`; suite run with `OCTAVE_BIN="C:\Users\montg\AppData\Local\Programs\GNU Octave\Octave-11.1.0\mingw64\bin\octave-cli.exe" npm test` (no script change needed — `run_tests.sh` already honors `OCTAVE_BIN`). Result: `OK (passed=102)`, 0 failures — no software/sim regression from the board work, verified on this host.
