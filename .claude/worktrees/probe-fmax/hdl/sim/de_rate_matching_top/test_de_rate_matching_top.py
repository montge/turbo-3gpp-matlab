"""Inner bit-exact gate for the soft de-rate-matching core.

The HDL `de_rate_matching_top` (hdl/rtl/de_rate_matching_top.vhdl) is the
RECEIVE-side soft mirror of `rate_matching_top`: it turns a length-E stream of
received channel LLRs back into the 3x(K+4) soft `d_a` matrix the turbo decoder
loads (inverse circular-buffer soft-combine + inverse subblock-interleave, with
`+inf` filler / `0` erasure). It must reproduce, *bit-for-bit*, the fixed-point
Octave oracle `scripts/fixedpoint_de_rate_matching.m` -- the same reference the
golden CSV was generated from (scripts/generate_hdl_de_rate_matching_vectors.m).

This lane drives each golden frame's `e_soft` stream through the DUT and asserts
the collected 3*(K+4) column-major `d_a` codes equal the CSV's `d_a` column
exactly (including filler = MAX_SENT = 2047 and erasure = 0). Any single-code
difference fails with a clear (case_id, index, expected/got) diagnostic.

Schema (hdl/vectors/de_rate_matching.csv):
  case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,e_soft,d_a
    e_soft : E space-separated signed ints, the received channel LLRs quantized
             to W_LLR = 8 (Q3.4), range [-128, 127] -- the DUT input stream.
             The core pulls them in TX read order via the e_req handshake; the
             order is k = 0,1,...,E-1 (the float `e(k)` index), so we feed them
             sequentially on each e_req pulse.
    d_a    : 3*(K+4) space-separated signed ints, the EXPECTED de-rate-matched
             soft matrix COLUMN-MAJOR (col1 rows 1..3, col2 rows 1..3, ...),
             each a W_EXT = 12 (Q7.4) LSB code in [-2048, 2047]. THE gate.
"""

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "de_rate_matching.csv"
)

# Pinned fixed-point widths (design.md Decision 3; match the DUT generics).
W_LLR = 8    # received channel LLR input word (Q3.4)
W_EXT = 12   # decoder load word / d_a code (Q7.4)


def s2u(value, width):
    """Two's-complement of a signed int into an unsigned `width`-bit code."""
    return value & ((1 << width) - 1)


def u2s(value, width):
    """Interpret an unsigned `width`-bit code as signed two's-complement."""
    value &= (1 << width) - 1
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value


def load_vectors():
    """Yield (case_id, K, N_ref, I_LBRM, rv, E, F_r, e_soft, d_a) per CSV row."""
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        (cid, k, n_ref, i_lbrm, rv, e, f_r, e_soft, d_a) = line.split(",")
        K = int(k)
        e_soft_v = [int(x) for x in e_soft.split()]
        d_a_v = [int(x) for x in d_a.split()]
        E = int(e)
        assert len(e_soft_v) == E, (
            f"case {cid}: e_soft has {len(e_soft_v)} entries, want E={E}"
        )
        assert len(d_a_v) == 3 * (K + 4), (
            f"case {cid}: d_a has {len(d_a_v)} entries, want {3 * (K + 4)}"
        )
        yield (int(cid), K, int(n_ref), int(i_lbrm), int(rv), E,
               int(f_r), e_soft_v, d_a_v)


async def de_rate_match_frame(dut, K, N_ref, I_LBRM, rv, E, F_r, e_soft):
    """Drive one frame through the DUT, return the collected 3*(K+4) d_a codes.

    The core pulls received LLRs in TX read order via e_req: each cycle e_req is
    high, the DUT consumes one LLR -- we advance through e_soft sequentially and
    present the next code on e_soft_in. After the soft scatter-accumulate /
    scatter / filler phases the core streams the 3x(K+4) d_a column-major on
    da_valid (each beat presenting d_a(1)/d_a(2)/d_a(3)), da_last on the last
    column. We collect them column-major to match the CSV order.
    """
    N_COLS = K + 4

    # ---- Reset.
    dut.rst.value = 1
    dut.in_start.value = 0
    dut.k_in.value = 0
    dut.f_r_in.value = 0
    dut.n_ref_in.value = 0
    dut.i_lbrm.value = 0
    dut.rv_in.value = 0
    dut.e_in.value = 0
    dut.e_soft_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    # ---- in_start: latch params (S_IDLE -> S_MAP_START).
    dut.in_start.value = 1
    dut.k_in.value = K
    dut.f_r_in.value = F_r
    dut.n_ref_in.value = N_ref
    dut.i_lbrm.value = I_LBRM
    dut.rv_in.value = rv
    dut.e_in.value = E
    await RisingEdge(dut.clk)
    dut.in_start.value = 0

    # ---- Run: feed LLRs on e_req (TX read order = sequential k), collect d_a.
    # The de-rate-match prelude (map build + soft accumulate) is long but
    # linear; bound generously (map ~K_Pi, accumulate ~few*E, scatter ~3*K_Pi,
    # output ~K+4) and well above worst case.
    K_Pi = 32 * ((K + 4 + 31) // 32)
    e_idx = 0
    collected = []
    last_seen = False
    guard = 8 * (E + 6 * K_Pi + N_COLS) + 8192
    for _ in range(guard):
        await Timer(1, unit="ns")  # let combinational outputs settle

        # LLR pull: when e_req is high the core consumes one LLR THIS cycle, so
        # present the current code and advance for the next pull.
        if int(dut.e_req.value) == 1:
            code = e_soft[e_idx] if e_idx < E else 0
            dut.e_soft_in.value = s2u(code, W_LLR)
            e_idx += 1

        if int(dut.da_valid.value) == 1:
            collected.append((
                u2s(int(dut.da1_o.value), W_EXT),
                u2s(int(dut.da2_o.value), W_EXT),
                u2s(int(dut.da3_o.value), W_EXT),
            ))
            if int(dut.da_last.value) == 1:
                last_seen = True

        await RisingEdge(dut.clk)
        if last_seen:
            break

    assert e_idx >= E, (
        f"K={K} E={E}: core pulled only {e_idx} of {E} LLRs (e_req stalled)"
    )
    assert last_seen, (
        f"K={K} E={E}: da_last never asserted "
        f"(collected {len(collected)} of {N_COLS} columns)"
    )
    assert len(collected) == N_COLS, (
        f"K={K}: collected {len(collected)} columns, want {N_COLS}"
    )
    # Flatten column-major (col j rows 1,2,3) to match the CSV d_a order.
    flat = []
    for (a1, a2, a3) in collected:
        flat.extend((a1, a2, a3))
    return flat


@cocotb.test()
async def matches_fixedpoint_reference_golden_vectors(dut):
    """HDL d_a codes must equal the fixed-point de-rate-match oracle CSV."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    n_frames = 0
    for (cid, K, N_ref, I_LBRM, rv, E, F_r, e_soft, d_a_exp) in load_vectors():
        got = await de_rate_match_frame(
            dut, K, N_ref, I_LBRM, rv, E, F_r, e_soft)

        for idx, (g, exp) in enumerate(zip(got, d_a_exp)):
            assert g == exp, (
                f"case {cid} (K={K} N_ref={N_ref} LBRM={I_LBRM} rv={rv} "
                f"E={E} F_r={F_r}): d_a mismatch at column-major index {idx} "
                f"(col {idx // 3}, row {idx % 3 + 1}): expected {exp}, got {g}\n"
                f"  expected d_a[:12] {d_a_exp[:12]}\n"
                f"  got      d_a[:12] {got[:12]}"
            )

        n_frames += 1
        dut._log.info(
            f"case {cid}: K={K} E={E} F_r={F_r} rv={rv} I_LBRM={I_LBRM} -> "
            f"{len(got)} d_a codes bit-exact (frame {n_frames})"
        )

    assert n_frames > 0, "no golden frames ran; check the CSV path"
    dut._log.info(f"all {n_frames} de-rate-match frames bit-exact PASS")
