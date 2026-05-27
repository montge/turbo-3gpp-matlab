"""LCD byte-sequence digit assertion for the TX DE2 demo.

This lane proves the enriched LCD line 2 renders the right error-count DECIMAL,
not just that a verdict latched. It reuses the byte-sequence approach from
hdl/sim/hd44780_lcd/test_hd44780_lcd.py: it latches (lcd_rs, lcd_data) on every
lcd_en falling edge, reconstructs the most-recent complete line-2 DDRAM refresh
(the 16 data bytes following the 0xC0 set-DDRAM command), and asserts the
ASCII string.

The wrapper holds "RUNNING" on the LCD for ~1.5 s on the board; the TB sets the
TEST-ONLY generic RUN_HOLD_CYC_OVR small (via SIM_ARGS in the runner) so the
latched verdict line reaches the LCD within the sim budget. CORRUPT_IDX selects
the golden PASS case (-1 -> "PASS err=000   *") or a one-bit FAIL case
(a valid index -> "FAIL err=001   *").

COCOTB_EXPECT_LINE2 tells the test the exact 16-char line-2 string to expect.
The heartbeat glyph occupies column 16 and blinks on a slow (~0.34 s) phase that
does not toggle within the sim budget, so columns 1..15 (the verdict + the
err=NNN digits) are asserted exactly and column 16 must be '*' or ' '.
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
    """Return the most-recent complete 16-char line-2 refresh, or None.

    A line-2 refresh is a 0xC0 set-DDRAM command (rs=0) followed by exactly 16
    data bytes (rs=1).
    """
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

    cocotb.start_soon(Clock(dut.CLOCK_50, 20, unit="ns").start())
    dut.KEY.value = 0xF

    captured = []
    line2 = None
    prev_en = 0

    # Match cols 1..15 exactly; col 16 (heartbeat) may be '*' or ' '.
    want_head = expect[:15]

    for _ in range(4_000_000):
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
