# Tasks — add-fpga-decoder-recurrence-pipelining (bounded throughput)

Re-scoped 2026-05-27 after an Fmax probe (see `design.md` §0): anchor
normalization alone moved Fmax 14.25 → 14.2 MHz (no gain) because the `S_BWD`
feed-forward δ→x_e fold co-limits at ~70 ns alongside the α/β recurrence. Scope
is now a **measurement-gated bounded throughput win**, not 50 MHz. Stage 1 is a
GO/NO-GO synthesis gate (the M2 discipline). Two-tier verification per
`decoder_roadmap.md`; the board's Max-Log-MAP mode is output-bit-exact in the
common case (no new reference).

## 1. Stage-1 GO/NO-GO Fmax probe

- [x] 1.1 Add a **balanced-tree extrinsic fold** in `constituent_decoder` `S_BWD`
  behind a generic defaulting to the current serial fold; gate the tree ON only
  for `EXACT_LOGMAP=false` (plain `max` is associative → bit-exact), keeping the
  pinned serial seed-from-first order for exact mode.
  (Generic `BAL_TREE_FOLD : boolean := false`; effective predicate
  `BAL_TREE_FOLD and not EXACT_LOGMAP`; `tree_max8` balanced 3-level max-tree.
  Default + enabled both bit-exact vs golden vectors; threaded into
  turbo_decoder_top.)
- [x] 1.2 Add **cheaper recurrence normalization** (anchor first; modulo only
  with a width-spread proof) behind a generic defaulting to the current 8-way
  max-normalization, in both `S_FWD` (α) and `S_BWD` (β).
  (Generic `ANCHOR_NORM : boolean := false`; true → subtract state-1 anchor
  instead of the 8-way max in both α and β. Output-equivalent: x_e / decoded
  bits identical with both opts enabled across all four lanes; threaded into
  turbo_decoder_top.)
- [x] 1.1c (stage 1c) **Pipeline the `S_BWD` feed-forward δ-fold** one stage
  behind a generic defaulting to the current single-cycle path (design.md §2c;
  the probe showed this lifts Fmax 19.14 → 26.31 MHz, the δ-fold being the
  limiter). Generic `PIPE_DFOLD : boolean := false`; true → STAGE A registers
  the gathered d0/d1 deltas (+ valid/last flags), STAGE B reduces them and
  emits x_e one cycle later; a one-cycle `S_BWD_DRAIN` state emits the final
  (column-0) beat. Pure +1-cycle x_e LATENCY change — decoded x_e VALUES
  identical, exactly N=K+3 beats, out_last on column 0 unchanged → golden
  vectors byte-identical. Threaded into turbo_decoder_top (the reverse-stream
  capture down-counter is transparent to the uniform +1 latency). VERIFIED:
  constituent_decoder lane (27/27) + turbo_decoder_top lane (10+10 frames, both
  MAX_ITER groups) PASS with `-gPIPE_DFOLD=true` AND with all three levers
  (`PIPE_DFOLD+ANCHOR_NORM+BAL_TREE_FOLD`) enabled, against the SAME golden
  vectors; default path byte-identical (all four lanes green).
- [x] 1.3 Synthesize `turbo_decoder_top` (board K) under Quartus II 13.0sp1 with
  the optimizations enabled; **record restricted Fmax + the new worst-case path**.
  RESULT (`turbo_decoder_de2`, all three levers on): restricted Fmax **27.63 MHz**
  (vs 14.25 baseline = **1.94×**); LE **11,164** (vs 12,759 baseline — LOWER,
  anchor-norm drops the 8-way max-tree); M4K 162,206 bits unchanged. Worst path is
  the δ-fold stage-B (`d1_r → tree → sat_sub → xe_r`); the α/β recurrence is no
  longer the limiter. (Intermediate probes: anchor+tree only = 19.14 MHz;
  off-by-one δ-pipe probe = 26.31 MHz.)
- [x] 1.4 **GATE: GO.** 1.94× ≥ 1.5× — proceed to stages 2/3.

## 2. Bit-exactness (post-GO)

- [ ] 2.1 Enable the winning combination by default for Max-Log-MAP mode; re-run
  the `constituent_decoder`, `turbo_decoder_top`, `turbo_decoder_term_top`, and
  `constituent_decoder_logmap` cocotb lanes — all green.
- [ ] 2.2 Confirm `hdl/vectors/*` byte-identical. Regenerate a reference + vectors
  ONLY if design.md §3 (i) exact-mode re-association, (ii) internally-checked
  normalization, or (iii) fold-pipeline latency forces it; if so, characterize
  unchanged BER vs float.

## 3. Integrate + fit at the measured clock (post-GO)

- [x] 3.1 Decoder lanes green with the levers enabled (constituent_decoder
  27/27, turbo_decoder_top 10+10 both MAX_ITER groups, all bit-exact vs the SAME
  golden vectors) + the DE2 self-check lane PASS on the ÷2 sim PLL with all three
  levers on; `hdl/vectors/*` byte-identical. (Stage 1/1c already regressed the
  full decoder + TX suites on the merged RTL.)
- [x] 3.2 Quartus II 13.0sp1 fit `turbo_decoder_de2` at **25 MHz** (new ÷2 PLL
  `pll_25`, replacing the ÷4 `pll_12p5`). Timing CLOSES: worst setup slack
  **+9.899 ns** @ 40 ns, restricted Fmax **33.22 MHz**. LE **11,194** (vs 12,759
  @ 12.5 MHz baseline — lower), M4K 162,206 bits unchanged, 1 PLL. `.sof`
  produced. Self-check + LCD demo unchanged; only the PLL ratio + the three
  lever generics moved.
- [ ] 3.3 On-board re-confirm (HARDWARE-GATED — user's board): the existing
  `PASS e=000 it=2` decoder self-check still passes at the faster 25 MHz clock.

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-decoder-recurrence-pipelining --strict`
  and `npx openspec validate --all --strict` pass.
