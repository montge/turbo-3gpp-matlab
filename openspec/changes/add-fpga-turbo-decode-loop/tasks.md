## 1. Fixed-Point Full-Loop Reference + Characterization

- [x] 1.1 Author `scripts/fixedpoint_turbo_decoder.m` (Octave): wrap the P1 `scripts/fixedpoint_constituent_decoder.m` in the exact `turbo_decoder.m` loop algebra — de-mux `3×(K+4)` `d_a` into upper `(x_a,z_a)` / lower `(x'_a,z'_a)` + `ch_sys`, `c_a=0`, half-iteration framing `H=round(2·max_iter)` (even=upper, odd=lower), `x_a=c_a+ch_sys` / `c_e=x_e+ch_sys`, interleave `x'_a=c_e[pi]` / deinterleave `c_a[pi]=x'_e`, hard decision `(c_a+c_e)<0`. No filler/NaN, no early termination (P3).
- [x] 1.2 Pin the **extrinsic-exchange Q-format** (`c_a`/`c_e` width, the `+ch_sys`/`+c_a` add accumulator, re-quantization to the P1 core input format) and the `max_iterations`/`H` default, against the design.md "Fixed-point format" table and Open Questions, once the reference is written and characterized. P1 constituent-core widths + ±inf sentinel are inherited unchanged.
- [x] 1.3 Add `scripts/characterize_turbo_decoder.m`: encode→BPSK+AWGN→LLR frames over a **bounded** SNR grid / modest frame counts; assert the fixed-point turbo reference vs float `turbo_decoder.m` **bounded BER-vs-SNR within a documented dB margin** (a trend/margin check, shallow target BER ~1e-2–1e-3). This is the P2 outer oracle — now a communications-BER check (the loop iterates), unlike P1's equivalence check.

## 2. Golden-Vector Generator

- [x] 2.1 Add `scripts/generate_hdl_turbo_decoder_vectors.m`: build realistic LLR frames, quantize, run the fixed-point full-loop reference, emit `hdl/vectors/turbo_decoder_top.csv` (`K`, `max_iter`, quantized `d_a` (`3×(K+4)`, column-major), expected `c` (`K` hard bits); optionally intermediate `c_a`/`c_e` for diagnostics).
- [x] 2.2 Suite: representative `K` set + a couple of SNRs + at least one small-`H` and the default-`H` case; keep **few** large-`K` cases (cycle budget `~4·H·K`). Document the CSV schema.
- [x] 2.3 Generators use only existing helpers (`turbo_encoder`, `internal_interleaver`, the P1 reference) + the new full-loop reference; no MATLAB/Octave sources changed.

## 3. Turbo Decode Loop Core (`turbo_decoder_top`)

- [ ] 3.1 Add `hdl/rtl/turbo_decoder_top.vhdl`: half-iteration loop controller / FSM (`S_IDLE→S_LOAD_D→S_HALF_DISPATCH→{upper|lower}→S_FINAL→S_OUT→S_DONE`), `H=round(2·max_iter)`, even=upper / odd=lower, stop at `H`.
- [ ] 3.2 LLR memories: persistent `z_a[K+3]`, `z'_a[K+3]`, `ch_sys[K]` (set once at load) + cyclic `c_a[K]`, `c_e[K]` (per half) + termination consts `x_a[3]`/`x'_a[3]`; de-mux of `d_a` per the loop algebra; `c_a=0` init. K-agnostic (start latches `K`).
- [ ] 3.3 Instantiate the **P1 `constituent_decoder` core unmodified**, one instance, sequential upper→lower; mux `(x_a,z_a)`/`(x'_a,z'_a)` in, consume `x_e[0..K-1]` (discard the 3 termination extrinsics). Upper: `x_a=c_a+ch_sys` (re-quantized), `c_e=x_e+ch_sys`.
- [ ] 3.4 Interleave datapath: instantiate `qpp_rom` + `qpp_interleaver` **unmodified** (same pattern as `turbo_encode_top`); regenerate `pi[k]` per use; lower interleave read `x'_a=c_e[pi]` (async), deinterleave scatter `c_a[pi]=x'_e`.
- [ ] 3.5 Final hard decision `c[k]=(c_a[k]+c_e[k])<0`; stream `K` bits out with valid/last.

## 4. Simulation Lane

- [ ] 4.1 Add `hdl/sim/turbo_decoder_top/` (Makefile + cocotb) mirroring established lanes; compile `turbo_decoder_top` + the reused `constituent_decoder`, `qpp_rom`, `qpp_interleaver`.
- [ ] 4.2 Driver loads `K`/`max_iter`/`d_a`, collects the `K` hard bits; asserts **bit-exact** vs the fixed-point full-loop reference golden CSV.
- [ ] 4.3 Artifacts covered by existing `.gitignore`.

## 5. Verification

- [ ] 5.1 Inner gate: lane PASS bit-exact for all representative `K`/SNR/`H` vectors.
- [ ] 5.2 Outer: bounded BER-vs-SNR characterization vs float `turbo_decoder.m` within the documented dB margin (recorded). Note the P1→P2 oracle shift (equivalence → BER).
- [ ] 5.3 Regression: all prior HDL lanes + Octave suite still pass; reused cores (`constituent_decoder`, `qpp_rom`, `qpp_interleaver`) unmodified.
- [ ] 5.4 Record results (vectors, `K`/SNR/`H` set, BER figures + margin).

## 6. Validation and Docs

- [ ] 6.1 Add `hdl/sim/turbo_decoder_top/README.md` (two-tier method incl. the P2 BER-outer shift, CSV schema, regeneration, run, roadmap pointer).
- [ ] 6.2 `npx openspec validate add-fpga-turbo-decode-loop --strict` passes.
- [ ] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [ ] 7.1 Confirm roadmap §3 P3+ (`add-fpga-turbo-decoder-termination`: CRC-aided early termination, HARQ accumulation, filler `NaN→+inf`; and the maturation track: exact Log-MAP LUT + extrinsic scaling M1, sliding-window/BRAM M2, fixed-point width tightening M3, RX integration P4, board demo M4) remain captured in `hdl/docs/decoder_roadmap.md` as the explicit next increments; out of scope here.
