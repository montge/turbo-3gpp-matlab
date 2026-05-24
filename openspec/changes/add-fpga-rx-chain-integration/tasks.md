## Tasks — add-fpga-rx-chain-integration

Two-tier + end-to-end gate (per `hdl/docs/decoder_roadmap.md` §1 and design.md
Decision 4): **inner** = cocotb/GHDL bit-exact of `de_rate_matching_top` vs an
authored fixed-point de-rate-match reference (golden CSV); **outer / end-to-end**
= bounded TX → BPSK+AWGN → RX BER vs float `turbo_decoding_chain`; plus a
Quartus II 13.0sp1 fit gate. The decoder + reused addressing cores stay
UNMODIFIED. Scope: single code block (`C = 1`); plain `turbo_decoder_top`; single
transmission. Multi-CB / CRC-term / HARQ deferred (proposal scope).

## 1. Fixed-point de-rate-match reference + characterization

- [x] 1.1 Author `scripts/fixedpoint_de_rate_matching.m` — factor the inline
  float de-rate-match (`turbo_decoding_chain.m` lines 86–93: scatter-accumulate
  via `rate_matching_patterns`, reshape `3×D`, `d(1:2,1:F_r)=NaN`) into a callable
  fixed-point reference: quantize received LLRs to W_LLR (Q3.4), inverse
  circular-buffer **saturating soft-combine** into the W_DRM (Q11.4) `w`
  accumulator, inverse subblock-interleave (×3), map filler `d_a(1:2,1:F_r)` →
  `+inf` = P1 `MAX_SENT`, untransmitted positions → `0` erasure, saturate output
  to W_EXT (Q7.4). Output the `3×(K+4)` `d_a` matrix in the decoder's load format.
- [x] 1.2 Pin the **soft-combine accumulator width** `W_DRM = 16` (Q11.4) and the
  **input LLR format** `W_LLR = 8` (Q3.4) against the design.md Fixed-point table;
  reuse the P1 `MAX_SENT = +16383` filler sentinel and the W_EXT = 12 output word
  UNCHANGED (no new decode-datapath format). Verify the saturating accumulate
  never wraps for the worst-case visit/wrap count (design.md sizing).
- [x] 1.3 Characterize the reference vs the **inline float de-rate-match** on
  identical inputs: the permutation/accumulate is integer-exact; assert the
  recovered `d_a` matches the float `d` (finite values exact modulo W_LLR/W_DRM
  quantization; `+inf` filler and `0` erasure at the float positions) across a
  representative `(K, N_ref, I_LBRM, rv_idx, E, F_r)` set, including an `E > N_cb`
  (forced wrap → genuine multi-LLR accumulate) case. Record in
  `results/characterize_de_rate_matching.txt`.

## 2. Golden-vector generator

- [x] 2.1 Author `scripts/generate_hdl_de_rate_matching_vectors.m` →
  `hdl/vectors/de_rate_matching_top.csv`: per case `case_id`, `K`, `N_ref`,
  `I_LBRM`, `rv_idx`, `E`, `F_r`, the E quantized received LLRs `e_soft`, and the
  expected `3×(K+4)` `d_a` matrix (W_EXT). Document the CSV schema in the header;
  idempotent (fixed per-case seeds → byte-identical across runs); few large-`K`
  cases (sized for the linear de-rate-match latency).
- [x] 2.2 Vectors EXERCISE the new behaviours: (a) a baseline `E ≈ N_cb` no-wrap
  case; (b) an **`E > N_cb` wrap** case (a `w` position accumulates ≥2 LLRs —
  soft-combine); (c) an `E < N_cb` **erasure** case (untransmitted `w` positions
  → `0`); (d) at least one **filler** case `F_r > 0` (first `F_r` systematic +
  upper-parity → `+inf`); (e) `rv_idx ≠ 0` (different `k_0`). Uses only existing
  helpers (`turbo_encoder`, `rate_matching`, `internal_interleaver`,
  `subblock_interleaver`, `circular_buffer`) + the stage-1 reference; no existing
  `.m` changed.

## 3. RTL: `de_rate_matching_top` + `rx_chain_top`

- [x] 3.1 Add `hdl/rtl/de_rate_matching_top.vhdl`: inverse circular-buffer
  **soft-combine** (mirror the `circular_buffer.vhdl` `k_0`/`N_cb`/dummy-skip
  divider-free recurrence `S_QCALC`/`S_K0MOD`/running `pos`, with a saturating
  read-modify-write `w_soft[pos] += e_soft[k]` into a banked soft `w` RAM
  sys/ev/od) — author as a standalone `de_circular_buffer` sibling or a mode flag
  (design.md open question; recommend standalone, leaving the TX
  `circular_buffer` UNTOUCHED).
- [x] 3.2 Inverse subblock-interleave (×3): split soft `w` into the 3 sub-blocks
  (sys/ev/od bank read), reuse the **UNMODIFIED `subblock_interleaver`** address+
  filler generator, and **scatter** `d_soft[d-index] = subblock_soft[pos]` for
  non-filler positions; drop the subblock pad positions.
- [x] 3.3 Filler / erasure / output: map `d_a(1:2, 1:F_r)` → `MAX_SENT` (`+inf`),
  leave untransmitted positions `0`, **saturate** every `d_a` word W_DRM → W_EXT,
  and stream the `3×(K+4)` matrix column-major (`da_valid`/`da{1,2,3}` W_EXT) in
  the decoder's exact load order.
- [x] 3.4 Add `hdl/rtl/rx_chain_top.vhdl`: wire `de_rate_matching_top` →
  **`turbo_decoder_top` (UNMODIFIED)** with a start-pulse FSM, mirroring
  `tx_chain_top` in reverse; expose K decoded hard bits with valid/last.
  K-agnostic (start latches `K`, `N_ref`, `I_LBRM`, `rv_idx`, `E`, `F_r`).

## 4. Inner simulation lane (bit-exact)

- [x] 4.1 Add `hdl/sim/de_rate_matching_top/` (Makefile + cocotb) mirroring the
  established lanes; compile `de_rate_matching_top` + `subblock_interleaver`
  (+ the `de_circular_buffer` sibling). Driver loads `K`/`N_ref`/`I_LBRM`/`rv`/`E`/
  `F_r`/`e_soft`, collects the `3×(K+4)` `d_a`, asserts **bit-exact** vs the golden
  CSV (the deterministic soft de-rate-match stage). Clear per-frame diff on
  mismatch. Artifacts covered by the root `.gitignore`.

## 5. End-to-end verify (TX → AWGN → RX)

- [x] 5.1 Add `hdl/sim/rx_chain_top/` (Makefile + cocotb): compile `rx_chain_top`
  + `de_rate_matching_top` + `subblock_interleaver` + the reused (UNMODIFIED)
  `turbo_decoder_top`, `constituent_decoder`, `qpp_rom`, `qpp_interleaver`. A
  couple of end-to-end smoke frames (TX golden frame → AWGN-quantized LLRs → RX),
  hard-decoded K bits checked.
- [x] 5.2 Add `scripts/characterize_rx_chain.m` — bounded end-to-end **BER**
  harness: random block → `turbo_encoder` → `rate_matching` → BPSK+AWGN →
  quantize to W_LLR → RX chain (fixed-point de-rate-match → fixed-point turbo
  decode) → compare decoded bits / BER-vs-SNR against float `turbo_decoding_chain`
  on the **same** frames over a bounded SNR grid (few points, modest frames,
  shallow target BER); assert within the documented decoder dB margin (≤ ~1.0 dB).
  Record in `results/characterize_rx_chain.txt`.
- [x] 5.3 Regression: all prior HDL lanes (TX lanes + P1/P2/P3 decoder lanes +
  CRC) and the Octave suite still pass; reused cores (`turbo_decoder_top`,
  `subblock_interleaver`, the TX `circular_buffer`) byte-unchanged.

## 6. Fit + docs + validate

- [x] 6.1 Quartus II 13.0sp1 fit of `rx_chain_top` on the EP2C35F672C6 at a
  board-demo `K` (e.g. K = 512, sized generics) — record LE / M4K / registers /
  DSP / Fmax; the soft `w` RAM infers M4K (sys/ev/od banks, like the TX
  `circular_buffer`).
- [x] 6.2 Add `hdl/sim/de_rate_matching_top/README.md` (+ `rx_chain_top/README.md`):
  two-tier + end-to-end method, the de-rate-match-as-inverse algebra, the CSV
  schema, W_LLR/W_DRM/W_EXT pins, regenerate + run commands, roadmap pointer; note
  the deferred multi-CB / CRC-term / HARQ follow-ons.
- [ ] 6.3 `npx openspec validate add-fpga-rx-chain-integration --strict` and
  `npx openspec validate --all --strict` pass.
