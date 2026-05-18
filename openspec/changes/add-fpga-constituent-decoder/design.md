## Context

`constituent_decoder.m` is a Log-BCJR over the 8-state, 16-transition trellis
of the TS36.212 constituent code: branch metrics `γ = γ_x + γ_z` (input-1
transitions contribute `−x_a`, parity-1 contribute `−z_a`), α forward and β
backward recursions combined via `maxstar`, then
`x_e = maxstar(δ|x=0) − maxstar(δ|x=1)`, length `K+3`. The float model is the
long-trusted golden reference; full multi-increment context is in
`hdl/docs/decoder_roadmap.md` (this change is **P1**).

## Goals / Non-Goals

**Goals:** a board-neutral fixed-point Max-Log-MAP constituent Log-BCJR core
bit-exact to an authored fixed-point reference; that reference characterized
against the float model; reuse of the established layout/harness; the new
two-tier verification methodology established for soft blocks.

**Non-Goals (P1 boundary, see roadmap §3):** iterative turbo loop,
interleaver, CRC early-termination, HARQ, filler/`NaN`, exact Log-MAP LUT,
extrinsic scaling, sliding-window/BRAM, board work, screen.

## Decisions

(Locked decisions are in `hdl/docs/decoder_roadmap.md` §2; this section pins
the P1-specific shape.)

1. **Two-tier oracle.** Inner: cocotb checks HDL **bit-exact** vs an Octave
   fixed-point reference (existing generator→CSV→cocotb discipline). Outer:
   a script asserts **numerical equivalence** of the fixed-point reference vs
   float `constituent_decoder.m` on *identical* LLR frames — extrinsic-LLR
   error statistics + hard-decision agreement within a documented band.
   **This is explicitly NOT a communications-BER check**: a single
   non-iterative constituent decoder has poor BER *by design* (turbo gain is
   the iteration), so absolute BER is meaningless here and is a P2 oracle, not
   a P1 one (see `hdl/docs/decoder_roadmap.md` §1). The fixed-point reference
   is the most safety-critical artifact and is small/reviewable.

1a. **Datapath shape (informs sizing, not behaviour).** The rate-1 trellis has
   exactly 2 transitions in/out of each of 8 states; γ takes only 4 distinct
   values `{0,−x_a,−z_a,−x_a−z_a}`; each α/β step is a 2-way `max`; the
   extrinsic is two 8-way `max` and one subtract. No multiplier, LUT, or
   divider — the cost is the `8×(K+3)` α memory, the `≈3·(K+3)`-cycle
   latency, and fixed-point/normalization, not arithmetic. The interface
   `(x_a,z_a)`→`x_e` (length `K+3`, termination extrinsics included but later
   discarded by the turbo loop) is exactly what P2 will reuse unmodified.

2. **Max-Log-MAP.** `maxstar` → plain `max`. `max` is associative and exact
   in fixed-point, so reduction order is irrelevant — the only bit-exactness
   contract is identical quantization, saturation, and normalization point.

3. **Per-step max-normalization.** After each α (and β) trellis step subtract
   the running max over the 8 states. The constant cancels in
   `x_e = max(δ|x=0) − max(δ|x=1)`, so the extrinsic output is unaffected
   while metric width stays bounded. Specified identically in the reference.

4. **Fixed-point format.** Signed Q-format, saturating. Input LLR width and
   internal α/β/γ widths start generous (functional-first) and are pinned in
   this design once the reference is written; tightening to realistic
   channel-LLR widths is a maturation increment (roadmap M3). The reference
   and HDL share one parameter set.

4a. **±inf sentinel (P1 decides; P3 reuses).** `maxstar` initialises
   impossible α/β states to `−inf`. Fixed-point has no inf, so P1 picks a
   saturating max-magnitude value that (i) never overflows when γ is added and
   (ii) can never spuriously win a `max` against a real metric. This single
   chosen magnitude *is* the decoder-wide "inf" and P3's filler `NaN→+inf`
   handling MUST reuse it — a P1 format decision with a P3 consequence, pinned
   here rather than discovered late (roadmap §2 locked decision).

5. **Full-block α storage.** Compute and store all α (8 states × `K+3`), then
   sweep β backward computing `x_e` on the fly. Sim-OK like prior large
   buffers; sliding-window is roadmap M2 (synthesis hardening).

6. **Streaming interface, K-agnostic.** `start` latches `K`; load `K+3`
   `(x_a,z_a)` LLR pairs; core runs γ → α(store) → β(+extrinsic); stream
   `K+3` `x_e` out with `valid`/`last`. Representative `K` set like every
   prior lane; no filler (a turbo_decoder-level concern, deferred).

7. **Realistic vectors.** The generator encodes random code blocks with the
   already-verified encoder path, maps to BPSK + AWGN at a few SNRs, forms
   LLRs, quantizes, runs the fixed-point reference → golden `(x_a,z_a,x_e)`
   CSV. The same frames feed the outer **equivalence** check (fixed vs float
   on identical inputs) — bounded (few SNRs, modest frame counts) so it stays
   tractable in Octave.

## Risks / Trade-offs

- **Fixed-point reference is new trusted code** → outer equivalence check vs
  the float model on identical inputs; reference kept small and reviewed; it
  is authored and validated *before* the HDL is trusted.
- **Metric overflow** → per-step max-normalization (locked) + saturating
  arithmetic + width margin + the ±inf sentinel chosen not to overflow under
  +γ; asserted at the largest `K`.
- **Max-Log-MAP accuracy loss** → at P1 only fixed-vs-float *equivalence* is
  checked (a lone constituent decoder's BER is poor by design); the
  communications loss is measured at P2 (bounded BER) and recovered later by
  roadmap M1 (LUT + extrinsic scaling).
- **Bit-exactness fragility** → minimized by Max-Log-MAP (order-independent)
  and a single precisely-specified normalization point.
- **Verification-methodology novelty** → this is the first soft/fixed-point
  block; the two-tier method is documented here and in the roadmap so later
  decoder increments reuse it unchanged.

## Fixed-point format — first cut (reasoned start; confirm/tighten in task 1.2)

Generous starting point (roadmap M3 tightens later). Because the inner gate is
bit-exact to *our* reference, "wrong" widths cost only equivalence-band/area,
never correctness — so start wide.

| Quantity | Format (signed) | Width | Derivation |
|---|---|---|---|
| input LLR `x_a,z_a` | Q4.3 (I=4,F=3) + sign | **W_in = 8** | range ≈ [−16,+16), step 0.125; AWGN LLRs at useful SNR mostly within ±~12; F=3 keeps quantization error small for the equivalence band |
| branch metric γ | — | **W_γ = W_in+1 = 9** | γ ∈ {0,−x_a,−z_a,−x_a−z_a} ⇒ \|γ\| ≤ \|x_a\|+\|z_a\| |
| α, β (post-norm) | — | **W_αβ = W_in+6 = 14** | per-step max-norm caps max at 0; the 8-state, memory-3 trellis bounds the normalized spread to ≲ ~8·max\|γ\| ⇒ ≲ ~2048 LSB ≪ 2^13 |
| δ = α+β+γ_z | — | **W_δ = W_αβ+2 = 16** | sum of two W_αβ values + a γ term |
| extrinsic x_e | — | **W_xe = W_δ+1 = 17** | `max(δ\|x=0) − max(δ\|x=1)` (signed difference) |

**±inf sentinel + overflow argument.** `MIN_SENT = −2^(W_αβ−1) = −8192`,
`MAX_SENT = +(2^(W_αβ−1)−1)`; **all α/β/δ adds saturate** (never wrap). Real
post-normalization metrics lie in ≈[−2048, 0] LSB; the sentinel at ∓8192 is
~4× beyond that, and saturating add can only push it *further* from 0 — so an
impossible state can never spuriously win a `max` (`max(MIN_SENT, real)=real`
always). P3's filler `+inf` reuses `MAX_SENT` symmetrically. At `k=0` only
state 1 = 0, others = `MIN_SENT`, per-step max = 0 (correct).

**Normalization point (bit-exactness contract).** Each α step: compute the 8
next-state metrics, take `m = max` over the 8, store `α − m`; identical for β.
The reference and HDL MUST use the same max-set, the same subtraction point,
and the same saturation. With Max-Log-MAP (`max` exact/associative) this is
the *entire* bit-exactness contract.

**Equivalence-band knob.** If the outer fixed-vs-float equivalence band is too
loose, increase **F** (fractional bits), not integer bits — the gap is
quantization-resolution-bound, not range-bound (range is comfortably covered).

## Open Questions

- The table above is a *reasoned first cut*, not the final pin. Task 1.2
  confirms/tightens it once the reference is written and characterized
  (mainly: is F=3 enough for the equivalence band; can W_αβ shrink).
- LLR computation detail (e.g. `2/σ²` scaling vs normalized) — settle in the
  reference; the inner gate is bit-exact regardless of scaling; the outer
  equivalence check is sensitive to F (resolution), addressed by the knob
  above.
