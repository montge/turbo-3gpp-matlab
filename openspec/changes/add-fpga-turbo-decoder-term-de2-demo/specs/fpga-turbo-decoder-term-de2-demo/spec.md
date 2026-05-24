## ADDED Requirements

### Requirement: DE2 board demo of the P3 termination decoder

The system SHALL provide a DE2 board demo of `turbo_decoder_term_top` (the P3
decoder with CRC-aided early termination, HARQ accumulation, and filler
NaN→+inf handling) that reuses the existing decoder-demo harness and LCD status
pattern, self-checking the decoded bits against the committed P3 golden vector
with no host link, while leaving the verified cores unmodified.

#### Scenario: Self-checked termination decode on the board

- **WHEN** the demo is triggered (KEY0)
- **THEN** `turbo_decoder_term_top` decodes the on-chip golden-LLR frame using
  CRC-aided early termination and filler handling, the decoded bits are checked
  bit-for-bit against the P3 golden vector, and LED + 7-seg + the shared
  `hd44780_lcd` status report the verdict (RUNNING/heartbeat → PASS/FAIL) on the
  PLL-derived ~12.5 MHz decoder clock

#### Scenario: Verified cores and harness reused unmodified

- **WHEN** the demo is built
- **THEN** it reuses `turbo_decoder_term_top`, the decoder-demo harness, and the
  `hd44780_lcd` controller without modifying them, and the GHDL self-check lane
  passes on the golden vector and fails on a corrupted bit

### Requirement: CRC-matrix M4K fit study selects the demo K

The system SHALL document a Quartus II 13.0sp1 fit study of the CRC-matrix M4K
cost and SHALL select a demo K (reducing K and/or optimizing the CRC
representation if needed) such that `turbo_decoder_term_top` fits the EP2C35.

#### Scenario: Fit study isolates CRC-matrix cost and picks K

- **WHEN** the term decoder is fit under Quartus II 13.0sp1
- **THEN** the two 6144×24 CRC matrices' ~65 M4K (fixed) contribution is
  isolated, and if the chosen design does not fit the EP2C35's 105 M4K the demo
  reduces K and/or optimizes the CRC representation (e.g. on-the-fly LFSR CRC),
  recording the chosen demo K and the M4K breakdown
- **AND** the final demo fits with no Fitter or Analysis & Synthesis errors and
  timing closes on the decoder PLL clock
