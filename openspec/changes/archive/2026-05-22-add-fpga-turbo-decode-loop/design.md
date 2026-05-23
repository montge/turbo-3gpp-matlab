## Context

`turbo_decoder.m` is the float oracle for the full iterative turbo decoder of
TS36.212 §5.1.3.2. It de-muxes a `3×(K+4)` LLR matrix `d_a` into an upper
constituent decoder's a-priori `(x_a, z_a)` and a lower decoder's `(x'_a,
z'_a)`, initialises the interleaved extrinsic `c_a = 0`, then runs
`max_iterations` (a multiple of 0.5) of: upper `constituent_decoder` →
interleave the systematic-plus-extrinsic to the lower decoder → lower
`constituent_decoder` → de-interleave back. The hard decision is
`c = (c_a + c_e) < 0` over the `K` systematic bits.

This change is **P2** of the staged decoder plan in
`hdl/docs/decoder_roadmap.md`. The constituent Log-BCJR (P1,
`add-fpga-constituent-decoder`) is implemented and sim-verified; the QPP
interleaver (`qpp_interleaver`) and its `K→(d0,step)` ROM (`qpp_rom`) are
implemented and sim-verified in the TX chain. P2 is the surrounding loop:
add / interleave / hard-decision / iteration FSM around those reused cores.
The full data-flow algebra, half-iteration reframing, memory map, FSM sketch,
reuse list, and cycle budget were worked out during P1 scoping and are captured
in `hdl/docs/p2_turbo_loop_design_seed.md`; **this design is faithful to that
seed and does not re-derive it.** It mirrors `constituent_encoder` →
`turbo_encoder`: standalone core first, iterative loop second.

## Goals / Non-Goals

**Goals:** a board-neutral fixed-point iterative turbo-decode loop core
(`turbo_decoder_top`) that wraps the P1 constituent decoder unmodified, exchanges
extrinsic information through the reused QPP interleaver across a fixed number
of half-iterations, and is bit-exact to an authored fixed-point full-loop
reference; that reference characterized against the float `turbo_decoder.m`
with a **bounded BER-vs-SNR** check (now meaningful); reuse of the established
layout/harness and the P1 two-tier verification methodology.

**Non-Goals (P2 boundary, see roadmap §3 — deferred to P3 / maturation):**
CRC-aided early termination, HARQ LLR accumulation, filler/`NaN→+inf`
handling, exact Log-MAP correction LUT, inter-half extrinsic scaling (~0.75),
sliding-window/BRAM BCJR, fixed-point width tightening to realistic
channel-LLR formats, a second constituent instance for pipelining, board work,
screen.

## Decisions

(Locked decisions are in `hdl/docs/decoder_roadmap.md` §2 and the data flow is
in `hdl/docs/p2_turbo_loop_design_seed.md`; this section pins the P2-specific
shape consistent with both.)

1. **Data-flow algebra (from `turbo_decoder.m`, P2 — no filler).** Computed
   once from `d_a` (`3×(K+4)`):

   ```
     z_a[0..K-1]   = d_a(2, 0..K-1)        upper parity a-priori
     z'_a[0..K-1]  = d_a(3, 0..K-1)        lower parity a-priori
     z_a[K..K+2],  x_a[K..K+2]             upper termination (de-mux)
     z'_a[K..K+2], x'_a[K..K+2]            lower termination (de-mux)
     ch_sys[0..K-1]= d_a(1, 0..K-1)        channel systematic LLR
     c_a[0..K-1]   = 0                      interleaved extrinsic (state)
   ```

   Per **upper** half: `x_a[0..K-1] = c_a + ch_sys`;
   `x_e = constituent_decoder(x_a, z_a)`;
   `c_e[0..K-1] = x_e[0..K-1] + ch_sys` (the 3 termination extrinsics
   `x_e[K..K+2]` are discarded). Per **lower** half (skipped on the final half
   when `2·max_iter` is odd): `x'_a[0..K-1] = c_e[pi[k]]` (interleave read);
   `x'_e = constituent_decoder(x'_a, z'_a)`;
   `c_a[pi[k]] = x'_e[0..K-1]` (deinterleave scatter). After all halves:
   `c[k] = (c_a[k] + c_e[k]) < 0` for `k=0..K-1`. The `x_a`/`x'_a` termination
   triplets and `z_a`/`z'_a` are **constant across iterations** — only the
   systematic a-priori body changes. The constituent core never sees "channel
   vs extrinsic"; P2 is the surrounding add / interleave / hard-decision /
   iteration FSM.

2. **Half-iteration reframing (`H = round(2·max_iterations)`).** Iterate
   `h = 0..H-1`: `h even → UPPER` half, `h odd → LOWER` half. This makes the
   0.5 granularity and the "skip final lower half" case fall out naturally
   (stop at `H`), avoiding the float `ceil`/`floor` logic of `turbo_decoder.m`
   in hardware. The reference model uses the **same** half-iteration framing so
   the inner gate is bit-exact regardless of even/odd `H`.

3. **Reuse, unmodified (the standalone-before-integration payoff).**

   | Reused core | Role in P2 | Status |
   |---|---|---|
   | `constituent_decoder` (P1) | one instance, called 2×/iteration (upper, then lower) with muxed `(x_a,z_a)` / `(x'_a,z'_a)` | implemented & sim-verified |
   | `qpp_interleaver` | streams `pi[k]` for the interleave read & deinterleave scatter | verified (TX chain) |
   | `qpp_rom` | `K→(d0,step)` for the QPP, same instantiation pattern as `turbo_encode_top` | verified (TX chain) |

   No interface change to any reused core. P1 deliberately keeps the `K+3`
   constituent output (faithful standalone `constituent_decoder`); P2 consumes
   `x_e[0..K-1]` and ignores the last 3 — no P1 change for P2's benefit
   (seed §7).

4. **One constituent instance (sequential upper→lower) for sim-first v1.** A
   second instance for upper/lower pipelining is a later throughput option, not
   v1.

5. **Memory map (`K ≤ 6144`; sim-first, async-read like prior tops).**

   ```
     persistent (set once):  z_a[K+3], z'_a[K+3], ch_sys[K]      (LLR words)
     state (per half):        c_a[K], c_e[K]                      (LLR words)
     termination consts:      x_a[3], x'_a[3]                      (tiny)
     pi:                      regenerated by qpp_interleaver       (no RAM)
     + inside the reused core: α RAM 8×(K+3)
     ───────────────────────────────────────────────────────────────────────
     ≈ 5·K LLR words + α RAM   → modest, GHDL-OK (cf. circular_buffer w[18528])
   ```

6. **`pi` regenerated per use (no `pi` RAM) for v1.** `pi` is needed twice per
   lower half (interleave read, deinterleave scatter); v1 regenerates it from
   `qpp_interleaver` each time (+`K` cycles) rather than storing a `K`-entry
   RAM — simpler, consistent with sim-first. Storing `pi` is a throughput
   option later. The interleaver-address → buffer addressing is the same
   pattern `rate_matching_top` already uses.

7. **Fixed-point continuity with P1.** The constituent core's internal
   α/β/γ/δ widths and ±inf sentinel are **inherited unchanged from P1's pinned
   format** (`add-fpga-constituent-decoder` design.md: `W_in=9` Q4.4 input
   LLR, `W_αβ=15`, `W_δ=17`, `W_xe=18`, `MIN_SENT=−16384`/`MAX_SENT=+16383`,
   saturating, per-step max-norm). P2 adds **one** new pinned format decision:
   the **extrinsic-exchange Q-format** for the persistent/cyclic LLR words
   (`z_a`, `z'_a`, `ch_sys`, `c_a`, `c_e`) and the `+ch_sys`/`+c_a` adds that
   feed the core's `x_a` input. The reference and HDL share this one parameter
   set; it is pinned in the "Fixed-point format" section once the reference is
   written and characterized (the equivalence-band knob, exactly as P1
   exercised it). Inter-half extrinsic scaling (~0.75, a common Max-Log-MAP
   accuracy aid) is **M1**, not P2 — P2 just fixes *a* format and mirrors it
   exactly in the reference.

8. **FSM sketch (seed §5).**

   ```
     S_IDLE ─in_start─► S_LOAD_D ──► S_HALF_DISPATCH ──┐
                        (de-mux d_a,     ▲             │ h<H ?
                         c_a=0, h=0)     │             ▼
                                         │      h even │ h odd
                                         │   ┌─────────┴─────────┐
                                         │   ▼                   ▼
                                         │ S_UP_BUILD         S_LO_ILV
                                         │ (x_a=c_a+ch_sys)   (drive qpp; x'_a=c_e[pi])
                                         │   ▼                   ▼
                                         │ S_UP_DEC           S_LO_DEC
                                         │ (constituent core) (constituent core)
                                         │   ▼                   ▼
                                         │ S_UP_CE            S_LO_DILV
                                         │ (c_e=x_e+ch_sys)   (drive qpp; c_a[pi]=x'_e)
                                         │   └────── h++ ────────┘
                                         └────────────┘
                                (h==H) ──► S_FINAL ──► S_OUT ──► S_DONE
                                           (c=(c_a+c_e)<0)  (stream K bits)
   ```

   `S_UP_DEC`/`S_LO_DEC` *are* the reused constituent core's run (≈ load + α +
   β/extrinsic). The interleave/deinterleave states drive `qpp_interleaver` and
   use its `pi[k]` to address `c_e` (async read) / scatter-write `c_a`.

9. **Two-tier oracle, shifted to BER at the outer layer.** Inner: cocotb checks
   HDL **bit-exact** vs the Octave fixed-point full-loop reference (existing
   generator → CSV → cocotb discipline, identical to P1). Outer: a script
   asserts a **bounded BER-vs-SNR** comparison of the fixed-point turbo
   reference vs float `turbo_decoder.m` within a documented dB margin. Unlike
   P1 (numerical *equivalence* on identical inputs, because a lone constituent
   decoder's BER is meaningless), at P2 the loop iterates and BER is the right
   oracle — this is exactly where the Max-Log-MAP ~0.1–0.5 dB loss is measured
   (roadmap §1). The harness MUST be explicitly **bounded** (few SNR points,
   modest frame counts, shallow target BER ~1e-2–1e-3 — a trend/margin check,
   not a deep waterfall, intractable in Octave).

10. **Cycle budget (pre-commit the large-`K` limit).** constituent call
    ≈ `3·(K+3)`, 2 calls/full iteration; interleave + deinterleave ≈ `2·K`
    (qpp regen); per full iteration ≈ `~8·K`; `H` halves → ≈ `~4·H·K` total.
    `K=6144, max_iter=8 (H=16)` → ≈ `4·16·6144 ≈ 4·10^5` sim cycles/vector. The
    P2 vector suite keeps **few** large-`K` cases (the `tx_chain_top` lesson,
    a locked roadmap constraint, roadmap §2).

## Risks / Trade-offs

- **Fixed-point full-loop reference is new trusted code** → outer bounded-BER
  check vs the float `turbo_decoder.m`; the reference is the P1 fixed-point
  constituent reference (already characterized) wrapped with the exact loop
  algebra above, so the new surface is the loop/exchange code, not the BCJR —
  small and reviewable.
- **Outer check meaning changed from P1** → at P2 it is communications BER, not
  numerical equivalence; the band is a *bounded* dB-margin trend check, pinned
  in the Fixed-point format section once measured. Risk: an over-tight margin
  becomes brittle → set ~1.5× above worst-observed like P1's equivalence band.
- **Extrinsic-exchange overflow** → the `c_a`/`c_e` and `+ch_sys` adds use a
  pinned saturating Q-format with the same margin discipline as P1; asserted at
  the largest `K`. No new ±inf sentinel — the core's saturation magnitude is
  reused (P3's filler `+inf` will reuse it too).
- **Cycle budget at large `K`** → `~4·H·K` is large; keep few large-`K`
  vectors (pre-committed) and exploit the deterministic FSM so per-vector sim
  time is predictable.
- **`pi` regeneration cost** → `+K` cycles per lower half is accepted for v1
  simplicity (no `pi` RAM); a `pi`-store is a later throughput option.
- **Bit-exactness fragility** → minimized exactly as P1: Max-Log-MAP
  (order-independent `max`), the single P1 normalization point, the shared ±inf
  sentinel, and now one additional pinned exchange format mirrored identically
  in the reference.

## Fixed-point format — PINNED (post reference-authoring, task 1.2)

P2 inherits the P1 constituent-core format unchanged (see
`add-fpga-constituent-decoder` design.md: `W_in=9` Q4.4, `F_in=4`,
`W_gamma=10`, `W_ab=15`, `W_delta=17`, `W_xe=18`, ±inf sentinel
`MIN_SENT=−16384`/`MAX_SENT=+16383`, per-step max-norm, saturating). The **one**
new quantity P2 pins is the extrinsic-exchange word format. These values are the
pinned defaults in `scripts/fixedpoint_turbo_decoder.m` (`default_params`) and
were confirmed against the outer BER margin (`scripts/characterize_turbo_decoder.m`):

| Quantity | Format (signed) | Status |
|---|---|---|
| fractional scale (whole exchange) | `F_in = 4` — **shared with the P1 core**, so the exchange↔core boundary is a pure width/saturate, no rescaling | **PINNED** |
| persistent parity LLR `z_a, z'_a` + termination triplets | P1 core input format `W_in = 9` (Q4.4) — they are direct core inputs, quantized once | **PINNED** |
| persistent systematic LLR `ch_sys` | extrinsic-exchange word `W_ext = 12` (Q7.4, range ~[−128,+128) at `F_in=4`) — it feeds the accumulator adds | **PINNED** |
| cyclic extrinsic `c_a, c_e` | extrinsic-exchange word **`W_ext = 12`** (Q7.4) — 3 integer bits over `W_in`'s range; extrinsics accumulate confidence across `H=16` half-iterations and `W_in=9` (~[−16,+16)) would clip strong extrinsics and inject loss the float oracle lacks | **PINNED** |
| combiner accumulator `c_a+ch_sys`, `x_e+ch_sys`, `c_a+c_e` | **`W_acc = 14`** (one bit over `W_ext` for the two-operand sum + margin), saturating to the `W_acc` range, then re-quantized (saturating) to `W_ext` for storage / to `W_in` for the core input | **PINNED** |
| `x_a = c_a + ch_sys` (core input) | re-quantized (saturating) from the `W_acc` accumulator down to the P1 core input format **`W_in = 9`** before entering the core | **PINNED** |

`W_ext` and `W_acc` reuse P1's saturation philosophy: a single symmetric
saturating magnitude per width, no wrap, no new ±inf token (P3's filler `+inf`
will reuse the core's `MAX_SENT`). The widths are pinned ~1.5× above the worst
observed need across the bounded SNR sweep — the same band discipline P1 used.
**No widening beyond `W_in=9` was needed at the exchange *inputs***: the
`W_in=9` parity/termination/core-input words are unchanged from P1; the only new
width is the wider *stored/accumulator* path (`W_ext=12`, `W_acc=14`) that keeps
the exchange itself from saturating.

**Iteration default (PINNED):** `max_iterations = 8` ⇒ `H = round(2·8) = 16`
half-iterations (even=upper/systematic, odd=lower/interleaved). No early
termination (P3). A small-`H` case is reserved for the fast-regression vector
suite (task 2.2).

**LLR memory-word footprint (PINNED, from the reference's memory map):**
persistent `z_a[K+3]`, `z'_a[K+3]`, `ch_sys[K]` + cyclic `c_a[K]`, `c_e[K]` =
**`5·K + 6` LLR words** (`≈ 5·K`), plus the reused core's `8×(K+3)` α-RAM and
the tiny `x_a[3]`/`x'_a[3]` termination consts. At `K=6144` that is `≈ 30,726`
exchange LLR words (`W_ext=12` ⇒ ≈ 46 kB) + the core α-RAM — modest, GHDL-OK
(cf. `circular_buffer w[18528]`). `pi` is regenerated per use (no `pi` RAM).

## Open Questions

Settled during task-1.2/1.3 implementation (CLOSED below); the one remaining
item is an RTL-stage decision deferred to stage 3.

- **`max_iterations` default — CLOSED.** Pinned **`max_iter = 8`** ⇒
  **`H = 16`** half-iterations (user-confirmed). A small-`H` case is reserved
  for the fast-regression vector suite (task 2.2). No early termination (P3).
- **Extrinsic-exchange fixed-point width — CLOSED.** Pinned
  **`W_ext = 12`** (Q7.4) for stored `c_a`/`c_e`/`ch_sys` and **`W_acc = 14`**
  for the combiner accumulator (`c_a+ch_sys`, `x_e+ch_sys`, `c_a+c_e`),
  re-quantized (saturating) to `W_in = 9` for the core input. `F_in = 4` is
  shared with the core (pure width/saturate boundary). The `W_in=9`
  parity/termination/core-input words are **unchanged from P1** — no widening
  there; only the stored/accumulator path is wider. See the "Fixed-point
  format — PINNED" table. Confirmed within the outer BER margin.
- **Memory width confirmation — CLOSED.** **`5·K + 6` LLR words** (`≈ 5·K`):
  persistent `z_a[K+3]` + `z'_a[K+3]` + `ch_sys[K]`, cyclic `c_a[K]` + `c_e[K]`;
  plus the reused core's `8×(K+3)` α-RAM and tiny `x_a[3]`/`x'_a[3]` consts.
  GHDL-modest (see the PINNED footprint note above).
- **Outer BER margin (dB) and bounded grid — CLOSED.** Bounded grid:
  `K ∈ {40, 512}`, `SNR ∈ {−2.5,−2.0,−1.5,−1.0,−0.5} dB`, frames 120/`K=40`
  and 10/`K=512` (~5k+ bits/cell), shallow target BER `1e-2`. Pinned band:
  **fixed-point implementation loss ≤ 1.0 dB** (horizontal shift at the target
  BER), set generously because the `W_in=9` core is intentionally not yet
  width-tightened (that is M3). See `scripts/characterize_turbo_decoder.m`.
- **Shared vs duplicated α RAM — DEFERRED (RTL stage 3).** v1 uses **one**
  constituent instance, so its `8×(K+3)` α RAM is reused across upper and
  lower halves (re-filled each half) — no duplication. This is the v1 seed
  decision; a second instance (with its own α RAM) for pipelining is a deferred
  throughput option, flagged so it is not silently assumed. Not settled by
  stage 1 (which is reference + characterization only).
