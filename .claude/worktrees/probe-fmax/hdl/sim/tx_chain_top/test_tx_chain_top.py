from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = Path(__file__).resolve().parents[2] / "vectors" / "tx_chain.csv"


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        K, n_ref, i_lbrm, rv, e_len, c, e = line.split(",")
        yield int(K), int(n_ref), int(i_lbrm), int(rv), int(e_len), c, e


@cocotb.test()
async def matches_tx_chain_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for K, N_ref, I_LBRM, rv, E, c, e in load_vectors():
        K_Pi = 32 * (((K + 4) + 31) // 32)

        dut.rst.value = 1
        dut.in_start.value = 0
        dut.c_in.value = 0
        dut.c_in_valid.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        dut.k_in.value = K
        dut.n_ref_in.value = N_ref
        dut.i_lbrm.value = I_LBRM
        dut.rv_in.value = rv
        dut.e_in.value = E
        dut.in_start.value = 1
        await RisingEdge(dut.clk)          # S_IDLE -> S_START (Kr latched)
        dut.in_start.value = 0
        await RisingEdge(dut.clk)          # S_START -> S_RUN (te/rm started)

        # Stream the K code bits into turbo_encode_top (via the chain).
        for j in range(K):
            dut.c_in.value = int(c[j])
            dut.c_in_valid.value = 1
            await RisingEdge(dut.clk)
        dut.c_in_valid.value = 0

        bits = []
        guard = E + 10 * K_Pi + 30000
        while len(bits) < E and guard > 0:
            await Timer(1, unit="ns")
            if int(dut.out_valid.value) == 1:
                bits.append(str(int(dut.e_bit.value)))
            await RisingEdge(dut.clk)
            guard -= 1

        assert len(bits) == E, f"K={K} rv={rv}: got {len(bits)} of {E}"
        actual = "".join(bits)
        assert actual == e, (
            f"K={K} N_ref={N_ref} LBRM={I_LBRM} rv={rv} E={E} mismatch\n"
            f"  expected {e[:48]}...\n  actual   {actual[:48]}..."
        )
