## Tasks — add-fpga-turbo-decoder-term-de2-demo

High-level STAGE skeleton (stub). Dual gate per the prior board demos: GHDL
self-check lane (PASS on golden, FAIL on a corrupted bit) + Quartus II 13.0sp1
fit/timing closure at the decoder PLL clock; on-board read is the hardware
oracle (gated). The verified cores stay UNMODIFIED throughout.

## 1. CRC-matrix fit study + demo K selection

- [ ] 1.1 Characterize the `turbo_decoder_term_top` M4K cost under Quartus II
  13.0sp1, isolating the two 6144×24 CRC-matrix (~65 M4K fixed) contribution.
- [ ] 1.2 If K=512 does not fit the EP2C35 (105 M4K), reduce K and/or optimize
  the CRC representation (e.g. on-the-fly LFSR CRC vs stored matrices); record
  the chosen demo K and the M4K breakdown.

## 2. Board wrapper + self-check

- [ ] 2.1 Add `turbo_decoder_term_de2_top.vhdl` reusing the decoder-demo
  harness: on-chip golden-LLR ROM, KEY0 restart, LED + 7-seg verdict, shared
  `hd44780_lcd` status on the PLL-derived ~12.5 MHz clock.
- [ ] 2.2 Self-check decoded bits + early-termination outcome bit-for-bit vs the
  P3 golden vector; add the demo `.qsf` (pins + source list).
- [ ] 2.3 GHDL self-check lane: PASS on golden, FAIL on a corrupted bit.

## 3. Fit/timing + on-board

- [ ] 3.1 Quartus II 13.0sp1 fit at the chosen K: fits, pins map, timing closes
  on the PLL clock; produce the `.sof`.
- [ ] 3.2 On-board program-and-observe (HARDWARE-GATED): LCD label + RUNNING →
  PASS, KEY0 re-runs.

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-turbo-decoder-term-de2-demo --strict`
  and `npx openspec validate --all --strict` pass.
