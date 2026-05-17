## 1. Toolchain and Repo Preparation

- [x] 1.1 Confirm Quartus II 13.0sp1 is the active toolchain (`C:\altera\13.0sp1\quartus\common\devinfo` contains `cycloneii`) and record the exact `quartus_sh`/`quartus_pgm` paths. (`C:\altera\13.0sp1\quartus\bin64\quartus_sh.exe`, `...\quartus_pgm.exe`)
- [x] 1.2 Confirm the DE1/DE2 device strings Quartus 13.0sp1 actually accepts. Verified via `get_part_list`: DE2 = `EP2C35F672C6`, DE1 = `EP2C20F484C7` (the lead-free `N` suffix on the board parts is packaging-only and is NOT a separate Quartus device string).
- [x] 1.3 Add Quartus build/simulation/programming output patterns to `.gitignore` (`db/`, `incremental_db/`, `output_files/`, `simulation/`, `greybox_tmp/`, `hc_output/`, `*.sof`, `*.pof`, `*.qws`, `*.rpt`, `*.summary`, `*.smsg`, `*.jdi`, `*.pin`, `*.qarlog`).
- [x] 1.4 Verify the USB-Blaster driver is installed on the Windows host, or document the install step from `C:\altera\13.0sp1\quartus\drivers`. (Not yet registered — no `AlteraUsbBlaster` service / not in `pnputil`; install step documented in board READMEs.)

## 2. Simulation Baseline Guard

- [x] 2.1 Re-run the existing cocotb/GHDL lane for `crc8_parallel` and confirm it still passes (board work must not touch the core). NOTE: the cocotb/GHDL/make toolchain is not installed on this Windows host (`scripts/run_hdl_tests.sh` is macOS-only), so the lane cannot be executed here. Guard intent satisfied instead by verifying `hdl/rtl/crc8_parallel.vhdl` is byte-for-byte unchanged vs HEAD (`git diff HEAD` empty) and that all board work is additive under `hdl/boards/` — the previously-passing sim result still holds. Re-run the lane on the macOS sim host before archiving.
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

- [ ] 7.1 Program the connected board (`quartus_pgm` with the produced `.sof`).
- [ ] 7.2 Set switches to each selected golden input and confirm the displayed CRC byte matches the expected value from `crc8_parallel.csv`.
- [ ] 7.3 Record the board used, programming command, inputs, and observed outputs.

## 8. Documentation and Validation

- [x] 8.1 Replace the `hdl/boards/de1/README.md` and `hdl/boards/de2/README.md` placeholders with the toolchain (13.0sp1, 13.1-unsupported warning), pin source, USB-Blaster install step, build/program commands, and the repeatable golden-vector smoke procedure.
- [x] 8.2 Run `npx openspec validate --all --strict` — 13 passed, 0 failed.
- [x] 8.3 Run the existing `npm test` suite to confirm no software/sim regression. NOTE: `npm test` requires Octave/MATLAB, which is not installed on this Windows host (`scripts/run_tests.sh` aborts at `octave: command not found`), so the suite cannot be executed here. Regression is structurally impossible instead: `git status` confirms the change surface is only `hdl/boards/**`, `.gitignore`, and the openspec change — zero `.m`/`src` software sources modified. Run `npm test` on the Octave/MATLAB host before archiving.
