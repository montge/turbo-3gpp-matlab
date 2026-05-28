## Why

The iterative turbo-decode loop (P2, `add-fpga-turbo-decode-loop`) is
implemented and sim-verified, but it is a *bare* loop: it runs a fixed `H`
half-iterations every time, has no early stop, no CRC check, no HARQ soft
combining, and explicitly defers filler bits. Those three deferrals are exactly
what separate the P2 loop from a usable LTE **code-block** decoder. This change
delivers the next decoder increment (**P3** of `hdl/docs/decoder_roadmap.md`):
the deferred `turbo_decoder.m` / `turbo_decoding_chain.m` behaviours that mature
the loop into a real code-block decoder.

- **CRC-aided early termination** cuts *average* decoding latency ~2–3× at good
  SNR: most blocks converge in 2–4 iterations, so running all `max_iterations`
  every time wastes the majority of the cycle budget. The float
  `turbo_decoder.m` already implements this via its `G_max` (CRC generator
  matrix) argument and the `iterations_performed` return — P3 adds the matching
  HDL.
- **HARQ soft combining** is required for any real link with retransmissions:
  `turbo_decoding_chain.m` accumulates the `3×D_r` channel-LLR matrix across
  retransmissions in `obj.buffers` *before* decoding. Without it, a
  retransmission throws away the prior soft information.
- **Filler-bit handling** is required for the code-block sizes LTE actually
  uses: `turbo_decoding_chain.m` marks the first `F_r` systematic LLRs `NaN`,
  and `turbo_decoder.m` maps `NaN → +inf`. The fixed-point decoder maps filler
  to the **`MAX_SENT = +16383` saturating sentinel** — the SAME ±inf token P1
  pinned (archived `add-fpga-constituent-decoder` design.md; roadmap §2 locked
  decision). P2 explicitly deferred filler to P3; this is where the sentinel
  reuse pays off.

It mirrors the established discipline: the P2 loop (`turbo_decoder_top`), the P1
constituent core, and the verified `qpp` / CRC infrastructure are reused; the
new surface (CRC24 check, early-stop control, filler mapping, HARQ accumulate)
is small and separately verified by the same two-tier oracle.

## What Changes

- Extend the Octave **fixed-point full-loop reference**
  (`scripts/fixedpoint_turbo_decoder.m`) — the inner bit-exact oracle — with:
  - **filler mapping** (`NaN → +inf → MAX_SENT`) reusing the P1 sentinel, applied
    at LLR de-mux exactly where float `turbo_decoder.m` does `d_a(isnan(d_a)) =
    inf`;
  - **CRC-aided early termination**: after each half-iteration compute the
    code-block CRC on the current hard decision and stop when it checks, else run
    to `max_iterations`; return `iterations_performed`. The early-stop schedule
    is **deterministic** (same inputs → same stop iteration) so the inner lane
    stays bit-exact.
  - **HARQ soft accumulation**: a soft buffer that sums the `3×D_r` channel-LLR
    matrix across retransmissions before the loop, mirroring the
    `turbo_decoding_chain.m` `obj.buffers` behaviour and its reset semantics.
- Extend the **bounded characterization harness** so the outer check exercises
  the new behaviours against float `turbo_decoder.m` / `turbo_decoding_chain.m`:
  early-stop with varying `iterations_performed`, filler blocks, and a HARQ
  retransmission case (BER + early-stop-iteration-count + CRC-pass-rate trend,
  bounded as in P2).
- Extend the **golden-vector generator** to emit cases that EXERCISE
  early termination (vectors with differing `iterations_performed`), filler code
  blocks, and a HARQ retransmission sequence — each carrying the expected decoded
  bits AND the expected `iterations_performed` so the lane checks the stop point.
- Add board-neutral synthesizable VHDL:
  - a **CRC24 check core** (CRC24A for the transport-block CRC, CRC24B for the
    code-block CRC) — assess reuse-vs-new against the existing
    `crc8_parallel.vhdl` generator-matrix pattern (open question below);
  - **early-termination control** folded into the existing P2 loop FSM: after
    each half compute the hard decision, run the CRC core, and exit to
    `S_FINAL` early when the CRC passes, recording `iterations_performed`;
  - **filler mapping** at LLR load (`+inf` token → `MAX_SENT`), so filler
    positions never spuriously win a `max` in the constituent core (the P1
    sentinel guarantee), and are forced `NaN`/known on output as the float model
    does;
  - **HARQ soft-accumulate** at the channel-LLR input stage (sum the incoming
    `3×D_r` LLR matrix into a soft buffer with a reset/clear), reusing the
    existing buffer/RAM idioms where applicable.
- Add a cocotb/GHDL lane checking the HDL **bit-exact** against the extended
  fixed-point reference golden vectors — decoded bits AND `iterations_performed`
  — plus regression of all prior lanes.
- Reuse the P2 `turbo_decoder_top` loop, the P1 `constituent_decoder` core, the
  `qpp_rom` / `qpp_interleaver`, and the existing CRC generator-matrix idiom; the
  ±inf sentinel is reused for filler **unchanged**.

## Capabilities

### New Capabilities

- `fpga-turbo-decoder-termination`: the P3 maturation of the iterative loop into
  a code-block decoder — the CRC24 check core, the CRC-aided early-termination
  control integrated into the P2 loop FSM (`iterations_performed`), the filler
  `NaN→+inf→MAX_SENT` mapping reusing the P1 sentinel, the HARQ soft-buffer
  accumulation, the fixed-point-reference extensions that model all three, and
  the two-tier verification (inner bit-exact incl. early-stop determinism +
  outer bounded BER / CRC-pass-rate vs float `turbo_decoder.m` /
  `turbo_decoding_chain.m`) with its golden-vector lane.

### Modified Capabilities

<!-- None. New capability only. The P2 fpga-turbo-decode-loop core
     (turbo_decoder_top) is reused: P3 layers early-stop control, filler
     mapping, CRC24, and HARQ accumulation around/into it. The P1
     fpga-constituent-decoder core, fpga-qpp-rom, and fpga-internal-interleaver
     are reused UNMODIFIED. The software turbo_decoder.m /
     turbo_decoding_chain.m and their specs are unchanged (used as the float
     reference). Modelled as a NEW capability rather than a modification of
     fpga-turbo-decode-loop because that P2 change is archived/sealed and the P3
     deferrals form a distinct, separately-verified behavioural surface — the
     same new-capability pattern P1→P2 used. -->

## Impact

- New files under `hdl/rtl/` (a CRC24 check core; an early-termination /
  filler / HARQ wrapper or extension around the P2 loop), extensions to the
  fixed-point reference + characterization + vector generators under `scripts/`,
  new golden vectors under `hdl/vectors/`, and a new
  `hdl/sim/turbo_decoder_termination/` cocotb lane.
- No changes to MATLAB/Octave sources or prior specs/cores: the P2
  `turbo_decoder_top`, P1 `constituent_decoder`, `qpp_rom`, and `qpp_interleaver`
  are reused; the float `turbo_decoder.m` / `turbo_decoding_chain.m` are the
  reference. The ±inf sentinel pinned at P1 is reused for filler unchanged.
- Extends the documented two-tier oracle from P2: inner bit-exact vs the
  fixed-point reference is identical in discipline (now also checking
  `iterations_performed`); the outer check stays a **bounded** comparison vs the
  float model, extended to early-stop iteration counts and CRC-pass rate.
- **In scope (P3):** CRC-aided early termination, HARQ LLR accumulation, filler
  `NaN→+inf` handling.
- **Out of scope (deferred, per `hdl/docs/decoder_roadmap.md` §3 — the
  maturation track and beyond):** exact Log-MAP correction LUT + inter-half
  extrinsic scaling (**M1**), sliding-window BCJR + BRAM mapping (**M2**),
  fixed-point width tightening to realistic channel-LLR formats (**M3**),
  RX-chain integration / de-rate-matching feeding the decoder (**P4**), and the
  optional DE2 board demo (**M4**). These are the roadmap's subsequent
  increments, not P3 work.
