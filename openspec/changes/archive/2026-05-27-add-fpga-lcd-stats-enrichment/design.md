# Design — add-fpga-lcd-stats-enrichment

Design/planning only — NO RTL lands in this change. This documents the exact
mechanism so the implementation increment is unambiguous.

## Context

Both DE2 board demos share the same self-check + display structure (see
`hdl/boards/de2/turbo_decoder_de2_top.vhdl` and `tx_chain_de2_top.vhdl`):

- A self-check FSM resets the UNMODIFIED core, streams the on-chip golden input,
  captures every `out_valid` output bit, and compares it bit-for-bit to the
  expected golden bit at the same index.
- **Today the comparator bails on the FIRST mismatch**: it sets `fail_f`/`done_f`
  and jumps to `CH_FAIL`, never looking at the remaining bits. So it knows only
  *whether* there was an error, never *how many*.
- A combinational `lcd_line2 : string(1 to 16)` is selected from
  `pass_f`/`fail_f`/`done_f` plus a `run_hold` window and an always-on `hb`
  heartbeat, and fed to the shared `hd44780_lcd` controller (`CLK_HZ => 12.5e6`
  on the decoder, `50e6` on the TX demo).
- The shared `hd44780_lcd` takes two `string(1 to 16)` line buffers and emits
  HD44780 character codes via `chr()`; it is **not touched** by this change.

The verdict path (`pass_f`/`fail_f`/`done_f` → LEDs + 7-seg) and its GHDL
oracle (`hdl/sim/{turbo_decoder_de2,tx_chain_de2}/`, which watch LEDR/LEDG/HEX)
must stay green and unchanged in meaning.

## Decision 1 — Error count is the primary stat; count, don't bail

The meaningful live stat is **how many output bits mismatched the golden
vector**. To produce it, the self-check comparator is extended to **count
mismatches across the whole output stream** instead of jumping to `CH_FAIL` on
the first one.

### FSM change (both wrappers, symmetric)

Add one register to each wrapper:

```
signal err_cnt : unsigned(ERR_W-1 downto 0) := (others => '0');  -- saturating
```

`ERR_W` is sized to the field width chosen below (3 decimal digits → max
displayable 999 → 10 bits is plenty; saturate at the display max so a wildly
wrong run still renders a sane field — see Decision 3). In the `CH_RUN` compare
arm, on each `out_valid` (`core_ov` / decoder, TX same) beat with
`cmp_idx < GV_K`/`GV_E`:

- **On mismatch** (`core_cout /= exp_bit(cmp_idx)`): `err_cnt <= err_cnt + 1`
  (saturating), but **do NOT jump to CH_FAIL** — keep streaming and comparing so
  the count accumulates over all bits.
- Continue advancing `cmp_idx` exactly as today.
- The framing checks (`out_last`/`last` must land exactly at the final index)
  are unchanged; an early/late/oversized framing condition still sets a framing-
  error flag.

At end-of-stream (the existing "last expected bit" branch fires, or the stream
ends), latch the verdict from the accumulated state — **verdict meaning
preserved exactly**:

```
PASS  iff  err_cnt = 0  AND  framing correct (out_last/last at the final index)
FAIL  otherwise
```

So `pass_f`/`fail_f`/`done_f` retain their current semantics (PASS = a fully
correct, correctly-framed block; FAIL = any mismatch or framing error). The only
behavioral difference is internal: the FSM now visits every output bit before
latching FAIL instead of short-circuiting. The whole-block latency is unchanged
(the decode already runs to completion; we were already in `CH_RUN` watching
`out_valid` to the end of the stream on the PASS path). The GHDL self-check
oracle that reads LEDR/LEDG/HEX is therefore unaffected: golden → PASS,
`CORRUPT_IDX` → FAIL, identical to today.

> A subtle but important consequence: with the bail-on-first-mismatch FSM, a
> single corrupted bit short-circuits and the *rest* of the stream is never
> compared. The counting FSM compares the full stream, so for a multi-bit
> corruption it reports the true total. The `CORRUPT_IDX` test path flips one
> bit → `err_cnt` ends at exactly 1 → still FAIL, now with `err=001` on the LCD.

## Decision 2 — Iterations: a STATIC info field, not a dynamic count

`turbo_decoder_de2_top` instantiates the core with
`MAX_ITERATIONS => GV_MAX_ITER` (currently 2), and there is **no CRC early-
termination on the board** (that is `turbo_decoder_term_top`, a separate planned
demo). So "iterations performed" is a **compile-time constant**, the same on
every run.

We therefore display it as a **static configuration field** `it=N`, sourced
directly from the `GV_MAX_ITER`/`MAX_ITERATIONS` constant (no new counter, no
runtime measurement), and document it as "configured max iterations" — never as
a measured dynamic count.

- **Decoder demo:** show `it=N` if it fits within the 16-char budget after the
  error count (see Decision 3). This is informative because the decoder *does*
  iterate a fixed number of times.
- **TX demo:** the TX chain does **not** iterate at all, so there is **no
  iteration field** — line 2 carries only `err=NNN` + heartbeat.

A *dynamic* iteration count is explicitly deferred to a future term/CRC board
demo and is out of scope here.

## Decision 3 — `uint`→decimal-ASCII helper + line-2 field layout

### The helper

The `hd44780_lcd` consumes character codes; an integer count must become ASCII
decimal digits. Add a tiny shared, pure helper — a VHDL function (placed either
in a small shared package alongside the board components, or inline in each
wrapper; final placement decided at implementation, leaning toward a shared
function so both wrappers and the LCD TB use one definition):

```
-- Render an unsigned value as an N-digit zero-padded decimal ASCII string,
-- most-significant digit first. Saturates to all-9s if the value exceeds the
-- field (so the field width is a hard guarantee for the 16-char line).
function uint_to_ascii(value : unsigned; n_digits : integer) return string;
```

Implementation is repeated divide/mod-by-10 (or successive subtraction) over a
small fixed `n_digits` — combinational, a handful of LE, no M4K. Because the
counts are bounded (K=512 decoder, E=400 TX), **3 digits** covers every real
value; the saturate-to-999 guard only matters for a pathological corruption and
keeps the rendered field at a fixed width.

### Line-2 layout (≤ 16 chars, hard constraint)

Line 1 is the existing fixed label (`3GPP TURBO K=512` / `3GPP TX K=40`) and is
unchanged. Line 2 is rebuilt to embed the count. Every branch must be **exactly
16 characters** (the `hd44780_lcd` writes 16 codes per line); the heartbeat
glyph (`*`/space) occupies the last column as today.

**TX demo (no iterations), 16 cols:**

```
col:    1234567890123456
PASS:  "PASS err=000   *"   (heartbeat in col 16; space when off)
FAIL:  "FAIL err=042   *"
RUN:   "RUNNING        *"   (count not meaningful until done; show RUNNING)
```

`PASS err=000` = 12 chars, `+` padding `+` heartbeat = 16. Comfortable fit.

**Decoder demo (with the static iter field), 16 cols:**

```
col:    1234567890123456
PASS:  "PASS e=000 it=2*"   (verdict + err + static iter + heartbeat)
FAIL:  "FAIL e=042 it=2*"
RUN:   "RUNNING        *"
```

To fit verdict + error + `it=` + heartbeat in 16 columns the decoder uses the
short key `e=` (still unambiguous next to `it=`); `PASS e=000 it=2` = 15 chars +
heartbeat = 16. **Field-width arithmetic (pinned):**
`PASS`(4) + space(1) + `e=`(2) + `000`(3) + space(1) + `it=`(2) + `N`(1) =
14, + a trailing space + heartbeat = 16. If a future config needs `it=` wider
than one digit, the implementation drops `it=` first (error count is primary) —
this is the documented open question below.

`RUNNING` keeps its current presentation (the count is not final until the
verdict latches; showing a partial count during the held RUNNING window would be
misleading), with the heartbeat in the last column. The existing `run_hold`
minimum-display window and always-on heartbeat are retained verbatim.

The verdict-selection structure stays the same `when ... else` ladder, just with
the error/iter substring spliced in via `uint_to_ascii(err_cnt, 3)` (and the
constant iter digit on the decoder).

## What stays untouched (additive guarantee)

- The verified cores `turbo_decoder_top` and `tx_chain_top` — instantiated with
  the same generics, no port or generic change.
- The on-chip golden vectors (`turbo_decoder_golden_pkg`, `tx_chain_golden_pkg`)
  — byte-identical.
- The PASS/FAIL verdict *meaning* and the `pass_f`/`fail_f`/`done_f` →
  LEDR/LEDG/HEX mapping — bit-for-bit identical outputs for any given run.
- The shared `hd44780_lcd` controller — no edit; it still takes two 16-char
  strings and emits the same byte protocol.
- The `run_hold` RUNNING-display window and the always-on heartbeat.

## Verification

Dual gate, same as the prior LCD change; on-board reads are hardware-gated.

1. **GHDL self-check lanes stay green (verdict oracle).** Both
   `hdl/sim/turbo_decoder_de2/` and `hdl/sim/tx_chain_de2/` still PASS on the
   golden vector (`CORRUPT_IDX=-1`) and FAIL on a corrupted bit
   (`CORRUPT_IDX=valid`). These read LEDR/LEDG/HEX and are unaffected by the
   line-2 reformat — they confirm the verdict meaning is preserved.

2. **GHDL byte-sequence assertion of the rendered digits (new coverage).**
   Extend the byte-sequence verification approach used by
   `hdl/sim/hd44780_lcd/test_hd44780_lcd.py` (which latches `(lcd_rs, lcd_data)`
   on every `lcd_en` falling edge and asserts the emitted character stream) to
   the demo wrappers, so the TB asserts that for a **known error count** the
   line-2 character stream contains the right `err=NNN` digits:
   - **PASS case** (golden): line 2 resolves to the `err=000` (`e=000`) string.
   - **FAIL-with-count case** (`CORRUPT_IDX` set to flip one bit): line 2
     resolves to `err=001` — proving the counter and the `uint_to_ascii` digit
     formatting render the correct decimal, not just *a* FAIL.
   - The `uint_to_ascii` helper is additionally unit-checked across a few values
     (0, mid, max/saturation) so the digit conversion is asserted directly.

3. **Quartus II 13.0sp1 fit, both demos.** Re-fit `turbo_decoder_de2` and
   `tx_chain_de2`: still fit the EP2C35, all `LCD_*` pins still map, timing still
   closes (12.5 MHz PLL / 50 MHz). Record the LE / M4K delta — expected to be a
   small positive LE delta (one saturating counter + the combinational digit
   conversion) and **zero M4K change**.

4. **On-board (hardware-gated).** Program the enriched decoder demo and confirm
   line 2 shows `PASS e=000 it=2` with the heartbeat (and a corrupt build shows
   `FAIL e=NNN`); program the TX demo (closing deferred task 4.3) and confirm
   `PASS err=000` + heartbeat, KEY0 re-runs both.

## Risks / open questions

- **16-char budget on the decoder.** Verdict + `err` + `it` + heartbeat is
  tight. The pinned layout (`PASS e=000 it=2*`) fits at one iter digit. **Open
  question:** if a larger configured `MAX_ITERATIONS` ever needs a 2-digit
  `it=`, do we (a) drop the `it=` field (error count is primary), (b) shorten
  the verdict token, or (c) accept a 2-digit `it=` by trimming a pad space? The
  recommendation is (a): the static iter field is the first thing to go.
- **Digit-formatting cost.** Repeated divide/mod-by-10 over 3 fixed digits is
  trivial combinational logic (tens of LE); negligible vs. the existing LE
  margins. No timing risk on the slow LCD-refresh path. Low.
- **Counter saturation semantics.** Saturating at the 3-digit max (999) keeps
  the field width fixed even for a pathological all-wrong stream; real values are
  bounded well under that (≤ 512 / ≤ 400). Documented, not a correctness risk —
  the verdict is FAIL the moment `err_cnt > 0` regardless of the displayed cap.
- **Whether to show `it=` at all.** Some reviewers may prefer the cleaner
  `PASS err=000` (no static field) on the decoder too, for symmetry with the TX
  demo. Decision: keep the static `it=` on the decoder (it conveys real config
  info), drop it on TX (no iterations). Revisit at implementation if the layout
  feels cramped on the physical panel.
- **RUNNING-window count display.** We intentionally do NOT show a partial count
  during the held RUNNING window (it is not final). Confirmed acceptable; the
  count appears with the latched verdict.
