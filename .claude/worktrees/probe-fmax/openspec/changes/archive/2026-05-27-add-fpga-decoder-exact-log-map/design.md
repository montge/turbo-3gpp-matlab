# Design — add-fpga-decoder-exact-log-map (M1)

## 1. Context

The float oracle already supports exact Log-MAP. `maxstar.m` is the Jacobian
logarithm used by `constituent_decoder.m` at every metric combine:

```matlab
% maxstar.m, global approx_star
if approx_star          % Max-Log-MAP (v1 fixed-point + HDL baseline)
    c = max(a,b);
else                    % exact Log-MAP (the M1 target)
    c = max(a,b) + log(1+exp(-abs(a-b)));
end
% n-ary form: sequential fold c = maxstar(c, a(i)) over rows i=2..N.
```

`constituent_decoder.m` calls `maxstar` in exactly four places:

| Site | `constituent_decoder.m` | combine |
|---|---|---|
| α recurrence | line 74 `alphas(s,k)=maxstar(temp(into s))` | 2-way (2 transitions into each state) |
| β recurrence | line 84 `betas(s,k)=maxstar(temp(outof s))` | 2-way |
| extrinsic `log_p0` | line 92 `maxstar(deltas(x==0,:))` | 8-way (8 transitions, x=0) |
| extrinsic `log_p1` | line 93 `maxstar(deltas(x==1,:))` | 8-way |

So **`approx_star=false` (float exact Log-MAP) is the BER oracle**; the P2/RX
characterizers already wire it (`characterize_constituent_decoder.m` computes
`x_e_fl_ex` with `approx_star=false`). This change authors a **fixed-point
exact-Log-MAP reference** as the inner bit-exact oracle, and the HDL is bit-exact
to *that*.

The current fixed-point Max-Log-MAP reference
(`scripts/fixedpoint_constituent_decoder.m`) does each combine as a plain
`max(cand1,cand2)` / `max(deltas_k(x==0))`. The exact-Log-MAP reference = the
same datapath with `max*(a,b)=max(a,b)+lut(|a−b|)` substituted at every `max`,
plus the 8-way maxes expanded into an explicitly-ordered tree of 2-way `max*`
(see §4). Pinned widths are inherited unchanged: `W_in=9, F_in=4, W_gamma=10,
W_ab=15, W_delta=17, W_xe=18`.

## 2. The maxstar → correction-LUT mapping

`max*(a,b) = max(a,b) + f(|a−b|)`, `f(d) = ln(1 + e^−d)`.

In fixed-point everything is integer LSB codes at `F_in=4` (`lsb = 2^−4 =
0.0625`). Let `dcode = |a − b|` be the integer code of the absolute difference
(`a`, `b` are already in `W_ab`/`W_delta` integer codes at the same `F_in`
scale, so their difference is on the same grid — no rescale). The correction is

```
corr_code(dcode) = round( f(dcode · lsb) / lsb ) = round( ln(1+e^−(dcode·0.0625)) · 16 )
```

added to the integer `max(a,b)`. This is the **same round-half rule** the
reference uses elsewhere, so the reference's `lut` is generated once at author
time and the HDL embeds the identical constants.

### Decision: per-`max*`-site placement

After **every** 2-way `max` in the datapath — the 8 α combines, the 8 β
combines, and each 2-way node of the two extrinsic max-trees — insert
`+ corr_code(sat(|a−b|))`. The α/β post-step **max-normalization** (subtract the
per-step running max) is **unchanged** — it is a `max`+subtract over already-
computed `max*` values, and the normalization constant still cancels in the
final `log_p0 − log_p1` extrinsic difference, so it does NOT itself get a
correction term (it is not a metric combine of two competing paths; it is a
bookkeeping offset). This matches `constituent_decoder.m`: `maxstar` is applied
to the trellis aggregation only; the float model has no normalization step (it
relies on float dynamic range), and the fixed-point reference's normalization is
a width-control device that must stay a plain `max` so it remains exactly the
two references' shared offset.

> Bit-exactness consequence: the correction is applied at the **aggregation**
> maxes only (α into-state, β outof-state, extrinsic δ folds). The per-step
> `m = max(new_alpha)` normalization and the final `sat_sub(log_p0, log_p1)` are
> plain ops in both modes. This is pinned identically in reference and HDL.

## 3. The correction LUT — pinned (depth / contents / width)

Generated at `F_in=4` (`octave: round(log(1+exp(-(0:D-1)*2^-4))*16)`):

| dcode (index) | real |a−b| | f = ln(1+e^−d) | corr_code = round(f·16) |
|---|---|---|---|
| 0 | 0.0000 | 0.69315 | **11** |
| 1 | 0.0625 | 0.66239 | 11 |
| 2 | 0.1250 | 0.63260 | 10 |
| 4 | 0.2500 | 0.57594 | 9 |
| 6 | 0.3750 | 0.52312 | 8 |
| 9 | 0.5625 | 0.45094 | 7 |
| 12 | 0.7500 | 0.38687 | 6 |
| 15 | 0.9375 | 0.33046 | 5 |
| 18 | 1.1250 | 0.28115 | 4 |
| 23 | 1.4375 | 0.21311 | 3 |
| 31 | 1.9375 | 0.13889 | 2 |
| 39 | 2.4375 | 0.08394 | … 1 region … |
| 55 | 3.4375 | 0.03164 | **1** |
| 56 | 3.5000 | 0.02975 | **0** (and all larger) |

**Pin:**

- **Depth `LUT_D = 56`** entries, index `dcode ∈ 0..55`. `corr_code(56)=0` and
  monotonically 0 thereafter (the term is sub-½-LSB beyond `dcode=55`), so the
  LUT is exhaustive: every nonzero correction is represented.
- **Index handling:** compute `dcode = |a − b|` (a `W_ab`- or `W_delta`-wide
  unsigned magnitude), **saturate to 55**, use as the 6-bit ROM address
  (`ceil(log2(56)) = 6` bits). Saturating the index (not the difference) is
  exact because the LUT is flat-0 above 55.
- **Value width:** `corr_code ∈ 0..11` ⇒ **4-bit unsigned** ROM word.
- **Storage:** 56 × 4 bits = **224 bits**. Realized as distributed LUT-ROM /
  case-statement in logic, **not** M4K (well below the 4 Kbit M4K granularity;
  pinning it to M4K would waste a whole block). **Zero M4K cost** — the whole
  point of M1 being no-fit-pressure.

The reference (`scripts/fixedpoint_constituent_decoder_exact.m`, new) builds this
table by the formula above and asserts the embedded HDL constants match it
(a generator-side cross-check, mirroring the W-format header discipline of
`fixedpoint_constituent_decoder.m`).

## 4. The 8-way extrinsic max* tree (the bit-exactness hazard)

Plain `max` is associative & exact, so the Max-Log-MAP 8-way reduction order is
irrelevant for the *value*. **`max*` is NOT associative** —
`max*(max*(a,b),c) ≠ max*(a,max*(b,c))` in general, because the correction
depends on the running partial-max. Therefore the reduction **order is now part
of the bit-exact contract** and reference and HDL MUST fold identically.

**Pin the fold to match the float oracle exactly.** `maxstar.m`'s n-ary form is a
**sequential left fold** over the rows in their natural (ascending transition-
index) order:

```
acc = delta(first x=0 transition)
for each subsequent x=0 transition t (ascending t):
    acc = max*(acc, delta(t))      % = max + lut(|acc - delta(t)|)
log_p0 = acc                        % (then same for x=1)
```

The x=0 transitions in ascending index are `{1,2,3,4,5,6,7,8}` and x=1 are
`{9,10,11,12,13,14,15,16}` (per the trellis in `constituent_decoder.vhdl`
`T_XBIT`). The reference performs the sequential fold in this order; the HDL
replaces its current incremental `imax(max0, delta)` accumulation (which already
walks `t = 1..16` in order — see `constituent_decoder.vhdl` lines 557–566) with
`max0 := maxstar(max0, delta)`, preserving the exact same visitation order. The
α/β 2-way combines have only two operands so order is moot, but the reference
and HDL still pin `max*(cand1, cand2)` with `cand1` from the lower transition
index (`A_TRAN(s)(0)` / `B_TRAN(s)(0)`), matching the `.m` `into_state{}` order.

> **Init of the fold.** The HDL today seeds `max0/max1 := DE_MIN` then folds in
> all eight δ. With `max*`, seeding from a sentinel would inject a spurious
> correction `lut(|DE_MIN − δ₀|)` (= 0 since the gap ≫ 55, so harmless) — but to
> be unambiguous the reference and HDL both **seed from the first δ of the set**
> (no synthetic sentinel in the fold) and fold the remaining seven. Pinned
> identically.

## 5. Generic-mode superset (default Max-Log-MAP stays bit-exact)

Add `EXACT_LOGMAP : boolean := false` to `constituent_decoder`'s generic list.
The `max*` is realized as a function `maxstar(a,b)` that, **when
`EXACT_LOGMAP=false`, returns `imax(a,b)` with no LUT lookup and no add** — i.e.
`f ≡ 0`. Synthesis with the default constant-folds the LUT/adder away entirely,
so the default build is structurally identical to today's core.

Consequences (the superset guarantee):

- **Default mode is bit-exact to the current Max-Log-MAP golden vectors** — the
  existing `constituent_decoder` (27 frames), `turbo_decoder_top` (20),
  `turbo_decoder_term_top` (10), and `rx_chain_top` lanes stay green
  **unchanged**, with byte-identical vectors. No regeneration of any existing
  vector.
- **Exact mode** (`EXACT_LOGMAP=true`) gets its **own** golden CSV from the new
  exact reference; a dedicated cocotb lane checks it.
- Upstream wrappers (`turbo_decoder_top`, etc.) forward the generic
  (defaulting `false`) so a top-level can opt into exact mode without touching
  the loop algebra — `z_a` constancy, QPP, half-iteration FSM all unchanged.

**Why generic-gate, not unconditional replace.** An unconditional `max*` would
change *every* decoder output and force regenerating + re-reviewing every
decoder lane's golden vectors (constituent + turbo + term + rx), turning an
accuracy add-on into a churny re-verification of the whole decoder stack. The
generic keeps the proven baseline as the default contract and makes exact Log-MAP
a strictly additive, opt-in superset — the same discipline the roadmap used to
keep `max` as the locked v1 (`decoder_roadmap.md` §2).

## 6. Extrinsic scaling factor — decision

Extrinsic scaling (`x_e ← sf · x_e`, `sf ≈ 0.7–0.8`) is a standard turbo
refinement that **compensates Max-Log-MAP over-optimism**: Max-Log-MAP
overestimates extrinsic magnitude (it drops the always-positive `f` term), and
scaling damps that to recover much of the loss *without* the LUT. With **exact**
`max*` the magnitudes are already correct, so the original motivation for scaling
largely disappears.

**Decision: v1 of this change OMITS the unconditional scaling multiply.**
Rationale:

1. Exact Log-MAP and extrinsic scaling are **two attacks on the same loss**;
   stacking both risks over-damping. The clean experiment is exact-`max*` alone
   first.
2. A scaling multiply (even by a shift-add constant like `0.75 = 1 − 1/4`, no
   DSP) adds datapath + a *new* bit-exact knob to pin per width — cost without
   clear benefit once `max*` is exact.
3. The float sizing sweep (§8) measures whether scaled-Max-Log-MAP rivals exact
   Log-MAP; if scaling alone closed the gap as well as `max*`, that would be an
   argument to ship scaling *instead* (cheaper). The data inform which to keep.

**Reserved, not deleted:** a documented `EXTR_SCALE_NUM/DEN` generic (default =
1/1, i.e. off) is noted as the follow-on hook. If the implementation's BER data
show residual loss that exact `max*` alone doesn't close, a shift-add scale (e.g.
`×0.75` = `x − (x>>2)`) is added then, behind its own generic, multiplier-free.
This keeps v1 focused and the datapath DSP-free.

## 7. Verification (two-tier + BER)

Inner (deterministic, every commit):

- **Exact-mode lane.** cocotb drives `constituent_decoder` with
  `EXACT_LOGMAP=true`, asserts **bit-exact** vs the new exact-Log-MAP reference's
  golden CSV over the representative K set.
- **Default-mode regression.** `EXACT_LOGMAP=false` build re-runs the existing
  constituent / turbo / term / rx lanes against their **unchanged** vectors —
  proves the superset (default == today's Max-Log-MAP, byte-identical).

Outer (bounded, periodic) — **BER showing the gain** (`decoder_roadmap.md` §1
P2/P3 semantics):

- A bounded BER-vs-SNR harness (`scripts/characterize_exact_log_map.m`, new)
  decodes the **same** AWGN frames three ways: **(a)** fixed-point Max-Log-MAP
  (`fixedpoint_turbo_decoder.m`), **(b)** fixed-point exact Log-MAP (new exact
  reference in the loop), **(c)** float exact Log-MAP (`turbo_decoder.m`,
  `approx_star=false`) as the upper bound. Few SNR points, modest frames, shallow
  target BER (~1e-2..1e-3) — a trend/margin check, not a deep waterfall.
- **Gate:** fixed-point exact (b) sits **at or above** fixed-point Max-Log-MAP
  (a) by a documented dB margin, and **within** a documented margin of float
  exact (c). Quantify the dB recovered (the M1 deliverable). The default-mode
  fixed-point output remains identical to (a) (sanity tie-back).

Fit/regression: a Quartus II 13.0sp1 fit of `constituent_decoder` with
`EXACT_LOGMAP=true` records LE / **M4K (must be unchanged from default — the LUT
is logic)** / Fmax delta from the added correction-add depth (a note for the
recurrence-pipelining arc).

## 8. Float sizing of the expected gain (read-only, this proposal)

A bounded read-only float sweep (`turbo_decoder.m`, K=512, 6 iters, BPSK+AWGN)
was run to *size* the M1 target before committing to the design: Max-Log-MAP vs
exact Log-MAP (`approx_star` toggle) vs scaled-Max-Log-MAP (`sf=0.75`). Results
are recorded in §9 (Open Questions / sizing) of this design. The implementation's
own `characterize_exact_log_map.m` produces the authoritative numbers; this is
only an order-of-magnitude check that the gain is real and worth the increment.

## 9. Risks & open questions

| Risk / question | Disposition |
|---|---|
| `max*` non-associativity ⇒ 8-way fold order is now bit-exact contract | **Pinned**: sequential left fold in ascending transition index, seed from first δ; reference and HDL share the order (§4) |
| Correction added at the wrong sites (normalization, final subtract) | **Pinned**: correction only at α/β aggregation + extrinsic δ folds; max-norm & final `log_p0−log_p1` stay plain `max`/`sub` (§2) |
| LUT precision vs `F_in` | LUT generated at `F_in=4`; depth 56 captures every nonzero correction (sub-½-LSB beyond) — pinned (§3). If F is tightened in M3, the LUT regenerates from the same formula |
| Combinational depth on the α recurrence (Fmax) | The correction-add lengthens the already-binding α cone (~15 MHz, `decoder_roadmap.md` §6). Documented note for `add-fpga-decoder-recurrence-pipelining`; not a blocker for an accuracy increment (DE2 demo runs slow clock) |
| Extrinsic scaling needed too? | v1 **omits** the multiply (exact `max*` removes the main motivation); reserved as a documented follow-on generic if BER residual warrants (§6) |
| Open: exact dB recovered & whether scaling-alone rivals `max*` | Sized by the float sweep (§8); pinned precisely by `characterize_exact_log_map.m` at implementation |
| Open: expose exact mode at `turbo_decoder_top` / `rx_chain_top`? | Forward the generic (default `false`); a board demo of exact mode is **out of scope** here |
