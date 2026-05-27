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
- [ ] 1.2 Generate golden vectors from the new reference (the Max-Log-MAP
  vectors do not carry over); document the new bit-exact contract.
- [x] 1.3 Outer characterization: bounded BER-vs-SNR vs float `turbo_decoder.m`,
  showing the recovered Max-Log-MAP gap within a documented dB margin.
  DONE: `scripts/characterize_exact_log_map.m`. Result (K=512, max_iter=8):
  fixed-point exact Log-MAP recovers **0.192 dB** over fixed-point Max-Log-MAP at
  BER=1e-2, within **0.310 dB** of the float-exact bound (band: gain ≥ -0.10 dB,
  gap ≤ 0.75 dB → PASS). K=40 short block does not bracket 1e-2 on the grid (N/A,
  informational). `selftest_logmap_reference.m` confirms the Max-Log-MAP superset.

## 2. HDL exact-Log-MAP

- [ ] 2.1 Add the `max*` correction LUT to the α/β recurrence and extrinsic
  paths; add the extrinsic scaling factor.
- [ ] 2.2 cocotb inner gate: HDL bit-exact to the new reference over the K set.

## 3. Fit + regression

- [ ] 3.1 Quartus II 13.0sp1 fit on the EP2C35; record LE / M4K and any Fmax
  delta from the added LUT depth.
- [ ] 3.2 Full regression green (all TX lanes + decoder lanes + Octave).

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-decoder-exact-log-map --strict` and
  `npx openspec validate --all --strict` pass.
