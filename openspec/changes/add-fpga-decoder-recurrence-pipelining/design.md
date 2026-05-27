# Design — add-fpga-decoder-recurrence-pipelining (bounded throughput)

## 0. Re-scope after a feasibility probe (2026-05-27)

The original stub (and `decoder_roadmap.md` §6) framed this as the **Option B**
"50 MHz decoder": ACS look-ahead / radix-2 unrolling to break the α/β feedback
cone, on the premise that the **per-step max-normalization** (the 8-way running
max + subtract folded into the recurrence) is the dominant ~64-70 ns critical
path. A direct synthesis probe **disproved that premise**, so this change is
re-scoped from "reach 50 MHz" to a **measurement-gated bounded throughput win**.

**The probe (timing-only, on a throwaway worktree, Quartus II 13.0sp1, EP2C35):**
replaced the per-step *max*-normalization in BOTH the forward α step (`S_FWD`)
and the backward β step (`S_BWD`) with **anchor normalization** — subtract
state-1 (`new_a(1)` / `new_b(1)`) instead of the 8-way running max. Anchor
normalization removes the whole 8-way max *tree* from the recurrence while
staying output-equivalent (it subtracts a common per-step offset from all 8
states, which cancels in the extrinsic `x_e = max(δ|x=0) − max(δ|x=1)` — exactly
the property `decoder_roadmap.md` §1 already documents for normalization).

**Result: Fmax 14.25 MHz → 14.2 MHz — essentially zero change.** The reason is
visible in the new worst-case setup path:

| build | restricted Fmax | worst-path endpoint | data delay |
|-------|-----------------|---------------------|------------|
| baseline (max-norm) | 14.25 MHz | `…u_cd\|alpha_prev[..]` (α recurrence) | 70.1 ns |
| anchor-norm probe   | 14.2 MHz  | `…u_cd\|xe_r[..]` (δ→x_e fold)         | 70.4 ns |

So the decoder has **(at least) two independent ~70 ns paths** that co-limit
Fmax, not one:

1. **The α/β recurrence** — a true single-cycle feedback cone
   (`sat_add(α+γ) → 2-way maxstar → normalize → feedback`). Cheapening the
   normalization did not lift Fmax because path (2) is sitting at the same level.
2. **The `S_BWD` extrinsic fold** — `alpha_mem` read → a **16-term sequential
   left-fold of `maxstar`** (8 transitions per `x∈{0,1}` set, ~7 maxstar deep
   per set) → `sat_sub` → `xe_r`. This is **feed-forward**, not a recurrence.

Conclusion: there is **no cheap single lever**, and 50 MHz (20 ns, a ~3.5×
shortening of *both* paths, including a true feedback recurrence) is not a safe
bet. But a **bounded** win is plausible and partly low-risk, because path (2) is
feed-forward and its serial fold is needlessly deep.

## 1. Goal (re-scoped)

Raise the decoder's achievable Fmax by attacking the two co-limiting paths with
techniques that are **output-bit-exact in the board's Max-Log-MAP mode**
(`EXACT_LOGMAP=false`), then **fit at the measured achievable clock** (likely a
faster PLL, e.g. ~25 MHz, ≈ 2× the current 12.5 MHz board clock = ~2× decode
throughput). The exact target clock is **whatever stage 1 measures**, not a
pre-committed 50 MHz. If stage 1 shows < ~1.5× headroom, this change is
**shelved with the finding documented** (the M2 precedent).

Non-goal: the original 50 MHz / radix-2 look-ahead. That remains a possible
*future* arc; this change banks the tractable partial win first.

## 2. Techniques (ranked by risk)

### 2a. Balanced-tree extrinsic fold (low risk, likely zero reference change)

The `S_BWD` extrinsic fold currently reduces 8 deltas per set with a **sequential
left-fold** (`max0 := delta₁; max0 := maxstar(max0, δ₂); …`), ~7 `maxstar` deep.
In the board's **Max-Log-MAP** mode `maxstar` degenerates to plain `imax`, which
is **associative** — so re-associating the fold into a **balanced 3-level binary
max-tree** yields **bit-identical** results. The 16-element `gamma`/`sat_add`
front of the fold is unchanged; only the reduction shape changes.

- **Bit-exactness:** in `EXACT_LOGMAP=false` the tree == the serial fold exactly,
  so the existing constituent / loop / term golden vectors stay **byte-identical**
  and all decoder lanes must remain green with **no new reference**.
- **EXACT_LOGMAP=true caveat:** there `maxstar` is *not* associative (the
  seed-from-first-delta order is a pinned bit-exact contract, design `§4` of the
  M1 change). The tree therefore must be **gated** so the exact-mode path keeps
  the serial fold (or the exact-mode reference is regenerated for the tree order).
  Default/board mode is the target; exact mode keeps its current schedule.
- **Expected effect:** turns a ~7-deep serial `maxstar` chain into ~3 levels,
  roughly halving path (2).

### 2b. Cheaper recurrence normalization (low–moderate risk)

Replace the in-loop 8-way max-normalization with **anchor normalization**
(subtract a fixed state) or **modulo normalization** (two's-complement
wraparound compare, no subtract at all). Both are output-equivalent (common
offset cancels in `x_e`). This shortens path (1)'s cone by removing the 8-way
max tree from the feedback loop.

- **Bit-exactness:** the *internal* α/β values change, but the decoded output
  (`x_e`, decoded bits) is unchanged. **Open question for stage 1/2:** do the
  decoder cocotb lanes assert on internal α/β, or only on `x_e` / output bits? If
  only outputs, golden vectors stay byte-identical. If internals are checked, the
  reference + vectors are regenerated for the new normalization (a contained,
  well-understood change — the offset is deterministic).
- Anchor norm preferred over modulo first (simpler, keeps the existing saturating
  arithmetic and width pinning; modulo needs a width-spread proof to guarantee no
  wrap-induced miscompare).

### 2c. Pipeline the feed-forward fold across cycles (moderate risk, latency cost)

If 2a alone leaves path (2) limiting, split the `S_BWD` cycle so the
`alpha_mem read → fold → xe_r` work spans **two pipeline stages** (e.g. register
the per-set partial maxes, emit `x_e` one cycle later). This is feed-forward, so
it only adds **latency**, not a value change — the emitted `x_e` bit values are
identical; only *when* they appear shifts by a fixed pipeline depth.

- **Bit-exactness:** output bit *values* unchanged; the cocotb lane's timing
  model (when `out_valid`/`x_e` beats land) updates, golden bit/LLR values do
  not. `iterations_performed` and framing semantics preserved.
- Deferred unless 2a+2b don't clear the stage-1 gate.

### 2d. (Out of scope) radix-2 / look-ahead on the feedback recurrence

The genuine α/β feedback recurrence (`sat_add → maxstar → normalize → feedback`)
is the hard floor. Radix-2 (two trellis steps/cycle) **doubles** the per-cycle
ACS work to halve the cycle count — net Fmax benefit is uncertain and the area
cost is large. **Explicitly out of scope here**; it is the lever for a *future*
50 MHz arc only if the bounded win proves insufficient and throughput is still
wanted.

## 3. The bit-exact contract (clarified vs the stub)

The stub assumed a **new** pipelined reference and **new** golden vectors. The
probe-informed design **inverts that default**: the primary techniques (2a, and
2b if the lanes check only outputs) are **output-bit-exact to the EXISTING
Max-Log-MAP golden vectors**, so the strong, low-risk gate is **"all existing
decoder lanes stay green and `hdl/vectors/*` stay byte-identical."** A new
reference is required **only** if (i) exact-mode fold re-association is pursued,
or (ii) the chosen normalization changes internally-checked values, or (iii) the
fold is pipelined and the lane asserts on exact beat timing. Each of those is a
contained, deterministic change — not the open-ended "new schedule + new widths"
the stub implied.

## 4. Staging (measurement-gated — the M2 discipline)

**Stage 1 — GO/NO-GO Fmax probe (the gate).** Implement 2a (balanced-tree fold,
gated on `EXACT_LOGMAP=false`) + 2b (anchor normalization) behind generics that
**default to the current behavior**. Synthesize `turbo_decoder_top` (board K)
under Quartus II 13.0sp1 and **measure restricted Fmax + the new worst path**.
- **GO** if Fmax improves ≥ ~1.5× (e.g. ≥ ~22 MHz) → proceed.
- **NO-GO** if < ~1.5× → record the finding in `decoder_roadmap.md`, mark the
  change shelved (M2-style), and stop. (Optionally evaluate 2c once before
  giving up.)

**Stage 2 — bit-exactness.** With the winning combination enabled by default for
Max-Log-MAP mode: re-run all decoder cocotb lanes (`constituent_decoder`,
`turbo_decoder_top`, `turbo_decoder_term_top`) + the constituent-logmap exact
lane; confirm `hdl/vectors/*` byte-identical. Regenerate a reference/vectors
**only** if §3 (i)/(ii)/(iii) forces it, and characterize unchanged BER.

**Stage 3 — integrate + fit at the measured clock.** Full regression (all TX +
decoder lanes + Octave suite). Quartus fit `turbo_decoder_de2` at the highest
PLL the stage-1 Fmax supports (e.g. 25 MHz); record Fmax / LE / M4K vs baseline.
The board demo keeps its self-check + LCD; only the PLL multiply/divide changes.
On-board re-confirm is hardware-gated (user's board), reusing the existing
`PASS e=000 it=2` self-check.

**Stage 4 — validate.** `openspec validate … --strict` + `--all --strict`.

## 5. Risks

- **Stage-1 NO-GO** is a real possibility — that's *why* stage 1 is the gate. If
  the α/β feedback recurrence ACS (sat_add → maxstar → normalize) is itself
  ~50-60 ns, neither 2a nor 2b clears 1.5× and we shelve. This is acceptable: the
  probe already de-risked the *direction*, and a documented NO-GO is a valid
  outcome (cf. M2).
- **EXACT_LOGMAP divergence** if the tree is applied in exact mode — mitigated by
  gating 2a on `EXACT_LOGMAP=false`.
- **Modulo-norm wrap miscompare** if 2b uses modulo without a spread proof —
  mitigated by preferring anchor normalization first.
