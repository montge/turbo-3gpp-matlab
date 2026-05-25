## Tasks — add-fpga-decoder-sliding-window

Two-tier gate per `decoder_roadmap.md`: inner cocotb bit-exact vs the **new**
sliding-window fixed-point reference; outer windowing-loss band
(windowed-vs-full-block, constituent + loop BER) and the preserved float-vs-fp
margins; plus a Quartus II 13.0sp1 fit gate showing the M4K drop and the full
K = 6144 fit.

## 1. Sliding-window fixed-point reference + characterization

- [x] 1.1 Author the windowed fixed-point reference
  (`scripts/fixedpoint_constituent_decoder_sw.m`, or a `WINDOW_LEN`/`L`-windowed
  mode of `fixedpoint_constituent_decoder.m`): per-window α from checkpoints + β
  with an `L`-step flat-init acquisition warm-up, emitting in-window extrinsics.
  Reuse the P1 arithmetic UNCHANGED (per-step max-norm, saturation, ±inf
  sentinel, pinned widths). The terminal window uses the true terminated-state β
  init; interior windows use the flat acquisition init.
- [x] 1.2 Constituent windowing-loss characterization
  (`scripts/characterize_constituent_decoder_sw.m`, or extend the existing one):
  windowed-vs-full-block fixed-point extrinsic-LLR error (max/RMS) + hard-decision
  agreement on systematic bits, over a bounded {K, SNR} × (W, L) grid. **Pin the
  `W`/`L` defaults** from the curve (design.md §3 prototype: W ∈ {64,128},
  L = 32 is the recommended default; L = 48 is bit-exact). Pin the
  windowing-loss band ~1.5× above the worst observed cell (the P1 discipline).
- [x] 1.3 Loop-level windowing-loss characterization (extend
  `characterize_turbo_decoder.m`): bounded BER-vs-SNR of the windowed-core turbo
  decoder vs the full-block-core turbo decoder and vs float `turbo_decoder.m`,
  confirming windowing loss ≲ 0.1–0.2 dB within the documented band and that the
  existing P1/P2 float-vs-fp margins still hold.

## 2. Golden-vector generator

- [ ] 2.1 Add/extend the golden-vector generator to emit the **new** windowed
  reference's vectors (the full-block vectors do not carry over). Cover the
  representative K set and a few SNRs at the pinned `W`/`L`; keep large-K cases
  few (cycle budget, roadmap §2). Document the new bit-exact contract.

## 3. HDL: window the constituent_decoder α/β

- [ ] 3.1 Replace the full-block `alpha_mem` (`8 × (K+3)`) with a windowed α
  store (`≈ 8 × W`) plus a boundary-state checkpoint store; rework the
  forward/backward scheduling so α is recomputed per window from the nearest
  checkpoint and β runs an `L`-step acquisition warm-up before each window emit.
  Ideally behind a `WINDOW_LEN` generic with `WINDOW_LEN ≥ K+3` collapsing to the
  existing full-block path (windowed core = strict superset). Keep the streaming
  interface (ports, load/output cadence) UNCHANGED; preserve the M4K-inference
  structure (write lifted out of the reset/case body, registered reads,
  `ramstyle = "M4K"`).
- [ ] 3.2 cocotb inner gate: `constituent_decoder` HDL bit-exact to the new
  windowed reference over the K set at the pinned `W`/`L`.

## 4. Regression: turbo / rx lanes with the windowed core

- [ ] 4.1 Regenerate `turbo_decoder_top` / `turbo_decoder_term_top` /
  `rx_chain_top` golden vectors from the windowed-core references and re-run their
  cocotb lanes green (the windowed constituent feeds the iterative loop unmodified
  at the interface).
- [ ] 4.2 Full regression green (all TX lanes + decoder lanes + Octave
  characterizations within their bands).

## 5. Quartus fit: M4K drop + full K = 6144 fit

- [ ] 5.1 Quartus II 13.0sp1 fit of the **full K = 6144** constituent /
  `turbo_decoder_top` / `rx_chain_top` path on the EP2C35F672C6 (the memory that
  previously did not fit); record LE / M4K / registers / DSP / Fmax, 0 A&S /
  Fitter errors.
- [ ] 5.2 Quartus fit at K = 512 showing the M4K count dropped materially below
  the full-block baseline (constituent 35 → ~`ceil(W/34)`-driven; `rx_chain_top`
  96/105 → headroom restored); record the before/after M4K delta.

## 6. Docs + validate

- [ ] 6.1 Update `hdl/docs/decoder_roadmap.md` (M2 done), the constituent sim
  README, and the relevant fit-note headers with the windowed α/β architecture,
  the pinned `W`/`L`, and the recorded fit numbers.
- [ ] 6.2 `npx openspec validate add-fpga-decoder-sliding-window --strict` and
  `npx openspec validate --all --strict` pass.
