import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def constituent_reference(c):
    """Bit-for-bit port of constituent_encoder.m -> (z, x), length K+3."""
    K = len(c)
    s1 = s2 = s3 = 0
    z = []
    x = []
    for k in range(K):
        s1p = (c[k] + s2 + s3) % 2
        x.append(c[k])
        z.append((s1p + s1 + s3) % 2)
        s1, s2, s3 = s1p, s1, s2
    for _ in range(3):  # trellis termination
        s1p = 0
        x.append((s2 + s3) % 2)
        z.append((s1p + s1 + s3) % 2)
        s1, s2, s3 = s1p, s1, s2
    return z, x


async def run_block(dut, c):
    dut.rst.value = 1
    dut.en.value = 0
    dut.term.value = 0
    dut.din.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    got_x, got_z = [], []
    for bit in list(c) + [None, None, None]:  # K data + 3 termination
        is_term = bit is None
        dut.en.value = 1
        dut.term.value = 1 if is_term else 0
        dut.din.value = 0 if is_term else int(bit)
        await Timer(1, unit="ns")
        got_x.append(int(dut.x_o.value))
        got_z.append(int(dut.z_o.value))
        await RisingEdge(dut.clk)

    exp_z, exp_x = constituent_reference(c)
    assert got_x == exp_x, f"x mismatch K={len(c)}: {got_x} != {exp_x}"
    assert got_z == exp_z, f"z mismatch K={len(c)}: {got_z} != {exp_z}"


@cocotb.test()
async def constituent_encoder_matches_reference(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    rng = random.Random(20260517)

    for K in (1, 2, 8, 40, 97):
        await run_block(dut, [0] * K)                       # zero-input -> zero
        await run_block(dut, [1] * K)
        for _ in range(3):
            await run_block(dut, [rng.randint(0, 1) for _ in range(K)])
