"""Self-check GHDL/cocotb lane for the DE2 board demo turbo_decoder_de2_top.

The board wrapper contains an on-chip golden ROM (the K=512, max_iter=2 row of
hdl/vectors/turbo_decoder_top.csv) and a self-check FSM that drives the
UNMODIFIED turbo_decoder_top core, streams the channel-LLR matrix d_a, waits out
the whole-block iterative decode, captures the K hard-decision c_out bits,
compares them bit-for-bit to the expected c, and latches a sticky PASS / FAIL on
the LED + 7-seg outputs.

The PLL is the SIM behavioural divide-by-4 (pll_12p5_sim.vhdl): GHDL cannot
elaborate the Altera altpll hard block, so the demo runs on CLOCK_50 / 4. The
self-check is clock-rate-agnostic (fully synchronous), so this is functionally
identical to the synthesised 12.5 MHz PLL output for the bit-exact verdict.

This module asserts the wrapper reaches the correct verdict:

  * with the default generic CORRUPT_IDX=-1 (the real board behaviour) the
    self-check must reach PASS for the genuine K=512 golden vector;
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

    # Drive the 50 MHz CLOCK_50; the SIM PLL divides it by 4 to the functional
    # ~12.5 MHz demo clock. The demo therefore advances one functional cycle per
    # 4 CLOCK_50 edges, so the cycle budget below must cover ~4x the functional
    # whole-block decode latency.
    cocotb.start_soon(Clock(dut.CLOCK_50, 20, unit="ns").start())

    # KEY is active-low; idle high (released). The FSM free-runs from CH_RESET
    # on power-up, so no key press is needed; hold KEY high throughout.
    dut.KEY.value = 0xF

    # Whole-block K=512 decode: H = 2*max_iter = 4 half-iterations, each a
    # constituent run (~3*(K+3) ~ 1.5k beats) + interleave (~K), times the /4 PLL
    # ratio, plus load + output streaming. Budget well above the worst case.
    # Functional cycles ~ H*(5*K + 64) + 4*K + overhead ~ 4*2624 + ~2.5k ~ 13k;
    # x4 for the PLL divide + margin.
    done = False
    verdict = None
    for _ in range(120000):
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
