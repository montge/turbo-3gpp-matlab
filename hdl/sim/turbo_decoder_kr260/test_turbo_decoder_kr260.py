"""Self-check GHDL/cocotb lane for the KR260 board demo turbo_decoder_kr260_top.

Xilinx analog of the DE2 self-check lane (hdl/sim/turbo_decoder_de2/). The board
wrapper contains an on-chip golden ROM (the K=512, max_iter=2 row, reused
unchanged from the DE2 build) and a self-check FSM that drives the UNMODIFIED
turbo_decoder_top core: it streams the channel-LLR matrix d_a, waits out the
whole-block iterative decode, captures the K hard-decision c_out bits, compares
them bit-for-bit to the expected c, and latches a sticky PASS/FAIL verdict.

Unlike the DE2 wrapper, the KR260 top has NO clock or done port -- its only port
is LEDS(1 downto 0). The PL clock normally comes from the Zynq PS; here the sim
stub kr260_clocking_wrapper_sim.vhdl self-generates a 100 MHz clock (GHDL cannot
elaborate the zynq_ultra_ps_e PS block). So this test does NOT drive a clock --
it advances simulation time and polls the encoded LEDS:

    LEDS = "00"  -> running (or pre-reset)   [LED0 heartbeat phase = 0, LED1 off]
    LEDS = "01"  -> PASS   (LEDS(0)=1, LEDS(1)=0)
    LEDS = "10"  -> FAIL   (LEDS(1)=1)

The run-hold window is shrunk via -gRUN_HOLD_CYC_OVR (see the Makefile) so the
latched verdict reaches the LEDs within the budget; the heartbeat bit
(hb_cnt(25)) stays 0 for the whole sim, so "00" unambiguously means
"not yet decided".

  * with the default generic CORRUPT_IDX=-1 (real board behaviour) the
    self-check must reach PASS for the genuine K=512 golden vector;
  * with CORRUPT_IDX set to a valid index (one expected bit flipped) it must
    reach FAIL -- proving the comparator actually checks.

The expected verdict is read from COCOTB_EXPECT ("pass"/"fail"); test_runner.py
elaborates the wrapper twice (once per generic) and sets it. Run via
test_runner.py, or via the Makefile (which runs the default PASS case).
"""

import os

import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def reaches_expected_verdict(dut):
    expect = os.environ.get("COCOTB_EXPECT", "pass").strip().lower()

    # The clock is generated INSIDE the sim stub (no top-level clock port to
    # drive). At 100 MHz one cycle = 10 ns; poll every 100 ns (~10 cycles).
    # Whole-block K=512 decode is ~13k functional cycles + load/stream; a budget
    # of ~60k cycles (6000 polls * 10 cycles) covers it with wide margin.
    POLL_NS = 100
    MAX_POLLS = 6000

    verdict = None
    last = "?"
    for _ in range(MAX_POLLS):
        await Timer(POLL_NS, unit="ns")
        # str(LogicArray) is MSB-first: bits[0]=LEDS(1), bits[1]=LEDS(0).
        bits = str(dut.LEDS.value)
        last = bits
        if any(c not in "01" for c in bits):
            continue                       # pre-reset 'U'/'X' -- keep waiting
        led1, led0 = bits[0], bits[1]
        if led1 == "1":
            verdict = "fail"
            break
        if led0 == "1":
            verdict = "pass"
            break

    assert verdict is not None, (
        "self-check never latched a verdict on LEDS within the cycle budget "
        f"(last LEDS={last})"
    )
    assert verdict == expect, (
        f"expected self-check verdict '{expect}' but got '{verdict}'"
    )
