from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "internal_interleaver.csv"
)


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_str, d0, step, pi = line.split(",")
        yield int(k_str), int(d0), int(step), [int(v) for v in pi.split()]


@cocotb.test()
async def matches_internal_interleaver_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for K, d0, step, expected_pi in load_vectors():
        assert len(expected_pi) == K

        dut.rst.value = 1
        dut.start.value = 0
        dut.k_in.value = 0
        dut.d0.value = 0
        dut.step.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        # Latch K/d0/step.
        dut.k_in.value = K
        dut.d0.value = d0
        dut.step.value = step
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        got = []
        for i in range(K):
            await Timer(1, unit="ns")
            assert int(dut.valid.value) == 1, f"K={K} i={i}: valid low"
            got.append(int(dut.pi_o.value))
            if i == K - 1:
                assert int(dut.last.value) == 1, f"K={K}: last not set at K-1"
            await RisingEdge(dut.clk)

        assert got == expected_pi, (
            f"K={K}: QPP mismatch\n  expected {expected_pi[:8]}...\n"
            f"  actual   {got[:8]}..."
        )
        assert sorted(got) == list(range(K)), f"K={K}: not a permutation"
