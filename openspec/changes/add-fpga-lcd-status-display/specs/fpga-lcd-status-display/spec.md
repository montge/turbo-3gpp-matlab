## ADDED Requirements

### Requirement: Shared HD44780 LCD controller

The system SHALL provide a reusable HD44780 16×2 character LCD controller
(`hdl/boards/hd44780_lcd.vhdl`) that performs the HD44780 power-on
initialization sequence and continuously writes two 16-character line buffers to
the display, with all timing delays scaled by a clock-frequency generic so the
same core works in multiple clock domains.

#### Scenario: Controller is a shared board component

- **WHEN** the LCD controller is added
- **THEN** it lives under `hdl/boards/` alongside `hdl/boards/hex7seg.vhdl` and
  is referenced (not copied) by each demo's `.qsf` source list
- **AND** it exposes the HD44780 bus (`lcd_data[7:0]`, `lcd_rs`, `lcd_rw`,
  `lcd_en`, `lcd_on`, `lcd_blon`) plus two 16-character line-buffer inputs and a
  `clk`/`rst`, and no file under `hdl/rtl/` is edited

#### Scenario: Power-on initialization sequence

- **WHEN** the controller starts (power-up or `rst`)
- **THEN** it issues the HD44780 cold-start sequence — an initial wait of at
  least ~15 ms, then function-set (8-bit interface, 2-line, 5×8 font),
  display-on (cursor and blink off), display-clear, and entry-mode set
  (increment, no shift) — each command framed by the `lcd_en` strobe with
  `lcd_rw` held at write and followed by the HD44780 post-command delay

#### Scenario: Continuous DDRAM refresh of both lines

- **WHEN** initialization has completed
- **THEN** the controller repeatedly sets DDRAM address `0x00` and writes the 16
  characters of line 1, then sets DDRAM address `0x40` and writes the 16
  characters of line 2, reflecting the current contents of the line-buffer
  inputs

### Requirement: Clock-frequency-parameterized timing

The controller SHALL scale every HD44780 delay from a `CLK_HZ` generic so a
single instantiation times correctly at both the 50 MHz TX-demo clock and the
12.5 MHz decoder-demo clock.

#### Scenario: Delays derive from the generic

- **WHEN** the controller is instantiated with a given `CLK_HZ`
- **THEN** each delay's terminal count is computed from `CLK_HZ` (cycles =
  ceil(`CLK_HZ` × delay_microseconds / 1e6)), so the realized delay equals the
  required HD44780 microsecond/millisecond window at that frequency
- **AND** the same RTL, instantiated at 50 MHz in the TX demo and at 12.5 MHz in
  the decoder demo, satisfies the HD44780 timing in both domains

### Requirement: LCD shows demo label and live status driven from the self-check FSM

The system SHALL drive the LCD in BOTH the `tx_chain_de2_top` and
`turbo_decoder_de2_top` board wrappers from each demo's existing self-check FSM
flags, showing a fixed demo label on line 1 and a live status (running with a
heartbeat, then pass or fail) on line 2, without modifying the verified cores,
the golden vectors, or the verdict logic.

#### Scenario: Line 1 names the demo

- **WHEN** a demo runs
- **THEN** line 1 of the LCD shows a fixed label identifying that demo (for
  example `3GPP TX K=40` for the TX demo and `3GPP TURBO K=512` for the decoder
  demo)

#### Scenario: Line 2 shows running with a heartbeat, then the verdict

- **WHEN** the self-check is in flight (the FSM's `done` flag is not yet set)
- **THEN** line 2 shows a running status with a visibly animated heartbeat
  character so the demo is observably alive
- **WHEN** the self-check has latched a verdict (`done` set)
- **THEN** line 2 shows `PASS` if the pass flag is latched, or `FAIL` if the
  fail flag is latched

#### Scenario: Driven from existing flags, additive only

- **WHEN** the LCD is wired into a board wrapper
- **THEN** it reads the wrapper's existing `pass`/`fail`/`done`/`running` flags
  and is instantiated with `CLK_HZ` set to that demo's clock (50 MHz for TX,
  12.5 MHz for the decoder)
- **AND** the self-check FSM, the LED mapping, the 7-seg A5/FF status codes, the
  verified cores (`tx_chain_top`, `turbo_decoder_top`), and the golden vectors
  are unchanged
- **AND** a KEY0 restart re-arms the verdict and the LCD updates accordingly

### Requirement: LCD pins and sources isolated under the board path

The system SHALL keep the LCD pin assignments and controller source under the
board paths, adding the HD44780 pins to each demo `.qsf` and listing the shared
controller in each source list, with no board or pin assignment in `hdl/rtl/`.

#### Scenario: LCD pins added to both demo projects

- **WHEN** the demos are updated
- **THEN** `hdl/boards/de2/tx_chain_de2.qsf` and
  `hdl/boards/de2/turbo_decoder_de2.qsf` each gain pin assignments for
  `LCD_DATA[7:0]`, `LCD_RW`, `LCD_EN`, `LCD_RS`, `LCD_ON`, and `LCD_BLON` under
  the existing `3.3-V LVTTL` / reserve-unused-pins discipline, and each `.qsf`
  source list references `../hd44780_lcd.vhdl`
- **AND** the LCD pins are flagged for cross-check against the Terasic DE2 user
  manual before programming real hardware, and no pin or board assignment
  appears in `hdl/rtl/`

### Requirement: LCD controller verified by emitted byte-sequence assertion

The system SHALL verify the LCD controller in GHDL by asserting its emitted
HD44780 command/data byte sequence, because the LCD is an output-only device for
which a golden-vector data compare is not applicable.

#### Scenario: Init and message byte sequence asserted

- **WHEN** the LCD controller GHDL testbench runs
- **THEN** it asserts the emitted command bytes of the init sequence and the
  command/data bytes of a sample message (DDRAM address sets plus the 16
  characters per line), including `lcd_rs` per byte, `lcd_rw` held at write, and
  the `lcd_en` strobe framing
- **AND** it runs the controller at both a fast and a slow `CLK_HZ` and asserts
  the realized delays span the required HD44780 timing windows at each

#### Scenario: Existing demo self-check lanes still pass

- **WHEN** the LCD is integrated into a board wrapper
- **THEN** that demo's existing GHDL self-check lane
  (`hdl/sim/tx_chain_de2/` or `hdl/sim/turbo_decoder_de2/`) still passes
  unchanged — PASS on the golden vector and FAIL on a corrupted bit via
  `CORRUPT_IDX` — confirming the LCD is additive and changes no verdict

### Requirement: On-board LCD readout is hardware-gated

The system SHALL define a manual program-and-observe step whose pass criterion
is the LCD showing the demo label plus a running heartbeat resolving to the
correct verdict; the change SHALL NOT require physical hardware for the GHDL
byte-sequence testbench, the unchanged self-check lanes, or the Quartus fit and
timing closure to be considered complete.

#### Scenario: Programmed board shows label and verdict on the LCD

- **WHEN** a DE2 is programmed with a demo `.sof` and the self-check is
  triggered
- **THEN** the LCD shows the demo's label on line 1 and `RUNNING` with a moving
  heartbeat on line 2, resolving to `PASS` (or `FAIL`) when the self-check
  completes, and a KEY0 press re-runs the demo and updates the LCD

#### Scenario: Completion does not depend on hardware

- **WHEN** the LCD byte-sequence testbench is green, both demos' existing
  self-check lanes still pass unchanged, both projects fit, and timing closes at
  each demo's clock under Quartus II 13.0sp1
- **THEN** the change is complete regardless of whether the physical
  program-and-observe step has been run
