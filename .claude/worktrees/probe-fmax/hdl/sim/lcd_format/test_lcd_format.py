"""Unit-check for the shared lcd_format_pkg.uint_to_ascii helper.

cocotb cannot call a VHDL function directly, so lcd_format_tb_top renders three
representative values at elaboration and exposes each 3-digit ASCII result as
byte ports. This test reads them and asserts the decimal string:

  uint_to_ascii(0,    3) -> "000"   (zero)
  uint_to_ascii(42,   3) -> "042"   (mid value, zero-padded)
  uint_to_ascii(1234, 3) -> "999"   (saturation: value > 999 caps the field)

This directly proves the digit conversion (MSD-first, zero-pad, saturate) that
the board wrappers splice into LCD line 2 via uint_to_ascii(err_cnt, 3).
"""

import cocotb
from cocotb.triggers import Timer


def _txt(msd, mid, lsd) -> str:
    return "".join(chr(int(s.value)) for s in (msd, mid, lsd))


@cocotb.test()
async def renders_expected_decimal(dut):
    # Pure combinational outputs; let deltas settle.
    await Timer(1, unit="ns")

    got0 = _txt(dut.d0_msd, dut.d0_mid, dut.d0_lsd)
    got1 = _txt(dut.d1_msd, dut.d1_mid, dut.d1_lsd)
    got2 = _txt(dut.d2_msd, dut.d2_mid, dut.d2_lsd)

    assert got0 == "000", f"uint_to_ascii(0,3) = {got0!r}, expected '000'"
    assert got1 == "042", f"uint_to_ascii(42,3) = {got1!r}, expected '042'"
    assert got2 == "999", f"uint_to_ascii(1234,3) = {got2!r}, expected '999' (saturated)"

    dut._log.info(
        f"uint_to_ascii unit-check OK: 0->{got0!r}, 42->{got1!r}, 1234->{got2!r}"
    )
