## ADDED Requirements

### Requirement: De-rate-matching inverts the TX rate-matching on soft LLRs

The system SHALL provide a `de_rate_matching_top` that inverts `rate_matching_top`
on soft channel LLRs — inverse circular-buffer **soft-combine accumulation**
(reusing the `k_0` / `N_cb` / dummy-skip addressing of `circular_buffer` in the
inverse direction) and inverse subblock-interleave (reusing the
`subblock_interleaver` permutation, ×3) — to reconstruct the `3×(K+4)` soft `d_a`
matrix in the decoder's exact W_EXT load format, with filler positions mapped to
the `+inf` sentinel and untransmitted positions left as `0` erasures.

#### Scenario: Inverse circular-buffer soft-combine reconstructs the w-buffer

- **WHEN** `de_rate_matching_top` receives the E soft LLRs for a code block with
  parameters `(K, N_ref, I_LBRM, rv_idx, E)`
- **THEN** it accumulates each received LLR onto its mother-code `w` position
  using the same circular addressing the TX `circular_buffer` reads from
- **AND** when more than one received LLR maps to the same `w` position
  (`E > N_cb` wrap), it soft-combines them by saturating addition
- **AND** any `w` position never transmitted is left as a `0` LLR (erasure)

#### Scenario: Inverse subblock-interleave recovers the three soft streams

- **WHEN** the soft `w` buffer has been accumulated
- **THEN** `de_rate_matching_top` splits it into the three soft sub-blocks and
  applies the inverse subblock-interleave permutation to recover the `3×(K+4)`
  soft `d_a` (systematic + two parity)
- **AND** it maps the first `F_r` systematic and upper-parity positions to the
  `+inf` known sentinel (the P1 `MAX_SENT`), matching the float
  `d(1:2,1:F_r)=NaN`
- **AND** it outputs `d_a` column-major on the decoder's W_EXT (Q7.4) grid,
  bit-identical in format to what `turbo_decoder_top` loads

### Requirement: RX chain feeds the reused decoder UNMODIFIED

The system SHALL provide an `rx_chain_top` that wires `de_rate_matching_top` into
the reused `turbo_decoder_top` (instantiated UNMODIFIED) — streaming the
reconstructed `3×(K+4)` `d_a` matrix into the decoder's load port and emitting the
K decoded hard bits — mirroring `tx_chain_top` in reverse for a single code block
(`C = 1`).

#### Scenario: De-rate-matched soft streams decode to transport-block bits

- **WHEN** a code block's soft LLRs are presented to `rx_chain_top`
- **THEN** `de_rate_matching_top` reconstructs the `3×(K+4)` `d_a` matrix and
  streams it into `turbo_decoder_top` (UNMODIFIED, plain P2 loop, fixed `H`)
- **AND** `rx_chain_top` emits the K decoded hard bits with valid/last, which for
  `C = 1` are the decoded transport-block bits

### Requirement: RX chain verified bit-exact (inner) and end-to-end BER (outer)

The system SHALL verify the RX chain two-tier: the deterministic
`de_rate_matching_top` stage **bit-exact** against an authored fixed-point
de-rate-match reference (golden CSV), and the full chain **end-to-end** by a
bounded TX → BPSK+AWGN → RX BER comparison against the float
`turbo_decoding_chain` within the documented decoder margin.

#### Scenario: Inner bit-exact de-rate-match gate

- **WHEN** the `de_rate_matching_top` cocotb lane runs the golden vectors
  (including an `E > N_cb` wrap/soft-combine case, an erasure case, and an
  `F_r > 0` filler case)
- **THEN** the reconstructed `3×(K+4)` `d_a` matrix matches the fixed-point
  reference bit-for-bit for every vector

#### Scenario: End-to-end BER within the decoder margin

- **WHEN** random blocks are passed through `turbo_encoder` → `rate_matching` →
  BPSK+AWGN → quantized channel LLRs → the RX chain (de-rate-match → decode) over
  a bounded SNR grid
- **THEN** the decoded bits / BER-vs-SNR track the float `turbo_decoding_chain` on
  the same frames within the documented decoder dB margin
- **AND** the reused `turbo_decoder_top`, `subblock_interleaver`, and the TX
  `circular_buffer` remain byte-unchanged
