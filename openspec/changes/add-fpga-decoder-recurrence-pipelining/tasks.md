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
- [ ] 1.3 Synthesize `turbo_decoder_top` (board K) under Quartus II 13.0sp1 with
  the optimizations enabled; **record restricted Fmax + the new worst-case path**.
- [ ] 1.4 **GATE:** proceed only if Fmax ≥ ~1.5× the 14.25 MHz baseline
  (≈ ≥ 22 MHz). If NO-GO, record the finding in `decoder_roadmap.md`, mark this
  change shelved (M2-style), and stop after task 4.1.

## 2. Bit-exactness (post-GO)

- [ ] 2.1 Enable the winning combination by default for Max-Log-MAP mode; re-run
  the `constituent_decoder`, `turbo_decoder_top`, `turbo_decoder_term_top`, and
  `constituent_decoder_logmap` cocotb lanes — all green.
- [ ] 2.2 Confirm `hdl/vectors/*` byte-identical. Regenerate a reference + vectors
  ONLY if design.md §3 (i) exact-mode re-association, (ii) internally-checked
  normalization, or (iii) fold-pipeline latency forces it; if so, characterize
  unchanged BER vs float.

## 3. Integrate + fit at the measured clock (post-GO)

- [ ] 3.1 Full regression: all TX lanes + decoder lanes + the Octave suite green.
- [ ] 3.2 Quartus II 13.0sp1 fit `turbo_decoder_de2` at the highest PLL the
  stage-1 Fmax supports (e.g. 25 MHz); record Fmax / LE / M4K vs the 12.5 MHz
  baseline. Self-check + LCD demo unchanged; only the PLL ratio moves.
- [ ] 3.3 On-board re-confirm (HARDWARE-GATED — user's board): the existing
  `PASS e=000 it=2` decoder self-check still passes at the faster clock.

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-decoder-recurrence-pipelining --strict`
  and `npx openspec validate --all --strict` pass.
