"""Inner bit-exact gate for the termination-capable turbo-decode loop core.

The HDL ``turbo_decoder_term_top`` (hdl/rtl/turbo_decoder_term_top.vhdl) is the
P3 entity: it copy-extends the UNMODIFIED P2 ``turbo_decoder_top`` half-
iteration loop and adds CRC-aided early termination (``crc24_check``), filler-
bit handling, and HARQ soft combining. It must reproduce, *bit-for-bit*, the
fixed-point Octave oracles
  scripts/fixedpoint_turbo_decoder_term.m   (decode + early-term + filler)
  scripts/fixedpoint_turbo_harq_accumulate.m (HARQ soft buffer)
whose joint output is the golden CSV hdl/vectors/turbo_decoder_term_top.csv.

THE GATE asserts TWO things per frame:
  (1) the K decoded hard bits ``c`` are bit-exact, AND
  (2) ``iters_out`` equals the CSV ``iterations_performed`` (early-stop
      determinism).
Any single-bit difference, or any iteration-count difference, fails.

CSV schema (hdl/vectors/turbo_decoder_term_top.csv), 10 rows:
  case_id,K,max_iter,crc_sel,F_r,filler_pos,n_retx,d_a,
  iterations_performed,c,c_a,c_e

  crc_sel : 0 => crc_en=0 (no early term, plain P2 path)
            1 => crc_en=1, is_tb=1 (CRC24A / transport-block, C==1)
            2 => crc_en=1, is_tb=0 (CRC24B / code-block, C>1)
  F_r     : filler count (first F_r systematic positions). 0 = none.
  filler_pos : F_r 1-based indices (informational; filler is the first F_r).
  n_retx  : 1 = single transmission; >=2 = HARQ (d_a holds n_retx per-tx
            3*(K+4) column-major matrices; the lane drives harq_clear on the
            first beat, accumulates each, harq_last on the final tx).
  d_a     : n_retx * 3*(K+4) column-major W_EXT=12 signed codes.
  iterations_performed : a multiple of 0.5. The DUT outputs round(2*iters) as a
            half-index integer on iters_out; the lane compares
            iters_out == round(2 * iterations_performed).
  c       : K hard bits; the value 2 marks a FILLER position (the oracle writes
            NaN there). At a filler position the DUT streams the deterministic
            known-0 decode (the +inf token pins the bit), so the lane expects 0
            from the DUT where the CSV holds 2 (RTL header lines 22-26).

Per-frame max_iter handling
----------------------------
``MAX_ITERATIONS`` is an elaboration-time generic on the DUT (H = 2*MAX_ITER
half-iterations). All current CSV rows are max_iter=8; the lane is run once per
generic value (Makefile ``all_groups``), each pass exports ``MAX_ITER`` and
this test decodes ONLY the CSV rows whose max_iter matches the elaborated
generic.
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


VECTOR_PATH = (
    Path(__file__).resolve().parents[2]
    / "vectors"
    / "turbo_decoder_term_top.csv"
)

# Pinned exchange width (design.md "Fixed-point format - pinned"; matches the
# DUT generic default W_EXT). d_a is loaded as W_EXT signed codes.
W_EXT = 12

# CSV filler flag: a `c` value of 2 marks a filler position (oracle NaN). The
# DUT streams the deterministic known-0 decode there.
FILLER_FLAG = 2
FILLER_EXPECTED_BIT = 0


def _max_iter_filter():
    """The max_iter group this elaborated DUT decodes (from the MAX_ITER env)."""
    raw = os.environ.get("MAX_ITER")
    return int(raw) if raw is not None else None


def _crc_sel_to_ctrl(crc_sel):
    """Map CSV crc_sel -> (crc_en, is_tb) per the contract.

    0 => no CRC / no early term (plain P2 path)
    1 => CRC24A, transport-block  (is_tb=1)
    2 => CRC24B, code-block       (is_tb=0)
    """
    if crc_sel == 0:
        return 0, 0
    if crc_sel == 1:
        return 1, 1
    if crc_sel == 2:
        return 1, 0
    raise ValueError(f"unknown crc_sel={crc_sel}")


def load_vectors(max_iter_filter):
    """Yield one dict per CSV row matching max_iter_filter."""
    rows = VECTOR_PATH.read_text(encoding="utf-8").strip().splitlines()
    for line in rows[1:]:
        parts = line.split(",")
        (case_id, k_str, mi_str, crc_str, fr_str, fpos_str, nretx_str,
         da_str, iters_str, c_str, _ca_str, _ce_str) = parts
        K = int(k_str)
        max_iter = float(mi_str)
        if max_iter_filter is not None and int(max_iter) != max_iter_filter:
            continue
        crc_sel = int(crc_str)
        F_r = int(fr_str)
        n_retx = int(nretx_str)
        d_a = [int(v) for v in da_str.split()]
        c = [int(v) for v in c_str.split()]
        iters = float(iters_str)
        iters_half = round(2 * iters)

        assert len(d_a) == n_retx * 3 * (K + 4), (
            f"{case_id}: K={K} n_retx={n_retx}: d_a has {len(d_a)} entries, "
            f"want {n_retx * 3 * (K + 4)}"
        )
        assert len(c) == K, f"{case_id}: K={K}: c has {len(c)} entries, want {K}"

        # Split d_a into n_retx per-transmission column-major matrices.
        per = 3 * (K + 4)
        matrices = [d_a[t * per:(t + 1) * per] for t in range(n_retx)]

        yield {
            "case_id": case_id,
            "K": K,
            "max_iter": max_iter,
            "iters_half": iters_half,
            "iters": iters,
            "crc_sel": crc_sel,
            "F_r": F_r,
            "n_retx": n_retx,
            "matrices": matrices,
            "c": c,
        }


def s2u(value, width):
    """Two's-complement of a signed int into an unsigned ``width``-bit code."""
    return value & ((1 << width) - 1)


def u2s(value, width):
    """Interpret an unsigned ``width``-bit code as a signed two's-complement."""
    value &= (1 << width) - 1
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value


async def decode_frame(dut, vec):
    """Drive one frame (incl. HARQ replay) through the DUT.

    Returns (collected_bits, iters_half_out).
    """
    K = vec["K"]
    N_COLS = K + 4
    crc_en, is_tb = _crc_sel_to_ctrl(vec["crc_sel"])
    matrices = vec["matrices"]
    n_retx = vec["n_retx"]
    harq_en = 1 if n_retx >= 2 else 0

    # ---- Reset.
    dut.rst.value = 1
    dut.in_start.value = 0
    dut.k_in.value = 0
    dut.crc_en.value = 0
    dut.is_tb.value = 0
    dut.f_r_in.value = 0
    dut.harq_en.value = 0
    dut.da_valid.value = 0
    dut.da1_in.value = 0
    dut.da2_in.value = 0
    dut.da3_in.value = 0
    dut.harq_clear.value = 0
    dut.harq_last.value = 0
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    # ---- in_start: latch K, crc_en, is_tb, F_r, harq_en (S_IDLE -> S_LOAD_D).
    dut.in_start.value = 1
    dut.k_in.value = K
    dut.crc_en.value = crc_en
    dut.is_tb.value = is_tb
    dut.f_r_in.value = vec["F_r"]
    dut.harq_en.value = harq_en
    await RisingEdge(dut.clk)
    dut.in_start.value = 0
    dut.crc_en.value = 0
    dut.is_tb.value = 0
    dut.f_r_in.value = 0
    dut.harq_en.value = 0

    # ---- Load each transmission's 3x(K+4) matrix as K+4 column beats.
    #
    # Single-transmission (n_retx==1, harq_en=0): one matrix loaded straight
    # through (P2 path); harq_clear/harq_last are don't-care but driven 0.
    #
    # HARQ (n_retx>=2, harq_en=1): present each retransmission's matrix on
    # da_valid; harq_clear='1' on the FIRST beat of the FIRST transmission
    # (resets the buffer), harq_last='1' across the load of the FINAL
    # retransmission (RTL samples it at the last column, lcol==K+3). Between
    # retransmissions the RTL restarts the column counter and stays in S_LOAD_D
    # (buffer retained), so the lane drives consecutive matrices with no gap.
    for t, mat in enumerate(matrices):
        is_last_tx = (t == n_retx - 1)
        for j in range(N_COLS):
            dut.da_valid.value = 1
            dut.da1_in.value = s2u(mat[3 * j + 0], W_EXT)
            dut.da2_in.value = s2u(mat[3 * j + 1], W_EXT)
            dut.da3_in.value = s2u(mat[3 * j + 2], W_EXT)
            # harq_clear: only on the very first beat of the first transmission.
            dut.harq_clear.value = 1 if (harq_en and t == 0 and j == 0) else 0
            # harq_last: held high across the final transmission's load (the RTL
            # samples it at lcol==K+3 to decide whether to decode).
            dut.harq_last.value = 1 if (harq_en and is_last_tx) else 0
            await RisingEdge(dut.clk)
    dut.da_valid.value = 0
    dut.da1_in.value = 0
    dut.da2_in.value = 0
    dut.da3_in.value = 0
    dut.harq_clear.value = 0
    dut.harq_last.value = 0

    # ---- Collect K hard bits streamed under out_valid (c[0] first), out_last
    # on the final bit, and latch iters_out. Latency ~ 4*H*K cycles plus load/
    # interleave/CRC overhead; poll generously before declaring a hang.
    collected = []
    iters_half_out = None
    last_seen = False
    # H = 2*max_iter <= 16; per-half core run ~ 2N + interleave + CRC ~ 3K.
    # Bound the poll well above the worst case + margin.
    guard = 16 * (6 * K + 128) + 8192
    for _ in range(guard):
        await Timer(1, unit="ns")  # let combinational outputs settle
        if int(dut.out_valid.value) == 1:
            collected.append(int(dut.c_out.value))
            if int(dut.out_last.value) == 1:
                last_seen = True
                iters_half_out = int(dut.iters_out.value)
        await RisingEdge(dut.clk)
        if last_seen:
            break

    assert last_seen, (
        f"{vec['case_id']} K={K}: out_last never asserted "
        f"(collected {len(collected)} of {K})"
    )
    assert len(collected) == K, (
        f"{vec['case_id']} K={K}: collected {len(collected)} hard bits, want {K}"
    )
    return collected, iters_half_out


def _expected_bit(csv_bit):
    """CSV c value -> the bit the DUT is expected to stream.

    A filler position is flagged 2 in the CSV (oracle NaN); the DUT streams the
    deterministic known-0 decode there (RTL header lines 22-26).
    """
    if csv_bit == FILLER_FLAG:
        return FILLER_EXPECTED_BIT
    return csv_bit


@cocotb.test()
async def matches_fixedpoint_reference_golden_vectors(dut):
    """HDL hard bits c AND iters_out must equal the fixed-point oracle CSV."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    mi_filter = _max_iter_filter()
    elaborated_h = 2 * mi_filter if mi_filter is not None else None
    dut._log.info(
        f"MAX_ITER group = {mi_filter} (H = {elaborated_h}); "
        f"decoding matching CSV rows"
    )

    n_frames = 0
    for vec in load_vectors(mi_filter):
        K = vec["K"]
        case_id = vec["case_id"]
        collected, iters_half_out = await decode_frame(dut, vec)

        # ---- GATE part 1: K decoded hard bits bit-exact.
        for idx, (got, csv_bit) in enumerate(zip(collected, vec["c"])):
            exp = _expected_bit(csv_bit)
            note = " (filler)" if csv_bit == FILLER_FLAG else ""
            assert got == exp, (
                f"{case_id} K={K} crc_sel={vec['crc_sel']} "
                f"F_r={vec['F_r']} n_retx={vec['n_retx']}: hard-bit mismatch "
                f"at index {idx}{note}: expected {exp}, got {got}\n"
                f"  expected c[:16] "
                f"{[_expected_bit(b) for b in vec['c'][:16]]}\n"
                f"  got      c[:16] {collected[:16]}"
            )

        # ---- GATE part 2: iters_out == round(2 * iterations_performed).
        assert iters_half_out == vec["iters_half"], (
            f"{case_id} K={K} crc_sel={vec['crc_sel']}: "
            f"iterations mismatch: expected iters_out="
            f"{vec['iters_half']} (= round(2*{vec['iters']})), "
            f"got {iters_half_out} (= {iters_half_out / 2.0} iters)"
        )

        n_frames += 1
        dut._log.info(
            f"{case_id} K={K} crc_sel={vec['crc_sel']} F_r={vec['F_r']} "
            f"n_retx={vec['n_retx']}: {K} hard bits bit-exact AND "
            f"iters_out={iters_half_out} (={vec['iters']}) match "
            f"(frame {n_frames})"
        )

    assert n_frames > 0, (
        f"no golden frames ran for MAX_ITER={mi_filter}; "
        f"check the CSV / MAX_ITER env"
    )
    dut._log.info(
        f"all {n_frames} frames bit-exact PASS (bits + iterations); "
        f"MAX_ITER group {mi_filter}"
    )
