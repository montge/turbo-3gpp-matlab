"""LCD byte-sequence digit assertion for the turbo-decoder DE2 demo.

Proves the enriched LCD line 2 renders the right error-count DECIMAL plus the
static it= field, not just that a verdict latched. It reuses the byte-sequence
approach from hdl/sim/hd44780_lcd/test_hd44780_lcd.py: latch (lcd_rs, lcd_data)
on every lcd_en falling edge, reconstruct the most-recent complete line-2 DDRAM
refresh (the 16 data bytes following the 0xC0 set-DDRAM command), and assert the
ASCII string.

The wrapper holds "RUNNING" on the LCD for ~1.5 s on the board; the TB sets the
TEST-ONLY generic RUN_HOLD_CYC_OVR small (via SIM_ARGS in the runner) so the
latched verdict line reaches the LCD within the sim budget. CORRUPT_IDX selects
the golden PASS case (-1 -> "PASS e=000 it=2*") or a one-bit FAIL case
(a valid index -> "FAIL e=001 it=2*").

The decoder demo runs on a PLL-derived /4 clock; this TB drives CLOCK_50 and the
behavioural divider produces the functional clock. The heartbeat glyph occupies
column 16 and blinks slowly, so columns 1..15 are asserted exactly and column 16
must be '*' or ' '.

COCOTB_EXPECT_LINE2 tells the test the exact 16-char line-2 string to expect.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


SET_DDRAM_LINE2 = 0xC0


def _bit(sig) -> int:
    try:
        return int(sig.value)
    except ValueError:
        return 0


def _latest_line2(captured):
    for start in range(len(captured) - 17, -1, -1):
        rs0, b0 = captured[start]
        if rs0 == 0 and b0 == SET_DDRAM_LINE2:
            block = captured[start + 1:start + 17]
            if len(block) == 16 and all(rs == 1 for rs, _ in block):
                return "".join(chr(b) for _, b in block)
    return None


@cocotb.test()
async def line2_renders_expected(dut):
    expect = os.environ["COCOTB_EXPECT_LINE2"]
    assert len(expect) == 16, f"expected line2 must be 16 chars, got {len(expect)!r}"

    # Drive CLOCK_50; the wrapper's behavioural /4 divider derives the clock.
    cocotb.start_soon(Clock(dut.CLOCK_50, 20, unit="ns").start())
    dut.KEY.value = 0xF

    captured = []
    line2 = None
    prev_en = 0
    want_head = expect[:15]

    for _ in range(8_000_000):
        await RisingEdge(dut.CLOCK_50)
        en = _bit(dut.LCD_EN)
        if prev_en == 1 and en == 0:
            rs = int(dut.LCD_RS.value)
            data = int(dut.LCD_DATA.value)
            captured.append((rs, data))
            if len(captured) >= 17:
                cand = _latest_line2(captured)
                if cand is not None:
                    line2 = cand
                    if line2[:15] == want_head and line2[15] in ("*", " "):
                        break
        prev_en = en

    assert line2 is not None, "never captured a complete line-2 refresh"
    assert line2[:15] == want_head, (
        f"LCD line 2 = {line2!r}, expected cols 1..15 {want_head!r}"
    )
    assert line2[15] in ("*", " "), (
        f"LCD line 2 heartbeat col = {line2[15]!r}, expected '*' or ' '"
    )
    dut._log.info(f"LCD line 2 rendered {line2!r} (head matches {want_head!r})")
