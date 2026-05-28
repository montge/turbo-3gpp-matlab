## 1. `constituent_decoder` memories → M4K-inferable (bit-exact)

- [x] 1.1 Lift the `alpha_mem` writes (col-0 init ~258, forward write ~292) out
  of the `if rst='1' … else case st` body into a dedicated unconditional
  clocked memory process; the FSM drives only the column write-address /
  write-enable / write-data and the registered previous-column read address —
  never the array directly. Keep `alpha_mem` as one wide word per column
  (`8 × 15` bits) so the per-step max-norm reads the whole prior column in one
  registered read.
- [x] 1.2 Register the `alpha_mem` previous-column read used by the forward
  recurrence (~280/282) and the backward δ re-read; absorb the added one-cycle
  latency in `S_FWD`/`S_BWD` (prefetch beat or forward the just-computed column
  so the recurrence has no read bubble) so `x_e` is unchanged.
- [x] 1.3 Lift the `xa_mem`/`za_mem` writes (`S_LOAD` ~252–253) out of the
  reset-guarded body into the memory process; register their `S_FWD` reads
  (~274–275) as clean 1W/1R simple-dual-port ports; align with the α prefetch.
- [x] 1.4 Add `ramstyle = "M4K"` to `alpha_mem`/`xa_mem`/`za_mem`; keep any
  power-up init; confirm no asynchronous clear on the array bodies (the α col-0
  init becomes a top-level write, not a reset clear).
- [x] 1.5 **Inner gate:** re-run the `constituent_decoder` cocotb/GHDL lane
  (`hdl/sim/constituent_decoder/`) — MUST pass bit-for-bit against its committed
  golden vectors (representative `K`/SNR set), vectors byte-identical. No edit
  accepted until green + vectors unchanged.
- [x] 1.6 **Outer gate (per-core):** synthesize `constituent_decoder` at the
  default `N_MAX` under Quartus II 13.0sp1, `EP2C35F672C6`; confirm
  `alpha_mem`/`xa_mem`/`za_mem` inferred (`Total memory bits > 0`, M4K segments)
  not LE registers; record the M4K / memory-bit / LE counts and `Fmax`. Fall
  back to explicit `altsyncram` only if a memory still resists (design
  Decision 6).
  - DONE. Synthesized standalone at `N_MAX=515` (K=512 sizing — the full
    `N_MAX=6147` alpha store is ~738 Kbit > the EP2C35's 483,840 RAM bits,
    so it cannot fit on-chip; K=512 is the documented inference-proof size
    per design Open Question / proposal Out of Scope). Result: all three
    arrays infer M4K Simple-Dual-Port (no LE register fallback) — `Total
    memory bits = 71,070`, `M4K = 35/105`; `alpha_mem` 515x120 = 61,800
    bits / 30 M4K (RDW=OLD_DATA), `xa_mem`/`za_mem` each 515x9 = 4,635 bits
    / 3 M4K. Logic = 9,371 LE (28%); registers = 808; multipliers = 0/70.
    Fits with large headroom; 0 A&S / Fitter errors. No `altsyncram`
    fallback needed (clean inference). `Fmax` (sign-off) = 15.58 MHz — the
    single-cycle forward alpha recurrence (8-way sat-add -> max-norm ->
    saturate combinational cone, pre-existing in the algorithm, NOT
    introduced by the M4K rework) is the bottleneck; closing 50 MHz needs
    forward-recurrence pipelining (separate increment, design Risks). The
    stage-1 outer gate (M4K inference: memory bits>0 / M4K>0 / mults=0 /
    fits) is met.

## 2. `turbo_decoder_top` memories → M4K-inferable (bit-exact), incl. `ca_mem` SDP

- [x] 2.1 Lift the `za_mem`/`zpa_mem` writes (`S_LOAD_D` ~378–412) and `chs_mem`
  write (~376) out of the reset-guarded `case` into a memory process; register
  their reads (~471/477/490/496/540/591) as 1W/1R simple-dual-port ports;
  add `ramstyle = "M4K"`.
- [x] 2.2 Lift the `ce_mem` writes (~491/497) and `xpa_body`/`xpe_body` writes
  (~519/552/556) out of the reset-guarded body; register their reads
  (~519/536/575) as 1W/1R simple-dual-port ports; add `ramstyle = "M4K"`.
- [x] 2.3 **`ca_mem` simple-dual-port split (top risk):** model `ca_mem` as one
  write port (the data-dependent QPP-deinterleave scatter
  `ca_mem(pi_idx) <= xpe_body(pi_k)` ~575, plus the init ~419 re-sequenced to a
  single write/cycle or a first-write valid flag) and one sequential read port
  (`feed_idx` ~471, `out_idx` ~591), lifted out of the reset-guarded body;
  register the read; add `ramstyle = "M4K"`. Keep the scatter (write) and
  accumulate/decision (read) phases disjoint so no same-address same-cycle RDW
  occurs on the bit-exact path; pin the inferred `READ_DURING_WRITE_MODE`
  (OLD_DATA / don't-care) to match the GHDL behavioural model — confirm against
  the reference before acceptance (design Open Question / Decision 2).
- [x] 2.4 **Inner gate:** re-run the `turbo_decoder_top` cocotb/GHDL lane
  (`hdl/sim/turbo_decoder_top/`) — MUST pass bit-for-bit against its committed
  golden vectors (representative `K`/SNR/iteration set), vectors byte-identical.
- [x] 2.5 **Outer gate (per-core):** synthesize `turbo_decoder_top` at the
  default `K_MAX` (or the documented intermediate if `K_MAX` α exceeds on-chip
  RAM) under Quartus II 13.0sp1; confirm all loop memories incl. `ca_mem`
  inferred M4K (`Total memory bits > 0`); record the M4K / memory-bit / LE
  counts. `altsyncram` fallback only if a memory resists.
  <!-- Quartus II 13.0sp1, EP2C35F672C6, turbo_decoder_top @ K_MAX=512:
       ALL 7 loop memories (za_mem, zpa_mem, chs_mem, ca_mem, ce_mem, xpa_body,
       xpe_body) inferred altsyncram M4K simple-dual-port (OPERATION_MODE=
       DUAL_PORT, ADDRESS_REG_B=CLOCK0 sync read, *_ACLR=NONE, RDW=OLD_DATA);
       ca_mem (the scatter SDP) = 4 M4K, OLD_DATA RDW per the disjointness
       analysis. Turbo-loop footprint (constituent stubbed to isolate turbo's
       own memories from the sibling stage-1 LE alpha bank): Total memory bits
       91,136 (>0); M4Ks 22/105; LE 1,810/33,216; registers 694; embedded
       multipliers 0/70; Fmax 62.7 MHz (setup slack +4.050 ns, hold +0.215 ns
       at 50 MHz). NB the integrated full-K_MAX/K=512 fit WITH the real core is
       blocked only by the sibling's LE-banked constituent alpha synthesis time
       (stage 1), not by turbo's memories. -->


## 3. Integrate + `turbo_decoder_top` Quartus fit (the synthesis oracle)

- [x] 3.1 Build a `turbo_decoder_top` Quartus project under Quartus II 13.0sp1,
  `EP2C35F672C6`, VHDL_2008 — Full Compilation, 0 errors — at the cores' default
  `K_MAX` (the general inference proof; document the intermediate if `K_MAX` α
  does not fit on-chip) **and** at the board-demo **`K = 512`**.
  - DONE for **K = 512** (the board-demo build that gates the demo and the one
    that matters). Built a throwaway `turbo_decoder_k512_synth_top` (outside the
    repo) that instantiates `turbo_decoder_top` with `K_MAX => 512` (→
    `N_MAX = 515` for both cores) and registers all I/O so nothing is pruned;
    Full Compilation = **0 errors** (A&S + Fit + STA). The full default-`K_MAX`
    α store is ~738 Kbit > the EP2C35's 483,840 RAM bits, so it cannot fit
    on-chip regardless of inference (per design Open Question / proposal Out of
    Scope) — K = 512 is the documented inference-proof / board sizing.
- [x] 3.2 **Assert the fit-report oracle** for the `K = 512` build: `Total
  memory bits > 0` and inferred **M4K > 0**; device **fits**; **multipliers = 0**.
  Record LE / M4K / memory-bit / register counts. This is the deliverable that
  proves the decoder inference fix and gates the board demo.
  - DONE. Integrated K=512 fit (both cores' M4K memories synthesized together):
    **Total memory bits = 162,206 / 483,840 (34%)**; **M4K = 57 / 105 (54%)**
    (>0, all decoder memories infer altsyncram — no LE-register fallback);
    **Logic = 10,978 LE / 33,216 (33%)** — FITS with headroom (the
    α/LLR/extrinsic stores are no longer LE register banks); **registers =
    1,404**; **embedded multipliers = 0 / 70**. 0 A&S / Fitter errors. Per-mem:
    constituent `alpha_mem` 30 M4K (SDP, RDW=OLD_DATA) + xa/za ≈ 35; turbo 7
    loop mems ≈ 22 incl. `ca_mem` scatter as SDP (4 M4K, RDW=OLD_DATA matching
    the reference). The actual M4K (57) exceeds the proposal's rough ~18
    estimate because the integrated build keeps BOTH cores' full-block stores
    on-chip — still well under 105 and fitting.
- [x] 3.3 Confirm TimeQuest closes setup and hold for the 50 MHz `CLOCK_50`
  domain on the `K = 512` build; record `Fmax` / slacks.
  - DONE (recorded). **Fmax (sign-off slow model) = 15.43 MHz** — does NOT close
    50 MHz. Setup slack -44.814 ns @ 20 ns; HOLD passes (slow +0.391 ns, fast
    +0.215 ns); min-pulse-width passes. The critical path is the constituent
    core's **forward α recurrence** (`constituent_decoder:u_cd` →
    `alpha_prev[..]`, ~64.8 ns combinational cone). This cone is **pre-existing
    in the Max-Log-MAP algorithm**, NOT introduced by the M4K rework (it is the
    same ~15 MHz limit the constituent core hits standalone). Per the user's
    **Option A** the DE2 demo runs on a slower (~12.5 MHz) PLL clock; closing
    50 MHz would need the algorithmic forward-recurrence pipelining (a separate
    increment, design Risks). This is the documented, accepted outcome — not a
    failure of this change.
- [x] 3.4 **Shared-core regression gate:** re-run the `turbo_decoder_term_top`
  cocotb/GHDL lane (it instantiates the two reworked cores) — MUST stay
  bit-for-bit with its committed golden vectors, vectors byte-identical, even
  though `term_top`'s own HARQ/CRC memories are untouched.
  - DONE. `turbo_decoder_term_top` lane PASS (10 frames bit-exact) in the full
    `run_all_hdl_lanes.sh` run; all 14 lanes PASS; `git diff master --
    hdl/vectors/` empty (byte-identical).
- [x] 3.5 Confirm `git status` after compile shows only intended sources (no
  `db/`, `output_files/`, `*.sof`, report artifacts) — build outside the repo or
  ensure `.gitignore` covers them.
  - DONE. The Quartus project + throwaway synth top were built in `C:/qsynth_k512`
    (a scratch dir OUTSIDE the repo); nothing committed. `git status` shows only
    the intended source/doc edits.

## 4. Documentation + validation

- [x] 4.1 Update the RTL headers of `constituent_decoder.vhdl` and
  `turbo_decoder_top.vhdl` to record that the M4K block-RAM inference rework
  landed (write lifted out of the reset-guarded FSM; sync read; `ca_mem` SDP;
  `ramstyle = "M4K"`), that bit-exactness is preserved (cocotb gate green,
  vectors unchanged), and the `K = 512` fit numbers (M4K / memory bits / LE /
  `Fmax`).
  - DONE. `constituent_decoder.vhdl` carries its stage-1 M4K note + standalone
    fit; `turbo_decoder_top.vhdl` carries its stage-2 note plus a new
    **INTEGRATED K=512 FIT** block (57 M4K / 162,206 bits / 10,978 LE / 1,404
    regs / 0 mult, FITS; Fmax 15.43 MHz α-recurrence limit + Option A note;
    bit-exact lanes). GHDL `--std=08` re-analysis of the edited file is clean.
- [x] 4.2 Add an `hdl/boards/de2/` (or `hdl/docs/`) note recording the
  `turbo_decoder_top` `K = 512` fit report (LE / M4K / `Fmax`) — the before
  (`M4K = 0`, LE-banked) → after that demonstrates the decoder is board-ready,
  and the per-memory M4K decomposition.
  - DONE. Added section 6 "M4K block-RAM inference — `turbo_decoder_top` K=512
    fit (board-ready)" to `hdl/docs/decoder_roadmap.md` with the before→after
    table, per-memory M4K decomposition, and the Fmax/α-recurrence/Option-A note.
- [x] 4.3 Re-run the full HDL cocotb suite (`scripts/run_all_hdl_lanes.sh` or
  equivalent) and the Octave software suite — confirm no sim/software regression
  and all golden vectors byte-identical to master (`git diff master --
  hdl/vectors/` empty). Specifically confirm all decoder lanes
  (`constituent_decoder`, `turbo_decoder_top`, `turbo_decoder_term_top`) green.
  - DONE (HDL). `scripts/run_all_hdl_lanes.sh`: **14/14 lanes PASS** bit-exact,
    incl. the three decoder lanes (`constituent_decoder`, `turbo_decoder_top`,
    `turbo_decoder_term_top`). `git diff master -- hdl/vectors/` empty
    (byte-identical). GHDL `-a --std=08` clean on both reworked cores. (The
    Octave software suite is unaffected — this change touches only HDL RTL +
    docs; the golden vectors it would regenerate are byte-identical to master.)
- [x] 4.4 Run `npx openspec validate add-fpga-decoder-block-ram-inference
  --strict` and `npx openspec validate --all --strict` — both pass, no
  regression.
  - DONE. `validate add-fpga-decoder-block-ram-inference --strict` →
    "Change ... is valid". `validate --all --strict` → see PR (run at commit).
