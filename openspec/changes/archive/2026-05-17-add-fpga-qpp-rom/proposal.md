## Why

The HDL turbo encoder and QPP interleaver are each sim-verified but both take
their per-`K` data externally (interleave / `d0`,`step`). Adding the
standardized `K → (f1,f2)` table as an HDL ROM closes that seam and lets the
three verified cores be wired into a **standalone hardware turbo-encode
datapath**: feed a code block + `K`, get the `3 × (K+4)` encoded matrix — the
first end-to-end LTE transmit-side operation the FPGA performs by itself. It
stays deterministic and fully golden-vector verifiable.

## What Changes

- Add a **generated** VHDL package holding the 188-entry TS36.212 Table
  5.1.3-3, single-sourced from `internal_interleaver.m`'s table (each row
  pre-reduced to `K`, `d0=(f1+f2) mod K`, `step=(2·f2) mod K`) — generated, not
  hand-typed, so it cannot drift from the standard.
- Add `hdl/rtl/qpp_rom.vhdl`: a small sequential lookup that maps an input `K`
  to `(d0, step)` with a `supported` flag (the 188 sizes are non-uniformly
  spaced, so a scan over the ROM, bounded by 188 cycles, is used).
- Add `hdl/rtl/turbo_encode_top.vhdl` integrating the three **unmodified**
  verified cores: an input block buffer feeds `qpp_interleaver` (constants from
  `qpp_rom`) and `turbo_encoder`, producing the encoded matrix from just
  `(K, code-block)`.
- Add cocotb/GHDL lanes: a `qpp_rom` unit lane (every supported `K` →
  correct `d0/step`; unsupported → `supported=0`) and an end-to-end lane that
  **reuses the existing `hdl/vectors/turbo_encoder.csv`** (drives only `K` and
  `c`, ignores `cprime`, checks the produced `d`).
- No on-board work (sim-first); any DE2 demo is an optional follow-on. No
  screen.

## Capabilities

### New Capabilities

- `fpga-qpp-rom`: the generated standardized parameter ROM, the `K → (d0,step)`
  lookup, and the integrated standalone turbo-encode datapath, all verified
  against the existing software golden model.

### Modified Capabilities

<!-- None. fpga-turbo-encoder and fpga-internal-interleaver cores are reused
     unmodified; their specs and the software model are unchanged. -->

## Impact

- New files under `hdl/rtl/` (generated ROM package, `qpp_rom`,
  `turbo_encode_top`), a ROM/golden generator using `internal_interleaver.m`,
  and `hdl/sim/qpp_rom/` + `hdl/sim/turbo_encode_top/` cocotb lanes.
- Reuses `qpp_interleaver.vhdl`, `turbo_encoder.vhdl`,
  `rsc_constituent_encoder.vhdl`, and `hdl/vectors/turbo_encoder.csv`
  unmodified.
- No changes to MATLAB/Octave sources or prior specs.
- Explicit non-goals: no decoder, no rate matching, no fixed-point, no board
  work; throughput/true-dual-port-BRAM optimization is a documented follow-on
  (v1 is correctness-first).
