## ADDED Requirements

### Requirement: PL-only KR260 decoder self-check demo over JTAG

The system SHALL run the verified `turbo_decoder_top` on the Kria K26
(`xck26-sfvc784-2LV`) as a PL-only Vivado bitstream — instantiating the core
UNMODIFIED with an on-chip golden-vector ROM and a self-check FSM that reports
PASS/FAIL on the KR260 user LEDs — downloaded over the on-board FT4232H JTAG,
with NO microSD, Linux, or PS+AXI integration.

#### Scenario: Bitstream self-checks against the on-chip golden vector

- **WHEN** the KR260 bitstream is downloaded over JTAG and runs the K=512 decode
- **THEN** the self-check FSM compares the decoded bits to the on-chip golden
  ROM and lights a PASS LED on a match (a deliberately corrupted build lights
  FAIL), with a re-run control

#### Scenario: Verified cores reused unchanged

- **WHEN** the KR260 demo is built
- **THEN** `turbo_decoder_top` and its sub-cores are instantiated unmodified
  (the same RTL the GHDL/cocotb bit-exact lanes cover), with no new fixed-point
  reference or golden vectors

### Requirement: Vivado timing closure on the K26

The system SHALL close timing in Vivado (synthesis + implementation) for the
KR260 demo on `xck26-sfvc784-2LV` at the chosen PL clock, recording the
resource usage (LUT/FF/BRAM/DSP) and worst negative slack.

#### Scenario: Timing closes and resources recorded

- **WHEN** the KR260 demo is run through Vivado synth + implementation
- **THEN** `report_timing` shows non-negative worst slack at the constrained PL
  clock, and the LUT/FF/BRAM/DSP + WNS + achieved Fmax are recorded (compared to
  the DE2's ~28 MHz)

### Requirement: Pinned KR260 toolchain and target

The system SHALL pin the KR260 toolchain and target — AMD Vivado ML Standard
(license-free for Kria) with the KR260/K26 board files, device
`xck26-sfvc784-2LV-c`, programmed via the FT4232H JTAG — and record it in the
project FPGA-toolchain memory, with the Vivado version fixed at install time.

#### Scenario: Toolchain pin recorded before build work

- **WHEN** the KR260 build work begins
- **THEN** the Vivado version, device part, board-file install, and JTAG/cable
  details are recorded (the analog of the DE2 Quartus 13.0sp1 pin), and the
  clocking strategy (PS `pl_clk0` vs a carrier clock) and LED pin LOCs are
  confirmed against the KR260 board documentation rather than guessed
