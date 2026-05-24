## ADDED Requirements

### Requirement: LCD shows decoded-bit error count and iterations performed

The system SHALL enrich the decoder demo's LCD line 2 with an ASCII-formatted
decoded-bit error count and iterations-performed value, driven from the existing
self-check bit-comparator and the decoder's existing iteration/termination
signal, additive to the existing PASS/FAIL plus heartbeat, without modifying the
verified cores, the golden vectors, or the LED / 7-seg verdict.

#### Scenario: Error count and iterations rendered on the LCD

- **WHEN** the decoder demo completes a self-check
- **THEN** LCD line 2 shows, in ASCII, the decoded-bit error count (from the
  existing self-check comparator) and the iterations performed (from the
  decoder's existing iteration/termination signal), alongside the PASS/FAIL
  verdict and the heartbeat

#### Scenario: Enrichment is additive presentation only

- **WHEN** the stats enrichment is added
- **THEN** only the line-2 string-selection logic and a binary→ASCII format
  helper change; the self-check FSM, the verdict, the LED / 7-seg mapping, the
  verified cores (`turbo_decoder_top`), the golden vectors, and the
  `hd44780_lcd` controller are unchanged
- **AND** the decoder self-check lane still passes on the golden vector and
  fails on a corrupted bit, and the `hd44780_lcd` byte-sequence testbench still
  passes

### Requirement: On-board TX-demo LCD confirmation is completed

The system SHALL close the deferred on-board TX-demo LCD confirmation (task 4.3
of `add-fpga-lcd-status-display`) by programming the TX demo's LCD `.sof` to a
DE2 and visually confirming the LCD output, as a hardware-gated manual step.

#### Scenario: TX demo LCD confirmed on hardware

- **WHEN** the TX demo's LCD `.sof` is programmed to a DE2 and triggered
- **THEN** the LCD shows the TX demo's label on line 1 and RUNNING with a moving
  heartbeat resolving to PASS on line 2, and a KEY0 press re-runs the demo and
  updates the LCD
