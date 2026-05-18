## 1. Fixed-Point Reference + Characterization

- [ ] 1.1 Author `scripts/fixedpoint_constituent_decoder.m` (Octave): Max-Log-MAP port of `constituent_decoder.m` with explicit input/metric Q-format, saturation, per-step max-normalization, fixed op-order.
- [ ] 1.2 Confirm/tighten the fixed-point widths + ±inf sentinel against the design.md "first cut" table, and pin the outer equivalence band, once the reference is written and characterized (close the design Open Questions; main check: is F=3 enough, can W_αβ shrink).
- [ ] 1.3 Add `scripts/characterize_constituent_decoder.m`: encode→BPSK+AWGN→LLR frames at a *bounded* set of SNRs/frame counts; assert fixed-point reference vs float `constituent_decoder.m` **numerical equivalence on identical inputs** (extrinsic-LLR error stats + hard-decision agreement) within the documented band — explicitly NOT a communications-BER check (BER is a P2 oracle).

## 2. Golden-Vector Generator

- [ ] 2.1 Add `scripts/generate_hdl_constituent_decoder_vectors.m`: build realistic LLR frames, quantize, run the fixed-point reference, emit `hdl/vectors/constituent_decoder.csv` (`K`, quantized `x_a`, `z_a`, expected `x_e`).
- [ ] 2.2 Suite: representative `K` set + a couple of SNRs; document the CSV schema.
- [ ] 2.3 Generators use only existing helpers + the new reference; no MATLAB/Octave sources changed.

## 3. Constituent Decoder Core

- [ ] 3.1 Add `hdl/rtl/constituent_decoder.vhdl`: γ branch metrics from the 16 trellis transitions; signed saturating Q-format datapath.
- [ ] 3.2 α forward recursion with per-step max-normalization; full-block α storage (8 × (K+3)).
- [ ] 3.3 β backward recursion with per-step max-normalization; extrinsic `x_e = max(δ|x=0) − max(δ|x=1)` streamed out.
- [ ] 3.4 K-agnostic streaming interface (`start` latches `K`; load `K+3` `(x_a,z_a)`; stream `K+3` `x_e` with valid/last).

## 4. Simulation Lane

- [ ] 4.1 Add `hdl/sim/constituent_decoder/` (Makefile + cocotb) mirroring established lanes.
- [ ] 4.2 Driver loads `(x_a,z_a)`, collects `x_e`; asserts **bit-exact** vs the fixed-point reference golden CSV.
- [ ] 4.3 Artifacts covered by existing `.gitignore`.

## 5. Verification

- [ ] 5.1 Inner gate: lane PASS bit-exact for all representative `K`/SNR vectors.
- [ ] 5.2 Outer: characterization within the documented band (recorded).
- [ ] 5.3 Regression: all prior HDL lanes + Octave suite still pass.
- [ ] 5.4 Record results (vectors, K/SNR set, agreement figures).

## 6. Validation and Docs

- [ ] 6.1 Add `hdl/sim/constituent_decoder/README.md` (two-tier method, schema, regeneration, run, roadmap pointer).
- [ ] 6.2 `npx openspec validate add-fpga-constituent-decoder --strict` passes.
- [ ] 6.3 `npx openspec validate --all --strict` — no regression.

## 7. Follow-on Note (not required for completion)

- [ ] 7.1 Confirm roadmap §3 P2+ (turbo loop, CRC/HARQ/filler, exact Log-MAP LUT, sliding-window/BRAM, RX integration, board demo) remain captured in `hdl/docs/decoder_roadmap.md` as the explicit next increments; out of scope here.
