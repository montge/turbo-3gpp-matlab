## Why

This is roadmap milestone **M1** (`hdl/docs/decoder_roadmap.md` §3 maturation
track): add **exact Log-MAP** to the constituent decoder to close the
documented **Max-Log-MAP loss** (~0.1–0.5 dB per the roadmap risk table; the P2
characterization already exposes the float-Max-Log-MAP-vs-float-exact gap as the
M1 target). The locked v1 decision (`decoder_roadmap.md` §2) chose plain `max`
deliberately — it is associative & exact in fixed-point, deleting a whole class
of bit-exactness pain — and named exact Log-MAP (the `max*` / `maxstar`
correction LUT) as the later *accuracy* increment. This change formalizes it.

Exact Log-MAP replaces each `max(a,b)` with `max*(a,b) = max(a,b) + f(|a−b|)`,
where `f(d) = ln(1 + e^−d)` is realized as a tiny **correction LUT** (the float
oracle already does this — `maxstar.m` computes exactly `max(a,b) +
log(1+exp(-|a-b|))` when the global `approx_star=false`). The term decays to ~0
for `|a−b| ≳ 4`, so at the pinned `F_in=4` grid a handful of ROM entries suffice;
the cost is one small adder + a tiny LUT per `max*` site — **negligible logic and
zero M4K**, which matters because the decoder's M4K budget is now known to be
tight (~57–61/105 at K=512; the iterative-loop LLR memories are the wall, see
`decoder_roadmap.md` §6 + the M2-shelved note).

Crucially, exact Log-MAP is added behind a **generic** (`EXACT_LOGMAP : boolean
:= false`). With the default `false`, `f ≡ 0` and `max*` collapses to plain
`max` — i.e. the **default is bit-exact identical to the current Max-Log-MAP
core**. So every existing decoder lane (constituent / turbo-loop / term / rx)
stays green **unchanged** against its current golden vectors, and exact Log-MAP
is purely opt-in. This makes the Max-Log-MAP core a true *superset* default, not
a thing to be replaced and re-verified.

## What Changes

- **Add** the `max*` correction term to each pairwise `max` in the α recurrence,
  the β recurrence, and the two 8-way extrinsic reductions of the constituent
  decoder (`fpga-constituent-decoder`): after every 2-way `max(a,b)` add
  `f(|a−b|)` from a small quantized LUT indexed by the saturated `|a−b|`. The
  8-way extrinsic max becomes a tree of 2-way `max*` (the corrected fold must
  match the reference fold exactly).
- **Gate** the whole addition behind an `EXACT_LOGMAP : boolean := false`
  generic. Default `false` ⇒ `f ≡ 0` ⇒ bit-exact to today's Max-Log-MAP core.
- **Decide and pin** the extrinsic scaling factor question (see design.md):
  scaling primarily compensates Max-Log-MAP *optimism*; with exact `max*` the
  reference largely removes the need, so v1 of this change **omits** the scaling
  multiply (keeps the datapath multiplier-free) and records the float evidence;
  the scaling generic is reserved as a documented follow-on if the BER data
  later justify it.
- **Author** a new exact-Log-MAP fixed-point **reference**
  (`scripts/fixedpoint_constituent_decoder_exact.m`-class, mirroring
  `fixedpoint_constituent_decoder.m` + the LUT) and golden vectors **in exact
  mode**; the Max-Log-MAP vectors are unchanged and remain the default-mode
  contract.
- **Verify** two-tier + BER: inner cocotb bit-exact vs the new exact-Log-MAP
  reference (exact-mode vectors); a **default-mode regression** keeping every
  existing lane bit-exact; outer **BER showing the gain** — fixed-point
  exact-Log-MAP vs fixed-point Max-Log-MAP vs float exact-Log-MAP over a bounded
  SNR grid, quantifying the dB recovered.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`, or
`.m` edits land here. LUT depth/contents/width and the scaling decision are
pinned in design.md; their realization is deferred to when this change is
implemented.

## Capabilities

### New Capabilities

- `fpga-decoder-exact-log-map`: an exact-Log-MAP constituent-decoder variant,
  selected by an `EXACT_LOGMAP` generic, that adds a LUT-based `max*` correction
  term `f(|a−b|) = ln(1+e^−|a−b|)` to every pairwise `max` in the α/β/extrinsic
  datapath to recover the Max-Log-MAP BER loss. It is bit-exact to a new
  exact-Log-MAP fixed-point reference (a distinct bit-exact contract), while the
  **default `EXACT_LOGMAP=false` collapses `max*` to plain `max`, remaining
  bit-exact to the existing Max-Log-MAP baseline** (a superset, not a
  replacement).

## Impact

- Extends `fpga-constituent-decoder` (and transitively `fpga-turbo-decode-loop`,
  termination, rx-chain) with a more accurate metric, **without changing the
  default bit-exact golden-vector contract** (default mode = unchanged
  Max-Log-MAP). Exact mode introduces its own additional golden vectors.
- Negligible synthesis cost: one small adder + tiny LUT per `max*` site, **zero
  M4K** (important given the tight M4K budget, `decoder_roadmap.md` §6). The LUT
  adds combinational depth to the already-Fmax-limiting α recurrence cone — a
  note for `add-fpga-decoder-recurrence-pipelining`, not a blocker for this
  accuracy increment.
- Depends on the two-tier verification discipline (cocotb bit-exact + bounded
  outer BER) and Quartus II 13.0sp1 on the Windows host.

## Out of Scope (explicit)

- **Replacing** the default Max-Log-MAP path — exact Log-MAP is opt-in via the
  generic; the default stays a bit-exact superset.
- Sliding-window memory (M2 / shelved per `decoder_roadmap.md`).
- Recurrence pipelining for Fmax (`add-fpga-decoder-recurrence-pipelining`).
- An *unconditional* extrinsic scaling multiply in the datapath (omitted in v1;
  reserved as a documented generic if BER data later justify it).
- Any board demo of the exact-Log-MAP variant.
