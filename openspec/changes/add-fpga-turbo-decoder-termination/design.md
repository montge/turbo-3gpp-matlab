## Context

`turbo_decoder.m` and `turbo_decoding_chain.m` are the float oracles for the
full LTE code-block turbo decoder of TS36.212 §5.1.3.2 / §5.1.2. P2
(`add-fpga-turbo-decode-loop`, implemented and sim-verified) delivered the
*bare* iterative loop `turbo_decoder_top`: de-mux of the `3×(K+4)` LLR matrix,
`H = round(2·max_iterations)` half-iterations exchanging extrinsic information
through the reused `qpp_interleaver`, and the hard decision `(c_a + c_e) < 0`.
P2 ran a fixed `H` every time and explicitly deferred CRC early termination,
HARQ accumulation, and filler bits to P3.

This change is **P3** of `hdl/docs/decoder_roadmap.md`. It adds exactly those
three deferred `turbo_decoder.m` / `turbo_decoding_chain.m` behaviours:

1. **CRC-aided early termination.** `turbo_decoder.m` takes a 4th argument
   `G_max` (a CRC generator matrix); after the de-mux it computes an initial
   hard decision and, after *each* half-iteration, recomputes the hard decision,
   runs `calculate_crc_bits(c, G_max)`, and `return`s early with
   `iterations_performed` set to the half-iteration index when `sum(p) == 0`
   (CRC passes). Otherwise it runs to `max_iterations` and returns
   `iterations_performed = max_iterations`. The check points are: before the
   loop (`iterations_performed = 0`), after each upper half
   (`iteration_index − 0.5`), and after each lower half (`iteration_index`).
2. **HARQ soft combining.** `turbo_decoding_chain.m` with `I_HARQ ~= 0`
   accumulates the rate-dematched `3×D_r` channel-LLR matrix `d` into a per-code-
   block soft buffer (`obj.buffers{r+1} = obj.buffers{r+1} + d`) **before**
   calling `turbo_decoder`, and resets the buffer via `reset` between
   information blocks.
3. **Filler bits.** `turbo_decoding_chain.m` marks the first `F_r` systematic
   LLRs `NaN` (`d(1:2,1:F_r) = NaN`); `turbo_decoder.m` records
   `filler_bits = find(isnan(d_a(1,:)))`, maps `d_a(isnan) = inf`, decodes
   normally, and forces `c(filler_bits) = NaN` on output. Filler positions are
   *known* bits (encoder-side they are forced 0), so `+inf` LLR pins them.

The float model also distinguishes the **code-block CRC (CRC24B)** — used per
code block when `C > 1` — from the **transport-block CRC (CRC24A)** — used when
`C == 1` (a single code block carries the TB CRC). Both are 24-bit; the existing
hardware-verified `crc8_parallel.vhdl` is only an 8-bit CRC, so a new CRC24
block (or a width-generalised CRC core) is needed (decision below). This design
is faithful to the float algebra and does not re-derive the P2 loop.

## Goals / Non-Goals

**Goals:** mature the P2 loop into a usable LTE code-block decoder by adding, in
fixed-point and bit-exact to an extended authored reference: (a) deterministic
CRC-aided early termination with an `iterations_performed` output, (b) HARQ soft
combining of channel LLRs across retransmissions, and (c) filler-bit handling
that reuses the P1 ±inf sentinel; reuse the P2 loop, the P1 constituent core,
the `qpp` cores, and the existing CRC generator-matrix idiom; characterize the
extended reference against the float `turbo_decoder.m` /
`turbo_decoding_chain.m` with a bounded outer oracle extended to early-stop and
CRC-pass-rate.

**Non-Goals (P3 boundary, see roadmap §3 — the maturation track and beyond):**
exact Log-MAP correction LUT + inter-half extrinsic scaling (~0.75) (**M1**),
sliding-window/BRAM BCJR (**M2**), fixed-point width tightening to realistic
channel-LLR formats (**M3**), RX-chain integration / de-rate-matching / soft
combining feeding the decoder (**P4**), the optional DE2 board demo (**M4**). No
new fixed-point format for the decode datapath (P3 inherits P1/P2 widths and the
±inf sentinel unchanged); no second constituent instance; no board work; no
screen.

## Decisions

(Locked decisions are in `hdl/docs/decoder_roadmap.md` §2; the P2 loop is in
`add-fpga-turbo-decode-loop`. This section pins the P3-specific shape consistent
with both.)

1. **CRC core: new CRC24 block, generator-matrix style (reusing the
   `crc8_parallel` idiom, not the 8-bit core).** The existing
   `crc8_parallel.vhdl` computes `p = a·G mod 2` over a fixed `16→8` generator
   matrix whose rows match `get_crc_generator_matrix(16, CRC8)` — exactly the
   `calculate_crc_bits` algebra. P3 needs the **same algebra at 24 bits** for a
   variable-length code block (`K` up to 6144), with two polynomials: **CRC24A**
   (TB CRC, `C == 1`) and **CRC24B** (CB CRC, `C > 1`). The 8-bit core is not
   reusable directly (fixed 16-bit input, 8-bit poly), but its *pattern* is: a
   new `crc24_check` core accumulates the per-bit XOR of the generator-matrix
   rows over a streaming hard-decision bit sequence and asserts a single
   `crc_ok` when the 24-bit remainder is all-zero. **Open question raised, not
   resolved:** whether to author one parameterised CRC core (width + generator
   ROM as generics) that subsumes `crc8_parallel`, or a standalone `crc24_check`
   leaving `crc8_parallel` untouched. v1 leans standalone (additive, no
   regression risk to the hardware-verified CRC8), but the generator-matrix
   generation must match `get_crc_generator_matrix(6144, ·)` for the two LTE
   polynomials; the float `calculate_crc_bits` slices `G_max(end-K+1:end, :)`
   for length `K`, so the HDL generator ROM is sized for the max `K` and indexed
   from the tail — pinned during reference authoring.

2. **Early-stop control integrated into the P2 FSM via `iterations_performed`.**
   The P2 loop FSM (`S_IDLE→S_LOAD_D→S_HALF_DISPATCH→{upper|lower}→S_FINAL→
   S_OUT→S_DONE`) gains a CRC-check sub-step after each half's hard decision:
   compute `c[k] = (c_a[k] + c_e[k]) < 0` over the `K` systematic bits (the same
   combiner the P2 `S_FINAL` already has, now also evaluated mid-loop), stream it
   through the `crc24_check` core, and on `crc_ok` jump to `S_FINAL`/`S_OUT`
   early, latching `iterations_performed` (`0` pre-loop, `iteration_index − 0.5`
   after an upper half, `iteration_index` after a lower half — matching the
   float return values). When CRC never passes, the loop runs to `H` exactly as
   P2 and returns `iterations_performed = max_iterations`. There is **also a
   pre-loop check** (`turbo_decoder.m` evaluates `c = (d_a(1:K) < 0)` and the
   CRC before the iteration loop, possibly returning `iterations_performed = 0`)
   — the HDL reproduces this. Early termination is enabled only when a CRC
   generator is supplied (mirrors `nargin == 4`); with no CRC the core behaves
   exactly like P2 (fixed `H`).

3. **Early termination is DETERMINISTIC ⇒ the bit-exact lane is preserved.**
   The decisive design constraint: the early-stop point is a pure function of
   the (quantized) inputs — same `d_a`, `K`, `max_iterations`, CRC polynomial ⇒
   same `iterations_performed` and same decoded bits, in both the reference and
   the HDL. No timing-, race-, or scheduling-dependence. Therefore the inner
   oracle stays a strict bit-exact check: golden vectors carry the expected
   `iterations_performed` AND the expected `c`, and the lane asserts both. The
   reference and HDL evaluate the CRC at the **same** check points
   (pre-loop, post-upper, post-lower) in the **same** order, so the stop index
   is identical bit-for-bit. This is the analogue of P1/P2's "identical
   quantization, saturation, normalization point" contract, extended to "identical
   CRC check schedule".

4. **Filler `NaN→+inf→MAX_SENT` reuses the P1 sentinel UNCHANGED.** At LLR
   de-mux the reference and HDL map filler-marked positions (the first `F_r`
   systematic LLRs, signalled `NaN` upstream by `turbo_decoding_chain.m`) to the
   `+inf` token, which in fixed-point is the P1-pinned **`MAX_SENT = +16383`**
   (archived `add-fpga-constituent-decoder` design.md: the saturating
   max-magnitude that never overflows under `+γ` and can never spuriously lose a
   `max` for a known-confident bit). No new sentinel, no new format — this is the
   exact P1→P3 reuse the roadmap §2 pinned. Filler positions decode as
   strongly-known bits (`+inf` ⇒ hard `0`, since LLR `= ln[P(0)/P(1)]`) and are
   forced to the model's `NaN`/known value on output, matching
   `c(filler_bits) = NaN`. The CRC-over-hard-decision treats filler positions
   consistently with the float model (the float computes the CRC on `c` *before*
   the `c(filler_bits) = NaN` overwrite — pinned identically in the reference).

5. **HARQ soft-accumulate at the channel-LLR input stage.** Before the loop, an
   optional accumulate stage sums the incoming `3×D_r` (`= 3×(K+4)`) channel-LLR
   matrix into a soft buffer (`buffer ← buffer + d`), mirroring
   `turbo_decoding_chain.m`'s `obj.buffers{r+1} = obj.buffers{r+1} + d`. The
   accumulated matrix is what feeds the P2 de-mux. A `clear`/`reset` control
   zeroes the buffer between information blocks (the float `resetImpl`). The
   accumulator is a saturating fixed-point add into a buffer one or more bits
   wider than the channel-LLR word (so a bounded number of retransmissions
   cannot wrap), reusing the same saturating-add / width-margin philosophy as
   the P2 extrinsic exchange and, where the storage pattern fits, the existing
   `circular_buffer` / RAM idioms. **Open question raised:** HARQ buffer width
   and max-retransmission count (below). Note filler positions accumulate as
   `+inf`/`MAX_SENT` and stay saturated (a known bit stays known across
   retransmissions) — the saturating sentinel is idempotent under accumulation,
   which is the correct behaviour.

6. **Fixed-point continuity with P1/P2 — NO new decode-datapath format.** The
   constituent core's α/β/γ/δ widths and ±inf sentinel are inherited from P1;
   the extrinsic-exchange format (`W_ext`, `W_acc`, `W_in`) is inherited from P2
   unchanged. P3 introduces only: (a) the **HARQ accumulator width** (an
   extension of the channel-LLR word with retransmission headroom — pinned once
   the reference is characterized, the only new fixed-point knob), and (b) the
   CRC core, which is pure bit logic (no Q-format). The filler mapping reuses the
   existing sentinel, introducing no new format. This keeps the bit-exactness
   surface minimal — the new code is control (early-stop FSM), bit logic (CRC),
   and one saturating accumulator, not new soft arithmetic.

7. **FSM sketch (P2 loop + P3 early-stop / filler / HARQ).**

   ```
     S_IDLE ─in_start─►(HARQ? S_HARQ_ACC: buffer+=d)─► S_LOAD_D
        (de-mux d_a, filler→MAX_SENT, c_a=0, h=0)
                   │
                   ▼
         S_PRECHECK ─CRC(c0)ok?─► S_FINAL (iters=0)
                   │ no
                   ▼
     ┌──► S_HALF_DISPATCH ──── h<H ? ────────────────┐
     │        h even │ h odd                          │ h==H
     │   ┌───────────┴───────────┐                    ▼
     │   ▼                        ▼                 S_FINAL
     │ (P2 upper half)        (P2 lower half)     (iters=max_iter)
     │   ▼                        ▼                    │
     │ S_CRC_CHK (c=(c_a+c_e)<0; crc24_check)          ▼
     │   │ crc_ok → latch iters=(h even? h/2+0.5 : ...) S_OUT (stream K bits +
     │   │         → S_FINAL                                    iters_performed)
     │   └─ not ok ─ h++ ─┘                            ▼
     └────────────────────────────────────────────► S_DONE
   ```

   `S_PRECHECK` and `S_CRC_CHK` reuse the P2 combiner (`c_a + c_e`, here also the
   pre-loop `d_a(1:K) < 0`) and drive the new `crc24_check` core; everything else
   is the unmodified P2 loop. With early termination disabled (no CRC supplied),
   `S_PRECHECK`/`S_CRC_CHK` are bypassed and the behaviour is byte-for-byte P2.

8. **Two-tier oracle, extended (not changed in kind).** Inner: cocotb checks the
   HDL **bit-exact** vs the extended Octave fixed-point reference — now asserting
   BOTH the `K` decoded bits AND `iterations_performed` (the generator → CSV →
   cocotb discipline, identical to P1/P2). Outer: the bounded characterization
   harness compares the fixed-point reference vs float `turbo_decoder.m` /
   `turbo_decoding_chain.m` on the **same** bounded grid, now also asserting that
   the early-stop `iterations_performed` distribution and the CRC-pass rate track
   the float model, and that HARQ retransmission improves BER as the float
   predicts. Bounded exactly as P2 (few SNR points, modest frames, shallow target
   BER) — a trend/margin check, not a deep waterfall.

9. **Vectors EXERCISE the new behaviours.** The golden suite must include: (a)
   blocks that early-terminate at *different* `iterations_performed` (low-SNR →
   runs to `max_iter`; high-SNR → stops in 1–3 iterations; a pre-loop-pass case
   with `iterations_performed = 0`); (b) at least one filler code block (`F_r >
   0`), checking filler positions decode as known bits and the CRC handles them
   per the float model; (c) at least one HARQ sequence (≥2 retransmissions of the
   same block at a low per-transmission SNR that only decodes after combining),
   checking the soft buffer accumulates correctly and the post-combine decode
   matches. Few large-`K` cases (the `~4·H·K` cycle budget from P2, now *reduced*
   on average by early termination but bounded by `H` worst-case).

## Risks / Trade-offs

- **CRC24 generator-matrix correctness is new trusted bit logic** → the new
  `crc24_check` is verified bit-exact against `calculate_crc_bits(c, G_max)` for
  both CRC24A and CRC24B over the vector suite (the same generator-matrix algebra
  the hardware-verified `crc8_parallel` already validates at 8 bits); the
  generator ROM rows are emitted from `get_crc_generator_matrix` so they cannot
  drift from the float model.
- **Early termination could break bit-exactness if non-deterministic** →
  mitigated by Decision 3: the stop point is a pure function of quantized inputs,
  the reference and HDL check the CRC at identical points in identical order, and
  the lane asserts `iterations_performed` explicitly. Risk surfaces immediately
  as a lane mismatch if the schedules ever diverge.
- **HARQ accumulator overflow** → saturating add into a width-margined buffer
  (Decision 5); the max-retransmission count is bounded and pinned (open
  question); asserted at the largest `K` and the worst-case retransmission count;
  filler `MAX_SENT` is idempotent under saturating accumulation (stays a known
  bit).
- **Filler interaction with the CRC and the ±inf sentinel** → filler reuses the
  P1 sentinel unchanged and is mapped at de-mux exactly where the float does
  `d_a(isnan) = inf`; the CRC is computed on the hard decision *before* the
  `c(filler) = NaN` overwrite, pinned identically in the reference; asserted by a
  dedicated filler vector.
- **Average-vs-worst-case latency** → early termination reduces *average* cycles
  (~2–3× at good SNR) but worst case stays the P2 `~4·H·K`; the cycle budget and
  few-large-`K` rule are unchanged; the outer harness records the
  `iterations_performed` distribution so the latency win is measured.
- **Scope creep into M1–M4 / P4** → hard boundary in Goals/Non-Goals; the new
  surface is control + bit logic + one accumulator, no new soft arithmetic, no
  width retune of the decode datapath.

## Fixed-point format — PINNED (post reference-authoring, task 1.x)

P3 inherits the P1 constituent-core format and the P2 extrinsic-exchange format
**unchanged** (P1 design.md: `W_in = 9` Q4.4, `W_γ = 10`, `W_αβ = 15`,
`W_δ = 17`, `W_xe = 18`, ±inf sentinel `MIN_SENT = −16384` / `MAX_SENT =
+16383`, per-step max-norm, saturating; P2 design.md: `W_ext = 12` Q7.4 stored,
`W_acc = 14` combiner, re-quantize to `W_in = 9` for the core input,
`F_in = 4`). The decode datapath gets **no new format**.

| Quantity | Format (signed) | Status |
|---|---|---|
| filler-bit fixed-point token | the P1 ±inf sentinel **`MAX_SENT = +16383`** at the core input format — reused unchanged, no new value | inherited (P1) |
| early-termination control / `iterations_performed` | integer (half-iteration index, multiple of 0.5 ⇒ stored as `round(2··)` half-index); no Q-format | new (control only) |
| CRC24 remainder / `crc_ok` | pure GF(2) bit logic (24-bit XOR-accumulate over the generator-matrix rows); no Q-format | new (bit logic) |
| HARQ soft accumulator `buffer + d` | channel-LLR word widened by `ceil(log2(N_retx_max))` bits + margin, saturating; re-quantized to the P2 de-mux input format before decoding | **PINNED (task 1.x)** |

The HARQ accumulator is the **only** new fixed-point knob; its width is pinned
≥ the channel-LLR word plus headroom for the pinned max-retransmission count,
~1.5× above worst-observed need across the bounded sweep — the same band
discipline P1/P2 used. No widening of the decode datapath.

## Open Questions

These are the items the user should weigh in on; settled during task-1.x
implementation otherwise.

- **CRC24 vs existing CRC8 infra — OPEN (Decision 1).** Author a standalone
  `crc24_check` (additive, zero regression risk to the hardware-verified
  `crc8_parallel`), or generalise into one parameterised CRC core (width +
  generator-ROM generics) that subsumes both? Both LTE polynomials (CRC24A for
  the TB CRC when `C == 1`, CRC24B for the CB CRC when `C > 1`) must be
  supported, generated from `get_crc_generator_matrix(6144, ·)` and tail-indexed
  for length `K` exactly as `calculate_crc_bits` slices `G_max`. Recommendation:
  standalone `crc24_check` for v1; flag the parameterised-core refactor as a
  later cleanup. **User input requested.**
- **HARQ buffer width and max-retransmission count — OPEN (Decision 5).** The
  soft accumulator needs a pinned max number of retransmissions to size its
  width-margin (e.g. 4 or 8 retx). What `N_retx_max` should v1 target, and is one
  shared buffer per code block (matching `obj.buffers{r+1}`) the right v1 storage
  (vs reusing a `circular_buffer`-style RAM)? Pinned in the Fixed-point table
  once characterized; **user input requested** on the retransmission count.
- **Does early termination change the bit-exact contract? — CLOSED (Decision
  3).** No. Early termination is deterministic (pure function of quantized
  inputs); the reference and HDL check the CRC at identical points in identical
  order; the lane asserts `iterations_performed` AND the decoded bits. The
  bit-exact inner gate is preserved exactly as P1/P2.
- **CB-vs-TB CRC selection — CLOSED.** Mirror `turbo_decoding_chain.m`: use
  CRC24B (`CRC_generator_matrix_CB`) when `C > 1`, CRC24A
  (`CRC_generator_matrix_TB`) when `C == 1`. At the single-code-block decoder
  level this is a run-time polynomial-select input to the `crc24_check` core; the
  chain-level `C` selection is a P4 (RX integration) concern, flagged so it is
  not silently assumed here.
- **Filler on output — CLOSED (Decision 4).** Filler positions decode as
  known bits (`+inf`/`MAX_SENT` ⇒ hard `0`); the CRC is computed on the hard
  decision *before* the float's `c(filler) = NaN` overwrite; the reference pins
  this order and the lane checks it. Whether the HDL emits a NaN-equivalent
  "known" flag or just the decoded `0` is an interface detail pinned at the RTL
  stage (it does not affect the CRC or the bit-exact decode check).
