## Context

`rate_matching(d,…) = circular_buffer([subblock_interleaver(d(1,:),0);
subblock_interleaver(d(2,:),1); subblock_interleaver(d(3,:),2)], …)`. All
three sub-cores and `turbo_encode_top` are individually sim-verified and
unmodified here; only orchestration is new (the QPP-ROM integration pattern).

`turbo_encode_top` streams its `3×(K+4)` output as column triples
`(d0_o,d1_o,d2_o)` with `out_valid` — directly the `d` rows
(`d(1,k)=d0_o`, `d(2,k)=d1_o`, `d(3,k)=d2_o`), `D=K+4`.

## Goals / Non-Goals

**Goals:** `rate_matching_top` bit-exact vs `rate_matching.m`; `tx_chain_top`
bit-exact vs the composed software chain; sub-cores reused unmodified;
golden-vector sim; reuse the established layout/harness.

**Non-Goals:** no decoder/fixed-point/board/screen; no divider-free or BRAM
synthesis hardening (documented follow-on).

## Decisions

1. **Three `subblock_interleaver` in lockstep.** Start idx-0/1/2 instances
   together with the same `D`; each emits element `k` (with `valid`,
   `filler`, `idx_o`) on the same cycle, giving `v(:,k)` per cycle with no
   reordering buffer.

2. **`d` buffered in three async-read arrays.** `rate_matching_top` loads the
   `D` input columns into `d1/d2/d3` (length ≤ 6148). `v(r,k) = filler_r ?
   (bit 0, fill 1) : (bit d_r[idx_o_r], fill 0)`, fed straight into
   `circular_buffer`'s column load.

3. **`K_Pi` computed once and shared.** `K_Pi = 32·⌈D/32⌉ = ((D+31)>>5)<<5`,
   passed to `circular_buffer.start` (it sizes `w` / offsets from it); the
   sub-block interleavers derive the same `K_Pi` internally.

4. **FSM:** `LOAD_D` (D cols) → `INIT` (pulse the 3 subblock starts +
   `circular_buffer` start with `K_Pi/N_ref/I_LBRM/rv/E`) → `STREAM` (K_Pi
   cycles: subblocks emit, form `v`, drive `circular_buffer` `v_valid`) →
   `circular_buffer` auto compute+read → output `E`. Alignment matches the
   sub-cores' verified start-then-next-cycle streaming.

5. **`tx_chain_top` delegates.** `turbo_encode_top` is started with `K` and
   fed the code block; its `out_valid` column stream is the `d` load for
   `rate_matching_top` (started with `D=K+4` and the rate-match params). The
   chain output is `rate_matching_top`'s output.

6. **Golden vectors.** `generate_hdl_rate_matching_vectors.m`: random `d`
   3×D, params → `rate_matching(d,…)`; CSV `D,N_ref,I_LBRM,rv,E,d,e`.
   `generate_hdl_tx_chain_vectors.m`: random code block `c` + `K` + params →
   `e = rate_matching(turbo_encoder(c, internal_interleaver(0:K-1)), …)`;
   CSV `K,N_ref,I_LBRM,rv,E,c,e`. The sim comparison is the oracle.

## Risks / Trade-offs

- **Two new orchestration FSMs + cross-core alignment** → every sub-core is
  already golden-verified; `rate_matching_top` is verified standalone before
  `tx_chain_top` reuses it, so any wiring/timing error surfaces in the
  smaller lane first.
- **`d`/`w` buffers (~6148 / ~18528)** → fine for GHDL sim; BRAM mapping is
  the documented hardening follow-on (as for `turbo_encode_top`).
- **Lockstep assumption** (all 3 subblock instances same `D` ⇒ same `K_Pi`
  and identical timing) → true by construction (same entity, same `D`);
  asserted indirectly by the exact end-to-end comparison.

## Open Questions

- Coverage set: `D` from `K∈{40,512,6144}`; `rv∈{0,1,2,3}`; `I_LBRM∈{0,1}`;
  `E` incl. wrap — pin in tasks; reuse circular-buffer-style parameters.
- CSV `d`/`c` layout — settle in the generators; the lanes are the oracle.
