# fpga-lcd-stats-enrichment Specification

## Purpose
TBD - created by archiving change add-fpga-lcd-stats-enrichment. Update Purpose after archive.
## Requirements
### Requirement: LCD shows the self-check error count

The system SHALL enrich both DE2 demos' LCD line 2 with an ASCII-formatted
output-bit error count (`err=NNN`), driven by the existing self-check comparator
extended to COUNT mismatches against the on-chip golden vector across the full
output stream, additive to the existing PASS/FAIL verdict plus heartbeat, and
without changing the PASS/FAIL verdict meaning, the verified cores, the golden
vectors, or the LED / 7-seg mapping.

#### Scenario: Error count rendered on the LCD at the verdict

- **WHEN** a demo's self-check reaches its latched verdict
- **THEN** LCD line 2 shows, in fixed-width ASCII decimal, the number of
  output-bit mismatches the self-check observed against the golden vector (e.g.
  `err=000` on a clean pass, `err=NNN` on a fail), alongside the PASS/FAIL
  verdict and the always-on heartbeat
- **AND** the error count is rendered only once the verdict is latched; the held
  RUNNING display window continues to show `RUNNING` plus the heartbeat

#### Scenario: Comparator counts mismatches instead of bailing on the first

- **WHEN** the self-check compares the captured output stream to the golden
  vector
- **THEN** the comparator accumulates every output-bit mismatch into a
  saturating error-count register across the whole stream, rather than stopping
  at the first mismatch
- **AND** the latched verdict is PASS if and only if the error count is zero and
  the end-of-block framing (`out_last`/`last` at the final index) is correct,
  and FAIL otherwise — preserving the existing verdict meaning, LEDs, and 7-seg
  exactly

#### Scenario: Fixed-width decimal formatting

- **WHEN** the error count is placed on line 2
- **THEN** a `uint`→decimal-ASCII helper renders it as a fixed-width zero-padded
  decimal field that fits within the 16-character line, saturating at the field
  maximum so the rendered width is always constant

#### Scenario: Enrichment is additive and the verdict path is preserved

- **WHEN** the error-count enrichment is added
- **THEN** only the self-check comparator (counting instead of bailing), the
  line-2 string, and the new `uint`→ASCII helper change; the verified cores
  (`turbo_decoder_top`, `tx_chain_top`), the golden vectors, the PASS/FAIL
  verdict meaning, the LED / 7-seg mapping, and the `hd44780_lcd` controller are
  unchanged
- **AND** both demo self-check lanes still pass on the golden vector and fail on
  a corrupted bit, and a byte-sequence testbench confirms line 2 renders the
  correct decimal digits (`err=000` for the golden pass, `err=001` for a
  one-bit corruption)

### Requirement: Decoder LCD shows the configured iteration count as a static field

The system SHALL show, on the decoder demo's LCD line 2 only, the configured
maximum decoder iterations as a STATIC information field (e.g. `it=N` sourced
from the `MAX_ITERATIONS` constant), documented as a constant configuration
value and not as a dynamic per-run measurement, while the TX demo shows no
iteration field.

#### Scenario: Static iteration field on the decoder demo

- **WHEN** the decoder demo's verdict is shown on the LCD
- **THEN** line 2 includes a static `it=N` field whose value is the compile-time
  configured `MAX_ITERATIONS`, identical on every run, alongside the error count
  and within the 16-character line budget

#### Scenario: No dynamic iteration count is implied

- **WHEN** the iteration field is displayed
- **THEN** it is sourced from the configured constant and not from any runtime
  iteration counter, because the plain decoder board demo runs a fixed number of
  iterations with no on-board CRC early-termination; a dynamic iteration count
  is out of scope and belongs to a future term/CRC board demo

#### Scenario: TX demo has no iteration field

- **WHEN** the TX demo's verdict is shown on the LCD
- **THEN** line 2 carries only the error count plus heartbeat, with no iteration
  field, because the TX chain does not iterate

### Requirement: On-board TX-demo LCD confirmation is completed

The system SHALL close the deferred on-board TX-demo LCD confirmation (task 4.3
of `add-fpga-lcd-status-display`) by programming the TX demo's LCD `.sof` to a
DE2 and visually confirming the LCD output, as a hardware-gated manual step.

#### Scenario: TX demo LCD confirmed on hardware

- **WHEN** the TX demo's LCD `.sof` is programmed to a DE2 and triggered
- **THEN** the LCD shows the TX demo's label on line 1 and `RUNNING` with a
  moving heartbeat resolving to `PASS err=000` on line 2, and a KEY0 press
  re-runs the demo and updates the LCD

