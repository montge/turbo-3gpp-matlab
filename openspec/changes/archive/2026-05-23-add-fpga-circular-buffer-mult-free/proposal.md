## Why

`circular_buffer.vhdl` was designed to be **all add/shift/compare** after the
earlier divider-free hardening (the `q = ceil(N_cb/(8·R_TC))` accumulate and the
`pos = k_0 mod N_cb` shift/compare-subtract recurrences). Its header and the
`add-fpga-block-ram-inference` design intent expected **0 embedded multipliers**
— the block was meant to map to pure logic + M4K block RAM, no DSP.

A full-`KW_MAX=18528` standalone Quartus II 13.0sp1 synthesis (EP2C35F672C6)
shows otherwise. Recorded in `add-fpga-block-ram-inference` task 4.2 and
re-confirmed here by a standalone Analysis & Synthesis run:

> **`Embedded Multiplier 9-bit elements : 2`** (2 of 70), alongside the intended
> `Total memory bits : 49,152 / 12 M4K` and ~619 logic elements.

The parameterized-down `K=40` board demo (`KW_MAX=256`) did **not** infer these
multipliers — they appear only at full depth. The two `lpm_mult` megafunctions
trace to the start-offset computation

```vhdl
k0    <= R_TC * (2*q_cnt*RvR + 2);   -- circular_buffer.vhdl line 298
m_rem <= R_TC * (2*q_cnt*RvR + 2);   -- circular_buffer.vhdl line 299
```

which is the RTL of the standard's `k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)`
(TS36.212 §5.1.4.1.2; `circular_buffer.m` line 74). It contains **two
variable×variable products** — the inner `q_cnt * RvR` (16-bit × 2-bit
→ `lpm_mult LPM_WIDTHA=16,LPM_WIDTHB=2`) and the outer `R_TC * (…)` — and Quartus
maps each to one embedded 9-bit multiplier.

Eliminating those two multipliers makes the block map to **pure logic + M4K (no
DSP)**, matching the design intent: cleaner, more portable (no reliance on the
device's scarce DSP column), and self-consistent with the "divider-free /
multiplier-free index arithmetic" claim already written in the header.

**This is an explicitly LOW-PRIORITY cleanup, not a fit blocker.** The full-`K`
`tx_chain_top` already **fits** the EP2C35 *with* the 2 multipliers (1,716 LE,
22/105 M4K, Fmax 89.33 MHz; the EP2C35 has 70 embedded 9-bit multipliers, so 2 is
trivial). This change removes them only to honour the design intent and keep the
mapping logic+RAM-only; nothing depends on it landing.

## What Changes

- **Replace the multiplying start-offset expression with a shift/add +
  per-step-accumulate equivalent**, bit-exact, removing both runtime products
  from `circular_buffer.vhdl`:
  - The S_QCALC accumulate already loops `q = q_cnt` times (incrementing
    `q_acc` by the constant `q_step = 8·R_TC` until it reaches `N_cb`). Add a
    **parallel running accumulator** `k0_acc` that adds a per-block constant
    `k0_inc = 2·R_TC·rv_idx` on each of those same steps, so that after the loop
    `k0_acc = 2·R_TC·rv_idx·q` **by repeated addition** — no `q·rv` product.
  - Form the two block constants without a DSP: `2·R_TC` is a left-shift of
    `R_TC`; `2·R_TC·rv_idx` (with `rv_idx ∈ {0,1,2,3}`, 2 bits) is a small
    shift/add selected by `rv_idx` (`0→0, 1→2·R_TC, 2→4·R_TC, 3→4·R_TC+2·R_TC`),
    i.e. a 4-way mux over shifted copies — no variable×variable multiply.
  - The final offset is then `k_0 = k0_acc + 2·R_TC`, seeded identically into
    both `k0` and the `m_rem` running remainder (the inputs to the existing
    `S_K0MOD` divider-free `mod N_cb`).
- **Confirm the parity read-address decode (`r/2`, `r mod 2`, line 202/203) and
  the `q`/`pos` recurrences are already multiplier-free** and are kept unchanged
  (`/2` of a constant divisor is a shift; the empirical synthesis shows the only
  two DSP elements come from the `k_0` expression, not the decode).
- **Bit-exactness is preserved.** The committed golden vectors
  (`hdl/vectors/circular_buffer.csv`) stay **byte-identical** and the existing
  `hdl/sim/circular_buffer/` cocotb/GHDL lane stays green; the standard-defined
  behaviour (which `w` positions are read, in what order, skipping fillers) is
  unchanged. The reformulation is a pure algebraic rewrite of one register
  assignment, verified equal to the golden `k_0` over all `(K_Pi, N_cb, rv_idx)`.

## Capabilities

### Modified Capabilities

- **`fpga-circular-buffer`** — add a requirement that the core's `N_cb`/`q`/`k_0`
  index arithmetic uses **no embedded multipliers** (it is realized entirely with
  add / shift / compare / accumulate), so the synthesized block maps to logic +
  M4K with **DSP = 0**, while staying bit-for-bit equal to
  `circular_buffer(v, N_ref, I_LBRM, rv_idx, E)` and its golden lane.

**Decision — MODIFY `fpga-circular-buffer` (not a new capability).** This is a
property of the **same** core the spec already owns: the existing "Start offset
matches the standard" requirement already specifies `k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)`,
and the prior hardening already established the divider-free/synchronous-read
properties as requirements of this capability. "No embedded multipliers in the
index arithmetic" is the natural next member of that same family — a
implementation-resource property of the one circular-buffer core — not a new
cross-cutting verification gate. (Contrast `add-fpga-block-ram-inference`, which
*did* warrant a new `fpga-block-ram-inference` capability because it introduced
a brand-new synthesis-oracle gate spanning three cores. Here we reuse that
already-established two-tier gate; no new capability is needed.)

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, `.m` edits
  land here. This is the proposal; implementation follows the staged `tasks.md`.
- When implemented: `hdl/rtl/circular_buffer.vhdl` only — the S_QCALC state gains
  a parallel `k0_acc`/`k0_inc` accumulate and the line-298/299 `k_0` assignment
  becomes an add; the header note is updated to record DSP = 0. No other RTL, no
  vector regeneration, no `.m` change.
- Reuses the established **two-tier gate**: the `circular_buffer` cocotb lane
  (functional bit-exactness, vectors byte-identical) plus a full-`KW_MAX=18528`
  Quartus II 13.0sp1 fit report asserting **`Embedded Multiplier 9-bit elements =
  0`** while the **M4K inference (12 segments / 49,152 bits) and 50 MHz timing are
  retained**.
- Depends on Quartus II 13.0sp1 on the existing Windows host; the fit-report gate
  is the same local/manual synthesis step the prior changes used (not CI).
  Requires no DE2 hardware.

## Out of Scope (explicit)

- Any change to the M4K block-RAM inference, the divider-free `q`/`pos`
  recurrences, or the bank-split read decode (all kept exactly as committed —
  this change touches only the `k_0` multiply).
- Decoder memories, sliding-window, UART, DE1, fixed-point/width changes
  (all out of scope, as in the prior TX-chain changes).
- Any output-bit / standard-behaviour change — the rewrite is bit-exact by
  construction.
