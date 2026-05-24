## Context

The complete LTE **transmit** chain is built and sim-verified in HDL
(`tx_chain_top` = `turbo_encode_top` → `rate_matching_top`), and the turbo
decoder is sim-verified and M4K-fit (`turbo_decoder_top` P2, `turbo_decoder_term_top`
P3). P4 closes the loop: the **receive-side inverse** that turns received soft
channel LLRs back into the decoder's `3×(K+4)` `d_a` input.

The float oracle for de-rate-matching is **not** a standalone function — it is
**inline in `turbo_decoding_chain.m` (lines 80–93)** and documented in the
`rate_matching.m` header (lines 33–39). Per code block `r`:

```matlab
% turbo_decoding_chain.m, lines 86-93 (the de-rate-match oracle):
d_vec = zeros(1,3*obj.D_r(r+1));
for k = 0:length(obj.rate_matching_patterns{r+1})-1
    d_vec(obj.rate_matching_patterns{r+1}(k+1)+1) = ...
        d_vec(obj.rate_matching_patterns{r+1}(k+1)+1) + e_r{r+1}(k+1);  % SCATTER-ACCUMULATE
end
d = reshape(d_vec,3,obj.D_r(r+1));
d(1:2,1:obj.F_r(r+1)) = NaN;   % filler systematic + upper-parity rows -> NaN -> +inf
```

`rate_matching_patterns{r+1}` is the **same length-E permutation `pi`** produced by
the TX `rate_matching(d, N_ref, I_LBRM, rv_idx, E)` (`turbo_coding_chain.m`
`processTunedPropertiesImpl`, line 282) — TX does `e = d_vec(pi+1)` (gather/read),
RX does `d_vec(pi+1) += e` (scatter/accumulate). Because the rate-match read can
visit a `w` position more than once (circular wrap when `E > N_cb`, i.e. HARQ /
high coding rate), the inverse is an **accumulate**, soft-combining every LLR that
landed on that position. `w` positions the read never visited get `0` — an
**erasure** (no channel information). The reshape + `d(1:2,1:F_r)=NaN` recovers
the `3×(K+4)` matrix with filler.

`d_a` then feeds `turbo_decoder(d, ...)` UNMODIFIED. The decoder's HDL load
format is already pinned (`turbo_decoder_top.vhdl` entity header): K+4 column
beats on `da_valid`, each presenting `d_a(1)/d_a(2)/d_a(3)` on W_EXT=12 (Q7.4)
ports; the decoder maps `NaN→+inf→MAX_SENT` and de-muxes internally. **So the RX
chain's job is to produce exactly that `3×(K+4)` soft matrix, in that exact
format, and stream it into the unmodified decoder.**

A **standalone fixed-point de-rate-match reference MUST be authored**
(`scripts/fixedpoint_de_rate_matching.m`), mirroring how P1/P2/P3 authored
`fixedpoint_constituent_decoder.m` / `fixedpoint_turbo_decoder.m` /
`fixedpoint_turbo_decoder_term.m`. The float de-rate-match is inline (not a
reusable `.m`), so the fixed-point reference both (a) factors the float algebra
out into a callable function and (b) adds the fixed-point quantization /
saturating soft-combine. It is the inner-gate oracle.

## Goals / Non-Goals

**Goals:** specify a `de_rate_matching_top` that inverts `rate_matching_top` on
soft LLRs (inverse circular-buffer soft-combine + inverse subblock-interleave,
with `+inf` filler / `0` erasure), producing the `3×(K+4)` soft `d_a` in the
decoder's exact W_EXT input format; an `rx_chain_top` wiring de-rate-match →
`turbo_decoder_top` (UNMODIFIED); a fixed-point de-rate-match reference + golden
vectors (inner bit-exact); and a bounded end-to-end BER harness (TX → AWGN → RX
vs float `turbo_decoding_chain`). Single code block (`C = 1`).

**Non-Goals (P4 v1 boundary):** multi-CB (`C > 1`) segmentation/desegmentation,
CRC early termination (`turbo_decoder_term_top` swap), cross-transmission HARQ
buffering, a DE2 board demo, upstream demod/LLR formation, decoder accuracy /
memory maturation (M1/M2/M3). No new decode math (the decoder is reused
UNMODIFIED). No edits to any TX core, decoder core, or `.m` source (only the new
de-rate-match reference + RX RTL/lanes are authored when this change is started).

## Decisions

### 1. De-rate-match = inverse circular-buffer soft-combine + inverse subblock-interleave

The de-rate-match exactly inverts `rate_matching_top` on soft words, stage for
stage, **reusing the addressing logic of the existing cores in the inverse
direction**:

**(a) Inverse circular buffer (inverts `circular_buffer.vhdl`).** TX
`circular_buffer` builds `w` (`K_w = 3·K_Pi`: row-1 systematic, then rows 2/3
interleaved — `circular_buffer.m` lines 58–66), computes `N_cb` and `k_0`
(`k_0 = R_TC·(2·ceil(N_cb/(8·R_TC))·rv + 2)`), then **reads** E non-filler bits
circularly from `w` starting at `k_0` (skipping the dummy/filler positions). The
RX inverse uses the **identical** `N_cb` / `k_0` / dummy-skip addressing
(divider-free recurrence already in `circular_buffer.vhdl`: `S_QCALC` for `q`,
`S_K0MOD` for `k_0 mod N_cb`, the running `pos` increment with conditional
`−N_cb`), but instead of *reading* `w[pos] → e[k]`, it **accumulates**
`w_soft[pos] += e_soft[k]` (saturating soft add). Positions visited more than
once (E > N_cb wrap) soft-combine; positions never visited remain `0` (erasure).
This is the float `d_vec(pi(k)+1) += e(k)` loop, position-by-position.

**(b) Inverse subblock-interleave (inverts `subblock_interleaver.vhdl`, ×3).**
TX `rate_matching` builds `w` from `v = [subblock(d1,0); subblock(d2,1);
subblock(d3,2)]`. The RX inverse splits the soft `w_soft` back into the three
soft sub-blocks (`w_soft[0..K_Pi-1]` = row 1; `w_soft[K_Pi+2k]` = row 2 even;
`w_soft[K_Pi+2k+1]` = row 3 odd — the same bank split `circular_buffer.vhdl`
already uses: `w_sys` / `w_ev` / `w_od`), then applies the **inverse subblock
permutation** to recover each soft `d_r[0..D-1]`. The `subblock_interleaver`
address generator emits, per output position, `(filler, d-index)`; the inverse
**scatters** `d_soft[d-index] = subblock_soft[position]` for the non-filler
positions (the float `subblock_interleaver.m` header "Deinterleaving":
`d(pi(~isnan(pi))+1) = v(~isnan(pi))`). The subblock pad positions (`pi == NaN`,
the `N_D = K_Pi − D` left-pad) carry no `d`-element and are dropped.

**(c) Filler / erasure mapping.** After the inverse permute, the recovered
`3×(K+4)` `d_a` has:
- **filler** at `d_a(1, 1:F_r)` and `d_a(2, 1:F_r)` (the first `F_r` systematic
  and upper-parity positions) — set to the **`+inf` known sentinel** (`MAX_SENT`),
  exactly the float `d(1:2,1:F_r)=NaN` which `turbo_decoder.m` maps to `inf`.
  (Row 3, lower parity, is not filler-masked — matching the float, which only
  sets rows 1:2.)
- **erasure** at any `w` position the rate-match never transmitted — `0` LLR
  (equal-probability, no information), the natural result of the un-accumulated
  zero-initialized `d_vec`.

The output is the `3×(K+4)` soft matrix, column-major, on W_EXT=12 (Q7.4) — the
**exact** `turbo_decoder_top` load format.

### 2. `de_rate_matching_top` reuses the TX-core addressing; only the datapath flips

The new `de_rate_matching_top` is the soft mirror of `rate_matching_top`. The
**control / addressing** (the `k_0` / `N_cb` / dummy-skip recurrence; the three
subblock address generators; the `w` bank split) is identical to the TX path —
ideally by **reusing the `subblock_interleaver` core UNMODIFIED** (it is a pure
address+filler generator, direction-agnostic) and **mirroring the
`circular_buffer` addressing** (the same `S_QCALC`/`S_K0MOD`/`pos` recurrence,
re-instantiated with an accumulate write instead of a read). The **datapath**
flips: TX reads bits out of `w`, RX accumulates soft LLRs into a soft `w`. The
`w` storage becomes a soft RAM (`3 × K_Pi` words of W_DRM, see §3), banked
sys/ev/od as in `circular_buffer.vhdl`, read-modify-write on the accumulate.

`rx_chain_top` wires `de_rate_matching_top` → `turbo_decoder_top` exactly as
`tx_chain_top` wires `turbo_encode_top` → `rate_matching_top`: a start-pulse FSM
and the `3×(K+4)` `d_a` column stream straight into the decoder's `da_valid` /
`da{1,2,3}_in` load port. The decoder is instantiated **UNMODIFIED**.

### 3. Fixed-point format — PINNED

The RX chain inherits the decoder's exchange grid and the P1 ±inf sentinel
unchanged; the **only new knob** is the soft-combine accumulator width.

| Quantity | Format (signed) | Status |
|---|---|---|
| Received soft LLR input `e_soft[k]` (channel LLR) | **W_LLR = 8** (Q3.4, range `±128`), `F_in = 4` shared — the channel-LLR word the AWGN+BPSK demapper produces; the realistic ~6-bit-class channel format the roadmap M3 targets, with margin | **PINNED** (input contract) |
| `w`-buffer soft-combine accumulator `w_soft[pos] += e_soft` | **W_DRM = 16** (Q11.4, signed, range `[−32768, 32767]`), `F_in = 4` shared; saturating accumulate | **PINNED** (reuses the P3 `W_harq = 16` precedent) |
| Output `d_a` (decoder load word) | **W_EXT = 12** (Q7.4, range `±2048`) — the decoder's inherited exchange word; the W_DRM accumulator is **saturated** to W_EXT at the de-rate-match output | inherited (P2) |
| filler-bit fixed-point token | the P1 ±inf sentinel **`MAX_SENT = +16383`** mapped to `+inf` at the decoder input format — reused unchanged | inherited (P1) |
| erasure (untransmitted position) | **`0`** LLR (equal-probability) — the zero-init of the accumulate; no new token | inherited (semantics) |

**Sizing rationale (the ≥1.5× band discipline P1/P2/P3 used).** The channel-LLR
word is `W_LLR = 8` (`±128`). A `w` position can be hit by at most a few wrap
visits within one transmission (and, in the deferred HARQ case, across up to
`N_retx = 4` transmissions). A saturating sum of, conservatively, `4 × 128 = 512`
needs 11 signed bits; `W_DRM = 16` (`±32768`) gives `32767 / 512 ≈ 64×`
headroom — it **never wraps** for any realistic visit count, and matches the P3
`W_harq` so the (deferred) HARQ accumulate can share the same buffer/width. The
accumulate **saturates** to `W_DRM`; the result is **saturated** to `W_EXT = 12`
at the output (the decoder load format is unchanged). The `+inf` filler is
idempotent under the saturating accumulate (a known bit stays known), matching
the P3 filler treatment.

`W_LLR = 8` is the **input contract** — the demapper/test harness must quantize
the channel LLRs to Q3.4 before the RX chain. The reference and golden vectors
pin it; the BER harness uses the same quantization so the inner CSV and the outer
BER use the same channel-LLR grid.

### 4. Two-tier oracle + end-to-end BER (the P4 verification)

**Inner (bit-exact, every commit — the established discipline).** The
deterministic soft de-rate-match stage is bit-exact:
- author `scripts/fixedpoint_de_rate_matching.m` — the fixed-point de-rate-match
  reference (the float `turbo_decoding_chain` lines 86–93 algebra, plus the
  W_LLR→W_DRM saturating accumulate, the inverse subblock permute, the `+inf`
  filler / `0` erasure mapping, saturate-to-W_EXT output). Characterize it
  against the inline float de-rate-match on identical inputs (numeric equivalence
  band — finite values agree exactly modulo the documented quantization; the
  permutation/accumulate is integer-exact, only the soft add saturates).
- `scripts/generate_hdl_de_rate_matching_vectors.m` → `hdl/vectors/de_rate_matching_top.csv`:
  per case `K`, `N_ref`, `I_LBRM`, `rv_idx`, `E`, `F_r`, the E quantized received
  LLRs `e_soft`, and the expected `3×(K+4)` `d_a` matrix (W_EXT). cocotb asserts
  the `de_rate_matching_top` output is **bit-for-bit** the reference's `d_a`.

**Outer / end-to-end BER (bounded, periodic — proves the whole loop).** A bounded
harness (`scripts/characterize_rx_chain.m`, the P2/P3 bounded discipline: few SNR
points, modest frames, shallow target BER ~1e-2–1e-3):
- random block `a` → `turbo_encoder` → `rate_matching` → **BPSK + AWGN** → channel
  LLRs → quantize to W_LLR → **RX chain (`de_rate_matching_top` →
  `turbo_decoder_top`)** → decoded bits;
- compare the decoded bits / BER-vs-SNR against the float `turbo_decoding_chain`
  on the **same** frames over the bounded grid; assert within the documented
  decoder dB margin (the same band P2/P3 use, ≤ ~1.0 dB; the de-rate-match adds
  no loss of its own beyond the W_LLR/W_DRM quantization).

This is exactly the roadmap §1 two-tier picture (inner bit-exact vs authored
reference; outer statistical vs float), with the outer tier being the *full
TX → channel → RX loop* — the P4-specific end-to-end proof. The cocotb
`rx_chain_top` lane runs a couple of end-to-end frames (TX golden frame → AWGN →
RX, hard-decoded bits checked) as a smoke gate; the deep BER trend is the Octave
outer harness.

### 5. Reuse, UNMODIFIED

- **`turbo_decoder_top`** — fed UNMODIFIED via its existing W_EXT `d_a` load
  port. v1 uses the plain P2 decoder (fixed `H`); the P3
  `turbo_decoder_term_top` (CRC24A early stop for `C = 1`) is a drop-in
  follow-on.
- **`subblock_interleaver`** — the direction-agnostic address+filler generator,
  reused UNMODIFIED for the inverse permute scatter.
- **`circular_buffer` addressing** — the `N_cb` / `k_0` / dummy-skip divider-free
  recurrence (`S_QCALC` / `S_K0MOD` / running `pos`), mirrored in the inverse
  direction (accumulate write instead of read). Whether to literally instantiate
  `circular_buffer` with a mode flag or author a sibling `de_circular_buffer`
  that shares the recurrence is an RTL-packaging open question (below); the
  *addressing algebra* is reused either way.
- **P1 `MAX_SENT` / P3 `W_harq`** — filler sentinel and accumulator width reused
  unchanged.

### 6. FSM sketch (`de_rate_matching_top`)

```
  S_IDLE ─in_start (K, N_ref, I_LBRM, rv, E, F_r)─►
  S_ZERO   : clear the soft w-buffer (3·K_Pi words = 0; erasure default)
     │
  S_ACCUM  : run the inverse-circular-buffer addressing (same k_0/N_cb/pos
     │       recurrence as circular_buffer); for each received e_soft[k],
     │       read-modify-write w_soft[pos] += e_soft[k] (saturating), skipping
     │       dummy positions exactly as the TX read does; until E LLRs consumed
     ▼
  S_DEINT  : split w_soft into the 3 soft sub-blocks (sys/ev/od bank read) and
     │       run the 3 subblock_interleaver address generators; scatter
     │       d_soft[d-index] = subblock_soft[pos] for non-filler positions
     ▼
  S_FILL   : map d_a(1:2, 1:F_r) -> MAX_SENT (+inf); saturate every d_a word
     │       W_DRM -> W_EXT
     ▼
  S_OUT    : stream the 3x(K+4) d_a matrix column-major on da_valid/da{1,2,3}
     ▼
  S_DONE
```

Latency is dominated by `S_ACCUM` (E reads) + `S_DEINT` (3·K_Pi positions) — both
linear, comparable to the TX `rate_matching_top` latency; negligible against the
decoder's `~4·H·K`. Sim-first storage (soft `w` RAM banked sys/ev/od as in
`circular_buffer.vhdl`, M4K-inferable when board-targeted).

## Risks / Trade-offs

- **Soft-combine accumulate correctness (new).** The wrap/multi-visit accumulate
  is the new arithmetic. Mitigation: it is the exact float `d_vec(pi(k)+1) += e(k)`
  loop; the fixed-point reference pins the saturating add; the inner cocotb lane
  asserts bit-exact `d_a` including a case with `E > N_cb` (forced wrap, so a
  position genuinely accumulates ≥2 LLRs). `W_DRM = 16` gives ~64× headroom so it
  never wraps.
- **Inverse-permute filler / erasure handling (new).** The `+inf` filler and `0`
  erasure must land at exactly the float positions. Mitigation: reuse the
  `subblock_interleaver` filler flag and the P1 `MAX_SENT`; a dedicated vector
  with `F_r > 0` and a vector with untransmitted (erased) `w` positions; the
  reference computes both from the inline float algebra.
- **Soft-vs-bit reuse of the circular-buffer addressing.** The TX core was
  authored for bits/reads; reusing its index recurrence for soft accumulate could
  drift. Mitigation: the addressing recurrence is reused *verbatim* (same `S_QCALC`
  / `S_K0MOD` / `pos`); only the data port flips read→accumulate; the inner lane
  is bit-exact against the reference which uses the same `rate_matching_patterns`
  permutation as the TX path, so any drift surfaces immediately.
- **End-to-end BER intractability.** Mitigation: the outer harness is explicitly
  **bounded** (few SNRs, modest frames, shallow target BER) — a trend/margin
  check, exactly as P2/P3. The de-rate-match itself adds no BER loss beyond the
  W_LLR/W_DRM quantization (it is information-preserving by construction).
- **Scope creep into multi-CB / CRC / HARQ / board.** Hard boundary in
  Goals/Non-Goals and the proposal scope section; v1 is `C = 1`, plain decoder,
  single transmission, no board.

## Open Questions

- **RTL packaging of the inverse circular buffer — OPEN.** Author a standalone
  `de_circular_buffer` (sibling sharing the `k_0`/`N_cb`/`pos` recurrence, with an
  accumulate datapath), or add a direction/mode flag to `circular_buffer.vhdl`
  that selects read (TX) vs accumulate (RX)? Recommendation: **standalone
  `de_circular_buffer`** for v1 (additive, zero regression risk to the
  hardware-verified TX `circular_buffer`; the index recurrence is small to
  duplicate); flag the unified-core refactor as a later cleanup. **User input
  welcome.**
- **Where does the soft `w` accumulate live, and read-modify-write vs scatter?**
  A banked soft RAM (sys/ev/od, like `circular_buffer.vhdl`'s `w_sys/w_ev/w_od`)
  with a registered read-add-write per accumulate beat, or a wider single-port
  scatter? Recommendation: banked soft RAM with RMW, M4K-inferable; pinned at the
  RTL stage. (Sim-first, like the TX tops.)
- **Plain `turbo_decoder_top` vs `turbo_decoder_term_top` for v1 — RECOMMEND
  plain.** v1 feeds the plain P2 decoder (fixed `H`, no CRC). For `C = 1` the
  TB CRC (CRC24A) early-stop would use `turbo_decoder_term_top`; it is a drop-in
  swap once the soft de-rate-match is proven, flagged as the immediate follow-on.
- **W_LLR channel-LLR input format — RECOMMEND Q3.4 (W_LLR = 8).** This is the
  RX input contract (the demapper grid). Pinned in §3; confirm against the BER
  harness's actual channel-LLR dynamic range during reference characterization
  (the reference + harness use the same quantization). The realistic ~6-bit
  channel format the roadmap M3 targets is a tightening follow-on, not v1.
- **Multi-CB (`C > 1`) desegmentation — DEFERRED, flagged.** `code_block_deconcatenation`
  (RX-side split of G LLRs into per-block `E_r`) + `code_block_desegmentation`
  (concatenate decoded bits, strip CRC24B, drop filler). For `C = 1` it is a
  pass-through; the multi-CB buffering is a bounded follow-on reusing the float
  `code_block_deconcatenation.m` / `code_block_desegmentation.m` as the oracle.
- **HARQ across transmissions — DEFERRED, supported.** The inverse-circular-buffer
  accumulate IS the soft-combine, so a cross-frame HARQ buffer (reuse the P3
  `fixedpoint_turbo_harq_accumulate` + `W_harq = 16`, which `W_DRM` matches) is a
  natural extension; deferred to keep v1 single-transmission.
