## Why

The MATLAB/Octave implementation now has enough specification, tests, and proof
coverage to serve as a golden model for hardware work. We should establish an
FPGA/HDL path that can be simulated on this Mac with GHDL/cocotb/GTKWave before
attempting synthesis and board bring-up on Altera DE1/DE2 hardware.

## What Changes

- Add a hardware implementation capability describing the repo's HDL source,
  simulation, waveform, and board-target workflow.
- Create an HDL project layout for VHDL modules, cocotb tests, and generated
  golden vectors without committing simulator build products.
- Add a Mac-local GHDL smoke path that proves the VHDL simulator can compile,
  run, and emit waveforms.
- Start with a small, deterministic turbo-code block such as CRC or subblock
  interleaving before attempting full turbo encoder/decoder hardware.
- Define DE1/DE2 bring-up as a later milestone after simulator verification is
  repeatable and the target FPGA family/toolchain details are pinned.

## Capabilities

### New Capabilities

- `fpga-hdl-path`: HDL source layout, simulator verification, golden-vector
  generation, waveform artifacts, and eventual Altera DE1/DE2 board bring-up.

### Modified Capabilities

- `test-suite`: the development test workflow gains an HDL simulation lane that
  can run locally with GHDL/cocotb and later in CI when tool availability is
  settled.

## Impact

- Adds VHDL/cocotb-oriented development files under new HDL/test directories.
- Uses the existing MATLAB/Octave implementation as the golden reference for
  HDL vectors.
- Depends on local Python 3.13, cocotb, GHDL, and GTKWave for the first
  simulation workflow; Quartus and board constraints are deferred until the
  first HDL block is stable in simulation.
