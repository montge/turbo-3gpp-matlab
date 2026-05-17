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

   Decoder:     float .m ──AWGN BER──► fixed-point reference (we author)
                                            │
                                  golden CSV │ bit-exact
                                            ▼
                                           HDL
```

- **Inner gate (every commit, deterministic):** HDL is bit-exact to a
  **fixed-point reference model** we author in Octave. This preserves the
  existing generator → CSV → cocotb discipline exactly.
- **Outer characterization (periodic, statistical):** the fixed-point
  reference is itself validated against the float `.m` by hard-decision
  agreement / BER over AWGN frames, asserting a **documented bound** (not a
  brittle per-commit gate).

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
| Memory (v1) | **full-block α storage** (8 × (K+3), K ≤ 6144) | sim-OK like prior big buffers (`w[18528]`). Sliding-window BCJR is the synthesis-hardening follow-on. |
| Verify | two-tier (inner bit-exact vs fixed-point ref; outer BER vs float) | preserves the project discipline at the inner layer; honestly addresses "is the fixed-point good enough" at the outer layer |
| Vectors | encode → BPSK + AWGN → LLR at a few SNRs | realistic inputs; the *same* harness feeds the outer BER characterization |
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

- **Build:** (a) the Octave **fixed-point Max-Log-MAP reference** for
  `constituent_decoder` (quantization, per-step max-norm, saturation, fixed
  op-order); (b) the **characterization harness** (fixed-point ref vs float
  `constituent_decoder.m`, hard-decision agreement / BER over AWGN); (c) the
  **HDL core**: γ branch metrics from the 16 trellis transitions, α forward
  recursion (+norm), β backward recursion (+norm), extrinsic
  `x_e = max(δ|x=0) − max(δ|x=1)`; full-block α storage; streaming
  `(x_a,z_a)` in → `x_e` out, length `K+3`.
- **Verify:** inner — cocotb bit-exact vs the fixed-point reference CSV over a
  representative `K` set; outer — characterization asserts agreement within
  the documented band.
- **Defer:** iterative loop, interleaver, CRC, HARQ, filler, exact Log-MAP,
  sliding-window. No board.
- **Exit:** HDL == fixed-point ref bit-exact for all vectors; ref vs float
  within the documented BER band; regression (all TX lanes + Octave) green.

### P2 — `add-fpga-turbo-decoder-loop`

- Iterative decoder: de-mux `3×(K+4)` LLRs into upper `(x_a,z_a)` / lower
  `(x'_a,z'_a)` per `turbo_decoder.m`'s termination layout; `c_a=0`;
  half-iterations upper → interleave → lower → de-interleave, **reusing the
  P1 constituent core and the existing verified `qpp_interleaver` unmodified**.
- Fixed `max_iterations` (no early termination yet); no filler.
- Verify vs a fixed-point `turbo_decoder` reference (same two-tier method).

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
| Fixed-point reference is new trusted code | Outer BER characterization vs float; the reference is a small, reviewable Octave artifact authored before/with P1 |
| Metric overflow | Per-step max-normalization (locked decision); saturating arithmetic; widths pinned with margin |
| Bit-exactness fragility | Max-Log-MAP (`max` associative/exact) + a precisely specified normalization point — the only bit-exactness contract |
| Scope blow-up | Hard increment boundaries (P1 = constituent only); standalone-before-integration; defer list explicit |
| Accuracy loss (Max-Log-MAP) | Accepted & *characterized* in v1 (documented band); M1 recovers it (LUT + scaling) — maturation, not a blocker |
| Memory size (full-block α) | sim-first stance (consistent with TX); sliding-window is the M2 hardening follow-on |

---

## 5. What "mature" eventually means

A decoder is "mature" when: P1–P3 complete (full iterative turbo decode with
early termination, sim-verified); the fixed-point reference is characterized
within a documented BER bound of the float model; and at least M1 (accuracy)
and M2 (sliding-window/BRAM, synthesis-ready) are done. P4 and a board demo
extend toward a full RX path. Until then the decoder is *correct in simulation*
and improving along the accuracy and synthesis axes — exactly the staged
"mature over time" intent.
