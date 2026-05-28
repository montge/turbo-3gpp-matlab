from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "constituent_decoder.csv"
)

# Pinned extrinsic width (design.md "Fixed-point format - pinned"; matches the
# DUT generic default W_XE). Used only to sanity-check the signed range of the
# CSV's expected values; the bit-exact compare is a plain integer compare.
W_XE = 18


def load_vectors():
    """Yield (K, x_a, z_a, x_e) per CSV row.

    Schema (hdl/vectors/constituent_decoder.csv): K, x_a, z_a, x_e where each
    of x_a/z_a/x_e is a space-separated list of K+3 signed integer codes.
    """
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_str, xa_str, za_str, xe_str = line.split(",")
        K = int(k_str)
        x_a = [int(v) for v in xa_str.split()]
        z_a = [int(v) for v in za_str.split()]
        x_e = [int(v) for v in xe_str.split()]
        assert len(x_a) == K + 3, f"K={K}: x_a has {len(x_a)} entries, want {K+3}"
        assert len(z_a) == K + 3, f"K={K}: z_a has {len(z_a)} entries, want {K+3}"
        assert len(x_e) == K + 3, f"K={K}: x_e has {len(x_e)} entries, want {K+3}"
        yield K, x_a, z_a, x_e


def s2i(handle, width):
    """Read a vector handle as a signed integer (two's complement, `width` bits)."""
    raw = int(handle.value)
    if raw >= (1 << (width - 1)):
        raw -= 1 << width
    return raw


@cocotb.test()
async def matches_fixedpoint_reference_golden_vectors(dut):
    """Inner bit-exact gate: HDL x_e must equal the fixed-point oracle CSV."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    n_frames = 0
    for K, x_a, z_a, x_e_exp in load_vectors():
        N = K + 3

        # ---- Reset.
        dut.rst.value = 1
        dut.start.value = 0
        dut.k_in.value = 0
        dut.in_valid.value = 0
        dut.x_a_in.value = 0
        dut.z_a_in.value = 0
        await RisingEdge(dut.clk)
        dut.rst.value = 0

        # ---- start: latch K (S_IDLE -> S_LOAD on this edge).
        dut.start.value = 1
        dut.k_in.value = K
        await RisingEdge(dut.clk)
        dut.start.value = 0

        # ---- Load N = K+3 (x_a, z_a) quantized codes via in_valid.
        # The DUT is in S_LOAD now and captures one (x_a,z_a) per in_valid edge.
        for k in range(N):
            dut.in_valid.value = 1
            dut.x_a_in.value = x_a[k] & ((1 << 9) - 1)
            dut.z_a_in.value = z_a[k] & ((1 << 9) - 1)
            await RisingEdge(dut.clk)
        dut.in_valid.value = 0
        dut.x_a_in.value = 0
        dut.z_a_in.value = 0

        # ---- Collect N extrinsic codes streamed under out_valid; out_last
        # marks the final word. The DUT streams the backward sweep, emitting
        # x_e(N-1) first down to x_e(0) last (out_last on the index-0 word), so
        # the captured stream is in REVERSE index order vs the forward-order
        # CSV; we un-reverse it below before the bit-exact compare.
        # Forward + backward sweeps take ~2N cycles, so poll generously before
        # declaring a hang.
        collected = []
        last_seen = False
        guard = 8 * N + 64
        for _ in range(guard):
            await Timer(1, unit="ns")  # let combinational outputs settle
            if int(dut.out_valid.value) == 1:
                collected.append(s2i(dut.x_e_out, W_XE))
                if int(dut.out_last.value) == 1:
                    last_seen = True
            await RisingEdge(dut.clk)
            if last_seen:
                break

        assert last_seen, (
            f"K={K}: out_last never asserted (collected {len(collected)} of {N})"
        )
        assert len(collected) == N, (
            f"K={K}: collected {len(collected)} extrinsics, want {N}"
        )

        # Un-reverse: stream is x_e(N-1)..x_e(0), CSV is x_e(0)..x_e(N-1).
        collected = collected[::-1]

        # ---- Bit-exact compare against the golden CSV.
        for idx, (got, exp) in enumerate(zip(collected, x_e_exp)):
            assert got == exp, (
                f"K={K}: x_e bit-exact mismatch at index {idx}: "
                f"expected {exp}, got {got}\n"
                f"  expected[:8] {x_e_exp[:8]}\n"
                f"  got[:8]      {collected[:8]}"
            )

        n_frames += 1
        dut._log.info(f"K={K}: {N} extrinsics bit-exact (frame {n_frames})")

    dut._log.info(f"all {n_frames} frames bit-exact PASS")
    assert n_frames == 27, f"expected 27 golden frames, ran {n_frames}"
