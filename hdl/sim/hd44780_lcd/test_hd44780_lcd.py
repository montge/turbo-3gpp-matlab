"""Byte-sequence GHDL/cocotb lane for the shared hd44780_lcd controller.

The HD44780 LCD is an OUTPUT-only device: it emits, it never returns data, so
"bit-exact" verification here is asserting the emitted command/data byte
SEQUENCE (with the per-byte lcd_rs route, lcd_rw=0, and the lcd_en strobe
framing) -- not a golden-vector CSV compare.

Each HD44780 write latches the data bus on the FALLING edge of lcd_en. This test
samples (lcd_rs, lcd_data) at every lcd_en 1->0 transition and asserts the
captured stream against the expected init + sample-message sequence:

  init    : 0x38, 0x0C, 0x01, 0x06            (all rs=0 commands)
  line 1  : 0x80 (set DDRAM 0x00, rs=0), then "HELLO LCD WORLD!" 16 bytes rs=1
  line 2  : 0xC0 (set DDRAM 0x40, rs=0), then "0123456789ABCDEF" 16 bytes rs=1

The line strings are fixed in hd44780_lcd_tb_top.vhdl (cocotb cannot drive a
VHDL string port). The CLK_HZ generic is varied by test_runner.py to prove the
delay scaling; this module additionally measures the realized power-on settle
(cycles before the first strobe) and checks it equals the ceil(CLK_HZ*us/1e6)
the controller is specced to produce, so the scaling is asserted in sim.

COCOTB_EXPECT_CLK_HZ tells the test which frequency the harness elaborated at,
so it can compute the expected delay counts.
"""

import math
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


LINE1 = "HELLO LCD WORLD!"
LINE2 = "0123456789ABCDEF"

# HD44780 worst-case delays the controller is specced to (microseconds).
US_POWERON = 20_000
US_CLEAR = 2_000
US_SHORT = 50


def _byte(sig) -> int:
    return int(sig.value)


def _bit(sig) -> int:
    """Read a 1-bit signal as 0/1; treat X/U/Z as 0 (pre-strobe idle)."""
    try:
        return int(sig.value)
    except ValueError:
        return 0


def _expected_sequence():
    """List of (rs, byte) the controller must emit, in order."""
    seq = []
    # init commands
    for b in (0x38, 0x0C, 0x01, 0x06):
        seq.append((0, b))
    # line 1: set-DDRAM 0x80 then the 16 chars
    seq.append((0, 0x80))
    for ch in LINE1:
        seq.append((1, ord(ch)))
    # line 2: set-DDRAM 0xC0 then the 16 chars
    seq.append((0, 0xC0))
    for ch in LINE2:
        seq.append((1, ord(ch)))
    return seq


def _us_cycles(clk_hz: int, us: int) -> int:
    c = math.ceil((clk_hz * us) / 1_000_000)
    return c if c >= 1 else 1


@cocotb.test()
async def emits_expected_byte_sequence(dut):
    clk_hz = int(os.environ.get("COCOTB_EXPECT_CLK_HZ", "50000000"))

    # 1 ns clock; cycle-accurate counting is by RisingEdge, so the literal
    # period is irrelevant to the cycle-count assertions.
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # One reset cycle, then release: the controller (re)runs init from rst.
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    expected = _expected_sequence()
    captured = []

    # Count cycles to the first enable rise to verify the power-on settle scale.
    poweron_cycles = 0
    saw_first_en = False

    prev_en = 0
    # Cycle budget: power-on settle + the ~1.5 ms display-clear + one full
    # refresh pass of ~38 writes at ~C_SHORT cycles each, with generous margin
    # (each write also spends a few cycles in the E-strobe framing states).
    budget = (
        _us_cycles(clk_hz, US_POWERON)
        + _us_cycles(clk_hz, US_CLEAR)
        + 80 * _us_cycles(clk_hz, US_SHORT)
        + 20_000
    )
    for _ in range(budget):
        await RisingEdge(dut.clk)
        en = _bit(dut.lcd_en)

        if not saw_first_en:
            if en == 1:
                saw_first_en = True
            else:
                poweron_cycles += 1

        # latch on the falling edge of E
        if prev_en == 1 and en == 0:
            rs = int(dut.lcd_rs.value)
            data = _byte(dut.lcd_data)
            captured.append((rs, data))
            # lcd_rw must be tied low for every write
            assert int(dut.lcd_rw.value) == 0, "lcd_rw must be 0 (write-only)"
            if len(captured) >= len(expected):
                break
        prev_en = en

    # --- byte-sequence assertion ---
    assert len(captured) >= len(expected), (
        f"only captured {len(captured)} writes, expected >= {len(expected)}"
    )
    for i, (exp, got) in enumerate(zip(expected, captured)):
        assert got == exp, (
            f"write #{i}: expected (rs={exp[0]}, 0x{exp[1]:02X}) "
            f"got (rs={got[0]}, 0x{got[1]:02X})"
        )

    # --- panel power + backlight tied high ---
    assert int(dut.lcd_on.value) == 1, "lcd_on must be driven '1'"
    assert int(dut.lcd_blon.value) == 1, "lcd_blon must be driven '1'"

    # --- CLK_HZ delay-scaling assertion ---
    # The controller burns ceil(CLK_HZ*20000us/1e6) cycles of power-on settle
    # before the first strobe. We count the cycles where lcd_en was still 0
    # before the first rise; allow a couple-cycle slack for the sequencer
    # handoff (W_IDLE -> W_SETUP latches data one cycle before E rises).
    exp_poweron = _us_cycles(clk_hz, US_POWERON)
    assert abs(poweron_cycles - exp_poweron) <= 4, (
        f"power-on settle {poweron_cycles} cycles, expected ~{exp_poweron} "
        f"(= ceil({clk_hz}*{US_POWERON}us/1e6)); CLK_HZ scaling wrong"
    )
    # The realized settle must cover the >=15 ms HD44780 window at this clock.
    min_15ms = _us_cycles(clk_hz, 15_000)
    assert poweron_cycles >= min_15ms, (
        f"power-on settle {poweron_cycles} < 15 ms ({min_15ms} cycles) at "
        f"CLK_HZ={clk_hz}"
    )

    dut._log.info(
        f"CLK_HZ={clk_hz}: power-on settle {poweron_cycles} cycles "
        f"(>= 15 ms = {min_15ms}); {len(captured)} bytes matched the "
        f"HD44780 init + sample-message sequence."
    )
