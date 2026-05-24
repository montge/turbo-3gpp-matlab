# Tasks — add-fpga-lcd-status-display

Dual gate per integration: **GHDL** (the LCD byte-sequence TB + the demo's
existing self-check lane unchanged) + **Quartus fit** (still fits, LCD pins map,
timing closes at that demo's clock). The on-board LCD read is the hardware
oracle (gated). The verified cores (`tx_chain_top`, `turbo_decoder_top`), golden
vectors, and verdict logic stay UNMODIFIED throughout.

## 1. Shared `hd44780_lcd` controller + GHDL byte-sequence TB

- [x] 1.1 Add `hdl/boards/hd44780_lcd.vhdl` (sibling of `hex7seg.vhdl`): an
  HD44780 16×2 controller with a `CLK_HZ` generic, `clk`/`rst`, two 16-char line
  buffers (`line1_i`/`line2_i`), and the LCD bus outputs (`lcd_data[7:0]`,
  `lcd_rs`, `lcd_rw`, `lcd_en`, `lcd_on`, `lcd_blon`). `lcd_rw` tied '0'
  (write-only); `lcd_on`/`lcd_blon` driven '1'.
- [x] 1.2 Implement the **init FSM**: ~15 ms power-on wait → function-set
  (8-bit / 2-line / 5×8) → display-on (display on, cursor/blink off) →
  display-clear (~1.5 ms) → entry-mode (increment, no shift), each with E-strobe
  framing and the HD44780 post-command delay. Re-run on `rst`.
- [x] 1.3 Implement the **refresh FSM**: set DDRAM 0x00, write 16 `line1_i`
  chars; set DDRAM 0x40, write 16 `line2_i` chars; loop forever (continuous
  refresh repaints the current status).
- [x] 1.4 Make every delay **counter-based, scaled from `CLK_HZ`**
  (`cycles = ceil(CLK_HZ * delay_us / 1e6)`); size counter widths for the worst
  case at the highest supported `CLK_HZ` (the ~15 ms wait at 50 MHz).
- [x] 1.5 Add `hdl/sim/hd44780_lcd/` (Makefile + test module + runner, mirroring
  the existing sim-lane layout). Assert the emitted **command/data byte
  sequence** for: (a) the full init sequence (each command byte, `lcd_rs = 0`,
  `lcd_rw = 0`, the `lcd_en` strobe framing), and (b) a sample message — DDRAM
  0x00 set, 16 chars of line 1 with `lcd_rs = 1`, DDRAM 0x40 set, 16 chars of
  line 2.
- [x] 1.6 In the same TB, run the core at BOTH a fast and a slow `CLK_HZ` (e.g.
  50e6 and 12.5e6) and assert each realized delay spans its required microsecond
  window (cycle-count check), proving the `CLK_HZ` scaling.

## 2. Integrate into `turbo_decoder_de2_top` (12.5 MHz)

- [x] 2.1 Add LCD ports to `turbo_decoder_de2_top` and instantiate `u_lcd :
  hd44780_lcd generic map (CLK_HZ => 12_500_000)` on the PLL-derived `clk`, with
  `rst` from the restart pulse. Drive `line1_i = "3GPP TURBO K=512"`; `line2_i`
  combinationally from the existing `pass_f`/`fail_f`/`done_f`: `PASS` / `FAIL` /
  `RUNNING <heartbeat>`. Add nothing to the FSM or the LED/7-seg mapping.
- [x] 2.2 Add the heartbeat: a free-running counter giving a few-Hz animated
  char on line 2 while running (`done_f = '0'`).
- [x] 2.3 Add LCD pins (`LCD_DATA[7:0]`, `LCD_RW`, `LCD_EN`, `LCD_RS`, `LCD_ON`,
  `LCD_BLON`) to `turbo_decoder_de2.qsf` (DE2 canonical, `3.3-V LVTTL`,
  flagged for user cross-check vs the DE2 manual) and add `../hd44780_lcd.vhdl`
  to its source list (referenced, not copied).
- [x] 2.4 Confirm the existing `hdl/sim/turbo_decoder_de2/` self-check lane
  STILL PASSES unchanged (PASS on golden, FAIL on `CORRUPT_IDX`) — the LCD is
  additive output.
- [x] 2.5 Quartus II 13.0sp1 fit: still fits the EP2C35, the LCD pins map, and
  timing still closes on the PLL-derived 12.5 MHz clock. Record LE/M4K delta.
  Result: 12,276 / 33,216 LE (37 %), 162,206 / 483,840 memory bits (34 %), 1 PLL,
  36 pins (all 13 `LCD_*` pins mapped, 3.3-V LVTTL). TimeQuest setup slack
  +9.416 ns, hold +0.391 ns on the 12.5 MHz PLL clock (all TNS=0 — closes).
  `output_files/turbo_decoder_de2.sof` produced.

## 3. Integrate into `tx_chain_de2_top` (50 MHz)

- [x] 3.1 Add LCD ports to `tx_chain_de2_top` and instantiate `u_lcd :
  hd44780_lcd generic map (CLK_HZ => 50_000_000)` on `CLOCK_50`, `rst` from the
  restart pulse. Drive `line1_i = "3GPP TX K=40    "`; `line2_i` from the
  existing `pass_f`/`fail_f`/`done_f` (`PASS` / `FAIL` / `RUNNING <heartbeat>`).
  No FSM or LED/7-seg changes.
- [x] 3.2 Add the heartbeat (same scheme as 2.2).
- [x] 3.3 Add the LCD pins to `tx_chain_de2.qsf` and `../hd44780_lcd.vhdl` to
  its source list (as in 2.3).
- [x] 3.4 Confirm the existing `hdl/sim/tx_chain_de2/` self-check lane STILL
  PASSES unchanged.
- [x] 3.5 Quartus II 13.0sp1 fit: still fits, LCD pins map, timing still closes
  at 50 MHz. Record LE/M4K delta.
  Result: 1,269 / 33,216 LE (4 %), 1,088 / 483,840 memory bits (<1 %), 0 PLL,
  36 pins (all 13 `LCD_*` pins mapped, 3.3-V LVTTL). TimeQuest setup slack
  +10.494 ns, hold +0.391 ns on CLOCK_50 (all TNS=0 — closes, Fmax ~105 MHz).
  `output_files/tx_chain_de2.sof` produced.

## 4. On-board program + visual confirmation (HARDWARE-GATED — user's board)

- [ ] 4.1 Cross-check the LCD pin assignments against the Terasic DE2 user
  manual; correct both `.qsf` files if needed.
- [ ] 4.2 Program the decoder demo on the DE2 and visually confirm the LCD shows
  the label line + `RUNNING` with a moving heartbeat → `PASS` (and that KEY0
  re-runs and the LCD updates). FAIL path optionally checked via a corrupt
  build.
- [ ] 4.3 Program the TX demo and confirm the LCD likewise.

## 4b. Refinement — minimum RUNNING-display window + always-on heartbeat

Surfaced by the stage-4 on-board test: the decode finishes in <1 ms, so the
`RUNNING` state + heartbeat flashed by invisibly and only `PASS` was ever seen.
This refinement holds the LCD's RUNNING *display* long enough to see, and makes
the heartbeat always-on. The verdict/LED/7-seg path is UNCHANGED.

- [x] 4b.1 In both wrappers add a `RUN_HOLD_CYC = (3 * CLK_HZ) / 2` (~1.5 s)
  counter, reloaded from the existing KEY0 restart pulse and counting down to 0,
  sized per wrapper's `CLK_HZ` (12.5 MHz decoder, 50 MHz TX). While nonzero, the
  LCD line 2 HOLDS `RUNNING`; then it shows the latched verdict.
- [x] 4b.2 Make the heartbeat always-on: a single free-running counter bit
  (~0.34 s) drives a blink glyph in EVERY state — `RUNNING *`/`RUNNING`,
  `PASS *`/`PASS`, `FAIL *`/`FAIL`.
- [x] 4b.3 Confirm the change is line-2-string-only: the self-check FSM,
  `pass_f`/`fail_f`/`done_f`, the LED/7-seg mapping, the verified cores, the
  golden vectors, and the `hd44780_lcd` core are all untouched.
- [x] 4b.4 GHDL gate unchanged-green: both self-check lanes (`turbo_decoder_de2`,
  `tx_chain_de2`) still PASS on golden and FAIL on `CORRUPT_IDX`; the
  `hd44780_lcd` byte-sequence TB still passes; `hdl/vectors/*` byte-identical.
- [x] 4b.5 Quartus II 13.0sp1 re-fit BOTH demos: still fit (LE delta ~ one extra
  counter), timing closes (12.5 MHz / 50 MHz), all `LCD_*` pins still mapped;
  both `.sof` produced (scratch, not committed).

## 5. Docs + validate

- [x] 5.1 Update `hdl/boards/de2/turbo_decoder_de2_README.md`,
  `tx_chain_de2_README.md`, and `hdl/boards/de2/README.md` to describe what the
  LCD shows (label + RUNNING/heartbeat → PASS/FAIL) alongside the LED/7-seg.
- [x] 5.2 `npx openspec validate add-fpga-lcd-status-display --strict` and
  `npx openspec validate --all --strict` pass.
