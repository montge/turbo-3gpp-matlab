## Context

The fixed-point Max-Log-MAP decoder is sim-complete and M4K-fit at K = 512:

```
constituent_decoder      = forward α (full-block) + backward β + extrinsic
turbo_decoder_top        = constituent_decoder (reused: upper, lower) + qpp_rom + qpp_interleaver
turbo_decoder_term_top   = turbo_decoder_top + crc24_check + HARQ accumulate
rx_chain_top             = de_rate_matching_top -> turbo_decoder_top
```

`constituent_decoder.vhdl` (the dominant memory, reused by every decoder lane)
currently uses **full-block α storage**: `alpha_mem` is `N_MAX = K+3` deep, one
packed 120-bit word per trellis column (`STATES(8) × W_AB(15)`). The forward
sweep fills all `K+3` columns; the backward sweep re-reads every column to form
the extrinsic. The recorded Quartus II 13.0sp1 fit at K = 512 (`N_MAX = 515`,
`constituent_decoder.vhdl` lines 100-107) is:

- `alpha_mem`: `515 × 120 = 61,800` bits → **30 M4K** (Simple Dual Port, RDW =
  OLD_DATA) — the dominant memory;
- `xa_mem` / `za_mem`: `515 × 9` each → 3 M4K each;
- constituent total ≈ **35 M4K**; `rx_chain_top` at K = 512 sits at **96/105
  M4K** with almost no headroom.

At **K = 6144** (`N = 6147`) the full-block α store is `8 × 6147 × 15 ≈
720 Kbit ≈ 358 M4K-equivalents` — it exceeds the EP2C35's **484 Kbit / 105 M4K**
both by raw bits and by block count, so **full K does not fit at all**. This is
the wall M2 removes.

The locked v1 design (`decoder_roadmap.md` §2) deliberately chose full-block α
as a sim-first stance and named **sliding-window BCJR** as the synthesis-hardening
follow-on (M2). This change details that follow-on.

## Goals / Non-Goals

**Goals**

- Replace the full-block α store inside `constituent_decoder` with a
  **sliding-window** α/β so live α storage is `≈ 8 × W` + checkpoints (K-independent),
  freeing most of the α M4K.
- Make the full **K = 6144** constituent / `turbo_decoder_top` / `rx_chain_top`
  path **fit** the EP2C35 under Quartus II 13.0sp1, and drop the K = 512 M4K
  count well below today's `rx_chain_top` 96/105.
- Keep the constituent's **streaming interface** (ports, load/output cadence)
  and the inherited **fixed-point format** UNCHANGED; only the α/β schedule and
  storage change. So all decoder tops benefit automatically and K-agnostically.
- Author a **new** windowed fixed-point reference + golden vectors (the
  full-block vectors do not carry over), and characterise the **windowing loss**
  against the full-block decoder within a documented band.

**Non-Goals**

- No exact Log-MAP accuracy work (M1). No recurrence pipelining for Fmax
  (`add-fpga-decoder-recurrence-pipelining`). No fixed-point width tightening
  (M3) — the P1 widths are inherited as-is.
- No change to any streaming interface, no UART, no DE1, no board demo of the
  K = 6144 fit beyond the Quartus fit gate.

## Decisions

### 1. Windowing scheme — forward α in windows + backward β with acquisition

Process the length-`N = K+3` trellis as `⌈N/W⌉` contiguous windows. The
classical sliding-window BCJR (Viterbi 1998; the standard LTE turbo
implementation) is adopted:

- **β acquisition (warm-up) before each window** — *the standard direction*.
  For a window covering columns `[w0 .. w1]`, β is **initialised flat**
  (all-equal, i.e. 0 after max-norm — the "we don't know the state" prior) at a
  column `acq = min(N, w1 + L)`, then recursed **backward** across the `L`
  acquisition steps `acq-1 … w1`. By the time the recursion reaches `w1` the β
  metric has converged close to the true β (the recursion is a contraction in
  the metric-difference space), so the in-window β over `[w0 .. w1]` is emitted.
  - The **terminal window** (the one whose `w1 = N`) uses the **true terminated
    state** β init (state 1 = 0, others = MIN_SENT) — no acquisition needed,
    identical to full-block at the block end.
  - Every **interior window** pays an `L`-step warm-up. This is the source of
    the approximation (see §3).
- **α**: α is an ordinary forward recursion. Its *values* are identical to
  full-block (the forward recursion always starts from the true initial state
  and runs left-to-right with no acquisition). The only question is **storage**
  (§2): rather than retain all `K+3` α columns for the backward sweep, keep a
  **state checkpoint** at each window boundary and **recompute** the window's α
  columns from the nearest checkpoint when that window's β is being swept. So α
  is *recomputed*, not retained — trading a bounded recompute for the big RAM.

This makes **β** (and therefore the extrinsic) the only quantity that differs
from full-block, and only by the finite-`L` acquisition error.

### 2. Memory — `≈ 8 × W` window + checkpoints vs `8 × (K+3)`

Live α/β storage becomes K-independent:

| store | full-block (today) | windowed (this change) |
|---|---|---|
| α columns held | `8 × (K+3)` (all) | `≈ 8 × (W + L)` (one window + its acquisition span) + `⌈N/W⌉` boundary checkpoints (`8 × ⌈N/W⌉`) |
| β columns held | 1 (on-the-fly) | 1 (on-the-fly, unchanged) |

M4K estimate (calibrated to the recorded fit: a 120-bit `alpha_mem` word packs
~17 columns/M4K, since `515 deep → 30 M4K`):

| case | α-RAM depth | α-RAM M4K | fits EP2C35? |
|---|---|---|---|
| K = 512 full-block (today) | 515 | **30** | yes (35 M4K core; rx_chain 96/105) |
| K = 6144 full-block | 6147 | **~358** | **no** (also 720 Kbit > 484 Kbit) |
| **W = 64, L = 32** windowed | ~104 (W+L+ckpt) | **~6** | yes, K-independent |
| **W = 128, L = 32** windowed | ~168 | **~10** | yes, K-independent |

So at the recommended W = 64 / L = 32 (§3) the α store drops from **30 → ~6 M4K**
at K = 512 (and from infeasible → ~6 M4K at K = 6144). The checkpoint store is
tiny (`8 × ⌈N/W⌉ × W_AB`; at K = 6144, W = 64 that is `8 × 96 × 15 ≈ 1.4 Kbit`,
< 1 M4K). `xa_mem` / `za_mem` are unchanged (`N × 9`, the input buffer — they
still hold the whole block since the loader streams it once; if their depth is a
concern at K = 6144 they remain ~`6147 × 9 ≈ 7 M4K` each, far under budget). Net:
**the dominant α-RAM stops scaling with K**, full K = 6144 fits, and K = 512
`rx_chain_top` drops from 96/105 to roughly low-70s/105 (≈ 24 M4K freed on the
core's α alone, before any second-order effects).

### 3. Window length `W` and acquisition length `L` — pinned from prototype

A throwaway Octave prototype (windowed fixed-point constituent decoder vs the
existing full-block `fixedpoint_constituent_decoder.m`, **identical** arithmetic
and pinned widths, K = 512, SNR = 2 dB, 6 frames) measured the **windowing**
error — the extrinsic-LLR error introduced *purely* by finite acquisition (the
quantization is shared, so it cancels):

```
W     L     max|err|(LLR)  rms|err|(LLR)  hd_agree%
64    8     7.44           0.7115         99.512
64    16    6.56           0.2149         99.967
64    24    1.69           0.0435         100.000
64    32    0.81           0.0293         100.000   <- recommended
64    48    0.00           0.0000         100.000   <- bit-exact to full-block
128   8     7.25           0.5220         99.674
128   16    6.56           0.1777         99.967
128   24    0.50           0.0183         100.000
128   32    0.81           0.0293         100.000
128   48    0.00           0.0000         100.000
```

Reading:

- The windowing error falls **monotonically and steeply** with `L`. At `L = 8`
  the acquisition has not converged (max|err| ~7 LLR, hard-decision agreement
  only ~99.5 %). By `L = 24` it is already tiny (rms ~0.04 LLR, 100 % HD
  agreement), and by `L = 48` the windowed extrinsic is **bit-exact** to
  full-block (the acquisition has fully converged within the metric resolution).
- `W` (64 vs 128) barely affects the *per-bit* error — convergence is governed
  by `L`, not `W`. Larger `W` amortises the `L`-step warm-up over more emitted
  columns (fewer windows ⇒ less recompute and lower relative latency overhead),
  at the cost of a slightly larger live α window.

**Pinned defaults (task-1.2 characterization, FINAL): `W = 64`, `L = 48`.**
The full {K, SNR} characterization confirmed the design seed for PART 0 (superset
byte-exact, 24/24) and PART A (constituent windowing-loss), but `L = 32` **missed
the PART B loop-level BER band**: windowing loop loss `0.261 dB > 0.20 dB`. The
sweep showed `L = 48` (near-bit-exact: most cells 0.0000, worst-corner
6144 @ 0 dB rms 0.023 LLR / 100 % HD) clears it decisively — **PART B loop loss
−0.029 dB** (i.e. lossless within Monte-Carlo noise) — so `L = 48` is pinned.
Trade-off: `L` extends the β-acquisition warm-up; per the seed estimate it costs
roughly +6 M4K on the live α/β window vs `L = 32` (≈ 12 vs 6 M4K) plus
+16 cycles/window latency. That is still far below the full-block 30 M4K (K=512)
and the K = 6144 full-block ~358 M4K-equiv, so the M2 goal — α store becomes
K-independent and full K = 6144 fits on-chip — holds; the exact post-windowing
M4K is confirmed by the stage-5 Quartus fit. `L = 32` remains a documented
aggressive option (smaller α, ~0.26 dB loop loss) if a future caller accepts it.
**Pinned PART A band** (from the `L = 48` run): max|err| ≤ 3.375 LLR, rms ≤ 0.138,
HD ≥ 99.5 %; **PART B band**: loop windowing loss ≤ 0.20 dB (observed −0.029).

**Loop-level confirmation:** the prototype also ran a bounded end-to-end turbo
BER comparison (windowed core vs full-block core vs float), K = 512,
max_iter = 8, 8 frames/SNR:

```
SNR_dB  full_BER     W64,L32_BER   W128,L24_BER
-2.00   2.244e-01    2.293e-01     2.119e-01
-1.50   1.663e-01    1.350e-01     1.577e-01
-1.00   9.28e-03     2.95e-02      1.20e-02
```

The windowed curves sit essentially on top of the full-block curve; the
cell-to-cell spread is dominated by the small (5120-bit) sample's BER-estimator
noise, not a systematic windowing penalty — consistent with the ~100 % HD
agreement at `L ≥ 24` in the constituent sweep. The windowing loss at the loop
level is therefore ≲ 0.1 dB for the pinned `L` (the per-bit extrinsic error is
already ≪ the exchange-grid LSB after a couple of iterations). The loop
characterization (task 1.3) re-runs this with more frames to pin the band
formally.

### 4. α recompute vs checkpoint (the RAM/recompute trade)

Two ways to feed the backward β sweep with α:

- **(chosen) checkpoint + recompute.** Store only the 8-state α column at each
  window boundary (`8 × ⌈N/W⌉`). When sweeping window `[w0..w1]` backward,
  re-run the forward α recursion from the `w0-1` checkpoint up to `w1` into a
  small `8 × W` scratch, then sweep β over it. Cost: roughly **one extra forward
  pass of α** total (each column recomputed once) ⇒ ~`+N` cycles, i.e. the
  forward work doubles but the *memory* collapses to `≈ 8 × W`. This is the
  standard sliding-window memory/throughput trade and is the recommended path
  (memory is the binding constraint here, not cycles — the decoder is already
  cycle-bounded by the recurrence, §6).
- **(alternative) retain the active window's α only.** If the schedule emits
  windows strictly in order, the live α can be just the current window
  (`8 × W`), recomputed once. Functionally identical RAM; slightly different
  control. Pin the exact scheme in task 3.1; both meet the `≈ 8 × W` bound.

### 5. Fixed-point inheritance (UNCHANGED)

The windowed reference and HDL inherit the P1 pin **verbatim**: `W_in = 9`,
`F_in = 4`, `W_gamma = 10`, `W_ab = 15`, `W_delta = 17`, `W_xe = 18`; per-step
max-normalization (subtract the 8-state max each α/β step); saturating
adds/subs; the ±inf sentinel `MIN_SENT = -2^(W_ab-1) = -16384` for impossible
α/β init states. The flat β **acquisition** init is the **all-equal** column
(0 after max-norm) — distinct from the `MIN_SENT` terminal init, because
acquisition encodes "unknown state" (uniform), whereas the block end encodes
"known terminated state". Only the α/β **schedule and storage** change; every
arithmetic op, op-order, normalization point, and sentinel is identical to the
full-block reference. This is what keeps the inner bit-exact gate tractable.

### 6. Scope / where — inside `constituent_decoder`, K-agnostic, interface-preserving

Windowing is applied **inside** `constituent_decoder.vhdl` so that
`turbo_decoder_top`, `turbo_decoder_term_top`, and `rx_chain_top` all inherit it
**without modification** (they only ever call the constituent core with streaming
`(x_a, z_a)` in / `x_e` out). The streaming **interface is preserved**: same
ports (`start`/`k_in`/`in_valid`/`x_a_in`/`z_a_in` → `out_valid`/`out_last`/
`x_e_out`/`busy`/`done`), same load cadence (K+3 inputs), same output cadence
(K+3 extrinsics). Internally the FSM gains window/acquisition control and a
checkpoint store; the `alpha_mem` shrinks from `N_MAX`-deep to `≈ W`-deep. The
M4K-inference structure is preserved (write lifted out of the reset/case body,
registered reads, `ramstyle = "M4K"`) so the smaller α store still infers M4K.

Ideally the windowing is gated behind a **`WINDOW_LEN` generic** (with a paired
`ACQ_LEN`): setting `WINDOW_LEN ≥ K+3` collapses the schedule to a single window
with no acquisition ⇒ the **existing full-block behaviour exactly**. The windowed
core is then a strict superset, the full-block golden vectors remain valid in
that degenerate mode (a useful cross-check), and the windowed vectors are
generated at the production `WINDOW_LEN = 64`, `ACQ_LEN = 32`.

### 7. Verification — two-tier + windowing-loss band + fit (the safety-critical part)

Because finite-`L` windowing is an **approximation, not bit-exact to full-block**
(§3), the verification has the inner reference re-authored and an extra outer
band:

- **Inner gate (cocotb / GHDL, bit-exact).** `constituent_decoder` HDL is
  bit-exact to the **new** windowed fixed-point reference's golden CSV over the
  representative K set at the pinned `W`/`L`. The prior full-block vectors do
  **not** apply (they encode a different β traversal). The
  `turbo_decoder_top` / `term_top` / `rx_chain_top` lanes re-run against vectors
  regenerated from the windowed-core references.
- **Outer-A — windowing-loss band (the new check).** Windowed vs **full-block**
  fixed-point, *identical* LLR frames: extrinsic-LLR error (max/RMS) +
  hard-decision agreement at the constituent level (task 1.2), and a bounded
  end-to-end **BER-vs-SNR** windowed-core-vs-full-block-core (and vs float)
  comparison at the loop level (task 1.3). The windowing loss must stay within a
  documented band (constituent: ~1.5× above the worst converged cell of the §3
  sweep; loop: ≲ 0.1–0.2 dB). This is the artifact that establishes "windowing
  introduces no accuracy regression beyond a documented margin."
- **Outer-B — preserved float-vs-fp margins.** Re-running the existing P1
  equivalence (`characterize_constituent_decoder.m`) and P2 BER
  (`characterize_turbo_decoder.m`) with the windowed core must still pass their
  pinned bands — windowing must not erode the established float-vs-fixed-point
  margins.
- **Fit gate (Quartus II 13.0sp1, EP2C35F672C6).** Record fits at **K = 6144**
  (constituent / `turbo_decoder_top` / `rx_chain_top` — the case that previously
  did not fit; assert it now fits with 0 A&S/Fitter errors, M4K > 0, mults = 0)
  and at **K = 512** (assert the α M4K dropped from 30 to ~6 and `rx_chain_top`
  from 96/105 into comfortable headroom). Both reports are recorded deliverables.

The windowed fixed-point reference is, as at P1, **the single most
safety-critical artifact** — its correctness is established statistically by the
outer windowing-loss + float-vs-fp checks, not by bit-exactness to existing
trusted code. It deserves the most review.

## Risks / Trade-offs

- **Acquisition length vs windowing loss (the central trade).** Too short an `L`
  injects extrinsic error (§3: `L = 8` → ~7 LLR max error, HD agreement drops to
  ~99.5 %), which the iterative loop can amplify. *Mitigation:* the §3 sweep pins
  `L = 32` on the converged plateau (rms ~0.03 LLR, 100 % HD), the
  characterization band is the gate, and `L = 48` is the bit-exact escape hatch.
- **β acquisition init value.** Flat (all-equal) is the correct "unknown state"
  prior and is distinct from the `MIN_SENT` terminal init; using `MIN_SENT` for
  an interior window would be wrong (it asserts a *known* state). Pin the flat
  init explicitly in the reference and HDL (§5); the terminal window keeps the
  `MIN_SENT` init.
- **Streaming-interface preservation.** Windowing must remain an internal change;
  the per-window recompute/acquisition must not alter the externally observed
  load/output cadence or port semantics. *Mitigation:* the cocotb lanes for all
  tops compare the streamed `x_e` / decoded-bit content and are the gate;
  interface ports are explicitly out of scope.
- **Latency increase (~+L per window + recompute).** Each interior window adds
  `L` acquisition steps, and the checkpoint+recompute scheme adds ~one extra
  forward α pass (~`+N` cycles total). So total latency rises from ~`3·(K+3)` to
  roughly `~4·(K+3) + L·⌈N/W⌉`. *Mitigation:* the decoder is already
  cycle-bounded by the forward recurrence at ~15 MHz (the M4K-inference fit note);
  M2's win is **memory/fit**, not throughput. Document the latency change; it is
  acceptable for the sim/fit target.
- **Bit-exactness fragility of the new contract.** A re-authored reference is new
  trusted code. *Mitigation:* inherit the P1 arithmetic verbatim (only the
  schedule changes), keep the `WINDOW_LEN`-superset cross-check (full-block mode
  must reproduce the old vectors), and lean on the outer windowing-loss band.
- **M4K word-packing under 13.0sp1.** The smaller `alpha_mem` is the same wide
  120-bit-word shape that already infers M4K; shrinking its depth should only
  reduce the block count. *Mitigation:* per-memory fit inspection in stage 3/5;
  the proven `altsyncram` fallback remains if a shape resists inference.

## Open Questions

- **Exact `W` / `L`.** RESOLVED (task-1.2): `W = 64`, **`L = 48`** pinned. The
  full {K, SNR} sweep found `L = 32` adequate at the constituent level (PART A)
  but it missed the loop-BER band (PART B, 0.261 dB > 0.20 dB); `L = 48` is
  near-bit-exact and clears PART B (−0.029 dB). `W = 128` was not needed (`W`
  barely affects per-bit error and doubles the α window). See §3.
- **`WINDOW_LEN` generic as a full-block superset.** Confirm the degenerate
  `WINDOW_LEN ≥ K+3` mode reproduces the archived full-block golden vectors
  byte-identically (a clean regression cross-check) — the cleanest way to make
  the windowed core a strict superset.
- **α recompute vs retain-active-window (§4).** Both meet `≈ 8 × W`; pin the
  exact scheme (recompute-from-checkpoint is the default) in task 3.1, weighing
  the extra forward pass against control simplicity.
- **`xa_mem` / `za_mem` at K = 6144.** They still buffer the whole block
  (`6147 × 9 ≈ 7 M4K` each). Confirm that is acceptable (it is, vs 105 M4K) or
  whether the input buffer is also windowed/streamed — likely out of scope since
  α was the wall.
- **Fit-report gate scripted or manual.** Default: recorded manual step (no CI
  synthesis lane), matching the TX and block-RAM-inference changes.
