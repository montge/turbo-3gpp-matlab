# Sub-block interleaver HDL simulation

Verifies `hdl/rtl/subblock_interleaver.vhdl` bit-for-bit against the
MATLAB/Octave `subblock_interleaver` (TS36.212 §5.1.4.1.1).

## Golden vectors

`hdl/vectors/subblock_interleaver.csv` — one case per row:

| column | meaning |
|--------|---------|
| `D`    | input length |
| `idx`  | sub-block index (0, 1, 2) |
| `pat`  | space-separated `K_Pi` ints = `subblock_interleaver(0:D-1, idx)`, `-1` = NaN filler |

`K_Pi = 32·⌈D/32⌉`. The core streams, per position, a `filler` flag and
(when not filler) the original `d`-index; the test checks both and that the
filler count is exactly `K_Pi − D`.

### Regenerate

```
OCTAVE_BIN=<octave-cli> octave --no-gui --quiet --eval \
  "addpath(pwd); addpath(fullfile(pwd,'octave_shims')); \
   run('scripts/generate_hdl_subblock_interleaver_vectors.m')"
```

Suite spans encoder-relevant `D ∈ {44,516,6148}`, an exact multiple of 32
(`D=64`, no filler), a non-multiple (`D=100`), indices `{0,2}`, and a `D=44
idx=1` row (indices 0 and 1 are identical per the standard).

## Run

```
cd hdl/sim/subblock_interleaver && make SIM=ghdl
```

## Design note

No divider: `R=⌈D/32⌉=(D+31)>>5`, `K_Pi=R<<5`, `N_D=K_Pi−D`; nested counters
`r0=k mod R`, `c0=⌊k/R⌋`; a local 32-entry `P` ROM. `idx 0/1`:
`pi_y=(r0<<5)+P[c0]`. `idx 2`: `+1` then one conditional subtract of `K_Pi`.

## Follow-on (not in this change)

The §5.1.4.1.2 circular buffer — bit collection, redundancy versions, LBRM,
`E`/bit selection with filler-skip — is the explicit next follow-on; this
change is the deterministic interleave-pattern stage only.
