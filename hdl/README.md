# HDL workspace

This tree is the simulator-first FPGA exploration area for the MATLAB turbo-code model.

- `rtl/` contains board-neutral synthesizable VHDL cores.
- `sim/` contains simulator harnesses and cocotb tests.
- `smoke/` contains tiny GHDL-only checks for validating local tooling.
- `vectors/` contains generated golden vectors derived from MATLAB/Octave helpers.
- `boards/` contains board-specific notes and future wrappers for Altera DE1/DE2 bring-up.

