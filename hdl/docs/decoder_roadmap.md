# HDL Turbo Decoder — Comprehensive Roadmap

Status: planning (scoped 2026-05-17). The complete LTE **transmit** chain is
done and sim-verified in HDL. The decoder is the next major effort. It is
fundamentally harder than every TX block and is therefore staged into bounded
OpenSpec increments that **mature over time** — correctness-first in
simulation, then accuracy and synthesis hardening.

This document is the multi-increment plan. Each increment below becomes its own
OpenSpec change (propose → implement → verify → archive), exactly like the TX
blocks.

---

## 1. Why the decoder breaks the established pattern

Every TX block was bit-exact integer/bit logic, verified bit-for-bit against a
CSV produced by a long-trusted `.m`. The decoder is **soft / LLR /
floating-point**, so the HDL is **fixed-point** and *cannot* be bit-exact to
`constituent_decoder.m` / `turbo_decoder.m`. The verification oracle must
change.

```
   TX blocks:   float .m ──CSV──► HDL              (one bit-exact gate)

   Decoder:     float .m ──outer check──► fixed-point reference (we author)
                                            │
                                  golden CSV │ bit-exact
                                            ▼
                                           HDL
```

- **Inner gate (every commit, deterministic):** HDL is bit-exact to a
  **fixed-point reference model** we author in Octave. This preserves the
  existing generator → CSV → cocotb discipline exactly.
- **Outer characterization (periodic, statistical):** the fixed-point
  reference is validated against the float `.m`. **The outer-check semantics
  differ by phase** (a single non-iterative constituent decoder is a
  deliberately weak decoder — its absolute BER is poor *by design*, so BER is
  meaningless at P1):
  - **P1 — numerical equivalence.** On *identical* LLR frames, the
    fixed-point reference's extrinsic LLRs and hard decisions track the float
    `constituent_decoder.m` within a documented error/agreement band. **Not a
    communications-BER check.**
  - **P2/P3 — communications BER.** Once the loop iterates, a *bounded*
    BER-vs-SNR comparison of the fixed-point turbo decoder against the float
    `turbo_decoder.m` within a documented dB margin (where the Max-Log-MAP
    ~0.1–0.5 dB loss is actually measured).
  - The harness MUST be explicitly **bounded** (few SNR points, modest frame
    counts, shallow target BER ~1e-2–1e-3 — a trend/margin check, not a deep
    waterfall, which would be intractable in Octave).

**The single most safety-critical artifact of the whole decoder effort is the
fixed-point reference model.** Its correctness is established statistically
(outer check), not by bit-exactness to existing trusted code. It deserves the
most review.

---

## 2. Locked design decisions (apply to all increments)

| Decision | Choice | Rationale |
|---|---|---|
| Algorithm (v1) | **Max-Log-MAP** (plain `max`) | Sanctioned by the spec's `approx_star`. `max` is associative & exact in fixed-point → reduction order is irrelevant, deleting a whole class of bit-exactness pain. Exact Log-MAP (maxstar + correction LUT) is a later *accuracy* increment. |
| Metric growth | **Per-step max-normalization** of α and β (subtract running max over the 8 states each trellis step) | Bounds metric width; the constant cancels in the final `log_p0 − log_p1` extrinsic difference, so output is unaffected. Must be specified identically in the reference. |
| Fixed-point | signed Q-format, saturating; input LLR + α/β/γ widths pinned per increment, generous first then tightened | v1 verifies against our own reference, so widths can start generous and **mature** toward realistic (~6-bit channel LLR) once functionally correct. |
| **±inf sentinel** | **P1 picks the saturating max-magnitude value that behaves as ±inf under `max`+add (no overflow, never spuriously wins); P3's filler `NaN→+inf` REUSES it.** | `maxstar` inits impossible states to `−inf`; `turbo_decoder` maps filler to `+inf`. Fixed-point has no inf — the saturation magnitude *is* the decoder-wide "inf". A P1 format decision with P3 consequences; pin it once. |
| Memory (v1) | **full-block α storage** (8 × (K+3), K ≤ 6144) | sim-OK like prior big buffers (`w[18528]`). Sliding-window BCJR is the synthesis-hardening follow-on. |
| Verify | two-tier; inner bit-exact vs fixed-point ref (all phases); outer = **equivalence at P1, BER at P2/P3** (see §1) | preserves the project discipline at the inner layer; the outer layer's *meaning* is phase-dependent — equivalence before the loop exists, BER once it does |
| Vectors | encode → BPSK + AWGN → LLR at a few SNRs | realistic inputs; the *same* frames feed the outer check. **Large-`K` cases kept few** (full-block BCJR × 2·I constituent calls ≈ `~6·I·K` cycles/block — the `tx_chain_top` lesson, pre-committed). |
| Discipline | standalone-before-integration, sub-cores reused unmodified, sim-first | identical to the TX effort (constituent_encoder → turbo_encoder, etc.) |

---

## 3. Phased increments

```
 P1  add-fpga-constituent-decoder      ◄── implement first
       fixed-point reference + char harness + Log-BCJR core
              │  (verified bit-exact vs ref; BER vs float)
              ▼
 P2  add-fpga-turbo-decoder-loop
       iterative upper/lower, reuse qpp_interleaver (already built!)
       + constituent core unmodified; fixed half-iteration count
              │  (verified vs fixed-point turbo_decoder ref)
              ▼
 P3  add-fpga-turbo-decoder-termination
       CRC-aided early termination + filler(NaN→+inf) + HARQ accumulation
              │
              ▼
 P4  RX-chain integration  (de-rate-matching → decoder)   [scope later]
              │
              ▼
 Maturation track (parallel, optional, layered on a working decoder):
   M1 exact Log-MAP correction LUT + extrinsic scaling factor (accuracy)
   M2 sliding-window BCJR + BRAM mapping (memory/throughput synthesis)
   M3 fixed-point width tightening to realistic channel-LLR formats
   M4 optional DE2 board demo (switches/LEDs, no screen)
```

### P1 — `add-fpga-constituent-decoder` (the keystone)

- **Datapath is small** (rate-1 trellis ⇒ exactly 2 transitions in/out per
  state; γ has only 4 distinct values `{0,−x_a,−z_a,−x_a−z_a}`; α/β step =
  2-way `max`; extrinsic = two 8-way `max` + a subtract). No multiplier, LUT,
  or divider — *simpler* than the encoder. The engineering is the `8×(K+3)`
  α memory, the `≈3·(K+3)`-cycle latency, and fixed-point/normalization.
- **Build:** (a) the Octave **fixed-point Max-Log-MAP reference** for
  `constituent_decoder` (quantization, per-step max-norm, saturation, the
  ±inf sentinel, fixed op-order); (b) the **equivalence harness**
  (fixed-point ref vs float `constituent_decoder.m` on *identical* LLR
  frames); (c) the **HDL core**: γ from the 16 transitions, α forward
  (+norm), β backward (+norm), `x_e = max(δ|x=0) − max(δ|x=1)`; full-block α;
  streaming `(x_a,z_a)` in → `x_e` out, length `K+3`.
- **Verify:** inner — cocotb bit-exact vs the fixed-point reference CSV over a
  representative `K` set; outer — **numerical equivalence** (extrinsic-LLR
  error stats + hard-decision agreement of fixed-point ref vs float on
  identical inputs) within the documented band. **Not a BER check** (a lone
  constituent decoder's BER is poor by design; BER is a P2 oracle).
- **Defer:** iterative loop, interleaver, CRC, HARQ, filler, exact Log-MAP,
  sliding-window. No board.
- **Exit:** HDL == fixed-point ref bit-exact for all vectors; ref vs float
  within the documented *equivalence* band; regression (all TX lanes +
  Octave) green.
- **Forward-looking (validated by `turbo_decoder.m`):** the loop calls this
  core with pre-summed `(x_a,z_a)` and discards the 3 termination extrinsics
  — so P1's interface is exactly what P2 needs, and P2 reuses this core **and**
  the already-verified `qpp_interleaver` unmodified (`z_a` is constant across
  iterations; only the systematic a-priori changes).

### P2 — `add-fpga-turbo-decoder-loop`

- Iterative decoder: de-mux `3×(K+4)` LLRs into upper `(x_a,z_a)` / lower
  `(x'_a,z'_a)` per `turbo_decoder.m`'s termination layout; `c_a=0`;
  half-iterations upper → interleave → lower → de-interleave, **reusing the
  P1 constituent core and the existing verified `qpp_interleaver` unmodified**.
- Fixed `max_iterations` (no early termination yet); no filler. Memory is
  modest: persistent `z_a`/`z'_a`/channel-systematic + exchanged `c_a`/`c_e`
  (K-length) + the reused core's α RAM — not a new hard problem.
- Verify: inner bit-exact vs a fixed-point `turbo_decoder` reference; outer is
  now a **bounded BER-vs-SNR** comparison vs float `turbo_decoder.m` within a
  documented dB margin (this is where iterative/Max-Log-MAP performance is
  actually measured). Keep large-`K` vectors few (cycle-budget, §2).

### P3 — `add-fpga-turbo-decoder-termination`

- Add the deferred `turbo_decoder.m` behaviours: CRC-aided early termination
  (needs a CRC-check core — assess reuse vs new; turbo uses CRC24), filler
  `NaN→+inf` handling, optional HARQ LLR accumulation. May split if large.

### P4 — RX-chain integration (scope later)

- Inverse rate-matching (de-rate-matching / soft combining) feeding the
  decoder, toward a full RX chain mirroring the `tx_chain_top` capstone.
  Scoped when P1–P3 land.

### Maturation track (M1–M4)

Layered onto a *working* decoder, each its own change: exact Log-MAP LUT +
extrinsic scaling (close the Max-Log-MAP gap), sliding-window + BRAM
(synthesis/throughput), fixed-point tightening (realistic widths), optional
board demo.

---

## 4. Risks & how the plan addresses them

| Risk | Mitigation |
|---|---|
| Fixed-point reference is new trusted code | Outer check vs float (equivalence at P1, BER at P2/P3); the reference is a small, reviewable Octave artifact authored before/with P1 |
| Metric overflow | Per-step max-normalization (locked); saturating arithmetic; widths + ±inf sentinel pinned with margin |
| Bit-exactness fragility | Max-Log-MAP (`max` associative/exact) + a precisely specified normalization point + shared ±inf sentinel — the entire bit-exactness contract |
| Scope blow-up | Hard increment boundaries (P1 = constituent only); standalone-before-integration; defer list explicit |
| Accuracy loss (Max-Log-MAP) | At P1 only fixed-vs-float *equivalence* is checked (BER of a lone constituent decoder is meaningless); the communications loss is measured at **P2** (bounded BER); M1 recovers it (LUT + scaling) — maturation, not a blocker |
| Characterization intractable | Outer harness explicitly bounded (few SNRs, modest frames, shallow target BER) — a trend/margin check, not a deep waterfall |
| Memory size (full-block α) | sim-first stance (consistent with TX); sliding-window is the M2 hardening follow-on |

---

## 5. What "mature" eventually means

A decoder is "mature" when: P1–P3 complete (full iterative turbo decode with
early termination, sim-verified — P1 fixed-point ref equivalent to float on
identical inputs; P2/P3 fixed-point turbo within a documented BER margin of
float `turbo_decoder.m`); and at least M1 (accuracy) and M2
(sliding-window/BRAM, synthesis-ready) are done. P4 and a board demo
extend toward a full RX path. Until then the decoder is *correct in simulation*
and improving along the accuracy and synthesis axes — exactly the staged
"mature over time" intent.
