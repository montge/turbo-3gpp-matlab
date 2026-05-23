"""Self-check GHDL/cocotb lane for the DE2 board demo tx_chain_de2_top.

The board wrapper contains an on-chip golden ROM (the K=40 row of
hdl/vectors/tx_chain.csv) and a self-check FSM that drives the UNMODIFIED
tx_chain_top core, captures its output stream, compares it bit-for-bit to the
expected e, and latches a sticky PASS / FAIL on the LED + 7-seg outputs.

This module asserts the wrapper reaches the correct verdict:

  * with the default generic CORRUPT_IDX=-1 (the real board behaviour) the
    self-check must reach PASS for the genuine golden vector;
  * with CORRUPT_IDX set to a valid index (one expected bit flipped) it must
    reach FAIL -- proving the comparator actually checks.

The verdict the harness selects is read from the COCOTB_EXPECT environment
variable ("pass" or "fail"); test_runner.py elaborates the wrapper twice (once
per generic) and sets it. Run via test_runner.py, or via the Makefile (which
runs the default PASS case).
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


# 7-seg active-low patterns from hdl/boards/hex7seg.vhdl.
SEG_A = "0001000"  # 0xA
SEG_5 = "0010010"  # 0x5
SEG_F = "0001110"  # 0xF
SEG_0 = "1000000"  # 0x0


def _seg(sig) -> str:
    return sig.value.binstr if hasattr(sig.value, "binstr") else str(sig.value)


@cocotb.test()
async def reaches_expected_verdict(dut):
    expect = os.environ.get("COCOTB_EXPECT", "pass").strip().lower()

    cocotb.start_soon(Clock(dut.CLOCK_50, 20, unit="ns").start())

    # KEY is active-low; idle high (released). The FSM free-runs from CH_RESET
    # on power-up, so no key press is needed; hold KEY high throughout.
    dut.KEY.value = 0xF

    # Run long enough for the K=40 / E=400 vector to fully stream out.
    # tx_chain latency is well under a few thousand cycles for K=40.
    done = False
    verdict = None
    for _ in range(20000):
        await RisingEdge(dut.CLOCK_50)
        ledr = dut.LEDR.value
        ledg = dut.LEDG.value
        pass_f = int(ledg) & 0x1            # LEDG[0]
        fail_f = int(ledr) & 0x1            # LEDR[0]
        done_f = (int(ledr) >> 1) & 0x1     # LEDR[1]
        if done_f == 1:
            done = True
            verdict = "pass" if pass_f == 1 else ("fail" if fail_f == 1 else "?")
            break

    assert done, "self-check never reached DONE within the cycle budget"
    assert verdict in ("pass", "fail"), f"DONE but ambiguous verdict ({verdict})"

    # Cross-check the 7-seg status code matches the LED verdict.
    if verdict == "pass":
        assert _seg(dut.HEX0) == SEG_5 and _seg(dut.HEX1) == SEG_A, (
            f"pass verdict but HEX!=A5: HEX1={_seg(dut.HEX1)} HEX0={_seg(dut.HEX0)}"
        )
    else:
        assert _seg(dut.HEX0) == SEG_F and _seg(dut.HEX1) == SEG_F, (
            f"fail verdict but HEX!=FF: HEX1={_seg(dut.HEX1)} HEX0={_seg(dut.HEX0)}"
        )

    assert verdict == expect, (
        f"expected self-check verdict '{expect}' but got '{verdict}'"
    )
