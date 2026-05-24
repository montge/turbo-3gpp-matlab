## Context

`circular_buffer.vhdl` (TS36.212 §5.1.4.1.2) was synthesis-hardened over two
prior increments to be **divider-free** (the `q = ceil(N_cb/(8·R_TC))`
accumulate-and-count in `S_QCALC`; the `pos = k_0 mod N_cb` shift/compare-subtract
in `S_K0MOD`) and **M4K-block-RAM-inferable** (bank-split `w_sys`/`w_ev`/`w_od`
arrays, write lifted out of the reset-guarded FSM, synchronous registered read).
Its header states the index math is all add/shift/compare and the
`add-fpga-block-ram-inference` design intent expected **0 embedded multipliers**.

A full-`KW_MAX=18528` standalone Quartus II 13.0sp1 Analysis & Synthesis
(EP2C35F672C6) contradicts that intent:

```
Embedded Multiplier 9-bit elements : 2     (of 70)
Total memory bits                  : 49,152 / 12 M4K   (intended; kept)
Total logic elements               : ~619
```

Two `lpm_mult` megafunctions are elaborated:

- `lpm_mult:Mult0` with `LPM_WIDTHA=16, LPM_WIDTHB=2, LPM_WIDTHP=18` — the inner
  `q_cnt * RvR` (16-bit accumulate count × 2-bit redundancy version).
- a second `lpm_mult` with a wider A and `LPM_WIDTHR=26` — the outer `R_TC * (…)`.

Both trace to the start-offset register assignment, duplicated on two lines:

```vhdl
-- circular_buffer.vhdl, state S_QCALC, when q_acc >= N_cb:
k0    <= R_TC * (2*q_cnt*RvR + 2);   -- line 298
m_rem <= R_TC * (2*q_cnt*RvR + 2);   -- line 299  (seeds the mod-N_cb recurrence)
```

This is the literal RTL of the standard's
`k_0 = R_TC·(2·⌈N_cb/(8·R_TC)⌉·rv_idx + 2)` (`circular_buffer.m` line 74), with
`q_cnt` holding `⌈N_cb/(8·R_TC)⌉`. It carries **two variable×variable products**:
`q_cnt·RvR` and `R_TC·(…)`. Each maps to one embedded 9-bit multiplier; that is
the entire source of the 2 DSP elements (the parity decode `r/2`, the `q`/`pos`
recurrences, and the bank reads use no `lpm_mult`, confirmed by the elaboration
log showing exactly one `Mult0` chain).

## Goals / Non-Goals

**Goals**

- Make `circular_buffer` synthesize with **`Embedded Multiplier 9-bit elements =
  0`** at full `KW_MAX=18528` under Quartus II 13.0sp1 — the index/offset
  arithmetic realized purely with add / shift / compare / accumulate.
- Keep the change **bit-exact**: the `circular_buffer` cocotb lane stays green and
  `hdl/vectors/circular_buffer.csv` is byte-identical.
- **Retain** the M4K inference (12 segments / 49,152 bits) and 50 MHz timing
  closure that the prior changes established — DSP removal must not cost the RAM
  mapping or the clock.

**Non-Goals**

- No change to the M4K inference, the divider-free `q`/`pos` recurrences, or the
  bank-split read decode (kept as committed).
- No vector regeneration, no `.m` change, no decoder/UART/DE1/fixed-point work.
- No algorithmic / standard-behaviour change — only the *realization* of one
  register assignment changes; every output bit is identical.

## Decisions

### 1. Replace `k_0 = R_TC·(2·q·rv + 2)` with a running accumulate (the core fix)

Expand the offset algebraically:

```
k_0 = R_TC·(2·q·rv_idx + 2) = (2·R_TC·rv_idx)·q + 2·R_TC
```

`q = q_cnt` is **already produced by a loop** in `S_QCALC` that runs exactly `q`
iterations (each adds the constant `q_step = 8·R_TC` to `q_acc` and increments
`q_cnt`, until `q_acc ≥ N_cb`). Add one **parallel running accumulator** updated on
those same iterations:

```vhdl
-- block constant, computed once at S_QCALC entry (shift/add, no multiply):
--   k0_inc = 2 * R_TC * rv_idx      with rv_idx in {0,1,2,3}
-- on every S_QCALC accumulate step (alongside q_acc/q_cnt):
k0_acc <= k0_acc + k0_inc;
-- when q_acc >= N_cb (loop done, q_acc/q_cnt frozen):
--   k0_acc now == 2*R_TC*rv_idx*q   (q repeated additions of k0_inc)
k0    <= k0_acc + two_rtc;           -- two_rtc = 2*R_TC ; pure add
m_rem <= k0_acc + two_rtc;
```

This computes the **same integer** `k_0` with **zero runtime products** — the
`q·rv` product becomes `q` repeated additions of the constant `k0_inc`, and the
outer `R_TC·(…)` disappears because `k0_inc` already folds in `2·R_TC`. The extra
accumulate runs in the already-existing per-block `S_QCALC` loop, so it adds **no
new states and no read-path latency** (offset computation is one-time, latency-
irrelevant). Verified equal to the golden `k_0` over all
`(K_Pi ∈ {40,64,128,512,6176}, N_cb, rv_idx ∈ {0,1,2,3})` test points.

### 2. Build the two block constants without a multiplier

- `two_rtc = 2·R_TC` — a single left-shift (`R_TC sll 1`), R_TC is already an
  integer register.
- `k0_inc = 2·R_TC·rv_idx`, `rv_idx ∈ {0,1,2,3}` (2 bits) — a 4-way select over
  shifted copies of `R_TC` (no variable×variable multiply):
  - `rv_idx = 0 → 0`
  - `rv_idx = 1 → 2·R_TC` (`= two_rtc`)
  - `rv_idx = 2 → 4·R_TC` (`R_TC sll 2`)
  - `rv_idx = 3 → 4·R_TC + 2·R_TC` (`(R_TC sll 2) + two_rtc`)

  This is the canonical "constant-coefficient multiply by a 2-bit operand =
  shift+add+mux" lowering Quartus performs as LE logic, never `lpm_mult`. The
  constants are latched once at `S_QCALC` entry (when `R_TC`/`RvR` are known),
  off the read path.

### 3. Everything else is unchanged

The `q`/`pos`/`mod` recurrences, the bank-split arrays + `ramstyle = "M4K"`, the
synchronous read and `S_PRIME` latency-absorb beat, and the parity decode
(`r/2 = r srl 1`, `r mod 2`, lines 201–207) are kept byte-for-byte. The empirical
synthesis confirms none of these infers a multiplier; only the `k_0` expression
does, and it is the only thing this change rewrites.

### 4. How bit-exactness is preserved and confirmed (two-tier gate)

- **Inner gate — cocotb / GHDL, bit-exact (functional oracle).** Re-run the
  `hdl/sim/circular_buffer/` lane against the **unchanged** committed
  `hdl/vectors/circular_buffer.csv` (all `rv_idx ∈ {0,1,2,3}`, both `I_LBRM`
  modes, and the buffer-wrap `E`). The rewrite changes only how the *same* `k_0`
  integer is computed, so the emitted `(e_bit, out_valid, last)` stream is
  identical cycle-for-cycle; no vector is regenerated. Re-run the full
  `scripts/run_all_hdl_lanes.sh` suite to confirm no neighbouring lane regresses.
- **Outer gate — Quartus II 13.0sp1 fit report (synthesis oracle).** Re-synthesize
  `circular_buffer` standalone at full `KW_MAX=18528` and assert from the report:
  - **`Embedded Multiplier 9-bit elements = 0`** (was 2) — the deliverable;
  - **`Total memory bits` unchanged ≈ 49,152 / 12 M4K** — inference retained;
  - logic elements roughly flat or lower (the shift/add/mux replaces a DSP chain
    and a register-fed multiplier; a small LE delta either way is acceptable);
  - **`Fmax ≥ 50 MHz`** on the read clock — timing still closes.

  Optionally re-check the integrated full-`K` `tx_chain_top` fit to confirm the
  chain's total drops from 2 DSP to 0 with M4K/LE/Fmax otherwise intact.

## Risks / Trade-offs

- **Bit-exactness of the rewritten `k_0`.** A wrong shift/select or an off-by-one
  in the parallel accumulate would corrupt the start offset and every output bit.
  *Mitigation:* the algebra is verified equal to the golden `k_0` over all
  `(K_Pi, N_cb, rv_idx)` test points; the cocotb lane (which exercises all
  `rv_idx` and the wrap `E`) is the hard gate — not accepted until green with
  vectors byte-identical.
- **Accumulator range / overflow.** `k0_acc` must hold up to
  `2·R_TC·rv_idx·q ≤ k_0_max`. `k0` is already declared `range 0 to 8·KW_MAX`, so
  `k0_acc`/`k0_inc`/`two_rtc` are sized from the same bound; no new overflow.
  *Mitigation:* size the new registers off the existing `k0` range and confirm in
  review / simulation.
- **The mult is NOT on the latency-critical read path** (it is one-time, in the
  per-block `S_QCALC`), so removing it cannot slow the streaming read; but the new
  accumulate adds one adder into `S_QCALC`. *Mitigation:* the Fmax check confirms
  50 MHz still closes (the prior standalone closed at 96.48 MHz with large slack,
  so an extra adder in a one-time state has ample margin).
- **LE cost.** Replacing 2 DSP with shift/add/mux + an accumulator adds a few LE.
  *Mitigation:* trivial against 33,216; the fit report records the delta. Trading
  2 scarce DSP for a handful of abundant LE is the intended direction.

## Open Questions

- **Exactly which line(s) to rewrite.** The 2 DSP come from the single expression
  `R_TC*(2*q_cnt*RvR+2)` duplicated at lines 298 (`k0`) and 299 (`m_rem`); both
  are replaced by `k0_acc + two_rtc`. Confirm there is no *other* `*` in the file
  that infers a multiplier (the standalone elaboration shows only one `Mult0`
  chain, so this single expression is the whole source). Default: rewrite only
  lines 298/299 + add the `S_QCALC` accumulate.
- **Does removing the DSP cost LE or timing?** Expected negligible (a one-time
  adder + a 4-way constant mux). Confirm from the post-rewrite fit report; if a
  surprise timing regression appears, the accumulate can be split across the
  existing `S_QCALC` steps (it already is — one add per step).
- **Should the integrated `tx_chain_top` fit also be re-recorded** to show the
  chain-level DSP drop 2 → 0? Default: yes, as a confirming check, but the
  standalone `circular_buffer` DSP = 0 is the primary gate (the chain has no
  other DSP source).
