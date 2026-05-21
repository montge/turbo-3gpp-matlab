## 1. Fixed-Point Reference + Characterization

- [x] 1.1 Author `scripts/fixedpoint_constituent_decoder.m` (Octave): Max-Log-MAP port of `constituent_decoder.m` with explicit input/metric Q-format, saturation, per-step max-normalization, fixed op-order.
- [x] 1.2 Confirm/tighten the fixed-point widths + ±inf sentinel against the design.md "first cut" table, and pin the outer equivalence band, once the reference is written and characterized (close the design Open Questions; main check: is F=3 enough, can W_αβ shrink).
- [x] 1.3 Add `scripts/characterize_constituent_decoder.m`: encode→BPSK+AWGN→LLR frames at a *bounded* set of SNRs/frame counts; assert fixed-point reference vs float `constituent_decoder.m` **numerical equivalence on identical inputs** (extrinsic-LLR error stats + hard-decision agreement) within the documented band — explicitly NOT a communications-BER check (BER is a P2 oracle).

## 2. Golden-Vector Generator

- [x] 2.1 Add `scripts/generate_hdl_constituent_decoder_vectors.m`: build realistic LLR frames, quantize, run the fixed-point reference, emit `hdl/vectors/constituent_decoder.csv` (`K`, quantized `x_a`, `z_a`, expected `x_e`).
- [x] 2.2 Suite: representative `K` set + a couple of SNRs; document the CSV schema.
- [x] 2.3 Generators use only existing helpers + the new reference; no MATLAB/Octave sources changed.

## 3. Constituent Decoder Core

- [x] 3.1 Add `hdl/rtl/constituent_decoder.vhdl`: γ branch metrics from the 16 trellis transitions; signed saturating Q-format datapath.
- [x] 3.2 α forward recursion with per-step max-normalization; full-block α storage (8 × (K+3)).
- [x] 3.3 β backward recursion with per-step max-normalization; extrinsic `x_e = max(δ|x=0) − max(δ|x=1)` streamed out.
- [x] 3.4 K-agnostic streaming interface (`start` latches `K`; load `K+3` `(x_a,z_a)`; stream `K+3` `x_e` with valid/last).

## 4. Simulation Lane

- [x] 4.1 Add `hdl/sim/constituent_decoder/` (Makefile + cocotb) mirroring established lanes.
- [x] 4.2 Driver loads `(x_a,z_a)`, collects `x_e`; asserts **bit-exact** vs the fixed-point reference golden CSV.
- [x] 4.3 Artifacts covered by existing `.gitignore`.

## 5. Verification

- [x] 5.1 Inner gate: lane PASS bit-exact for all representative `K`/SNR vectors. (27/27 frames bit-exact: K∈{40,512,6144} × SNR∈{0,2,4} dB × 3.)
- [x] 5.2 Outer: characterization within the documented band (recorded). (Band pinned in P1.1–1.3 / design.md "Equivalence band": max |ext-LLR err| ≤ 0.50, RMS ≤ 0.10 LLR; not re-derived here, the inner gate enforces the fixed-point reference bit-exactly.)
- [x] 5.3 Regression: all prior HDL lanes + Octave suite still pass. (11/11 HDL lanes PASS incl. the new constituent_decoder; Octave suite 102/102.)
- [x] 5.4 Record results (vectors, K/SNR set, agreement figures). (Vectors: hdl/vectors/constituent_decoder.csv, 27 frames; inner gate bit-exact 27/27; outer band as 5.2.)

## 6. Validation and Docs

- [x] 6.1 Add `hdl/sim/constituent_decoder/README.md` (two-tier method, schema, regeneration, run, roadmap pointer).
- [x] 6.2 `npx openspec validate add-fpga-constituent-decoder --strict` passes.
- [x] 6.3 `npx openspec validate --all --strict` — no regression. (22 passed, 0 failed.)

## 7. Follow-on Note (not required for completion)

- [x] 7.1 Confirm roadmap §3 P2+ (turbo loop, CRC/HARQ/filler, exact Log-MAP LUT, sliding-window/BRAM, RX integration, board demo) remain captured in `hdl/docs/decoder_roadmap.md` as the explicit next increments; out of scope here.
