from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "circular_buffer.csv"
)


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_pi, n_ref, i_lbrm, rv, e_len, v, e = line.split(",")
        vv = [int(x) for x in v.split()]
        yield (int(k_pi), int(n_ref), int(i_lbrm), int(rv),
               int(e_len), vv, e)


@cocotb.test()
async def matches_circular_buffer_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for K_Pi, N_ref, I_LBRM, rv, E, v, e in load_vectors():
        dut.rst.value = 1
        dut.start.value = 0
        dut.v_valid.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        # Latch params.
        dut.k_pi_in.value = K_Pi
        dut.n_ref_in.value = N_ref
        dut.i_lbrm.value = I_LBRM
        dut.rv_in.value = rv
        dut.e_in.value = E
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        # LOAD: K_Pi columns, column-major v (v1,v2,v3 per column).
        for k in range(K_Pi):
            for sig, raw in (
                (("v1_bit", "v1_fill"), v[3 * k + 0]),
                (("v2_bit", "v2_fill"), v[3 * k + 1]),
                (("v3_bit", "v3_fill"), v[3 * k + 2]),
            ):
                bit_name, fill_name = sig
                if raw == -1:
                    getattr(dut, bit_name).value = 0
                    getattr(dut, fill_name).value = 1
                else:
                    getattr(dut, bit_name).value = raw
                    getattr(dut, fill_name).value = 0
            dut.v_valid.value = 1
            await RisingEdge(dut.clk)
        dut.v_valid.value = 0

        # Auto-run: collect E output bits.
        bits = []
        guard = E + 3 * K_Pi + 4096
        while len(bits) < E and guard > 0:
            await Timer(1, unit="ns")
            if int(dut.out_valid.value) == 1:
                bits.append(str(int(dut.e_bit.value)))
            await RisingEdge(dut.clk)
            guard -= 1

        assert len(bits) == E, f"K_Pi={K_Pi} rv={rv}: got {len(bits)} of {E}"
        actual = "".join(bits)
        assert actual == e, (
            f"K_Pi={K_Pi} N_ref={N_ref} LBRM={I_LBRM} rv={rv} E={E} mismatch\n"
            f"  expected {e[:48]}...\n  actual   {actual[:48]}..."
        )


@cocotb.test()
async def rejects_invalid_params(dut):
    # Out-of-contract: K_Pi=0 or E=0 -> defined safe abort (no out_valid,
    # no div/mod-by-zero hang).
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for kpi, elen in ((0, 400), (64, 0)):
        dut.rst.value = 1
        dut.start.value = 0
        dut.v_valid.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0
        dut.k_pi_in.value = kpi
        dut.n_ref_in.value = 0
        dut.i_lbrm.value = 0
        dut.rv_in.value = 0
        dut.e_in.value = elen
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        for _ in range(64):
            await Timer(1, unit="ns")
            assert int(dut.out_valid.value) == 0, f"kpi={kpi} e={elen}: no output"
            await RisingEdge(dut.clk)
