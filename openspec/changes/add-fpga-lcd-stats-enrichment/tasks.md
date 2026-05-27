# Tasks — add-fpga-lcd-stats-enrichment

Dual gate per the LCD demo pattern: **GHDL** (both demo self-check lanes
unchanged-green + a byte-sequence digit assertion) + **Quartus II 13.0sp1 fit**
(both demos still fit, `LCD_*` pins map, timing closes); on-board reads are
hardware-gated. The verified cores (`turbo_decoder_top`, `tx_chain_top`), the
golden vectors, the PASS/FAIL verdict *meaning*, and the LED / 7-seg mapping stay
UNMODIFIED throughout. Error count is the PRIMARY stat; the decoder's `it=N` is a
STATIC config field (not a dynamic count); the TX demo has no iteration field.

## 1. `uint`→ASCII digit helper + line-2 layout

- [x] 1.1 Add a `uint`→decimal-ASCII format helper (a pure VHDL function,
  preferably a small shared definition both wrappers + the TB use): renders an
  unsigned value as a fixed-width (3-digit) zero-padded decimal ASCII string,
  MSD first, saturating to all-9s above the field so the width is guaranteed.
- [x] 1.2 Pin the ≤16-char line-2 field layout: TX demo
  `PASS err=000   *` / `FAIL err=NNN   *`; decoder demo
  `PASS e=000 it=2*` / `FAIL e=NNN it=2*` (verdict + error + static `it=` +
  heartbeat in col 16). `RUNNING        *` unchanged (count shown only at the
  latched verdict). Every branch exactly 16 chars.

## 2. Wire the error count (+ static iter on the decoder) into both wrappers

- [x] 2.1 In `turbo_decoder_de2_top` and `tx_chain_de2_top` add a saturating
  `err_cnt` register and extend the `CH_RUN` comparator to **count** output-bit
  mismatches across the full stream (increment `err_cnt`, keep streaming)
  instead of bailing to `CH_FAIL` on the first one. Latch the verdict at end-of-
  stream: PASS iff `err_cnt = 0` AND framing (`out_last`/`last` at the final
  index) is correct; FAIL otherwise. `pass_f`/`fail_f`/`done_f` meaning is
  preserved exactly.
- [x] 2.2 Splice the rendered count into line 2 via `uint_to_ascii(err_cnt, 3)`
  in both wrappers; on the decoder also splice the STATIC `it=N` from the
  `GV_MAX_ITER`/`MAX_ITERATIONS` constant (TX demo: no iteration field). Line-2
  string-selection ladder otherwise unchanged (same `run_hold` window + always-
  on heartbeat).
- [x] 2.3 Confirm additive-only: the verified cores, the golden vectors, the
  PASS/FAIL verdict meaning, the LED / 7-seg mapping, and the `hd44780_lcd`
  controller are untouched; only the FSM comparator (count vs. bail), the
  line-2 string, and the new helper change.

## 3. Verification — GHDL gates

- [x] 3.1 Both self-check lanes (`hdl/sim/turbo_decoder_de2/`,
  `hdl/sim/tx_chain_de2/`) still PASS on the golden vector and FAIL on
  `CORRUPT_IDX`; the `hdl/sim/hd44780_lcd/` byte-sequence TB still passes;
  `hdl/vectors/*` byte-identical.
- [x] 3.2 Add a byte-sequence digit assertion (extending the
  `test_hd44780_lcd.py` latch-on-`lcd_en`-fall approach to the wrappers): assert
  line 2 renders `err=000` on the golden PASS case and `err=001` on a one-bit
  `CORRUPT_IDX` FAIL case (proving the counter + `uint_to_ascii` emit the right
  decimal); unit-check `uint_to_ascii` at 0 / mid / saturation.

## 4. Verification — Quartus fit (both demos)

- [x] 4.1 Quartus II 13.0sp1 re-fit `turbo_decoder_de2` and `tx_chain_de2`: both
  fit the EP2C35, all `LCD_*` pins map, timing closes. Both `.sof` produced
  (scratch, not committed). **Results:** decoder 12,759 LE (38%) / 162,206 mem
  bits (34%) / 1 PLL, worst setup slack **+11.151 ns** @ 12.5 MHz — LE/M4K delta
  ~0 vs the pre-enrichment fit (the err counter + render are tiny next to the
  K=512 core). TX 1,785 LE (5%) / 1,088 mem bits / 0 PLL, worst setup slack
  **+1.039 ns** @ 50 MHz. NOTE: the first TX fit came in at **-0.282 ns**
  (`err_cnt[hi] → uint_to_ascii (3× div/mod) → hd44780 r_data`); registering the
  rendered `err_str` one cycle (off the divider chain, functionally invisible —
  err_cnt is stable ~1.5 s before the verdict line shows) recovered it to
  +1.039 ns. Same register applied symmetrically to the decoder.

## 5. On-board (HARDWARE-GATED — user's board)

- [ ] 5.1 Program the enriched decoder demo; confirm LCD line 2 shows
  `PASS e=000 it=2` with the heartbeat (a corrupt build shows `FAIL e=NNN`), and
  KEY0 re-runs.
- [ ] 5.2 Close the deferred `add-fpga-lcd-status-display` task 4.3: program the
  TX demo and visually confirm line 1 label + line 2 `RUNNING`/heartbeat →
  `PASS err=000`, and KEY0 re-runs.

## 6. Docs + validate

- [x] 6.1 Update `hdl/boards/de2/turbo_decoder_de2_README.md`,
  `tx_chain_de2_README.md`, and `hdl/boards/de2/README.md` to describe the new
  `err=NNN` field (and the decoder's static `it=N`) on LCD line 2.
- [x] 6.2 `npx openspec validate add-fpga-lcd-stats-enrichment --strict` and
  `npx openspec validate --all --strict` pass (34/34).
