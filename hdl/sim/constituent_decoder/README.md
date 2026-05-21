# Constituent-decoder HDL simulation

Verifies the board-neutral `constituent_decoder` core
(`hdl/rtl/constituent_decoder.vhdl`) — a fixed-point Max-Log-MAP Log-BCJR
decoder for the TS36.212 §5.1.3.2 constituent code.

## Two-tier verification method

The decoder is checked at two levels (design.md §1 "two-tier oracle"):

- **Inner gate (this lane, bit-exact).** The HDL extrinsic output `x_e` must
  equal, *bit-for-bit*, the fixed-point Octave reference
  `scripts/fixedpoint_constituent_decoder.m` on identical quantized inputs.
  Max-Log-MAP uses plain `max` (exact and associative in fixed-point), so the
  only contract is identical quantization, saturation and per-step
  max-normalization — see the BIT-EXACTNESS CONTRACT block in the RTL header.
  This is an integer compare; any single-LSB difference fails the test.
- **Outer equivalence (recorded, not run here).** The fixed-point reference was
  characterized against the long-trusted float `constituent_decoder.m` within a
  pinned band (`scripts/characterize_constituent_decoder.m`, design.md
  "Equivalence band": `max |extrinsic-LLR error| ≤ 0.50`,
  `RMS ≤ 0.10` LLR). That band was pinned in P1.1–1.3; this lane does not
  re-derive it, it only enforces the inner bit-exact tier.

## Golden vectors

`hdl/vectors/constituent_decoder.csv` — one frame per row:

| column | meaning |
|--------|---------|
| `K`    | information block length (40, 512, 6144) |
| `x_a`  | `K+3` space-separated signed ints, quantized systematic a-priori LLR codes (Q4.4, `W_in=9`, range `[-256,255]`) |
| `z_a`  | `K+3` space-separated signed ints, quantized parity a-priori LLR codes |
| `x_e`  | `K+3` space-separated signed ints, expected extrinsic LLR codes (`W_xe=18`, range `[-131072,131071]`) |

Each list has `K+3` entries (the `+3` is the trellis-termination tail). The
DUT streams `x_e` in **reverse** index order (backward sweep: `x_e(K+2)` first
down to `x_e(0)` last, `out_last` on the index-0 word); the cocotb driver
un-reverses the captured stream before the forward-order CSV compare.

27 frames total: `K ∈ {40, 512, 6144}` × `SNR ∈ {0, 2, 4} dB` × 3 frames.

### Regenerate vectors

Idempotent (fixed RNG seed → byte-identical CSV). `OCTAVE_BIN` is the Octave
CLI (`run_tests.sh` honors it):

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_constituent_decoder_vectors.m')"
```

## Run the lane

Same cross-platform toolchain as the other lanes (GHDL + cocotb in the repo
`.venv`). On Windows the `scripts/hdl_env.sh` shim applies the GHDL embedded-
interpreter knobs (`LIBPYTHON_LOC` / `PYGPI_PYTHON_BIN` / `PYTHONPATH` +
`.venv/Scripts`); source it (or use `scripts/run_all_hdl_lanes.sh`), then:

```
cd hdl/sim/constituent_decoder && make SIM=ghdl
```

## Roadmap

This is the P1 constituent decoder. The turbo decode loop (interleaved
iteration, CRC/HARQ/filler handling, exact Log-MAP correction LUT,
sliding-window/BRAM, RX integration, board demo) is the explicit P2+ next
increment — see `hdl/docs/decoder_roadmap.md`.
