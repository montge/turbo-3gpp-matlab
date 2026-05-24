## Context

Both DE2 demos already self-check and report a verdict:

```
tx_chain_de2_top       (50  MHz CLOCK_50 direct)  -> LEDG/LEDR + HEX "A5"/"FF"/"00"
turbo_decoder_de2_top  (12.5 MHz PLL-derived)     -> LEDG/LEDR + HEX "A5"/"FF"/"00"
```

Each wrapper holds a self-check FSM with sticky `pass_f` / `fail_f` / `done_f`
flags (see `hdl/boards/de2/tx_chain_de2_top.vhdl` lines 148-151, 309-322 and
`hdl/boards/de2/turbo_decoder_de2_top.vhdl` lines 160-163, 333-346). Today those
flags drive:

- `LEDG[0] = pass_f`, `LEDR[0] = fail_f`, `LEDG[1] = not done_f` (running),
  `LEDR[1] = done_f`;
- two `hex7seg` instances → "A5" (pass) / "FF" (fail) / "00" (running).

The DE2 has an on-board **16×2 HD44780-compatible character LCD** that neither
demo uses. This change adds a shared LCD controller driven from those SAME
flags, giving a readable label + live status. It mirrors the existing shared
board-component pattern: `hd44780_lcd.vhdl` lives next to `hex7seg.vhdl` under
`hdl/boards/`, is referenced (not copied) by each demo `.qsf`, and is verified
by its own GHDL lane.

The single cross-cutting wrinkle is that the two demos run on different clocks
(50 MHz for TX, 12.5 MHz PLL-derived for the decoder), and HD44780 timing is in
real microseconds/milliseconds, so the controller's delay counters must be
parameterized by clock frequency.

## Goals / Non-Goals

**Goals:**

- One reusable `hd44780_lcd` controller that runs the HD44780 power-on init and
  then continuously refreshes a 16×2 character display from two line buffers,
  with all timing delays scaled by a `CLK_HZ` generic so the same core works at
  50 MHz AND 12.5 MHz.
- Wire it into BOTH wrappers: line 1 = fixed demo label; line 2 = `RUNNING` +
  heartbeat → `PASS` / `FAIL`, decoded from each demo's existing FSM flags;
  KEY0 restart re-arms it.
- Additive only — the verified cores, golden vectors, verdict logic, and the
  7-seg A5/FF codes are unchanged; both demos' existing GHDL self-check lanes
  still pass.
- Prove the controller in GHDL by asserting its emitted HD44780 command/data
  **byte sequence** (init + a sample message), then fit both demos in Quartus
  (still fits, LCD pins map, timing closes at each clock).

**Non-Goals:**

- No VGA, no rich stats (error/iteration counts), no host link (see proposal
  Out of Scope).
- No RTL change to `tx_chain_top` / `turbo_decoder_top` or any sub-core; no
  change to the golden vectors or the pass/fail/done verdict logic.
- No DE1 LCD variant; no CI synthesis lane (board build stays local/manual).

## Decisions

### 1. Shared `hd44780_lcd` controller (the one new RTL element)

Entity sketch (under `hdl/boards/hd44780_lcd.vhdl`, sibling of `hex7seg.vhdl`):

```vhdl
entity hd44780_lcd is
  generic (
    CLK_HZ : integer := 50_000_000   -- scales every HD44780 delay counter;
                                      -- 50e6 for TX, 12_500_000 for the decoder
  );
  port (
    clk      : in  std_logic;        -- the demo's functional clock
    rst      : in  std_logic;        -- synchronous reset (re-run init on restart)
    line1_i  : in  string(1 to 16);  -- top line ASCII (fixed demo label)
    line2_i  : in  string(1 to 16);  -- bottom line ASCII (live status)
    -- HD44780 8-bit parallel bus to the DE2 LCD header:
    lcd_data : out std_logic_vector(7 downto 0);  -- DB7..DB0
    lcd_rs   : out std_logic;        -- 0 = command, 1 = data
    lcd_rw   : out std_logic;        -- tied 0 (write-only; no busy-flag readback)
    lcd_en   : out std_logic;        -- E strobe
    lcd_on   : out std_logic;        -- panel power (drive '1')
    lcd_blon : out std_logic         -- backlight (drive '1')
  );
end entity hd44780_lcd;
```

(`line1_i`/`line2_i` as `string(1 to 16)` is the simplest message interface; an
equivalent `std_logic_vector` of 16 packed bytes per line is an acceptable
alternative if a `string` port proves awkward for the wrapper — decide at
implementation. Either way the wrapper sets two 16-char lines and the core does
the rest.)

Two cooperating FSMs / phases:

- **Init FSM** — on reset (and at power-up) run the HD44780 cold-start: wait
  ~15 ms, issue function-set (8-bit / 2-line / 5×8 font), display-on (display
  on, cursor off, blink off), display-clear (~1.5 ms settle), entry-mode set
  (increment, no shift). Each step holds `lcd_data`/`lcd_rs`, pulses `lcd_en`
  with the required E-high/E-low widths, and waits the HD44780 post-command
  delay. `lcd_rw` is tied '0' (write-only; we use fixed worst-case delays rather
  than reading the busy flag — simpler and robust).
- **Refresh FSM** — after init, loop forever: set DDRAM address 0x00, write the
  16 `line1_i` chars; set DDRAM address 0x40, write the 16 `line2_i` chars; then
  repeat. Because the wrapper drives the line buffers combinationally from the
  FSM flags + heartbeat counter, the next refresh pass paints the current
  status. A full refresh at HD44780 per-char timing (~40 µs/char × 32 + address
  sets) is well under a frame to the eye.

All waits are **counter-based**, with each terminal count computed from the
`CLK_HZ` generic, e.g. `cycles = CLK_HZ * delay_us / 1_000_000` rounded up. So
the same RTL yields ~15 ms at 50 MHz and at 12.5 MHz by construction; only the
counter widths/values differ per instantiation. Counter widths are sized for the
largest delay at the highest `CLK_HZ` (the ~15 ms power-on wait at 50 MHz ≈
750 000 cycles → 20-bit counter).

### 2. Heartbeat (liveness indicator)

A free-running counter in the wrapper (or in the LCD core, fed to line 2)
toggles a heartbeat character on a slow, human-visible cadence (e.g. a few Hz).
While `done_f = '0'` (running), line 2 reads e.g. `RUNNING <hb>` where `<hb>`
animates (alternating between two glyphs, or a small spinner `|/-\`, or a
blinking block). When `done_f = '1'`, line 2 becomes the static `PASS` or
`FAIL`. The animated char distinguishes a live run from a hung one (the static
"00" on the 7-seg cannot). The exact heartbeat style is an open question; a
two-glyph blink off the counter MSB is the simplest default.

### 3. How each wrapper drives the LCD (additive; flags already exist)

In each `*_de2_top`, add (board-wrapper edits only):

- a `component hd44780_lcd` declaration and an `u_lcd : hd44780_lcd` instance
  with `generic map (CLK_HZ => <this demo's Hz>)` and `clk`/`rst` from the same
  domain that already clocks the FSM (CLOCK_50 for TX; the PLL `clk` for the
  decoder), `rst` from the restart pulse so KEY0 re-inits the panel;
- `line1_i` = a constant label string: `"3GPP TX K=40    "` (TX) /
  `"3GPP TURBO K=512"` (decoder) — exact strings are an open question;
- `line2_i` driven combinationally from the existing flags:
  - `pass_f = '1'` → `"PASS            "`,
  - `fail_f = '1'` → `"FAIL            "`,
  - else → `"RUNNING " & <heartbeat glyphs> & padding` (running);
- new LCD ports added to the entity and forwarded to the instance.

No FSM state, no verdict logic, and no LED/7-seg mapping changes — `pass_f` /
`fail_f` / `done_f` are read, never rewritten. The 7-seg A5/FF and the LEDs stay
exactly as they are.

### 4. LCD pins per demo `.qsf`

Add to BOTH `tx_chain_de2.qsf` and `turbo_decoder_de2.qsf` the Terasic DE2
canonical LCD pins for `LCD_DATA[7:0]`, `LCD_RW`, `LCD_EN`, `LCD_RS`, `LCD_ON`,
`LCD_BLON`, under the same `3.3-V LVTTL` I/O standard and
`RESERVE_ALL_UNUSED_PINS` discipline as the existing pins. As with the existing
CLOCK_50/KEY/LED/HEX pins, these are valid package pins for fit/synthesis but
MUST be cross-checked against the Terasic DE2 user manual before programming
real hardware (flagged for user verification — the gated on-board task). Also
add `../hd44780_lcd.vhdl` to each `.qsf` source list (referenced, not copied,
exactly like `../hex7seg.vhdl`).

### 5. Verified cores + golden vectors untouched

`hdl/rtl/` is not edited. The on-chip golden ROMs (`tx_chain_golden_pkg`,
`turbo_decoder_golden_pkg`) and the self-check FSMs' compare/verdict paths are
unchanged. The LCD reads the verdict flags; it cannot affect them. Therefore the
existing `hdl/sim/tx_chain_de2/` and `hdl/sim/turbo_decoder_de2/` lanes (PASS on
golden, FAIL on a corrupted bit via `CORRUPT_IDX`) must still pass after the LCD
is added — proving that is an explicit task per integration.

## Risks / Trade-offs

- **HD44780 init-timing correctness (top risk).** A wrong init sequence or
  too-short delay leaves the panel blank or garbled. *Mitigation:* implement the
  documented cold-start (≥15 ms wait, function-set, display-on, clear,
  entry-mode) with conservative fixed worst-case delays (write-only, no
  busy-flag read); the GHDL TB asserts the exact emitted command byte sequence
  and the E-strobe framing, and the on-board read is the final oracle.
- **Output-only device → no golden-vector compare.** The LCD emits, it does not
  return data. *Mitigation:* "bit-exact" verification = asserting the emitted
  **command/data byte SEQUENCE** (and `lcd_rs` per byte, `lcd_rw = 0`, the
  `lcd_en` strobe) in the TB for the init + a sample message — not a CSV golden
  compare. This is the natural shape for a display controller.
- **Clock-domain / delay-generic correctness.** The same core must time
  correctly at 50 MHz and 12.5 MHz. *Mitigation:* derive every terminal count
  from `CLK_HZ` (round up); size counter widths for the worst case; the TB runs
  the core at both a fast and a slow `CLK_HZ` and checks the realized delays
  span the required microsecond windows (cycle-count assertions), so the
  generic scaling is proven in sim, not just at one frequency.
- **Refresh continuously vs write-once.** Continuous refresh is robust (recovers
  from any glitch, repaints the current status every pass) at trivial cost; the
  alternative (write only on change) is marginally less bus traffic but more
  state. *Decision:* continuous refresh.
- **Resource / fit.** ~hundreds of LE, ~0 M4K — negligible against either demo's
  current utilization; fit pressure is a non-issue. Still re-run fit per demo as
  a gate (LCD pins must map, timing must still close).

## Open Questions

- **Exact LCD pin assignments** — confirm `LCD_DATA[7:0]`, `LCD_RW`, `LCD_EN`,
  `LCD_RS`, `LCD_ON`, `LCD_BLON` against the Terasic DE2 user manual before the
  on-board step (flagged like the prior board pins; valid package pins suffice
  for fit).
- **Heartbeat style** — two-glyph blink (default), spinner `|/-\`, or a moving
  block? Pick the cadence (a few Hz) and glyph set.
- **Keep the 7-seg A5/FF codes?** Default **YES** — the LCD is additive, the
  7-seg/LEDs stay. (Could later free the HEX pins, out of scope here.)
- **Exact label / status strings** — e.g. `3GPP TX K=40` / `3GPP TURBO K=512`
  for line 1; `RUNNING` / `PASS` / `FAIL` for line 2. Confirm wording and the
  16-char padding.
- **Message-interface form** — `string(1 to 16)` line ports (default) vs a
  packed `std_logic_vector` of 16 bytes, vs a small state→message ROM inside the
  core. Default: two `string` line buffers set by the wrapper.
- **Deferred:** rich stats (iteration / error counts) on the LCD — explicitly
  out of scope here; noted as a possible later increment.
