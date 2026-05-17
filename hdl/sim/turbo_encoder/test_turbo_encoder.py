from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = Path(__file__).resolve().parents[2] / "vectors" / "turbo_encoder.csv"


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_str, c, c_prime, d = line.split(",")
        yield int(k_str), c, c_prime, d


async def step(dut, valid, term, c_bit, cp_bit, emit):
    """Drive one cycle; sample the combinational column before the edge."""
    dut.in_valid.value = valid
    dut.in_term.value = term
    dut.c_bit.value = c_bit
    dut.cprime_bit.value = cp_bit
    dut.emit.value = emit
    await Timer(1, unit="ns")  # let combinational outputs settle
    col = (
        int(dut.d0.value),
        int(dut.d1.value),
        int(dut.d2.value),
        int(dut.out_valid.value),
    )
    await RisingEdge(dut.clk)  # state / term buffers / counters advance
    return col


@cocotb.test()
async def matches_matlab_turbo_encoder_golden_vectors(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for K, c, c_prime, expected_d in load_vectors():
        # Reset: clear both constituent encoders and the sequencer.
        dut.rst.value = 1
        dut.in_valid.value = 0
        dut.in_term.value = 0
        dut.c_bit.value = 0
        dut.cprime_bit.value = 0
        dut.emit.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        columns = []

        # K data steps -> body columns [x; z; z'].
        for k in range(K):
            d0, d1, d2, ov = await step(dut, 1, 0, int(c[k]), int(c_prime[k]), 0)
            assert ov == 1, f"K={K} k={k}: out_valid low during data step"
            columns.append((d0, d1, d2))

        # 3 trellis-termination steps -> captured, no column emitted.
        for _ in range(3):
            _, _, _, ov = await step(dut, 1, 1, 0, 0, 0)
            assert ov == 0, f"K={K}: out_valid high during termination step"

        # 4 emit cycles -> the four trellis-termination columns.
        for e in range(4):
            d0, d1, d2, ov = await step(dut, 0, 0, 0, 0, 1)
            assert ov == 1, f"K={K} emit {e}: out_valid low"
            columns.append((d0, d1, d2))

        assert len(columns) == K + 4, f"K={K}: got {len(columns)} cols, want {K+4}"

        actual = "".join(f"{a}{b}{c2}" for a, b, c2 in columns)
        assert actual == expected_d, (
            f"K={K}: turbo-encoder output mismatch\n"
            f"  expected {expected_d[:48]}...\n"
            f"  actual   {actual[:48]}..."
        )
