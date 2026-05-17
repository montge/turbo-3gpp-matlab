## 1. Tooling and Layout

- [x] 1.1 Create an `hdl/` source layout with board-neutral core, simulation, generated-vector, and board-wrapper locations.
- [x] 1.2 Add a local HDL simulation command or script that checks for GHDL and cocotb and prints actionable setup guidance when either is missing.
- [x] 1.3 Add a minimal GHDL smoke module/testbench that can run on macOS and emit an ignored waveform artifact.
- [x] 1.4 Document the local HDL workflow, including Python 3.13 virtualenv activation, cocotb install, GHDL use, and GTKWave waveform inspection.

## 2. Golden Model and First HDL Block

- [x] 2.1 Choose the first HDL implementation target: CRC calculation or subblock interleaver ordering/address generation.
- [x] 2.2 Add a MATLAB/Octave golden-vector generator for the chosen block using existing public helpers.
- [x] 2.3 Implement the first synthesizable VHDL core with a small, explicit simulator-facing interface.
- [x] 2.4 Add cocotb tests that drive the VHDL core with golden vectors and compare every output value.
- [x] 2.5 Confirm simulator output can produce a VCD, GHW, or FST waveform that is ignored by git and readable by GTKWave.

## 3. Verification Integration

- [x] 3.1 Add an HDL simulation test lane that is separate from the existing MATLAB/Octave and proof checks.
- [x] 3.2 Run `npx openspec validate --all --strict`.
- [x] 3.3 Run the existing `npm test` suite to ensure the HDL workflow did not regress software behavior.
- [x] 3.4 Run the new HDL simulation command locally with GHDL and cocotb.

## 4. Board Bring-Up Planning

- [x] 4.1 Identify the exact available Altera board variant and FPGA part number for DE1/DE2 work.
- [x] 4.2 Identify a compatible Quartus version and document any macOS limitations or required alternate host.
- [x] 4.3 Define the first board smoke interface, such as switches/keys feeding a small input and LEDs or seven-segment display showing status.
- [x] 4.4 Defer Quartus project files and pin constraints until the simulator-verified HDL core is selected and stable.
