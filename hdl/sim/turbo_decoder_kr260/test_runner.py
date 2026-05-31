"""Two-case GHDL self-check driver for the KR260 turbo-decoder board demo.

Xilinx analog of hdl/sim/turbo_decoder_de2/test_runner.py. Runs the cocotb lane
twice, via the same proven Makefile flow the other lanes use, and asserts the
self-check verdict in each case:

  1. CORRUPT_IDX = -1  (default; the real board behaviour) -> must reach PASS
     for the genuine K=512 golden vector;
  2. CORRUPT_IDX = 7   (one expected output bit flipped)   -> must reach FAIL,
     proving the comparator actually checks.

This is the sim gate for the KR260 board stage. The default `make` in this
directory runs case 1 only (the regression entry point picked up by
scripts/run_all_hdl_lanes.sh); this script additionally exercises case 2.

Run it directly (after sourcing scripts/hdl_env.sh):

    python test_runner.py
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run_case(corrupt_idx: int, expect: str) -> None:
    # RUN_HOLD_CYC_OVR is repeated here because a command-line SIM_ARGS
    # assignment overrides the Makefile default; the encoded LEDs need the short
    # run-hold window to expose the latched verdict within the sim budget.
    sim_args = (
        f"-gCORRUPT_IDX={corrupt_idx} -gRUN_HOLD_CYC_OVR=8 "
        "--vcd=turbo_decoder_kr260_top.vcd"
    )
    cmd = [
        "make",
        "SIM=ghdl",
        f"COCOTB_EXPECT={expect}",
        f"SIM_ARGS={sim_args}",
    ]
    # Fresh build each case so the generic override re-elaborates.
    subprocess.run(["make", "clean"], cwd=HERE, check=False)
    res = subprocess.run(cmd, cwd=HERE)
    if res.returncode != 0:
        raise SystemExit(
            f"case CORRUPT_IDX={corrupt_idx} (expect {expect}) FAILED "
            f"(make rc={res.returncode})"
        )


def main() -> int:
    print("== case 1: CORRUPT_IDX=-1 -> expect PASS ==")
    run_case(-1, "pass")
    print("== case 2: CORRUPT_IDX=7  -> expect FAIL ==")
    run_case(7, "fail")
    print("== both self-check cases reached the expected verdict ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
