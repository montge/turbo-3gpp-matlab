## Why

Every LTE transmit-side block now exists and is sim-verified in HDL: turbo
encode (standalone datapath) and both rate-matching pieces (sub-block
interleave, circular buffer). The capstone is to integrate them — first into a
full `rate_matching` (3× sub-block interleaver + circular buffer, vs
`rate_matching.m`), then chain the verified `turbo_encode_top` into it for a
**complete hardware LTE transmit chain** verified end-to-end against the
composed software model. This mirrors the QPP-ROM integration pattern (wire
already-verified cores; only thin orchestration is new).

## What Changes

- Add `hdl/rtl/rate_matching_top.vhdl`: buffers the 3×`D` input `d`, runs three
  **unmodified** `subblock_interleaver` instances (idx 0/1/2) in lockstep,
  forms each `v(r,k)` (`filler ? NaN : d(r, d-index)`), feeds the columns into
  the **unmodified** `circular_buffer`, and streams the length-`E` output —
  bit-for-bit equal to `rate_matching(d, N_ref, I_LBRM, rv_idx, E)`.
- Add `hdl/rtl/tx_chain_top.vhdl`: instantiates the **unmodified**
  `turbo_encode_top` feeding `rate_matching_top`, so `(K, code block, rate-
  match params)` → length-`E` rate-matched bits — equal to
  `rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)), …)`.
- Add cocotb/GHDL lanes `hdl/sim/rate_matching_top/` and
  `hdl/sim/tx_chain_top/` with golden vectors from the existing
  `rate_matching.m` and the composed software chain.
- v1 stays sim-first/correctness-first (reuses the sub-cores' existing
  arithmetic); divider-free / BRAM synthesis hardening remains the documented
  follow-on. No board work. No screen.

## Capabilities

### New Capabilities

- `fpga-rate-matching`: the integrated HW `rate_matching` (3× sub-block
  interleaver + circular buffer) and the complete `turbo_encode_top →
  rate_matching_top` transmit chain, each verified against the software model.

### Modified Capabilities

<!-- None. All sub-cores (subblock_interleaver, circular_buffer,
     turbo_encode_top and its children) are reused unmodified; their specs and
     the software model are unchanged. -->

## Impact

- New files under `hdl/rtl/` (`rate_matching_top`, `tx_chain_top`), generators
  using `rate_matching.m` / the composed chain, and two `hdl/sim/` lanes.
- No changes to MATLAB/Octave sources or prior specs/cores.
- Reuses the cross-platform HDL harness and golden-vector methodology.
- Explicit non-goals: no decoder, no fixed-point, no board work, no
  divider-free/BRAM synthesis hardening (documented follow-on).
