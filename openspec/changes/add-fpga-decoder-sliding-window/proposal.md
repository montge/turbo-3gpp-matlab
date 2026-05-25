## Why

This is roadmap milestone **M2** (`hdl/docs/decoder_roadmap.md` §3 maturation
track), **RE-SCOPED after a negative fit result**. The original M2 thesis was:
window the constituent decoder's **full-block α RAM** so the **full K = 6144
decoder fits on-chip** and the M4K footprint drops at every K. Stage 1 of M2
(`#73`, commit `5cd92ce`) authored the windowed fixed-point reference
(`scripts/fixedpoint_constituent_decoder_sw.m`) and characterised it (`W = 64`,
`L = 48`, byte-exact superset + bounded windowing loss). **The HDL windowing
(task 3.1) was never implemented.** Before implementing it, a Quartus fit of the
*existing* `turbo_decoder_top` was run to confirm the α-windowing payoff — and it
**disproved the M2 thesis**:

- **α windowing delivers ZERO M4K benefit in `turbo_decoder_top`.** K = 512 with
  a short α window (`WINDOW_LEN = 64`) and K = 512 full-block
  (`WINDOW_LEN = 6147`) both fit at the **identical ~61/105 M4K**. (See the
  WINDOW_LEN-propagation caveat below — the headline 61 = 61 holds regardless.)
- **K = 6144 does not fit** — it needs **far more than 105 M4K** (≈ 2.3 Mbit of
  physical block-RAM-equivalent), and shrinking α does not move that needle.

The reason: **α was never the binding M4K constraint in the integrated decoder.**
The α RAM is local to one constituent call. The wall is `turbo_decoder_top`'s
**iterative-loop LLR memories** (`ca_mem`, `ce_mem`, `chs_mem`, `za_mem`,
`zpa_mem`, `xpa_body`, `xpe_body` — ~5–7·K words; `ca_mem` alone is 4 M4K at
K = 512), **plus** the constituent's own K-deep input buffers
(`xa_mem` / `za_mem`). At K = 6144 the loop LLR memories scale to **~264 M4K**
and the constituent input buffers to **~72 M4K** more — both **far over the 105
M4K budget**, and **neither is touched by α windowing**. This change is
**re-scoped to attack that real wall** and to give an honest verdict on whether
full K = 6144 is reachable on the EP2C35 at all.

### The WINDOW_LEN-propagation question (resolved, with a caveat)

The diagnostic intent was: fit `turbo_decoder_top` at `WINDOW_LEN = 64` vs `6147`
and read the synthesized `alpha_mem` Port-A depth — depth 64 ⇒ windowing
propagated (so the 0-M4K-benefit result is genuine), depth ~515 ⇒ the generic did
not propagate (so the result is partly an artifact). **The honest answer: there
is NO `WINDOW_LEN` generic anywhere in the HDL** (`constituent_decoder.vhdl` is
parameterised only by `N_MAX = K+3`; `grep -r WINDOW_LEN hdl/**/*.vhdl` →
no matches). The windowed HDL (task 3.1) was never written. So the only depth
knob is `N_MAX`, and `alpha_mem`'s synthesized Port-A depth is therefore **~515 at
K = 512** in *both* runs — i.e. the "WINDOW_LEN = 64 vs 6147" experiment did not
(and could not) shrink the α store, which is exactly **why the two fits are
identical (61 = 61)**. The negative conclusion is **not** an artifact of a
non-propagating generic; it is more fundamental: **α windowing is unimplemented,
and even if implemented it cannot help, because α is not the binding constraint.**

## What Changes

- **Record the negative fit finding** as the headline result: windowed-α →
  0 M4K benefit in `turbo_decoder_top`; the loop LLR memories + the K-deep input
  buffers are the real wall; K = 6144 does not fit and α windowing cannot make
  it fit.
- **Quantify the loop-LLR-memory wall** per memory at K = 512 and K = 6144,
  calibrated to the recorded `ca_mem = 4 M4K` data point, and pin the **maximum
  on-chip K** that fits the EP2C35 today (full-block α) and with windowed α.
- **State the interleaver-global-access constraint** that rules out simple
  on-chip "windowing" of the loop memories the way α was windowed: every lower
  half-iteration reads `x'_a = c_e[π[k]]` and scatters `c_a[π[k]] = x'_e` through
  the QPP interleaver π over the **entire K-bit block** — there is no local
  window of the interleaved access, so the loop LLR arrays need full random
  access each half-iteration and cannot be streamed/checkpointed on-chip.
- **Assess the external-memory path** (the only realistic route to full K) on the
  DE2's **512 KB SRAM** and **8 MB SDRAM**, with an honest latency-vs-decode-budget
  verdict and a controller-effort estimate.
- **Give a recommendation** (below) and **re-stage all tasks UNCHECKED** for the
  recommended path. **No `hdl/`, `scripts/`, `.qsf`, or `.m` edits land in this
  change** — it is design/analysis only.

## The recommendation (justified in design.md)

**(a) Shelve windowed-α** as a `turbo_decoder_top` M4K lever — it delivers 0 M4K
in the integrated decoder and does not move the K = 6144 wall. **Keep the Octave
windowed reference + characterization** (`#73`) as a documented, validated
artifact: it is still correct, it modestly raises the *constituent-standalone*
on-chip K ceiling (≈ 1016 → ≈ 1536), and it is directly reusable for a future
ASIC / larger-FPGA target where α *is* on the critical-area path. It is shelved,
not deleted.

**(b) Accept an on-chip maximum-K cap** for the EP2C35 (≈ **K ≤ 1008** full-block;
≈ **K ≤ 1536** if windowed-α is later wired in) and treat full K = 6144 on this
board as reachable **only via external memory**.

**(c) Pursue full K = 6144 as a distinct, large, staged external-**SRAM** increment**
(`add-fpga-decoder-external-loop-mem`, proposed here as the staged task plan) —
**not SDRAM**. The 7 loop LLR arrays total **~63 KB**, which **fits entirely in
the DE2's 512 KB async SRAM** with ~1× per-access latency under the ~12.5 MHz demo
clock; SDRAM is bandwidth-adequate but its **random-access latency is hostile** to
the per-step recurrence (QPP permutation destroys burst locality) and it needs a
heavy refresh/row-management controller. The external route is feasible but is a
**large** effort (external-memory controller + reworking every loop-mem access +
the constituent input buffers) and is staged accordingly.

## Capabilities

### New Capabilities

- `fpga-decoder-sliding-window`: re-detailed to (1) **record** the negative
  α-windowing fit finding and the loop-LLR-memory wall as the binding constraint,
  (2) **pin** the on-chip maximum-K the EP2C35 supports, and (3) **specify** the
  external-SRAM full-K path (interleaver-random-access mapping, latency budget,
  staged plan) as the only realistic route to K = 6144 on this board. The windowed
  α/β reference is retained as a shelved, validated artifact, not as the M4K lever
  it was originally proposed to be.

## Impact

- **Re-frames** the M2 thesis from "window α → full-K fits" to "α is not the wall;
  the QPP-globally-permuted loop LLR memories + K-deep input buffers are, and they
  cannot be on-chip-windowed; full K = 6144 on the EP2C35 needs external SRAM."
- **No code lands** in this change. The windowed-α RTL (task 3.1) is **not
  written** here and is recommended **shelved**. The existing decoder lanes,
  golden vectors, and fits are **unchanged**.
- The recommended external-SRAM increment, if pursued, **changes board pinout**
  (adds `SRAM_*`), adds a memory-controller core, and reworks the loop-mem and
  input-buffer access paths — a large effort tracked as its own change.
- Depends on the recorded Quartus II 13.0sp1 fits (K = 512: ~57–61/105 M4K; K =
  6144: does not fit) and the archived `add-fpga-decoder-block-ram-inference`
  per-memory M4K decomposition (`decoder_roadmap.md` §6).

## Out of Scope (explicit)

- **Any HDL/scripts/qsf/.m edit** — this is design/analysis only.
- Implementing windowed-α in `constituent_decoder.vhdl` (recommended shelved).
- Implementing the external-SRAM controller or the loop-mem rework (a distinct,
  large future increment; staged here as UNCHECKED tasks only).
- Exact Log-MAP accuracy (M1), recurrence pipelining for Fmax
  (`add-fpga-decoder-recurrence-pipelining`), fixed-point width tightening (M3).
- Any change to the constituent or top-level streaming interface.
- Any board demo of a K = 6144 fit (it does not fit on-chip; the external route
  is not implemented here).
