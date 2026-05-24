## Why

This is roadmap milestone **M1** (`hdl/docs/decoder_roadmap.md` §3 maturation
track): add the **exact Log-MAP** correction term to the constituent decoder,
plus an **extrinsic scaling factor**, to close the **~0.1–0.5 dB** loss that the
current **Max-Log-MAP** (`max`) algorithm incurs (measured at P2 per the roadmap
risk table). The locked v1 decision (`decoder_roadmap.md` §2) chose plain `max`
deliberately — it is associative/exact in fixed-point, deleting a class of
bit-exactness pain — and named exact Log-MAP (the `max*` / `maxstar` correction
LUT) as a later *accuracy* increment. This change formalizes that increment.

Exact Log-MAP replaces each `max(a,b)` with `max(a,b) + f(|a−b|)` where `f` is a
small **correction LUT**. That **changes the bit-exact contract**: the output is
no longer the Max-Log-MAP `max`-only result, so this needs its **own
exact-Log-MAP fixed-point reference** and fresh **golden vectors**; the HDL is
bit-exact to that new reference. The extrinsic scaling factor (a standard
turbo-decoder refinement) is folded into the same reference.

## What Changes

- **Add** a `max*` correction term to the α/β recurrence and the extrinsic
  computation of the constituent decoder (`fpga-constituent-decoder`): a small
  LUT indexed by `|a−b|` added to each pairwise `max`.
- **Add** an extrinsic scaling factor applied to the exchanged extrinsic LLRs.
- **Author** a new exact-Log-MAP fixed-point **reference model** (Octave) and
  golden vectors; the Max-Log-MAP vectors do NOT carry over.
- **Verify** two-tier per the roadmap: inner cocotb bit-exact vs the new
  exact-Log-MAP reference; outer bounded BER-vs-SNR vs float `turbo_decoder.m`,
  demonstrating the BER improvement (the recovered Max-Log-MAP gap) within a
  documented dB margin.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. LUT precision / index width and the scaling-factor
quantization are deferred to when this change is started.

## Capabilities

### New Capabilities

- `fpga-decoder-exact-log-map`: an exact-Log-MAP constituent decoder variant
  that adds a LUT-based `max*` correction term and an extrinsic scaling factor
  to recover the Max-Log-MAP BER loss, bit-exact to a new exact-Log-MAP
  fixed-point reference (a new bit-exact contract distinct from the Max-Log-MAP
  baseline).

## Impact

- Extends `fpga-constituent-decoder` (and transitively `fpga-turbo-decode-loop`)
  with a more accurate metric; changes the bit-exact golden-vector contract.
- Depends on the two-tier verification discipline (cocotb bit-exact + outer BER
  characterization) and Quartus II 13.0sp1 on the Windows host.
- Risk: the correction LUT adds combinational depth to the already
  Fmax-limiting α recurrence cone — note for the recurrence-pipelining arc; LUT
  precision trades accuracy against width.

## Out of Scope (explicit)

- Sliding-window memory (that is M2 / `add-fpga-decoder-sliding-window`).
- Recurrence pipelining for Fmax (`add-fpga-decoder-recurrence-pipelining`).
- Any board demo of the exact-Log-MAP variant.
