from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "rate_matching.csv"
)


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        D, n_ref, i_lbrm, rv, e_len, d, e = line.split(",")
        yield (int(D), int(n_ref), int(i_lbrm), int(rv), int(e_len),
               [int(x) for x in d.split()], e)


@cocotb.test()
async def matches_rate_matching_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for D, N_ref, I_LBRM, rv, E, d, e in load_vectors():
        K_Pi = 32 * ((D + 31) // 32)

        dut.rst.value = 1
        dut.in_start.value = 0
        dut.d_valid.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        dut.d_len.value = D
        dut.n_ref_in.value = N_ref
        dut.i_lbrm.value = I_LBRM
        dut.rv_in.value = rv
        dut.e_in.value = E
        dut.in_start.value = 1
        await RisingEdge(dut.clk)
        dut.in_start.value = 0

        for k in range(D):
            dut.d1_in.value = d[3 * k + 0]
            dut.d2_in.value = d[3 * k + 1]
            dut.d3_in.value = d[3 * k + 2]
            dut.d_valid.value = 1
            await RisingEdge(dut.clk)
        dut.d_valid.value = 0

        bits = []
        guard = E + 3 * K_Pi + 8192
        while len(bits) < E and guard > 0:
            await Timer(1, unit="ns")
            if int(dut.out_valid.value) == 1:
                bits.append(str(int(dut.e_bit.value)))
            await RisingEdge(dut.clk)
            guard -= 1

        assert len(bits) == E, f"D={D} rv={rv}: got {len(bits)} of {E}"
        actual = "".join(bits)
        assert actual == e, (
            f"D={D} N_ref={N_ref} LBRM={I_LBRM} rv={rv} E={E} mismatch\n"
            f"  expected {e[:48]}...\n  actual   {actual[:48]}..."
        )


@cocotb.test()
async def rejects_invalid_d_len(dut):
    # Out-of-contract: D=0 or D>DMAX(6148) -> defined safe abort.
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for dlen in (0, 7000):
        dut.rst.value = 1
        dut.in_start.value = 0
        dut.d_valid.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0
        dut.d_len.value = dlen
        dut.n_ref_in.value = 0
        dut.i_lbrm.value = 0
        dut.rv_in.value = 0
        dut.e_in.value = 400
        dut.in_start.value = 1
        await RisingEdge(dut.clk)
        dut.in_start.value = 0
        for _ in range(80):
            await Timer(1, unit="ns")
            assert int(dut.out_valid.value) == 0, f"d_len={dlen}: no output"
            await RisingEdge(dut.clk)
