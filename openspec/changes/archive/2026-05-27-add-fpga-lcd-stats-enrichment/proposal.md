## Why

The archived `add-fpga-lcd-status-display` added a shared `hd44780_lcd`
controller to both DE2 demos, showing a fixed label on line 1 and
`RUNNING`/heartbeat → `PASS`/`FAIL` on line 2. That change explicitly named
**"rich stats (error counts, iteration counts, throughput)"** as a deferred
option. This change delivers the meaningful slice of that enrichment: show, on
BOTH demos' LCD line 2, the **decoded/output-bit error count** (`err=N`)
alongside the existing PASS/FAIL + heartbeat. The error count is the live,
informative stat — it is the *magnitude* of the mismatch that the self-check
already detects, so a near-miss FAIL (`err=001`) reads very differently from a
gross one (`err=042`) at a glance on the board.

This change ALSO closes the one **deferred hardware checkbox** from
`add-fpga-lcd-status-display` (its task 4.3): the TX demo's LCD `.sof` was never
programmed and visually confirmed on the board (only the decoder demo was). That
on-board TX-LCD confirmation is folded in here as a task so the LCD work has no
dangling hardware step — it is the same shared `hd44780_lcd` controller plus the
small enrichment delta, naturally bundled with this LCD-presentation change
rather than spun up as its own change.

### The iterations decision (honest scope)

The brief asked us to decide *honestly* whether to also show "iterations
performed." We chose to **show iterations as a STATIC info field, not a dynamic
count** — and only on the decoder demo:

- The plain `turbo_decoder_de2_top` instantiates `turbo_decoder_top` with a
  **fixed** `MAX_ITERATIONS => GV_MAX_ITER` (currently 2). There is **no CRC
  early-termination on the board** — that is the `turbo_decoder_term_top` /
  CRC path, which is a *different* (planned) board demo
  (`add-fpga-turbo-decoder-term-de2-demo`). So "iterations performed" is a
  **compile-time constant**, identical on every run.
- Displaying it as a *dynamic* count would imply a runtime measurement that does
  not exist and would mislead. We therefore render it as a clearly-static
  configuration field, e.g. `it=2`, documented as the configured maximum.
- A genuinely *dynamic* iteration count only becomes meaningful in a future
  term/CRC board demo; this change explicitly does NOT promise one. If the
  ≤16-char line-2 budget gets tight, the static `it=` field is the first thing
  dropped (open question in design.md) — the **error count is the primary, must-
  have stat**; the static iteration field is a nice-to-have.

The enrichment is **additive presentation plus a small self-check tweak**: the
error count comes from extending the existing self-check comparator to *count*
mismatches across all output bits (instead of bailing on the first one) rather
than from any new verified-core, golden-vector, or verdict-meaning change. The
PASS/FAIL verdict, the LEDs, and the 7-seg stay exactly as they are.

## What Changes

- **Enrich** BOTH demos' LCD line 2 with an ASCII-formatted **error count**
  (`err=NNN`) alongside the existing PASS/FAIL + heartbeat. The count is the
  number of output-bit mismatches the self-check observes against the on-chip
  golden vector.
- **Extend the self-check FSMs** (`turbo_decoder_de2_top`, `tx_chain_de2_top`)
  so the comparator **counts** mismatches across the full output stream into a
  saturating `err_cnt` register, instead of jumping to `CH_FAIL` on the first
  mismatch. The latched verdict is preserved exactly: PASS iff `err_cnt = 0`
  **and** the `out_last`/`last` framing lands at the expected final index;
  otherwise FAIL. The LED / 7-seg mapping is byte-for-byte unchanged.
- **Add a small `uint`→decimal-ASCII format helper** that renders an unsigned
  count into a fixed-width (3-digit) ASCII field for the line-2 string buffer.
- **Show, on the decoder demo only, a static `it=N` info field** (the configured
  `MAX_ITERATIONS`), documented as a constant configuration value — not a
  dynamic count.
- **Confirm on-board** the TX demo's LCD `.sof` (the deferred task 4.3 from
  `add-fpga-lcd-status-display`): program the TX demo and visually confirm the
  LCD shows its label + RUNNING/heartbeat → PASS with `err=000`, and KEY0
  re-runs.

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`,
or `.m` edits land here. The exact line-2 field layout (widths, abbreviations to
fit 16 chars, whether the static `it=` field stays) is pinned in design.md and
finalized when this change is implemented.

## Capabilities

### New Capabilities

- `fpga-lcd-stats-enrichment`: an ASCII-formatted output-bit **error count** on
  both DE2 demos' LCD line 2 (additive to the existing PASS/FAIL + heartbeat),
  driven by extending the existing self-check comparator to count mismatches; a
  small `uint`→decimal-ASCII format helper; a static `it=N` configuration field
  on the decoder demo; and closing the deferred on-board TX-demo LCD
  confirmation from `add-fpga-lcd-status-display`.

## Impact

- Builds on `fpga-lcd-status-display` (the shared `hd44780_lcd` + line-2 status)
  and the two demo capabilities (`fpga-turbo-decoder-de2-demo`,
  `fpga-tx-chain-de2-demo`); the verified cores (`turbo_decoder_top`,
  `tx_chain_top`), the golden vectors, and the PASS/FAIL verdict *meaning* stay
  UNMODIFIED.
- Affects only the two board wrappers and a small shared format helper: the
  self-check FSM comparator gains a mismatch counter, and line 2 is reformatted
  to embed the count.
- Depends on Quartus II 13.0sp1 on the Windows host; the GHDL byte-sequence /
  self-check lanes + the Quartus fit are verifiable without a board; the two
  on-board observe steps (enriched LCDs + the TX-demo confirmation) are
  hardware-gated manual steps.
- **No fit / M4K pressure expected.** The added logic is one saturating counter
  per demo plus a few-LE `uint`→ASCII conversion; the prior LCD fit had wide
  margins (decoder 37 % LE, TX 4 % LE). Expected delta: tens of LE, no M4K.

## Out of Scope (explicit)

- A **dynamic** iteration count (only the static configured `MAX_ITERATIONS` is
  shown, and only on the decoder demo); a dynamic count belongs to a future
  term/CRC board demo.
- Throughput / timing / latency stats on the LCD (only the error count + the
  static iteration field here).
- VGA or any richer display.
- Any change to the verified cores, the golden vectors, the PASS/FAIL verdict
  *meaning*, or the LED / 7-seg mapping.
