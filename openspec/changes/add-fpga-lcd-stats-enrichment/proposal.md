## Why

The archived `add-fpga-lcd-status-display` added a shared `hd44780_lcd`
controller to both DE2 demos, showing a fixed label on line 1 and
`RUNNING`/heartbeat → `PASS`/`FAIL` on line 2. That change explicitly named
**"rich stats (error counts, iteration counts, throughput)"** as a deferred
option. This change delivers the deferred enrichment: show, on the decoder
demo's LCD line 2, the **decoded-bit error count** and the **iterations
performed**, ASCII-formatted, beyond the bare PASS/FAIL + heartbeat.

This change ALSO closes the one **deferred hardware checkbox** from
`add-fpga-lcd-status-display` (its task 4.3): the TX demo's LCD `.sof` was never
programmed and visually confirmed on the board (only the decoder demo was). That
on-board TX-LCD confirmation is folded in here as a task so the LCD work has no
dangling hardware step — it is the same shared `hd44780_lcd` controller and a
tiny on-board observe step, naturally bundled with this LCD-presentation change
rather than spun up as its own change.

The enrichment is **additive presentation only**: the error count comes from the
existing self-check comparator and the iteration count from the decoder's
existing termination/iteration signal — no verdict logic, verified core, or
golden vector changes.

## What Changes

- **Enrich** the decoder demo's LCD line 2 with ASCII-formatted **decoded-bit
  error count** (from the existing self-check bit-comparator) and **iterations
  performed** (from the decoder's existing iteration/termination signal),
  alongside the existing PASS/FAIL + heartbeat. Add a small binary→ASCII format
  helper for the on-LCD numbers.
- **Keep** the controller and verdict path unchanged — line-2 string-selection
  logic only; the verified cores (`turbo_decoder_top`), golden vectors, LED /
  7-seg, and `hd44780_lcd` are untouched.
- **Confirm on-board** the TX demo's LCD `.sof` (the deferred task 4.3 from
  `add-fpga-lcd-status-display`): program the TX demo and visually confirm the
  LCD shows its label + RUNNING/heartbeat → PASS, and KEY0 re-runs.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. The exact line-2 layout (field widths, abbreviations to
fit 16 chars) is deferred to when this change is started.

## Capabilities

### New Capabilities

- `fpga-lcd-stats-enrichment`: ASCII-formatted decoded-bit error count and
  iterations-performed on the decoder demo's LCD line 2 (additive to the
  existing PASS/FAIL + heartbeat), driven from the existing self-check
  comparator and iteration signal, plus closing the deferred on-board TX-demo
  LCD confirmation from `add-fpga-lcd-status-display`.

## Impact

- Builds on `fpga-lcd-status-display` (the shared `hd44780_lcd` + line-2 status)
  and `fpga-turbo-decoder-de2-demo` (the self-check comparator + iteration
  signal); the verified cores and verdict logic stay UNMODIFIED.
- Depends on Quartus II 13.0sp1 on the Windows host; the GHDL byte-sequence /
  self-check lanes + the Quartus fit are verifiable without a board; the two
  on-board observe steps (enriched decoder LCD + the TX-demo LCD confirmation)
  are hardware-gated manual steps.
- Small change; resource cost is a small format helper (~tens of LE).

## Out of Scope (explicit)

- Throughput / timing stats on the LCD (only error count + iterations here).
- VGA or any richer display.
- Any change to the verified cores, golden vectors, or the LED / 7-seg verdict.
