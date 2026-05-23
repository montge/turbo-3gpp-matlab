# Termination-capable turbo decode-loop HDL simulation

Verifies the board-neutral `turbo_decoder_term_top` core
(`hdl/rtl/turbo_decoder_term_top.vhdl`) — the **P3** increment of the staged
decoder plan in `hdl/docs/decoder_roadmap.md`. It is a NEW entity that
copy-extends the **unmodified** P2 `turbo_decoder_top` half-iteration loop and
adds the three P3-deferred behaviours:

1. **CRC-aided early termination** — a new `crc24_check` core (CRC24A/CRC24B
   run-time select via `is_tb`) is run on the hard decision *before* the loop
   and *after* each half-iteration; decoding stops on `crc_ok`, latching
   `iterations_performed`.
2. **Filler-bit handling** — the first `F_r` systematic LLRs are forced to the
   P1 `+inf` sentinel `MAX_SENT` (= `EXT_MAX` on the exchange grid) at load, so
   they decode as strongly-known `0`. The CRC is computed on the hard decision
   *before* any filler overwrite.
3. **HARQ soft combining** — an optional saturating accumulate of up to
   `N_RETX_MAX = 4` channel-LLR matrices into a `W_HARQ = 16` buffer before
   decode.

With `crc_en = 0` (no CRC) the core degenerates to **byte-for-byte P2
behaviour** (fixed `H = round(2·max_iter)` half-iterations).

## Two-tier verification method

The decoder is checked at two levels (design.md "two-tier oracle"):

- **Inner gate (this lane, bit-exact).** The HDL output must equal, *bit-for-
  bit*, the fixed-point Octave oracles
  `scripts/fixedpoint_turbo_decoder_term.m` (decode + early-term + filler) and
  `scripts/fixedpoint_turbo_harq_accumulate.m` (HARQ soft buffer), whose joint
  output is the golden CSV. The gate asserts **two** things per frame:
    1. the `K` decoded hard bits `c` are bit-exact, **and**
    2. `iters_out` equals `iterations_performed` (early-stop determinism).
  Every loop add/quantize is a pinned saturating op and the CRC is checked at
  the SAME points (pre-loop, post-upper, post-lower) in the SAME order as the
  oracle, so the stop point is a pure function of the quantized inputs. Any
  single-bit difference, or any iteration-count difference, fails the test.
- **Outer characterization (recorded, not run here).** The stage-1 outer tier
  (`scripts/characterize_turbo_decoder_term.m`,
  `results/characterize_turbo_decoder_term.txt`) tracks BER-vs-SNR within the
  documented dB margin (the P2 oracle band, **fixed-point implementation loss
  ≤ 1.0 dB** at target BER `1e-2`), the early-stop `iterations_performed`
  distribution + CRC-pass rate, and confirms HARQ retransmission improves BER.
  This lane does not re-derive those bands; it enforces only the inner
  bit-exact tier.

## Golden vectors

`hdl/vectors/turbo_decoder_term_top.csv` — one frame per row (header line
first). The P3 columns (marked \*) extend the P2 schema:

| column                 | meaning |
|------------------------|---------|
| `case_id` \*           | short label of the special case exercised (`preloop0`/`earlystop`/`runtomax`/`filler`/`harq`/`grid`/`nocrc`). Informational; no lane semantics. |
| `K`                    | information block length (40, 64, 512). |
| `max_iter`             | iteration count (multiple of 0.5); `H = round(2·max_iter)` half-iterations. All rows `max_iter = 8`. |
| `crc_sel` \*           | CRC select for early termination: `0` = no CRC (plain P2 fixed-`H` path), `1` = CRC24A (transport-block, `C == 1`), `2` = CRC24B (code-block, `C > 1`). |
| `F_r` \*               | number of filler bits (the first `F_r` systematic positions). `0` when none. |
| `filler_pos` \*        | `F_r` 1-based filler indices (always `1..F_r`; emitted explicitly). Empty when `F_r = 0`. |
| `n_retx` \*            | number of channel-LLR transmissions stacked in `d_a`. `1` for all non-HARQ rows; `≥ 2` (`≤ N_retx_max`) for a HARQ row. |
| `d_a`                  | `n_retx · 3·(K+4)` space-separated signed ints: `n_retx` consecutive quantized channel-LLR matrices, each **column-major** (col 1 rows 1..3, col 2 rows 1..3, …), each a **W_ext=12** exchange-grid LSB code (Q7.4, range `[-2048, 2047]`). Filler positions carry `ext_max = +2047` (the `+inf`/`MAX_SENT` sentinel). |
| `iterations_performed` \* | **REQUIRED** early-stop output (a multiple of 0.5): the half-iteration index at which decoding stopped (`0` pre-loop, `iter−0.5` post-upper, `iter` post-lower), or `max_iter` if the CRC never passed / `crc_sel = 0`. The DUT exports `round(2·iters)` as a half-index on `iters_out`; the lane compares `iters_out == round(2·iterations_performed)`. |
| `c`                    | `K` hard bits (0/1) — **THE gate output**. The value **`2`** marks a FILLER position (the oracle returns `NaN` there); the DUT streams the deterministic known-`0` decode at filler positions, so the lane expects `0` where the CSV holds `2`. |
| `c_a`                  | `K` signed W_ext=12 codes: final cyclic interleaved-extrinsic state. **Diagnostic only.** |
| `c_e`                  | `K` signed W_ext=12 codes: final upper-decoder cyclic extrinsic. **Diagnostic only.** |

10 frames total exercising every P3 behaviour:

| case_id   | K   | crc_sel | F_r | n_retx | iters | what it exercises |
|-----------|-----|---------|-----|--------|-------|-------------------|
| preloop0  | 40  | 1 (24A) | 0   | 1      | 0     | pre-loop CRC pass — output is the column-major pre-loop hard decision, no half-iteration runs |
| earlystop | 512 | 2 (24B) | 0   | 1      | 1     | high-SNR early stop |
| runtomax  | 512 | 2 (24B) | 0   | 1      | 8     | low-SNR, CRC never passes → run to `max_iter` |
| filler    | 64  | 2 (24B) | 8   | 1      | 0.5   | 8 filler bits (`NaN→+inf→ext_max`), body decodes, filler outputs known 0 |
| harq      | 40  | 2 (24B) | 0   | 4      | 0.5   | 4-tx HARQ — only decodes after soft combining |
| grid×4    | 40,512 | 2 (24B) | 0 | 1   | 8/0.5/1.5/1 | plain early-term grid, mixed stop points |
| nocrc     | 40  | 0       | 0   | 1      | 8     | no CRC → degenerate P2 fixed-`H` path |

### crc_sel / HARQ / filler driving

- **crc_sel mapping.** `0 → crc_en=0` (no early term, plain P2 path);
  `1 → crc_en=1, is_tb=1` (CRC24A/TB); `2 → crc_en=1, is_tb=0` (CRC24B/CB).
  `crc_en`, `is_tb`, `f_r_in`, `harq_en` are all latched at `in_start`.
- **HARQ replay (`n_retx ≥ 2`).** `d_a` holds `n_retx` per-tx column-major
  `3·(K+4)` matrices back-to-back. The driver presents each on `da_valid`,
  drives `harq_clear = 1` on the **first beat of the first** transmission
  (resets the buffer), and holds `harq_last = 1` across the **final**
  transmission's load (the RTL samples it at the last column `lcol = K+3` to
  decide whether to decode). Between transmissions the RTL restarts the column
  counter and stays in `S_LOAD_D` (buffer retained), so the matrices are driven
  with no gap — exactly mirroring `fixedpoint_turbo_harq_accumulate.m`'s
  saturating `buffer += d` then decode-on-combined-matrix round-trip.
- **Filler compare.** Where the CSV `c` holds `2` (oracle `NaN`), the lane
  expects the DUT to stream `0`. The filler systematic LLR is the `+inf` token
  (`ext_max`), which pins the decoded bit to a deterministic known `0`, so the
  decode at those positions is identical and the bit-exact contract holds.

### HARQ W_EXT-vs-W_HARQ grid alignment

The `d_a` ports are **W_EXT (12-bit)** — the P2/CSV contract. `F_in = 4` is
**shared** between the W_EXT exchange word and the W_HARQ accumulator, so a
W_EXT-grid input code is the **same integer code** on the W_HARQ grid (W_HARQ
merely has more headroom). The vector generator quantizes each retransmission
to W_EXT before emitting, and the RTL accumulates those W_EXT codes directly
into the W_HARQ buffer (saturating), then re-saturates the combined column to
W_EXT before the de-mux — matching the oracle code-for-code. The 4× sum
(`4 × ext_max ≈ 8188`) never wraps the W_HARQ range (`±32767`), so no upstream
clamp differs from the oracle. The lane confirms this end-to-end on the 4-tx
`harq` frame.

### `iters_out` encoding

`iterations_performed` is stored in the CSV as a value (a multiple of 0.5). The
DUT exports it as a **half-index integer** `iters_out = round(2·iters)`:
pre-loop pass `= 0`, post-upper(h even) `= h+1`, post-lower(h odd) `= h+1`,
never-pass `= 2·MAX_ITERATIONS` (= `H`). The lane reconciles by comparing
`int(iters_out) == round(2 · iterations_performed)`. (Confirmed: `preloop0`
`iters_out=0`, `filler`/`harq` `iters_out=1` (=0.5), `earlystop` `iters_out=2`
(=1.0), `runtomax`/`nocrc` `iters_out=16` (=8.0).)

### Regenerate vectors

Idempotent (fixed RNG seeds → byte-identical CSV). `OCTAVE_BIN` is the Octave
CLI:

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'scripts')); \
   run('scripts/generate_hdl_turbo_decoder_term_vectors.m')"
```

## Run the lane

Same cross-platform toolchain as the other lanes (GHDL + cocotb in the repo
`.venv`). On Windows the `scripts/hdl_env.sh` shim applies the GHDL
embedded-interpreter knobs (`LIBPYTHON_LOC` / `PYGPI_PYTHON_BIN` / `PYTHONPATH` +
`.venv/Scripts`); source it (or use `scripts/run_all_hdl_lanes.sh`), then:

```
cd hdl/sim/turbo_decoder_term_top && make SIM=ghdl
```

### Per-row `max_iter` handling (elaboration-time generic)

`MAX_ITERATIONS` is a DUT **generic** (`H = 2·MAX_ITERATIONS` half-iterations),
fixed at elaboration. All current CSV rows are `max_iter = 8`; the default
`make` target (`all_groups`) builds and runs the DUT once per distinct
`max_iter` group (here just `8`), overriding `-gMAX_ITERATIONS` and exporting
`MAX_ITER`; the cocotb test decodes only the CSV rows whose `max_iter` matches
the elaborated generic. Adding a future `max_iter` row only extends the
`MAX_ITER_GROUPS` list. A single group can be run by hand, e.g.
`make MAX_ITER=8 sim`.

## Roadmap

This is the P3 termination-capable turbo decoder (CRC-aided early termination,
filler `NaN→+inf`, HARQ soft combining). The exact Log-MAP correction LUT +
inter-half extrinsic scaling (M1), sliding-window/BRAM BCJR (M2), fixed-point
width tightening (M3), RX-chain integration / de-rate-matching feeding the
decoder (P4) and the optional DE2 board demo (M4) are the explicit next
increments — see `hdl/docs/decoder_roadmap.md`.
