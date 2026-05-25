## Context

M2 was proposed to window the constituent decoder's full-block α RAM so the full
K = 6144 turbo decoder fits the EP2C35. Stage 1 (`#73`) authored and characterised
the windowed **Octave reference** (`scripts/fixedpoint_constituent_decoder_sw.m`,
`scripts/characterize_sliding_window.m`; `W = 64`, `L = 48`, byte-exact full-block
superset + bounded windowing loss). The windowed **HDL** (task 3.1) was **not**
implemented. A Quartus fit run to confirm the payoff **disproved the thesis**.
This design re-details M2 honestly around that negative result.

The decoder stack and its recorded K = 512 fit (`decoder_roadmap.md` §6,
`add-fpga-decoder-block-ram-inference`):

```
constituent_decoder   = forward α (full-block, alpha_mem N_MAX-deep) + β + extrinsic
turbo_decoder_top      = constituent_decoder (reused) + qpp_rom + qpp_interleaver + 7 loop LLR mems
turbo_decoder_term_top = turbo_decoder_top + crc24_check + HARQ
rx_chain_top           = de_rate_matching_top -> turbo_decoder_top
```

## Goals / Non-Goals

**Goals**

- Record the **negative fit finding** (α windowing → 0 M4K in `turbo_decoder_top`;
  K = 6144 does not fit) prominently and explain *why* (α is not the binding
  constraint).
- Resolve the **WINDOW_LEN-propagation** question (it is moot — no such generic
  exists; the result is genuine, not an artifact).
- Quantify the **loop-LLR-memory wall** per memory at K = 512 / K = 6144 and pin
  the **on-chip maximum K**.
- State the **interleaver-global-access constraint** that rules out on-chip loop
  windowing.
- Give the honest **external-SRAM/SDRAM feasibility verdict** and a clear
  **recommendation** with staged (UNCHECKED) tasks.

**Non-Goals**

- No HDL/scripts/qsf/.m edits (design/analysis only). No implementation of
  windowed-α or external memory in this change. No exact Log-MAP (M1), recurrence
  pipelining, width tightening (M3), or interface change.

## Decisions

### 1. The negative fit finding (headline)

Quartus II 13.0sp1, EP2C35F672C6, `turbo_decoder_top`:

| case | result |
|---|---|
| K = 512, short α window (`WINDOW_LEN = 64`) | **~61 / 105 M4K** (fits) |
| K = 512, full-block α (`WINDOW_LEN = 6147`) | **~61 / 105 M4K** (fits) — *identical* |
| K = 6144 (full-block) | **does NOT fit** (needs ≫ 105 M4K; ~2.3 Mbit phys.) |

**α windowing delivers zero M4K benefit in the integrated decoder, and does not
move the K = 6144 wall.** (The recorded block-RAM-inference baseline was 57/105
at K = 512; the ~61 here reflects the slightly different M2-stage netlist. The
load-bearing fact is 61 = 61 between the two α-window settings, and no-fit at
6144 — both independent of any α scheme.)

> Note the ~57–61 vs the proposal's older "96/105 for `rx_chain_top`": the 96/105
> figure was the pre-block-RAM-inference `rx_chain_top` (with de-rate-matching);
> the 57–61 figures are `turbo_decoder_top` alone after the M4K-inference rework.
> Both are consistent — α is ≤ 30 M4K of either, and removing it would still leave
> the loop/input memories dominant.

### 2. The WINDOW_LEN-propagation question — RESOLVED (moot)

The intended diagnostic (read synthesized `alpha_mem` Port-A depth: 64 ⇒
propagated, ~515 ⇒ not) **cannot be run as posed**, because:

- **No `WINDOW_LEN` (or `ACQ_LEN`) generic exists in any HDL file.**
  `constituent_decoder.vhdl` is parameterised only by `N_MAX = K+3` (default
  6147), which sizes `alpha_mem : array(0 to N_MAX-1) of std_logic_vector(119
  downto 0)` directly. `turbo_decoder_top.vhdl` exposes `K_MAX` / `N_MAX`, not a
  window length. `grep -rn 'WINDOW_LEN\|ACQ_LEN' hdl/**/*.vhdl` → **no matches**.
- The windowed traversal lives **only** in the Octave reference; the HDL still
  computes and stores **all** `K+3` α columns.

Therefore the synthesized `alpha_mem` Port-A depth is **~515 at K = 512 in both
runs** (`N_MAX`-driven), and the "`WINDOW_LEN = 64` vs `6147`" experiment changed
a knob that does not affect α depth (or re-ran the same netlist) — which is
**exactly why the two fits are byte-identical at 61 M4K.** The implication: the
0-M4K-benefit result is **not** a propagation artifact; it is the genuine,
expected outcome of α not being the binding constraint. (Had a `WINDOW_LEN`
generic existed and shrunk α to depth 64, the constituent α would have dropped
from 30 → ~6 M4K, but `turbo_decoder_top` would *still* sit at ~37/105 — see §3 —
because the ~22 M4K loop memories and the constituent's own input buffers are
untouched. The fit would change; the K = 6144 verdict would not.)

### 3. The loop-LLR-memory wall — quantified

**M4K model.** Calibrated to the recorded anchors (`decoder_roadmap.md` §6 +
`constituent_decoder.vhdl` fit note): `alpha_mem` 515 × 120 = **30 M4K** (Quartus
maps the 120-bit word at a narrow 4-bit aspect ⇒ `ceil(120/4)·ceil(depth/1024)`);
`ca_mem` 512 × 12 = **4 M4K**; `xa_mem`/`za_mem` 515 × 9 = **3 M4K** each. For
fixed width, M4K scales ~linearly with depth, so the per-memory cost is the
recorded K = 512 value × `ceil(K/512)`.

**`turbo_decoder_top` loop LLR memories** (all body depth K; `mem_proc` in
`turbo_decoder_top.vhdl`):

| memory | width | role | M4K @ K = 512 | M4K @ K = 6144 |
|---|---|---|---|---|
| `za_mem`  | 9 (W_IN)  | z_a body (upper parity) | 3 | ~36 |
| `zpa_mem` | 9 (W_IN)  | z'_a body (lower parity) | 3 | ~36 |
| `chs_mem` | 12 (W_EXT) | ch_sys body | 3 | ~36 |
| `ca_mem`  | 12 (W_EXT) | c_a interleaved extrinsic (QPP scatter) | **4** | ~48 |
| `ce_mem`  | 12 (W_EXT) | c_e cyclic extrinsic | 3 | ~36 |
| `xpa_body`| 12 (W_EXT) | interleaved core-input x'_a | 3 | ~36 |
| `xpe_body`| 12 (W_EXT) | captured x'_e | 3 | ~36 |
| **loop subtotal** | | | **~22** | **~264** |

**Constituent core memories** (depth `N = K+3`):

| memory | width | M4K @ K = 512 | M4K @ K = 6144 |
|---|---|---|---|
| `alpha_mem` (full-block) | 120 | 30 | ~210 |
| `xa_mem` | 9 | 3 | ~39 |
| `za_mem` | 9 | 3 | ~39 |

**Totals and the wall:**

| K | loop mems | constituent (α + xa + za) | **TOTAL** | fits 105? |
|---|---|---|---|---|
| 512  | ~22 | 30 + 3 + 3 = 36 | **~58** | yes (matches recorded 57–61) |
| 1024 | ~44 | 60 + 6 + 6 = 72 | **~116** | **no** |
| 6144 | **~264** | 210 + 39 + 39 = 288 | **~552** | **no (5×+ over)** |

The "~264 M4K loop wall at K = 6144" is confirmed. The decoder is **K-buffered
everywhere**: even if α were windowed to ~6 M4K (K-independent), K = 6144 would
still need ~264 (loop) + ~6 (windowed α) + ~78 (constituent xa/za input buffers)
≈ **348 M4K ≫ 105**. **Windowing α removes ~24 M4K at K = 512 and ~204 at K = 6144,
but the residual is still ~348 M4K — full K = 6144 remains infeasible on-chip.**

**Maximum on-chip K (EP2C35, 105 M4K).** Holding all memories on-chip:

- **Full-block α (today):** K = 1024 already needs ~116 M4K. The largest fitting
  block is **K ≈ 1008** (next standard LTE K below 1024); practical headroom
  argues **cap at K = 1008** (the LTE-standard K just under the 105-M4K knee).
- **With windowed α (if task-3.1 were implemented):** α drops to ~6 M4K
  K-independent, raising the knee to ~K = 1536 (total ~90 M4K) — **cap ≈ K = 1536**.
  *This ≈ 1.5× lift is the only real benefit windowed-α buys, and it is on the
  on-chip-max-K, not on reaching 6144.*

### 4. The interleaver-global-access constraint (why loop windowing is impossible)

α was windowable because it is **local and causally recomputable**: the forward
recursion is left-to-right, so any window's α can be regenerated from a boundary
checkpoint, and only one window need be live. **The loop LLR memories have no such
locality.** Each half-iteration (`turbo_decoder_top` S_LO_PI1 / S_LO_PI2):

- **reads** `x'_a[k] = c_e[π[k]]` — gathers `c_e` through the QPP permutation π;
- **scatters** `c_a[π[k]] = x'_e[k]` — writes `c_a` through π.

π is the **QPP interleaver over the entire K-bit block** (`qpp_interleaver`,
quadratic `π(k) = (f₁·k + f₂·k²) mod K`). Consecutive `k` map to **scattered,
non-local** addresses spanning all of `[0, K)`. There is **no window** of the
interleaved access — a window of source indices `[w0, w1)` reads/writes
destination indices spread across the whole block. Consequently:

- The full `c_e` array must be resident before PI1 can gather it, and the full
  `c_a` array must be addressable for the PI2 scatter. **No streaming or
  checkpoint-recompute scheme reduces the live footprint** the way it does for α.
- The same applies to `chs_mem` (read at arbitrary feed indices), `xpa_body` /
  `xpe_body` (forward-order buffers feeding/captured-from the permuted exchange),
  and the constituent's `xa_mem` / `za_mem` (the whole block is streamed into the
  core each call).

So the **only** way to take the loop/input memories off the M4K budget is to put
the full K-sized arrays **somewhere other than M4K** — i.e. external memory.

### 5. External-memory feasibility (the realistic full-K route)

DE2 off-chip resources: **8 MB SDRAM** (`DRAM_*`, 16-bit, ~100 MHz, needs a
refresh/row controller) and **512 KB asynchronous SRAM** (`SRAM_*`, 256K × 16,
~10 ns access, no refresh). *Neither is currently wired in any board file —
`grep DRAM_/SRAM_ hdl/boards/de2/*` → none. Both are greenfield.*

**Footprint.** The 7 loop LLR arrays at K = 6144 = `(2·9 + 5·12)·6144 ≈ 479 Kbit
≈ 60 KB`; adding the constituent K-deep input buffers (`xa`/`za`, 2·9·6147 ≈
13 KB) ≈ **~73 KB total**. This **fits comfortably in the 512 KB SRAM** (≈ 14 %)
— and trivially in the 8 MB SDRAM.

**Access pattern vs latency budget.** On-chip decode budget ≈ `4·H·K` cycles
(H = 16 at max_iter = 8) ≈ 393 k cycles ≈ **31 ms at the 12.5 MHz demo clock**.
Per half-iteration the QPP gather/scatter performs ~2·K random single-word
accesses; over H halves ≈ 197 k random accesses.

- **SRAM (async, ~10 ns).** One 80 ns core cycle (12.5 MHz) fits ~8 SRAM accesses,
  so the ~3 reads + occasional write per recurrence step are servable **within
  the cycle budget — ≈ 1× latency**, even though QPP access is random (SRAM has no
  row/burst penalty; every access is a flat ~10 ns). Single 16-bit port serializes
  multi-array steps, but the budget absorbs it. **Feasible.** Aggregate ≈ 2 ms of
  SRAM access vs 31 ms compute. The cost is a (modest) async-SRAM controller and a
  rework of every loop-mem/input-buffer access to go off-chip.
- **SDRAM (8 MB, ~100 MHz).** Bandwidth is ample, but the **QPP permutation
  destroys burst locality** — every access is effectively a random row
  (precharge + activate + CAS ≈ 10–15 SDRAM clocks ≈ 100–150 ns), which **exceeds
  one 80 ns core cycle** and **stalls the recurrence every step**; with
  multi-array arbitration and refresh, realistically **~3–5× slower**, plus a
  **heavy controller** (init, auto-refresh, row management). **Bandwidth-OK but
  random-latency-hostile and controller-heavy — not the right target here.**

**Verdict.** Full K = 6144 on the EP2C35 is **reachable, but only via external
memory, and the right target is the 512 KB SRAM (≈ 1× latency, fits the ~73 KB
working set), not SDRAM.** It is a **large** increment: an SRAM controller, board
pinout (`SRAM_*` + an SDC), and reworking every loop-mem and constituent-input
access from M4K to external SRAM (preserving the bit-exact contract and the QPP
random-access semantics). Worth it only if a full-K demo is a hard requirement;
otherwise the **on-chip K ≤ 1008 cap** is the pragmatic stopping point.

### 6. Salvage assessment — the windowed-α RTL/reference

- The **windowed Octave reference + characterization (`#73`)** is **correct and
  worth keeping** (shelved, not deleted): it is byte-exact to the full-block
  superset, has a pinned `W = 64 / L = 48` with a bounded windowing-loss band, and
  is **directly reusable** for (a) a constituent-standalone on-chip-K lift
  (≈ 1016 → ≈ 1536), and (b) a future ASIC / larger-FPGA where α area *is* on the
  critical path.
- The **windowed-α HDL (task 3.1)** should **NOT be implemented for this board**:
  it delivers 0 M4K in `turbo_decoder_top` and ~204 M4K at K = 6144 against a
  ~348 M4K residual that is still infeasible — i.e. it cannot achieve the M2 goal,
  and it adds FSM/recompute complexity and a latency penalty for no board payoff.
  Shelve it behind the reference; revisit only if the on-chip-max-K lift to ~1536
  (constituent-standalone or a future larger device) becomes a requirement.

## Recommendation (and the staged plan)

1. **Shelve windowed-α** as a `turbo_decoder_top` M4K lever (it is 0-benefit
   there); **keep the validated Octave reference** as a documented artifact.
2. **Accept an on-chip maximum-K cap** on the EP2C35: **K ≤ 1008** with full-block
   α (the current board demo at K = 512 is well inside this), or **K ≤ 1536** if
   windowed-α is later wired in for the constituent.
3. **Pursue full K = 6144 only as a distinct, large, staged external-SRAM
   increment** (`add-fpga-decoder-external-loop-mem`) — SRAM, not SDRAM — with the
   staged tasks below. Do **not** start it unless full-K is a hard requirement.

This change **records the analysis and re-stages the tasks UNCHECKED**; it lands
**no code**.

## Risks / Trade-offs

- **Accepting the K-cap forecloses a full-K on-chip demo.** Mitigation: the cap is
  honest (the device physically cannot hold ~348–552 M4K of K-buffers); the
  external-SRAM path is specified if full-K is later required.
- **External-SRAM increment is large and bit-exactness-fragile.** Reworking
  M4K → external must preserve the QPP random-access semantics and the bit-exact
  golden-vector contract. Mitigation: stage it (controller → one array → all
  arrays → constituent buffers), gate each stage on the existing cocotb lanes.
- **SDRAM mis-selection.** A naive "8 MB is bigger, use SDRAM" choice would stall
  the recurrence ~3–5×. Mitigation: this design pins **SRAM** as the target and
  documents why.
- **Misreading the negative result as a propagation artifact.** Mitigation: §2
  shows no `WINDOW_LEN` generic exists, so 61 = 61 is genuine, not a non-propagated
  generic.

## Open Questions

- **Is a full K = 6144 board demo actually required?** If not, **stop at the
  on-chip K ≤ 1008 cap** and archive M2 as "α-windowing shelved, reference
  retained, wall documented." If yes, open the external-SRAM increment.
- **Async-SRAM controller reuse.** Is there a reusable async-SRAM controller
  pattern, or is it new RTL? (Greenfield today — no `SRAM_*` in any board file.)
- **Exact SRAM port scheduling.** The single 16-bit port must serialize the
  ~3-reads-per-step + scatter; confirm the per-step access count fits one core
  cycle at the chosen clock, or widen the cycle/word packing.
- **Whether to wire windowed-α into the constituent** for the ≈ 1536 on-chip-K
  lift (independent of the external-SRAM question) — a smaller, optional follow-on.
