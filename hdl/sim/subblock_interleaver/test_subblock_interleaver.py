from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "subblock_interleaver.csv"
)


def load_vectors():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        d_str, idx_str, pat = line.split(",")
        yield int(d_str), int(idx_str), [int(v) for v in pat.split()]


@cocotb.test()
async def matches_subblock_interleaver_golden(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    for D, idx, pat in load_vectors():
        K_Pi = len(pat)

        dut.rst.value = 1
        dut.start.value = 0
        dut.d_in.value = 0
        dut.idx_in.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        dut.d_in.value = D
        dut.idx_in.value = idx
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0

        fillers = 0
        for k in range(K_Pi):
            await Timer(1, unit="ns")
            assert int(dut.valid.value) == 1, f"D={D} idx={idx} k={k}: valid low"
            is_fill = int(dut.filler.value)
            if pat[k] == -1:
                assert is_fill == 1, f"D={D} idx={idx} k={k}: expected filler"
                fillers += 1
            else:
                assert is_fill == 0, f"D={D} idx={idx} k={k}: unexpected filler"
                got = int(dut.idx_o.value)
                assert got == pat[k], (
                    f"D={D} idx={idx} k={k}: got {got} want {pat[k]}"
                )
            if k == K_Pi - 1:
                assert int(dut.last.value) == 1, f"D={D} idx={idx}: last unset"
            await RisingEdge(dut.clk)

        assert fillers == K_Pi - D, (
            f"D={D} idx={idx}: filler count {fillers} != {K_Pi - D}"
        )
