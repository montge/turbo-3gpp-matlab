"""End-to-end (TX -> channel -> RX) bit-exact gate for the full receive chain.

`rx_chain_top` (hdl/rtl/rx_chain_top.vhdl) wires the soft de-rate-match
(`de_rate_matching_top`) straight into the UNMODIFIED `turbo_decoder_top`: it
turns a length-E stream of received channel LLRs into the K decoded hard bits.
This lane proves the full loop closes by driving each golden frame's `e_soft`
stream through the DUT and asserting the K collected hard bits equal the
REFERENCE CHAIN's `c` column bit-for-bit:

    d_a = fixedpoint_de_rate_matching(e_q, ...)   # stage-4 inner oracle
    c   = fixedpoint_turbo_decoder(d_a, pi, 8)    # P2 decoder oracle

run in sequence on the SAME W_LLR-quantized channel LLRs (golden CSV produced by
scripts/generate_hdl_rx_chain_vectors.m). Any wiring / handshake drift between
the de-rate-match column stream and the decoder load port surfaces as a hard-bit
mismatch -- the de-rate-match (stage-4 lane) and the decoder (turbo_decoder_top
lane) are each already bit-exact in isolation, so this gate isolates the
integration.

Schema (hdl/vectors/rx_chain_top.csv):
  case_id,K,N_ref,I_LBRM,rv_idx,E,F_r,max_iter,e_soft,c
    e_soft : E space-separated signed ints, received channel LLRs quantized to
             W_LLR = 8 (Q3.4), range [-128, 127]. Pulled in TX read order via
             e_req (sequential k = 0..E-1), the DUT input stream.
    c      : K space-separated hard bits (0/1) -- THE end-to-end gate output.
    max_iter: decoder iterations (H = 2*max_iter); 8 (the DUT default generic).
"""

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2] / "vectors" / "rx_chain_top.csv"
)

W_LLR = 8   # received channel LLR input word (Q3.4); matches the DUT generic.

# The golden CSV decodes at H = 2*max_iter = 16, i.e. the rx_chain_top
# MAX_ITERATIONS = 8 default the Makefile elaborates. A frame with a different
# max_iter could not be reproduced bit-exactly by this DUT.
EXPECTED_MAX_ITER = 8


def s2u(value, width):
    """Two's-complement of a signed int into an unsigned `width`-bit code."""
    return value & ((1 << width) - 1)


def load_vectors():
    """Yield (case_id, K, N_ref, I_LBRM, rv, E, F_r, max_iter, e_soft, c)."""
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        (cid, k, n_ref, i_lbrm, rv, e, f_r, mi, e_soft, c) = line.split(",")
        K = int(k)
        E = int(e)
        e_soft_v = [int(x) for x in e_soft.split()]
        c_v = [int(x) for x in c.split()]
        assert len(e_soft_v) == E, (
            f"case {cid}: e_soft has {len(e_soft_v)} entries, want E={E}"
        )
        assert len(c_v) == K, (
            f"case {cid}: c has {len(c_v)} entries, want K={K}"
        )
        yield (int(cid), K, int(n_ref), int(i_lbrm), int(rv), E,
               int(f_r), int(mi), e_soft_v, c_v)


async def run_frame(dut, K, N_ref, I_LBRM, rv, E, F_r, e_soft):
    """Drive one frame end-to-end; return the K collected decoded hard bits.

    Feed received LLRs on e_req (TX read order = sequential k), and collect the
    K hard bits the decoder streams under out_valid (c[0] first), out_last on
    the final bit. The de-rate-match prelude + the full ~4*H*K decode are both
    long but bounded; the de-rate-match raises e_req only during its accumulate,
    then the decoder runs silently before emitting out_valid.
    """
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

    # ---- in_start: latch params (S_IDLE -> S_START -> S_RUN).
    dut.in_start.value = 1
    dut.k_in.value = K
    dut.f_r_in.value = F_r
    dut.n_ref_in.value = N_ref
    dut.i_lbrm.value = I_LBRM
    dut.rv_in.value = rv
    dut.e_in.value = E
    await RisingEdge(dut.clk)
    dut.in_start.value = 0

    K_Pi = 32 * ((K + 4 + 31) // 32)
    e_idx = 0
    collected = []
    last_seen = False
    # de-rate-match (~E + 6*K_Pi) + decode (H=16 * ~5K + interleave) + margin.
    guard = 8 * (E + 6 * K_Pi) + 16 * (5 * K + 64) + 16384
    for _ in range(guard):
        await Timer(1, unit="ns")  # let combinational outputs settle

        # LLR pull: when e_req is high the chain consumes one LLR THIS cycle.
        if int(dut.e_req.value) == 1:
            code = e_soft[e_idx] if e_idx < E else 0
            dut.e_soft_in.value = s2u(code, W_LLR)
            e_idx += 1

        if int(dut.out_valid.value) == 1:
            collected.append(int(dut.c_out.value))
            if int(dut.out_last.value) == 1:
                last_seen = True

        await RisingEdge(dut.clk)
        if last_seen:
            break

    assert e_idx >= E, (
        f"K={K} E={E}: chain pulled only {e_idx} of {E} LLRs (e_req stalled)"
    )
    assert last_seen, (
        f"K={K} E={E}: out_last never asserted "
        f"(collected {len(collected)} of {K} bits)"
    )
    assert len(collected) == K, (
        f"K={K}: collected {len(collected)} hard bits, want {K}"
    )
    return collected


@cocotb.test()
async def matches_reference_chain_golden_vectors(dut):
    """HDL decoded bits c must equal the de-rate-match + decode reference chain."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    n_frames = 0
    for (cid, K, N_ref, I_LBRM, rv, E, F_r, mi, e_soft, c_exp) in load_vectors():
        assert mi == EXPECTED_MAX_ITER, (
            f"case {cid}: CSV max_iter={mi} but DUT elaborated at "
            f"MAX_ITERATIONS={EXPECTED_MAX_ITER}; regenerate the vectors or "
            f"override -gMAX_ITERATIONS"
        )
        got = await run_frame(dut, K, N_ref, I_LBRM, rv, E, F_r, e_soft)

        for idx, (g, exp) in enumerate(zip(got, c_exp)):
            assert g == exp, (
                f"case {cid} (K={K} N_ref={N_ref} LBRM={I_LBRM} rv={rv} "
                f"E={E} F_r={F_r}): decoded hard-bit mismatch at index {idx}: "
                f"expected {exp}, got {g}\n"
                f"  expected c[:24] {c_exp[:24]}\n"
                f"  got      c[:24] {got[:24]}"
            )

        n_frames += 1
        dut._log.info(
            f"case {cid}: K={K} E={E} F_r={F_r} rv={rv} I_LBRM={I_LBRM} -> "
            f"{K} decoded bits bit-exact vs reference chain (frame {n_frames})"
        )

    assert n_frames > 0, "no end-to-end golden frames ran; check the CSV path"
    dut._log.info(
        f"all {n_frames} rx_chain end-to-end frames bit-exact PASS"
    )
