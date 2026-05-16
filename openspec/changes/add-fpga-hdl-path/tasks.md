## 1. Tooling and Layout

- [ ] 1.1 Create an `hdl/` source layout with board-neutral core, simulation, generated-vector, and board-wrapper locations.
- [ ] 1.2 Add a local HDL simulation command or script that checks for GHDL and cocotb and prints actionable setup guidance when either is missing.
- [ ] 1.3 Add a minimal GHDL smoke module/testbench that can run on macOS and emit an ignored waveform artifact.
- [ ] 1.4 Document the local HDL workflow, including Python 3.13 virtualenv activation, cocotb install, GHDL use, and GTKWave waveform inspection.

## 2. Golden Model and First HDL Block

- [ ] 2.1 Choose the first HDL implementation target: CRC calculation or subblock interleaver ordering/address generation.
- [ ] 2.2 Add a MATLAB/Octave golden-vector generator for the chosen block using existing public helpers.
- [ ] 2.3 Implement the first synthesizable VHDL core with a small, explicit simulator-facing interface.
- [ ] 2.4 Add cocotb tests that drive the VHDL core with golden vectors and compare every output value.
- [ ] 2.5 Confirm simulator output can produce a VCD, GHW, or FST waveform that is ignored by git and readable by GTKWave.

## 3. Verification Integration

- [ ] 3.1 Add an HDL simulation test lane that is separate from the existing MATLAB/Octave and proof checks.
- [ ] 3.2 Run `npx openspec validate --all --strict`.
- [ ] 3.3 Run the existing `npm test` suite to ensure the HDL workflow did not regress software behavior.
- [ ] 3.4 Run the new HDL simulation command locally with GHDL and cocotb.

## 4. Board Bring-Up Planning

- [ ] 4.1 Identify the exact available Altera board variant and FPGA part number for DE1/DE2 work.
- [ ] 4.2 Identify a compatible Quartus version and document any macOS limitations or required alternate host.
- [ ] 4.3 Define the first board smoke interface, such as switches/keys feeding a small input and LEDs or seven-segment display showing status.
- [ ] 4.4 Defer Quartus project files and pin constraints until the simulator-verified HDL core is selected and stable.
