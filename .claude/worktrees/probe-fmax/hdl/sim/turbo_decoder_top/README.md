# Turbo decode-loop HDL simulation

Verifies the board-neutral `turbo_decoder_top` core
(`hdl/rtl/turbo_decoder_top.vhdl`) — the fixed-point iterative Max-Log-MAP
turbo decoder for the LTE turbo code (TS36.212 §5.1.3.2). It wraps the
**unmodified** P1 `constituent_decoder` inside the half-iteration loop algebra,
exchanging extrinsic information through the reused `qpp_rom` + `qpp_interleaver`
across `H = round(2·max_iter)` half-iterations, then makes a hard decision over
the `K` systematic bits. This is the P2 increment of the staged decoder plan in
`hdl/docs/decoder_roadmap.md`.

## Two-tier verification method

The decoder is checked at two levels (design.md §1 "two-tier oracle"), with the
**P2 outer-layer shift from numerical equivalence to communications BER**:

- **Inner gate (this lane, bit-exact).** The HDL hard-decision output `c` must
  equal, *bit-for-bit*, the fixed-point Octave oracle
  `scripts/fixedpoint_turbo_decoder.m` on identical quantized inputs. Max-Log-MAP
  uses plain `max` (exact in fixed-point) and every loop add/quantize is a
  pinned saturating op, so the only contract is identical quantization,
  saturation, re-quantization points and half-iteration framing — see the
  BIT-EXACT CONTRACT block in the RTL header. This is an integer compare; any
  single-bit difference fails the test.
- **Outer BER band (recorded, not run here).** Unlike P1's *equivalence* check,
  the P2 outer tier is a **communications BER-vs-SNR** comparison: the
  fixed-point full-loop reference vs the float `turbo_decoder.m`, because at P2
  the loop iterates and BER is the meaningful oracle (a single constituent
  decode has no meaningful BER). The band was pinned in stage 1
  (`scripts/characterize_turbo_decoder.m`, design.md "Outer BER margin"):
  **fixed-point implementation loss ≤ 1.0 dB** (horizontal shift at target
  BER `1e-2`) over the bounded grid `K ∈ {40, 512}`,
  `SNR ∈ {−2.5,−2.0,−1.5,−1.0,−0.5} dB`. This lane does not re-derive that band;
  it only enforces the inner bit-exact tier.

## Golden vectors

`hdl/vectors/turbo_decoder_top.csv` — one frame per row (header line first):

| column     | meaning |
|------------|---------|
| `K`        | information block length (40, 512, 6144) |
| `max_iter` | iteration count (multiple of 0.5); `H = round(2·max_iter)` half-iterations (even = upper/systematic, odd = lower/interleaved). No early termination (P3). |
| `d_a`      | `3·(K+4)` space-separated signed ints, the quantized channel-LLR matrix in **column-major** order (col 1 rows 1..3, col 2 rows 1..3, …), each a **W_ext=12** exchange-grid LSB code (Q7.4, range `[-2048, 2047]`). |
| `c`        | `K` space-separated hard bits (0/1) — **THE gate output**. `c(k) = (c_a(k) + c_e(k)) < 0`. |
| `c_a`      | `K` signed ints (W_ext=12 codes): final cyclic interleaved-extrinsic state. **Diagnostic only.** |
| `c_e`      | `K` signed ints (W_ext=12 codes): final upper-decoder cyclic extrinsic. **Diagnostic only.** |

20 frames total: `K ∈ {40, 512}` × `SNR ∈ {−1.5, −0.5} dB` × `max_iter ∈ {2, 8}`
× 2 frames (16 rows), plus `K = 6144` × same SNR/`max_iter` × 1 frame (4 rows).
`max_iter = 2` gives the small-`H = 4` regression case; `max_iter = 8` is the
default `H = 16`.

### d_a is loaded at W_ext (the P2 interface contract)

The oracle (`fixedpoint_turbo_decoder.m`, step 0) quantizes the **whole**
channel-LLR matrix to the W_ext=12 exchange grid, then re-saturates each
de-muxed row internally: `ch_sys` is kept at **W_ext**, while the parity
(`z_a`/`z'_a`) and the termination triplets are re-saturated to the core input
width **W_in=9**. The CSV therefore stores `d_a` at W_ext, and the DUT's
`da1_in`/`da2_in`/`da3_in` ports are **W_ext (12-bit)** wide — the load de-mux
re-clips the parity/termination rows to W_in, and the systematic body keeps
W_ext for the `c_a + ch_sys` accumulate. (A W_in port would clip channel LLRs
that exceed the W_in range before storage and break bit-exactness; this was
fixed in the RTL — see the PR / RTL header.)

The DUT streams the inner core's extrinsic output in **reverse** index order
(backward sweep); the RTL un-reverses it in hardware (a down-counter that writes
the forward-order body memory), so the cocotb driver compares the forward-order
`c` directly with no un-reversing needed at this top level.

### Regenerate vectors

Idempotent (fixed RNG seed → byte-identical CSV). `OCTAVE_BIN` is the Octave CLI:

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'scripts')); \
   run('scripts/generate_hdl_turbo_decoder_vectors.m')"
```

## Run the lane

Same cross-platform toolchain as the other lanes (GHDL + cocotb in the repo
`.venv`). On Windows the `scripts/hdl_env.sh` shim applies the GHDL
embedded-interpreter knobs (`LIBPYTHON_LOC` / `PYGPI_PYTHON_BIN` / `PYTHONPATH` +
`.venv/Scripts`); source it (or use `scripts/run_all_hdl_lanes.sh`), then:

```
cd hdl/sim/turbo_decoder_top && make SIM=ghdl
```

### Per-row `max_iter` handling (elaboration-time generic)

`MAX_ITERATIONS` is a DUT **generic** (`H = 2·MAX_ITERATIONS` half-iterations),
fixed at elaboration. The golden CSV mixes two `max_iter` values (2 and 8), so
the lane is run **once per generic value**: the default `make` target
(`all_groups`) builds and runs the DUT twice, overriding `-gMAX_ITERATIONS` and
exporting `MAX_ITER`; the cocotb test decodes only the CSV rows whose `max_iter`
matches the elaborated generic (10 frames per group, 20 total). A single group
can be run by hand, e.g. `make MAX_ITER=8 sim`. This keeps the DUT generic
honest (a DUT built with `H = 16` cannot bit-exactly produce an `H = 4` frame)
without a runtime `max_iter` input.

## Roadmap

This is the P2 iterative turbo decode loop (fixed iteration count, no early
termination). CRC-aided early termination, HARQ accumulation, filler
`NaN→+inf`, the exact Log-MAP correction LUT + extrinsic scaling,
sliding-window/BRAM, fixed-point width tightening, RX integration and the board
demo are the explicit P3+ next increments — see `hdl/docs/decoder_roadmap.md`.
