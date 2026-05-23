## Why

The fixed-point Max-Log-MAP **constituent decoder** (P1,
`add-fpga-constituent-decoder`) is implemented and sim-verified, but a single
non-iterative constituent decoder is a deliberately weak decoder — its absolute
BER is poor *by design* (the turbo gain is the iteration, not one BCJR pass).
This change delivers the next major decoder increment (**P2** of
`hdl/docs/decoder_roadmap.md`): the **iterative turbo-decode loop** that wraps
the existing P1 core, exchanging extrinsic information between an upper and a
lower constituent decoder through the QPP interleaver until a fixed number of
half-iterations completes. P2 is where the decoder first produces meaningful
communications performance, so BER-vs-SNR becomes a real (bounded) oracle for
the first time. The full data-flow algebra, half-iteration reframing, memory
map, FSM sketch, reuse list, and cycle budget are already worked out in
`hdl/docs/p2_turbo_loop_design_seed.md`; this change promotes that seed to a
formal OpenSpec change. It mirrors `turbo_encoder` wrapping
`constituent_encoder` (the standalone core landed first, the loop second) and
reuses the P1 core, `qpp_rom`, and `qpp_interleaver` **unmodified**.

## What Changes

- Add an Octave **fixed-point full-loop turbo-decoder reference**: the P1
  fixed-point constituent reference (`scripts/fixedpoint_constituent_decoder.m`)
  wrapped in the exact `turbo_decoder.m` loop algebra (de-mux of the
  `3×(K+4)` LLR matrix into upper `(x_a,z_a)` / lower `(x'_a,z'_a)`,
  `c_a=0` init, half-iteration upper → interleave → lower → de-interleave,
  hard decision `(c_a+c_e)<0`), pinning the extrinsic-exchange Q-format. This
  is the inner bit-exact oracle for the loop.
- Add a **bounded BER characterization harness**: encode→BPSK+AWGN→LLR frames
  at a few SNRs; assert the fixed-point turbo reference tracks float
  `turbo_decoder.m` within a documented dB margin (a trend/margin check, not a
  deep waterfall). BER is now meaningful because the loop iterates.
- Add a **golden-vector generator** for the full loop: realistic LLR frames,
  quantized, run through the fixed-point reference → `(K, max_iter, d_a, c)`
  golden CSV (plus optionally intermediate extrinsics for diagnostics).
- Add a board-neutral synthesizable VHDL **`turbo_decoder_top` core**: the
  half-iteration loop controller / FSM, the persistent (`z_a`, `z'_a`,
  `ch_sys`) and cyclic (`c_a`, `c_e`) LLR memories, the systematic-a-priori
  add (`x_a = c_a + ch_sys`), the interleave read / deinterleave scatter
  driving `qpp_rom`+`qpp_interleaver`, and the final hard decision — invoking
  the **P1 `constituent_decoder` core unmodified**, twice per full iteration.
- Add a cocotb/GHDL lane that checks the HDL **bit-exact** against the
  fixed-point turbo-decoder reference golden vectors (the existing inner-gate
  discipline), plus regression of all prior lanes.
- Reuse `constituent_decoder`, `qpp_rom`, and `qpp_interleaver` **unmodified**;
  fixed `max_iterations` (no early termination); one constituent instance
  (sequential upper→lower) for sim-first v1.

## Capabilities

### New Capabilities

- `fpga-turbo-decode-loop`: the iterative turbo-decode loop HDL core
  (`turbo_decoder_top`) wrapping the P1 constituent decoder, its fixed-point
  full-loop reference model, the LLR memory scheduling and half-iteration
  control, the QPP interleave/deinterleave extrinsic exchange, the two-tier
  verification (inner bit-exact + outer bounded-BER vs float
  `turbo_decoder.m`), and its golden-vector lane.

### Modified Capabilities

<!-- None. New core only. The P1 `fpga-constituent-decoder` core, `fpga-qpp-rom`,
     and `fpga-internal-interleaver` (qpp_interleaver) cores are reused
     UNMODIFIED; the software turbo_decoder.m and the turbo-decoder spec are
     unchanged (used as the float reference). -->

## Impact

- New files under `hdl/rtl/` (`turbo_decoder_top`), a fixed-point full-loop
  reference + bounded-BER characterization generator under `scripts/`,
  golden vectors under `hdl/vectors/`, and a `hdl/sim/turbo_decoder_top/`
  cocotb lane.
- No changes to MATLAB/Octave sources or prior specs/cores; the P1 constituent
  decoder, `qpp_rom`, and `qpp_interleaver` are instantiated unmodified.
- Extends the documented two-tier oracle from P1: inner bit-exact vs the
  fixed-point reference is identical in discipline; the **outer check shifts
  from numerical equivalence (P1) to bounded communications BER (P2)** because
  the iteration now produces real turbo gain (roadmap §1).
- Explicit non-goals, deferred to **P3**
  (`add-fpga-turbo-decoder-termination`) and the maturation track per
  `hdl/docs/decoder_roadmap.md` §3: CRC-aided early termination, HARQ LLR
  accumulation, filler/`NaN→+inf` handling, exact Log-MAP correction LUT,
  inter-half extrinsic scaling, sliding-window/BRAM, fixed-point width
  tightening, and any board demo. v1 keeps **few large-`K`** vectors
  (cycle-budget ≈ `4·H·K`).
