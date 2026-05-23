"""Inner bit-exact gate for the iterative turbo-decode loop core.

The HDL `turbo_decoder_top` (hdl/rtl/turbo_decoder_top.vhdl) wraps the
UNMODIFIED P1 `constituent_decoder` inside the half-iteration loop algebra and
must reproduce, *bit-for-bit*, the fixed-point Octave oracle
`scripts/fixedpoint_turbo_decoder.m`. This lane drives each golden frame
through the DUT and asserts the K hard-decision bits `c` equal the CSV's `c`
column exactly. Any single-bit difference fails.

Per-frame max_iter handling
----------------------------
`MAX_ITERATIONS` is an elaboration-time generic on the DUT (H = 2*MAX_ITER
half-iterations). The golden CSV mixes two max_iter values (2 and 8), so the
lane is run once per generic value (see the Makefile `all_groups` target); each
pass exports `MAX_ITER` and this test decodes ONLY the CSV rows whose max_iter
matches the elaborated generic. Rows for other max_iter values are skipped (a
DUT built with H=16 cannot bit-exactly produce an H=4 frame, by construction).
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "turbo_decoder_top.csv"
)

# Pinned exchange width (design.md "Fixed-point format - pinned"; matches the
# DUT generic default W_EXT). d_a is loaded as W_EXT signed codes; the DUT
# requantizes per the loop algebra internally.
W_EXT = 12


def _max_iter_filter():
    """The max_iter group this elaborated DUT decodes (from the MAX_ITER env).

    The Makefile overrides -gMAX_ITERATIONS and exports MAX_ITER for the same
    value; a DUT elaborated with MAX_ITERATIONS=N can only produce frames whose
    CSV max_iter == N. Returns None to mean "decode all rows" (single-group
    fallback when run by hand without the env set, only valid if the CSV is
    single-max_iter).
    """
    raw = os.environ.get("MAX_ITER")
    return int(raw) if raw is not None else None


def load_vectors(max_iter_filter):
    """Yield (K, max_iter, d_a, c) for CSV rows matching max_iter_filter.

    Schema (hdl/vectors/turbo_decoder_top.csv): K, max_iter, d_a, c, c_a, c_e.
      d_a : 3*(K+4) space-separated signed ints, COLUMN-MAJOR (col1 rows 1..3,
            col2 rows 1..3, ...), W_EXT=12 exchange-grid LSB codes.
      c   : K space-separated hard bits (0/1) -- THE gate output.
      c_a/c_e : diagnostic only (W_EXT codes), ignored here.
    """
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        k_str, mi_str, da_str, c_str, _ca_str, _ce_str = line.split(",")
        K = int(k_str)
        max_iter = int(mi_str)
        if max_iter_filter is not None and max_iter != max_iter_filter:
            continue
        d_a = [int(v) for v in da_str.split()]
        c = [int(v) for v in c_str.split()]
        assert len(d_a) == 3 * (K + 4), (
            f"K={K}: d_a has {len(d_a)} entries, want {3 * (K + 4)}"
        )
        assert len(c) == K, f"K={K}: c has {len(c)} entries, want {K}"
        yield K, max_iter, d_a, c


def s2u(value, width):
    """Two's-complement of a signed int into an unsigned `width`-bit code."""
    return value & ((1 << width) - 1)


async def decode_frame(dut, K, d_a):
    """Drive one frame through the DUT and return the K collected hard bits."""
    N_COLS = K + 4

    # ---- Reset.
    dut.rst.value = 1
    dut.in_start.value = 0
    dut.k_in.value = 0
    dut.da_valid.value = 0
    dut.da1_in.value = 0
    dut.da2_in.value = 0
    dut.da3_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    # ---- in_start: latch K (S_IDLE -> S_LOAD_D on this edge).
    dut.in_start.value = 1
    dut.k_in.value = K
    await RisingEdge(dut.clk)
    dut.in_start.value = 0

    # ---- Load the 3x(K+4) d_a matrix as K+4 column beats on da_valid. d_a is
    # stored COLUMN-MAJOR: column j occupies d_a[3*j .. 3*j+2] = rows 1,2,3.
    for j in range(N_COLS):
        dut.da_valid.value = 1
        dut.da1_in.value = s2u(d_a[3 * j + 0], W_EXT)
        dut.da2_in.value = s2u(d_a[3 * j + 1], W_EXT)
        dut.da3_in.value = s2u(d_a[3 * j + 2], W_EXT)
        await RisingEdge(dut.clk)
    dut.da_valid.value = 0
    dut.da1_in.value = 0
    dut.da2_in.value = 0
    dut.da3_in.value = 0

    # ---- Collect K hard bits streamed under out_valid (c[0] first), out_last
    # on the final bit. Latency ~ 4*H*K cycles plus load/interleave overhead;
    # poll generously before declaring a hang.
    collected = []
    last_seen = False
    # H = 2*max_iter <= 16; per-half core run ~ 2N + interleave ~ 2K. Bound the
    # poll well above the worst case (16 halves * ~5K) + margin.
    guard = 16 * (5 * K + 64) + 4096
    for _ in range(guard):
        await Timer(1, unit="ns")  # let combinational outputs settle
        if int(dut.out_valid.value) == 1:
            collected.append(int(dut.c_out.value))
            if int(dut.out_last.value) == 1:
                last_seen = True
        await RisingEdge(dut.clk)
        if last_seen:
            break

    assert last_seen, (
        f"K={K}: out_last never asserted (collected {len(collected)} of {K})"
    )
    assert len(collected) == K, (
        f"K={K}: collected {len(collected)} hard bits, want {K}"
    )
    return collected


@cocotb.test()
async def matches_fixedpoint_reference_golden_vectors(dut):
    """HDL hard bits c must equal the fixed-point full-loop oracle CSV."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    mi_filter = _max_iter_filter()
    elaborated_h = 2 * mi_filter if mi_filter is not None else None
    dut._log.info(
        f"MAX_ITER group = {mi_filter} (H = {elaborated_h}); "
        f"decoding matching CSV rows"
    )

    n_frames = 0
    for K, max_iter, d_a, c_exp in load_vectors(mi_filter):
        collected = await decode_frame(dut, K, d_a)

        for idx, (got, exp) in enumerate(zip(collected, c_exp)):
            assert got == exp, (
                f"K={K} max_iter={max_iter}: hard-bit mismatch at index "
                f"{idx}: expected {exp}, got {got}\n"
                f"  expected c[:16] {c_exp[:16]}\n"
                f"  got      c[:16] {collected[:16]}"
            )

        n_frames += 1
        dut._log.info(
            f"K={K} max_iter={max_iter}: {K} hard bits bit-exact "
            f"(frame {n_frames})"
        )

    assert n_frames > 0, (
        f"no golden frames ran for MAX_ITER={mi_filter}; "
        f"check the CSV / MAX_ITER env"
    )
    dut._log.info(
        f"all {n_frames} frames bit-exact PASS (MAX_ITER group {mi_filter})"
    )
