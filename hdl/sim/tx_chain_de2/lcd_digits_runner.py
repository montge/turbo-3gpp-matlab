"""Two-case LCD digit-assertion driver for the TX DE2 demo.

Elaborates the wrapper twice (with a small RUN_HOLD_CYC_OVR so the latched
verdict line reaches the LCD within the sim budget) and asserts the exact
16-char line-2 string the enriched display renders:

  1. CORRUPT_IDX = -1  (golden)            -> "PASS err=000   *"
  2. CORRUPT_IDX = 5   (one bit flipped)   -> "FAIL err=001   *"

This proves the err_cnt counter + uint_to_ascii render the correct decimal on
the LCD, not just that a verdict latched. Run after sourcing scripts/hdl_env.sh:

    python lcd_digits_runner.py
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Heartbeat occupies col 16; it blinks, so accept either '*' or ' ' there. We
# pin the heartbeat-on phase here and the test waits until the matching refresh
# appears, so we assert the '*' phase deterministically.
RUN_HOLD = 64  # tiny RUNNING-hold so the verdict line shows almost immediately


def run_case(corrupt_idx: int, expect_line2: str) -> None:
    sim_args = (
        f"-gCORRUPT_IDX={corrupt_idx} -gRUN_HOLD_CYC_OVR={RUN_HOLD} "
        f"--vcd=tx_chain_de2_lcd.vcd"
    )
    cmd = [
        "make",
        "SIM=ghdl",
        "COCOTB_TEST_MODULES=test_tx_chain_de2_lcd",
        f"COCOTB_EXPECT_LINE2={expect_line2}",
        f"SIM_ARGS={sim_args}",
    ]
    subprocess.run(["make", "clean"], cwd=HERE, check=False)
    res = subprocess.run(cmd, cwd=HERE)
    if res.returncode != 0:
        raise SystemExit(
            f"LCD-digit case CORRUPT_IDX={corrupt_idx} "
            f"(expect {expect_line2!r}) FAILED (make rc={res.returncode})"
        )


def main() -> int:
    print("== LCD case 1: golden -> 'PASS err=000   *' ==")
    run_case(-1, "PASS err=000   *")
    print("== LCD case 2: one-bit corrupt -> 'FAIL err=001   *' ==")
    run_case(5, "FAIL err=001   *")
    print("== both LCD line-2 digit assertions matched ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
