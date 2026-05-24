## Tasks — add-fpga-rx-chain-integration

High-level STAGE skeleton (stub). Two-tier gate: cocotb/GHDL numeric-exact for
the deterministic inverse-rate-match stages + bounded BER margin once the
decoder is in the loop (per `decoder_roadmap.md`), plus a Quartus II 13.0sp1 fit
gate. Existing cores reused unmodified.

## 1. Octave RX reference

- [ ] 1.1 Establish/confirm the float Octave RX model (inverse rate-matching +
  soft-combining + desegmentation) as the end-to-end oracle.
- [ ] 1.2 Generate vectors: TX golden frame → channel/soft samples → expected
  decoded transport-block bits.

## 2. Inverse rate-matching (de-rate-matching)

- [ ] 2.1 Inverse circular-buffer de-selection back to mother-code positions
  with soft-combining accumulation (HARQ).
- [ ] 2.2 Inverse subblock-interleave reconstructing the three soft LLR streams.
- [ ] 2.3 Inner gate: the reconstructed soft streams match the Octave model.

## 3. Desegmentation + decoder integration

- [ ] 3.1 Code-block desegmentation: drive each block through the reused
  `turbo_decoder_top`, concatenate decoded bits, strip per-block CRC.
- [ ] 3.2 `rx_chain_top` end-to-end vs the Octave RX model within the documented
  decoder margin.

## 4. Fit + regression + validate

- [ ] 4.1 Quartus II 13.0sp1 fit on the EP2C35; record LE / M4K.
- [ ] 4.2 Full regression green (all TX lanes + decoder lanes + Octave).
- [ ] 4.3 `npx openspec validate add-fpga-rx-chain-integration --strict` and
  `npx openspec validate --all --strict` pass.
