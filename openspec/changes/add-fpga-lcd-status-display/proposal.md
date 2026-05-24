## Why

Both DE2 board demos now run self-checked on real silicon: the TX chain
(`tx_chain_de2_top`, K=40) and the iterative turbo decoder
(`turbo_decoder_de2_top`, K=512). Each reports its verdict on LEDs plus a 7-seg
status code — pass = "A5", fail = "FF", running = "00" — via the shared
`hdl/boards/hex7seg.vhdl` nibble decoder. Those codes work, but they are cryptic:
"A5" / "FF" carry no meaning to anyone who has not memorized the mapping, and a
static "00" gives no sign the demo is actually *alive* (a hung demo and a
running one both read "00").

The DE2 carries an on-board **16×2 character LCD (HD44780-compatible)** that is
currently unused by either demo. Driving it gives an at-a-glance,
human-readable status with no external monitor: a fixed label naming the demo
(so you know *which* demo is loaded) on line 1, and a live status on line 2 that
shows `RUNNING` with a visible heartbeat (an animated character that ticks so
you can see the demo is alive), resolving to `PASS` or `FAIL` when the
self-check completes. Pressing KEY0 re-runs the demo and the LCD updates
accordingly — the same restart that already re-arms the LED/7-seg verdict.

The LCD is additive: it is driven from the demos' **existing** self-check FSM
flags (`pass`/`fail`/`done`/`running`), so it changes no verdict logic and
touches neither verified core. Resource cost is negligible (a few hundred LE,
~0 M4K) against the decoder demo's current 36 % LE / 54 % M4K, so there is ample
headroom on the EP2C35.

## What Changes

- **Add a shared, reusable HD44780 LCD controller** `hdl/boards/hd44780_lcd.vhdl`
  alongside `hdl/boards/hex7seg.vhdl` (same shared-board-component pattern,
  referenced — not copied — by each demo's `.qsf`). The controller:
  - runs the HD44780 **power-on init sequence** (~15 ms initial wait, then
    function-set 8-bit/2-line/5×8 font, display-on, clear, entry-mode set) and
    then continuously writes two 16-character line buffers to DDRAM (line 1 @
    DDRAM 0x00, line 2 @ 0x40), all with counter-based HD44780 timing delays;
  - exposes a simple message interface: two 16-character ASCII line buffers
    (`line1_i`, `line2_i`) that the board wrapper drives, plus the LCD bus
    outputs (`LCD_DATA[7:0]`, `LCD_RS`, `LCD_RW`, `LCD_EN`, `LCD_ON`,
    `LCD_BLON`);
  - carries a **`CLK_HZ` generic** that scales every delay counter, so the same
    core works in BOTH the 50 MHz TX domain and the 12.5 MHz decoder domain.
- **Wire the LCD into BOTH board wrappers** (`tx_chain_de2_top`,
  `turbo_decoder_de2_top`) — board-wrapper edits only, the verified cores
  (`tx_chain_top`, `turbo_decoder_top`) stay UNMODIFIED:
  - line 1 = a fixed demo label (e.g. `3GPP TX K=40` / `3GPP TURBO K=512`);
  - line 2 = live status decoded from the existing FSM flags: `RUNNING` +
    heartbeat char (driven by a free-running counter) while in flight, then
    `PASS` or `FAIL` once `done` latches; KEY0 restart re-arms it;
  - instantiate `hd44780_lcd` with `CLK_HZ` set to that demo's clock (50 MHz for
    TX, 12.5 MHz for the decoder).
- **Add LCD pin assignments** to each demo's `.qsf`
  (`tx_chain_de2.qsf`, `turbo_decoder_de2.qsf`) for `LCD_DATA[7:0]`, `LCD_RW`,
  `LCD_EN`, `LCD_RS`, `LCD_ON`, `LCD_BLON` (Terasic DE2 canonical pins, flagged
  for cross-check against the DE2 user manual like the prior board pins).
- **Add a GHDL testbench for the LCD controller** under `hdl/sim/hd44780_lcd/`
  that asserts the emitted HD44780 **command/data byte sequence** for the init
  sequence and a sample message (an output-only device → bit-exact verification
  is a byte-sequence assertion, not a golden-vector compare). The existing
  `hdl/sim/tx_chain_de2/` and `hdl/sim/turbo_decoder_de2/` self-check lanes must
  STILL PASS unchanged (the LCD is additive output).

All work is **proposal-only in this change** — no `hdl/`, `scripts/`, `.qsf`, or
`.m` edits land here. The 7-seg A5/FF codes are kept (the LCD is additive, not a
replacement) unless the user decides otherwise.

## Capabilities

### New Capabilities

- `fpga-lcd-status-display`: a shared HD44780 16×2 LCD controller
  (`hd44780_lcd`) with a `CLK_HZ`-parameterized init + char-write timing, plus
  human-readable status output (fixed demo label + `RUNNING`/heartbeat →
  `PASS`/`FAIL`) wired into BOTH DE2 board demos, driven from each demo's
  existing self-check FSM flags. This is a new board-presentation behavior — an
  on-board character display reused across two clock domains — distinct from the
  existing LED/7-seg verdict.

### Modified Capabilities

None at the capability level. `fpga-tx-chain-de2-demo` and
`fpga-turbo-decoder-de2-demo` are touched only at the **board-wrapper** level
(adding an additive LCD output driven from their already-specified pass/fail/
running flags); their verdict contracts, golden vectors, and verified cores are
unchanged, so neither capability spec is modified. The new behavior gets its own
capability rather than overloading either demo spec.

## Impact

- **Planning only in this change** — no `hdl/`, `scripts/`, `.qsf`, or `.m`
  edits land here. Implementation follows in the staged `tasks.md`.
- When implemented: one new shared core `hdl/boards/hd44780_lcd.vhdl`; a new
  GHDL lane `hdl/sim/hd44780_lcd/`; additive edits to the two board wrappers and
  their `.qsf` pin tables; README updates noting what the LCD shows. Nothing
  under `hdl/rtl/` changes; the verified cores and golden vectors are untouched.
- Resource cost is negligible (a few hundred LE, ~0 M4K) on top of each demo;
  the decoder demo's 36 % LE / 54 % M4K leaves ~21k LE / ~48 M4K free — space is
  a non-issue.
- The controller's `CLK_HZ` generic makes one core serve both the 50 MHz TX
  domain and the 12.5 MHz PLL-derived decoder domain; correct delay-count
  scaling at both is a verification item.
- Depends on Quartus II 13.0sp1 on the existing Windows host; the GHDL
  byte-sequence TB + the unchanged self-check lanes + Quartus fit/timing are all
  verifiable without a board. The physical program-and-observe (read the LCD) is
  the hardware oracle and a gated manual step.

## Out of Scope (explicit)

- **VGA** output (needs an external monitor and a far larger controller).
- **Rich stats** on the LCD (error counts, iteration counts, throughput) — noted
  as a deferred option; this change is status + heartbeat only.
- Any change to the verified cores (`tx_chain_top`, `turbo_decoder_top`) or to
  the golden vectors / verdict logic — the LCD is additive output only.
- Replacing the 7-seg A5/FF codes (kept by default; the LCD is additive).
- A DE1 LCD variant or any host link.
