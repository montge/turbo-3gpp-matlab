## Why

The FPGA path is proven end-to-end: a board-neutral core (`crc8_parallel`) is
simulator-verified against the MATLAB/Octave golden model and confirmed on real
DE2 Cyclone II silicon. The next meaningful increment of the actual project on
hardware is the transmit datapath — the rate-1/3 turbo encoder of TS36.212
§5.1.3.2. It is deterministic and bit-level (no fixed-point), so it can be
verified exhaustively in simulation against the existing software encoder before
any board work, exactly like CRC8.

## What Changes

- Add a board-neutral synthesizable VHDL turbo-encoder core under `hdl/rtl/`:
  - a reusable recursive-systematic constituent encoder (3 memory elements,
    generator `[1,1,0,1]`, feedback `[1,0,1,1]`) with the 3-step trellis
    termination;
  - a top core that runs two constituent encoders (original and interleaved
    order) and emits the `3 × (K+4)` systematic/parity1/parity2 layout,
    including the four termination columns, matching the software
    `turbo_encoder(c, pi)` contract bit-for-bit.
- The core **receives the interleaver order** (mirroring the software
  `turbo_encoder(c, pi)` signature); QPP/`internal-interleaver` address
  generation in hardware stays a separate future block — keeping this change
  K-agnostic and bounded.
- Add a cocotb/GHDL simulation lane `hdl/sim/turbo_encoder/` driven by golden
  vectors generated from the existing MATLAB/Octave turbo-encoder and
  internal-interleaver helpers (`hdl/vectors/turbo_encoder*.csv`), reusing the
  now-Windows-capable HDL test harness.
- Add a minimal, OPTIONAL/deferred DE2 switches→LEDs/HEX smoke (a small fixed
  block, signature of the encoded output on HEX) in the same style as the CRC
  demo — hardware-gated, not required for this change to be complete. No
  screen/VGA.

## Capabilities

### New Capabilities

- `fpga-turbo-encoder`: HDL constituent + turbo-encoder core that reproduces the
  TS36.212 §5.1.3.2 `turbo_encoder(c, pi)` behavior bit-for-bit, its
  golden-vector simulation lane, and an optional deferred board smoke.

### Modified Capabilities

<!-- None. Reuses the existing fpga-hdl-path layout/methodology and
     fpga-board-bringup pattern without changing their requirements; the
     software turbo-encoder / internal-interleaver specs are unchanged (used
     only as the golden reference). -->

## Impact

- New files under `hdl/rtl/` (constituent + turbo encoder cores), a generator
  for `hdl/vectors/turbo_encoder*.csv` using existing public MATLAB/Octave
  helpers, and `hdl/sim/turbo_encoder/` cocotb tests.
- No changes to existing MATLAB/Octave sources, the CRC core, or the
  fpga-hdl-path / fpga-board-bringup specs; the software encoder is the golden
  reference only.
- Reuses the existing `hdl/` layout, the `scripts/run_hdl_tests.sh` lane
  (already cross-platform), and the golden-vector methodology.
- Explicit non-goals: no turbo decoder, no rate matching, no code-block
  segmentation, no fixed-point arithmetic, no in-hardware QPP generation, and
  no filler/`NaN` handling (v1 encodes concrete full code blocks).
