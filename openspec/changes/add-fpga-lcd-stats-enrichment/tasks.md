## Tasks — add-fpga-lcd-stats-enrichment

High-level STAGE skeleton (stub). Dual gate per the LCD demo: GHDL
byte-sequence + self-check lanes unchanged-green + Quartus II 13.0sp1 fit;
on-board reads are hardware-gated. The verified cores, golden vectors, and
LED / 7-seg verdict stay UNMODIFIED throughout.

## 1. ASCII stats enrichment on the decoder LCD

- [ ] 1.1 Add a binary→ASCII format helper for on-LCD numbers (decimal,
  fixed-width to fit 16 chars).
- [ ] 1.2 Drive decoder LCD line 2 with the decoded-bit error count (from the
  existing self-check bit-comparator) and the iterations performed (from the
  decoder's existing iteration/termination signal), alongside PASS/FAIL +
  heartbeat. Line-2 string-selection logic only.
- [ ] 1.3 Confirm additive-only: the self-check FSM, verdict, LED / 7-seg,
  verified cores, golden vectors, and `hd44780_lcd` are untouched.

## 2. Verification gates

- [ ] 2.1 GHDL: the decoder self-check lane still PASSES (golden) / FAILS
  (corrupt); the `hd44780_lcd` byte-sequence TB still passes; vectors
  byte-identical.
- [ ] 2.2 Quartus II 13.0sp1 re-fit the decoder demo: still fits, pins map,
  timing closes on the PLL clock; record LE / M4K delta.

## 3. On-board (HARDWARE-GATED — user's board)

- [ ] 3.1 Program the enriched decoder demo; confirm the LCD shows the error
  count + iterations alongside PASS, KEY0 re-runs.
- [ ] 3.2 Close the deferred `add-fpga-lcd-status-display` task 4.3: program the
  TX demo's LCD `.sof` and visually confirm label + RUNNING/heartbeat → PASS,
  KEY0 re-runs.

## 4. Validate

- [ ] 4.1 `npx openspec validate add-fpga-lcd-stats-enrichment --strict` and
  `npx openspec validate --all --strict` pass.
