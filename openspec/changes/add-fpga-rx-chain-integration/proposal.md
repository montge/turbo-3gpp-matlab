## Why

This is roadmap milestone **P4** (`hdl/docs/decoder_roadmap.md` §3, "RX-chain
integration"): build the **receive-side inverse** of the completed `tx_chain_top`
capstone, feeding the now-verified turbo decoder. The TX chain
(`turbo_encode_top` → `rate_matching_top`, i.e. turbo encode → subblock-interleave
×3 → circular-buffer select length-E) is built, fits the EP2C35, and is
sim-verified bit-exact; the decoder cores (`turbo_decoder_top`,
`turbo_decoder_term_top`) are sim-verified and M4K-fit at K=512. What is missing
is the glue that turns received **soft channel LLRs** back into decoder input:
**de-rate-matching** on soft values. P4 was explicitly scoped "later, once P1–P3
land" — they have landed, so this formalizes the P4 design.

The RX chain inverts `rate_matching` on **soft LLRs** rather than bits. The float
oracle already exists, inline in `turbo_decoding_chain.m` (lines 80–93) and
documented in the `rate_matching.m` header (lines 33–39): the E received soft
LLRs are **scatter-accumulated** back onto the `3·D` mother-code grid using the
*same* TX rate-matching permutation, reshaped to `3×D`, and the filler
systematic/parity rows set to `NaN` (→ `+inf` known) — yielding exactly the
`3×(K+4)` `d_a` matrix the decoder consumes. The HDL builds this as a new
`de_rate_matching_top` (inverting `circular_buffer`'s addressing and the three
`subblock_interleaver` permutations on soft words) plus an `rx_chain_top`
(de-rate-match → `turbo_decoder_top`), mirroring `tx_chain_top` in reverse. It is
**integration of existing cores** (the decoder is reused UNMODIFIED), not new
decode math, verified two-tier (bit-exact inner) plus **end-to-end BER**
(TX → BPSK+AWGN → RX vs the float `turbo_decoding_chain`).

## What Changes

- **Add** an RX-chain top (`rx_chain_top`, the soft inverse of `tx_chain_top`):
  - **`de_rate_matching_top`** (inverse of `rate_matching_top`):
    - **inverse circular buffer** — the E received soft LLRs map back to the
      `w`-buffer positions using the *same* `k_0` / `N_cb` / LBRM addressing as
      `circular_buffer.vhdl`, but the TX circular READ becomes an RX
      scatter-**ACCUMULATE**: soft-combine (saturating add) LLRs that wrapped
      onto the same `w` position; positions never transmitted stay `0` (erasure /
      no information). This same accumulate naturally implements HARQ soft
      combining across retransmissions (deferred, see scope).
    - **inverse subblock-interleave** (inverse of `subblock_interleaver.vhdl`,
      ×3) — de-permute `w` back to the three soft sub-blocks and recover the
      `3×(K+4)` soft `d_a` (systematic + 2 parity), mapping the dummy/pad
      positions out and the **filler** systematic/parity positions to the
      `+inf` known sentinel (the P1 `MAX_SENT`), exactly as the float
      `d(1:2,1:F_r)=NaN` (→ `inf` in the decoder).
    - Output: the `3×(K+4)` soft `d_a` matrix on the decoder's W_EXT=12 (Q7.4)
      exchange grid, column-major, **bit-identical in format** to what
      `turbo_decoder_top` already loads.
  - **feed `turbo_decoder_top`** (reused UNMODIFIED) — `d_a` streamed straight
    into the decoder load port; out come the K hard decoded bits.
- **Verify** two-tier plus end-to-end:
  - **inner** — cocotb/GHDL **bit-exact** of `de_rate_matching_top` vs an
    authored fixed-point de-rate-match reference (golden CSV), the
    deterministic integer/soft-deterministic stage (the established P1–P3
    discipline).
  - **outer / end-to-end BER** — random block → `turbo_encoder` →
    `rate_matching` → BPSK+AWGN → **RX chain (de-rate-match → decode)** →
    decoded bits / BER compared against the float `turbo_decoding_chain` over a
    **bounded** SNR grid (few points, modest frames, shallow target BER). This
    proves the whole TX → channel → RX loop closes within the documented decoder
    margin.

All work is **proposal/design-only in this change** — no `hdl/`, `scripts/`,
`.qsf`, or `.m` edits land here. The fixed-point soft-combine accumulator format,
the inverse-permute filler/erasure handling, and the desegmentation buffering are
specified here and implemented when the change is started.

## Capabilities

### New Capabilities

- `fpga-rx-chain-integration`: an `rx_chain_top` that inverts `tx_chain_top` on
  soft LLRs — `de_rate_matching_top` (inverse circular-buffer **soft-combine
  accumulate** + inverse subblock-interleave, with `+inf` filler / `0` erasure)
  producing the `3×(K+4)` `d_a` matrix in the decoder's exact W_EXT input format,
  feeding the reused `turbo_decoder_top` UNMODIFIED — verified bit-exact (inner)
  against an authored fixed-point de-rate-match reference and end-to-end (outer)
  by a bounded TX → AWGN → RX BER comparison against the float
  `turbo_decoding_chain`.

## Impact

- Integrates existing capabilities `fpga-circular-buffer`,
  `fpga-subblock-interleaver`, `fpga-rate-matching`, and `fpga-turbo-decode-loop`
  into a receive capstone mirroring `fpga-tx-chain-de2-demo`'s `tx_chain_top`.
- Reuses, UNMODIFIED, `turbo_decoder_top` and its W_EXT=12 (Q7.4) `d_a` load
  format; reuses the `k_0` / `N_cb` / LBRM addressing of `circular_buffer.vhdl`
  and the permutation of `subblock_interleaver.vhdl`, run in the inverse
  direction on soft words.
- Reuses the P1 ±inf sentinel `MAX_SENT = +16383` for filler positions and the
  P3 HARQ width precedent (`W_harq = 16`, Q11.4) for the soft-combine
  accumulator. The **only new fixed-point knob** is the soft-combine accumulator
  width, pinned in design.md.
- Depends on the two-tier discipline (cocotb/GHDL bit-exact for the soft
  de-rate-match stage + bounded BER margin once the decoder is in the loop) and
  Quartus II 13.0sp1.
- Risk: the soft-combine accumulate (saturating add at wrap/HARQ positions), the
  inverse-permute filler/erasure handling, and the soft-vs-bit re-use of the
  circular-buffer / subblock-interleaver addressing are the new pieces; the rest
  is reuse. Board demo is out of scope here.

## Scope boundary (explicit)

**In scope (v1):**

- **Single code block, `C = 1`** — the dominant LTE case; de-rate-matching of one
  block feeding one decoder call. De-rate-matching with the `C = 1` filler in the
  first (only) block.
- The full soft de-rate-match (inverse circular-buffer + inverse subblock ×3) and
  the unmodified-decoder feed, verified bit-exact (inner) + end-to-end BER
  (outer).

**Deferred / out of scope here (flagged follow-ons):**

- **Multi-code-block (`C > 1`) segmentation/desegmentation** — `code_block_deconcatenation`
  (split G LLRs into per-block `E_r`) on the RX side and `code_block_desegmentation`
  (concatenate decoded bits, strip per-block CRC24B, drop filler) on the output
  side. For `C = 1` desegmentation is a pass-through (no CB CRC, filler in block
  0); the multi-CB buffering/concatenation is a bounded follow-on.
- **CRC-aided early termination / `turbo_decoder_term_top`** — v1 feeds the plain
  `turbo_decoder_top` (fixed `H`); swapping in `turbo_decoder_term_top` (CRC24A
  for `C = 1`) is a drop-in follow-on once the soft de-rate-match is proven.
- **HARQ combining across transmissions** — the inverse-circular-buffer accumulate
  *is* the soft-combine primitive, so the datapath supports it; the cross-frame
  HARQ buffer/replay (reuse the P3 `fixedpoint_turbo_harq_accumulate` precedent
  and `W_harq`) is deferred to keep v1 single-transmission.
- A **DE2 board demo** of the RX chain (a later capstone like the TX demo).
- **Channel estimation / demodulation / LLR formation** upstream of the soft
  samples (the RX chain starts from soft LLRs, as the decoder does today).
- Decoder accuracy/memory maturation (M1/M2/M3, separate changes).
