# HDL workspace

This tree is the simulator-first FPGA exploration area for the MATLAB turbo-code model.

- `rtl/` contains board-neutral synthesizable VHDL cores.
- `sim/` contains simulator harnesses and cocotb tests.
- `smoke/` contains tiny GHDL-only checks for validating local tooling.
- `vectors/` contains generated golden vectors derived from MATLAB/Octave helpers.
- `boards/` contains board-specific notes and future wrappers for Altera DE1/DE2 bring-up.
- `docs/` contains design notes and roadmaps (e.g. the turbo-decoder plan).

## Running the HDL lanes

`scripts/run_all_hdl_lanes.sh` discovers every `hdl/sim/*/` lane and runs it
with GHDL/cocotb against the **committed** golden vectors (no Octave/MATLAB
needed). It sources `scripts/hdl_env.sh` for the cross-platform venv/PATH shim
(Linux/macOS use `.venv/bin`; Windows binds GHDL's embedded Python). The CI
`hdl-sim` job runs this on every PR/push, so an HDL regression now fails a
gate — not just a local run.

```
bash scripts/run_all_hdl_lanes.sh
```

