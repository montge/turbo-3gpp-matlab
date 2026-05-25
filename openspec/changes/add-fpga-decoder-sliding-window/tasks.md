## Tasks — add-fpga-decoder-sliding-window (RE-SCOPED)

This change is **re-scoped after a negative fit result**: α windowing delivers
0 M4K in `turbo_decoder_top` and cannot make K = 6144 fit; the QPP-globally-permuted
loop LLR memories + K-deep input buffers are the real wall (~264 + ~78 M4K at
K = 6144), and they cannot be on-chip-windowed. The deliverable is the **honest
analysis + recommendation** (design.md), plus a **staged, UNCHECKED** plan for the
only realistic full-K route (external SRAM). **No code lands in this change.**

The stage-1 reference work (`#73`) — `scripts/fixedpoint_constituent_decoder_sw.m`
+ `scripts/characterize_sliding_window.m`, `W = 64`, `L = 48` — is **retained as a
shelved, validated artifact** (see §6), not extended here.

## 1. Record the negative finding + re-detail the design (this change)

- [ ] 1.1 Record the **negative fit finding** in design.md §1: windowed-α
  (`WINDOW_LEN = 64`) vs full-block (`WINDOW_LEN = 6147`) `turbo_decoder_top` both
  fit at the identical ~61/105 M4K; K = 6144 does not fit. State that α is **not**
  the binding M4K constraint.
- [ ] 1.2 Resolve the **WINDOW_LEN-propagation** question in design.md §2: confirm
  **no `WINDOW_LEN`/`ACQ_LEN` generic exists in any HDL** (the windowed HDL was
  never written; `alpha_mem` depth is `N_MAX`-driven), so the 61 = 61 result is
  **genuine, not a non-propagation artifact**.
- [ ] 1.3 Quantify the **loop-LLR-memory wall** in design.md §3: per-memory M4K at
  K = 512 / K = 6144 (calibrated to `ca_mem = 4 M4K`), the ~264-M4K loop total at
  K = 6144, and the **on-chip maximum K** (≈ 1008 full-block; ≈ 1536 windowed-α).
- [ ] 1.4 State the **interleaver-global-access constraint** in design.md §4: the
  QPP gather/scatter (`c_e[π[k]]` / `c_a[π[k]]`) spans the whole K-bit block, so
  the loop LLR arrays need full random access each half-iteration and **cannot be
  on-chip-windowed/streamed** the way α was.
- [ ] 1.5 Record the **external-SRAM/SDRAM feasibility verdict** in design.md §5:
  the ~73 KB working set fits the 512 KB async SRAM at ≈ 1× latency; SDRAM is
  bandwidth-OK but random-latency-hostile (~3–5×) and controller-heavy — **SRAM is
  the target, not SDRAM**.
- [ ] 1.6 Record the **recommendation** in design.md §6 + Recommendation: shelve
  windowed-α as a board M4K lever (keep the Octave reference), accept the on-chip
  K ≤ 1008 cap, and pursue full-K only as the distinct staged external-SRAM
  increment below.
- [ ] 1.7 `npx openspec validate add-fpga-decoder-sliding-window --strict` and
  `npx openspec validate --all --strict` pass.

## 2. Shelve windowed-α cleanly (documentation only, this change)

- [ ] 2.1 Document in `hdl/docs/decoder_roadmap.md` (M2 section) that α windowing
  is **shelved as a `turbo_decoder_top` M4K lever** (0 M4K benefit; wall is the
  loop/input memories), the **windowed Octave reference is retained** as a
  validated artifact reusable for the constituent-standalone on-chip-K lift
  (≈ 1016 → ≈ 1536) and a future ASIC/larger-FPGA, and the windowed **HDL (the
  former task 3.1) is NOT implemented**. *(Doc edit; performed when this change is
  applied, not in the design-only PR.)*

## 3. (CONDITIONAL) External-SRAM full-K increment — staged, only if full-K is required

> These tasks belong to a **distinct future change**
> (`add-fpga-decoder-external-loop-mem`). They are listed here UNCHECKED as the
> staged plan the recommendation points to. **Do not start unless a full K = 6144
> board demo is a hard requirement** — otherwise the on-chip K ≤ 1008 cap stands.

- [ ] 3.1 **Async-SRAM controller** for the DE2 `SRAM_*` (256K × 16, ~10 ns):
  read/write port, address mux, the SDC/QSF pinout. Bit-exact behavioural model
  for cocotb.
- [ ] 3.2 **Move ONE loop array off-chip** (start with `ce_mem` — the QPP gather
  source) to external SRAM behind the controller; keep all others on-chip; re-run
  the `turbo_decoder_top` cocotb lane bit-exact (proves the external-access
  rework preserves the contract).
- [ ] 3.3 **Move the remaining loop LLR arrays** (`ca_mem`, `chs_mem`, `za_mem`,
  `zpa_mem`, `xpa_body`, `xpe_body`) off-chip with a shared SRAM arbiter; verify
  the per-step access count fits the core-cycle budget at the chosen clock; cocotb
  bit-exact.
- [ ] 3.4 **Move the constituent K-deep input buffers** (`xa_mem` / `za_mem`)
  off-chip (or confirm they fit on-chip at the target K); cocotb bit-exact.
- [ ] 3.5 **Quartus II 13.0sp1 fit at K = 6144** of the external-SRAM
  `turbo_decoder_top`: confirm on-chip M4K is now well under 105 (loop/input
  arrays in SRAM, only working windows on-chip), 0 A&S/Fitter errors, and record
  the SRAM access-latency vs decode-budget measurement.
- [ ] 3.6 (Optional) **Wire windowed-α into the constituent** for the
  on-chip-max-K lift to ≈ 1536, reusing the retained Octave reference and its
  pinned `W = 64 / L = 48` — independent of the external-SRAM work.
