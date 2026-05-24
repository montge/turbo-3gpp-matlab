# De-rate-matching + RX-chain (receive side) HDL simulation

The P4 **receive** chain that closes the LTE loop in HDL: turn received channel
LLRs back into the decoder's soft `d_a` matrix, then decode.

- `de_rate_matching_top` — soft mirror of `rate_matching_top` (TS36.212
  §5.1.4.1, RX). Inverse circular-buffer **soft-combine** (`de_circular_buffer`)
  + inverse subblock-interleave (reusing the **unmodified** `subblock_interleaver`
  ×3), with `+inf` filler / `0` erasure, producing the `3×(K+4)` soft `d_a`
  matrix in the decoder's exact W_EXT load format.
- `rx_chain_top` — wires `de_rate_matching_top` → the **unmodified**
  `turbo_decoder_top` (the reverse of how `tx_chain_top` wires
  `turbo_encode_top` → `rate_matching_top`); emits the K decoded hard bits.

## Two-tier + end-to-end verification

Per the roadmap §1 picture: an **inner bit-exact** gate per deterministic stage,
and an **outer statistical** gate over the whole loop.

| tier | what | gate |
|------|------|------|
| inner (this lane) | `de_rate_matching_top` soft de-rate-match | **bit-exact** vs `scripts/fixedpoint_de_rate_matching.m` golden CSV (9 cases) |
| end-to-end (smoke) | `rx_chain_top` full loop | **bit-exact** decoded bits vs the reference CHAIN (de-rate-match → decode) on a few frames (`hdl/sim/rx_chain_top/`) |
| end-to-end (BER) | TX → BPSK+AWGN → RX | bounded **BER-vs-SNR** vs the float `turbo_decoding_chain` path, fixed-point loss within band (`scripts/characterize_rx_chain.m`) |

### De-rate-match as the inverse (the algebra)

The float de-rate-match is inline in `turbo_decoding_chain.m` (lines 86–93):

```
d_vec = zeros(1,3*D);
for k: d_vec(pi(k)+1) += e(k);     % SCATTER-ACCUMULATE (inverse of the TX gather)
d = reshape(d_vec,3,D); d(1:2,1:F_r) = NaN;   % filler -> +inf
```

`pi` is the **same** length-E permutation the TX `rate_matching` produced, so the
RX scatter is the exact inverse of the TX gather. Wrap (`E > N_cb`) revisits a
`w` position → those LLRs **soft-combine**; positions never visited stay `0`
(erasure). The de-rate-match is **information-preserving** — it adds no error of
its own beyond the pinned quantization (the stage-1 equivalence is exact).

The HDL skips, in the circular read, **both** the subblock NaN pad (`N_D` left
pad) **and** the d-level filler (rows 1:2 of the first `F_r` columns — the
`d_idx(1:2,1:F_r)=NaN` the TX template punctures), matching the reference's
`rate_matching` on the punctured template; rows 1:2 of cols `0..F_r-1` are then
written the `+inf` `MAX_SENT` token.

## Fixed-point pins (design.md Decision 3)

| word | format | role |
|------|--------|------|
| `W_LLR = 8` | Q3.4, `[-128,127]` | received channel-LLR input `e_soft` (the demapper grid) |
| `W_DRM = 16` | Q11.4 | soft-combine accumulator (saturating; ~64× headroom — never wraps) |
| `W_EXT = 12` | Q7.4, `[-2048,2047]` | decoder load word `d_a` (the accumulator is saturated to this) |
| `MAX_SENT = +2047` | — | `+inf` filler token (the P1 sentinel; float `NaN`) |
| `0` | — | erasure (untransmitted position) |

`F_in = 4` is shared across all grids, so every grid boundary is a pure
width/saturate (no rescale).

## Golden vectors

### `hdl/vectors/de_rate_matching.csv` (inner, 9 cases)

Schema: `case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,e_soft,d_a`

| column | meaning |
|--------|---------|
| `K`,`N_ref`,`I_LBRM`,`rv_idx`,`E`,`F_r` | block + rate-match parameters |
| `e_soft` | `E` signed ints, received channel LLRs @ W_LLR (Q3.4); the DUT input stream (pulled in TX read order via `e_req`) |
| `d_a` | `3·(K+4)` signed ints, expected soft `d_a` **column-major** (col1 rows1..3, …) @ W_EXT; filler = `2047`, erasure = `0`. **THE gate.** |

Cases exercise every behaviour: baseline (no wrap), wrap (`E>N_cb` soft-combine),
erasure (`E<N_cb`), filler (`F_r=4`), `rv_idx≠0`, large-K (512, 6144), and LBRM
(`I_LBRM=1`, `N_ref<K_w`).

### `hdl/vectors/rx_chain_top.csv` (end-to-end smoke, 4 cases)

Schema: `case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,max_iter,e_soft,c`

The expected `c` is the reference CHAIN
`fixedpoint_turbo_decoder(fixedpoint_de_rate_matching(e_q, …), pi, 8)` run on the
same W_LLR-quantized LLRs the HDL loads (`max_iter=8` → H=16, the DUT default
generic). The gate is HDL == reference chain, bit-for-bit on the K decoded bits —
isolating the `rx_chain_top` wiring (each sub-core is already bit-exact alone).

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_de_rate_matching_vectors.m')"
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_rx_chain_vectors.m')"
```

Both are idempotent (fixed seeds → byte-identical CSV).

## Run

```
cd hdl/sim/de_rate_matching_top && make SIM=ghdl    # inner, 9/9 bit-exact
cd hdl/sim/rx_chain_top         && make SIM=ghdl    # end-to-end, 4/4 bit-exact
```

Or the whole HDL suite: `scripts/run_all_hdl_lanes.sh`.

## End-to-end BER (the TX → channel → RX proof)

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "run('scripts/characterize_rx_chain.m')"
```

Bounded grid (few K, a handful of SNR points, modest frames): random block →
`turbo_encoder` → `rate_matching` → BPSK+AWGN → channel LLRs → **both** the
fixed-point RX chain (the HDL's arithmetic) and the float `turbo_decoding_chain`
path, reporting BER-vs-SNR and the fixed-point implementation loss (dB). The
de-rate-match adds no loss of its own; the measured loss is the decoder's
W_in/W_ext fixed-point + the shared W_LLR input quantization. Band: ≤ 1.0 dB
(the P2/P3 decoder band). Result recorded in `results/characterize_rx_chain.txt`.

## Deferred follow-ons (proposal scope)

Multi-CB (`C>1`) de-concatenation/de-segmentation, CRC early-termination
(`turbo_decoder_term_top` drop-in), cross-transmission HARQ soft-combine (the
inverse circular buffer **is** the soft-combine; `W_DRM=16` matches the P3
`W_harq`), a DE2 board demo, and the realistic ~6-bit M3 channel-LLR grid.
