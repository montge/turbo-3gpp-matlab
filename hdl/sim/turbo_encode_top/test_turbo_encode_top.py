from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# Reuse the turbo-encoder golden vectors: the integrated top computes
# c_prime itself (ROM + interleaver + buffer), so only K and c are driven.
VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "turbo_encoder.csv"
)


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_str, c, _c_prime, d = line.split(",")
        yield int(k_str), c, d


@cocotb.test()
async def turbo_encode_top_matches_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst.value = 1
    dut.in_start.value = 0
    dut.c_in.value = 0
    dut.c_in_valid.value = 0
    dut.k_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    for K, c, expected_d in load_vectors():
        # Clean FSM/sub-core state between cases.
        dut.rst.value = 1
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        # Begin block.
        dut.in_start.value = 1
        dut.k_in.value = K
        await RisingEdge(dut.clk)
        dut.in_start.value = 0

        # LOAD: stream exactly K code bits.
        for j in range(K):
            dut.c_in.value = int(c[j])
            dut.c_in_valid.value = 1
            await RisingEdge(dut.clk)
        dut.c_in_valid.value = 0

        # Auto-run: collect K+4 output column triples.
        cols = []
        guard = K + 300
        while len(cols) < K + 4 and guard > 0:
            await Timer(1, unit="ns")
            if int(dut.out_valid.value) == 1:
                cols.append(
                    (int(dut.d0_o.value), int(dut.d1_o.value), int(dut.d2_o.value))
                )
            await RisingEdge(dut.clk)
            guard -= 1

        assert len(cols) == K + 4, f"K={K}: got {len(cols)} cols, want {K+4}"
        actual = "".join(f"{a}{b}{c2}" for a, b, c2 in cols)
        assert actual == expected_d, (
            f"K={K}: integrated turbo-encode mismatch\n"
            f"  expected {expected_d[:48]}...\n"
            f"  actual   {actual[:48]}..."
        )
