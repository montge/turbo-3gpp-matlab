# Windowed constituent-decoder HDL simulation

Verifies the board-neutral `constituent_decoder` core
(`hdl/rtl/constituent_decoder.vhdl`) in its **sliding-window** mode — the M2
increment (`openspec/changes/add-fpga-decoder-sliding-window`). Same RTL entity
as the P1 lane (`hdl/sim/constituent_decoder/`); this lane elaborates it with
the windowed schedule generics.

## Windowing method

The full-block Max-Log-MAP Log-BCJR keeps the entire forward (α) metric array
(`8 × (K+3)`), which does not fit in M4K for large `K`. The windowed schedule
cuts the length-`Nr = K+3` trellis into `ceil(Nr / W)` windows of length
`W = WINDOW_LEN`:

- **α** is recomputed per window from the nearest boundary-state **checkpoint**
  (saved on the single full forward pass), so only `≈ 8 × W` α columns are
  stored at a time instead of `8 × Nr`.
- **β** runs an `L = ACQ_LEN`-step flat-init **acquisition warm-up** before each
  window's in-window emit. The terminal window uses the true terminated-state β
  init; interior windows use the flat acquisition init.
- The per-step arithmetic (max-norm, saturation, ±inf sentinel, pinned widths)
  is the SAME as the full-block P1 path — only the α/β *scheduling* changes.

`WINDOW_LEN ≥ Nr` collapses the schedule back to the full-block path, so the
windowed core is a strict **superset** of P1 (the default generics make the P1
lane bit-exact, unchanged).

## Pinned window parameters

| generic      | value | meaning |
|--------------|-------|---------|
| `WINDOW_LEN` | `64`  | sliding-window length `W` (design.md §3 prototype) |
| `ACQ_LEN`    | `48`  | β acquisition warm-up length `L` (bit-exact cell) |

`WINDOW_LEN` / `ACQ_LEN` are **elaboration-time** generics on
`constituent_decoder` (defaults `WINDOW_LEN = N_MAX = 6147`, `ACQ_LEN = 48`,
i.e. the full-block superset). This lane overrides both via GHDL `-g` in the
`Makefile` (`SIM_ARGS += -gWINDOW_LEN=64 -gACQ_LEN=48`) — the same `-g`
override pattern the P2 `turbo_decoder_top` lane uses for `MAX_ITERATIONS`. The
pinned `W = 64` / `L = 48` MUST match
`scripts/generate_hdl_constituent_decoder_sw_vectors.m` (the parameters the
golden CSV was generated at); changing one without regenerating the CSV breaks
the bit-exact contract. Override for experiments with
`make WINDOW_LEN=128 ACQ_LEN=32 sim` (no longer bit-exact to the committed CSV).

## Two-tier verification method

- **Inner gate (this lane, bit-exact).** The HDL extrinsic output `x_e` must
  equal, *bit-for-bit*, the **windowed** fixed-point Octave reference
  `scripts/fixedpoint_constituent_decoder_sw.m` (run at `W = 64`, `L = 48`) on
  identical quantized inputs. This is an integer compare; any single-LSB
  difference fails the test.
- **Outer equivalence (recorded, not run here).** The windowed reference was
  characterized against the full-block fixed-point reference and the float
  `constituent_decoder.m` within the pinned windowing-loss band
  (`scripts/characterize_constituent_decoder_sw.m`). This lane enforces only the
  inner bit-exact tier.

## Golden vectors

`hdl/vectors/constituent_decoder_sw.csv` — one frame per row. Schema is
**identical** to the P1 `constituent_decoder.csv`; the only difference is `x_e`,
which is the WINDOWED reference's extrinsic (at `W = 64`, `L = 48`):

| column | meaning |
|--------|---------|
| `K`    | information block length (40, 512, 6144) |
| `x_a`  | `K+3` space-separated signed ints, quantized systematic a-priori LLR codes (Q4.4, `W_in=9`, range `[-256,255]`) |
| `z_a`  | `K+3` space-separated signed ints, quantized parity a-priori LLR codes |
| `x_e`  | `K+3` space-separated signed ints, expected WINDOWED extrinsic LLR codes (`W_xe=18`, range `[-131072,131071]`) |

Each list has `K+3` entries (the `+3` is the trellis-termination tail). The DUT
streams `x_e` in **reverse** index order (backward sweep: `x_e(K+2)` first down
to `x_e(0)` last, `out_last` on the index-0 word); the cocotb driver un-reverses
the captured stream before the forward-order CSV compare. The windowed schedule
changes only the internal α/β scheduling — the streaming output cadence/order is
preserved.

27 frames total: `K ∈ {40, 512, 6144}` × `SNR ∈ {0, 2, 4} dB` × 3 frames.

### Regenerate vectors

Idempotent (fixed RNG seed → byte-identical CSV). `OCTAVE_BIN` is the Octave
CLI (`run_tests.sh` honors it):

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_constituent_decoder_sw_vectors.m')"
```

## Run the lane

Same cross-platform toolchain as the other lanes (GHDL + cocotb in the repo
`.venv`). On Windows the `scripts/hdl_env.sh` shim applies the GHDL embedded-
interpreter knobs; source it (or use `scripts/run_all_hdl_lanes.sh`), then:

```
cd hdl/sim/constituent_decoder_sw && make SIM=ghdl
```

Expected: `TESTS=1 PASS=1 FAIL=0`, all 27 windowed frames bit-exact.

## Fit results (M4K drop / full K = 6144 fit)

TODO (stage 5): the Quartus II 13.0sp1 fit of the full `K = 6144` windowed path
on the EP2C35F672C6 (the memory that previously did not fit) and the K = 512
M4K-count before/after delta are recorded by the parent change's stage-5 fit.
Numbers to be filled in here once that fit completes.
