# QPP interleaver HDL simulation

Verifies the board-neutral `qpp_interleaver` core
(`hdl/rtl/qpp_interleaver.vhdl`) bit-for-bit against the MATLAB/Octave
`internal_interleaver` (TS36.212 §5.1.3.2.3).

## Golden vectors

`hdl/vectors/internal_interleaver.csv` — one test case per row:

| column | meaning |
|--------|---------|
| `K`    | supported information block length |
| `d0`   | `(f1+f2) mod K`, derived as `pi(1)` |
| `step` | `(2*f2) mod K`, derived as the constant 2nd difference of `pi` |
| `pi`   | space-separated `K` integers = `internal_interleaver(0:K-1)` |

`d0`/`step` are derived purely from the golden `pi` (the QPP second difference
is constant `= 2*f2 mod K`), so `internal_interleaver` is the only dependency
and the constants are guaranteed consistent with the model.

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_internal_interleaver_vectors.m')"
```

`K` is taken only from `internal_interleaver`'s supported table (it errors on
unsupported sizes), so the size set cannot drift from the standard. v1 uses
`K ∈ {40, 512, 6144}` (LTE min / mid / max).

## Run the lane

Same cross-platform GHDL/cocotb flow as the other lanes:

```
cd hdl/sim/internal_interleaver && make SIM=ghdl
```

The test checks every streamed `pi(i)` against the golden vector **and**
asserts the sequence is a permutation of `0..K-1` (runtime guard mirroring the
Lean-proven bijectivity).

## Follow-on (not in this change)

The 188-entry `K → (f1,f2)` ROM (so the core derives its own constants) and an
optional DE2 demo are the explicit next follow-on; v1 supplies `d0/step`
externally, mirroring how interleave was externalized from the turbo encoder.
