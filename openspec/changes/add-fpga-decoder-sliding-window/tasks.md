## Tasks — add-fpga-decoder-sliding-window

High-level STAGE skeleton (stub). Two-tier gate per `decoder_roadmap.md`:
inner cocotb bit-exact vs the new sliding-window fixed-point reference + outer
characterization vs float, plus a Quartus II 13.0sp1 fit gate at K = 6144.

## 1. Sliding-window fixed-point reference + characterization

- [ ] 1.1 Author the Octave sliding-window α fixed-point reference (windowed
  forward pass + checkpoints; max-norm and ±inf sentinel as locked in the
  roadmap).
- [ ] 1.2 Generate golden vectors from the new reference (the full-block vectors
  do not carry over); document the new bit-exact contract.
- [ ] 1.3 Outer characterization: equivalence (constituent) and bounded
  BER-vs-SNR (loop) vs float within a documented band, confirming no accuracy
  regression from windowing.

## 2. HDL sliding-window α

- [ ] 2.1 Replace the full-block α store with a `8 × W` window RAM plus a
  checkpoint store; rework the forward/backward scheduling.
- [ ] 2.2 cocotb inner gate: HDL bit-exact to the new reference over the K set.

## 3. K = 6144 fit + regression

- [ ] 3.1 Quartus II 13.0sp1 fit of the full K = 6144 path on the EP2C35
  (the memory that previously did not fit); record LE / M4K.
- [ ] 3.2 Full regression green (all TX lanes + decoder lanes + Octave).

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-decoder-sliding-window --strict` and
  `npx openspec validate --all --strict` pass.
