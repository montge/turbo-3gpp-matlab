"""Dual-frequency byte-sequence driver for the shared hd44780_lcd controller.

Runs the cocotb lane twice via the same proven Makefile flow the other lanes
use, once per clock domain the controller must serve, and in each case asserts
the emitted HD44780 command/data byte SEQUENCE plus the CLK_HZ-scaled power-on
settle:

  1. TOPLEVEL = hd44780_lcd_tb_top  -> CLK_HZ = 12_500_000 (decoder domain)
  2. TOPLEVEL = hd44780_lcd_tb_fast -> CLK_HZ = 50_000_000 (TX domain)

CLK_HZ is baked into each harness via generic map (mcode does not recompute
generic-derived elaboration constants on a run-step -g override), so the clock
domain is selected by TOPLEVEL. The byte sequence is identical at both clocks
(it is clock-independent), while the realized power-on settle differs by exactly
the 4:1 frequency ratio -- the test asserts each realized count equals
ceil(CLK_HZ * 20_000 us / 1e6), proving the generic delay scaling in simulation,
not just at one frequency.

Run it directly (after sourcing scripts/hdl_env.sh):

    python test_runner.py

The default `make` in this directory runs case 1 only (the regression entry
point picked up by scripts/run_all_hdl_lanes.sh); this script also runs case 2.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run_case(toplevel: str, clk_hz: int) -> None:
    cmd = [
        "make",
        "SIM=ghdl",
        f"TOPLEVEL={toplevel}",
        f"COCOTB_EXPECT_CLK_HZ={clk_hz}",
    ]
    # Fresh build each case so the selected top re-elaborates.
    subprocess.run(["make", "clean"], cwd=HERE, check=False)
    res = subprocess.run(cmd, cwd=HERE)
    if res.returncode != 0:
        raise SystemExit(
            f"case TOPLEVEL={toplevel} (CLK_HZ={clk_hz}) FAILED "
            f"(make rc={res.returncode})"
        )


def main() -> int:
    print("== case 1: hd44780_lcd_tb_top  CLK_HZ=12_500_000 (decoder domain) ==")
    run_case("hd44780_lcd_tb_top", 12_500_000)
    print("== case 2: hd44780_lcd_tb_fast CLK_HZ=50_000_000 (TX domain) ==")
    run_case("hd44780_lcd_tb_fast", 50_000_000)
    print("== both clock domains emitted the expected HD44780 byte sequence "
          "with correctly scaled delays ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
