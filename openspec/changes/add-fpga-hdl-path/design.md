## Context

The repository currently implements the 3GPP LTE turbo coding chain in
MATLAB/Octave with OpenSpec requirements, MOxUnit tests, property tests, and
formal proof artifacts. The new local tooling gives us a practical HDL
simulation path on macOS: GHDL 6.0.0, GTKWave, Python 3.13, and cocotb 2.0.1.

The hardware goal should be staged. A full turbo decoder is the hardest part of
the system because it needs fixed-point Log-BCJR arithmetic, memory scheduling,
iteration control, and throughput/resource trade-offs. The first useful FPGA
step is a simulator-verified HDL path plus one small block whose behavior can be
checked against the existing MATLAB/Octave golden model.

## Goals / Non-Goals

**Goals:**

- Establish a repo-native HDL layout for VHDL source, cocotb tests, generated
  golden vectors, and waveform outputs.
- Prove GHDL/cocotb can run locally on macOS and produce waveforms that GTKWave
  can inspect.
- Use MATLAB/Octave as the golden-vector source for HDL tests.
- Implement the first hardware block behind a small, explicit interface before
  expanding toward encoder/decoder subsystems.
- Keep DE1/DE2 board work visible in the plan while deferring Quartus-specific
  constraints until the first HDL simulation target is stable.

**Non-Goals:**

- Do not attempt to auto-convert the full MATLAB codebase into synthesizable HDL.
- Do not implement the full turbo decoder in the first hardware milestone.
- Do not commit generated waveforms, simulator work directories, Quartus output,
  or board programming artifacts.
- Do not require DE1/DE2 hardware to pass the initial Mac-local simulation tests.

## Decisions

1. **Use VHDL plus GHDL/cocotb for the first simulation lane.**

   GHDL is already working locally, cocotb is installed in the Python 3.13
   virtualenv, and VHDL keeps the path compatible with common Intel/Altera FPGA
   toolchains. A Verilog/SystemVerilog path can be added later if synthesis or
   board tooling makes it attractive.

2. **Use MATLAB/Octave-generated golden vectors instead of hand-authored
   expected values.**

   The existing implementation already has broad tests and specs. Golden-vector
   generation should call the same public helpers that software tests exercise,
   producing compact JSON/CSV/MAT-free fixtures suitable for cocotb.

3. **Start with CRC or subblock interleaving as the first HDL module.**

   Both are deterministic, bounded, and already covered by OpenSpec scenarios.
   CRC is attractive for a bit-serial/parallel hardware proof of concept.
   Subblock interleaving is attractive for memory-address generation. Either is
   materially safer than starting with Log-BCJR decoding.

4. **Keep board bring-up separate from simulator correctness.**

   DE1 and DE2 boards differ in device family, memory, clocks, switches/LEDs,
   and Quartus project details. The initial HDL should have a simulator-facing
   testbench first; board wrappers can later adapt the same core to a specific
   board target.

5. **Target the observed DE2 / Cyclone II board first.**

   The available board has a Cyclone II `EP2C35F672C6N` marking on the FPGA.
   That matches the original Terasic/Altera DE2 class of board, whose public
   materials list a Cyclone II `EP2C35F672C6` FPGA. Treat this as the first
   hardware bring-up target and keep DE1/DE2-70 variants out of scope until a
   second physical board is identified.

6. **Use Quartus II 13.0sp1 on Windows or Linux for synthesis.**

   Intel's device-support table lists Cyclone II support through Quartus II
   `13.0sp1` for Windows/Linux. Current macOS work should remain
   simulator-first with GHDL/cocotb/GTKWave; Quartus synthesis/programming will
   need a Windows/Linux host, VM, or later self-hosted runner with the legacy
   toolchain installed.

## Risks / Trade-offs

- **Fixed-point behavior can diverge from MATLAB doubles** -> Delay decoder HDL
  until the small-block flow proves vector generation, simulation, and waveform
  inspection. Add explicit fixed-point specs before decoder work.
- **cocotb/GHDL version drift can break tests** -> Pin cocotb in
  `requirements-dev.txt` and document the GHDL version used for local smoke
  tests.
- **Board-specific work can leak into portable cores** -> Keep synthesizable
  cores under a board-neutral path and isolate DE1/DE2 wrappers/constraints.
- **Generated artifacts can clutter the repo** -> Use `.gitignore` patterns for
  waveform files, simulator work products, and build directories.
- **Quartus availability is not guaranteed in CI** -> Treat board synthesis as a
  local/manual or later self-hosted runner step until tool licensing and
  automation are understood.

## Open Questions

- Should Quartus run on a Windows/Linux VM from this Mac, or on a separate
  Windows/Linux host attached to the DE2 USB-Blaster?
- Should the first HDL module be CRC calculation or subblock interleaver address
  generation?
- Should golden vectors be stored as checked-in fixtures for small cases or
  generated on demand during tests?
