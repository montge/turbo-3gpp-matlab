## Tasks — add-fpga-decoder-exact-log-map

High-level STAGE skeleton (stub). Two-tier gate per `decoder_roadmap.md`:
inner cocotb bit-exact vs the new exact-Log-MAP fixed-point reference + outer
bounded BER-vs-SNR vs float, plus a Quartus II 13.0sp1 fit gate.

## 1. Exact-Log-MAP fixed-point reference + characterization

- [ ] 1.1 Author the Octave exact-Log-MAP reference: `max*(a,b) = max(a,b) +
  f(|a−b|)` with a quantized correction LUT, plus the extrinsic scaling factor.
- [ ] 1.2 Generate golden vectors from the new reference (the Max-Log-MAP
  vectors do not carry over); document the new bit-exact contract.
- [ ] 1.3 Outer characterization: bounded BER-vs-SNR vs float `turbo_decoder.m`,
  showing the recovered Max-Log-MAP gap within a documented dB margin.

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
