## 1. Identify the multiplying expression(s)

- [x] 1.1 Re-confirm (standalone Quartus II 13.0sp1 A&S at full `KW_MAX=18528`,
  scratch dir outside the repo) that `circular_buffer` reports `Embedded
  Multiplier 9-bit elements : 2` and that the elaboration log shows exactly the
  two `lpm_mult` chains from the start-offset expression `R_TC*(2*q_cnt*RvR+2)`
  (lines 298/299) — i.e. the inner `q_cnt*RvR` (`LPM_WIDTHA=16,LPM_WIDTHB=2`) and
  the outer `R_TC*(…)`; no other `*` infers a multiplier. Record the baseline
  (DSP=2, memory bits ≈ 49,152 / 12 M4K, LE ≈ 619, Fmax).

## 2. Reformulate the offset multiplier-free (bit-exact)

- [x] 2.1 At `S_QCALC` entry latch the two block constants with shifts/mux only
  (no `*`): `two_rtc = R_TC sll 1` (= 2·R_TC) and
  `k0_inc = 2·R_TC·rv_idx` as a 4-way select over shifted `R_TC`
  (`rv=0→0, 1→two_rtc, 2→R_TC sll 2, 3→(R_TC sll 2)+two_rtc`).
- [x] 2.2 Add a parallel running accumulator `k0_acc` updated on every existing
  `S_QCALC` accumulate step (`k0_acc <= k0_acc + k0_inc;` alongside
  `q_acc`/`q_cnt`), sized off the existing `k0` range (`0 to 8·KW_MAX`), seeded 0.
- [x] 2.3 Replace the line-298/299 products with pure adds: when `q_acc >= N_cb`,
  `k0 <= k0_acc + two_rtc; m_rem <= k0_acc + two_rtc;` (no `R_TC*…`, no `q*rv`).
- [x] 2.4 Confirm the `q`/`pos`/`mod` recurrences, the parity decode
  (`r srl 1`, `r mod 2`), the bank arrays + `ramstyle = "M4K"`, the synchronous
  read and the `S_PRIME` latency-absorb beat are **unchanged** byte-for-byte.

## 3. Inner gate — cocotb bit-exact (vectors byte-identical)

- [x] 3.1 Re-run the `circular_buffer` cocotb/GHDL lane
  (`hdl/sim/circular_buffer/`) — MUST pass bit-for-bit against
  `hdl/vectors/circular_buffer.csv` (all `rv_idx ∈ {0,1,2,3}`, both `I_LBRM`,
  the wrap `E`). No edit accepted until green.
- [x] 3.2 Confirm `hdl/vectors/circular_buffer.csv` (and all other golden
  vectors) are **byte-identical** to master (`git diff master -- hdl/vectors/`
  empty); no vector regenerated.
- [x] 3.3 Re-run the full suite `scripts/run_all_hdl_lanes.sh` — all lanes PASS,
  confirming no neighbouring core regresses.

## 4. Outer gate — Quartus fit at full `KW_MAX`, DSP = 0

- [x] 4.1 Re-synthesize `circular_buffer` standalone at full `KW_MAX=18528`
  (Quartus II 13.0sp1, `EP2C35F672C6`, VHDL_2008) and assert from the report
  **`Embedded Multiplier 9-bit elements = 0`** (was 2) — the deliverable.
- [x] 4.2 Confirm the **M4K inference is retained** (`Total memory bits` ≈ 49,152
  / 12 M4K segments, unchanged) and logic elements are roughly flat or lower;
  record the LE / memory-bit / DSP counts before → after.
- [x] 4.3 Confirm **`Fmax ≥ 50 MHz`** on the read clock (positive setup + hold
  slack); record Fmax / slacks. Optionally re-check the integrated full-`K`
  `tx_chain_top` fit to confirm the chain-level DSP drops 2 → 0 with M4K / LE /
  Fmax otherwise intact.
- [x] 4.4 Confirm `git status` shows only the intended `hdl/rtl/circular_buffer.vhdl`
  edit (no `db/`, `output_files/`, `*.sof`, report artifacts; build in a scratch
  dir outside the repo).

## 5. Documentation + validation

- [x] 5.1 Update the `circular_buffer.vhdl` header to record that the start-offset
  multiply was replaced by the `S_QCALC` running accumulate + shift/mux constants,
  that the block now synthesizes with **DSP = 0** at full `KW_MAX`, and that
  bit-exactness is preserved (cocotb gate green, vectors unchanged).
- [x] 5.2 Run `npx openspec validate add-fpga-circular-buffer-mult-free --strict`
  and `npx openspec validate --all --strict` — both pass, no regression.
