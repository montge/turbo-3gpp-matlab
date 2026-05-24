## Tasks — add-fpga-decoder-recurrence-pipelining

High-level STAGE skeleton (stub). Two-tier gate per `decoder_roadmap.md`:
inner cocotb bit-exact vs the new pipelined fixed-point reference + outer
characterization vs float, plus a Quartus II 13.0sp1 50 MHz timing-closure gate.

## 1. Pipelined-recurrence fixed-point reference + characterization

- [ ] 1.1 Author the Octave reference for the restructured recurrence (ACS
  look-ahead / radix-2 schedule + intermediate widths).
- [ ] 1.2 Generate golden vectors from the new reference; document the new
  bit-exact contract.
- [ ] 1.3 Outer characterization vs float confirming the decoded output / BER is
  unchanged within the documented band.

## 2. HDL recurrence restructuring

- [ ] 2.1 Break the single-cycle α/β feedback cone via look-ahead / radix-2
  (precompute-then-select two trellis steps per cycle).
- [ ] 2.2 cocotb inner gate: HDL bit-exact to the new reference over the K set.

## 3. 50 MHz timing closure + regression

- [ ] 3.1 Quartus II 13.0sp1: `turbo_decoder_top` closes timing at 50 MHz on the
  EP2C35 (vs the prior ~15.4 MHz); record Fmax / LE / M4K.
- [ ] 3.2 Full regression green (all TX lanes + decoder lanes + Octave).

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-decoder-recurrence-pipelining --strict`
  and `npx openspec validate --all --strict` pass.
