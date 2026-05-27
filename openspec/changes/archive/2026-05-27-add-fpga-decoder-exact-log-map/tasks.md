## Tasks — add-fpga-decoder-exact-log-map

High-level STAGE skeleton (stub). Two-tier gate per `decoder_roadmap.md`:
inner cocotb bit-exact vs the new exact-Log-MAP fixed-point reference + outer
bounded BER-vs-SNR vs float, plus a Quartus II 13.0sp1 fit gate.

## 1. Exact-Log-MAP fixed-point reference + characterization

- [x] 1.1 Author the Octave exact-Log-MAP reference: `max*(a,b) = max(a,b) +
  f(|a−b|)` with a quantized correction LUT, plus the extrinsic scaling factor.
  DONE: `scripts/fixedpoint_constituent_decoder_logmap.m` (+ a windowed/loop
  wrapper in the characterization). Self-test PASS — with the correction LUT ≡ 0
  it is BYTE-EXACT to `fixedpoint_constituent_decoder.m` (Max-Log-MAP superset).
- [x] 1.2 Generate golden vectors from the new reference (the Max-Log-MAP
  vectors do not carry over); document the new bit-exact contract.
  DONE: `scripts/generate_hdl_constituent_decoder_logmap_vectors.m` ->
  `hdl/vectors/constituent_decoder_logmap.csv` (27 rows, K in {40,512,6144} x
  SNR {0,2,4} dB x 3 frames). Schema `K,x_a,z_a,x_e` (W_in=9 inputs, W_xe=18
  expected extrinsics). Mirrors the Max-Log-MAP generator frame-for-frame
  (same seed => x_a/z_a byte-identical to constituent_decoder.csv); x_e comes
  from `fixedpoint_constituent_decoder_logmap.m` in EXACT mode (LUT on) and
  differs in all 27 rows. Idempotent (run twice = byte-identical) and
  round-trips (reload x_a/z_a + re-run the exact reference reproduces x_e).
  The stage-4 exact-mode cocotb lane consumes this CSV.
- [x] 1.3 Outer characterization: bounded BER-vs-SNR vs float `turbo_decoder.m`,
  showing the recovered Max-Log-MAP gap within a documented dB margin.
  DONE: `scripts/characterize_exact_log_map.m`. Result (K=512, max_iter=8):
  fixed-point exact Log-MAP recovers **0.192 dB** over fixed-point Max-Log-MAP at
  BER=1e-2, within **0.310 dB** of the float-exact bound (band: gain ≥ -0.10 dB,
  gap ≤ 0.75 dB → PASS). K=40 short block does not bracket 1e-2 on the grid (N/A,
  informational). `selftest_logmap_reference.m` confirms the Max-Log-MAP superset.

## 2. HDL exact-Log-MAP

- [x] 2.1 Add the `max*` correction LUT to the α/β recurrence and extrinsic
  paths behind an `EXACT_LOGMAP` generic (default `false` = Max-Log-MAP, the
  bit-exact superset). DONE: `hdl/rtl/constituent_decoder.vhdl` — generic
  `EXACT_LOGMAP : boolean := false` + the pinned 56-entry `CORR_LUT` ROM (logic,
  no M4K) + a `maxstar(a,b)` function applied at every 2-way α/β max and each
  2-way node of the two extrinsic δ left-folds (seed-from-first-δ, ascending
  transition index per design.md §4); per-step max-norm and the final
  `sat_sub(log_p0,log_p1)` stay plain (design.md §2). Default mode is bit-exact
  (all lanes green, vectors byte-identical); `EXACT_LOGMAP=true` is bit-exact to
  `scripts/fixedpoint_constituent_decoder_logmap.m` on a sample frame. The
  extrinsic scaling factor is reserved (omitted in v1; design.md §6). The
  dedicated exact-mode cocotb lane (task 2.2) + Quartus fit (task 3.1) are
  stage 4.
- [x] 2.2 cocotb inner gate: HDL bit-exact to the new reference over the K set.
  DONE: `hdl/sim/constituent_decoder_logmap/` (Makefile + cocotb test) mirrors
  the P1 `hdl/sim/constituent_decoder/` lane but elaborates the SAME core with
  the boolean generic override `-gEXACT_LOGMAP=true` (GHDL `-g<NAME>=true`, the
  same `-g` mechanism the turbo_decoder_top/*_de2 lanes use). Per row it drives
  `(x_a,z_a)`, collects the reverse-streamed `x_e`, un-reverses, and asserts
  bit-exact vs `hdl/vectors/constituent_decoder_logmap.csv`: 27/27 frames
  (K in {40,512,6144}) bit-exact. The P1 default-mode lane (EXACT_LOGMAP=false)
  still passes unchanged — the Max-Log-MAP superset holds.

## 3. Fit + regression

- [x] 3.1 Quartus II 13.0sp1 fit on the EP2C35; record LE / M4K and any Fmax
  delta from the added LUT depth. DONE: `constituent_decoder` standalone @ K≈512,
  EP2C35F672C6 — `EXACT_LOGMAP=true`: **LE 13,397 (40%), M4K 35/105 (33%),
  0 multipliers**. Baseline (`EXACT_LOGMAP=false`, Max-Log-MAP): 9,371 LE, 35 M4K,
  0 mult. So the `max*` LUT+adders cost **≈ +4,000 LE (~+12% of device) but 0 M4K
  and 0 DSP** — exact mode is a pure-logic addition (no memory/multiplier
  pressure, important vs the tight M4K budget), and default mode is unchanged
  (the LUT/adder constant-fold away). Fits comfortably (40% LE standalone).
- [x] 3.2 Full regression green (all TX lanes + decoder lanes + Octave).
  DONE: `scripts/run_all_hdl_lanes.sh` -> 19/19 lanes PASS (the new exact lane +
  all prior lanes at their defaults). `hdl/vectors/*` byte-identical vs master
  except the ADDED `constituent_decoder_logmap.csv`.

## 4. Validate

- [x] 4.1 `npx openspec validate add-fpga-decoder-exact-log-map --strict` and
  `npx openspec validate --all --strict` pass.
  DONE: both pass (change valid; --all 34 passed, 0 failed).
