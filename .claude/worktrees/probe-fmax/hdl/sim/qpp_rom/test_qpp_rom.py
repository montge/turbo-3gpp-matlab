from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = Path(__file__).resolve().parents[2] / "vectors" / "qpp_rom.csv"


def load_rom():
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    table = {}
    for line in rows[1:]:
        k, d0, step = (int(v) for v in line.split(","))
        table[k] = (d0, step)
    return table


async def lookup(dut, K):
    dut.k_in.value = K
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    for _ in range(300):                 # scan is <= 188 cycles
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            break
    else:
        raise AssertionError(f"K={K}: rom lookup never asserted done")
    await Timer(1, unit="ns")
    return (
        int(dut.supported.value),
        int(dut.d0_o.value),
        int(dut.step_o.value),
    )


@cocotb.test()
async def qpp_rom_matches_table(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value = 1
    dut.start.value = 0
    dut.k_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    table = load_rom()

    for K, (d0, step) in table.items():
        sup, got_d0, got_step = await lookup(dut, K)
        assert sup == 1, f"K={K}: supported not set"
        assert (got_d0, got_step) == (d0, step), (
            f"K={K}: got d0={got_d0},step={got_step} want d0={d0},step={step}"
        )

    # A few unsupported sizes must report supported=0.
    for bad in (41, 100, 6143):
        sup, _, _ = await lookup(dut, bad)
        assert sup == 0, f"K={bad}: should be unsupported"
