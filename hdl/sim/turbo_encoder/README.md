# Turbo-encoder HDL simulation

Verifies the board-neutral `turbo_encoder` core (`hdl/rtl/turbo_encoder.vhdl`
+ `hdl/rtl/rsc_constituent_encoder.vhdl`) bit-for-bit against the MATLAB/Octave
golden model (`turbo_encoder.m`, TS36.212 §5.1.3.2).

## Golden vectors

`hdl/vectors/turbo_encoder.csv` — one test case per row:

| column   | meaning |
|----------|---------|
| `K`      | information block length (a supported TS36.212 size) |
| `c`      | `K` chars `0/1` — natural-order code block |
| `cprime` | `K` chars — interleaved block, `c_prime = c(pi+1)` |
| `d`      | `3*(K+4)` chars — expected `turbo_encoder(c,pi)` matrix, flattened **column-major** (for each column: row1,row2,row3) |

The column-major `d` order is exactly the order the core streams its output
column triples, so the cocotb check is a direct sequence equality. No
filler/`NaN` (v1 encodes concrete full code blocks).

### Regenerate vectors

`K` is taken only from `internal_interleaver`'s supported table (it errors on
unsupported lengths), so the size set cannot drift from the standard. v1 uses
the representative subset `K ∈ {40, 512, 6144}` (LTE min / mid / max), each
with all-zeros, all-ones, and 4 seeded-random blocks:

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_turbo_encoder_vectors.m')"
```

## Run the lane

Same cross-platform toolchain as the CRC lane (GHDL + cocotb in the repo
`.venv`). On Windows the `scripts/run_hdl_tests.sh` env applies
(`LIBPYTHON_LOC`/`PYGPI_PYTHON_BIN`/`PYTHONPATH` + `.venv/Scripts`); then:

```
cd hdl/sim/turbo_encoder && make SIM=ghdl
```

A focused constituent-encoder unit test lives in
`hdl/sim/rsc_constituent_encoder/` (faster-failing, checks the recurrence and
the 3-step trellis termination against a Python port of
`constituent_encoder.m`).

## On-board demonstration

Out of scope for this change (sim-first). A DE2 smoke would reuse the verified
core via a wrapper showing a signature of the encoded output on `HEX`/`LEDR`
(switches/keys only, no screen) — a documented follow-on, not required for
completion.
