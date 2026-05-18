## Why

The complete LTE transmit chain is sim-verified in HDL. The decoder is the
next major effort and is fundamentally harder: it is soft/LLR/floating-point,
so the HDL must be fixed-point and **cannot** be bit-exact to
`constituent_decoder.m`. This change delivers the keystone first increment
(P1) of the staged decoder plan in `hdl/docs/decoder_roadmap.md`: a
fixed-point Max-Log-MAP **constituent Log-BCJR** core plus the new two-tier
verification methodology it requires. It mirrors `constituent_encoder` →
`turbo_encoder` (standalone core before the iterative loop).

## What Changes

- Add an Octave **fixed-point Max-Log-MAP reference** for the constituent
  Log-BCJR (`constituent_decoder`): identical quantization, per-step
  max-normalization, saturation, and fixed operation order the HDL will use.
- Add a **characterization harness**: hard-decision agreement / BER of the
  fixed-point reference vs the float `constituent_decoder.m` over
  encode→BPSK+AWGN→LLR frames at representative SNRs, asserting a documented
  band (not a brittle per-commit gate).
- Add a board-neutral synthesizable VHDL **`constituent_decoder` core**:
  γ branch metrics from the 16 trellis transitions, α forward recursion
  (+max-norm), β backward recursion (+max-norm), extrinsic
  `x_e = max(δ|x=0) − max(δ|x=1)`; Max-Log-MAP; full-block α storage;
  streaming `(x_a,z_a)` in → `x_e` out (length `K+3`).
- Add a cocotb/GHDL lane that checks the HDL **bit-exact** against the
  fixed-point reference golden vectors (the existing inner-gate discipline).
- Defer (later roadmap increments): iterative turbo loop, interleaver
  integration, CRC early termination, HARQ, filler/`NaN`, exact Log-MAP LUT,
  sliding-window/BRAM, board demo. No board work. No screen.

## Capabilities

### New Capabilities

- `fpga-constituent-decoder`: the fixed-point Max-Log-MAP constituent Log-BCJR
  HDL core, its fixed-point reference model, the two-tier verification
  (inner bit-exact + outer BER characterization), and its golden-vector lane.

### Modified Capabilities

<!-- None. New cores only; the software constituent_decoder.m and the
     turbo-decoder spec are unchanged (used as the float reference). -->

## Impact

- New files under `hdl/rtl/` (constituent decoder), a fixed-point reference +
  characterization generator under `scripts/`, golden vectors under
  `hdl/vectors/`, and a `hdl/sim/constituent_decoder/` cocotb lane.
- No changes to MATLAB/Octave sources or prior specs/cores.
- Reuses the cross-platform HDL harness and the generator→CSV→cocotb pattern;
  introduces the documented two-tier oracle for soft/fixed-point blocks.
- Explicit non-goals per `hdl/docs/decoder_roadmap.md` §3 (P1 boundary):
  no iterative loop, CRC, HARQ, filler, exact Log-MAP, sliding-window, board.
